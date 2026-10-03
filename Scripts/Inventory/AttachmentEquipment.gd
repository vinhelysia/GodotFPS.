extends CogitoEquipment
class_name AttachmentEquipment

## Presents ONE weapon's attachments as a CogitoEquipment so the modding panel
## can reuse EquipmentSlotUI / collect_equipment_slots() / the grabbed-slot
## cursor / inventory_interface's _on_equipment_slot_pressed() verbatim.
##
## The weapon item is the source of truth (WieldableItemPD.attachments); the
## inherited `slots` dict is just a rebuilt view of it, so get_equipped() works
## unchanged. Bind it to a weapon with bind() before showing the panel.

## Index = AttachmentItemPD.AttachmentSlot enum value. Append-only.
const SLOT_IDS: Array[StringName] = [&"optic", &"muzzle", &"grip", &"stock", &"magazine"]

var weapon_item: WieldableItemPD
## Where stripped magazine rounds go, and where attachments are dragged from.
var inventory: CogitoInventory


func bind(new_weapon: WieldableItemPD, new_inventory: CogitoInventory) -> void:
	weapon_item = new_weapon
	inventory = new_inventory
	rebuild()


## Refreshes the `slots` view from the weapon. Call after any external change
## (e.g. the X-key quick-detach) to resync the panel.
func rebuild() -> void:
	slots = {}
	for slot_index in SLOT_IDS.size():
		var item: AttachmentItemPD = null
		if weapon_item != null:
			item = weapon_item.get_attachment_item(slot_index)
		slots[SLOT_IDS[slot_index]] = _wrap(item)


func can_equip(slot_id: StringName, slot_data: InventorySlotPD) -> bool:
	if weapon_item == null or weapon_item.is_being_wielded:
		return false
	if slot_data == null:
		return false
	var attachment := slot_data.inventory_item as AttachmentItemPD
	if attachment == null:
		return false
	if SLOT_IDS[attachment.attachment_slot] != slot_id:
		return false
	return attachment.fits(weapon_item)


func equip(slot_id: StringName, slot_data: InventorySlotPD) -> InventorySlotPD:
	if not can_equip(slot_id, slot_data):
		return slot_data  # rejected — stays on the cursor
	var attachment := slot_data.inventory_item as AttachmentItemPD
	# Magazine rounds need no handling here: the outgoing magazine leaves with
	# its own, the incoming one brings its own (WieldableItemPD._take_attachment).
	var previous := weapon_item.try_attach(attachment)
	rebuild()
	changed_slot.emit(slot_id)
	_notify_inventory()
	return _wrap(previous)


func unequip(slot_id: StringName) -> InventorySlotPD:
	if weapon_item == null or weapon_item.is_being_wielded:
		return null
	var slot_index := SLOT_IDS.find(slot_id)
	if slot_index < 0:
		return null
	var attachment := weapon_item.get_attachment_item(slot_index)
	if attachment == null:
		return null

	# A stripped magazine keeps the rounds it was feeding — they come off with it.
	var removed := weapon_item.detach(slot_index)
	rebuild()
	changed_slot.emit(slot_id)
	_notify_inventory()
	return _wrap(removed)


## changed_slot only repaints THIS panel's slots. The weapon's own slot — in the
## pockets grid or an equipment slot — carries the "+N" mod badge, and those
## repaint on inventory_updated, so the fitted count would otherwise go stale.
func _notify_inventory() -> void:
	if inventory != null:
		inventory.inventory_updated.emit(inventory)


func _wrap(item: AttachmentItemPD) -> InventorySlotPD:
	if item == null:
		return null
	var slot_data := InventorySlotPD.new()
	slot_data.inventory_item = item
	slot_data.quantity = 1
	slot_data.origin_index = -1
	return slot_data
