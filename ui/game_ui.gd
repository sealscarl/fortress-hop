class_name GameUI
extends CanvasLayer
## In-game menus: team select (F2), class select (F1), scoreboard (hold Tab),
## the Esc menu (with Options) and the kill feed. Built in code; owned by Game.
##
## On joining you pick a team, then a class, then you spawn.

const TEAM_COLORS := PlayerClasses.TEAM_COLORS

var _team_panel: Control
var _class_panel: Control
var _scoreboard: Control
var _feed: VBoxContainer
var _opened_for_join := false
var _message: Label
var _message_time := 0.0
var _status: RichTextLabel
var _status_box: VBoxContainer
var _status_rows: Array[HBoxContainer] = []
var _carry: Label
var _pause: Control
var _options: OptionsMenu

static var instance: GameUI


## True while any in-game menu is up (clicks shouldn't grab the mouse).
static func menu_open() -> bool:
	if Console.is_open():
		return true
	if not is_instance_valid(instance):
		return false
	return instance._team_panel.visible or instance._class_panel.visible \
		or instance._pause.visible or is_instance_valid(instance._options)


func _ready() -> void:
	instance = self
	layer = 10
	_team_panel = _make_team_panel()
	_class_panel = _make_class_panel()
	_scoreboard = _make_scoreboard()
	_pause = _make_pause_menu()
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -24
	_feed.offset_top = 24
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	# Center messages ("Your flag has been taken!").
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -500
	_message.offset_right = 500
	_message.offset_top = 150
	_message.offset_bottom = 260
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 28)
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)

	# Map status (flags, security, team scores), top left.
	_status_box = VBoxContainer.new()
	_status_box.position = Vector2(24, 20)
	_status_box.add_theme_constant_override("separation", 2)
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_box)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(420, 0)
	_status.add_theme_font_size_override("normal_font_size", 20)
	_status.add_theme_font_size_override("bold_font_size", 20)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_child(_status)

	# "YOU HAVE THE FLAG" above the bottom HUD.
	_carry = Label.new()
	_carry.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_carry.offset_left = -300
	_carry.offset_right = 300
	_carry.offset_top = -230
	_carry.offset_bottom = -190
	_carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry.add_theme_font_size_override("font_size", 26)
	_carry.add_theme_constant_override("outline_size", 8)
	_carry.add_theme_color_override("font_outline_color", Color.BLACK)
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_carry)
	# Menus and the scoreboard draw over the messages and status.
	for panel in [_scoreboard, _team_panel, _class_panel, _pause]:
		move_child(panel, -1)


func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message_time = 4.0


func _process(_delta: float) -> void:
	var me := Game.instance.local_player if Game.instance else null
	# First time in: walk through team then class.
	if me and not _opened_for_join and me.class_id == -1:
		_opened_for_join = true
		_show(_team_panel)
	_message_time -= _delta
	if _message_time < 1.0:
		_message.modulate.a = clampf(_message_time, 0.0, 1.0)
	var ml := MapLogic.instance
	if ml and me:
		var head := "[b][color=#%s]RED %d[/color]  —  [color=#%s]BLUE %d[/color][/b]\n" % [
			TEAM_COLORS[0].to_html(false), ml.team_scores[0], TEAM_COLORS[1].to_html(false), ml.team_scores[1]]
		_status.text = head.strip_edges()
		_update_status_rows(ml.status_entries())
		var carrying := ""
		for f in ml.flags:
			if f.carrier == me:
				carrying = "YOU HAVE THE %s!" % f.name.to_upper()
		_carry.text = carrying
		_carry.modulate = TEAM_COLORS[1 - me.team] if carrying else Color.WHITE
	_scoreboard.visible = Input.is_action_pressed("scoreboard") and not Console.is_open()
	if _scoreboard.visible:
		_refresh_scoreboard()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_options):
		return   # The Options screen handles its own keys.
	# Number keys pick a class while the class menu is open.
	if _class_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < PlayerClasses.DATA.size():
			_pick_class(n)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("change_class"):
		_toggle(_class_panel)
	elif event.is_action_pressed("change_team"):
		_toggle(_team_panel)
	elif event.is_action_pressed("ui_cancel"):
		# Esc: close whatever's open, or open the Esc menu.
		if _team_panel.visible or _class_panel.visible or _pause.visible:
			_close_menus()
		else:
			_show(_pause)
		get_viewport().set_input_as_handled()


func _toggle(panel: Control) -> void:
	if panel.visible:
		_close_menus()
	else:
		_show(panel)


func _show(panel: Control) -> void:
	_team_panel.visible = panel == _team_panel
	_class_panel.visible = panel == _class_panel
	_pause.visible = panel == _pause
	if panel == _class_panel:
		_refresh_class_hint()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menus() -> void:
	_team_panel.visible = false
	_class_panel.visible = false
	_pause.visible = false
	var me := Game.instance.local_player
	if me and me.class_id != -1:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Esc menu ------------------------------------------------------------------

func _make_pause_menu() -> Control:
	var box := _panel("MENU")
	var items := [
		["Resume", _close_menus],
		["Options", _open_options],
		["Change team  (F2)", _show.bind(_team_panel)],
		["Change class  (F1)", func(): _show(_class_panel)],
		["Leave game", func(): Net.leave()],
		["Quit to desktop", func(): get_tree().quit()],
	]
	for it in items:
		var b := _big_button(it[0], Color(0.22, 0.24, 0.28))
		b.custom_minimum_size = Vector2(340, 52)
		b.pressed.connect(it[1])
		box.add_child(b)
	return box.get_parent().get_parent()


func _open_options() -> void:
	_pause.visible = false
	_options = OptionsMenu.new()
	_options.closed.connect(func(): _show(_pause))
	add_child(_options)


# --- Team panel ----------------------------------------------------------------

func _make_team_panel() -> Control:
	var box := _panel("CHOOSE A TEAM  (F2)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for t in 2:
		var b := _big_button(PlayerClasses.TEAM_NAMES[t].to_upper(), TEAM_COLORS[t])
		b.pressed.connect(_pick_team.bind(t))
		row.add_child(b)
	var auto := _big_button("AUTO", Color(0.4, 0.4, 0.45))
	auto.pressed.connect(_pick_team.bind(-1))
	row.add_child(auto)
	return box.get_parent().get_parent()


func _pick_team(t: int) -> void:
	Game.instance.request_team(t)
	var me := Game.instance.local_player
	if me and me.class_id == -1:
		_show(_class_panel)   # Joining: class next.
	else:
		_close_menus()


# --- Class panel ---------------------------------------------------------------

var _class_hint: Label


func _make_class_panel() -> Control:
	var box := _panel("CHOOSE A CLASS  (F1)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for id in PlayerClasses.DATA:
		var d: Dictionary = PlayerClasses.DATA[id]
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(200, 0)
		var b := _big_button("%d  %s" % [id + 1, d.name.to_upper()], Color(0.3, 0.32, 0.36))
		b.pressed.connect(_pick_class.bind(id))
		col.add_child(b)
		var info := Label.new()
		info.text = "%d HP  ·  %d ups\n%s" % [d.health, d.speed_ups, d.blurb]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", 15)
		col.add_child(info)
		row.add_child(col)
	_class_hint = Label.new()
	_class_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_class_hint)
	return box.get_parent().get_parent()


func _refresh_class_hint() -> void:
	var me := Game.instance.local_player
	_class_hint.text = "" if me == null or me.class_id == -1 \
		else "You'll switch the next time you respawn."


func _pick_class(id: int) -> void:
	Game.instance.request_class(id)
	_close_menus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Map status (flags, security), top left -----------------------------------

func _update_status_rows(entries: Array[Dictionary]) -> void:
	while _status_rows.size() < entries.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		_status_box.add_child(row)
		_status_rows.append(row)
	for i in _status_rows.size():
		var row := _status_rows[i]
		row.visible = i < entries.size()
		if not row.visible:
			continue
		var e: Dictionary = entries[i]
		var color: Color = TEAM_COLORS[e.team]
		var icon := row.get_child(0) as TextureRect
		icon.texture = HudIcons.flag(color) if e.icon == "flag" else HudIcons.button(color)
		# Offline security: the button greys out and blinks.
		icon.modulate = Color(0.45, 0.45, 0.45, 0.5 + 0.5 * absf(sin(Time.get_ticks_msec() / 250.0))) \
			if e.dim else Color.WHITE
		var l := row.get_child(1) as Label
		l.text = e.text
		l.modulate = e.color


# --- Scoreboard -----------------------------------------------------------------

const _SCORE_COLS := [["NAME", 220, HORIZONTAL_ALIGNMENT_LEFT], ["CLASS", 110, HORIZONTAL_ALIGNMENT_LEFT],
	["KILLS", 64, HORIZONTAL_ALIGNMENT_RIGHT], ["DEATHS", 80, HORIZONTAL_ALIGNMENT_RIGHT],
	["DAMAGE", 92, HORIZONTAL_ALIGNMENT_RIGHT], ["TOUCHES", 96, HORIZONTAL_ALIGNMENT_RIGHT],
	["CARRY", 80, HORIZONTAL_ALIGNMENT_RIGHT], ["CAPS", 62, HORIZONTAL_ALIGNMENT_RIGHT]]

var _score_box: VBoxContainer
var _score_sig := ""


func _make_scoreboard() -> Control:
	var box := _panel("SCOREBOARD")
	_score_box = VBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 4)
	_score_box.custom_minimum_size = Vector2(900, 0)
	box.add_child(_score_box)
	var root := box.get_parent().get_parent()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root


## One table per team: a header row and a row per player, in a grid so every
## column lines up. Rebuilt only when something on it changes.
func _refresh_scoreboard() -> void:
	var g := Game.instance
	var rows := [[], []]
	for p: Player in g.players_root.get_children():
		var sc: Dictionary = g.scores.get(p.peer_id, {"name": "?", "kills": 0, "deaths": 0})
		var carry := int(sc.get("carry", 0.0))
		rows[p.team].append([sc.kills, sc.deaths, sc.name,
			PlayerClasses.stat(p.class_id, "name") if p.class_id != -1 else "—", p == g.local_player,
			roundi(sc.get("damage", 0.0)), int(sc.get("touches", 0)), "%d:%02d" % [floori(carry / 60.0), carry % 60],
			int(sc.get("caps", 0))])
	var points := [0, 0]
	if MapLogic.instance:
		points = MapLogic.instance.team_scores
	for t in 2:
		rows[t].sort_custom(func(a, b): return a[0] > b[0])
	var sig := str(rows) + str(points)
	if sig == _score_sig:
		return
	_score_sig = sig
	for c in _score_box.get_children():
		c.queue_free()
	for t in 2:
		var total := 0
		for r in rows[t]:
			total += r[0]
		var title := _cell("%s  —  %d points  ·  %d kills" % [PlayerClasses.TEAM_NAMES[t].to_upper(), points[t], total],
			0, HORIZONTAL_ALIGNMENT_LEFT, TEAM_COLORS[t], 22)
		if t == 1:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 12)
			_score_box.add_child(gap)
		_score_box.add_child(title)
		var grid := GridContainer.new()
		grid.columns = _SCORE_COLS.size()
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 2)
		_score_box.add_child(grid)
		for col in _SCORE_COLS:
			grid.add_child(_cell(col[0], col[1], col[2], Color(0.6, 0.62, 0.66), 15))
		for r in rows[t]:
			var me: bool = r[4]
			var color := Color(1.0, 0.92, 0.6) if me else Color.WHITE
			var vals := [r[2], r[3], str(r[0]), str(r[1]), str(r[5]), str(r[6]), r[7], str(r[8])]
			for i in vals.size():
				grid.add_child(_cell(vals[i], _SCORE_COLS[i][1], _SCORE_COLS[i][2], color, 19))


func _cell(text: String, width: int, align: HorizontalAlignment, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = align
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", size)
	l.modulate = color
	return l


# --- Kill feed -------------------------------------------------------------------

## One kill feed entry, top right: "Killer [weapon] Victim", team colored.
## Suicides and the world show just the icon and the victim. Entries that
## involve you get a light background (like TF2).
func add_kill(killer: String, victim: String, killer_team: int, victim_team: int, how := "",
		weapon := "skull", involves_me := false, teamkill := false) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.9, 0.82, 0.92) if involves_me else Color(0.06, 0.07, 0.09, 0.72)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	if not killer.is_empty():
		row.add_child(_feed_label(killer, TEAM_COLORS[killer_team], involves_me))
	var icon := TextureRect.new()
	icon.texture = HudIcons.weapon(weapon)
	icon.custom_minimum_size = Vector2(52, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	row.add_child(_feed_label(victim, TEAM_COLORS[victim_team], involves_me))
	var note := ""
	if teamkill:
		note = "TEAMKILL"
	elif killer.is_empty() and how != "":
		note = how   # The map's own message, e.g. a security laser.
	if note:
		var n := _feed_label(note, Color(1.0, 0.45, 0.35) if teamkill else Color(0.75, 0.75, 0.75), involves_me)
		n.add_theme_font_size_override("font_size", 14)
		row.add_child(n)
	_feed.add_child(panel)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(8.0 if involves_me else 6.0).timeout.connect(panel.queue_free)


func _feed_label(text: String, color: Color, on_light: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color.darkened(0.25) if on_light else color.lightened(0.15))
	if not on_light:
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


# --- Helpers ---------------------------------------------------------------------

## A centered dark panel with a title; returns the VBox to fill.
func _panel(title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 28)
	box.add_child(t)
	return box


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 64)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b
