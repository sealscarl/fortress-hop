extends Node
## Player options (autoload "Settings"): mouse, video, audio, HUD and key
## bindings. Saved to user://settings.cfg (shared with the player name) and
## applied on startup. Change one with set_option(); the Options menu does.

signal changed

const FILE := "user://settings.cfg"

## Quake/Source "m_yaw": degrees turned per mouse count at sensitivity 1.
## So a TFC/QW/CS/TF2 sensitivity carries over 1:1.
const M_YAW := 0.022

const DEFAULTS := {
	"sensitivity": 4.5,          # 0.099°/count, about what we had before.
	"invert_y": false,
	"dpi": 800,                  # Only used to show cm/360.
	"fov": 90.0,                 # Horizontal at 4:3, like Quake's "fov".
	"window_mode": 0,            # 0 windowed, 1 fullscreen, 2 exclusive fullscreen.
	"vsync": false,
	"max_fps": 0,                # 0 = unlimited.
	"show_fps": false,
	"volume": 0.8,
	"auto_hop": true,
	"show_speed": true,
}

## Bindable actions, in menu order. "" starts a new group.
const ACTIONS := [
	["", "Movement"],
	["move_forward", "Forward"],
	["move_back", "Back"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["jump", "Jump"],
	["crouch", "Crouch"],
	["", "Combat"],
	["fire", "Fire"],
	["grenade_1", "Frag grenade"],
	["grenade_2", "Conc grenade"],
	["reload", "Reload"],
	["detonate_pipes", "Detonate pipe bombs"],
	["weapon_1", "Weapon 1"],
	["weapon_2", "Weapon 2"],
	["weapon_3", "Weapon 3"],
	["weapon_next", "Next weapon"],
	["weapon_prev", "Previous weapon"],
	["", "Menus"],
	["scoreboard", "Scoreboard"],
	["change_class", "Change class"],
	["change_team", "Change team"],
]

var values := DEFAULTS.duplicate()
var _dirty := false
var _fps_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		for k in DEFAULTS:
			var v = cfg.get_value("options", k, DEFAULTS[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (v is int and DEFAULTS[k] is float):
				values[k] = v
		for a in action_names():
			if not cfg.has_section_key("controls", a):
				continue
			var s = cfg.get_value("controls", a)
			if s is String:
				var ev := event_from_string(s)
				if ev:
					_set_binding(a, ev)
	_apply_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save()


func get_option(key: String) -> Variant:
	return values[key]


func set_option(key: String, value: Variant) -> void:
	if values[key] == value:
		return
	values[key] = value
	_dirty = true
	_apply(key)
	changed.emit()


# --- Derived values ---------------------------------------------------------------

## Degrees per mouse count.
func degrees_per_count() -> float:
	return values.sensitivity * M_YAW


## Centimeters of mouse travel for a full 360° turn at the saved DPI.
func cm_per_360() -> float:
	var counts := 360.0 / maxf(degrees_per_count(), 0.0001)
	return counts / maxf(values.dpi, 1) * 2.54


## Camera3D.fov is vertical. Our setting is horizontal at 4:3 (Quake, TF2),
## so wider screens see more to the sides, not less up and down.
func vertical_fov() -> float:
	var h := deg_to_rad(values.fov)
	return rad_to_deg(2.0 * atan(tan(h * 0.5) * 0.75))


# --- Applying ---------------------------------------------------------------------

func _apply_all() -> void:
	for k in values:
		_apply(k)


func _apply(key: String) -> void:
	var headless := DisplayServer.get_name() == "headless"
	match key:
		"window_mode":
			if headless: return
			var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			var m: int = modes[clampi(values.window_mode, 0, 2)]
			if DisplayServer.window_get_mode() != m:
				DisplayServer.window_set_mode(m)
		"vsync":
			if headless: return
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			if headless: return
			Engine.max_fps = values.max_fps
		"volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(values.volume, 0.0001)))
			AudioServer.set_bus_mute(0, values.volume <= 0.0)
		"show_fps":
			if headless: return
			if values.show_fps and not _fps_label:
				var layer := CanvasLayer.new()
				layer.layer = 100
				add_child(layer)
				_fps_label = Label.new()
				_fps_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
				_fps_label.offset_left = -80
				_fps_label.offset_right = 80
				_fps_label.offset_top = 2
				_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_fps_label.add_theme_constant_override("outline_size", 6)
				_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
				_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				layer.add_child(_fps_label)
			if _fps_label:
				_fps_label.visible = values.show_fps


func _process(_delta: float) -> void:
	if _fps_label and _fps_label.visible:
		_fps_label.text = "%d fps" % Engine.get_frames_per_second()


# --- Saving -----------------------------------------------------------------------

func save() -> void:
	if not _dirty:
		return
	var cfg := ConfigFile.new()
	cfg.load(FILE)   # Keep other sections (player name).
	for k in values:
		cfg.set_value("options", k, values[k])
	# Only keys you changed are saved, so new defaults still reach you.
	if cfg.has_section("controls"):
		cfg.erase_section("controls")
	for a in action_names():
		var ev := binding(a)
		var defaults: Array = ProjectSettings.get_setting("input/" + a).events
		var is_default := ev != null and defaults.size() > 0 and same_input(ev, defaults[0])
		if not is_default:
			cfg.set_value("controls", a, event_to_string(ev) if ev else "")
	cfg.save(FILE)
	_dirty = false


# --- Key bindings -----------------------------------------------------------------

func action_names() -> Array:
	var out := []
	for row in ACTIONS:
		if row[0] != "":
			out.append(row[0])
	return out


## The action's (first) key or mouse button, or null if unbound.
func binding(action: String) -> InputEvent:
	var evs := InputMap.action_get_events(action)
	return evs[0] if evs.size() else null


## Binds a key/button to an action. If another action already uses it, that
## action gets this action's old binding (a swap), so nothing is left unbound.
## Returns the action it was taken from ("" if none).
func rebind(action: String, ev: InputEvent) -> String:
	var old := binding(action)
	var taken_from := ""
	for a in action_names():
		if a != action and binding(a) and same_input(binding(a), ev):
			taken_from = a
			if old:
				_set_binding(a, old)
			else:
				InputMap.action_erase_events(a)
	_set_binding(action, ev)
	_dirty = true
	changed.emit()
	return taken_from


func reset_bindings() -> void:
	for a in action_names():
		InputMap.action_erase_events(a)
		for ev in ProjectSettings.get_setting("input/" + a).events:
			InputMap.action_add_event(a, ev)
	_dirty = true
	changed.emit()


func reset_options() -> void:
	for k in DEFAULTS:
		values[k] = DEFAULTS[k]
	_dirty = true
	_apply_all()
	changed.emit()


func _set_binding(action: String, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)


func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a) == _key_code(b)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


func _key_code(k: InputEventKey) -> int:
	return k.physical_keycode if k.physical_keycode != 0 else k.keycode


## A clean copy of a pressed key or mouse button, ready to bind; null if the
## event can't be bound (mouse motion, Esc...).
func bindable(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var code := _key_code(ev)
		if code == 0 or code == KEY_ESCAPE:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code as Key
		return k
	if ev is InputEventMouseButton and ev.pressed:
		var m := InputEventMouseButton.new()
		m.button_index = ev.button_index
		return m
	return null


func event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:%d" % _key_code(ev)
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


func event_from_string(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var n := parts[1].to_int()
	if parts[0] == "key" and n > 0:
		var k := InputEventKey.new()
		k.physical_keycode = n as Key
		return k
	if parts[0] == "mouse" and n > 0:
		var m := InputEventMouseButton.new()
		m.button_index = n as MouseButton
		return m
	return null


## "E", "Space", "Mouse 4", "Wheel down"... Mouse buttons are numbered the
## way gamers say them: Mouse 1 left, 2 right, 3 middle, 4 and 5 the thumb buttons.
func event_name(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		var code := _key_code(ev)
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_keycode_from_physical(code)
			if local != KEY_NONE:
				code = local
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Mouse 1"
			MOUSE_BUTTON_RIGHT: return "Mouse 2"
			MOUSE_BUTTON_MIDDLE: return "Mouse 3"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			MOUSE_BUTTON_WHEEL_LEFT: return "Wheel left"
			MOUSE_BUTTON_WHEEL_RIGHT: return "Wheel right"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % ev.button_index
	return "?"
