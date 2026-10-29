class_name Explosions
## Shared Quake-style radius damage: damage falls off linearly to zero at the
## edge of the radius, and knockback is proportional to the damage.
## No friendly fire: teammates are neither hurt nor pushed. Your own
## explosions still hurt (scaled) and push you, so rocket/pipe jumps work.

## Server only.
static func radial(tree: SceneTree, origin: Vector3, damage: float, radius: float,
		knockback: float, attacker: Player, self_damage_scale: float) -> void:
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
		p.hurt(points * scale, attacker, dir * points * knockback)
