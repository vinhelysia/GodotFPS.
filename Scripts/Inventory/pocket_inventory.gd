extends CogitoInventory
class_name PocketInventory

@export var pocket_size: Vector2i = Vector2i(2, 2)

func _init() -> void:
	super()
	grid = true
	inventory_size = Vector2i(pocket_size.x * 2, pocket_size.y)
	# Resize slots to 8 (2 pockets of 2x2 = 4x2 = 8 slots)
	inventory_slots.resize(inventory_size.x * inventory_size.y)

func is_enough_space(grabbed_slot_data: InventorySlotPD, to_place_index: int, pickup: bool) -> bool:
	var size = grabbed_slot_data.get_effective_size() if grid else Vector2i(1,1)
	var to_place_x = to_place_index % inventory_size.x
	
	# Pocket boundary check:
	# Columns [0, pocket_size.x - 1] belong to pocket A.
	# Columns [pocket_size.x, inventory_size.x - 1] belong to pocket B.
	# An item cannot cross the boundary at column pocket_size.x
	if to_place_x < pocket_size.x and (to_place_x + size.x - 1) >= pocket_size.x:
		return false
		
	return super(grabbed_slot_data, to_place_index, pickup)

func use_slot_data(index: int):
	# Check if index is a sentinel value
	if index < 0:
		var matched_slot_id: StringName = &""
		# We look up CogitoEquipment via class name or load it
		var cogito_equipment_script = load("res://Scripts/Inventory/cogito_equipment.gd")
		if cogito_equipment_script:
			var origins = cogito_equipment_script.EQUIPMENT_ORIGIN
			for slot_id in origins:
				if origins[slot_id] == index:
					matched_slot_id = slot_id
					break
		
		if matched_slot_id != &"":
			if is_instance_valid(owner) and ("equipment" in owner or owner.get("equipment") != null):
				var player_equip = owner.get("equipment")
				if player_equip:
					var slot_data = player_equip.get_equipped(matched_slot_id)
					if slot_data and slot_data.inventory_item:
						slot_data.inventory_item.use(owner)
		return
	
	super(index)


func can_pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	if is_instance_valid(owner) and ("equipment" in owner or owner.get("equipment") != null):
		var equipment = owner.get("equipment")
		if equipment:
			var item = slot_data.inventory_item
			if item is WieldableItemPD:
				var item_weapon_slot = item.get("weapon_slot")
				if item_weapon_slot == 0: # PRIMARY
					if equipment.get_equipped("primary_1") == null or equipment.get_equipped("primary_2") == null:
						return true
				elif item_weapon_slot == 1: # HOLSTER
					if equipment.get_equipped("holster") == null:
						return true
				elif item_weapon_slot == 2: # MELEE
					if equipment.get_equipped("melee") == null:
						return true
			elif item is GearItemPD:
				var item_gear_slot = item.get("gear_slot")
				var gear_slot_id = &""
				match item_gear_slot:
					0: gear_slot_id = &"body_armor"
					1: gear_slot_id = &"helmet"
					2: gear_slot_id = &"eyewear"
					3: gear_slot_id = &"face_cover"
					4: gear_slot_id = &"earpiece"
				if gear_slot_id != &"" and equipment.get_equipped(gear_slot_id) == null:
					return true
					
	return super(slot_data)


func pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	if is_instance_valid(owner) and ("equipment" in owner or owner.get("equipment") != null):
		var equipment = owner.get("equipment")
		if equipment:
			var item = slot_data.inventory_item
			if item is WieldableItemPD:
				var item_weapon_slot = item.get("weapon_slot")
				var chosen_slot = &""
				if item_weapon_slot == 0: # PRIMARY
					if equipment.get_equipped("primary_1") == null:
						chosen_slot = &"primary_1"
					elif equipment.get_equipped("primary_2") == null:
						chosen_slot = &"primary_2"
				elif item_weapon_slot == 1: # HOLSTER
					if equipment.get_equipped("holster") == null:
						chosen_slot = &"holster"
				elif item_weapon_slot == 2: # MELEE
					if equipment.get_equipped("melee") == null:
						chosen_slot = &"melee"
						
				if chosen_slot != &"":
					var prepared_slot = _prepare_slot_for_inventory(slot_data)
					equipment.equip(chosen_slot, prepared_slot)
					slot_data.quantity = 0
					inventory_updated.emit(self)
					picked_up_new_inventory_item.emit(prepared_slot)
					return true
					
			elif item is GearItemPD:
				var item_gear_slot = item.get("gear_slot")
				var gear_slot_id = &""
				match item_gear_slot:
					0: gear_slot_id = &"body_armor"
					1: gear_slot_id = &"helmet"
					2: gear_slot_id = &"eyewear"
					3: gear_slot_id = &"face_cover"
					4: gear_slot_id = &"earpiece"
					
				if gear_slot_id != &"" and equipment.get_equipped(gear_slot_id) == null:
					var prepared_slot = slot_data.duplicate() as InventorySlotPD
					equipment.equip(gear_slot_id, prepared_slot)
					slot_data.quantity = 0
					inventory_updated.emit(self)
					picked_up_new_inventory_item.emit(prepared_slot)
					return true
					
	return super(slot_data)
