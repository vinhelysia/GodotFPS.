extends InteractionComponent
class_name PickupComponent

const PLAYER_COLLISION_EXCEPTION_RETRY_ATTEMPTS: int = 8
const PLAYER_COLLISION_EXCEPTION_RETRY_DELAY: float = 0.1

@export var slot_data : InventorySlotPD:
	set(value):
		slot_data = value
		_update_display_name()
@export var display_item_name : bool = false
@export var ignore_player_collision: bool = true

var player_interaction_component
var _original_interaction_text : String = ""


func _update_display_name():
	if _original_interaction_text == "":
		_original_interaction_text = interaction_text
		
	if slot_data and slot_data.inventory_item:
		var owner_object : CogitoObject = get_parent()
		if owner_object:
			if display_item_name:
				owner_object.display_name = tr(slot_data.inventory_item.name)
			
			if slot_data.quantity > 1:
				interaction_text = tr(_original_interaction_text) + " x" + str(slot_data.quantity)
			else:
				interaction_text = tr(_original_interaction_text)


func _ready() -> void:
	if _original_interaction_text == "":
		_original_interaction_text = interaction_text
	_update_display_name()
	if ignore_player_collision:
		call_deferred("_try_setup_player_collision_exception")


func interact(_player_interaction_component: PlayerInteractionComponent):
	if !is_disabled:
		pick_up(_player_interaction_component)


func pick_up(_player_interaction_component: PlayerInteractionComponent):
	### Currency Item handling
	if slot_data.inventory_item is CurrencyItemPD and slot_data.inventory_item.add_on_pickup:
		if slot_data.inventory_item.use(_player_interaction_component.get_parent()):
			#_player_interaction_component.send_hint(slot_data.inventory_item.hint_icon_on_use, slot_data.inventory_item.hint_text_on_use)
			Audio.play_sound(slot_data.inventory_item.sound_pickup)
			was_interacted_with.emit(interaction_text, input_map_action)
			self.get_parent().queue_free()
			return
		else:
			_player_interaction_component.send_hint(slot_data.inventory_item.icon, tr(slot_data.inventory_item.name) + " " +tr("HINT_cant_pick_up") )
			return
	
	var original_quantity = slot_data.quantity
	var pick_up_success = _player_interaction_component.get_parent().inventory_data.pick_up_slot_data(slot_data)
	var picked_up_amount = original_quantity - slot_data.quantity

	# Update wieldable UI if we have picked up ammo for current wieldable
	if _player_interaction_component.is_wielding:
		var is_ammo: bool = slot_data.inventory_item.has_method("is_ammo_item")
		var is_current_ammo: bool = _player_interaction_component.equipped_wieldable_item.ammo_item_name == slot_data.inventory_item.name
		if is_ammo and is_current_ammo:
			var equipped_wieldable = _player_interaction_component.equipped_wieldable_item
			_player_interaction_component.equipped_wieldable_item.update_wieldable_data(_player_interaction_component)

	if picked_up_amount > 0:
		Audio.play_sound(slot_data.inventory_item.sound_pickup)
		was_interacted_with.emit(interaction_text, input_map_action)
		
		if slot_data.quantity <= 0:
			# Entire stack picked up
			_player_interaction_component.send_hint(slot_data.inventory_item.icon, tr(slot_data.inventory_item.name) + " " + tr("INVENTORY_add_item") )
			self.get_parent().queue_free()
		else:
			# Partial stack picked up
			_player_interaction_component.send_hint(slot_data.inventory_item.icon, "Picked up " + str(picked_up_amount) + " " + tr(slot_data.inventory_item.name) )
			_update_display_name()
	else:
		# Nothing was picked up at all (inventory full)
		_player_interaction_component.send_hint(slot_data.inventory_item.icon, tr(slot_data.inventory_item.name) + " " + tr("HINT_cant_pick_up") )


func _try_setup_player_collision_exception(attempts_remaining: int = PLAYER_COLLISION_EXCEPTION_RETRY_ATTEMPTS) -> void:
	if not is_inside_tree():
		return

	var pickup_body := _find_pickup_physics_body()
	if not pickup_body:
		push_warning("PickupComponent: could not find pickup physics body for collision exception.")
		return

	var player_body := _find_player_body()
	if player_body:
		pickup_body.add_collision_exception_with(player_body)
		return

	if attempts_remaining > 0:
		get_tree().create_timer(PLAYER_COLLISION_EXCEPTION_RETRY_DELAY).timeout.connect(
				_try_setup_player_collision_exception.bind(attempts_remaining - 1),
				CONNECT_ONE_SHOT)
	else:
		push_warning("PickupComponent: could not find player body for collision exception.")


func _find_pickup_physics_body() -> PhysicsBody3D:
	var node: Node = self
	while node:
		if node is PhysicsBody3D:
			return node as PhysicsBody3D
		node = node.get_parent()
	return null


func _find_player_body() -> PhysicsBody3D:
	if is_instance_valid(CogitoSceneManager._current_player_node) and CogitoSceneManager._current_player_node is PhysicsBody3D:
		return CogitoSceneManager._current_player_node as PhysicsBody3D

	for node: Node in get_tree().get_nodes_in_group("Player"):
		if node is PhysicsBody3D:
			return node as PhysicsBody3D
	return null
