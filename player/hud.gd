extends CanvasLayer
## Grenade fuse timer (left of the crosshair), plus health and grenade counts.

const FRAG_COLOR := Color(1.0, 0.6, 0.2)
const CONC_COLOR := Color(0.55, 0.85, 1.0)

@onready var player: Player = get_parent()
@onready var timer_label: Label = $GrenadeTimer
@onready var status_label: Label = $Status
var _ammo: Label


func _ready() -> void:
	# Ammo readout, bottom right.
	_ammo = Label.new()
	_ammo.label_settings = status_label.label_settings.duplicate()
	_ammo.label_settings.font_size = 30
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.offset_left = -420
	_ammo.offset_top = -110
	_ammo.offset_right = -32
	_ammo.offset_bottom = -28
	add_child(_ammo)


func _process(_delta: float) -> void:
	var g := player.grenades
	if g.timer_type == -1:
		timer_label.visible = false
	else:
		timer_label.visible = true
		var is_frag := g.timer_type == Grenade.Type.FRAG
		var color := FRAG_COLOR if is_frag else CONC_COLOR
		# Dim once thrown; flash red in the last second while still in hand.
		if g.held_type == -1:
			color.a = 0.55
		elif g.timer_left < 1.0 and fmod(g.timer_left, 0.25) > 0.125:
			color = Color(1, 0.2, 0.2)
		timer_label.modulate = color
		timer_label.text = "%s %.1f" % ["FRAG" if is_frag else "CONC", maxf(g.timer_left, 0.0)]

	if player.class_id == -1:
		status_label.text = "F2 team  ·  F1 class"
		_ammo.text = ""
		return
	var parts := ["%s   HP %d / %d" % [PlayerClasses.stat(player.class_id, "name").to_upper(),
		ceili(player.health), roundi(player.max_health)]]
	if g.max_frags > 0: parts.append("FRAG %d" % g.frags)
	if g.max_concs > 0: parts.append("CONC %d" % g.concs)
	if player.pending_class != -1:
		parts.append("next: %s" % PlayerClasses.stat(player.pending_class, "name"))
	status_label.text = "     ".join(parts)
	status_label.modulate = Color(1, 0.4, 0.35) if player.health < player.max_health * 0.3 else Color.WHITE

	var w := player.weapons
	if w.kinds.is_empty():
		_ammo.text = ""
		return
	var k := w.current
	var size: int = w.stat(k, "clip")
	var state := ""
	if w.switching > 0.0:
		state = "\n..."
	elif w.reloading:
		state = "\nRELOADING"
	elif (size > 0 and w.clip[k] == 0 or size == 0) and w.reserve[k] == 0:
		state = "\nOUT OF AMMO"
	var count := ""
	if size > 0:
		count = "%d / %d" % [w.clip[k], w.reserve[k]]
	elif w.reserve[k] >= 0:
		count = "%d" % w.reserve[k]
	_ammo.text = "%s   %s%s" % [w.stat(k, "name"), count, state]
	_ammo.modulate = Color(1, 0.45, 0.35) if size > 0 and w.clip[k] == 0 else Color.WHITE
