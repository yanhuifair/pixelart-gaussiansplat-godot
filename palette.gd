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
