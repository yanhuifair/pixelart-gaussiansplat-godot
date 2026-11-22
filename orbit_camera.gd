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

var _idle := 0.0


func _ready() -> void:
	fov = 30.0
	near = 0.05
	far = 200.0
	snap()


func snap() -> void:
	# pitch is "how far above the target", and rotating a +Z offset by +X takes it down, so negate
	var rot := Basis.from_euler(Vector3(-deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	position = target + rot * Vector3(0.0, 0.0, distance)
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
	if auto_orbit and _idle > idle_delay:
		yaw += auto_orbit_speed * delta
		snap()
