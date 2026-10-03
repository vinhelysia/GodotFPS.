extends Resource
class_name CogitoEquipment

signal changed_slot(slot_id: StringName)

const EQUIPMENT_ORIGIN: Dictionary[StringName, int] = {
	&"primary_1": -10,
	&"primary_2": -11,
	&"holster": -12,
	&"melee": -13
}

# The slots containing InventorySlotPD or null
@export var slots: Dictionary = {
	&"primary_1": null,
	&"primary_2": null,
	&"holster": null,
	&"melee": null,
	&"body_armor": null,
	&"helmet": null,
	&"eyewear": null,
	&"face_cover": null,
	&"earpiece": null
}

func can_equip(slot_id: StringName, slot_data: InventorySlotPD) -> bool:
	if slot_data == null or slot_data.inventory_item == null:
		return false
		
	var item = slot_data.inventory_item
	
	match slot_id:
		&"primary_1", &"primary_2":
			return item is WieldableItemPD and item.get("weapon_slot") == 0 # WeaponSlot.PRIMARY
		&"holster":
			return item is WieldableItemPD and item.get("weapon_slot") == 1 # WeaponSlot.HOLSTER
		&"melee":
			return item is WieldableItemPD and item.get("weapon_slot") == 2 # WeaponSlot.MELEE
		&"body_armor":
			return item is GearItemPD and item.get("gear_slot") == 0 # GearSlot.BODY_ARMOR
		&"helmet":
			return item is GearItemPD and item.get("gear_slot") == 1 # GearSlot.HELMET
		&"eyewear":
			return item is GearItemPD and item.get("gear_slot") == 2 # GearSlot.EYEWEAR
		&"face_cover":
			return item is GearItemPD and item.get("gear_slot") == 3 # GearSlot.FACE_COVER
		&"earpiece":
			return item is GearItemPD and item.get("gear_slot") == 4 # GearSlot.EARPIECE
			
	return false

func equip(slot_id: StringName, slot_data: InventorySlotPD) -> InventorySlotPD:
	if not can_equip(slot_id, slot_data):
		return slot_data # Return unchanged if we can't equip
		
	var displaced = slots[slot_id]
	slots[slot_id] = slot_data
	
	# Set slot origin_index to matching negative index if weapon, or -1 for gear
	if EQUIPMENT_ORIGIN.has(slot_id):
		slot_data.origin_index = EQUIPMENT_ORIGIN[slot_id]
	else:
		slot_data.origin_index = -1
		
	changed_slot.emit(slot_id)
	return displaced

func unequip(slot_id: StringName) -> InventorySlotPD:
	var slot_data = slots[slot_id]
	if slot_data:
		slots[slot_id] = null
		slot_data.origin_index = -1
		changed_slot.emit(slot_id)
	return slot_data

func get_equipped(slot_id: StringName) -> InventorySlotPD:
	return slots.get(slot_id)
