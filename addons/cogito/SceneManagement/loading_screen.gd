extends CanvasLayer
# Loading screen script is heavily dependent on Cogito Scene Manager and scene states.
# MODIFY AT YOUR OWN RISK. Besides the forced_delay, there aren't really any tweakable parameters here.

## Adds a forced wait time to the loading screen. Used to avoid loading screen flickering if load time is too short.
@export var forced_delay : float = 0.5
@onready var label_progress: Label = $Control/VBoxContainer/LabelProgress

var next_scene_path : String
var connector_name : String
var next_scene_state_filename : String
var passed_slot : String
var load_mode
var progress_array : Array[float]

func _ready():
	progress_array.clear()
	if ResourceLoader.load_threaded_request(next_scene_path, "", false, ResourceLoader.CACHE_MODE_IGNORE) != OK:
		_abort_transition()


func _process(_delta):
	var status := ResourceLoader.load_threaded_get_status(next_scene_path)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_abort_transition()
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		CogitoGlobals.debug_log(true, "loading_screen.gd", "Attempting to load " + next_scene_path)
		set_process(false)
		await get_tree().create_timer(forced_delay).timeout
		var current_scene = get_tree().current_scene # Stores currently active scene so it can be set later
		var current_scene_name = current_scene.get_name()
		var new_scene_packed: PackedScene = ResourceLoader.load_threaded_get(next_scene_path)
		if new_scene_packed == null:
			_abort_transition()
			return
		var new_scene_node = new_scene_packed.instantiate()
		if new_scene_node == null:
			_abort_transition()
			return
		current_scene.free() # Only remove the previous scene after incoming instantiation succeeds.
		get_tree().get_root().add_child(new_scene_node) # Adds the instatiated new scene as a node.
		get_tree().current_scene = new_scene_node
		CogitoSceneManager._current_scene_name = str(new_scene_node.name)
		CogitoSceneManager._current_scene_path = new_scene_node.scene_file_path
		# Let deferred HUD/quickslot setup finish before emitting player_state_loaded.
		await get_tree().process_frame
		
		CogitoGlobals.debug_log(true, "loading_screen.gd", "Load_mode is " + str(load_mode) )
		
		#If load_mode asks for it, scene state will be loaded.
		if load_mode == CogitoSceneManager.CogitoSceneLoadMode.FRESH_WITH_PLAYER:
			# Keep the authored world and restore only the carried player snapshot.
			CogitoSceneManager.load_player_state(CogitoSceneManager._current_player_node, "temp")
		elif load_mode != CogitoSceneManager.CogitoSceneLoadMode.RESET:
			next_scene_state_filename = new_scene_node.get_name()
			
			# This flag is used if the scene transition was called from loading a save
			if load_mode == 1: #Load_Mode one is attempting to load a save
				CogitoGlobals.debug_log(true, "loading_screen.gd", "Attempting to load a save for passsed_slot " + passed_slot)
				CogitoSceneManager._current_scene_name = new_scene_node.name #Manually setting new scene name
				CogitoSceneManager.loading_saved_game(passed_slot, current_scene_name)
			else:
				CogitoGlobals.debug_log(true, "loading_screen.gd", "Attempting to load scene state: " + next_scene_state_filename)
				CogitoSceneManager.load_scene_state(next_scene_state_filename,"temp") # Loading temp scene state
				CogitoSceneManager.load_player_state(CogitoSceneManager._current_player_node,"temp") # Loading temp player state.
		else:
			CogitoGlobals.debug_log(true, "loading_screen.gd", "Load mode 2 (RESET), ignoring scene and player states.")
		
		
		if connector_name != "": #If a connector name has been passed, move the player to it. This requires the target scene to have a cogito scene script attached to it's root scene node.
			new_scene_node.move_player_to_connector(connector_name)
		
		CogitoSceneManager.is_currently_loading = false
		queue_free()
	else:
		# Getting progress value and displaying it
		ResourceLoader.load_threaded_get_status(next_scene_path, progress_array) 
		var progress_value = progress_array[0] if typeof(progress_array[0]) == TYPE_FLOAT else 0.0
		var progress_percentage := remap(progress_value, 0.4, 1.0, 0, 99)
		progress_percentage = snapped(progress_percentage, 0.1)
		label_progress.text = str(progress_percentage) + "%"


func _abort_transition() -> void:
	set_process(false)
	CogitoSceneManager.is_currently_loading = false
	CogitoSceneManager.fade_panel.modulate = Color.TRANSPARENT
	var current := get_tree().current_scene
	if current != null and current.has_method("on_scene_transition_failed"):
		current.on_scene_transition_failed()
	push_error("LoadingScreen: destination failed; kept the current scene")
	queue_free()
