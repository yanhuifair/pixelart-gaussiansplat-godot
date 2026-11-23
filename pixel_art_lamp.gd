@tool
class_name PixelArtLamp
extends OmniLight3D
## A lamp a scene declares: the splat pass adds [code]power * flicker[/code] at this position, so this
## node keeps an OmniLight3D's energy in step with that number — and does the flicker, the way the
## browser's [code]setLights[/code] does.
##
## Add one per entry of a world's [code]meta.lights[/code]. The scene's own groups do not carry
## lights, so a builder has to place these; see the caravan demo for the numbers.
##
## Only splats that are **not baked** are lit by it: a baked scene's colour already holds its light,
## and the shader skips point lights for it. That is why a model standing on an island gets the
## flicker but the island does not.

## The lamp's strength as the world declares it.
@export var power := 1.0

## Which lamp this is, so a row of them does not flicker in lockstep.
@export var index := 0

## Off keeps a steady light (a lamp that should not move, like a window).
@export var flicker := true

## The shader multiplies the engine light's energy by this; keep in step with splat_common.
const GAIN := 0.35


func _ready() -> void:
	shadow_enabled = false
	omni_range = 6.0
	add_to_group("pixel_art_lights")
	_apply(0.0)


func _process(_delta: float) -> void:
	_apply(Time.get_ticks_msec() / 1000.0)


func _apply(t: float) -> void:
	var f := 1.0
	if flicker:
		f = 0.86 + 0.1 * sin(t * 11.0 + index * 2.0) + 0.06 * sin(t * 23.7 + float(index))
	light_energy = power * f / GAIN
