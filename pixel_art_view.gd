@tool
class_name PixelArtView
extends Control
## Draws the world small, then turns it into pixel art.
##
## Creates the camera and the low-resolution SubViewport, and a full-screen pass that reads that
## buffer and votes every 2x2 block of samples into one palette colour. Put this anywhere in the
## scene: it sizes itself to the window.
##
## The scene needs its own [Camera3D]? No: the camera is created here, inside the SubViewport, so
## the world is only ever rendered at the art resolution.

const PASS_SHADER := preload("res://addons/pixel_art_splats/shaders/pixel_art.gdshader")

@export_group("Shared look")
## Drop a [PixelArtLook] here and the fields below read and write through to it, so several scenes
## can share one look. Leave it empty to keep the values on this node.
@export var look: PixelArtLook:
	set(value):
		look = value
		if is_inside_tree():
			_apply_palette()

@export var palette: PixelArtPalette:
	get = _get_palette, set = _set_palette

@export_group("Pixel grid")
## Screen pixels per art pixel. Fixed to the screen, so zooming never changes a pixel's size.
@export_range(1, 8) var pixel_size: int:
	get = _get_pixel_size, set = _set_pixel_size
## Draw at twice the art resolution: four samples per art pixel, which the pass votes over.
@export var supersample: bool:
	get = _get_supersample, set = _set_supersample

@export_group("Look")
## Hard-edged splats and nearest-sampled palette colours. Off draws soft Gaussians, blended.
@export var crisp: bool:
	get = _get_crisp, set = _set_crisp
## Silhouettes take a darker ink of their own colour.
@export var outline: bool:
	get = _get_outline, set = _set_outline
## Snap every pixel to the palette. Off shows the continuous colours.
@export var quantise: bool:
	get = _get_quantise, set = _set_quantise
## Ordered (Bayer) dithering between the two nearest palette colours. 0 = off.
@export_range(0.0, 1.0) var dither: float:
	get = _get_dither, set = _set_dither
## Grow every splat to at least this many source texels so far surfaces do not fall apart.
@export_range(0.0, 3.0) var min_texels: float:
	get = _get_min_texels, set = _set_min_texels

@export_group("Camera")
@export var debug_raw: bool:
	get = _get_debug_raw, set = _set_debug_raw
@export var camera_target := Vector3(0.0, -0.02, 0.0)
@export var camera_distance := 5.4
@export var camera_yaw := 22.0
@export var camera_pitch := 6.0
@export var auto_orbit := true

var camera: OrbitCamera
var viewport: SubViewport

var _pass: ColorRect
var _material: ShaderMaterial
var _art := Vector2i.ZERO
var _src := Vector2i.ZERO
var _ss := 2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.own_world_3d = false
	add_child(viewport)

	camera = OrbitCamera.new()
	camera.target = camera_target
	camera.distance = camera_distance
	camera.yaw = camera_yaw
	camera.pitch = camera_pitch
	camera.auto_orbit = auto_orbit
	viewport.add_child(camera)
	camera.snap()

	_pass = ColorRect.new()
	_pass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = PASS_SHADER
	_material.set_shader_parameter("splat_tex", viewport.get_texture())
	_pass.material = _material
	add_child(_pass)

	_apply_palette()
	_resize()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	camera.tick(delta)
	_resize()
	var t := Time.get_ticks_msec() / 1000.0
	for node in get_tree().get_nodes_in_group(SplatCloudNode.GROUP):
		node.set_time(t)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		camera.orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(1.0)


func _apply_palette() -> void:
	if _material == null:
		return
	var resolved := palette.shader_palette() if palette != null else PixelArtPalette.new().shader_palette()
	_material.set_shader_parameter("palette", resolved["palette"])
	_material.set_shader_parameter("surface_count", resolved["surface_count"])
	_material.set_shader_parameter("palette_count", resolved["palette_count"])
	_material.set_shader_parameter("background", resolved["background"])


func _resize() -> void:
	if _material == null:
		return
	var screen := get_viewport_rect().size
	_ss = 2 if supersample else 1
	var art := Vector2i(maxi(1, ceili(screen.x / float(pixel_size))), maxi(1, ceili(screen.y / float(pixel_size))))
	var src := art * _ss
	if art != _art or src != _src:
		_art = art
		_src = src
		viewport.size = src
		_material.set_shader_parameter("src_size", Vector2(src))
		_material.set_shader_parameter("art_size", Vector2(art))
		_material.set_shader_parameter("pixel_size", float(pixel_size))
		_material.set_shader_parameter("ss", float(_ss))
	# these are cheap and must follow the inspector even when the size did not change
	_material.set_shader_parameter("crisp", 1.0 if crisp else 0.0)
	_material.set_shader_parameter("outline_on", 1.0 if outline else 0.0)
	_material.set_shader_parameter("quantise_on", 1.0 if quantise else 0.0)
	_material.set_shader_parameter("dither", dither)
	_material.set_shader_parameter("debug_raw", 1.0 if debug_raw else 0.0)
	_push_to_clouds()


func _push_to_clouds() -> void:
	for node in get_tree().get_nodes_in_group(SplatCloudNode.GROUP):
		node.set_view_params(Vector2(_src), min_texels, 0.0 if crisp else 1.0)


# ---- the look, here or in a shared PixelArtLook --------------------------------
# Each exported field routes through these, so the inspector and the hud keep working whether the
# values live on the node or on the resource.

var _palette: PixelArtPalette
var _pixel_size := 5
var _supersample := true
var _crisp := true
var _outline := true
var _quantise := true
var _dither := 0.0
var _min_texels := 0.9
var _debug_raw := false


func _get_palette() -> PixelArtPalette:
	return look.palette if look != null else _palette


func _set_palette(value: PixelArtPalette) -> void:
	if look != null:
		look.palette = value
	else:
		_palette = value
	if is_inside_tree():
		_apply_palette()


func _get_pixel_size() -> int:
	return look.pixel_size if look != null else _pixel_size


func _set_pixel_size(value: int) -> void:
	if look != null:
		look.pixel_size = value
	else:
		_pixel_size = value


func _get_supersample() -> bool:
	return look.supersample if look != null else _supersample


func _set_supersample(value: bool) -> void:
	if look != null:
		look.supersample = value
	else:
		_supersample = value


func _get_crisp() -> bool:
	return look.crisp if look != null else _crisp


func _set_crisp(value: bool) -> void:
	if look != null:
		look.crisp = value
	else:
		_crisp = value


func _get_outline() -> bool:
	return look.outline if look != null else _outline


func _set_outline(value: bool) -> void:
	if look != null:
		look.outline = value
	else:
		_outline = value


func _get_quantise() -> bool:
	return look.quantise if look != null else _quantise


func _set_quantise(value: bool) -> void:
	if look != null:
		look.quantise = value
	else:
		_quantise = value


func _get_dither() -> float:
	return look.dither if look != null else _dither


func _set_dither(value: float) -> void:
	if look != null:
		look.dither = value
	else:
		_dither = value


func _get_min_texels() -> float:
	return look.min_texels if look != null else _min_texels


func _set_min_texels(value: float) -> void:
	if look != null:
		look.min_texels = value
	else:
		_min_texels = value


func _get_debug_raw() -> bool:
	return look.debug_raw if look != null else _debug_raw


func _set_debug_raw(value: bool) -> void:
	if look != null:
		look.debug_raw = value
	else:
		_debug_raw = value
