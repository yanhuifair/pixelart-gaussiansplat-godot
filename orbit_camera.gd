class_name OrbitCamera
extends Camera3D
## Drag to orbit, scroll to zoom, drift when left alone. Fed by [PixelArtView], because a camera
## inside a SubViewport does not see the main window's input.

var target := Vector3.ZERO
var distance := 5.7
var yaw := 202.0
var pitch := 10.0
var auto_orbit := true
var auto_orbit_speed := 7.0
var idle_delay := 4.0
var drag_speed := 0.18
var zoom_step := 1.12
var distance_range := Vector2(1.2, 20.0)

## The idle motion, as the viewer moves it: a scene breathes in and out, a model sways a little.
## Off keeps the old behaviour — a steady turn at [member auto_orbit_speed].
enum Drift { OFF, SCENE, MODEL }

var drift := Drift.SCENE
## How far the camera sits above its target, as a fraction of the distance (the viewer's `elev`).
var elev := 0.22
## The slow rise and fall of that height.
var bob := 0.06
## Pull back on a window narrower than the picture, the way the viewer's portraitFit does.
var portrait_fit := true

var _idle := 0.0
var _drift := 0.0
var _last_zoom := 1.0


func _ready() -> void:
	fov = 30.0
	near = 0.05
	far = 200.0
	snap()


func snap() -> void:
	# pitch is "how far above the target", and rotating a +Z offset by +X takes it down, so negate
	var rot := Basis.from_euler(Vector3(-deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	position = target + rot * Vector3(0.0, 0.0, distance * _fit())
	look_at(target, Vector3.UP)


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * drag_speed
	pitch = clampf(pitch - relative.y * drag_speed, -89.0, 89.0)
	_idle = 0.0
	snap()


func zoom(steps: float) -> void:
	distance = clampf(distance * pow(zoom_step, steps), distance_range.x, distance_range.y)
	_idle = 0.0
	snap()


func tick(delta: float) -> void:
	_idle += delta
	if not auto_orbit or _idle <= idle_delay:
		return
	if _idle - delta <= idle_delay:
		# just started drifting: take the zoom curve's value as the baseline, so it does not jump
		_drift = 0.0
		_last_zoom = _zoom_at(0.0)

	_drift += delta
	yaw += auto_orbit_speed * delta
	if drift != Drift.OFF:
		var z := _zoom_at(_drift)
		distance = clampf(distance * z / _last_zoom, distance_range.x, distance_range.y)
		_last_zoom = z
		pitch = rad_to_deg(atan(elev + bob * sin(_drift * 0.2)))
	snap()


func _zoom_at(t: float) -> float:
	# the viewer: a scene drifts in for a close look and back out, a model breathes by 12%
	match drift:
		Drift.SCENE:
			return 0.7 + 0.3 * (0.5 + 0.5 * cos(t * 0.11))
		Drift.MODEL:
			return 1.0 - 0.12 * sin(t * 0.15)
	return 1.0


func _fit() -> float:
	# a portrait window is narrower than the picture: step back so the object still fits
	if not portrait_fit:
		return 1.0
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var size := vp.get_visible_rect().size
	if size.x <= 1.0 or size.y <= 1.0:
		return 1.0
	var aspect := size.x / size.y
	return maxf(1.0, 0.9 / aspect)
