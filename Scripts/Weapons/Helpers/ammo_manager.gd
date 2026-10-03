## Handles inventory ammo queries and consumption during reload.
## Extracted from cogito_weapon.gd to isolate ammo/inventory logic.
class_name AmmoManager
extends RefCounted

var _pic: PlayerInteractionComponent
## name -> AmmoItemPD. Survive consume wiping the last stack so return_ammo
## can still rebuild a normal quantity stack.
var _ammo_templates: Dictionary = {}


func _init(pic: PlayerInteractionComponent) -> void:
	_pic = pic


func set_pic(pic: PlayerInteractionComponent) -> void:
	_pic = pic


func get_inventory() -> CogitoInventory:
	if _pic == null:
		return null
	return _pic.get_parent().inventory_data as CogitoInventory


func get_available_ammo(item_ref: WieldableItemPD) -> int:
	var inventory := get_inventory()
	if inventory == null or item_ref == null:
		return 0
	var total: int = 0
	for slot: InventorySlotPD in inventory.inventory_slots:
		if slot == null or slot.inventory_item == null:
			continue
		if slot.inventory_item.name != item_ref.ammo_item_name:
			continue
		var ammo_item := slot.inventory_item as AmmoItemPD
		if ammo_item == null:
			continue
		_ammo_templates[ammo_item.name] = ammo_item
		total += ammo_item.reload_amount * slot.quantity
	return total


func consume_ammo(item_ref: WieldableItemPD, ammo_needed: int) -> int:
	var inventory := get_inventory()
	if inventory == null:
		return 0
	var ammo_loaded: int = 0
	var inventory_changed: bool = false
	for slot: InventorySlotPD in inventory.inventory_slots:
		if ammo_needed <= 0:
			break
		if slot == null or slot.inventory_item == null:
			continue
		if slot.inventory_item.name != item_ref.ammo_item_name:
			continue
		var ammo_item := slot.inventory_item as AmmoItemPD
		if ammo_item == null:
			continue
		_ammo_templates[ammo_item.name] = ammo_item
		var per_item: int = maxi(ammo_item.reload_amount, 1)
		var quantity_needed: int = ceili(float(ammo_needed) / float(per_item))
		var quantity_used: int = mini(slot.quantity, quantity_needed)
		var ammo_used: int = per_item * quantity_used
		if quantity_used >= slot.quantity:
			inventory.remove_slot_data(slot)
		else:
			slot.quantity -= quantity_used
		ammo_loaded += ammo_used
		ammo_needed -= ammo_used
		inventory_changed = true
	if inventory_changed:
		inventory.inventory_updated.emit(inventory)
	return ammo_loaded


func return_ammo(item_ref: WieldableItemPD, amount: int) -> void:
	var inventory := get_inventory()
	if inventory == null or item_ref == null or amount <= 0:
		return

	# Project rule: every AmmoItemPD.reload_amount == 1, so "N rounds" is
	# quantity=N on a normal stack — never a single item with reload_amount=N.
	var ammo_item_template: AmmoItemPD = _ammo_templates.get(item_ref.ammo_item_name) as AmmoItemPD
	if ammo_item_template == null:
		for slot: InventorySlotPD in inventory.inventory_slots:
			if slot and slot.inventory_item and slot.inventory_item.name == item_ref.ammo_item_name:
				ammo_item_template = slot.inventory_item as AmmoItemPD
				if ammo_item_template:
					_ammo_templates[ammo_item_template.name] = ammo_item_template
					break

	if ammo_item_template == null:
		push_warning("Could not find ammo item template to return %d rounds of '%s'." % [amount, item_ref.ammo_item_name])
		return

	var new_slot := InventorySlotPD.new()
	new_slot.inventory_item = ammo_item_template
	new_slot.quantity = amount
	inventory.pick_up_slot_data(new_slot)
