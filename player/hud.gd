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

	status_label.text = "HP %d     FRAG %d     CONC %d" % [
		ceili(player.health), g.frags, g.concs]

	var w := player.weapons
	var k := w.current
	var state := ""
	if w.switching > 0.0:
		state = "\n..."
	elif w.reloading:
		state = "\nRELOADING"
	elif w.clip[k] == 0 and w.reserve[k] == 0:
		state = "\nOUT OF AMMO"
	_ammo.text = "%s   %d / %d%s" % [w.weapon_name(k), w.clip[k], w.reserve[k], state]
	_ammo.modulate = Color(1, 0.45, 0.35) if w.clip[k] == 0 else Color.WHITE
