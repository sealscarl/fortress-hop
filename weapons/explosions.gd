class_name Explosions
## Shared Quake-style radius damage: damage falls off linearly to zero at the
## edge of the radius, and knockback is proportional to the damage.
## Teammates are hurt and pushed only with friendly fire on (mp_friendlyfire,
## see Player.hurt). Your own explosions always hurt (scaled) and push you,
## so rocket/pipe jumps work. `weapon` is the kill feed icon.

## Server only.
static func radial(tree: SceneTree, origin: Vector3, damage: float, radius: float,
		knockback: float, attacker: Player, self_damage_scale: float, self_push_scale := 1.0,
		weapon := "") -> void:
	for p: Player in tree.get_nodes_in_group("player"):
		if p.is_queued_for_deletion() or not p.alive:
			continue
		var offset := p.center() - origin
		var dist := offset.length()
		if dist > radius:
			continue
		var points := damage * (1.0 - dist / radius)
		var dir := offset / dist if dist > 0.05 else Vector3.UP
		var scale := self_damage_scale if p == attacker else 1.0
		var push := self_push_scale if p == attacker else 1.0
		p.hurt(points * scale, attacker, dir * points * knockback * push, weapon)
