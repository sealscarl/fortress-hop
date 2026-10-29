class_name Explosions
## Shared Quake-style radius damage: damage falls off linearly to zero at the
## edge of the radius, and knockback is proportional to the damage dealt.

## Server only.
static func radial(tree: SceneTree, origin: Vector3, damage: float, radius: float,
		knockback: float, attacker: Player, self_damage_scale: float) -> void:
	for p: Player in tree.get_nodes_in_group("player"):
		if p.is_queued_for_deletion():
			continue
		var offset := p.center() - origin
		var dist := offset.length()
		if dist > radius:
			continue
		var points := damage * (1.0 - dist / radius)
		var dir := offset / dist if dist > 0.05 else Vector3.UP
		p.launch(p.velocity + dir * points * knockback)
		p.take_damage(points * (self_damage_scale if p == attacker else 1.0))
