@tool
class_name SplatCloud
extends Resource
## A baked cloud of surfels: 64 bytes each, opaque ones first, then translucent light.
##
## Layout per surfel (little endian, no padding):
##   pos     3 x float32   at  0
##   axis1   3 x float32   at 12   the two wide axes; their length is the radius
##   axis2   3 x float32   at 24
##   normal  3 x float32   at 36   the thin axis
##   colour  3 x float32   at 48   display space
##   flags   uint32        at 60   see [constant SplatFlags]

const STRIDE := 64

## Emissive: the colour is its own light.
const F_EMISSIVE := 1
## Visible from behind (leaves, flowers, strokes).
const F_TWO_SIDED := 2
## Translucent light: halo, beam, smoke. Drawn blended, no depth write.
const F_GLOW := 4
## The colour already holds its light (a baked scene). Only fog is added.
const F_BAKED := 8
## Lit as if it faced up (grass blades, leaflets).
const F_UP_NORMAL := 16
## Swayed by the wind on the GPU (grass blades).
const F_SWAY := 32

@export_multiline var source: String = ""
@export var data: PackedByteArray = PackedByteArray()
@export var count: int = 0
@export var spacing: float = 0.02
## How many leading surfels are opaque. The rest are translucent light.
@export var opaque_count: int = 0


static func from_bytes(path: String) -> SplatCloud:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SplatCloud: cannot open %s" % path)
		return null
	var cloud := SplatCloud.new()
	cloud.data = file.get_buffer(file.get_length())
	cloud.count = cloud.data.size() / STRIDE
	cloud.source = path
	return cloud


func has_data() -> bool:
	return data.size() >= STRIDE and count > 0


## Splits the cloud into two MultiMesh buffers: solid, then translucent light.
## Each instance is 12 floats of transform, 4 of colour, 4 of custom data (flags).
func build_buffers() -> Dictionary:
	var n := mini(count, data.size() / STRIDE)
	if n == 0:
		return {"solid": PackedFloat32Array(), "solid_count": 0, "glow": PackedFloat32Array(), "glow_count": 0}

	var floats := data.slice(0, n * STRIDE).to_float32_array()
	var split := clampi(opaque_count, 0, n)

	var buf := PackedFloat32Array()
	buf.resize(n * 20)
	for i in n:
		var f := i * 16
		var o := i * 20
		# rows of the 3x4 transform: the basis columns are axis1, axis2 and the normal
		buf[o + 0] = floats[f + 3]   # axis1.x
		buf[o + 1] = floats[f + 6]   # axis2.x
		buf[o + 2] = floats[f + 9]   # normal.x
		buf[o + 3] = floats[f + 0]   # pos.x
		buf[o + 4] = floats[f + 4]   # axis1.y
		buf[o + 5] = floats[f + 7]   # axis2.y
		buf[o + 6] = floats[f + 10]  # normal.y
		buf[o + 7] = floats[f + 1]   # pos.y
		buf[o + 8] = floats[f + 5]   # axis1.z
		buf[o + 9] = floats[f + 8]   # axis2.z
		buf[o + 10] = floats[f + 11] # normal.z
		buf[o + 11] = floats[f + 2]  # pos.z
		buf[o + 12] = floats[f + 12] # colour.r
		buf[o + 13] = floats[f + 13] # colour.g
		buf[o + 14] = floats[f + 14] # colour.b
		buf[o + 15] = float((data.decode_u32(i * STRIDE + 60) >> 8) & 0xFF) / 255.0
		buf[o + 16] = float(data.decode_u32(i * STRIDE + 60) & 0xFF)
		buf[o + 17] = 0.0
		buf[o + 18] = 0.0
		buf[o + 19] = 0.0

	return {
		"solid": buf.slice(0, split * 20),
		"solid_count": split,
		"glow": buf.slice(split * 20),
		"glow_count": n - split,
	}


## How many leading surfels are solid: the first translucent one ends the run.
func detect_opaque_count() -> int:
	for i in mini(count, data.size() / STRIDE):
		if (data.decode_u32(i * STRIDE + 60) & F_GLOW) != 0:
			return i
	return mini(count, data.size() / STRIDE)


## Bounding box of the cloud, in the cloud's own space.
func compute_aabb() -> AABB:
	var n := mini(count, data.size() / STRIDE)
	if n == 0:
		return AABB()
	var floats := data.slice(0, n * STRIDE).to_float32_array()
	var box := AABB(Vector3(floats[0], floats[1], floats[2]), Vector3.ZERO)
	for i in n:
		var f := i * 16
		box = box.expand(Vector3(floats[f], floats[f + 1], floats[f + 2]))
	return box
