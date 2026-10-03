extends "res://addons/cogito/SceneManagement/cogito_scene.gd"

const RaidSaveSnapshot := preload("res://Scripts/Raid/raid_save_snapshot.gd")
const ReturnErrorScene := preload("res://Scene/Raid/raid_return_error.tscn")

@export_file("*.tscn") var hub_scene_path: String = "res://Scene/Hideout/stash_hub.tscn"
@export var hub_connector: String = "RaidReturn"

var ending_raid: bool = false
var active_raid: bool = false
var return_error: CanvasLayer


func _enter_tree() -> void:
	super._enter_tree()
	if CogitoSceneManager.has_meta("raid_departure"):
		# The incoming world must not simulate combat before departure is committed.
		process_mode = Node.PROCESS_MODE_DISABLED


func _ready() -> void:
	_connect_player.call_deferred()
	if CogitoSceneManager.has_meta("raid_departure"):
		_start_raid.call_deferred()


func _start_raid() -> void:
	while CogitoSceneManager.is_currently_loading:
		await get_tree().process_frame
	var departure: Dictionary = CogitoSceneManager.get_meta("raid_departure")
	var player: CogitoPlayer = CogitoSceneManager._current_player_node
	if player.inventory_data != CogitoSceneManager._player_state.player_inventory or player.equipment != CogitoSceneManager._player_state.player_equipment:
		CogitoSceneManager.remove_meta("raid_departure")
		CogitoSceneManager.loading_saved_game(departure["slot"])
		return
	var slot: String = departure["slot"]
	var saved: bool = RaidSaveSnapshot.stage_abandon(departure["player"]) \
		and CogitoSceneManager.commit_staged_save(slot)
	CogitoSceneManager.remove_meta("raid_departure")
	if not saved:
		# The prepared Hub save still has the kit; discard the failed incoming world.
		CogitoSceneManager.loading_saved_game(slot)
		return
	active_raid = true
	process_mode = Node.PROCESS_MODE_INHERIT
	CogitoSceneManager._current_player_node.player_interaction_component.send_hint(null, "Raid started — leaving loses carried gear")


## Directly running Town remains a debug sandbox; Hub-deployed raids cannot commit mid-raid.
func commit_save(slot: String) -> bool:
	if active_raid or CogitoSceneManager.has_meta("raid_departure"):
		CogitoSceneManager._current_player_node.player_interaction_component.send_hint(null, "Extract to save carried gear")
		return false
	return CogitoSceneManager.commit_staged_save(slot)


func _connect_player() -> void:
	var player: CogitoPlayer = CogitoSceneManager._current_player_node
	var health: CogitoHealthAttribute = player.player_attributes["health"]
	var hud: CogitoPlayerHudManager = player.get_node(player.player_hud)
	# Town owns the raid outcome instead of Cogito's reload-last-save death menu.
	if health.death.is_connected(hud._on_player_death):
		health.death.disconnect(hud._on_player_death)
	health.death.connect(_on_player_death, CONNECT_DEFERRED)


func _on_player_death() -> void:
	get_tree().paused = false
	finish_raid(false)


func extract() -> void:
	finish_raid(true)


func finish_raid(extracted: bool) -> void:
	var player: CogitoPlayer = CogitoSceneManager._current_player_node
	if ending_raid or CogitoSceneManager.is_currently_loading:
		return
	if extracted and (player.is_dead or player.player_attributes["health"].value_current <= 0.0):
		return
	var slot: String = CogitoSceneManager._active_slot
	if not CogitoSceneManager.is_valid_slot_name(slot) or slot == "temp" \
		or not hub_scene_path.begins_with("res://") or hub_scene_path.contains("..") \
		or not ResourceLoader.exists(hub_scene_path) \
		or not ResourceLoader.load(hub_scene_path) is PackedScene:
		push_error("Raid: invalid save slot or hub scene; staying in Town")
		if not extracted:
			_show_death_return_error()
		return

	if not RaidSaveSnapshot.stage_scene(self, player, extracted):
		if not extracted:
			_show_death_return_error()
		return

	CogitoSceneManager.set_meta("raid_return", {"slot": slot, "extracted": extracted})
	if is_instance_valid(return_error):
		return_error.hide()
	_load_hub()


func _load_hub() -> void:
	ending_raid = true
	CogitoSceneManager.is_currently_loading = true
	# Freeze combat during the handoff; the loading screen belongs to the tree root.
	process_mode = Node.PROCESS_MODE_DISABLED
	CogitoSceneManager.fade_out()
	await CogitoSceneManager.fade_finished
	CogitoSceneManager.load_next_scene(hub_scene_path, hub_connector, "temp", CogitoSceneManager.CogitoSceneLoadMode.TEMP)


func on_scene_transition_failed() -> void:
	if not ending_raid or not CogitoSceneManager.has_meta("raid_return"):
		return
	ending_raid = false
	var outcome: Dictionary = CogitoSceneManager.get_meta("raid_return")
	if outcome["extracted"]:
		CogitoSceneManager.remove_meta("raid_return")
		process_mode = Node.PROCESS_MODE_INHERIT
		CogitoSceneManager._current_player_node.player_interaction_component.send_hint(null, "Return failed — kit kept; try extracting again")
		return
	_show_death_return_error()


func _show_death_return_error() -> void:
	# Freeze the dead world whether staging or the later transition failed.
	process_mode = Node.PROCESS_MODE_DISABLED
	if not is_instance_valid(return_error):
		return_error = ReturnErrorScene.instantiate()
		return_error.retry_requested.connect(_retry_return)
		return_error.quit_requested.connect(_quit_failed_return)
		add_child(return_error)
	return_error.show_error()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _retry_return() -> void:
	if ending_raid or CogitoSceneManager.is_currently_loading:
		return
	if not CogitoSceneManager.has_meta("raid_return"):
		# Early failure has no loss snapshot yet; retry capture before loading Hub.
		finish_raid(false)
		return
	if not hub_scene_path.begins_with("res://") or hub_scene_path.contains("..") \
		or not ResourceLoader.exists(hub_scene_path) or not ResourceLoader.load(hub_scene_path) is PackedScene:
		return_error.show_error()
		return
	return_error.visible = false
	# Do not recapture live gear or Load an older save after death.
	_load_hub()


func _quit_failed_return() -> void:
	CogitoSceneManager.delete_temp_saves()
	get_tree().quit()
