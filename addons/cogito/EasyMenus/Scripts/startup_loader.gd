extends Node
#Loads options like volume and graphic options on game startup

var config = ConfigFile.new()
var _ao_mode: int = OptionsConstants.AOMode.SCENE_DEFAULT
var _ao_intensity := 1.0

@onready var sfx_bus_index = AudioServer.get_bus_index(OptionsConstants.sfx_bus_name)
@onready var music_bus_index = AudioServer.get_bus_index(OptionsConstants.music_bus_name)

# Loads settings from config file. Loads with standard values if settings not 
# existing
func load_settings():
	var err = config.load(OptionsConstants.config_file_name)
	
	if err != OK:
		return
	apply_ambient_occlusion(config)
	
	var sfx_volume = config.get_value(OptionsConstants.section_name, OptionsConstants.sfx_volume_key_name, 1)
	var music_volume = config.get_value(OptionsConstants.section_name, OptionsConstants.music_volume_key_name, 1)
	var is_fullscreen = config.get_value(OptionsConstants.section_name, OptionsConstants.fullscreen_mode_key_name, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var resolution_index = config.get_value(OptionsConstants.section_name, OptionsConstants.resolution_index_key_name, 0)
	var fullscreen_resolution_scale = config.get_value(OptionsConstants.section_name, OptionsConstants.fullscreen_resolution_scale_key, 1.0)
	var gui_scale = config.get_value(OptionsConstants.section_name, OptionsConstants.gui_scale_key, 1)
	var vsync = config.get_value(OptionsConstants.section_name, OptionsConstants.vsync_key, true)
	var invert_y = config.get_value(OptionsConstants.section_name, OptionsConstants.invert_vertical_axis_key, true)
	var msaa_2d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_2d_key, 0)
	var msaa_3d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_3d_key, 0)
	
	AudioServer.set_bus_volume_db(sfx_bus_index, sfx_volume)
	AudioServer.set_bus_volume_db(music_bus_index, music_volume)
	
	# Set window mode based on fullscreen toggle
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	
	# Apply appropriate 3D scaling based on window mode (fullscreen vs windowed)
	if is_fullscreen:
		get_viewport().scaling_3d_scale = fullscreen_resolution_scale
	else:
		get_viewport().scaling_3d_scale = 1.0
	
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
	set_msaa("msaa_2d", msaa_2d)
	set_msaa("msaa_3d", msaa_3d)


func _ready():
	get_tree().node_added.connect(_on_node_added)
	load_settings()


func apply_ambient_occlusion(options: ConfigFile) -> void:
	_ao_mode = OptionsConstants.get_ao_mode(options)
	_ao_intensity = OptionsConstants.get_ao_intensity(options)
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_environment(node as WorldEnvironment)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		# The incoming scene may not be current_scene yet. Apply to this exact node.
		_apply_new_environment.call_deferred(weakref(node))


func _apply_new_environment(reference: WeakRef) -> void:
	var node := reference.get_ref() as WorldEnvironment
	if is_instance_valid(node) and node.is_inside_tree():
		_apply_environment(node)


func _apply_environment(node: WorldEnvironment) -> void:
	if node.environment == null:
		return
	var original := node.get_meta("_options_ao_original", node.environment) as Environment
	if _ao_mode == OptionsConstants.AOMode.SCENE_DEFAULT and is_equal_approx(_ao_intensity, 1.0):
		node.environment = original
		if node.has_meta("_options_ao_original"):
			node.remove_meta("_options_ao_original")
		return
	if not node.has_meta("_options_ao_original"):
		# Environment resources can be shared by scenes; only change this runtime copy.
		node.set_meta("_options_ao_original", original)
		node.environment = original.duplicate() as Environment
	node.environment.ssao_enabled = original.ssao_enabled if _ao_mode == OptionsConstants.AOMode.SCENE_DEFAULT else _ao_mode == OptionsConstants.AOMode.ON
	node.environment.ssao_intensity = original.ssao_intensity * _ao_intensity


func set_msaa(mode, index):
	match index:
		0:
			get_viewport().set(mode, Viewport.MSAA_DISABLED)
		1:
			get_viewport().set(mode, Viewport.MSAA_2X)
		2:
			get_viewport().set(mode, Viewport.MSAA_4X)
		3:
			get_viewport().set(mode, Viewport.MSAA_8X)
