@tool
class_name SplatCloudNode
extends Node3D
## Draws one [SplatCloud] as two MultiMeshes: solid surfels, then translucent light.
##
## The pixel resolution, the falloff and the clock are pushed in by [PixelArtView], because the
## size of the buffer being drawn into depends on the window and the pixel size.

const SOLID_SHADER := preload("res://addons/pixel_art_splats/shaders/splat.gdshader")
const GLOW_SHADER := preload("res://addons/pixel_art_splats/shaders/splat_glow.gdshader")

const GROUP := "pixel_art_splats"

@export var cloud: SplatCloud:
	set(value):
		cloud = value
		if is_inside_tree():
			rebuild()

@export_group("Live light")
## Only affects splats that are not baked (imported meshes, mostly).
@export_range(0.5, 2.5, 0.05) var exposure := 1.0
## Flat light steps for cel shading on live-lit splats. 0 = smooth.
@export_range(0, 8) var bands := 5
@export_group("Rig")
## A .rig file (tools/rig_to_json.py) for a skinned model: it animates the splats.
@export_file("*.rig") var rig_path := ""
## Which clip to play. Empty uses the first one.
@export var clip := ""
@export var clip_speed := 1.0
@export var clip_loop := true
## Pose the rig at a fixed time instead of playing it. -1 follows the clock.
@export var pose_hold := -1.0
@export_group("")
@export var fog_start := 6.2
@export var fog_end := 9.0
@export var cull_backfaces := true

var _solid: MultiMeshInstance3D
var _glow: MultiMeshInstance3D
var _solid_count := 0

var _rig: PixelArtRig
var _bone_tex: ImageTexture
var _skin_time := 0.0
var _skinned := false
var _skin_width := 1
var _view_params := {"low_res": Vector2(640, 360), "min_texels": 0.9, "falloff": 0.0}


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


func rebuild() -> void:
	for child in [_solid, _glow]:
		if is_instance_valid(child):
			child.queue_free()
	_solid = null
	_glow = null
	if cloud == null or not cloud.has_data():
		return

	var buffers := cloud.build_buffers()
	var box := cloud.compute_aabb()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)

	_solid_count = buffers["solid_count"]
	_solid = _make(buffers["solid"], buffers["solid_count"], quad, SOLID_SHADER, box)
	_glow = _make(buffers["glow"], buffers["glow_count"], quad, GLOW_SHADER, box)
	_push_base()
	_setup_skin()
	_push_params()


func _make(buffer: PackedFloat32Array, count: int, quad: QuadMesh, shader: Shader, box: AABB) -> MultiMeshInstance3D:
	if count <= 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	mm.buffer = buffer

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.custom_aabb = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 0.0
	var mat := ShaderMaterial.new()
	mat.shader = shader
	node.material_override = mat
	add_child(node)
	return node


## Called by [PixelArtView] when the window, the pixel size or the look changes.
func set_view_params(low_res: Vector2, min_texels: float, falloff: float) -> void:
	_view_params = {"low_res": low_res, "min_texels": min_texels, "falloff": falloff}
	_push_params()


## Called every frame, for the wind.
## Pose the motion at a fixed time, for a look check or a screenshot. -1 follows the clock.
@export var time_override := -1.0


func set_time(time: float) -> void:
	_set_param("ps_time", time if time_override < 0.0 else time_override)
	# lamps flicker, so their colour has to be re-read every frame
	_push_lights()


## A skinned model: joint indices and weights per splat, and the bones as a texture.
func _setup_skin() -> void:
	_skinned = false
	_rig = null
	_bone_tex = null
	if cloud == null or rig_path.is_empty() or not cloud.is_skinned():
		return
	_rig = PixelArtRig.load_file(rig_path)
	if _rig == null or _rig.bone_count == 0:
		_rig = null
		return
	if clip.is_empty():
		var names := _rig.clip_names()
		if names.size() > 0:
			clip = names[0]

	const WIDTH := 2048
	var n := cloud.count
	var rows := (n + WIDTH - 1) / WIDTH
	var idx := PackedByteArray()
	var wts := PackedByteArray()
	idx.resize(WIDTH * rows * 4)
	wts.resize(WIDTH * rows * 4)
	for i in n:
		var at := i * 8
		var o := i * 4
		idx[o] = cloud.skin[at]
		idx[o + 1] = cloud.skin[at + 1]
		idx[o + 2] = cloud.skin[at + 2]
		idx[o + 3] = cloud.skin[at + 3]
		wts[o] = cloud.skin[at + 4]
		wts[o + 1] = cloud.skin[at + 5]
		wts[o + 2] = cloud.skin[at + 6]
		wts[o + 3] = cloud.skin[at + 7]

	var idx_tex := ImageTexture.create_from_image(
		Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBA8, idx))
	var w_tex := ImageTexture.create_from_image(
		Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBA8, wts))
	var bones := Image.create(4, _rig.bone_count, false, Image.FORMAT_RGBAF)
	_bone_tex = ImageTexture.create_from_image(bones)

	_skin_width = WIDTH
	_skinned = true
	_skin_time = 0.0
	_push_bones(_rig.pose(clip, 0.0))

	for node in [_solid, _glow]:
		if not is_instance_valid(node):
			continue
		var mat: ShaderMaterial = node.material_override
		mat.set_shader_parameter("ps_skinned", true)
		mat.set_shader_parameter("ps_skin_idx", idx_tex)
		mat.set_shader_parameter("ps_skin_w", w_tex)
		mat.set_shader_parameter("ps_bones", _bone_tex)
		mat.set_shader_parameter("ps_skin_width", WIDTH)
		mat.set_shader_parameter("ps_bone_count", _rig.bone_count)


func _push_bones(mats: PackedFloat32Array) -> void:
	if _bone_tex == null or _rig == null:
		return
	_bone_tex.update(Image.create_from_data(4, _rig.bone_count, false, Image.FORMAT_RGBAF,
		mats.to_byte_array()))


func _process(delta: float) -> void:
	if not _skinned or _rig == null:
		return
	var length := _rig.duration(clip)
	if pose_hold >= 0.0:
		_skin_time = pose_hold
	else:
		_skin_time += delta * clip_speed
		if length > 0.0 and clip_loop:
			_skin_time = fmod(_skin_time, length)
	_push_bones(_rig.pose(clip, _skin_time))


func _push_base() -> void:
	# the motion hashes on the splat's index, and the glow buffer starts partway through the cloud
	if is_instance_valid(_solid) and _solid.material_override != null:
		_solid.material_override.set_shader_parameter("ps_base", 0.0)
	if is_instance_valid(_glow) and _glow.material_override != null:
		_glow.material_override.set_shader_parameter("ps_base", float(_solid_count))


func _push_params() -> void:
	for node in [_solid, _glow]:
		if not is_instance_valid(node):
			continue
		var mat: ShaderMaterial = node.material_override
		mat.set_shader_parameter("ps_low_res", _view_params["low_res"])
		mat.set_shader_parameter("ps_min_texels", _view_params["min_texels"])
		mat.set_shader_parameter("ps_falloff", _view_params["falloff"])
		mat.set_shader_parameter("ps_exposure", exposure)
		mat.set_shader_parameter("ps_bands", float(bands))
		mat.set_shader_parameter("ps_fog_start", fog_start)
		mat.set_shader_parameter("ps_fog_end", fog_end)
		mat.set_shader_parameter("ps_cull", 1.0 if cull_backfaces else 0.0)
	_push_lights()


func _push_lights() -> void:
	var sun := Vector3(0.45, 0.8, 0.4).normalized()
	var sun_colour := Color(1, 1, 1)
	var points: Array[Light3D] = []
	for node in get_tree().get_nodes_in_group("pixel_art_lights"):
		if node is DirectionalLight3D and node.visible:
			sun = -node.global_transform.basis.z
		elif node is OmniLight3D and node.visible and points.size() < 4:
			points.append(node)

	var pos := PackedVector3Array()
	var col := PackedVector3Array()
	pos.resize(4)
	col.resize(4)
	for i in 4:
		if i < points.size():
			var l := points[i]
			pos[i] = l.global_position
			var k := l.light_energy * 0.35
			col[i] = Vector3(l.light_color.r * k, l.light_color.g * k, l.light_color.b * k)
		else:
			pos[i] = Vector3(0, -99, 0)
			col[i] = Vector3.ZERO

	for node in [_solid, _glow]:
		if not is_instance_valid(node):
			continue
		var mat: ShaderMaterial = node.material_override
		mat.set_shader_parameter("ps_sun_dir", sun)
		mat.set_shader_parameter("ps_point_pos", pos)
		mat.set_shader_parameter("ps_point_color", col)
		mat.set_shader_parameter("ps_point_count", points.size())


func _set_param(name: StringName, value: Variant) -> void:
	for node in [_solid, _glow]:
		if is_instance_valid(node):
			var mat: ShaderMaterial = node.material_override
			mat.set_shader_parameter(name, value)
