extends SceneTree
## Turns a raw 64-byte surfel blob into a SplatCloud resource, so a scene can reference it.
##
##   godot --headless --path . --script res://addons/pixel_art_splats/editor/convert_bytes.gd \
##         -- res://path/to/cloud.bytes res://path/to/cloud.res 0.0215
##
## The blob layout is the same one the Unity package writes, so a scene baked there opens here
## unchanged.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <source.bytes> [target.res] [spacing]")
		quit(1)
		return

	var src: String = args[0]
	var dst: String = args[1] if args.size() > 1 else src.get_basename() + ".res"
	var spacing: float = float(args[2]) if args.size() > 2 else 0.0

	var cloud := SplatImporter.from_bytes(src)
	if cloud == null:
		push_error("cannot read " + src)
		quit(1)
		return
	cloud.spacing = spacing
	cloud.source = src

	# compressed: a cloud is mostly float noise, so zstd takes about 40% off and costs a few ms to load
	var err := ResourceSaver.save(cloud, dst, ResourceSaver.FLAG_COMPRESS)
	print("saved %s: %d surfels (%d solid), spacing %.4f, error %d" % [dst, cloud.count, cloud.opaque_count, spacing, err])
	quit(0 if err == OK else 1)
