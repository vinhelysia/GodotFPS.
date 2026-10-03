extends RefCounted

## Builds and checks raid snapshots in Cogito's temp directory.
## Scene roots decide when to commit; this module never publishes a save slot.


static func stage_scene(scene: Node, player: CogitoPlayer, keep_carried_items: bool = true) -> bool:
	var manager := CogitoSceneManager
	manager._current_scene_name = str(scene.name)
	manager._current_scene_path = scene.scene_file_path
	manager.save_scene_state(str(scene.name), "temp")
	# Cogito's capture APIs return void; check the actual resource write before handoff.
	if ResourceSaver.save(manager._scene_state, manager.scene_state_path("temp", str(scene.name))) != OK:
		push_error("Raid snapshot: scene save failed")
		return false
	manager.save_player_state(player, "temp")
	if not keep_carried_items:
		manager._player_state = _without_carried_items(manager._player_state)
	if ResourceSaver.save(manager._player_state, manager.player_state_path("temp")) != OK:
		push_error("Raid snapshot: player save failed")
		return false
	return true


## The prepared snapshot still names Hub and preserves its position and stash/world data.
static func stage_abandon(prepared: CogitoPlayerState) -> bool:
	var fallback := _without_carried_items(prepared)
	return ResourceSaver.save(fallback, CogitoSceneManager.player_state_path("temp")) == OK


static func _without_carried_items(source: CogitoPlayerState) -> CogitoPlayerState:
	var state: CogitoPlayerState = source.duplicate(true)
	# Replace carried resources, never mutate resources that a stash might share.
	var inventory: CogitoInventory = state.player_inventory.duplicate(true)
	inventory.inventory_slots.fill(null)
	inventory.starter_inventory.clear()
	inventory.first_slot = null
	# This non-exported array is not copied by Resource.duplicate().
	inventory.assigned_quickslots.resize(maxi(source.player_quickslots.size(), CogitoEquipment.EQUIPMENT_ORIGIN.size()))
	inventory.assigned_quickslots.fill(null)
	state.player_inventory = inventory
	state.player_equipment = CogitoEquipment.new()
	state.player_quickslots = inventory.assigned_quickslots
	state.saved_wieldable_charges.clear()
	state.interaction_component_state = [{"equipped_wieldable_item": null, "is_wielding": false, "wieldable_was_on": false}]
	var health: Vector2 = state.player_attributes["health"]
	state.player_attributes["health"] = Vector2(health.y, health.y)
	return state
