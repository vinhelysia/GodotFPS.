extends CogitoButton
## Owns the physical screen, camera transition and input projection. Hub owns deployment.

signal view_closed

const UI_ACTIONS: Array[StringName] = [
	&"ui_accept", &"ui_left", &"ui_right", &"ui_up", &"ui_down",
	&"ui_focus_next", &"ui_focus_prev",
]

@export_range(0.0, 2.0, 0.05) var camera_duration: float = 0.35
@export_range(20.0, 90.0, 1.0) var view_fov: float = 42.0

@onready var panel: Control = $ScreenViewport/TerminalPanel
@onready var screen_viewport: SubViewport = $ScreenViewport
@onready var screen_mesh: MeshInstance3D = $Screen
@onready var view_pose: Marker3D = $ViewPose
@onready var terminal_camera: Camera3D = $TerminalCamera
@onready var idle_screen: Control = $ScreenViewport/IdleScreen

var is_viewing: bool = false
var is_transitioning: bool = false
var _closing: bool = false
var _player: CogitoPlayer
var _previous_camera: Camera3D
var _previous_camera_pose: Transform3D
var _previous_fov: float
var _previous_process_mode: ProcessMode
var _previous_mouse_mode: Input.MouseMode
var _hud: CanvasItem
var _hud_was_visible: bool
var _wieldables: Node3D
var _wieldables_were_visible: bool
var _camera_tween: Tween
var _mouse_inside: bool = false
var _last_mouse_position: Vector2


func _ready() -> void:
	super._ready()
	set_process_input(false)
	panel.hide()
	# Resolve this instance's viewport directly; nested scene texture paths can bind elsewhere.
	var screen_material := screen_mesh.get_active_material(0) as StandardMaterial3D
	if screen_material != null:
		var instance_material := screen_material.duplicate() as StandardMaterial3D
		instance_material.albedo_texture = screen_viewport.get_texture()
		screen_mesh.material_override = instance_material
	else:
		push_error("Raid terminal Screen requires a StandardMaterial3D.")
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func begin_view(player: CogitoPlayer, destination_name: String) -> bool:
	if is_viewing or not is_instance_valid(player) or not is_instance_valid(player.camera):
		return false
	var previous_camera := get_viewport().get_camera_3d()
	if previous_camera == null or screen_mesh.to_local(previous_camera.global_position).z <= 0.0:
		return false
	_player = player
	_previous_camera = previous_camera
	_previous_camera_pose = previous_camera.get_camera_transform()
	_previous_fov = previous_camera.fov
	_previous_process_mode = player.process_mode
	_previous_mouse_mode = Input.mouse_mode
	_hud = player.get_node_or_null(player.player_hud) as CanvasItem
	_wieldables = player.player_interaction_component.wieldable_container
	# Frozen children cannot receive releases or clear held fire on their next tick.
	var interaction := player.player_interaction_component
	if is_instance_valid(interaction.equipped_wieldable_node):
		interaction.attempt_action_primary(true)
		interaction.attempt_action_secondary(true)
	if is_instance_valid(_hud):
		_hud_was_visible = _hud.visible
		_hud.hide()
	if is_instance_valid(_wieldables):
		_wieldables_were_visible = _wieldables.visible
		_wieldables.hide()
	# A second camera keeps lean/recoil and save-owned player transforms untouched.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	terminal_camera.global_transform = _previous_camera_pose
	terminal_camera.fov = _previous_fov
	terminal_camera.keep_aspect = previous_camera.keep_aspect
	terminal_camera.cull_mask = previous_camera.cull_mask
	terminal_camera.far = previous_camera.far
	terminal_camera.environment = previous_camera.environment
	terminal_camera.attributes = previous_camera.attributes
	terminal_camera.make_current()
	is_viewing = true
	is_transitioning = true
	_closing = false
	idle_screen.hide()
	panel.show_destination(destination_name)
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process_input(true)
	_move_camera(view_pose.global_transform, view_fov, _finish_open)
	return true


func close_view(immediate: bool = false) -> void:
	if not is_viewing or (_closing and not immediate):
		return
	_closing = true
	is_transitioning = true
	if is_instance_valid(_camera_tween):
		_camera_tween.kill()
	_set_mouse_inside(false)
	if immediate:
		_finish_close()
	else:
		_move_camera(_previous_camera_pose, _previous_fov, _finish_close)


func _move_camera(target_pose: Transform3D, target_fov: float, finished: Callable) -> void:
	if camera_duration <= 0.0:
		terminal_camera.global_transform = target_pose
		terminal_camera.fov = target_fov
		finished.call()
		return
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(terminal_camera, "global_transform", target_pose, camera_duration)
	_camera_tween.tween_property(terminal_camera, "fov", target_fov, camera_duration)
	_camera_tween.chain().tween_callback(finished)


func _finish_open() -> void:
	is_transitioning = false


func _finish_close() -> void:
	panel.hide()
	idle_screen.show()
	screen_viewport.gui_release_focus()
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_restore_player_view()
	view_closed.emit()


func _restore_player_view() -> void:
	set_process_input(false)
	var root_viewport := get_viewport()
	if root_viewport != null and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		var current_camera := root_viewport.get_camera_3d()
		if current_camera == terminal_camera or current_camera == null:
			_previous_camera.make_current()
	if is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
	if is_instance_valid(_wieldables):
		_wieldables.visible = _wieldables_were_visible
	if is_instance_valid(_player):
		# Process-disable stops the player's stick-event cache as well as movement.
		if _player.joystick_h_event:
			_player.joystick_h_event = _player.joystick_h_event.duplicate()
			_player.joystick_h_event.axis_value = Input.get_joy_axis(_player.joystick_h_event.device, _player.joystick_h_event.axis)
		if _player.joystick_v_event:
			_player.joystick_v_event = _player.joystick_v_event.duplicate()
			_player.joystick_v_event.axis_value = Input.get_joy_axis(_player.joystick_v_event.device, _player.joystick_v_event.axis)
		_player.process_mode = _previous_process_mode
	Input.mouse_mode = _previous_mouse_mode
	is_viewing = false
	is_transitioning = false
	_closing = false
	_player = null
	_previous_camera = null
	_hud = null
	_wieldables = null


func _input(event: InputEvent) -> void:
	if not is_viewing:
		return
	# Consume root input even during camera travel; only GUI events enter the screen.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		if not _closing:
			panel.close_requested.emit()
		return
	if is_transitioning:
		return
	if event is InputEventMouse:
		_forward_mouse(event)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		for action in UI_ACTIONS:
			if event.is_action(action):
				screen_viewport.push_input(event.duplicate(), true)
				break


func _forward_mouse(event: InputEventMouse) -> void:
	if event is InputEventMouseButton and event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var screen_position := _project_mouse(event.position)
	var inside := Rect2(Vector2.ZERO, Vector2(screen_viewport.size)).has_point(screen_position)
	var was_inside := _mouse_inside
	_set_mouse_inside(inside)
	# Outside releases must still cancel a button pressed while inside the screen.
	if event is InputEventMouseButton and event.pressed and not inside:
		return
	var forwarded := event.duplicate() as InputEventMouse
	forwarded.position = screen_position
	forwarded.global_position = screen_position
	if forwarded is InputEventMouseMotion:
		forwarded.relative = screen_position - _last_mouse_position if inside and was_inside else Vector2.ZERO
		forwarded.velocity = Vector2.ZERO
	_last_mouse_position = screen_position
	screen_viewport.push_input(forwarded, true)


func _project_mouse(root_position: Vector2) -> Vector2:
	# Intersect the authored QuadMesh plane in its own coordinates, then map +Y to UV down.
	var ray_origin := screen_mesh.to_local(terminal_camera.project_ray_origin(root_position))
	var ray_direction := screen_mesh.global_transform.basis.inverse() * terminal_camera.project_ray_normal(root_position)
	if ray_origin.z <= 0.0 or ray_direction.z >= -0.00001:
		return Vector2(-1, -1)
	var hit := ray_origin + ray_direction * (-ray_origin.z / ray_direction.z)
	var quad := screen_mesh.mesh as QuadMesh
	var uv := Vector2(hit.x / quad.size.x + 0.5, 0.5 - hit.y / quad.size.y)
	return uv * Vector2(screen_viewport.size)


func _set_mouse_inside(inside: bool) -> void:
	if _mouse_inside == inside:
		return
	_mouse_inside = inside
	if inside:
		screen_viewport.notify_mouse_entered()
	else:
		screen_viewport.notify_mouse_exited()


func _exit_tree() -> void:
	if is_instance_valid(_camera_tween):
		_camera_tween.kill()
	if is_viewing:
		_restore_player_view()
		view_closed.emit()
