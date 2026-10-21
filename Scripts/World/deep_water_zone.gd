extends Area3D
## No-swim water uses the existing health/death pipeline. Its shapes end below safe floors.


func _on_body_entered(body: Node3D) -> void:
	if not body is CogitoPlayer:
		return
	var player := body as CogitoPlayer
	var health := player.player_attributes.get("health") as CogitoHealthAttribute
	if health == null:
		push_error("Deep water requires the player's health attribute.")
		return
	if player.is_dead or health.value_current <= 0.0:
		return
	player.take_damage(health.value_current)
