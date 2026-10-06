extends ConsumableItemPD
class_name AnimatedConsumableItem
## Data/routing only; the player's action owns pending use and cancellation.

@export var use_scene: PackedScene


func begin_inventory_use(inventory: CogitoInventory, slot: InventorySlotPD, target: Node) -> bool:
	if target == null or target.is_in_group("external_inventory"):
		target = CogitoSceneManager._current_player_node
	if not is_instance_valid(target) or not (target is CogitoPlayer):
		return false
	var action := target.get_node_or_null("DrinkAction")
	if action == null or not action.has_method("begin"):
		return false
	return action.begin(self, inventory, slot)


func use(_target) -> bool:
	# Direct use lacks the source slot; only animation completion may apply recovery.
	return false


func apply_completed_use(player: CogitoPlayer) -> bool:
	return super.use(player)
