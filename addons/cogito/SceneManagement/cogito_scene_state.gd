class_name CogitoSceneState
extends Resource

var scene_state_dir : String = CogitoSceneManager.cogito_state_dir + CogitoSceneManager.cogito_scene_state_prefix

@export var saved_nodes : Array
@export var saved_states : Array


func clear_saved_nodes():
	saved_nodes.clear()


func clear_saved_states():
	saved_states.clear()


func add_node_data_to_array(node_data):
	saved_nodes.append(node_data)


func add_state_data_to_array(state_data):
	saved_states.append(state_data)


func write_state(state_slot : String, scene_name : String) -> void:
	if not CogitoSceneManager.is_valid_slot_name(state_slot) or not CogitoSceneManager.is_valid_scene_name(scene_name):
		push_warning("CogitoSceneState: refused write_state for invalid slot/scene '" + state_slot + "' / '" + scene_name + "'")
		return
	var dir = DirAccess.open(CogitoSceneManager.cogito_state_dir)
	if dir == null:
		push_warning("CogitoSceneState: cannot open save root " + str(CogitoSceneManager.cogito_state_dir))
		return
	dir.make_dir(str(state_slot))
	# Writes stage at the slot root; published generations are read-only.
	var scene_state_file = CogitoSceneManager.slot_dir_path(state_slot).path_join(str(CogitoSceneManager.cogito_scene_state_prefix) + scene_name + ".res")
	ResourceSaver.save(self, scene_state_file, ResourceSaver.FLAG_CHANGE_PATH)
	CogitoGlobals.debug_log(true, "cogito_scene_state.gd", "Scene state saved as " + scene_state_file)


func state_exists(state_slot : String, scene_name : String) -> bool:
	if not CogitoSceneManager.is_valid_slot_name(state_slot) or not CogitoSceneManager.is_valid_scene_name(scene_name):
		return false
	var scene_state_file = CogitoSceneManager.scene_state_path(state_slot, scene_name)
	CogitoGlobals.debug_log(true, "cogito_scene_state.gd","Looking if stat exists: " + scene_state_file)
	#return ResourceLoader.exists(scene_state_file)
	return FileAccess.file_exists(scene_state_file)


func load_state(state_slot : String, scene_name : String) -> Resource:
	if not CogitoSceneManager.is_valid_slot_name(state_slot) or not CogitoSceneManager.is_valid_scene_name(scene_name):
		push_warning("CogitoSceneState: refused load_state for invalid slot/scene '" + state_slot + "' / '" + scene_name + "'")
		return null
	var scene_state_file = CogitoSceneManager.scene_state_path(state_slot, scene_name)
	var res := ResourceLoader.load(scene_state_file, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res != null and not (res is CogitoSceneState):
		push_warning("CogitoSceneState: loaded resource is not CogitoSceneState (" + str(res.get_class()) + ")")
		return null
	return res
