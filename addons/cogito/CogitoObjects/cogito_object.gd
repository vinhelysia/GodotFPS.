@tool
@icon("res://addons/cogito/Assets/Graphics/Editor/Icon_CogitoObject.svg")
extends Node3D
class_name CogitoObject

signal damage_received(damage_value:float)
signal object_exits_tree()

@export var cogito_name : String = self.name
## Name that will displayed when interacting. Leave blank to hide
@export var display_name : String

enum PromptPositionMode{
	ORIGIN, ## at the objects origin point. Recommended for smaller objects.
	MARKER, ## at the position of an assigned Marker3D node. Will throw an error if no marker is assigned. Recommended for big objects/doors.
	AABB_CENTER, ## at the center of the calculated AABoundingBox. Works well but has a slight performance impact. 
}
## This sets where interaction prompt gets displayed on the object. 
@export var prompt_pos_mode : PromptPositionMode = PromptPositionMode.ORIGIN
@export var prompt_marker : Marker3D


@export_group("Object Size and Shape")
## Used for debug visualization and object-size estimation (e.g., carry/drag behavior).
## Not used for inventory item dropping — use InventoryItemPD.item_drop_size for drop clearance.
@export var custom_aabb : AABB = AABB():
	set(new_aabb):
		custom_aabb = new_aabb
		if show_aabb_debug_shape:
			CogitoGlobals.draw_box_aabb(get_aabb(), Color.AQUA)

## Shows the objects AABB debug shape in Editor.
@export var show_aabb_debug_shape : bool = false:
	set(new_show_debug_shape):
		show_aabb_debug_shape = new_show_debug_shape
		if Engine.is_editor_hint() and show_aabb_debug_shape:
			CogitoGlobals.draw_box_aabb(get_aabb(), Color.AQUA)
		else:
			CogitoGlobals.clear_debug_shape()

var interaction_nodes : Array[Node]
var cogito_properties : CogitoProperties = null
var properties : int
var spawned_loot_item: bool = false





func _ready():
	self.add_to_group("interactable")
	self.add_to_group("Persist") #Adding object to group for persistence
	find_interaction_nodes()
	find_cogito_properties()


func get_aabb():
	if custom_aabb:
		return custom_aabb
		
	var aabb : AABB = AABB()
	
	for child in find_children("*", "MeshInstance3D", true, false):
		if child.visible:
			aabb = aabb.merge(child.transform * child.get_aabb())
	
	return aabb


# Future method to set object state when a scene state file is loaded.
func set_state():	
	#TODO: Find a way to possibly save health of health attribute.
	find_cogito_properties()
	
	if spawned_loot_item:
		add_to_group("spawned_loot_items")
		
	pass


func find_interaction_nodes():
	interaction_nodes = find_children("","InteractionComponent",true) #Grabs all attached interaction components


func find_cogito_properties():
	var property_nodes = find_children("","CogitoProperties",true) #Grabs all attached property components
	if property_nodes:
		cogito_properties = property_nodes[0]


# Function to handle persistence and saving
func save():
	if self.is_in_group("spawned_loot_items"):
		spawned_loot_item = true
		
	var node_data = {
		"filename" : get_scene_file_path(),
		"parent" : get_parent().get_path(),
		"interaction_nodes" : interaction_nodes,
		"pos_x" : position.x,
		"pos_y" : position.y,
		"pos_z" : position.z,
		"rot_x" : rotation.x,
		"rot_y" : rotation.y,
		"rot_z" : rotation.z,
		"spawned_loot_item" : spawned_loot_item,
	}

	var pickup_component := _get_pickup_component()
	if pickup_component and pickup_component.slot_data:
		var pickup_slot_data := _duplicate_slot_data_for_pickup_state(pickup_component.slot_data)
		node_data["pickup_slot_data"] = pickup_slot_data
		if pickup_slot_data and pickup_slot_data.inventory_item is WieldableItemPD:
			var wieldable_item := pickup_slot_data.inventory_item as WieldableItemPD
			node_data["pickup_item_charge"] = wieldable_item.charge_current
			node_data["pickup_firearm_mechanical_state"] = wieldable_item.get_firearm_mechanical_state()
			node_data["pickup_attachments"] = wieldable_item.get_attachments()

	# If the node is a RigidBody3D, then save the physics properties of it
	var rigid_body = find_rigid_body()
	if rigid_body:
		node_data["linear_velocity_x"] = rigid_body.linear_velocity.x
		node_data["linear_velocity_y"] = rigid_body.linear_velocity.y
		node_data["linear_velocity_z"] = rigid_body.linear_velocity.z
		node_data["angular_velocity_x"] = rigid_body.angular_velocity.x
		node_data["angular_velocity_y"] = rigid_body.angular_velocity.y
		node_data["angular_velocity_z"] = rigid_body.angular_velocity.z
	return node_data


func find_rigid_body() -> RigidBody3D:
	var current = self
	while current:
		if current is RigidBody3D:
			return current as RigidBody3D
		current = current.get_parent()
	return null


func _get_pickup_component() -> PickupComponent:
	for interaction_node in interaction_nodes:
		if interaction_node is PickupComponent:
			return interaction_node as PickupComponent
	var pickup_nodes := find_children("", "PickupComponent", true, false)
	if pickup_nodes.size() > 0:
		return pickup_nodes[0] as PickupComponent
	return null


func _duplicate_slot_data_for_pickup_state(slot_data: InventorySlotPD) -> InventorySlotPD:
	var slot_copy := slot_data.duplicate() as InventorySlotPD
	if slot_copy == null or slot_copy.inventory_item == null:
		return slot_copy
	var wieldable_item := slot_copy.inventory_item as WieldableItemPD
	if wieldable_item != null:
		var item_copy := wieldable_item.duplicate(false) as WieldableItemPD
		if item_copy != null:
			item_copy.set_firearm_mechanical_state(wieldable_item.get_firearm_mechanical_state())
			item_copy.set_attachments(wieldable_item.get_attachments())
			slot_copy.inventory_item = item_copy
	return slot_copy


func _on_body_entered(body: Node) -> void:
	# Using this check to only call interactions on other Cogito Objects. #TODO: could be a better check...
	if body.has_method("save") and cogito_properties:
		cogito_properties.start_reaction_threshold_timer(body)


func _on_body_exited(body: Node) -> void:
	# Using this check to only call interactions on other Cogito Objects. #TODO: could be a better check...
	if body.has_method("save") and cogito_properties:
		cogito_properties.check_for_reaction_timer_interrupt(body)


func _exit_tree() -> void:
	object_exits_tree.emit()
