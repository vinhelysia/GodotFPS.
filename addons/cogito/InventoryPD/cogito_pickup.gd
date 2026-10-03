extends RigidBody3D

@export var slot_data : InventorySlotPD:
	set(value):
		slot_data = value
		_update_interaction_text()
@export var interaction_text : String = "Pick up"

var _original_interaction_text : String = ""

func _ready():
	self.add_to_group("Persist")
	if _original_interaction_text == "":
		_original_interaction_text = interaction_text
	_update_interaction_text()

func _update_interaction_text():
	if _original_interaction_text == "":
		_original_interaction_text = interaction_text
	if slot_data and slot_data.quantity > 1:
		interaction_text = tr(_original_interaction_text) + " x" + str(slot_data.quantity)
	else:
		interaction_text = tr(_original_interaction_text)

func interact(body):
	var original_quantity = slot_data.quantity
	var pick_up_success = body.get_parent().inventory_data.pick_up_slot_data(slot_data)
	var picked_up_amount = original_quantity - slot_data.quantity
	
	if picked_up_amount > 0:
		Audio.play_sound(slot_data.inventory_item.sound_pickup)
		if slot_data.quantity <= 0:
			body.send_hint(slot_data.inventory_item.icon, slot_data.inventory_item.name + " added to inventory.")
			queue_free()
		else:
			body.send_hint(slot_data.inventory_item.icon, "Picked up " + str(picked_up_amount) + " " + slot_data.inventory_item.name)
			_update_interaction_text()
	else:
		body.send_hint(slot_data.inventory_item.icon, "Unable to pick up " + slot_data.inventory_item.name)


func get_item_type() -> int:
	if slot_data and slot_data.inventory_item:
		return slot_data.inventory_item.item_type
	else:
		return -1

# Function to handle persistency and saving
func save():
	var node_data = {
		"filename" : get_scene_file_path(),
		"parent" : get_parent().get_path(),
		"slot_data" : slot_data,
		"item_charge" : slot_data.inventory_item.charge_current,
		"pos_x" : position.x,
		"pos_y" : position.y,
		"pos_z" : position.z,
		"rot_x" : rotation.x,
		"rot_y" : rotation.y,
		"rot_z" : rotation.z,
		
	}
	if slot_data and slot_data.inventory_item is WieldableItemPD:
		var wieldable_item := slot_data.inventory_item as WieldableItemPD
		node_data["pickup_item_charge"] = wieldable_item.charge_current
		node_data["pickup_firearm_mechanical_state"] = wieldable_item.get_firearm_mechanical_state()
		node_data["pickup_attachments"] = wieldable_item.get_attachments()
	return node_data
