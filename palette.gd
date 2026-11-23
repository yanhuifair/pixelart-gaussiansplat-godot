@tool
class_name PixelArtPalette
extends Resource
## The colours the picture is allowed to use, plus the background it is drawn on.
##
## Hex strings, in display space, the way the browser sources list them.

## Surface colours. The background must be one of them: the pixel pass never puts the background
## on the object.
@export var surface: PackedStringArray = PackedStringArray([
	"#0a0a18", "#17152c", "#2b2740", "#4c4a60", "#807e92", "#4a2a26",
	"#1f4a38", "#4f9a4a", "#a8d860", "#c8372d", "#ffcf5a", "#fff1c0",
])

## Extra colours only translucent light (beams, halos, smoke) may take.
@export var glow: PackedStringArray = PackedStringArray(["#4e3f3a", "#8a7356"])

## Hex, display space. Should appear in [member surface].
@export var background: String = "#0a0a18"

## Brightness levels a surface can take: the light is worked out per splat, so one albedo becomes
## several palette entries. Same numbers as the shader's ambient floor and ceiling.
const AMBIENT_LOW := 0.36
const AMBIENT_HIGH := 0.58
const DIFFUSE := 0.62


## A palette for a cloud that did not come with one, the way the viewer does it for models:
## k-means over the surface colours at the brightness levels the lighting will produce.
## `lit` is the colour of a lamp in the scene, so its warm tones get entries of their own.
##
## The Unity package has the same function with the same constants: the two must agree colour for
## colour, or the same model comes out differently in each engine.
static func extract(colours: PackedColorArray, k: int, exposure := 1.0, lit := Color(0, 0, 0),
		budget := 9000) -> PackedStringArray:
	k = clampi(k, 2, 64)
	if colours.is_empty():
		return PackedStringArray()

	var step := maxi(1, colours.size() / budget)
	var levels := [AMBIENT_LOW, 0.55, 0.85, AMBIENT_HIGH + DIFFUSE]
	var has_lit := lit.r + lit.g + lit.b > 0.001

	# samples, three doubles each: every colour under four brightnesses, plus the lamp's tint
	var s := PackedFloat64Array()
	var i := 0
	while i < colours.size():
		var c := colours[i]
		var r := float(c.r)
		var g := float(c.g)
		var b := float(c.b)
		for level in levels:
			s.append(minf(1.0, r * level * exposure))
			s.append(minf(1.0, g * level * exposure))
			s.append(minf(1.0, b * level * exposure))
		if has_lit and i % (step * 3) == 0:
			s.append(minf(1.0, r * 0.7 * exposure + (r * 0.85 + 0.1) * float(lit.r) * 0.45))
			s.append(minf(1.0, g * 0.7 * exposure + (g * 0.85 + 0.1) * float(lit.g) * 0.45))
			s.append(minf(1.0, b * 0.7 * exposure + (b * 0.85 + 0.1) * float(lit.b) * 0.45))
		i += step

	var n := s.size() / 3
	if n == 0:
		return PackedStringArray()

	# initial centres: a brightness histogram, so the k spots are quantiles of the samples
	const BINS := 2048
	var weight := PackedFloat64Array()
	var sum_r := PackedFloat64Array()
	var sum_g := PackedFloat64Array()
	var sum_b := PackedFloat64Array()
	weight.resize(BINS)
	sum_r.resize(BINS)
	sum_g.resize(BINS)
	sum_b.resize(BINS)
	for j in n:
		var r := s[j * 3]
		var g := s[j * 3 + 1]
		var b := s[j * 3 + 2]
		var bin := clampi(int((r + g * 2.0 + b) * 0.25 * 2047.0), 0, BINS - 1)
		weight[bin] += 1.0
		sum_r[bin] += r
		sum_g[bin] += g
		sum_b[bin] += b

	var centres := PackedFloat64Array()
	centres.resize(k * 3)
	var seen := 0.0
	var bin_at := 0
	for c in k:
		var target := (c + 0.5) / k * n
		while bin_at < BINS - 1 and seen + weight[bin_at] < target:
			seen += weight[bin_at]
			bin_at += 1
		if weight[bin_at] > 0.0:
			var w := weight[bin_at]
			centres[c * 3] = sum_r[bin_at] / w
			centres[c * 3 + 1] = sum_g[bin_at] / w
			centres[c * 3 + 2] = sum_b[bin_at] / w
		else:
			centres[c * 3] = 0.5
			centres[c * 3 + 1] = 0.5
			centres[c * 3 + 2] = 0.5

	# Lloyd's algorithm: each sample joins the nearest centre, each centre takes the mean
	var acc := PackedFloat64Array()
	var count := PackedInt32Array()
	acc.resize(k * 3)
	count.resize(k)
	for _pass in 10:
		acc.fill(0.0)
		count.fill(0)
		for j in n:
			var r := s[j * 3]
			var g := s[j * 3 + 1]
			var b := s[j * 3 + 2]
			var best := 0
			var best_d := 1e30
			for c in k:
				var dr := r - centres[c * 3]
				var dg := g - centres[c * 3 + 1]
				var db := b - centres[c * 3 + 2]
				var d := dr * dr + dg * dg + db * db
				if d < best_d:
					best_d = d
					best = c
			acc[best * 3] += r
			acc[best * 3 + 1] += g
			acc[best * 3 + 2] += b
			count[best] += 1
		for c in k:
			if count[c] == 0:
				continue
			var w := float(count[c])
			centres[c * 3] = acc[c * 3] / w
			centres[c * 3 + 1] = acc[c * 3 + 1] / w
			centres[c * 3 + 2] = acc[c * 3 + 2] / w

	# round half up, like the viewer's Math.round
	var out := PackedStringArray()
	var seen_hex := {}
	for c in k:
		var hex := "#%02x%02x%02x" % [
			int(floor(clampf(centres[c * 3], 0.0, 1.0) * 255.0 + 0.5)),
			int(floor(clampf(centres[c * 3 + 1], 0.0, 1.0) * 255.0 + 0.5)),
			int(floor(clampf(centres[c * 3 + 2], 0.0, 1.0) * 255.0 + 0.5)),
		]
		if not seen_hex.has(hex):
			seen_hex[hex] = true
			out.append(hex)
	return out

## Surface colours then glow colours, deduplicated, padded to 64 entries for the shader.
func shader_palette() -> Dictionary:
	var flat: Array[Color] = []
	for hex in surface:
		var c := _hex(hex)
		if c.a > 0.0 and not flat.has(c):
			flat.append(c)
	var surface_count := flat.size()
	for hex in glow:
		var c := _hex(hex)
		if c.a > 0.0 and not flat.has(c):
			flat.append(c)
	var palette_count := flat.size()

	var out := PackedVector3Array()
	out.resize(64)
	for i in 64:
		var c: Color = flat[i] if i < flat.size() else Color.BLACK
		out[i] = Vector3(c.r, c.g, c.b)

	var bg := _hex(background)
	return {
		"palette": out,
		"surface_count": surface_count,
		"palette_count": palette_count,
		"background": Vector3(bg.r, bg.g, bg.b),
	}


func background_color() -> Color:
	var c := _hex(background)
	return Color(c.r, c.g, c.b, 1.0)


static func _hex(hex: String) -> Color:
	if hex.is_empty():
		return Color(0, 0, 0, 0)
	if not hex.begins_with("#"):
		hex = "#" + hex
	return Color.from_string(hex, Color(0, 0, 0, 0))
