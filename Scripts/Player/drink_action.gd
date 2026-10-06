extends Node
## Owns one pending bottle animation, never inventory/movement/mouse state.

signal finished(completed: bool)

@export var camera: Camera3D
@export var interaction_component: PlayerInteractionComponent

var is_active: bool = false
var _player: CogitoPlayer
var _player_inventory: CogitoInventory
var _inventory: CogitoInventory
var _source_owner: Node
var _slot: InventorySlotPD
var _item: AnimatedConsumableItem
var _view: Node3D
var _weapon: Node3D
var _weapon_was_visible: bool


func _ready() -> void:
	_player = get_parent() as CogitoPlayer
	if _player == null:
		return
	_player.player_state_loaded.connect(cancel)
	var health: CogitoHealthAttribute = _player.get_node_or_null("HealthAttribute")
	if health != null:
		health.death.connect(cancel)


func begin(item: AnimatedConsumableItem, inventory: CogitoInventory, slot: InventorySlotPD) -> bool:
	if is_active or not _is_alive() or not is_instance_valid(camera) or not is_instance_valid(interaction_component):
		return false
	if item == null or item.use_scene == null or inventory == null or slot == null:
		return false
	if slot.inventory_item != item or slot.quantity <= 0 or not inventory.inventory_slots.has(slot):
		return false
	if interaction_component.is_carrying or interaction_component.is_changing_wieldables or not _can_recover(item):
		return false
	var weapon := interaction_component.equipped_wieldable_node as CogitoWieldable
	if is_instance_valid(weapon) and weapon.animation_player.is_playing():
		return false
	var scene_node := item.use_scene.instantiate()
	var view := scene_node as Node3D
	if view == null:
		scene_node.free()
		return false
	var animator := view.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animator == null or not animator.has_animation("drink"):
		view.free()
		return false
	# Releases must reach the weapon before active guards begin rejecting presses.
	if is_instance_valid(weapon):
		interaction_component.attempt_action_primary(true)
		interaction_component.attempt_action_secondary(true)
	_weapon = weapon
	if is_instance_valid(_weapon):
		_weapon_was_visible = _weapon.visible
		_weapon.hide()
	_item = item
	_inventory = inventory
	_source_owner = inventory.owner
	_player_inventory = _player.inventory_data
	_slot = slot
	_view = view
	is_active = true
	animator.animation_finished.connect(_on_animation_finished.bind(view))
	camera.add_child(view)
	animator.play("drink")
	return true


func cancel() -> void:
	if is_active:
		_finish(false)


func _on_animation_finished(animation_name: StringName, view: Node3D) -> void:
	if not is_active or view != _view or animation_name != &"drink":
		return
	var completed := false
	if _context_is_valid() and _can_recover(_item):
		completed = _item.apply_completed_use(_player)
		if completed:
			_slot.quantity -= 1
			if _slot.quantity <= 0:
				_inventory.null_out_slots(_slot)
			_inventory.inventory_updated.emit(_inventory)
	_finish(completed)


func _context_is_valid() -> bool:
	if not _is_alive() or _player.inventory_data != _player_inventory:
		return false
	if _inventory == null or _slot == null or _slot.inventory_item != _item or _slot.quantity <= 0:
		return false
	if not _inventory.inventory_slots.has(_slot):
		return false
	if _inventory == _player_inventory:
		return _inventory.owner == _player
	# An external source must still own this exact inventory after UI toggles.
	return is_instance_valid(_source_owner) and _source_owner.is_inside_tree() and not _source_owner.is_queued_for_deletion() \
		and _source_owner.get("inventory_data") == _inventory and _inventory.owner == _source_owner


func _can_recover(item: AnimatedConsumableItem) -> bool:
	var attribute: CogitoAttribute = _player.player_attributes.get(item.attribute_name)
	return attribute != null and not attribute.is_locked \
		and item.value_to_change == ConsumableItemPD.ValueType.CURRENT \
		and item.attribute_change_amount > 0.0 and attribute.value_current < attribute.value_max


func _is_alive() -> bool:
	if not is_instance_valid(_player) or not _player.is_inside_tree() or _player.is_queued_for_deletion() or _player.is_dead:
		return false
	var health: CogitoAttribute = _player.get_node_or_null("HealthAttribute")
	return health != null and health.value_current > 0.0


func _finish(completed: bool) -> void:
	is_active = false
	if is_instance_valid(_view):
		var animator := _view.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animator != null:
			animator.stop()
		_view.queue_free()
	if _is_alive() and is_instance_valid(_weapon) and is_instance_valid(interaction_component) \
		and interaction_component.equipped_wieldable_node == _weapon:
		_weapon.visible = _weapon_was_visible
	_view = null
	_weapon = null
	_item = null
	_slot = null
	_inventory = null
	_source_owner = null
	_player_inventory = null
	finished.emit(completed)


func _exit_tree() -> void:
	cancel()
