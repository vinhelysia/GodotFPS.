## Manages ADS (aim down sights) transitions: FOV tween + weapon position tween.
## Extracted from cogito_weapon.gd to isolate ADS lifecycle.
class_name ADSController
extends RefCounted

const DEFAULT_FOV: float = 75.0

var _owner: Node3D  # The weapon node
var _camera_tween: Tween = null
var _weapon_tween: Tween = null
var is_aiming: bool = false

# Scope sensitivity
var _base_mouse_sens: float = -1.0


func _init(owner: Node3D) -> void:
	_owner = owner


func enter(weapon_data: Weapon_Resource, ads_fov: float, ads_time: float,
		ads_position: Vector3, default_position: Vector3,
		block_during_shot: bool, is_shot_active: bool,
		animation_player: AnimationPlayer,
		player_interaction_component: PlayerInteractionComponent) -> bool:
	if is_aiming:
		return false
	if animation_player.is_playing():
		return false
	if block_during_shot and is_shot_active:
		return false

	is_aiming = true
	_set_scope_rendering(true)
	_apply_scope_sensitivity(player_interaction_component)
	_cancel_tweens()
	_play_transition(weapon_data, ads_fov, ads_time, ads_position, default_position, false)

	if player_interaction_component:
		player_interaction_component.update_crosshair.emit(false)
	return true


func exit(weapon_data: Weapon_Resource, ads_fov: float, ads_time: float,
		default_position: Vector3, block_during_shot: bool,
		is_shot_active: bool, immediate: bool,
		player_interaction_component: PlayerInteractionComponent,
		duration_override: float = -1.0) -> void:
	if not is_aiming and not immediate:
		return
	if not immediate and block_during_shot and is_shot_active:
		return

	is_aiming = false
	_set_scope_rendering(false)
	_restore_scope_sensitivity(player_interaction_component)
	_cancel_tweens()
	_play_transition(weapon_data, ads_fov, ads_time, Vector3.ZERO, default_position,
			immediate, duration_override)

	if player_interaction_component:
		player_interaction_component.update_crosshair.emit(true)


func cancel_tweens_and_snap(weapon_data: Weapon_Resource, ads_fov: float,
		default_position: Vector3, ads_position: Vector3) -> void:
	_cancel_tweens()
	var camera := _owner.get_viewport().get_camera_3d()
	var target_fov := DEFAULT_FOV
	if is_aiming:
		var override_fov := weapon_data.get_ads_fov_override() if weapon_data else -1.0
		target_fov = override_fov if override_fov > 0.0 else ads_fov
	if camera:
		camera.fov = target_fov
	if weapon_data == null or not weapon_data.is_scope_weapon():
		_owner.position = get_rest_position(weapon_data, ads_position, default_position)


func get_rest_position(weapon_data: Weapon_Resource, ads_position: Vector3,
		default_position: Vector3) -> Vector3:
	if is_aiming and (weapon_data == null or not weapon_data.is_scope_weapon()):
		return Vector3(0, ads_position.y, ads_position.z)
	return default_position


func _play_transition(weapon_data: Weapon_Resource, ads_fov: float, ads_time: float,
		ads_position: Vector3, default_position: Vector3,
		immediate: bool, duration_override: float = -1.0) -> void:
	var camera := _owner.get_viewport().get_camera_3d()
	var is_scope := weapon_data != null and weapon_data.is_scope_weapon()
	var target_fov := DEFAULT_FOV
	var duration := duration_override if duration_override >= 0.0 else ads_time

	if is_aiming:
		var override_fov := weapon_data.get_ads_fov_override() if weapon_data else -1.0
		target_fov = override_fov if override_fov > 0.0 else ads_fov
		if duration_override < 0.0:
			var override_dur := weapon_data.get_ads_duration_override() if weapon_data else -1.0
			if override_dur > 0.0:
				duration = override_dur
	else:
		if duration_override < 0.0 and weapon_data and weapon_data.get_ads_duration_override() > 0.0:
			duration = weapon_data.get_ads_duration_override()

	if camera:
		if immediate:
			camera.fov = target_fov
		else:
			_camera_tween = _owner.create_tween()
			_camera_tween.tween_property(camera, "fov", target_fov, duration)

	if is_scope:
		return

	var target_pos := get_rest_position(weapon_data, ads_position, default_position)
	if immediate:
		_owner.position = target_pos
	else:
		_weapon_tween = _owner.create_tween()
		_weapon_tween.tween_property(_owner, "position", target_pos, duration)


func _cancel_tweens() -> void:
	if _camera_tween:
		_camera_tween.kill()
		_camera_tween = null
	if _weapon_tween:
		_weapon_tween.kill()
		_weapon_tween = null


func _apply_scope_sensitivity(pic: PlayerInteractionComponent) -> void:
	if pic == null:
		return
	var sc := _get_scope_controller()
	if sc == null:
		return
	var player := pic.get_parent() if pic else null
	if player == null or not "MOUSE_SENS" in player:
		return
	_base_mouse_sens = player.MOUSE_SENS
	player.MOUSE_SENS = _base_mouse_sens * sc.get_sensitivity_multiplier()


func _set_scope_rendering(enabled: bool) -> void:
	var sc := _get_scope_controller()
	if sc:
		sc.set_rendering_enabled(enabled)


func is_view_blocked() -> bool:
	var scope := _get_scope_controller()
	return scope != null and scope.is_view_blocked(_owner.get_viewport().get_camera_3d())


func _get_scope_controller() -> ScopeController:
	for child in _owner.get_children():
		if child is ScopeController:
			return child as ScopeController
	return null


func _restore_scope_sensitivity(pic: PlayerInteractionComponent) -> void:
	if _base_mouse_sens < 0.0:
		return
	var player := pic.get_parent() if pic else null
	if player and "MOUSE_SENS" in player:
		player.MOUSE_SENS = _base_mouse_sens
	_base_mouse_sens = -1.0
