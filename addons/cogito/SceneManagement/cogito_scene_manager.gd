extends Node

## Emitted when a fade finishes
signal fade_finished

## Emitted when GUI options changed
signal update_gui

# Used to set active save slot. This could be set/modified, when selecting a save slot from the MainMenu.
@export var _active_slot : String = "A"

# Cached World State Dictionary, used for checks while game is running
@export var _current_world_dict : Dictionary

# Variables for player state
@export var _current_player_node : Node
@export var _player_state : CogitoPlayerState
# Used to pass a screenshot to the player state when saved. This is created by the TabMenu/PauseMenu
@export var _screenshot_to_save : Image

# Variables & Signals for Player sitting
@export var _current_sittable_node : Node
signal sit_requested(Node)
signal stand_requested()
signal seat_move_requested(Node)

# Variables for scene state
@export var _current_scene_name : String
@export var _current_scene_path : String
@export var _scene_state : CogitoSceneState
@warning_ignore("unused_private_class_variable")
@export var _current_scene_root_node : Node

enum CogitoSceneLoadMode {TEMP, LOAD_SAVE, RESET, FRESH_WITH_PLAYER}
@export var scene_load_mode: CogitoSceneLoadMode

@export var cogito_state_dir : String = "user://"

@onready var cogito_scene_state_prefix : String = CogitoGlobals.scene_state_prefix
@onready var cogito_player_state_prefix : String = CogitoGlobals.player_state_prefix

@onready var default_fade_duration : float = CogitoGlobals.default_transition_duration
@export var fade_panel : Panel = null

var is_currently_loading : bool = false

const SAVE_ROOT := "user://"
const MAX_SLOT_NAME_LEN := 64
const MAX_SCENE_NAME_LEN := 128
const SaveCommit := preload("res://addons/cogito/SceneManagement/save_commit.gd")

# Keys applied via Node.set during scene restore. Class-specific; must match save() emitters.
# Structural keys (filename/parent/pos_*/rot_*) are handled separately and never go through set().
const _SAVE_SKIP_KEYS := {
	"filename": true, "parent": true, "node_path": true,
	"pos_x": true, "pos_y": true, "pos_z": true,
	"rot_x": true, "rot_y": true, "rot_z": true,
	"item_charge": true, "pickup_slot_data": true, "pickup_item_charge": true,
	"pickup_firearm_mechanical_state": true, "pickup_attachments": true, "slot_data": true,
	"linear_velocity_x": true, "linear_velocity_y": true, "linear_velocity_z": true,
	"angular_velocity_x": true, "angular_velocity_y": true, "angular_velocity_z": true,
	"global_pos_x": true, "global_pos_y": true, "global_pos_z": true,
}

const _PIC_ALLOWLIST := {
	"equipped_wieldable_item": true,
	"is_wielding": true,
	"wieldable_was_on": true,
}

const _ALLOW_HOSTILE_NPC := {
	"patrol_path_nodepath": true, "saved_enemy_state": true,
	"equipment": true, "pockets": true, "equipped_wieldable": true,
	"equipped_weapon_data": true, "saved_ammo": true, "kit_from_save": true,
	"health_current": true, "health_max": true,
}
const _ALLOW_COGITO_NPC := {
	"patrol_path_nodepath": true, "saved_enemy_state": true,
}
const _ALLOW_CORPSE := {
	"display_name": true, "inventory_data": true, "interaction_nodes": true,
	"animation_player": true, "equipment": true,
}
const _ALLOW_CONTAINER := {
	"display_name": true, "inventory_data": true, "interaction_nodes": true,
	"animation_player": true,
}
const _ALLOW_LOOTABLE := {
	"display_name": true, "inventory_data": true, "interaction_nodes": true,
	"animation_player": true, "start_time": true, "end_time": true,
	"time_left": true, "initial_spawn": true,
}
const _ALLOW_OBJECT := {
	"interaction_nodes": true, "spawned_loot_item": true,
}
const _ALLOW_DOOR := {"is_locked": true, "is_open": true}
const _ALLOW_SWITCH := {"is_on": true, "is_holding_item": true}
const _ALLOW_BUTTON := {"has_been_used": true}
const _ALLOW_KEYPAD := {"is_locked": true, "entered_code": true}
const _ALLOW_PRESSURE := {"is_activated": true, "is_usable": true}
const _ALLOW_SITTABLE := {
	"is_occupied": true, "occupant_id": true, "physics_sittable": true,
	"interaction_text": true, "interaction_component_state": true,
}
const _ALLOW_VENDOR := {"amount_remaining": true, "is_dispensing": true}
const _ALLOW_TURNWHEEL := {"has_been_turned": true}
const _ALLOW_SNAP := {"is_active": true, "is_holding_object": true}
const _ALLOW_QUEST_UPDATER := {"has_been_triggered": true}


#region SAVE PATH / LOAD HARDENING
func is_valid_slot_name(slot_name: String) -> bool:
	return _is_valid_save_token(slot_name, MAX_SLOT_NAME_LEN)


func is_valid_scene_name(scene_name: String) -> bool:
	return _is_valid_save_token(scene_name, MAX_SCENE_NAME_LEN)


func _is_valid_save_token(token: String, max_len: int) -> bool:
	if token.is_empty() or token.length() > max_len:
		return false
	if token.begins_with(".") or token.contains(".."):
		return false
	# Reject path separators, absolute roots, nulls, and traversal fragments.
	if token.contains("/") or token.contains("\\") or token.contains(":") or token.contains(String.chr(0)):
		return false
	if token.contains("user://") or token.contains("res://") or token.begins_with("//"):
		return false
	for i in token.length():
		var code := token.unicode_at(i)
		var is_az := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit := code >= 48 and code <= 57
		var is_extra := code == 95 or code == 45 or code == 32 # _ - space
		if not (is_az or is_digit or is_extra):
			return false
	return true


func player_state_path(slot_name: String) -> String:
	return _read_slot_directory(slot_name).path_join(str(cogito_player_state_prefix) + ".res")


func scene_state_path(slot_name: String, scene_name: String) -> String:
	return _read_slot_directory(slot_name).path_join(str(cogito_scene_state_prefix) + scene_name + ".res")


func _read_slot_directory(slot_name: String) -> String:
	var directory := slot_dir_path(slot_name)
	return directory if slot_name == "temp" else SaveCommit.current_directory(directory)


func slot_dir_path(slot_name: String) -> String:
	return str(cogito_state_dir).path_join(slot_name)


func _coerce_player_state(res: Resource) -> CogitoPlayerState:
	if res is CogitoPlayerState:
		return res as CogitoPlayerState
	if res != null:
		push_warning("CSM: rejected player state resource of type " + str(res.get_class()))
	return null


func _coerce_scene_state(res: Resource) -> CogitoSceneState:
	if res is CogitoSceneState:
		return res as CogitoSceneState
	if res != null:
		push_warning("CSM: rejected scene state resource of type " + str(res.get_class()))
	return null


func _allowlist_for_object(obj: Object) -> Dictionary:
	if obj == null:
		return {}
	if obj is HostileNPC:
		return _ALLOW_HOSTILE_NPC
	if obj is CorpseContainer:
		return _ALLOW_CORPSE
	if obj is LootableContainer or obj is LootDropContainer:
		return _ALLOW_LOOTABLE
	if obj is CogitoContainer:
		return _ALLOW_CONTAINER
	if obj is CogitoNPC:
		return _ALLOW_COGITO_NPC
	if obj is CogitoObject:
		return _ALLOW_OBJECT
	if obj is CogitoBodyDrag:
		return _ALLOW_OBJECT
	if obj is CogitoDoor:
		return _ALLOW_DOOR
	if obj is CogitoSwitch:
		return _ALLOW_SWITCH
	if obj is CogitoButton:
		return _ALLOW_BUTTON
	if obj is CogitoKeypad:
		return _ALLOW_KEYPAD
	if obj is CogitoPressureplate:
		return _ALLOW_PRESSURE
	if obj is CogitoSittable:
		return _ALLOW_SITTABLE
	if obj is CogitoSnapSlot:
		return _ALLOW_SNAP
	if obj is CogitoQuestUpdater:
		return _ALLOW_QUEST_UPDATER
	# Types without class_name: script path only.
	var script = obj.get_script()
	var script_path := str(script.resource_path) if script else ""
	if script_path.ends_with("cogito_vendor.gd"):
		return _ALLOW_VENDOR
	if script_path.ends_with("cogito_turnwheel.gd"):
		return _ALLOW_TURNWHEEL
	if script_path.ends_with("cogito_pickup.gd"):
		return _ALLOW_OBJECT
	push_warning("CSM: no save allowlist for " + obj.get_class() + " (" + script_path + "); skipping property restore")
	return {}


func _apply_allowed_props(target: Object, data: Dictionary) -> void:
	if target == null or data.is_empty():
		return
	var allow := _allowlist_for_object(target)
	if allow.is_empty():
		return
	for key in data.keys():
		var k := str(key)
		if _SAVE_SKIP_KEYS.has(k):
			continue
		if not allow.has(k):
			push_warning("CSM: blocked save key '" + k + "' on " + str(target))
			continue
		target.set(k, data[key])


func _is_node_in_current_scene(node: Node) -> bool:
	if node == null:
		return false
	var current := get_tree().current_scene
	if current == null:
		return false
	return node == current or current.is_ancestor_of(node)


func _resolve_scene_local_node(path_value) -> Node:
	if path_value == null:
		return null
	var path_str := str(path_value)
	if path_str.is_empty() or path_str == "/root" or path_str == "/root/":
		push_warning("CSM: rejected node path " + path_str)
		return null
	if path_str.contains(".."):
		push_warning("CSM: rejected traversal node path " + path_str)
		return null
	var node := get_node_or_null(NodePath(path_str))
	if node == null:
		return null
	if not _is_node_in_current_scene(node):
		push_warning("CSM: node path outside current scene: " + path_str)
		return null
	return node


func _safe_instantiate_saved_scene(filename_value) -> Node:
	if typeof(filename_value) != TYPE_STRING:
		push_warning("CSM: saved filename is not a string")
		return null
	var filename: String = filename_value
	if not filename.begins_with("res://") or filename.contains(".."):
		push_warning("CSM: rejected saved scene path " + filename)
		return null
	if not (filename.ends_with(".tscn") or filename.ends_with(".scn")):
		push_warning("CSM: rejected saved scene extension " + filename)
		return null
	if not ResourceLoader.exists(filename):
		push_warning("CSM: saved scene missing " + filename)
		return null
	var packed = load(filename)
	if not (packed is PackedScene):
		push_warning("CSM: saved path is not a PackedScene: " + filename)
		return null
	var inst = (packed as PackedScene).instantiate()
	if inst == null or not (inst is Node):
		push_warning("CSM: failed to instantiate " + filename)
		return null
	return inst as Node
#endregion


func _ready() -> void:
	_player_state = get_existing_player_state(_active_slot) # Setting active slot (per default it's A)
	_scene_state = get_existing_scene_state(_active_slot)

	reset_scene_states()
	instantiate_fade_panel()


func switch_active_slot_to(slot_name:String) -> void:
	if not is_valid_slot_name(slot_name):
		push_warning("CSM: refused invalid slot name '" + slot_name + "'")
		return
	_player_state = null
	_player_state = get_existing_player_state(slot_name)
	if !_player_state:
		CogitoGlobals.debug_log(true,"CSM","Existing player state for slot " + slot_name + " not found.")
	_active_slot = slot_name
	CogitoGlobals.debug_log(true,"CSM","Active slot switched to " + _active_slot)


func get_existing_player_state(passed_slot) -> CogitoPlayerState:
	if not is_valid_slot_name(str(passed_slot)):
		push_warning("CSM: invalid player-state slot '" + str(passed_slot) + "'")
		return null
	var player_state_file : String = player_state_path(str(passed_slot))
	CogitoGlobals.debug_log(true,"CSM","Looking for file: "+ player_state_file)
	if ResourceLoader.exists(player_state_file):
		CogitoGlobals.debug_log(true,"CSM","CSM: Get existing player state: found for slot "+ str(passed_slot))
		return _coerce_player_state(ResourceLoader.load(player_state_file, "", ResourceLoader.CACHE_MODE_IGNORE))
	else:
		CogitoGlobals.debug_log(true,"CSM","Get existing player state: No player state found for slot "+ str(passed_slot))
		return null


func get_existing_scene_state(passed_slot) -> CogitoSceneState:
	if not is_valid_slot_name(str(passed_slot)):
		push_warning("CSM: invalid scene-state slot '" + str(passed_slot) + "'")
		return null
	var current_scene : String = ""
	if _player_state:
		current_scene = _player_state.player_current_scene
	if current_scene.is_empty() or not is_valid_scene_name(current_scene):
		CogitoGlobals.debug_log(true,"CSM","Get existing scene state: invalid/empty scene name")
		return null
	var scene_state_file : String = scene_state_path(str(passed_slot), current_scene)
	CogitoGlobals.debug_log(true,"CSM","Looking for file: "+ scene_state_file)
	if ResourceLoader.exists(scene_state_file):
		CogitoGlobals.debug_log(true,"CSM","Get existing scene state: found for slot "+ str(passed_slot))
		return _coerce_scene_state(ResourceLoader.load(scene_state_file, "", ResourceLoader.CACHE_MODE_IGNORE))
	else:
		CogitoGlobals.debug_log(true,"CSM","Get existing scene state: No scene state found for slot "+ str(passed_slot))
		return null


func loading_saved_game(passed_slot: String, current_scene_name: String = "") -> void:
	CogitoGlobals.debug_log(true,"CSM","CSM: Loading saved game from slot "+ passed_slot)
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: loading_saved_game refused invalid slot '" + passed_slot + "'")
		return
	if !_player_state or !_player_state.state_exists(passed_slot):
		CogitoGlobals.debug_log(true,"CSM","CSM: Player state of passed slot doesn't exist.")
		return

	var loaded_ps := _coerce_player_state(_player_state.load_state(passed_slot))
	if loaded_ps == null:
		push_warning("CSM: player state load rejected for slot " + passed_slot)
		return
	_player_state = loaded_ps

	if current_scene_name == "":
		current_scene_name = get_tree().get_current_scene().get_name()

	CogitoGlobals.debug_log(true,"CSM","Current scene detected as "+ current_scene_name)
	# Check if player is currently in the same scene as in the game that is being attempted to load:
	if _current_scene_name == _player_state.player_current_scene:
		# ABOVE used to be: get_tree().current_scene.get_name() ==
		CogitoGlobals.debug_log(true,"CSM","Player state for slot "+ passed_slot+ " is from current scene.")
		# Do a simple scene state load and player state load.
		load_scene_state(_player_state.player_current_scene, passed_slot)
		load_player_state(_current_player_node, passed_slot)
	else:
		# Transition to target scene and then attempt to load the saved game again.
		CogitoGlobals.debug_log(true,"CSM","Player state for slot "+ passed_slot + " is in different scene (" + _player_state.player_current_scene + "). Transitioning...")
		var scene_path := str(_player_state.player_current_scene_path)
		if not scene_path.begins_with("res://") or scene_path.contains("..") or not (scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")):
			push_warning("CSM: refused non-canonical player_current_scene_path " + scene_path)
			return
		load_next_scene(scene_path, "", passed_slot, CogitoSceneLoadMode.LOAD_SAVE)


#region PLAYER SAVE HANDLING
func load_player_state(player, passed_slot:String) -> void:
	CogitoGlobals.debug_log(true,"CSM","Loading player state...")
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: load_player_state refused invalid slot '" + passed_slot + "'")
		return
	if player == null:
		push_warning("CSM: load_player_state called with null player")
		return
	if !_player_state:
		_player_state = CogitoPlayerState.new()
	if _player_state and _player_state.state_exists(passed_slot):
		CogitoGlobals.debug_log(true,"CSM","Player State in slot " + passed_slot + " exists. Loading " + str(_player_state))
		var loaded_ps := _coerce_player_state(_player_state.load_state(passed_slot))
		if loaded_ps == null:
			push_warning("CSM: load_player_state rejected non-CogitoPlayerState for slot " + passed_slot)
			return
		_player_state = loaded_ps

		# Applying the save state to player node.
		player.inventory_data = _player_state.player_inventory # Loading inventory data from saved player state to current player inventory.
		if player.inventory_data:
			player.inventory_data.owner = player

		if _player_state.get("player_equipment") != null:
			player.equipment = _player_state.player_equipment
		else:
			player.equipment = CogitoEquipment.new()

		player.inventory_data.assigned_quickslots = _player_state.player_quickslots
		# Rebuild quickslots from equipment slots as single source of truth
		for slot_id in CogitoEquipment.EQUIPMENT_ORIGIN:
			var slot_data = player.equipment.get_equipped(slot_id)
			var quickslot_idx = -10 - CogitoEquipment.EQUIPMENT_ORIGIN[slot_id]
			if slot_data:
				player.inventory_data.assigned_quickslots[quickslot_idx] = slot_data
			else:
				player.inventory_data.assigned_quickslots[quickslot_idx] = null

		# Loading quests from player state with proper initialization:
		CogitoQuestManager.active.clear_group()
		for quest in _player_state.player_active_quests:
			quest.start(true)  # Initialize active quests (mute audio)
			CogitoQuestManager.active.add_quest(quest)

		var _temp_active_quest_dir = _player_state.player_active_quest_progression
		for entry in _temp_active_quest_dir:
			for quest in CogitoQuestManager.active.quests:
				if quest.quest_name == entry:
					quest.quest_counter = _temp_active_quest_dir[entry]
					CogitoGlobals.debug_log(true,"CSM", "Loading active quests. Quest " + quest.quest_name + " found. Setting progression to " + str(_temp_active_quest_dir[entry]) )


		CogitoQuestManager.completed.clear_group()
		for quest in _player_state.player_completed_quests:
			quest.complete(true)  # Initialize completed quests (mute audio)
			CogitoQuestManager.completed.add_quest(quest)

		CogitoQuestManager.failed.clear_group()
		for quest in _player_state.player_failed_quests:
			quest.failed(true)  # Initialize failed quests (mute audio)
			CogitoQuestManager.failed.add_quest(quest)


		# Loading saved charges of wieldables
		var array_of_wieldable_charges = _player_state.saved_wieldable_charges
		for data in array_of_wieldable_charges:
			if data == null:
				continue
			else:
				for slot in player.inventory_data.inventory_slots:
					if slot and slot.inventory_item and data.has("resource") and slot.inventory_item == data["resource"]:
						CogitoGlobals.debug_log(true,"CSM","Match found: " + str(slot.inventory_item))
						var wieldable_item := slot.inventory_item as WieldableItemPD
						if wieldable_item:
							_restore_wieldable_saved_state(wieldable_item,
									data.get("firearm_mechanical_state", {}),
									data.get("charge_current", null))
							if data.has("attachments"):
								wieldable_item.set_attachments(data["attachments"])

		player.inventory_data.force_inventory_update()

		# New way of loading player attributes:
		var loaded_attribute_data = _player_state.player_attributes
		for attribute in loaded_attribute_data:
			if not player.player_attributes.has(attribute):
				push_warning("CSM: unknown player attribute key '" + str(attribute) + "'")
				continue
			var attribute_data: Vector2 = loaded_attribute_data[attribute]
			var cur_value = attribute_data.x
			var max_value = attribute_data.y
			player.player_attributes[attribute].set_attribute(cur_value, max_value)

		# Loading player currencies
		var loaded_currency_data = _player_state.player_currencies
		for currency in loaded_currency_data:
			if not player.player_currencies.has(currency):
				push_warning("CSM: unknown player currency key '" + str(currency) + "'")
				continue
			var currency_data: Vector2 = loaded_currency_data[currency]
			var cur_value = currency_data.x
			var max_value = currency_data.y
			player.player_currencies[currency].set_currency(cur_value, max_value)

		# Loading world dictionary
		var local_dict_copy : Dictionary = _player_state.world_dictionary.duplicate(true)
		_current_world_dict.clear()
		for entry in local_dict_copy:
			_current_world_dict.get_or_add(entry, local_dict_copy[entry])


		player.global_position = _player_state.player_position
		player.body.global_rotation = _player_state.player_rotation
		player.try_crouch = _player_state.player_try_crouch
		# important: ensures the player isn't crouching on game load, regardless
		# of whether the option "Toggle Crouching" is set to OFF or ON
		player.is_crouching = player.try_crouch

		## Loading player sitting state
		_player_state.load_sitting_state(player)
		_player_state.load_collision_shapes(player)
		_player_state.load_node_transforms(player)

		# Loading player interaction component state (allowlisted keys only)
		var player_interaction_component_state = _player_state.interaction_component_state
		for state_data in player_interaction_component_state:
			if typeof(state_data) != TYPE_DICTIONARY:
				push_warning("CSM: skipping non-dict PIC state record")
				continue
			for data in state_data.keys():
				var key := str(data)
				if not _PIC_ALLOWLIST.has(key):
					push_warning("CSM: blocked PIC save key '" + key + "'")
					continue
				player.player_interaction_component.set(key, state_data[data])
			player.player_interaction_component.set_state.call_deferred() # Calling this deferred as some state calls need to make sure the scene is finished loading.

		player.player_state_loaded.emit()
		fade_in()
	else:
		CogitoGlobals.debug_log(true,"CSM","Player state of slot " + passed_slot + " doesn't exist.")



func save_player_state(player, slot:String) -> void:
	if not is_valid_slot_name(slot):
		push_warning("CSM: save_player_state refused invalid slot '" + slot + "'")
		return
	if !_player_state:
		CogitoGlobals.debug_log(true,"CSM","State doesn't exist. Creating for slot " + slot + "...")
		_player_state = CogitoPlayerState.new()
	
	# Writing the save state from current player node.
	_player_state.player_inventory = player.inventory_data # Saving player inventory
	_player_state.player_equipment = player.equipment
	_player_state.player_quickslots = player.inventory_data.assigned_quickslots # Saving assigned quickslots
	
	# Saving current quests to player state.
	_player_state.player_active_quests.clear()
	for quest in CogitoQuestManager.active.quests:
		_player_state.player_active_quests.append(quest)
		
	_player_state.player_completed_quests.clear()
	for quest in CogitoQuestManager.completed.quests:
		_player_state.player_completed_quests.append(quest)
		
	_player_state.player_failed_quests.clear()
	for quest in CogitoQuestManager.failed.quests:
		_player_state.player_failed_quests.append(quest)  # FIXED: Save failed quests to correct list
	
	# Saving active quests with progression counter
	_player_state.player_active_quest_progression.clear()
	for quest in CogitoQuestManager.active.quests:
		_player_state.add_to_active_quest_dictionary(quest.quest_name, quest.quest_counter_current)
	
	
	_player_state.clear_saved_wieldable_charges()
	for item_slot in player.inventory_data.inventory_slots:
		if item_slot and item_slot.inventory_item and item_slot.inventory_item.has_method("update_wieldable_data"): # Checking for wieldables.
			var item_save_data = item_slot.inventory_item.save()
			_player_state.append_saved_wieldable_charges(item_save_data)
			CogitoGlobals.debug_log(true,"CSM","Saved charge for " + str(item_slot.inventory_item) )
			
	# Save charges for items equipped in the equipment slots
	if player.equipment:
		for slot_id in player.equipment.slots:
			var item_slot = player.equipment.get_equipped(slot_id)
			if item_slot and item_slot.inventory_item and item_slot.inventory_item.has_method("update_wieldable_data"):
				var item_save_data = item_slot.inventory_item.save()
				_player_state.append_saved_wieldable_charges(item_save_data)
				CogitoGlobals.debug_log(true,"CSM","Saved equipment charge for " + str(item_slot.inventory_item) )
	
	_player_state.player_current_scene = _current_scene_name
	CogitoGlobals.debug_log(true,"CSM","Save_player_state(): setting player_current_scene to " + _current_scene_name)
	_player_state.player_current_scene_path = _current_scene_path
	_player_state.player_position = player.global_position
	_player_state.player_rotation = player.body.global_rotation
	_player_state.player_try_crouch = player.try_crouch
	
	## New way of saving attributes:
	_player_state.clear_saved_attribute_data()
	for attribute in player.player_attributes:
		var cur_value
		if !player.player_attributes[attribute].dont_save_current_value:
			cur_value = player.player_attributes[attribute].value_current
		else:
			cur_value = 0
		var max_value = player.player_attributes[attribute].value_max
		var attribute_data := Vector2(cur_value, max_value)
		_player_state.add_player_attribute_to_state_data(attribute, attribute_data)
	
	## Save player sitting state
	_player_state.save_sitting_state(player)
	_player_state.save_collision_shapes(player)
	_player_state.save_node_transforms(player)
	
	_player_state.clear_saved_currency_data()
	for currency in player.player_currencies:
		var cur_value
		if !player.player_currencies[currency].dont_save_current_value:
			cur_value = player.player_currencies[currency].value_current
		else:
			cur_value = 0
		var max_value = player.player_currencies[currency].value_max
		var currency_data := Vector2(cur_value, max_value)
		_player_state.add_player_currency_to_state_data(currency, currency_data)
	
	## Saving world dictionary
	var local_dict_copy : Dictionary = _current_world_dict.duplicate(true)
	_player_state.clear_world_dictionary()
	for entry in local_dict_copy:
		CogitoGlobals.debug_log(true,"CSM", "World Dict: attemtping to save key: " + str(entry) )
		_player_state.add_to_world_dictionary(entry, local_dict_copy[entry])

	## Adding a screenshot
	var screenshot_path : String = str(_player_state.player_state_dir + _active_slot + ".png")
	if _screenshot_to_save:
		_screenshot_to_save.save_png(screenshot_path)
		_player_state.player_state_screenshot_file = screenshot_path
	else:
		CogitoGlobals.debug_log(true,"CSM","No screenshot to save was passed.")
	
	## Getting time of saving
	_player_state.player_state_savetime = int(Time.get_unix_time_from_system())
	_player_state.player_state_slot_name = _active_slot

	# Writing the state from current player interaction component:
	var current_player_interaction_component = player.player_interaction_component
	_player_state.clear_saved_interaction_component_state()
	_player_state.add_interaction_component_state_data_to_array(current_player_interaction_component.save())
	
	# Write to temp directory first
	_player_state.write_state("temp")
#endregion


func get_active_slot_player_state_screenshot_path() -> String:
	if _player_state and _player_state.state_exists(_active_slot):
		var loaded_ps := _coerce_player_state(_player_state.load_state(_active_slot))
		if loaded_ps == null:
			return ""
		_player_state = loaded_ps
		return _player_state.player_state_screenshot_file
	else:
		return ""


func load_scene_state(_scene_name_to_load:String, slot:String) -> void:
	CogitoGlobals.debug_log(true,"CSM","Load scene state for:"+ _scene_name_to_load+ ". Slot: "+ slot)
	if not is_valid_slot_name(slot) or not is_valid_scene_name(_scene_name_to_load):
		push_warning("CSM: load_scene_state refused invalid slot/scene '" + slot + "' / '" + _scene_name_to_load + "'")
		return
	if !_scene_state:
		_scene_state = CogitoSceneState.new()
	if _scene_state and _scene_state.state_exists(slot, _scene_name_to_load):
		CogitoGlobals.debug_log(true,"CSM","Scene state exists. Loading " + str(_scene_state))
		var loaded_ss := _coerce_scene_state(_scene_state.load_state(slot, _scene_name_to_load))
		if loaded_ss == null:
			push_warning("CSM: load_scene_state rejected non-CogitoSceneState for " + _scene_name_to_load)
			return
		_scene_state = loaded_ss

		# Deleting all current nodes that are in the Persist group as to not clone objects.
		var save_nodes = get_tree().get_nodes_in_group("Persist")
		for i in save_nodes:
			CogitoGlobals.debug_log(true,"CSM","Deleting existing node: "+ i.name)
			i.queue_free()

		var array_of_node_data = _scene_state.saved_nodes
		for node_data in array_of_node_data:
			if typeof(node_data) != TYPE_DICTIONARY:
				push_warning("CSM: skipping non-dict saved node record")
				continue
			var new_object := _safe_instantiate_saved_scene(node_data.get("filename", ""))
			if new_object == null:
				continue
			var parent_node := _resolve_scene_local_node(node_data.get("parent", ""))
			if parent_node == null:
				push_warning("CSM: skip node restore — invalid parent for " + str(node_data.get("filename", "")))
				new_object.free()
				continue
			parent_node.add_child(new_object)
			CogitoGlobals.debug_log(true,"CSM","Adding to scene: "+ new_object.get_name())

			new_object.position = Vector3(node_data.get("pos_x", 0.0), node_data.get("pos_y", 0.0), node_data.get("pos_z", 0.0))
			new_object.rotation = Vector3(node_data.get("rot_x", 0.0), node_data.get("rot_y", 0.0), node_data.get("rot_z", 0.0))
			# Restore physics properties if it's a RigidBody3D
			if new_object is RigidBody3D:
				if node_data.has("linear_velocity_x") and node_data.has("linear_velocity_y") and node_data.has("linear_velocity_z"):
					new_object.linear_velocity = Vector3(node_data["linear_velocity_x"], node_data["linear_velocity_y"], node_data["linear_velocity_z"])
				if node_data.has("angular_velocity_x") and node_data.has("angular_velocity_y") and node_data.has("angular_velocity_z"):
					new_object.angular_velocity = Vector3(node_data["angular_velocity_x"], node_data["angular_velocity_y"], node_data["angular_velocity_z"])
			# Allowlisted property restore only (no free-form Object.set).
			_apply_allowed_props(new_object, node_data)

			_restore_pickup_state(new_object, node_data)

			# Call set_state only if the method exists
			if new_object.has_method("set_state"):
				new_object.set_state.call_deferred()

		# Loading states of objects in save_object_state
		var array_of_state_data = _scene_state.saved_states
		for state_data in array_of_state_data:
			if typeof(state_data) != TYPE_DICTIONARY:
				push_warning("CSM: skipping non-dict saved state record")
				continue
			var node_to_set := _resolve_scene_local_node(state_data.get("node_path", ""))
			if node_to_set == null:
				push_warning("CSM: skip state restore — missing/unsafe node_path")
				continue
			# Set variables here
			node_to_set.position = Vector3(state_data.get("pos_x", 0.0), state_data.get("pos_y", 0.0), state_data.get("pos_z", 0.0))
			node_to_set.rotation = Vector3(state_data.get("rot_x", 0.0), state_data.get("rot_y", 0.0), state_data.get("rot_z", 0.0))
			_apply_allowed_props(node_to_set, state_data)
			# Call set_state only if the method exists
			if node_to_set.has_method("set_state"):
				node_to_set.set_state()

		CogitoGlobals.debug_log(true,"CSM","CSM: Loading scene state finished.")

	else:
		CogitoGlobals.debug_log(true,"CSM","CSM: Scene state doesn't exist.")


func _restore_pickup_state(new_object: Node, node_data: Dictionary) -> void:
	var saved_slot_data = null
	if node_data.has("pickup_slot_data"):
		saved_slot_data = node_data["pickup_slot_data"]
	elif node_data.has("slot_data"):
		saved_slot_data = node_data["slot_data"]
	if not (saved_slot_data is InventorySlotPD):
		return

	var slot_copy := _duplicate_slot_data_for_scene_restore(saved_slot_data as InventorySlotPD, node_data)
	if slot_copy == null:
		return
	if "slot_data" in new_object:
		new_object.set("slot_data", slot_copy)
	var pickup_component := _find_pickup_component(new_object)
	if pickup_component:
		pickup_component.slot_data = slot_copy


func _duplicate_slot_data_for_scene_restore(slot_data: InventorySlotPD, node_data: Dictionary) -> InventorySlotPD:
	var slot_copy := slot_data.duplicate() as InventorySlotPD
	if slot_copy == null or slot_copy.inventory_item == null:
		return slot_copy
	var wieldable_item := slot_copy.inventory_item as WieldableItemPD
	if wieldable_item != null:
		var item_copy := wieldable_item.duplicate(false) as WieldableItemPD
		if item_copy != null:
			var state_data = node_data.get("pickup_firearm_mechanical_state", wieldable_item.get_firearm_mechanical_state())
			var fallback_charge = null
			if node_data.has("pickup_item_charge"):
				fallback_charge = node_data["pickup_item_charge"]
			elif node_data.has("item_charge"):
				fallback_charge = node_data["item_charge"]
			_restore_wieldable_saved_state(item_copy, state_data, fallback_charge)
			item_copy.set_attachments(node_data.get("pickup_attachments", wieldable_item.get_attachments()))
			item_copy.player_interaction_component = null
			item_copy.is_being_wielded = false
			item_copy.wielded_item = null
			slot_copy.inventory_item = item_copy
	return slot_copy


func _find_pickup_component(root: Node) -> PickupComponent:
	if root is PickupComponent:
		return root as PickupComponent
	var pickup_nodes := root.find_children("", "PickupComponent", true, false)
	if pickup_nodes.size() > 0:
		return pickup_nodes[0] as PickupComponent
	return null


func _restore_wieldable_saved_state(wieldable_item: WieldableItemPD, state_data, fallback_charge = null) -> void:
	if _is_firearm_state_dict(state_data):
		var state_dict: Dictionary = state_data
		wieldable_item.set_firearm_mechanical_state(state_dict)
		wieldable_item.charge_current = float(_get_firearm_state_total(state_dict))
		return
	if fallback_charge != null:
		wieldable_item.charge_current = float(fallback_charge)


func _is_firearm_state_dict(state_data) -> bool:
	if typeof(state_data) != TYPE_DICTIONARY:
		return false
	var state_dict: Dictionary = state_data
	return int(state_dict.get("version", 0)) == FirearmMechanicalState.SAVE_VERSION


func _get_firearm_state_total(state_data: Dictionary) -> int:
	return int(state_data.get("magazine_rounds", 0)) + int(state_data.get("chamber_rounds", 0))


func save_scene_state(_scene_name_to_save, slot: String) -> void:
	if not is_valid_slot_name(slot) or not is_valid_scene_name(str(_scene_name_to_save)):
		push_warning("CSM: save_scene_state refused invalid slot/scene '" + str(slot) + "' / '" + str(_scene_name_to_save) + "'")
		return
	if !_scene_state:
		CogitoGlobals.debug_log(true,"CSM","CSM: Save doesn't exist. Creating...")
		_scene_state = CogitoSceneState.new()
	# Empty groups must replace the previous scene's snapshot too.
	_scene_state.clear_saved_nodes()
	_scene_state.clear_saved_states()

	var save_nodes = get_tree().get_nodes_in_group("Persist")
	if !save_nodes:
		CogitoGlobals.debug_log(true,"CSM","No nodes in Persist group!")
	else:

		for node in save_nodes:
			if node.scene_file_path.is_empty(): # Check the node is an instanced scene so it can be instanced again during load.
				CogitoGlobals.debug_log(true,"CSM","persistent node '%s' is not an instanced scene, skipped" % node.name)
				continue

			if !node.has_method("save"): # Check the node has a save function.
				CogitoGlobals.debug_log(true,"CSM","persistent node '%s' is missing a save() function, skipped" % node.name)
				continue

			# If the node is a RigidBody3D, then save the physics properties
			if node is RigidBody3D:
				var node_data = node.save()
				node_data["linear_velocity_x"] = node.linear_velocity.x
				node_data["linear_velocity_y"] = node.linear_velocity.y
				node_data["linear_velocity_z"] = node.linear_velocity.z
				node_data["angular_velocity_x"] = node.angular_velocity.x
				node_data["angular_velocity_y"] = node.angular_velocity.y
				node_data["angular_velocity_z"] = node.angular_velocity.z
				_scene_state.add_node_data_to_array(node_data)
			else:
				_scene_state.add_node_data_to_array(node.save())


	# Saving states of objects
	var state_nodes = get_tree().get_nodes_in_group("save_object_state")
	if !state_nodes:
		CogitoGlobals.debug_log(true,"CSM","No nodes in save_object_state group!")
	else:

		for node in state_nodes:
			if !node.has_method("save"): # Check the node has a save function.
				CogitoGlobals.debug_log(true,"CSM","persistent node '%s' is missing a save() function, skipped" % node.name)
				continue

			_scene_state.add_state_data_to_array(node.save())

	_scene_state.write_state(slot, str(_scene_name_to_save))


# Function to transition to another scene via the loading screen.
func load_next_scene(target : String, connector_name: String, passed_slot: String, load_mode: CogitoSceneLoadMode) -> void:
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: load_next_scene refused invalid slot '" + passed_slot + "'")
		return
	if not str(target).begins_with("res://") or str(target).contains("..") or not (str(target).ends_with(".tscn") or str(target).ends_with(".scn")):
		push_warning("CSM: load_next_scene refused non-canonical target " + str(target))
		return
	# fade_out()
	is_currently_loading = true
	var loading_screen = preload("./LoadingScene.tscn").instantiate()
	loading_screen.next_scene_path = target
	loading_screen.connector_name = connector_name
	loading_screen.passed_slot = passed_slot
	# loading_screen.attempt_to_load_save = loading_a_save
	loading_screen.load_mode = load_mode
	CogitoGlobals.debug_log(true, "CSM", "Loading screen initiated with: next_scene_path=" + target + " | connector = " + connector_name + " | passed_slot = " + passed_slot + " | load_mode = " + str(load_mode) )
	get_tree().get_root().add_child(loading_screen)


func delete_save(passed_slot: String) -> void:
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: delete_save refused invalid slot '" + passed_slot + "'")
		return
	# var file_to_remove = cogito_state_dir + cogito_player_state_prefix + passed_slot + ".res"
	var dir_to_remove = slot_dir_path(passed_slot)
	OS.move_to_trash(ProjectSettings.globalize_path(dir_to_remove))
	CogitoGlobals.debug_log(true,"CSM","Save file removed: "+ dir_to_remove)

	# var scene_to_remove = cogito_state_dir + cogito_scene_state_prefix + passed_slot + ".res"


func copy_slot_saves_to_temp(passed_slot:String) -> bool:
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: copy_slot_saves_to_temp refused invalid slot '" + passed_slot + "'")
		return false
	CogitoGlobals.debug_log(true,"CSM","Attempting to copy files from slot " + passed_slot + " to temp.")
	var source_directory := _read_slot_directory(passed_slot)
	var slot_dir = DirAccess.open(source_directory)
	if slot_dir == null:
		return false

	var cogito_dir = DirAccess.open(cogito_state_dir)
	if not cogito_dir.dir_exists("temp"):
		cogito_dir.make_dir("temp")

	if slot_dir:
		slot_dir.list_dir_begin()
		var file_name = slot_dir.get_next()

		while file_name != "":
			if slot_dir.current_is_dir() or not file_name.ends_with(".res"):
				file_name = slot_dir.get_next()
				continue
			CogitoGlobals.debug_log(true,"CSM","Copying file to temp: "+ file_name)
			if slot_dir.copy(source_directory.path_join(file_name), str(slot_dir_path("temp").path_join(file_name)), -1) != OK:
				CogitoGlobals.debug_log(true,"CSM","Copying file "+ file_name + " failed.")
				return false
			# iterate to next file
			file_name = slot_dir.get_next()

	CogitoGlobals.debug_log(true,"CSM", "Copying files to temp finished.")

	loading_saved_game("temp") # This loads the temp save states after moving them from the slot.
	return true



func copy_temp_saves_to_slot(passed_slot:String) -> bool:
	if not is_valid_slot_name(passed_slot):
		push_warning("CSM: copy_temp_saves_to_slot refused invalid slot '" + passed_slot + "'")
		return false
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("commit_save"):
		return scene.commit_save(passed_slot)
	return commit_staged_save(passed_slot)


## Storage only. Scene roots use this after applying their game's save policy.
func commit_staged_save(passed_slot: String) -> bool:
	if not is_valid_slot_name(passed_slot) or passed_slot == "temp":
		return false
	return SaveCommit.commit(slot_dir_path("temp"), slot_dir_path(passed_slot), str(cogito_player_state_prefix) + ".res")


func delete_temp_saves() -> void:
	CogitoGlobals.debug_log(true,"CSM","Attempting to delete temp saves...")

	var dir = DirAccess.open(slot_dir_path("temp") + "/")

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			CogitoGlobals.debug_log(true,"CSM","Deleting file: " + file_name)
			if dir.remove(file_name) != OK:
				CogitoGlobals.debug_log(true,"CSM","Deleting file " + file_name + " failed.")
			# iterate to next file
			file_name = dir.get_next()

	var dir2 = DirAccess.open(cogito_state_dir)
	if dir2:
		dir2.list_dir_begin()
		var file_name = dir2.get_next()
		while file_name != "":
			if dir2.current_is_dir():
				CogitoGlobals.debug_log(true,"CSM","Deleting temp saves: Detected dir = " + file_name)
				if file_name == "temp":
					CogitoGlobals.debug_log(true,"CSM","Deleting temp directory: " + file_name)
					if dir2.remove(file_name) != OK:
						CogitoGlobals.debug_log(true,"CSM","Deleting temp dir failed.")
			file_name = dir2.get_next()

	CogitoGlobals.debug_log(true,"CSM","Delete temp saves complete!")


func reset_scene_states() -> void:
	# TODO: CREATE FUNCTION THAT DELETES SCENE STATE FILES.
	var scene_state_files : Dictionary

	var dir = DirAccess.open(cogito_state_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if dir.current_is_dir():
				CogitoGlobals.debug_log(true,"CSM","Found directory: " + file_name + ". skipping ahead.")

			# Look for _temp_ files
			if file_name.find(cogito_scene_state_prefix,0) != -1:
				CogitoGlobals.debug_log(true,"CSM","Found scene state file: " + file_name)
				if file_name.find("temp",0) != -1:
					CogitoGlobals.debug_log(true,"CSM","This file is a temp scene state.")
					# DELETE HERE
			
			# iterate to next file
			file_name = dir.get_next()
			
	else:
		CogitoGlobals.debug_log(true,"CSM","An error occurred when trying to access the path.")


func _exit_tree() -> void:
	delete_temp_saves()


func _save_autosave_state() -> void:
	_current_scene_name = get_tree().get_current_scene().get_name()
	_current_scene_path = get_tree().current_scene.scene_file_path
	# Use the class variable instead of creating a new local variable
	if not _screenshot_to_save:
		_screenshot_to_save = get_viewport().get_texture().get_image()
	
	save_player_state(_current_player_node, CogitoGlobals.cogito_settings.auto_save_name)
	save_scene_state(_current_scene_name, CogitoGlobals.cogito_settings.auto_save_name)
	copy_temp_saves_to_slot(CogitoGlobals.cogito_settings.auto_save_name) # Use this to include scene states from other scenes in the save.


### FUNCTIONS TO HANDLE SCREEN FADING
func instantiate_fade_panel() -> void:
	fade_panel = Panel.new()
	
	var black_stylebox := StyleBoxFlat.new()
	black_stylebox.bg_color = Color.BLACK
	
	fade_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_panel.focus_mode = Control.FOCUS_NONE
	fade_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_panel.set_modulate(Color.TRANSPARENT)
	fade_panel.add_theme_stylebox_override("panel", black_stylebox)
	
	add_child(fade_panel)


func fade_in(fade_duration:float = default_fade_duration) -> void:
	fade_panel.set_modulate(Color.BLACK)
	var fade_tween = get_tree().create_tween()
	
	fade_tween.tween_property(fade_panel, "modulate", Color.TRANSPARENT, fade_duration).set_trans(Tween.TRANS_CUBIC)
	await fade_tween.finished
	fade_finished.emit()


func fade_out(fade_duration:float = default_fade_duration) -> void:
	fade_panel.set_modulate(Color.TRANSPARENT)
	var fade_tween = get_tree().create_tween()
	
	fade_tween.tween_property(fade_panel, "modulate", Color.BLACK, fade_duration).set_trans(Tween.TRANS_CUBIC)
	await fade_tween.finished
	fade_finished.emit()
