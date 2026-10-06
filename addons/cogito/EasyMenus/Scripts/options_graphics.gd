class_name CogitoOptionsGraphics
extends MarginContainer
## Owns graphics controls and native window operations; the parent owns file IO and Apply.

signal options_changed(windowed_resolution_changed: bool)

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
@onready var ao_option_button: OptionButton = %AOOptionButton
@onready var ao_intensity_slider: HSlider = %AOIntensitySlider
@onready var ao_intensity_value_label: Label = %AOIntensityValueLabel
@onready var fullscreen_mode_check_button: CheckBox = %FullscreenModeCheckButton

var windowed_resolution: Vector2i
var prev_windowed_resolution: Vector2i
var fullscreen_resolution_scale_val := 1.0
var gui_scale: float
var resolutions_min_y := 540.0


const window_operations_delay = 0.25
const max_gui_scale_ratio = 0.75

var RESOLUTION_DICTIONARY: Dictionary = {
	"800x600 (4:3)": Vector2i(800, 600),
	"960x540 (16:9)": Vector2i(960, 540),
	"1024x576 (16:9)": Vector2i(1024, 576),
	"1024x640 (16:10)": Vector2i(1024, 640),
	"1024x768 (4:3)": Vector2i(1024, 768),
	"1152x648 (16:9)": Vector2i(1152, 648),
	"1280x720 (16:9)": Vector2i(1280, 720),
	"1280x800 (16:10)": Vector2i(1280, 800),
	"1366x768 (16:9)": Vector2i(1366, 768),
	"1440x900 (16:10)": Vector2i(1440, 900),
	"1600x1200 (4:3)": Vector2i(1600, 1200),
	"1600x900 (16:9)": Vector2i(1600, 900),
	"1680x720 (21:9)": Vector2i(1680, 720),
	"1920x1080 (16:9)": Vector2i(1920, 1080),
	"1920x1200 (16:10)": Vector2i(1920, 1200),
	"2560x1080 (21:9)": Vector2i(2560, 1080),
	"2560x1440 (16:9)": Vector2i(2560, 1440),
	"3440x1440 (21:9)": Vector2i(3440, 1440),
	"3840x2160 (16:9)": Vector2i(3840, 2160),
}

var _loaded_fullscreen_mode: Variant
var _loaded_resolution_index: Variant
var _loaded_fullscreen_resolution_scale: Variant
var _loaded_vsync: Variant
var _loaded_msaa_2d: Variant
var _loaded_msaa_3d: Variant
var _loaded_scope_resolution: int
var _loaded_ao_mode: int
var _loaded_ao_intensity: float


func initialize() -> void:
	init_fullscreen_mode()
	init_windowed_resolution()
	fullscreen_mode_check_button.toggled.connect(_on_fullscreen_mode_toggled)
	windowed_resolution_option_button.item_selected.connect(_on_resolution_selected)
	scope_quality_option_button.item_selected.connect(_on_scope_quality_selected)
	ao_option_button.item_selected.connect(_on_ao_selected)
	ao_intensity_slider.value_changed.connect(_on_ao_intensity_changed)
	gui_scale_slider.value_changed.connect(_on_gui_scale_slider_value_changed)
	vsync_check_button.toggled.connect(_on_v_sync_check_button_toggled)
	anti_aliasing_2d_option_button.item_selected.connect(_on_anti_aliasing_2d_option_button_item_selected)
	anti_aliasing_3d_option_button.item_selected.connect(_on_anti_aliasing_3d_option_button_item_selected)
	refresh_resolution_controls()


func read_config(config: ConfigFile, have_cfg: bool) -> void:
	_loaded_fullscreen_mode = config.get_value(OptionsConstants.section_name, OptionsConstants.fullscreen_mode_key_name, is_fullscreen())
	var current_resolution_index := windowed_resolution_option_button.selected
	_loaded_resolution_index = config.get_value(OptionsConstants.section_name, OptionsConstants.resolution_index_key_name, current_resolution_index)
	_loaded_fullscreen_resolution_scale = config.get_value(OptionsConstants.section_name, OptionsConstants.fullscreen_resolution_scale_key, 1.0)
	gui_scale = config.get_value(OptionsConstants.section_name, OptionsConstants.gui_scale_key, 1)
	_loaded_vsync = config.get_value(OptionsConstants.section_name, OptionsConstants.vsync_key, true)

	_loaded_msaa_2d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_2d_key, 0)
	_loaded_msaa_3d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_3d_key, 0)
	_loaded_scope_resolution = OptionsConstants.default_scope_resolution
	_loaded_ao_mode = OptionsConstants.AOMode.SCENE_DEFAULT
	_loaded_ao_intensity = 1.0
	if have_cfg:
		_loaded_scope_resolution = OptionsConstants.get_scope_resolution(config)
		_loaded_ao_mode = OptionsConstants.get_ao_mode(config)
		_loaded_ao_intensity = OptionsConstants.get_ao_intensity(config)


func apply_loaded(skip_applying: bool, have_cfg: bool, config: ConfigFile) -> void:
	fullscreen_resolution_scale_val = _loaded_fullscreen_resolution_scale
	update_fullscreen_resolution_slider_value()
	update_fullscreen_resolution_slider_label()

	# Need to set it like that to guarantee signal to be triggered
	vsync_check_button.set_pressed_no_signal(_loaded_vsync)
	vsync_check_button.toggled.emit(_loaded_vsync)

	anti_aliasing_2d_option_button.selected = _loaded_msaa_2d
	anti_aliasing_3d_option_button.selected = _loaded_msaa_3d
	scope_quality_option_button.select(scope_quality_option_button.get_item_index(_loaded_scope_resolution))
	ao_option_button.select(ao_option_button.get_item_index(_loaded_ao_mode))
	ao_intensity_slider.set_value_no_signal(_loaded_ao_intensity)
	refresh_ao_controls()
	if !skip_applying:
		get_tree().call_group("scope_renderers", "set_render_resolution", _loaded_scope_resolution)

	fullscreen_mode_check_button.set_pressed_no_signal(_loaded_fullscreen_mode)
	windowed_resolution_option_button.selected = _loaded_resolution_index

	if _loaded_fullscreen_mode:
		gui_scale_slider.max_value = get_gui_scale_max_value(DisplayServer.screen_get_size().y)
	else:
		var windowed_resolution = RESOLUTION_DICTIONARY.values()[_loaded_resolution_index]
		gui_scale_slider.max_value = get_gui_scale_max_value(windowed_resolution.y)

	gui_scale_slider.value = gui_scale
	gui_scale_current_value_label.text = "%d%%" % (gui_scale * 100)

	if !skip_applying:
		apply_gui_scale_value()

	# Only apply window mode + resolution + refresh when a config actually exists,
	# and when we're not skipping applying.
	if !skip_applying and have_cfg:
		anti_aliasing_2d_option_button.emit_signal("item_selected", _loaded_msaa_2d)
		anti_aliasing_3d_option_button.emit_signal("item_selected", _loaded_msaa_3d)
		windowed_resolution_option_button.item_selected.emit(_loaded_resolution_index)
		fullscreen_mode_check_button.toggled.emit(_loaded_fullscreen_mode)
		refresh_render(config)

	refresh_resolution_controls()


func store_in_config(config: ConfigFile) -> void:
	config.set_value(OptionsConstants.section_name, OptionsConstants.fullscreen_mode_key_name, is_fullscreen())
	config.set_value(OptionsConstants.section_name, OptionsConstants.resolution_index_key_name, windowed_resolution_option_button.selected)
	config.set_value(OptionsConstants.section_name, OptionsConstants.fullscreen_resolution_scale_key, fullscreen_resolution_slider.value / 100.0)
	config.set_value(OptionsConstants.section_name, OptionsConstants.gui_scale_key, gui_scale_slider.value);
	config.set_value(OptionsConstants.section_name, OptionsConstants.vsync_key, vsync_check_button.button_pressed)
	config.set_value(OptionsConstants.section_name, OptionsConstants.msaa_2d_key, anti_aliasing_2d_option_button.get_selected_id())
	config.set_value(OptionsConstants.section_name, OptionsConstants.msaa_3d_key, anti_aliasing_3d_option_button.get_selected_id())
	config.set_value(OptionsConstants.section_name, OptionsConstants.scope_resolution_key, scope_quality_option_button.get_selected_id())
	config.set_value(OptionsConstants.section_name, OptionsConstants.ao_mode_key, ao_option_button.get_selected_id())
	config.set_value(OptionsConstants.section_name, OptionsConstants.ao_intensity_key, ao_intensity_slider.value)

	# We previously removed the legacy `render_scale` key – clean it if present
	if config.has_section_key(OptionsConstants.section_name, "render_scale"):
		config.erase_section_key(OptionsConstants.section_name, "render_scale")


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


# Initialize the fullscreen mode check button to reflect current state.
func init_fullscreen_mode() -> void:
	fullscreen_mode_check_button.set_pressed_no_signal(is_fullscreen())


func get_resolution_index_for_window_size(size: Vector2i) -> int:
	var resolution_values = RESOLUTION_DICTIONARY.values();
	for i in resolution_values.size():
		var v := Vector2i(resolution_values[i])
		if v == size:
			return i
	return -1


# Initialize all windowed resolutions and set the current windowed resolution on the button
func init_windowed_resolution() -> void:
	for resolution_text in RESOLUTION_DICTIONARY:
		windowed_resolution_option_button.add_item(resolution_text)

	windowed_resolution = get_window().size
	prev_windowed_resolution = windowed_resolution

	var idx := get_resolution_index_for_window_size(get_window().size)
	if idx != -1:
		windowed_resolution_option_button.selected = idx


func get_gui_scale_max_value(resolution_y):
	var scale_max_value = (resolution_y / resolutions_min_y) * max_gui_scale_ratio
	var remainder = fmod(scale_max_value, gui_scale_slider.step)
	if remainder < gui_scale_slider.step - 0.0001:
		scale_max_value -= remainder

	return scale_max_value


func _on_fullscreen_mode_toggled(button_pressed: bool) -> void:
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

		gui_scale_slider.max_value = get_gui_scale_max_value(DisplayServer.screen_get_size().y)
		gui_scale_slider.value = gui_scale
		apply_gui_scale_value()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

		var scale_max_value = get_gui_scale_max_value(windowed_resolution.y)
		gui_scale_slider.max_value = scale_max_value
		if gui_scale_slider.value >= scale_max_value:
			gui_scale_slider.value = scale_max_value
		apply_gui_scale_value()

		var window = get_window()
		await get_tree().create_timer(window_operations_delay).timeout
		window.size = windowed_resolution
		window.content_scale_size = Vector2i.ZERO
		window.scaling_3d_scale = 1.0
		center_window()

	refresh_resolution_controls()


func refresh_render(config: ConfigFile):
	var window = get_window()

	if is_fullscreen():
		window.scaling_3d_scale = fullscreen_resolution_scale_val
	else:
		window.size = windowed_resolution
		window.content_scale_size = Vector2i.ZERO
		window.scaling_3d_scale = 1.0

	var msaa_2d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_2d_key, 0)
	var msaa_3d = config.get_value(OptionsConstants.section_name, OptionsConstants.msaa_3d_key, 0)
	set_msaa("msaa_2d", msaa_2d)
	set_msaa("msaa_3d", msaa_3d)


# Function to change resolution. Hooked up to the windowed_resolution_option_button.
func _on_resolution_selected(index: int) -> void:
	prev_windowed_resolution = windowed_resolution
	windowed_resolution = RESOLUTION_DICTIONARY.values()[index]

	gui_scale_slider.max_value = get_gui_scale_max_value(windowed_resolution.y)
	apply_gui_scale_value()

	if prev_windowed_resolution != windowed_resolution:
		var window = get_window()
		window.size = windowed_resolution
		window.content_scale_size = Vector2i.ZERO
		center_window()

		options_changed.emit(true)


func _on_scope_quality_selected(_index: int) -> void:
	options_changed.emit(false)


func _on_ao_selected(_index: int) -> void:
	refresh_ao_controls()
	options_changed.emit(false)


func _on_ao_intensity_changed(_value: float) -> void:
	refresh_ao_controls()
	options_changed.emit(false)


func refresh_ao_controls() -> void:
	ao_intensity_slider.editable = ao_option_button.get_selected_id() != OptionsConstants.AOMode.OFF
	ao_intensity_value_label.text = "%d%%" % roundi(ao_intensity_slider.value * 100.0)


func _on_fullscreen_resolution_slider_value_changed(value: float) -> void:
	var scale = value / 100.00
	fullscreen_resolution_scale_val = scale
	update_fullscreen_resolution_slider_label()
	options_changed.emit(false)


func refresh_resolution_controls():
	var fullscreen := is_fullscreen()
	fullscreen_resolution_slider.visible = fullscreen
	# Show fullscreen resolution slider only in fullscreen mode
	h_box_container_fullscreen_resolution.visible = fullscreen

	# Show windowed resolution selector only in windowed mode
	windowed_resolution_option_button.visible = !fullscreen

	if fullscreen:
		update_fullscreen_resolution_slider_value()
		update_fullscreen_resolution_slider_label()


func update_fullscreen_resolution_slider_value() -> void:
	fullscreen_resolution_slider.value = fullscreen_resolution_scale_val * 100.0


func update_fullscreen_resolution_slider_label() -> void:
	var scale = fullscreen_resolution_scale_val
	var window_size = DisplayServer.screen_get_size()
	var pct = roundi(scale * 100.0)
	var res_x = roundi(window_size.x * scale)
	var res_y = roundi(window_size.y * scale)
	fullscreen_resolution_current_value_label.text = "%d%% - %dx%d" % [pct, res_x, res_y]

# Centers the window in the middle of the user's current screen
func center_window() -> void:
	var window = get_window()
	var center_of_screen = DisplayServer.screen_get_position() + DisplayServer.screen_get_size() / 2
	var window_size = window.get_size_with_decorations()
	await get_tree().create_timer(window_operations_delay).timeout
	window.position = center_of_screen - window_size / 2


func _on_gui_scale_slider_value_changed(value):
	gui_scale_current_value_label.text = "%d%%" % int(value * 100)
	options_changed.emit(false)


func _on_gui_scale_slider_drag_ended(_value_changed):
	gui_scale_current_value_label.text = "%d%%" % int(gui_scale_slider.value * 100)
	options_changed.emit(false)


func apply_gui_scale_value():
	get_viewport().content_scale_factor = gui_scale_slider.value
	gui_scale_current_value_label.text = "%d%%" % (gui_scale_slider.value * 100)


func _on_v_sync_check_button_toggled(button_pressed):
	# There are multiple V-Sync Methods supported by Godot 
	# For now we just use the simple ones could be worth a consideration to add the others
	# Just sets V-Sync for the first window. So no support for multi window games
	if button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	options_changed.emit(false)


func _on_anti_aliasing_2d_option_button_item_selected(index):
	set_msaa("msaa_2d", index)
	options_changed.emit(false)


func _on_anti_aliasing_3d_option_button_item_selected(index):
	set_msaa("msaa_3d", index)
	options_changed.emit(false)


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


func remove_unsupported_resolutions():
	var screen_size = DisplayServer.screen_get_size()
	for resolution_key in RESOLUTION_DICTIONARY:
		var resolution = RESOLUTION_DICTIONARY[resolution_key]
		if resolution.x > screen_size.x or resolution.y > screen_size.y:
			RESOLUTION_DICTIONARY.erase(resolution_key)


func get_resolutions_min_y():
	var screen_size = DisplayServer.screen_get_size()
	var min_y = screen_size.y
	for resolution_key in RESOLUTION_DICTIONARY:
		var resolution = RESOLUTION_DICTIONARY[resolution_key]
		if resolution.y < min_y:
			min_y = resolution.y

	return min_y
