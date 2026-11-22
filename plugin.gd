@tool
extends EditorPlugin
## Tools for making and importing splat clouds (Project > Tools > Pixel Art Splats), plus the look
## panel in a dock, because the overlay only exists while the game runs.

const CONVERT := "Pixel Art Splats: convert .bytes to SplatCloud…"
const BAKE := "Pixel Art Splats: bake selected meshes to SplatCloud…"

var _hud: PixelArtHud


func _enter_tree() -> void:
	add_tool_menu_item(CONVERT, _convert_bytes)
	add_tool_menu_item(BAKE, _bake_selected)

	_hud = PixelArtHud.new()
	_hud.name = "Pixel Art Splats"
	_hud.docked = true
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _hud)
	_bind_hud()


func _exit_tree() -> void:
	remove_tool_menu_item(CONVERT)
	remove_tool_menu_item(BAKE)
	if _hud != null:
		remove_control_from_docks(_hud)
		_hud.queue_free()
		_hud = null


func _handles(object: Object) -> bool:
	return object is Node


func _edit(object: Object) -> void:
	_bind_hud()


func _bind_hud() -> void:
	if _hud == null:
		return
	var root := EditorInterface.get_edited_scene_root()
	var view: PixelArtView = null
	if root != null:
		for node in EditorInterface.get_selection().get_selected_nodes():
			if node is PixelArtView:
				view = node
				break
		if view == null:
			view = _find_view(root)
	_hud.bind(view)


func _convert_bytes() -> void:
	var source := ""
	for path in EditorInterface.get_selected_paths():
		if path.get_extension().to_lower() == "bytes":
			source = path
			break
	if source.is_empty():
		_alert("Select a .bytes file in the FileSystem dock first.\n\nIt must hold 64-byte surfels, the "
			+ "layout the Unity package writes: pos, two axes, normal, colour, flags.")
		return

	var cloud := SplatImporter.from_bytes(source)
	if cloud == null:
		_alert("Could not read " + source)
		return
	cloud.source = source
	var target := source.get_basename() + ".res"
	var err := ResourceSaver.save(cloud, target, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_alert("Could not write %s (error %d)" % [target, err])
		return
	EditorInterface.get_resource_filesystem().scan()
	print("Pixel art splats: %s -> %s, %d surfels" % [source, target, cloud.count])


func _bake_selected() -> void:
	var meshes: Array[MeshInstance3D] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MeshInstance3D:
			meshes.append(node)
	if meshes.is_empty():
		_alert("Select one or more MeshInstance3D nodes in the scene first.")
		return

	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return

	var cloud := SplatImporter.from_mesh(meshes, Transform3D.IDENTITY, 120000)
	if cloud == null:
		return

	var target := root.scene_file_path.get_base_dir().path_join(meshes[0].name + "_splats.res") if not root.scene_file_path.is_empty() else "res://%s_splats.res" % meshes[0].name
	var err := ResourceSaver.save(cloud, target, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_alert("Could not write %s (error %d)" % [target, err])
		return

	var holder := SplatCloudNode.new()
	holder.name = meshes[0].name + "Splats"
	holder.cloud = load(target)
	root.add_child(holder)
	holder.owner = root
	EditorInterface.get_resource_filesystem().scan()
	print("Pixel art splats: baked %d surfels into %s" % [cloud.count, target])


func _alert(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = message
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _find_view(root: Node) -> PixelArtView:
	if root is PixelArtView:
		return root
	for child in root.get_children():
		var found := _find_view(child)
		if found != null:
			return found
	return null
