extends CanvasLayer
## Grenade fuse timer (left of the crosshair), plus health and grenade counts.

const FRAG_COLOR := Color(1.0, 0.6, 0.2)
const CONC_COLOR := Color(0.55, 0.85, 1.0)

@onready var player: Player = get_parent()
@onready var timer_label: Label = $GrenadeTimer
@onready var status_label: Label = $Status


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
