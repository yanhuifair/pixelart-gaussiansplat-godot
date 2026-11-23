class_name PixelArtRig
extends RefCounted
## A skeleton and its animation clips, read from the `.rig` file that tools/rig_to_json.py writes.
##
## The bones are already in the splats' space: the converter recentres a model and scales its longest
## side to two units, and the rig is put through the same transform. So a bone's skinning matrix is
## just `world(t) * inverse_bind`, the usual formula, and no extra offset is needed here.
##
## Linear blend skinning is what the shader does; the browser uses dual quaternions. With four
## weights per splat the difference shows on hard twists, not on a walk cycle.

## One entry per bone: "parent" (index or -1), "rest" (t, r, s), "ibm" (Transform3D).
var bones: Array = []
## name -> Array of {bone, path ("t"/"r"/"s"), times: PackedFloat32Array, values: Array}
var clips: Dictionary = {}
var bone_count := 0

## Parents before children, so one pass is enough to build the world matrices.
var _order := PackedInt32Array()


static func load_file(path: String) -> PixelArtRig:
	if not FileAccess.file_exists(path):
		push_error("PixelArtRig: no such file %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("PixelArtRig: %s is not a rig" % path)
		return null
	var rig := PixelArtRig.new()
	rig._read(parsed)
	return rig


func _read(data: Dictionary) -> void:
	bones.clear()
	for entry in data.get("bones", []):
		var rest: Dictionary = entry.get("rest", {})
		var t: Array = rest.get("t", [0, 0, 0])
		var r: Array = rest.get("r", [0, 0, 0, 1])
		var s: Array = rest.get("s", [1, 1, 1])
		var m: Array = entry.get("ibm", [])
		var ibm := Transform3D(
			Basis(Vector3(m[0], m[4], m[8]), Vector3(m[1], m[5], m[9]), Vector3(m[2], m[6], m[10])),
			Vector3(m[3], m[7], m[11]))
		bones.append({
			"parent": int(entry.get("parent", -1)),
			"rest": {"t": Vector3(t[0], t[1], t[2]),
					 "r": Quaternion(r[0], r[1], r[2], r[3]),
					 "s": Vector3(s[0], s[1], s[2])},
			"ibm": ibm,
		})
	bone_count = bones.size()

	clips.clear()
	for clip in data.get("clips", []):
		var tracks: Array = []
		for track in clip.get("tracks", []):
			tracks.append({
				"bone": int(track.get("bone", 0)),
				"path": String(track.get("path", "t")),
				"times": PackedFloat32Array(track.get("times", [])),
				"values": track.get("values", []),
			})
		clips[String(clip.get("name", ""))] = tracks

	# everybody before their children
	_order.resize(bone_count)
	var at := 0
	var placed := {}
	for _pass in bone_count:
		for i in bone_count:
			if placed.has(i):
				continue
			var p: int = bones[i]["parent"]
			if p < 0 or placed.has(p):
				placed[i] = true
				_order[at] = i
				at += 1
		if at == bone_count:
			break


func clip_names() -> PackedStringArray:
	return PackedStringArray(clips.keys())


func duration(clip: String) -> float:
	if not clips.has(clip):
		return 0.0
	var longest := 0.0
	for track in clips[clip]:
		var times: PackedFloat32Array = track["times"]
		if times.size() > 0:
			longest = maxf(longest, times[times.size() - 1])
	return longest


## Bone matrices for a pose, sixteen floats each, column major — what the shader's texture holds.
func pose(clip: String, time: float) -> PackedFloat32Array:
	var local: Array[Transform3D] = []
	local.resize(bone_count)
	for i in bone_count:
		var rest: Dictionary = bones[i]["rest"]
		local[i] = Transform3D(Basis(rest["r"]) * Basis.from_scale(rest["s"]), rest["t"])

	if clips.has(clip):
		for track in clips[clip]:
			var bone: int = track["bone"]
			if bone < 0 or bone >= bone_count:
				continue
			var basis := local[bone].basis
			var origin := local[bone].origin
			var path: String = track["path"]
			var v: Variant = _sample(track["times"], track["values"], time, path)
			if v == null:
				continue
			if path == "r":
				var scale := basis.get_scale()
				basis = Basis(v as Quaternion) * Basis.from_scale(scale)
			elif path == "t":
				origin = v as Vector3
			else:
				var rot := basis.get_rotation_quaternion()
				basis = Basis(rot) * Basis.from_scale(v as Vector3)
			local[bone] = Transform3D(basis, origin)

	var world: Array[Transform3D] = []
	world.resize(bone_count)
	var out := PackedFloat32Array()
	out.resize(bone_count * 16)
	for i in _order:
		var m: Transform3D = local[i]
		var p: int = bones[i]["parent"]
		if p >= 0 and p < bone_count:
			m = world[p] * m
		world[i] = m
		var skin: Transform3D = m * (bones[i]["ibm"] as Transform3D)
		# columns, so the shader's mat4(c0, c1, c2, c3) needs no transpose
		var o := i * 16
		out[o + 0] = skin.basis.x.x
		out[o + 1] = skin.basis.x.y
		out[o + 2] = skin.basis.x.z
		out[o + 3] = 0.0
		out[o + 4] = skin.basis.y.x
		out[o + 5] = skin.basis.y.y
		out[o + 6] = skin.basis.y.z
		out[o + 7] = 0.0
		out[o + 8] = skin.basis.z.x
		out[o + 9] = skin.basis.z.y
		out[o + 10] = skin.basis.z.z
		out[o + 11] = 0.0
		out[o + 12] = skin.origin.x
		out[o + 13] = skin.origin.y
		out[o + 14] = skin.origin.z
		out[o + 15] = 1.0
	return out


func _sample(times: PackedFloat32Array, values: Array, t: float, path: String) -> Variant:
	var n := times.size()
	if n == 0:
		return null
	var width := 4 if path == "r" else 3
	var at := func(i: int) -> Variant:
		if path == "r":
			return Quaternion(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3])
		return Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2])

	if t <= times[0]:
		return at.call(0)
	if t >= times[n - 1]:
		return at.call(n - 1)

	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if times[mid] <= t:
			lo = mid
		else:
			hi = mid
	var span := times[hi] - times[lo]
	var f := 0.0 if span <= 0.00001 else (t - times[lo]) / span
	var a: Variant = at.call(lo)
	var b: Variant = at.call(hi)
	if path == "r":
		return (a as Quaternion).slerp(b as Quaternion, f)
	return (a as Vector3).lerp(b as Vector3, f)
