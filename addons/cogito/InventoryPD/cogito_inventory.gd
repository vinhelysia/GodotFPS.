extends Resource
class_name CogitoInventory

signal inventory_interact(inventory_data: CogitoInventory, index: int, mouse_button: int)
signal inventory_button_press(inventory_data: CogitoInventory, index: int, action: String)
signal inventory_updated(inventory_data: CogitoInventory)
signal unbind_quickslot_by_index(quickslot_index: int)
signal picked_up_new_inventory_item(slot_data: InventorySlotPD)

## Enables grid inventory. If using, make sure player and ALL interactables have this set to true.
@export var grid: bool
## Injects items from this into the inventory slots
@export var starter_inventory : Array[InventorySlotPD]
@export var inventory_size : Vector2i = Vector2i(4,1)
@export var inventory_slots : Array[InventorySlotPD]

var assigned_quickslots : Array[InventorySlotPD]
var owner : Node

@export var first_slot : InventorySlotPD


func _init():
	if inventory_slots.size() > 0:
		first_slot = inventory_slots[0]


# Call this in your initial scene
func apply_initial_inventory():
	inventory_slots.resize(inventory_size.x * inventory_size.y)
	for item in starter_inventory:
		# Pickup consumes incoming quantity; the authored starter remains reusable.
		if item != null:
			pick_up_slot_data(item.duplicate() as InventorySlotPD)
	if inventory_slots.size() > 0:
		first_slot = inventory_slots[0]


func on_slot_clicked(index: int, mouse_button: int):
	inventory_interact.emit(self, index, mouse_button)


func on_slot_button_pressed(index: int, action: String):
	CogitoGlobals.debug_log(true,"cogito_inventory.gd", "on_slot_button_pressed. index=" + str(index) + ", action=" + str(action) )
	inventory_button_press.emit(self, index, action)


func null_out_slots(slot_data):
	if not slot_data:
		return
	# Equipment/quickslot sentinels use negative origin_index — never wipe the grid with those.
	if slot_data.origin_index < 0:
		return
	var size = slot_data.get_effective_size() if grid else Vector2i(1,1)
	for x in size.x:
		for y in size.y:
			var idx: int = slot_data.origin_index + x + (y * inventory_size.x)
			if idx < 0 or idx >= inventory_slots.size():
				continue
			inventory_slots[idx] = null


# Returns slot data without actually changing the slot
func get_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	if slot_data:
		return slot_data
	else:
		return null


func grab_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	
	if slot_data:
		null_out_slots(slot_data)
		inventory_updated.emit(self)
		return slot_data
	else:
		return null


func grab_single_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	if slot_data:
		var single_slot = slot_data.create_single_slot_data_gamepad_drop(index)
		slot_data.quantity -= 1
		if slot_data.quantity < 1:
			null_out_slots(slot_data)
		inventory_updated.emit(self)
		return single_slot
	else:
		return null


func use_slot_data(index: int):
	if index == -1: # No item assigned to hotbar
		return
	
	var slot_data = inventory_slots[index]
	
	if not slot_data:
		return
	
	if !slot_data.inventory_item.has_method("use"):
		return

	var use_successful : bool = slot_data.inventory_item.use(owner)
	if slot_data.inventory_item.has_method("is_consumable") and use_successful:
		slot_data.quantity -= 1
		if slot_data.quantity < 1:
			null_out_slots(slot_data)
	
	inventory_updated.emit(self)
	
	
# Function to remove a specific item from inventory directly (without picking it up etc)
# Used for example by KEY items to be discarded after using them
func remove_slot_data(slot_data_to_remove: InventorySlotPD):
	var index = inventory_slots.find(slot_data_to_remove,0)
	if index == -1:
		CogitoGlobals.debug_log(true,"cogito_inventory.gd", "Couldn't remove item from inventory as it wasn't found.")
		return
	else:
		print("Removing ", slot_data_to_remove, " at index ", index)
		null_out_slots(slot_data_to_remove)
		inventory_updated.emit(self)


func remove_item_from_stack(slot_data: InventorySlotPD):
	var index = inventory_slots.find(slot_data,0)
	if index == -1:
		CogitoGlobals.debug_log(true,"cogito_inventory.gd", "Couldn't remove item from item stack as it wasn't found.")
		return
	else:
		print("Removing ", slot_data, " at index ", index)
		inventory_slots[index].quantity -= 1
		# What happens if last item of stack is removed.
		if inventory_slots[index].quantity <= 0:
			null_out_slots(slot_data)
			
			# If inventory slot was bind to a quick slot, unbind it.
			var quickslot_index = assigned_quickslots.find(inventory_slots[index],0)
			if quickslot_index > -1:
				unbind_quickslot_by_index.emit(quickslot_index)
				
		inventory_updated.emit(self)


func drop_slot_data(grabbed_slot_data: InventorySlotPD, index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]

	# Dropping an attachment onto a weapon attaches it (Tarkov-style modding).
	if slot_data and grabbed_slot_data.inventory_item is AttachmentItemPD \
			and slot_data.inventory_item is WieldableItemPD:
		return _attach_to_weapon(grabbed_slot_data, slot_data.inventory_item)

	# Dropping a whole ammo stack onto a magazine fills it — hand-loading 30
	# rounds one click at a time is not a game mechanic.
	if slot_data and slot_data.inventory_item is AttachmentItemPD \
			and grabbed_slot_data.inventory_item is AmmoItemPD:
		var loaded := _load_magazine(slot_data.inventory_item, grabbed_slot_data.inventory_item,
				grabbed_slot_data.quantity)
		if loaded > 0:
			grabbed_slot_data.quantity -= loaded
			_send_player_hint("Loaded %d rounds into %s." % [loaded, slot_data.inventory_item.name])
			return null if grabbed_slot_data.quantity <= 0 else grabbed_slot_data
		return grabbed_slot_data

	var return_slot_data : InventorySlotPD
	if slot_data and slot_data.can_fully_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(grabbed_slot_data)
	elif is_enough_space(grabbed_slot_data, index, false):
		# Swap out item
		var item_to_swap = get_item_to_swap(grabbed_slot_data, index)
		
		# If item to swap is being wielded, cancel the swap
		if item_to_swap and item_to_swap.inventory_item and item_to_swap.inventory_item.is_being_wielded:
			print("cogito_inventory.gd: ERROR - cants swap out item thats being wielded.")
			return grabbed_slot_data
		
		null_out_slots(item_to_swap)
		grabbed_slot_data.origin_index = index
		inventory_slots[index] = grabbed_slot_data
		add_adjacent_slots(index)
		return_slot_data = item_to_swap
	else:
		# do nothing, the grabbed slot remains the same
		return grabbed_slot_data
		
	inventory_updated.emit(self)
	return return_slot_data


## Moves up to `count` rounds of `ammo` into `magazine`. Returns how many landed
## — 0 means the pair doesn't match or the magazine is full, so the caller can
## fall through to the next drop rule.
func _load_magazine(magazine: AttachmentItemPD, ammo: InventoryItemPD, count: int = 1) -> int:
	if magazine == null or ammo == null or count <= 0:
		return 0
	if magazine.attachment_slot != AttachmentItemPD.AttachmentSlot.MAGAZINE:
		return 0
	if magazine.magazine_ammo_item == null or magazine.magazine_ammo_item.name != ammo.name:
		return 0
	# A magazine that never recorded its contents is treated as empty the moment
	# someone loads it by hand.
	var rounds: int = maxi(magazine.loaded_rounds, 0)
	var room: int = magazine.magazine_capacity - rounds
	if room <= 0:
		_send_player_hint(magazine.name + " is full.")
		return 0
	var loaded: int = mini(count, room)
	magazine.loaded_rounds = rounds + loaded
	inventory_updated.emit(self)
	return loaded


## Attaches the grabbed AttachmentItemPD onto weapon_item. Returns what stays
## on the cursor: null on success, the previous occupant of the slot (swap),
## or the grabbed slot unchanged when the attach is rejected.
##
## No round bookkeeping here any more: the outgoing magazine leaves with its own
## rounds (WieldableItemPD._take_attachment) and the incoming one brings its own,
## so downsizing can neither spill into the pockets nor be refused for space.
func _attach_to_weapon(grabbed_slot_data: InventorySlotPD, weapon_item: WieldableItemPD) -> InventorySlotPD:
	var attachment := grabbed_slot_data.inventory_item as AttachmentItemPD
	if grabbed_slot_data.quantity != 1 or weapon_item.is_being_wielded or not attachment.fits(weapon_item):
		_send_player_hint("Can't attach " + attachment.name + " to " + weapon_item.name + ".")
		return grabbed_slot_data
	var previous := weapon_item.try_attach(attachment)
	_send_player_hint("Attached: " + attachment.name)
	inventory_updated.emit(self)
	if previous != null:
		var prev_slot := InventorySlotPD.new()
		prev_slot.inventory_item = previous
		prev_slot.quantity = 1
		return prev_slot
	return null


func _send_player_hint(hint: String) -> void:
	if CogitoSceneManager._current_player_node and CogitoSceneManager._current_player_node.player_interaction_component:
		CogitoSceneManager._current_player_node.player_interaction_component.send_hint(null, hint)


func drop_single_slot_data(grabbed_slot_data: InventorySlotPD, index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	
	if not slot_data and is_enough_space(grabbed_slot_data, index, false):
		inventory_slots[index] = grabbed_slot_data.create_single_slot_data(index)
		add_adjacent_slots(index)
		CogitoGlobals.debug_log(true,"cogito_inventory.gd", "drop_single_slot_data(...): grabbed item placed in inventory.")
	elif not slot_data:
		return grabbed_slot_data
	elif slot_data.can_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(grabbed_slot_data.create_single_slot_data(slot_data.origin_index))
		CogitoGlobals.debug_log(true,"cogito_inventory.gd", "drop_single_slot_data(...): grabbed item fully merged with target.")
		#return null
	# Logic for ammo items
	elif slot_data.inventory_item.has_method("update_wieldable_data") and grabbed_slot_data.inventory_item.has_method("is_ammo_item") and slot_data.inventory_item.ammo_item_name == grabbed_slot_data.inventory_item.name:
		CogitoGlobals.debug_log(true,"cogito_inventory.gd", "drop_single_slot_data(...): AmmoItem detected. Attempting to reload target.")
		if slot_data.inventory_item.get_effective_charge_max() - slot_data.inventory_item.charge_current >= grabbed_slot_data.inventory_item.reload_amount:
			if CogitoSceneManager._current_player_node and CogitoSceneManager._current_player_node.player_interaction_component:
				CogitoSceneManager._current_player_node.player_interaction_component.send_hint(
					null,
					"Charging " + slot_data.inventory_item.name + " by " + str(grabbed_slot_data.inventory_item.reload_amount)
				)
			slot_data.inventory_item.add(grabbed_slot_data.inventory_item.reload_amount)
			grabbed_slot_data.quantity -= 1
		else:
			CogitoGlobals.debug_log(true,"cogito_inventory.gd", "drop_single_slot_data(...): AmmoItem detected. Target charge is too high to be reloaded.")

	# Loading a loose magazine: same gesture as charging a weapon, one round per
	# click, gated on the magazine's own caliber.
	elif _load_magazine(slot_data.inventory_item as AttachmentItemPD, grabbed_slot_data.inventory_item) > 0:
		grabbed_slot_data.quantity -= 1

	# Check if grabbed item is a combinable AND check if slot item is the target combine item:
	elif grabbed_slot_data.inventory_item.has_method("is_combinable") and slot_data.inventory_item.name == grabbed_slot_data.inventory_item.target_item_combine :
		var result_slot: InventorySlotPD = grabbed_slot_data.inventory_item.resulting_item
		# Unlike ordinary pickup, crafting must place ALL output before consuming inputs.
		var can_place_result := result_slot == null or _can_place_combined_result(result_slot, slot_data)
		if not can_place_result:
			_send_player_hint("No inventory space for the combined item.")
		else:
			remove_slot_data(slot_data)
			grabbed_slot_data.quantity -= 1
			if result_slot != null:
				pick_up_slot_data(result_slot.duplicate() as InventorySlotPD)
	
	inventory_updated.emit(self)
	
	if grabbed_slot_data.quantity > 0:
		return grabbed_slot_data
	else:
		return null
		
	#if grabbed_slot_data.quantity > 0:
		## Swapping items
		#var item_to_swap = get_item_to_swap(grabbed_slot_data, index)
		#null_out_slots(item_to_swap)
		#return grabbed_slot_data
	#else:
		## Placing items
		#print("cogito_inventory.gd: drop_single_slot_data( grabbed item name=", grabbed_slot_data.inventory_item.name, ", ", index, "): Placing items reached.")
		#return null


## Preview the freed target and complete output without touching live slot data,
## emitting pickup signals or equipping preview items. Native fit rules still apply.
func _can_place_combined_result(result: InventorySlotPD, target: InventorySlotPD) -> bool:
	if result.inventory_item == null or result.quantity <= 0:
		return false
	var preview := duplicate(false) as CogitoInventory
	preview.inventory_slots = inventory_slots.duplicate()
	preview.owner = owner
	preview.null_out_slots(target)
	if not result.inventory_item.is_stackable:
		return preview.can_pick_up_slot_data(result)
	if result.inventory_item.stack_size <= 0:
		return false
	var remaining := result.quantity
	var seen: Array[InventorySlotPD] = []
	for slot in preview.inventory_slots:
		if slot == null or seen.has(slot):
			continue
		seen.append(slot)
		if slot.inventory_item == result.inventory_item or slot.inventory_item.name == result.inventory_item.name:
			remaining -= maxi(0, slot.inventory_item.stack_size - slot.quantity)
			if remaining <= 0:
				return true
	for index in preview.inventory_slots.size():
		if preview.inventory_slots[index] == null and preview.is_enough_space(result, index, true):
			var placed := result.duplicate() as InventorySlotPD
			placed.origin_index = index
			preview.inventory_slots[index] = placed
			preview.add_adjacent_slots(index)
			remaining -= result.inventory_item.stack_size
			if remaining <= 0:
				return true
	return false


func pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	if not slot_data or not slot_data.inventory_item or slot_data.quantity <= 0:
		return false
		
	var original_quantity = slot_data.quantity
	
	# Step 1: Try to merge with existing stacks (only if the item is stackable)
	if slot_data.inventory_item.is_stackable:
		for index in inventory_slots.size():
			var current_slot = inventory_slots[index]
			# Check if we can merge with this slot (same item name/resource)
			if current_slot and (current_slot.inventory_item == slot_data.inventory_item or current_slot.inventory_item.name == slot_data.inventory_item.name):
				var max_stack = current_slot.inventory_item.stack_size
				if current_slot.quantity < max_stack:
					var room = max_stack - current_slot.quantity
					var to_add = min(room, slot_data.quantity)
					current_slot.quantity += to_add
					slot_data.quantity -= to_add
					if slot_data.quantity == 0:
						inventory_updated.emit(self)
						return true
						
	# Step 2: Try to place remaining in empty slots
	for index in inventory_slots.size():
		if not inventory_slots[index] and is_enough_space(slot_data, index, true):
			# If the item is stackable, we might split it if it exceeds stack_size
			if slot_data.inventory_item.is_stackable and slot_data.quantity > slot_data.inventory_item.stack_size:
				var new_slot = _prepare_slot_for_inventory(slot_data)
				new_slot.origin_index = index
				new_slot.quantity = slot_data.inventory_item.stack_size
				inventory_slots[index] = new_slot
				add_adjacent_slots(index)
				slot_data.quantity -= slot_data.inventory_item.stack_size
				picked_up_new_inventory_item.emit(new_slot)
			else:
				# Fits entirely in this empty slot
				var new_slot = _prepare_slot_for_inventory(slot_data)
				new_slot.origin_index = index
				inventory_slots[index] = new_slot
				add_adjacent_slots(index)
				slot_data.quantity = 0
				inventory_updated.emit(self)
				picked_up_new_inventory_item.emit(new_slot)
				return true
				
	# If we got here, slot_data.quantity might have decreased but is still > 0.
	# Or it could be unchanged.
	inventory_updated.emit(self)
	
	# Return true if we successfully picked up at least 1 item
	if slot_data.quantity < original_quantity:
		return true
		
	# If we picked up nothing at all
	var _p: Node = CogitoSceneManager._current_player_node
	if is_instance_valid(_p) and _p.get("player_interaction_component") != null:
		_p.player_interaction_component.send_hint(null, "Unable to pick up item.")
	return false


func _prepare_slot_for_inventory(slot_data: InventorySlotPD) -> InventorySlotPD:
	var new_slot := slot_data.duplicate() as InventorySlotPD
	if new_slot == null or new_slot.inventory_item == null:
		return new_slot
	var wieldable_item := new_slot.inventory_item as WieldableItemPD
	if wieldable_item != null and not wieldable_item.is_stackable:
		new_slot.inventory_item = _duplicate_wieldable_item_for_inventory(wieldable_item)
		return new_slot
	# Magazines hold rounds, so each one must be its own instance — load() hands
	# out a single shared resource per .tres, and two magazines of the same type
	# would otherwise share a round count. Other attachment types are stateless.
	var attachment := new_slot.inventory_item as AttachmentItemPD
	if attachment != null and attachment.attachment_slot == AttachmentItemPD.AttachmentSlot.MAGAZINE:
		new_slot.inventory_item = attachment.duplicate_instance()
	return new_slot


func _duplicate_wieldable_item_for_inventory(source_item: WieldableItemPD) -> WieldableItemPD:
	var item_copy := source_item.duplicate(false) as WieldableItemPD
	if item_copy == null:
		return source_item
	item_copy.set_firearm_mechanical_state(source_item.get_firearm_mechanical_state())
	# duplicate(false) shares nested Dictionaries by reference — deep-copy so
	# each weapon instance owns its attachment set.
	item_copy.set_attachments(source_item.get_attachments())
	item_copy.player_interaction_component = null
	item_copy.is_being_wielded = false
	item_copy.wielded_item = null
	return item_copy


## LootComponent - Gets all items in inventory
func get_all_items() -> Array[InventoryItemPD]:
	var result: Array[InventoryItemPD] = []
	for slot in inventory_slots:
		if slot != null:
			result.append(slot.inventory_item)
	return result


# Function to attempt to take all the items in a given inventory.
func take_all_items(target_inventory: CogitoInventory):
	for slot in inventory_slots:
		if slot != null:
			var original_quantity = slot.quantity
			var temp_slot = slot.duplicate()
			if target_inventory.pick_up_slot_data(temp_slot):
				if temp_slot.quantity <= 0:
					print("Grabbed all of ", slot.inventory_item.name)
					remove_slot_data(slot) #Empty the slot
				else:
					print("Grabbed partial ", slot.inventory_item.name, ", remaining: ", temp_slot.quantity)
					slot.quantity = temp_slot.quantity
				force_inventory_update()


func force_inventory_update():
	print("Forced inventory update: ", self)
	inventory_updated.emit(self)


func add_adjacent_slots(index: int):
	if not grid:
		return
	if index < 0 or index >= inventory_slots.size():
		return
	var slot = inventory_slots[index]
	if slot == null:
		return
	var size = slot.get_effective_size()
	for x in size.x:
		for y in size.y:
			var idx: int = index + x + (y * inventory_size.x)
			if idx < 0 or idx >= inventory_slots.size():
				continue
			inventory_slots[idx] = slot


# check if an item either has free slots to occupy or can swap one item out
func is_enough_space(grabbed_slot_data: InventorySlotPD, to_place_index: int, pickup: bool) -> bool:
	var swap_origin = -1
	var size = grabbed_slot_data.get_effective_size() if grid else Vector2i(1,1)
	# check outside of y bounds
	if (to_place_index + (size.x-1) + ((size.y-1)*inventory_size.x)) >= inventory_slots.size():
		return false
	var right_edge: int = to_place_index + size.x-1
	# check row does not shift
	if (int(to_place_index / inventory_size.x) != int(right_edge / inventory_size.x)):
		return false
	for x in size.x:
		for y in size.y:
			var adj_item = inventory_slots[to_place_index + x + (y*inventory_size.x)]
			if not adj_item:
				continue
			elif pickup: # if picking up an item, swap logic should not be invoked
				return false
			elif swap_origin == -1 and adj_item.origin_index != -1:
				swap_origin = adj_item.origin_index	
			elif adj_item.origin_index != swap_origin and adj_item.origin_index != -1:
				return false
	return true


func get_item_to_swap(grabbed_slot_data: InventorySlotPD, to_place_index: int):
	var size = grabbed_slot_data.get_effective_size() if grid else Vector2i(1,1)
	for x in size.x:
		for y in size.y:
			var adj_item = inventory_slots[to_place_index + x + (y*inventory_size.x)]
			if not adj_item:
				continue
			if adj_item.origin_index != -1:
				return adj_item


## Returns whether the given item fits in inventory
func can_pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	if not slot_data or not slot_data.inventory_item or slot_data.quantity <= 0:
		return false
	for index in inventory_slots.size():
		if inventory_slots[index] and inventory_slots[index].can_fully_merge_with(slot_data):
			return true
	for index in inventory_slots.size():
		if not inventory_slots[index] and is_enough_space(slot_data, index, true):
			return true
	return false
