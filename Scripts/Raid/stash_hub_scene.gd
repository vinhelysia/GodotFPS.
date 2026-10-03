extends "res://addons/cogito/SceneManagement/cogito_scene.gd"

const RaidScene := preload("res://Scripts/Raid/raid_scene.gd")
const RaidSaveSnapshot := preload("res://Scripts/Raid/raid_save_snapshot.gd")
const ResultScene := preload("res://Scene/Raid/raid_result_panel.tscn")
@export_file("*.tscn") var raid_scene_path: String = "res://Scene/Town.tscn"
@export var raid_connector: String = "RaidSpawn"
@export var restore_save_on_start: bool = true

var return_saved: bool = false
var departing: bool = false
var result_panel: CanvasLayer


func _ready() -> void:
	_finish_return.call_deferred()
	_restore_startup.call_deferred()


func _restore_startup() -> void:
	if not restore_save_on_start or CogitoSceneManager.has_meta("raid_return") or CogitoSceneManager.is_currently_loading:
		return
	var state := CogitoSceneManager.get_existing_player_state(CogitoSceneManager._active_slot)
	# Preserve legacy Town saves for explicit debug Load; never silently migrate them.
	if state != null and state.player_current_scene_path == scene_file_path:
		CogitoSceneManager._player_state = state
		CogitoSceneManager._current_scene_name = str(name)
		CogitoSceneManager.loading_saved_game(CogitoSceneManager._active_slot)


func start_raid() -> void:
	var manager := CogitoSceneManager
	var player: CogitoPlayer = manager._current_player_node
	if departing or manager.is_currently_loading or player.is_dead or player.is_showing_ui:
		return
	if not raid_scene_path.begins_with("res://") or raid_scene_path.contains("..") or not ResourceLoader.exists(raid_scene_path):
		player.player_interaction_component.send_hint(null, "Raid destination unavailable — kit kept")
		return
	var packed := ResourceLoader.load(raid_scene_path) as PackedScene
	if packed == null or not _has_connector(packed, raid_connector):
		player.player_interaction_component.send_hint(null, "Raid spawn unavailable — kit kept")
		return
	# A safe prepared save keeps the kit if loading or departure commit fails.
	if not commit_save(manager._active_slot):
		player.player_interaction_component.send_hint(null, "Save failed — staying in Hub")
		return
	var prepared: CogitoPlayerState = manager._player_state.duplicate(true)
	manager.set_meta("raid_departure", {"slot": manager._active_slot, "player": prepared})
	departing = true
	process_mode = Node.PROCESS_MODE_DISABLED
	manager.load_next_scene(raid_scene_path, raid_connector, "temp", manager.CogitoSceneLoadMode.FRESH_WITH_PLAYER)


func on_scene_transition_failed() -> void:
	departing = false
	process_mode = Node.PROCESS_MODE_INHERIT
	if CogitoSceneManager.has_meta("raid_departure"):
		CogitoSceneManager.remove_meta("raid_departure")
	CogitoSceneManager._current_player_node.player_interaction_component.send_hint(null, "Deployment failed — kit kept")


func _has_connector(packed: PackedScene, connector: String) -> bool:
	var state := packed.get_state()
	# Only the raid root owns the incoming freeze/commit policy.
	var root_script: Script
	for property in state.get_node_property_count(0):
		if state.get_node_property_name(0, property) == &"script":
			root_script = state.get_node_property_value(0, property)
	if root_script != RaidScene:
		return false
	for index in state.get_node_count():
		if str(state.get_node_path(index)).trim_prefix("./") == connector:
			return true
	return false


func commit_save(slot: String) -> bool:
	if departing or CogitoSceneManager.is_currently_loading or not CogitoSceneManager.is_valid_slot_name(slot) or slot == "temp":
		return false
	if not RaidSaveSnapshot.stage_scene(self, CogitoSceneManager._current_player_node):
		return false
	var saved: bool = CogitoSceneManager.commit_staged_save(slot)
	if CogitoSceneManager.has_meta("raid_return") and CogitoSceneManager.get_meta("raid_return")["slot"] == slot:
		return_saved = saved
		if saved:
			CogitoSceneManager.remove_meta("raid_return")
		if is_instance_valid(result_panel):
			result_panel.set_save_status(saved)
	return saved


func _finish_return() -> void:
	if not CogitoSceneManager.has_meta("raid_return"):
		return
	# LoadingScreen restores the player and connector before the next frame.
	await get_tree().process_frame
	while CogitoSceneManager.is_currently_loading:
		await get_tree().process_frame
	var outcome: Dictionary = CogitoSceneManager.get_meta("raid_return")
	var slot: String = outcome["slot"]
	var temp_hub_path: String = CogitoSceneManager.scene_state_path("temp", str(name))
	var saved_hub_path: String = CogitoSceneManager.scene_state_path(slot, str(name))
	if not FileAccess.file_exists(temp_hub_path) and FileAccess.file_exists(saved_hub_path):
		CogitoSceneManager.load_scene_state(str(name), slot)
		await get_tree().process_frame
	return_saved = commit_save(slot)
	if not return_saved:
		push_error("Raid return: could not commit slot " + slot)
	result_panel = ResultScene.instantiate()
	result_panel.continue_requested.connect(_close_result)
	result_panel.retry_save_requested.connect(_retry_return_save)
	add_child(result_panel)
	var player: CogitoPlayer = CogitoSceneManager._current_player_node
	player._on_pause_movement()
	player.is_showing_ui = true
	result_panel.show_result(outcome["extracted"], return_saved)


func _retry_return_save() -> void:
	if CogitoSceneManager.has_meta("raid_return"):
		var outcome: Dictionary = CogitoSceneManager.get_meta("raid_return")
		commit_save(outcome["slot"])


func _close_result() -> void:
	result_panel.visible = false
	var player: CogitoPlayer = CogitoSceneManager._current_player_node
	player.is_showing_ui = false
	player._on_resume_movement()
