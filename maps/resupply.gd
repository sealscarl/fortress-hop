extends Area3D
## Step on it to refill health and grenades.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Players.
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and multiplayer.is_server():
		body.health = body.max_health
		body.grenades.refill()
		body.weapons.refill()
