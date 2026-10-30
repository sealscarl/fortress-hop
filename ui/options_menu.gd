class_name OptionsMenu
extends Control
## The Options screen, built in code. Used by the main menu and the in-game
## Esc menu. Changes apply right away and are saved when it closes.
##
## Tabs: Mouse, Video, Game (sound, HUD, auto-hop), Controls (rebinding).

signal closed

var _sens_info: Label
var _bind_buttons := {}       ## action -> Button
var _waiting_action := ""     ## Action waiting for a key, or "".
var _bind_note: Label
var _refreshers: Array[Callable] = []   ## Re-read values into widgets (after a reset).


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(760, 440)
	box.add_child(tabs)
	tabs.add_child(_mouse_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(_controls_tab())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	var reset := Button.new()
	reset.text = "Reset everything to defaults"
	reset.pressed.connect(_reset_all)
	bottom.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 44)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(close)
	bottom.add_child(back)
	back.grab_focus.call_deferred()


func close() -> void:
	_waiting_action = ""
	Settings.save()
	closed.emit()
	queue_free()


## Esc: cancel a key capture first, then close.
func _input(event: InputEvent) -> void:
	if _waiting_action != "":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_stop_waiting("Cancelled.")
		else:
			var ev := Settings.bindable(event)
			if ev:
				var action := _waiting_action
				_waiting_action = ""
				var from := Settings.rebind(action, ev)
				_refresh_bindings()
				if from != "":
					_bind_note.text = "%s was on %s, so %s now has %s." % [Settings.event_name(ev),
						_label(from), _label(from), Settings.event_name(Settings.binding(from))]
				else:
					_bind_note.text = "%s: %s" % [_label(action), Settings.event_name(ev)]
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Tabs -------------------------------------------------------------------------

func _mouse_tab() -> Control:
	var g := _tab("Mouse")
	_number_row(g, "Sensitivity", "sensitivity", 0.1, 20.0, 0.01,
		"Same scale as Quake, TFC, CS and TF2: use your sensitivity from those.")
	_sens_info = Label.new()
	_sens_info.modulate = Color(0.75, 0.8, 0.9)
	g.add_child(_sens_info)
	_number_row(g, "Mouse DPI", "dpi", 100, 32000, 50,
		"Your mouse's DPI. Only used to show cm/360 above.", true, 1.0, false)
	_check_row(g, "Invert mouse Y", "invert_y")
	_refreshers.append(_update_sens_info)
	_update_sens_info()
	return g.get_parent()


func _video_tab() -> Control:
	var g := _tab("Video")
	_number_row(g, "Field of view", "fov", 70, 130, 1,
		"Horizontal FOV at 4:3, like Quake/TF2 \"fov\". Default 90 (classic). Wider screens see extra to the sides.", true)
	_choice_row(g, "Window", "window_mode", ["Windowed", "Fullscreen (borderless)", "Exclusive fullscreen"])
	_check_row(g, "V-Sync", "vsync", "Off is smoother for aiming; on stops screen tearing.")
	_choice_row(g, "Max FPS", "max_fps", ["Unlimited", "60", "120", "144", "165", "240", "300", "500"],
		[0, 60, 120, 144, 165, 240, 300, 500])
	_check_row(g, "Show FPS", "show_fps")
	return g.get_parent()


func _game_tab() -> Control:
	var g := _tab("Game")
	_number_row(g, "Volume", "volume", 0, 100, 1, "", true, 100.0)
	_check_row(g, "Auto-hop (hold jump to bunnyhop)", "auto_hop")
	_check_row(g, "Show speedometer", "show_speed")
	return g.get_parent()


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	_bind_note = Label.new()
	_bind_note.text = "Click a binding, then press a key or mouse button. Esc cancels."
	_bind_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	top.add_child(_bind_note)
	var reset := Button.new()
	reset.text = "Default keys"
	reset.pressed.connect(func():
		_waiting_action = ""
		Settings.reset_bindings()
		_refresh_bindings()
		_bind_note.text = "Keys reset to defaults.")
	top.add_child(reset)

	var grid: GridContainer
	for row in Settings.ACTIONS:
		if row[0] == "":
			var h := Label.new()
			h.text = row[1].to_upper()
			h.add_theme_font_size_override("font_size", 18)
			h.modulate = Color(1.0, 0.75, 0.4)
			v.add_child(h)
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 24)
			v.add_child(grid)
			continue
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size = Vector2(300, 0)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 34)
		b.pressed.connect(_start_waiting.bind(row[0]))
		grid.add_child(b)
		_bind_buttons[row[0]] = b
	_refresh_bindings()
	return scroll


# --- Rebinding --------------------------------------------------------------------

func _start_waiting(action: String) -> void:
	_refresh_bindings()
	_waiting_action = action
	_bind_buttons[action].text = "press a key..."
	_bind_note.text = "Press a key or mouse button for %s. Esc cancels." % _label(action)


func _stop_waiting(note: String) -> void:
	_waiting_action = ""
	_refresh_bindings()
	_bind_note.text = note


func _refresh_bindings() -> void:
	for a in _bind_buttons:
		_bind_buttons[a].text = Settings.event_name(Settings.binding(a))


func _label(action: String) -> String:
	for row in Settings.ACTIONS:
		if row[0] == action:
			return row[1]
	return action


# --- Rows -------------------------------------------------------------------------

## A tab page: a margin + VBox. Returns the VBox to fill.
func _tab(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	return v


func _row(parent: Control, label: String, hint := "") -> HBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	parent.add_child(outer)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	outer.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(240, 0)
	h.add_child(l)
	if hint != "":
		var hl := Label.new()
		hl.text = hint
		hl.modulate = Color(0.65, 0.68, 0.75)
		hl.add_theme_font_size_override("font_size", 13)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD
		outer.add_child(hl)
	return h


## Slider + exact number box. `display_scale` shows e.g. 0.8 volume as 80.
func _number_row(parent: Control, label: String, key: String, lo: float, hi: float, step: float,
		hint := "", whole := false, display_scale := 1.0, with_slider := true) -> void:
	var h := _row(parent, label, hint)
	var slider := HSlider.new()
	slider.visible = with_slider
	if not with_slider:
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(gap)
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.custom_minimum_size = Vector2(120, 0)
	spin.select_all_on_focus = true
	h.add_child(spin)
	var busy := [false]
	var push := func(shown: float):
		if busy[0]: return
		busy[0] = true
		slider.value = shown
		spin.value = shown
		var v: Variant = shown / display_scale
		if Settings.DEFAULTS[key] is int:
			v = int(round(shown))
		elif whole:
			v = round(shown) / display_scale
		Settings.set_option(key, v)
		busy[0] = false
	slider.value_changed.connect(push)
	spin.value_changed.connect(push)
	var refresh := func():
		busy[0] = true
		var shown: float = float(Settings.get_option(key)) * display_scale
		slider.value = shown
		spin.value = shown
		busy[0] = false
	refresh.call()
	_refreshers.append(refresh)


func _check_row(parent: Control, label: String, key: String, hint := "") -> void:
	var h := _row(parent, label, hint)
	var c := CheckButton.new()
	h.add_child(c)
	c.toggled.connect(func(on): Settings.set_option(key, on))
	var refresh := func(): c.set_pressed_no_signal(Settings.get_option(key))
	refresh.call()
	_refreshers.append(refresh)


## Dropdown. `values` are what gets saved (defaults to the index).
func _choice_row(parent: Control, label: String, key: String, names: Array, values := []) -> void:
	var h := _row(parent, label)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(280, 0)
	for n in names:
		o.add_item(n)
	h.add_child(o)
	o.item_selected.connect(func(i): Settings.set_option(key, values[i] if values.size() else i))
	var refresh := func():
		var v = Settings.get_option(key)
		var i: int = values.find(v) if values.size() else int(v)
		if i == -1:
			o.add_item(str(v))   # A custom value from the settings file.
			values.append(v)
			i = values.size() - 1
		o.select(i)
	refresh.call()
	_refreshers.append(refresh)


func _update_sens_info() -> void:
	_sens_info.text = "= %.3f° per mouse count  ·  %.1f cm (%.1f in) per 360° at %d DPI" % [
		Settings.degrees_per_count(), Settings.cm_per_360(), Settings.cm_per_360() / 2.54,
		Settings.get_option("dpi")]


func _reset_all() -> void:
	_waiting_action = ""
	Settings.reset_options()
	Settings.reset_bindings()
	for r in _refreshers:
		r.call()
	_refresh_bindings()
	_bind_note.text = "Everything reset to defaults."


func _process(_delta: float) -> void:
	if _sens_info:
		_update_sens_info()
