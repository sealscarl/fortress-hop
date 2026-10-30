extends CanvasLayer
## Quake-style drop-down console (autoload "Console"). Toggle with ~ (the key
## left of 1). Type "help" to start.
##
## Cvars come in two kinds:
## - Server cvars (sv_, pm_, tf_): movement and grenade tuning, in Quake units.
##   Only the server can change them; they're sent to every client so
##   prediction stays exact. Offline / hosting, your own values are used.
## - Client cvars: your Options settings (sensitivity, fov...), saved with them.
##
## user://autoexec.cfg runs at startup if it exists.

const U := 32.0   ## Quake units per meter.

## Server cvars: name -> [default, help, target, scale]. target is a Player
## property, or "grenades.<property>". Value in Godot = cvar / scale.
const SERVER_VARS := {
	"sv_gravity": [800.0, "Gravity (ups²)", "gravity", U],
	"sv_accelerate": [10.0, "Ground acceleration", "ground_accelerate", 1.0],
	"sv_airaccelerate": [10.0, "Air acceleration (strafing)", "air_accelerate", 1.0],
	"sv_friction": [6.0, "Ground friction", "friction", 1.0],
	"sv_stopspeed": [100.0, "Friction acts as if you're at least this fast (ups)", "stop_speed", U],
	"pm_jumpspeed": [270.0, "Jump upward speed (ups)", "jump_velocity", U],
	"pm_airwishspeed": [30.0, "Max speed added per air tick toward your strafe (ups). Quake: 30", "air_wish_speed_cap", U],
	"pm_bunnyspeedcap": [0.0, "Max horizontal speed while hopping (ups). 0 = no cap", "max_bhop_speed", U],
	"pm_stepheight": [18.0, "Tallest step you walk up (units)", "step_height", U],
	"pm_airstep": [1.0, "1 = step up stairs in the air too (bhop up stairs)", "air_step", 0.0],
	"tf_conc_maxspeed": [1000.0, "Horizontal speed cap after a conc (ups). 0 = no cap", "grenades.conc_max_horizontal_speed", U],
	"tf_hhconc_hpower": [2.74, "Handheld conc horizontal multiplier", "grenades.hh_lateral_power", 1.0],
	"tf_hhconc_vpower": [4.1, "Handheld conc vertical multiplier", "grenades.hh_vertical_power", 1.0],
	"tf_hhconc_minup": [320.0, "Handheld conc minimum upward speed (ups)", "grenades.hh_min_up_speed", U],
	"tf_hhfrag_push": [1000.0, "Handheld frag push (ups)", "grenades.hh_frag_push", U],
	"tf_gren_fuse": [3.0, "Grenade countdown after the prime delay (seconds)", "grenades.fuse_time", 1.0],
	"tf_gren_primedelay": [1.0, "Seconds after priming before the countdown starts (total = this + tf_gren_fuse)", "grenades.prime_delay", 1.0],
	"tf_rocket_selfdamage": [0.72, "Share of rocket damage you take yourself. 0.72 = 4 rocket jumps, the 5th kills", "", 1.0],
	"tf_rocket_selfpush": [0.8, "Share of rocket push you get yourself (rocket jump strength)", "", 1.0],
	"tf_flagthrow_speed": [400.0, "Flag throw speed along your aim (ups)", "", 1.0],
	"tf_flagthrow_up": [200.0, "Extra upward speed on a flag throw (ups)", "", 1.0],
	"mp_friendlyfire": [1.0, "1 = teammates can hurt and push each other (team kills cost a frag)", "", 1.0],
	"pm_stepdown": [1.0, "1 = walking down stairs/slopes keeps you on the ground", "step_down", 0.0],
	"pm_slopeboost": [0.5, "Landing on a downhill slope adds forward speed (0 = none, 1 = full Quake)", "slope_boost", 1.0],
}

## Client cvars: name -> [Settings key, help].
const CLIENT_VARS := {
	"sensitivity": ["sensitivity", "Mouse sensitivity (Quake/Source scale)"],
	"m_invert": ["invert_y", "1 = invert mouse Y"],
	"m_dpi": ["dpi", "Your mouse DPI (for the cm/360 readout)"],
	"fov": ["fov", "Horizontal field of view at 4:3 (Quake/TF2 style)"],
	"cl_autohop": ["auto_hop", "1 = hold jump to bunnyhop"],
	"cl_showspeed": ["show_speed", "1 = show the speedometer"],
	"cl_showfps": ["show_fps", "1 = show frames per second"],
	"cl_maxfps": ["max_fps", "Frame rate cap, 0 = unlimited"],
	"vid_vsync": ["vsync", "1 = V-Sync on"],
	"vid_mode": ["window_mode", "0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen"],
	"volume": ["volume", "Master volume, 0 to 1"],
}

## QW-style names for bindable actions.
const ACTION_ALIASES := {
	"+forward": "move_forward", "+back": "move_back", "+moveleft": "move_left",
	"+moveright": "move_right", "+jump": "jump", "+duck": "crouch", "+attack": "fire",
	"+gren1": "grenade_1", "+gren2": "grenade_2", "reload": "reload", "detpipe": "detonate_pipes",
	"slot1": "weapon_1", "slot2": "weapon_2", "slot3": "weapon_3",
	"invnext": "weapon_next", "invprev": "weapon_prev", "+showscores": "scoreboard",
	"changeclass": "change_class", "changeteam": "change_team", "throwflag": "throw_flag",
}

const MAX_LINES := 400

var sv_local := {}    ## Your own server cvar values (used offline / when hosting).
var sv_remote := {}   ## Values from the server you're connected to.

var _panel: Control
var _log: RichTextLabel
var _line: LineEdit
var _history: PackedStringArray = []
var _history_pos := 0
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _commands := {}   ## name -> [Callable(args: PackedStringArray), help]


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in SERVER_VARS:
		sv_local[k] = SERVER_VARS[k][0]
	_register_commands()
	_build_ui()
	multiplayer.server_disconnected.connect(_on_left_server)
	multiplayer.connection_failed.connect(_on_left_server)
	Net.status_changed.connect(func(s): if s != "": print_line(s))
	print_line("Fortress Hop console. Type [b]help[/b] for commands, [b]cvarlist[/b] for settings.")
	if FileAccess.file_exists("user://autoexec.cfg"):
		exec_file("autoexec", true)


func is_open() -> bool:
	return _panel.visible


# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.anchor_bottom = 0.45
	_panel.visible = false
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	var edge := ColorRect.new()
	edge.color = Color(1.0, 0.6, 0.2)
	edge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	edge.offset_top = -2
	_panel.add_child(edge)

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 6
	v.offset_bottom = -8
	_panel.add_child(v)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_override("normal_font", mono)
	_log.add_theme_font_override("bold_font", mono)
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	v.add_child(_log)

	_line = LineEdit.new()
	_line.add_theme_font_override("font", mono)
	_line.add_theme_font_size_override("font_size", 16)
	_line.placeholder_text = "]  type a command — Tab completes, ↑/↓ history, ~ or Esc closes"
	_line.text_submitted.connect(_on_submit)
	_line.keep_editing_on_text_submit = true
	v.add_child(_line)


func toggle() -> void:
	if is_open():
		close()
	else:
		_mouse_before = Input.mouse_mode
		_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_line.grab_focus()
		_line.clear()


func close() -> void:
	_panel.visible = false
	_line.release_focus()
	if _mouse_before == Input.MOUSE_MODE_CAPTURED and not GameUI.menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.physical_keycode == KEY_QUOTELEFT:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_complete()
			get_viewport().set_input_as_handled()
		KEY_UP:
			_browse_history(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_browse_history(1)
			get_viewport().set_input_as_handled()


func _on_submit(text: String) -> void:
	_line.clear()
	text = text.strip_edges()
	if text.is_empty():
		return
	if _history.is_empty() or _history[-1] != text:
		_history.append(text)
	_history_pos = _history.size()
	print_line("[color=#8899aa]] %s[/color]" % _escape(text))
	execute(text)


func _browse_history(dir: int) -> void:
	if _history.is_empty():
		return
	_history_pos = clampi(_history_pos + dir, 0, _history.size())
	_line.text = _history[_history_pos] if _history_pos < _history.size() else ""
	_line.caret_column = _line.text.length()


func _complete() -> void:
	var t := _line.text.strip_edges()
	if t.is_empty() or " " in t:
		return
	var names := _all_names().filter(func(n): return n.begins_with(t))
	if names.is_empty():
		return
	if names.size() == 1:
		_line.text = names[0] + " "
	else:
		names.sort()
		print_line("  ".join(names))
		var common: String = names[0]
		for n in names:
			while not n.begins_with(common):
				common = common.substr(0, common.length() - 1)
		_line.text = common
	_line.caret_column = _line.text.length()


func _all_names() -> Array:
	return _commands.keys() + SERVER_VARS.keys() + CLIENT_VARS.keys() + ["name"]


func print_line(text: String) -> void:
	_log.append_text(text + "\n")
	if _log.get_paragraph_count() > MAX_LINES:
		_log.remove_paragraph(0)


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


# --- Running commands -------------------------------------------------------------

## Runs one or more commands (separated by ; or new lines).
func execute(text: String) -> void:
	for line in text.replace(";", "\n").split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("#"):
			continue
		var args := _tokenize(line)
		var cmd := args[0].to_lower()
		args.remove_at(0)
		if _commands.has(cmd):
			_commands[cmd][0].call(args)
		elif SERVER_VARS.has(cmd) or CLIENT_VARS.has(cmd) or cmd == "name":
			_cvar_command(cmd, args)
		else:
			print_line("[color=#ff7766]Unknown command \"%s\". Type help.[/color]" % _escape(cmd))


static func _tokenize(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	for ch in line:
		if ch == "\"":
			quoted = not quoted
		elif ch == " " and not quoted:
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func exec_file(file: String, quiet := false) -> bool:
	var path := file if file.begins_with("user://") else "user://" + file
	if not path.ends_with(".cfg"):
		path += ".cfg"
	if not FileAccess.file_exists(path):
		if not quiet:
			print_line("[color=#ff7766]Can't find %s[/color]" % path)
		return false
	print_line("execing %s" % path)
	execute(FileAccess.get_file_as_string(path))
	return true


# --- Cvars ------------------------------------------------------------------------

func _cvar_command(cvar: String, args: PackedStringArray) -> void:
	if args.is_empty():
		print_line(_describe(cvar))
		return
	if cvar == "name":
		Net.set_player_name(" ".join(args))
		print_line("name is \"%s\" (takes effect next time you join)" % _escape(Net.player_name))
		return
	if not args[0].is_valid_float():
		print_line("[color=#ff7766]%s needs a number.[/color]" % cvar)
		return
	var v := args[0].to_float()
	if SERVER_VARS.has(cvar):
		set_server_var(cvar, v)
	else:
		_set_client_var(cvar, v)


func _describe(cvar: String) -> String:
	if cvar == "name":
		return "\"name\" is \"%s\"" % _escape(Net.player_name)
	if SERVER_VARS.has(cvar):
		var d = SERVER_VARS[cvar]
		return "\"%s\" is \"%s\" (default %s)  [color=#8899aa]%s[/color]" % [cvar, _fmt(_active()[cvar]), _fmt(d[0]), d[1]]
	var c = CLIENT_VARS[cvar]
	var cur = Settings.get_option(c[0])
	return "\"%s\" is \"%s\" (default %s)  [color=#8899aa]%s[/color]" % [
		cvar, _fmt(cur), _fmt(Settings.DEFAULTS[c[0]]), c[1]]


static func _fmt(v) -> String:
	if v is bool:
		return "1" if v else "0"
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return str(snappedf(float(v), 0.0001))


func _set_client_var(cvar: String, v: float) -> void:
	var key: String = CLIENT_VARS[cvar][0]
	var def = Settings.DEFAULTS[key]
	var value: Variant = v
	if def is bool:
		value = v != 0.0
	elif def is int:
		value = int(v)
	Settings.set_option(key, value)
	Settings.save()
	print_line(_describe(cvar))


func _is_client_of_server() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not mp is OfflineMultiplayerPeer and not multiplayer.is_server() \
		and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Server cvar values in effect right now.
func _active() -> Dictionary:
	return sv_remote if _is_client_of_server() and not sv_remote.is_empty() else sv_local


func set_server_var(cvar: String, v: float) -> void:
	if _is_client_of_server():
		print_line("[color=#ff7766]%s is a server setting: only the host can change it.[/color]" % cvar)
		return
	sv_local[cvar] = v
	_apply_all()
	if multiplayer.is_server() and Game.instance:
		Game.instance.send_all(self, "_sync_server_vars", [sv_local], false)
		if cvar != "":
			Game.instance.send_all(self, "_server_says", ["Server changed %s to %s" % [cvar, _fmt(v)]], false)
	print_line(_describe(cvar))


## A server cvar's current value.
func sv(cvar: String) -> float:
	return float(_active()[cvar])


## Sets one Player's movement and grenade values from the active cvars.
func apply_server_vars(p: Player) -> void:
	var vals := _active()
	for k in SERVER_VARS:
		var d = SERVER_VARS[k]
		var target: String = d[2]
		if target == "":
			continue   # Server-only rule (read with sv()), nothing to set on players.
		var value: Variant = vals[k] / d[3] if d[3] != 0.0 else vals[k] != 0.0
		if target.begins_with("grenades."):
			p.grenades.set(target.substr(9), value)
		else:
			p.set(target, value)


func _apply_all() -> void:
	if Game.instance and is_instance_valid(Game.instance.players_root):
		for p: Player in Game.instance.players_root.get_children():
			apply_server_vars(p)


## Server: send the current values to a client that just finished loading.
func send_server_vars_to(peer: int) -> void:
	_sync_server_vars.rpc_id(peer, sv_local)


@rpc("authority", "call_remote", "reliable")
func _sync_server_vars(vals: Dictionary) -> void:
	sv_remote = {}
	for k in SERVER_VARS:
		var v = vals.get(k, SERVER_VARS[k][0])
		sv_remote[k] = float(v) if (v is float or v is int) else SERVER_VARS[k][0]
	_apply_all()


@rpc("authority", "call_remote", "reliable")
func _server_says(text: String) -> void:
	print_line("[color=#ffcc66]%s[/color]" % _escape(text))


func _on_left_server() -> void:
	sv_remote = {}


## Server cvars that differ from the defaults, as console lines.
func changed_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for k in SERVER_VARS:
		if not is_equal_approx(float(sv_local[k]), float(SERVER_VARS[k][0])):
			out.append("%s %s" % [k, _fmt(sv_local[k])])
	return out


# --- Commands ---------------------------------------------------------------------

func _register_commands() -> void:
	_cmd("help", "List commands", func(_a):
		print_line("[b]Commands[/b] (cvars: type a name to see it, name + value to set it):")
		var names := _commands.keys()
		names.sort()
		for n in names:
			print_line("  [b]%-12s[/b] %s" % [n, _commands[n][1]]))
	_cmd("cvarlist", "List cvars (optionally only those containing some text). * = changed", func(a):
		var f: String = a[0] if a.size() else ""
		print_line("[b]Server cvars[/b] (host only, sent to everyone):")
		for k in SERVER_VARS:
			if f in k:
				var star := " " if is_equal_approx(float(_active()[k]), float(SERVER_VARS[k][0])) else "*"
				print_line(" %s %-18s %-8s [color=#8899aa]%s[/color]" % [star, k, _fmt(_active()[k]), SERVER_VARS[k][1]])
		print_line("[b]Client cvars[/b] (yours, same as Options):")
		for k in CLIENT_VARS:
			if f in k:
				var key: String = CLIENT_VARS[k][0]
				var star := " " if Settings.get_option(key) == Settings.DEFAULTS[key] else "*"
				print_line(" %s %-18s %-8s [color=#8899aa]%s[/color]" % [star, k, _fmt(Settings.get_option(key)), CLIENT_VARS[k][1]]))
	_cmd("reset", "reset <cvar>: back to default.  reset sv: all server cvars", func(a):
		if a.is_empty():
			print_line("usage: reset <cvar>  or  reset sv")
		elif a[0] == "sv":
			if _is_client_of_server():
				print_line("[color=#ff7766]Only the host can change server cvars.[/color]")
				return
			for k in SERVER_VARS:
				sv_local[k] = SERVER_VARS[k][0]
			_apply_all()
			if multiplayer.is_server() and Game.instance:
				Game.instance.send_all(self, "_sync_server_vars", [sv_local], false)
				Game.instance.send_all(self, "_server_says", ["Server reset all server cvars to defaults"], false)
			print_line("All server cvars reset to defaults.")
		elif SERVER_VARS.has(a[0]):
			set_server_var(a[0], SERVER_VARS[a[0]][0])
		elif CLIENT_VARS.has(a[0]):
			var key: String = CLIENT_VARS[a[0]][0]
			Settings.set_option(key, Settings.DEFAULTS[key])
			Settings.save()
			print_line(_describe(a[0]))
		else:
			print_line("No cvar \"%s\"" % _escape(a[0])))
	_cmd("changed", "Show server cvars you've changed, and copy them to the clipboard", func(_a):
		var lines := changed_lines()
		if lines.is_empty():
			print_line("All server cvars are at their defaults.")
			return
		for l in lines:
			print_line("  " + l)
		DisplayServer.clipboard_set("\n".join(lines))
		print_line("[color=#88dd88]Copied to the clipboard — paste it to Claude to make these the defaults.[/color]"))
	_cmd("writeconfig", "Save changed server cvars to user://tuning.cfg (load with: exec tuning)", func(a):
		var file: String = a[0] if a.size() else "tuning"
		file = file.trim_suffix(".cfg") + ".cfg"
		var f := FileAccess.open("user://" + file, FileAccess.WRITE)
		f.store_string("// Fortress Hop tuning, written by writeconfig\n" + "\n".join(changed_lines()) + "\n")
		f.close()
		print_line("Wrote user://%s (%d changed cvars). Folder: %s" % [file, changed_lines().size(),
			ProjectSettings.globalize_path("user://")]))
	_cmd("exec", "exec <file>: run a .cfg file from your user folder", func(a):
		if a.is_empty(): print_line("usage: exec <file>")
		else: exec_file(a[0]))
	_cmd("echo", "Print text", func(a): print_line(_escape(" ".join(a))))
	_cmd("clear", "Clear the console", func(_a): _log.clear())
	_cmd("quit", "Quit the game", func(_a): get_tree().quit())
	_cmd("connect", "connect <ip>: join a server", func(a):
		if a.is_empty(): print_line("usage: connect <ip>")
		else: Net.join(a[0]))
	_cmd("disconnect", "Leave the game", func(_a): Net.leave())
	_cmd("map", "map <name>: host a map (kicks everyone if you're already hosting). No name = list", func(a):
		if a.is_empty():
			for title in Net.MAPS:
				print_line("  %s  [color=#8899aa](%s)[/color]" % [Net.MAPS[title].get_file().get_basename(), title])
			return
		for path in Net.MAPS.values():
			if a[0].to_lower() in path.to_lower():
				if _is_client_of_server():
					print_line("[color=#ff7766]You're connected to someone else's server. disconnect first.[/color]")
					return
				if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
					Net.leave()
				Net.host.call_deferred(false, path)
				return
		print_line("No map matching \"%s\". Type map for the list." % _escape(a[0])))
	_cmd("status", "Show connection and players", func(_a):
		var role := "offline"
		if _is_client_of_server(): role = "client"
		elif multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer: role = "hosting"
		print_line("%s  map: %s" % [role, Net.current_map.get_file().get_basename() if Game.instance else "-"])
		if Game.instance:
			for id in Game.instance.scores:
				var s: Dictionary = Game.instance.scores[id]
				print_line("  %-24s %d kills  %d deaths" % [_escape(s.name), s.kills, s.deaths]))
	_cmd("kill", "Respawn (suicide)", func(_a):
		if Game.instance: Game.instance.request_kill()
		else: print_line("Not in a game."))
	_cmd("team", "team red|blue|auto", func(a):
		var m := {"red": 0, "blue": 1, "auto": -1}
		if Game.instance and a.size() and m.has(a[0].to_lower()): Game.instance.request_team(m[a[0].to_lower()])
		else: print_line("usage (in game): team red|blue|auto"))
	_cmd("class", "class scout|soldier|medic|demoman", func(a):
		if Game.instance and a.size():
			for id in PlayerClasses.DATA:
				if PlayerClasses.DATA[id].name.to_lower().begins_with(a[0].to_lower()):
					Game.instance.request_class(id)
					return
		print_line("usage (in game): class scout|soldier|medic|demoman"))
	_cmd("bind", "bind <key> [action]: show or set a binding. Keys: e, space, mouse1-5, mwheelup...", func(a):
		if a.is_empty():
			print_line("usage: bind <key> [action]   (actions: %s)" % ", ".join(ACTION_ALIASES.keys()))
			return
		var ev := key_event(a[0])
		if ev == null:
			print_line("[color=#ff7766]Unknown key \"%s\"[/color]" % _escape(a[0]))
			return
		if a.size() == 1:
			var bound := "nothing"
			for alias in ACTION_ALIASES:
				var b := Settings.binding(ACTION_ALIASES[alias])
				if b and Settings.same_input(b, ev): bound = alias
			print_line("\"%s\" = \"%s\"" % [a[0], bound])
			return
		var action: String = ACTION_ALIASES.get(a[1].to_lower(), a[1])
		if not InputMap.has_action(action) or not action in Settings.action_names():
			print_line("[color=#ff7766]Unknown action \"%s\"[/color]" % _escape(a[1]))
			return
		var from := Settings.rebind(action, ev)
		Settings.save()
		print_line("bound %s to %s%s" % [Settings.event_name(ev), a[1],
			"" if from == "" else " (%s moved to %s)" % [_alias_of(from), Settings.event_name(Settings.binding(from))]]))
	_cmd("bindlist", "Show all bindings", func(_a):
		for alias in ACTION_ALIASES:
			print_line("  %-14s %s" % [alias, Settings.event_name(Settings.binding(ACTION_ALIASES[alias]))]))


func _cmd(cmd_name: String, help: String, fn: Callable) -> void:
	_commands[cmd_name] = [fn, help]


func _alias_of(action: String) -> String:
	for alias in ACTION_ALIASES:
		if ACTION_ALIASES[alias] == action:
			return alias
	return action


## "e", "space", "mouse4", "mwheelup", "f1"... -> a bindable event.
static func key_event(key_name: String) -> InputEvent:
	var n := key_name.to_lower()
	var mouse := {"mouse1": MOUSE_BUTTON_LEFT, "mouse2": MOUSE_BUTTON_RIGHT, "mouse3": MOUSE_BUTTON_MIDDLE,
		"mouse4": MOUSE_BUTTON_XBUTTON1, "mouse5": MOUSE_BUTTON_XBUTTON2,
		"mwheelup": MOUSE_BUTTON_WHEEL_UP, "mwheeldown": MOUSE_BUTTON_WHEEL_DOWN}
	if mouse.has(n):
		var m := InputEventMouseButton.new()
		m.button_index = mouse[n]
		return m
	var aliases := {"ctrl": "Ctrl", "shift": "Shift", "alt": "Alt", "enter": "Enter", "tab": "Tab",
		"space": "Space", "backspace": "BackSpace", "capslock": "CapsLock", "uparrow": "Up",
		"downarrow": "Down", "leftarrow": "Left", "rightarrow": "Right"}
	var code := OS.find_keycode_from_string(aliases.get(n, key_name.to_upper() if key_name.length() == 1 else key_name.capitalize()))
	if code == KEY_NONE or code == KEY_ESCAPE or code == KEY_QUOTELEFT:
		return null
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k
