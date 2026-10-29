extends CanvasLayer
## In-game menus: team select (F2), class select (F1), scoreboard (hold Tab)
## and the kill feed. Built in code; owned by Game.
##
## On joining you pick a team, then a class, then you spawn.

const TEAM_COLORS := PlayerClasses.TEAM_COLORS

var _team_panel: Control
var _class_panel: Control
var _scoreboard: Control
var _score_text: RichTextLabel
var _feed: VBoxContainer
var _opened_for_join := false
var _message: Label
var _message_time := 0.0
var _status: RichTextLabel
var _carry: Label


func _ready() -> void:
	layer = 10
	_team_panel = _make_team_panel()
	_class_panel = _make_class_panel()
	_scoreboard = _make_scoreboard()
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -24
	_feed.offset_top = 24
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
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
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.position = Vector2(24, 20)
	_status.custom_minimum_size = Vector2(520, 0)
	_status.add_theme_font_size_override("normal_font_size", 18)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

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
		_status.text = head + "\n".join(ml.status_lines())
		var carrying := ""
		for f in ml.flags:
			if f.carrier == me:
				carrying = "YOU HAVE THE %s!" % f.name.to_upper()
		_carry.text = carrying
		_carry.modulate = TEAM_COLORS[1 - me.team] if carrying else Color.WHITE
	_scoreboard.visible = Input.is_action_pressed("scoreboard")
	if _scoreboard.visible:
		_refresh_scoreboard()


func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("ui_cancel") and (_team_panel.visible or _class_panel.visible):
		_close_menus()
		get_viewport().set_input_as_handled()


func _toggle(panel: Control) -> void:
	if panel.visible:
		_close_menus()
	else:
		_show(panel)


func _show(panel: Control) -> void:
	_team_panel.visible = panel == _team_panel
	_class_panel.visible = panel == _class_panel
	if panel == _class_panel:
		_refresh_class_hint()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menus() -> void:
	_team_panel.visible = false
	_class_panel.visible = false
	var me := Game.instance.local_player
	if me and me.class_id != -1:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


# --- Scoreboard -----------------------------------------------------------------

func _make_scoreboard() -> Control:
	var box := _panel("SCOREBOARD")
	_score_text = RichTextLabel.new()
	_score_text.bbcode_enabled = true
	_score_text.fit_content = true
	_score_text.custom_minimum_size = Vector2(760, 0)
	_score_text.add_theme_font_size_override("normal_font_size", 18)
	_score_text.add_theme_font_size_override("bold_font_size", 20)
	box.add_child(_score_text)
	var root := box.get_parent().get_parent()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root


func _refresh_scoreboard() -> void:
	var g := Game.instance
	var rows := [[], []]
	for p: Player in g.players_root.get_children():
		var sc: Dictionary = g.scores.get(p.peer_id, {"name": "?", "kills": 0, "deaths": 0})
		rows[p.team].append([sc.kills, sc.deaths, sc.name,
			PlayerClasses.stat(p.class_id, "name") if p.class_id != -1 else "—", p == g.local_player])
	var text := ""
	for t in 2:
		rows[t].sort_custom(func(a, b): return a[0] > b[0])
		var total := 0
		for r in rows[t]:
			total += r[0]
		var team_score := ""
		if MapLogic.instance:
			team_score = "%d points  ·  " % MapLogic.instance.team_scores[t]
		text += "[b][color=#%s]%s  —  %s%d kills[/color][/b]\n" % [TEAM_COLORS[t].to_html(false),
			PlayerClasses.TEAM_NAMES[t].to_upper(), team_score, total]
		text += "[color=#999999]%-24s %-10s %6s %6s[/color]\n" % ["NAME", "CLASS", "KILLS", "DEATHS"]
		for r in rows[t]:
			var line := "%-24s %-10s %6d %6d" % [r[2], r[3], r[0], r[1]]
			text += ("[b]%s[/b]\n" % line) if r[4] else line + "\n"
		text += "\n"
	_score_text.text = "[code]" + text + "[/code]"


# --- Kill feed -------------------------------------------------------------------

func add_kill(killer: String, victim: String, killer_team: int, victim_team: int, how := "") -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(496, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 18)
	var v := "[color=#%s]%s[/color]" % [TEAM_COLORS[victim_team].to_html(false), victim]
	if killer.is_empty():
		l.text = "[right]%s %s[/right]" % [v, how if how else "died"]
	else:
		l.text = "[right][color=#%s]%s[/color]  killed  %s[/right]" % [
			TEAM_COLORS[killer_team].to_html(false), killer, v]
	_feed.add_child(l)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)


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
