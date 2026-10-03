class_name OptionsTabMenu
extends Control
signal options_updated

# Grabbing TabContainer node for gamepad navigation
@onready var tab_container: CogitoTabMenu = $VBoxContainer/TabContainer

const HSliderWLabel = preload("res://addons/cogito/EasyMenus/Scripts/slider_w_labels.gd")
const KeyBindingsTab = preload("res://addons/cogito/EasyMenus/Scripts/options_key_bindings.gd")
const GraphicsTab = preload("res://addons/cogito/EasyMenus/Scripts/options_graphics.gd")
@onready var graphics_tab: GraphicsTab = $VBoxContainer/TabContainer/TAB_GRAPHICS
var config = ConfigFile.new()
var options_config_path: String = OptionsConstants.config_file_name

var have_options_changed := false
var has_windowed_resolution_changed := false

# GAMEPLAY
@onready var invert_y_check_button: CheckBox = %InvertYAxisCheckButton
@onready var toggle_crouching_check_button: CheckBox = %ToggleCrouchingCheckButton
@onready var headbob_option_button: OptionButton = %HeadbobOptionButton
@onready var mouse_sens_slider: HSlider = %MouseSensSlider
@onready var mouse_sens_value_label: Label = %MouseSensValueLabel
@onready var gp_look_sens_value_label: Label = %GPLookSensValueLabel
@onready var gp_look_sens_slider: HSlider = %GPLookSensSlider


var gp_looksens: float
var mouse_sens: float
var headbob_strength: int

# AUDIO
@onready var sfx_volume_slider: HSliderWLabel = %HBoxContainer_SFXVolumeSlider
@onready var music_volume_slider: HSliderWLabel = %HBoxContainer_MusicVolumeSlider

var sfx_bus_index
var music_bus_index

# GRAPHICS
@onready var fullscreen_resolution_slider: Slider = %FullscreenResolutionSlider
@onready var fullscreen_resolution_current_value_label: Label = %FullscreenResolutionCurrentValueLabel
@onready var h_box_container_fullscreen_resolution: HBoxContainer = %HBoxContainer_FullscreenResolution
@onready var windowed_resolution_option_button: OptionButton = %WindowedResolutionOptionButton
@onready var gui_scale_current_value_label: Label = %GUIScaleCurrentValueLabel
@onready var gui_scale_slider: HSlider = %GUIScaleSlider
@onready var vsync_check_button: CheckBox = %VSyncCheckButton
@onready var anti_aliasing_2d_option_button: OptionButton = $%AntiAliasing2DOptionButton
@onready var anti_aliasing_3d_option_button: OptionButton = $%AntiAliasing3DOptionButton
@onready var scope_quality_option_button: OptionButton = %ScopeQualityOptionButton
@onready var fullscreen_mode_check_button: CheckBox = %FullscreenModeCheckButton

var windowed_resolution: Vector2i:
	get:
		return graphics_tab.windowed_resolution
	set(value):
		graphics_tab.windowed_resolution = value
var prev_windowed_resolution: Vector2i:
	get:
		return graphics_tab.prev_windowed_resolution
	set(value):
		graphics_tab.prev_windowed_resolution = value
var fullscreen_resolution_scale_val: float:
	get:
		return graphics_tab.fullscreen_resolution_scale_val
	set(value):
		graphics_tab.fullscreen_resolution_scale_val = value
var gui_scale: float:
	get:
		return graphics_tab.gui_scale
	set(value):
		graphics_tab.gui_scale = value
var resolutions_min_y: float:
	get:
		return graphics_tab.resolutions_min_y
	set(value):
		graphics_tab.resolutions_min_y = value

const HEADBOB_DICTIONARY: Dictionary = {
	"Minimal": 1,
	"Average": 3,
	"Full": 7,
}

const window_operations_delay = GraphicsTab.window_operations_delay
const max_gui_scale_ratio = GraphicsTab.max_gui_scale_ratio

var RESOLUTION_DICTIONARY: Dictionary:
	get:
		return graphics_tab.RESOLUTION_DICTIONARY
	set(value):
		graphics_tab.RESOLUTION_DICTIONARY = value

# INPUT BINDING
@export var remap_entry: PackedScene
@export var separator_entry: PackedScene

@onready var bindings_container: VBoxContainer = %BindingsContainer
@onready var keybindings_tab: KeyBindingsTab = $VBoxContainer/TabContainer/TAB_BINDINGS

@export var rebind_dictionary: Dictionary

var input_actions: Dictionary = KeyBindingsTab.INPUT_ACTIONS.duplicate()

const serialized_default_inputs: String = KeyBindingsTab.SERIALIZED_DEFAULT_INPUTS


func _ready() -> void:
	graphics_tab.options_changed.connect(_on_graphics_options_changed)
	reset()
	remove_unsupported_resolutions()
	resolutions_min_y = get_resolutions_min_y()
	
	# GAMEPLAY
	add_headbob_items()
	headbob_option_button.item_selected.connect(on_headbob_selected)
	mouse_sens_slider.value_changed.connect(_on_mouse_sens_slider_value_changed)
	gp_look_sens_slider.value_changed.connect(_on_gp_looksens_slider_value_changed)
	
	# GRAPHICS
	graphics_tab.initialize()

	# AUDIO
	sfx_bus_index = AudioServer.get_bus_index(OptionsConstants.sfx_bus_name)
	music_bus_index = AudioServer.get_bus_index(OptionsConstants.music_bus_name)
	sfx_volume_slider.hslider.value_changed.connect(_on_sfx_volume_slider_value_changed)
	music_volume_slider.hslider.value_changed.connect(_on_music_volume_slider_value_changed)
	
	load_options()
	load_keybindings_from_config()
	create_action_remap_items()


# Called from outside initializes the options menu
func on_open():
	pass


# Adding headbob options to the button
func add_headbob_items() -> void:
	for headbob_option in HEADBOB_DICTIONARY:
		headbob_option_button.add_item(headbob_option)


func on_headbob_selected(index: int) -> void:
	headbob_strength = HEADBOB_DICTIONARY.values()[index]

func _on_mouse_sens_slider_value_changed(value):
	mouse_sens = value
	mouse_sens_value_label.text = str(value)
	

func _on_gp_looksens_slider_value_changed(value):
	gp_looksens = value
	gp_look_sens_value_label.text = str(value)


func is_fullscreen() -> bool:
	return graphics_tab.is_fullscreen()


func init_fullscreen_mode() -> void:
	graphics_tab.init_fullscreen_mode()


func get_resolution_index_for_window_size(size: Vector2i) -> int:
	return graphics_tab.get_resolution_index_for_window_size(size)


func init_windowed_resolution() -> void:
	graphics_tab.init_windowed_resolution()


func get_gui_scale_max_value(resolution_y):
	return graphics_tab.get_gui_scale_max_value(resolution_y)


func _on_fullscreen_mode_toggled(button_pressed: bool) -> void:
	await graphics_tab._on_fullscreen_mode_toggled(button_pressed)


func refresh_render():
	graphics_tab.refresh_render(config)


func _on_resolution_selected(index: int) -> void:
	graphics_tab._on_resolution_selected(index)

func _on_scope_quality_selected(_index: int) -> void:
	graphics_tab._on_scope_quality_selected(_index)


func _on_fullscreen_resolution_slider_value_changed(value: float) -> void:
	graphics_tab._on_fullscreen_resolution_slider_value_changed(value)

func _on_sfx_volume_slider_value_changed(value):
	set_volume(sfx_bus_index, value)


func _on_music_volume_slider_value_changed(value):
	set_volume(music_bus_index, value)


# Sets the volume for the given audio bus
func set_volume(bus_index, value):
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))


# Saves the options
func save_options() -> bool:
	config.set_value(OptionsConstants.section_name, OptionsConstants.invert_vertical_axis_key, invert_y_check_button.button_pressed)
	config.set_value(OptionsConstants.section_name, OptionsConstants.toggle_crouching_key, toggle_crouching_check_button.button_pressed)
	config.set_value(OptionsConstants.section_name, OptionsConstants.head_bobble_key, headbob_strength)
	config.set_value(OptionsConstants.section_name, OptionsConstants.mouse_sens_key, mouse_sens)
	config.set_value(OptionsConstants.section_name, OptionsConstants.gp_looksens_key, gp_looksens)
	graphics_tab.store_in_config(config)

	config.set_value(OptionsConstants.section_name, OptionsConstants.sfx_volume_key_name, sfx_volume_slider.hslider.value)
	config.set_value(OptionsConstants.section_name, OptionsConstants.music_volume_key_name, music_volume_slider.hslider.value)
	
	# SAVING INPUT MAP
	keybindings_tab.store_in_config(config)
	
	if config.save(options_config_path) != OK:
		push_warning("OptionsTabMenu: Saving options failed; changes are still pending.")
		return false
	CogitoGlobals.debug_log(true, "OptionsTabMenu.gd", "Saving config file OK")
	return true


# Loads options and sets the controls values to loaded values. Uses default values if config file does not exist
func load_options(skip_applying: bool = false):
	var err = config.load(options_config_path)
	# If the config file does not yet exist, we will NOT immediately
	# apply (emit) resolution/window size changes. This prevents the first launch
	# from overriding the ProjectSettings default resolution (e.g. 1920x1080) with
	# our menu's first resolution entry. We still populate UI controls so the user
	# can see/change them, but we only perform window/content_scale modifications
	# once a valid config exists (subsequent launches) or when the user explicitly
	# applies changes.
	var have_cfg = (err == OK)
	if !have_cfg:
		CogitoGlobals.debug_log(true, "OptionsTabMenu.gd", "Loading options config failed (likely first run). Using project defaults until user applies settings.")
	
	var invert_y = config.get_value(OptionsConstants.section_name, OptionsConstants.invert_vertical_axis_key, true)
	var toggle_crouching = config.get_value(OptionsConstants.section_name, OptionsConstants.toggle_crouching_key, true)
	mouse_sens = config.get_value(OptionsConstants.section_name, OptionsConstants.mouse_sens_key, 0.25)
	gp_looksens = config.get_value(OptionsConstants.section_name, OptionsConstants.gp_looksens_key, 2)
	headbob_strength = config.get_value(OptionsConstants.section_name, OptionsConstants.head_bobble_key, 2)
	graphics_tab.read_config(config, have_cfg)

	var sfx_volume = config.get_value(OptionsConstants.section_name, OptionsConstants.sfx_volume_key_name, 1)
	var music_volume = config.get_value(OptionsConstants.section_name, OptionsConstants.music_volume_key_name, 1)

	# LOADING GAMEPLAY CFG
	invert_y_check_button.set_pressed_no_signal(invert_y)
	toggle_crouching_check_button.set_pressed(toggle_crouching)
	
	if !skip_applying:
		invert_y_check_button.toggled.emit()
		toggle_crouching_check_button.toggled.emit()
	
	match headbob_strength:
		1: headbob_option_button.selected = 0
		3: headbob_option_button.selected = 1
		7: headbob_option_button.selected = 2
	if !skip_applying:
		headbob_option_button.item_selected.emit(headbob_option_button.selected)

	mouse_sens_slider.value = mouse_sens
	mouse_sens_value_label.text = str(mouse_sens)

	gp_look_sens_slider.value = gp_looksens
	gp_look_sens_value_label.text = str(gp_looksens)

	# LOADING AUDIO CFG
	sfx_volume_slider.hslider.value = sfx_volume
	music_volume_slider.hslider.value = music_volume

	# LOADING GRAPHICS CFG
	graphics_tab.apply_loaded(skip_applying, have_cfg, config)


func refresh_resolution_controls():
	graphics_tab.refresh_resolution_controls()

func update_fullscreen_resolution_slider_value() -> void:
	graphics_tab.update_fullscreen_resolution_slider_value()

func update_fullscreen_resolution_slider_label() -> void:
	graphics_tab.update_fullscreen_resolution_slider_label()


func center_window() -> void:
	await graphics_tab.center_window()


func _on_gui_scale_slider_value_changed(value):
	graphics_tab._on_gui_scale_slider_value_changed(value)

	
func _on_gui_scale_slider_drag_ended(_value_changed):
	graphics_tab._on_gui_scale_slider_drag_ended(_value_changed)


func apply_gui_scale_value():
	graphics_tab.apply_gui_scale_value()


func _on_v_sync_check_button_toggled(button_pressed):
	graphics_tab._on_v_sync_check_button_toggled(button_pressed)


func _on_anti_aliasing_2d_option_button_item_selected(index):
	graphics_tab._on_anti_aliasing_2d_option_button_item_selected(index)


func _on_anti_aliasing_3d_option_button_item_selected(index):
	graphics_tab._on_anti_aliasing_3d_option_button_item_selected(index)


func set_msaa(mode, index):
	graphics_tab.set_msaa(mode, index)


func load_keybindings_from_config():
	var err = config.load(options_config_path)
	if err != 0:
		CogitoGlobals.debug_log(true, "OptionsTabMenu.gd", "Keybindings: Loading options config failed.")
		#save_keybindings_to_config()
		
	keybindings_tab.apply_config(config)


func save_keybindings_to_config():
	keybindings_tab.store_in_config(config)
	config.save(options_config_path)

	
func create_action_remap_items() -> void:
	keybindings_tab.populate_rows(remap_entry, separator_entry, input_actions)


func _on_graphics_options_changed(windowed_resolution_changed: bool) -> void:
	have_options_changed = true
	if windowed_resolution_changed:
		has_windowed_resolution_changed = true


func _on_apply_changes_pressed() -> void:
	if not save_options():
		return
	get_tree().call_group("scope_renderers", "set_render_resolution", OptionsConstants.get_scope_resolution(config))
	apply_gui_scale_value()

	if have_options_changed:
		refresh_render()

	if has_windowed_resolution_changed:
		center_window()
	
	reset()
	options_updated.emit()


func reset():
	get_window().content_scale_size = Vector2i.ZERO
	have_options_changed = false
	has_windowed_resolution_changed = false


func remove_unsupported_resolutions():
	graphics_tab.remove_unsupported_resolutions()


func get_resolutions_min_y():
	return graphics_tab.get_resolutions_min_y()


func _on_tab_menu_resume():
	# reload options
	load_options.call_deferred()
