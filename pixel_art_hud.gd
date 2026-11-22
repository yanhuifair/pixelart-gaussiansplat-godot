class_name PixelArtHud
extends Control
## The panel the browser viewer puts over the picture: a few sliders and switches for the look,
## bound to a [PixelArtView], the [SplatCloudNode]s in the tree and the view's camera.
##
## H hides it. Q / X / S / E / O flip the switches, the same keys the site uses.

const BG := Color(0.07, 0.07, 0.09, 0.86)
const INK := Color(0.90, 0.90, 0.94)
const DIM := Color(0.60, 0.60, 0.66)
const ON := Color(0.85, 0.62, 0.16)
const OFF := Color(1, 1, 1, 0.12)

@export var view: PixelArtView
@export var toggle_key := KEY_H
@export var start_visible := true
## Inside the editor dock: no full-screen anchor, no click-to-close, no keyboard shortcuts.
@export var docked := false

var _panel: PanelContainer
var _sliders := {}    # label -> {slider, readout, get, format}
var _switches := {}   # label -> {swatch, get}
var _buttons := {}    # label -> the hit target for its keyboard shortcut


func _ready() -> void:
	if docked:
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if view == null and not docked:
		view = _find_view()
	_bind()


## Point the panel at another view (the editor dock does this when the selection changes).
func bind(new_view: PixelArtView) -> void:
	view = new_view
	if is_inside_tree():
		_bind()


func _bind() -> void:
	for child in get_children():
		child.queue_free()
	_sliders.clear()
	_switches.clear()
	_buttons.clear()
	if view == null:
		if not docked:
			push_warning("PixelArtHud: no PixelArtView in the scene.")
		return
	_build()
	visible = start_visible
	_refresh()


func _find_view() -> PixelArtView:
	var parent := get_parent()
	while parent != null:
		for child in parent.get_children():
			if child is PixelArtView:
				return child
		parent = parent.get_parent()
	return null


# ---- the panel ----------------------------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_width_left = 1
	style.border_color = Color(1, 1, 1, 0.08)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2.ZERO if docked else Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(272, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_section(box, "look")
	_range(box, "pixel size", 1, 8, 1,
		func(): return float(view.pixel_size),
		func(v): view.pixel_size = int(v),
		func(v): return "%dpx" % int(v))
	_range(box, "dither", 0, 1, 0.05,
		func(): return view.dither,
		func(v): view.dither = v,
		func(v): return "%.2f" % v)
	_range(box, "light", 0.5, 2.5, 0.05,
		func(): return _exposure(),
		func(v): _each_cloud(func(n): n.exposure = v),
		func(v): return "%.2f" % v)
	_range(box, "light bands", 0, 8, 1,
		func(): return float(_bands()),
		func(v): _each_cloud(func(n): n.bands = int(v)),
		func(v): return "smooth" if v < 0.5 else str(int(v)))

	_section(box, "view")
	_toggle(box, "palette", "Q",
		func(): return view.quantise,
		func(v): view.quantise = v)
	_toggle(box, "hard pixels", "X",
		func(): return view.crisp,
		func(v): view.crisp = v)
	_toggle(box, "2x2 supersample", "S",
		func(): return view.supersample,
		func(v): view.supersample = v)
	_toggle(box, "outline", "E",
		func(): return view.outline,
		func(v): view.outline = v)
	_toggle(box, "auto orbit", "O",
		func(): return _auto_orbit(),
		func(v): _set_auto_orbit(v))

	if docked:
		return

	var hint := Label.new()
	hint.text = "H  hide"
	hint.add_theme_color_override("font_color", DIM)
	hint.add_theme_font_size_override("font_size", 11)
	hint.position = Vector2(0, 4)
	box.add_child(hint)


func _section(box: VBoxContainer, title: String) -> void:
	if box.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		box.add_child(gap)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", DIM)
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)


func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)
	return row


func _spacer(row: HBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)


func _small(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", DIM)
	label.add_theme_font_size_override("font_size", 11)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _range(box: VBoxContainer, text: String, lo: float, hi: float, step: float,
		get_value: Callable, set_value: Callable, format: Callable) -> void:
	var row := _row(box, text)
	_spacer(row)
	var readout := _small(format.call(get_value.call()))
	row.add_child(readout)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = get_value.call()
	slider.custom_minimum_size = Vector2(0, 14)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v):
		readout.text = format.call(v)
		set_value.call(v))
	box.add_child(slider)
	_sliders[text] = {"slider": slider, "readout": readout, "get": get_value, "format": format}


func _toggle(box: VBoxContainer, text: String, key: String,
		get_value: Callable, set_value: Callable) -> void:
	var row := _row(box, text)
	if not key.is_empty():
		row.add_child(_small(key))
	_spacer(row)

	# a flat button coloured on or off: the site's little square, and the thing you click
	var swatch := Button.new()
	swatch.flat = true
	swatch.focus_mode = Control.FOCUS_NONE
	swatch.custom_minimum_size = Vector2(13, 13)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	swatch.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	swatch.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var glow := ColorRect.new()
	glow.custom_minimum_size = Vector2(13, 13)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.color = ON if get_value.call() else OFF
	swatch.add_child(glow)
	row.add_child(swatch)

	swatch.pressed.connect(func():
		var next: bool = not bool(get_value.call())
		set_value.call(next)
		glow.color = ON if next else OFF)
	_switches[text] = {"swatch": swatch, "glow": glow, "get": get_value}
	_buttons[text] = swatch


# ---- state --------------------------------------------------------------------

func _each_cloud(fn: Callable) -> void:
	for node in get_tree().get_nodes_in_group(SplatCloudNode.GROUP):
		fn.call(node)


func _cloud() -> SplatCloudNode:
	for node in get_tree().get_nodes_in_group(SplatCloudNode.GROUP):
		return node
	return null


func _auto_orbit() -> bool:
	return view.camera != null and view.camera.auto_orbit


func _set_auto_orbit(v: bool) -> void:
	if view.camera != null:
		view.camera.auto_orbit = v


func _exposure() -> float:
	var node := _cloud()
	return node.exposure if node != null else 1.0


func _bands() -> int:
	var node := _cloud()
	return node.bands if node != null else 5


func _refresh() -> void:
	# something else may have moved a value (the inspector, a script): the panel follows it
	for text in _sliders:
		var entry: Dictionary = _sliders[text]
		var v: float = entry["get"].call()
		entry["slider"].set_value_no_signal(v)
		entry["readout"].text = entry["format"].call(v)
	for text in _switches:
		var entry: Dictionary = _switches[text]
		entry["glow"].color = ON if entry["get"].call() else OFF


func _unhandled_input(event: InputEvent) -> void:
	if docked:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == toggle_key:
		visible = not visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	var name_by_key := {KEY_Q: "palette", KEY_X: "hard pixels", KEY_S: "2x2 supersample",
		KEY_E: "outline", KEY_O: "auto orbit"}
	var target: String = name_by_key.get(event.keycode, "")
	if target.is_empty():
		return
	var button: Button = _buttons.get(target)
	if button != null:
		button.pressed.emit()
		get_viewport().set_input_as_handled()
