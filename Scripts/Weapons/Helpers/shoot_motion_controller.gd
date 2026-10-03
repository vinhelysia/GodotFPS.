## Manages shoot-kick tweens (position + rotation) on the weapon node.
## Extracted from cogito_weapon.gd to isolate tween lifecycle.
class_name ShootMotionController
extends RefCounted

var _owner: Node3D  # The weapon node (cogito_weapon)
var _shoot_tween: Tween = null
var _fire_part_tween: Tween = null
var _shoot_state_tween: Tween = null
var is_active: bool = false

# Config (set from weapon exports via sync)
var hip_shot_position_offset: Vector3
var hip_shot_rotation_deg: Vector3
var ads_shot_position_offset: Vector3
var ads_shot_rotation_deg: Vector3
var shoot_kick_out_time: float
var shoot_return_time: float

# Fire part config
var fire_part: Node3D = null
var fire_part_rest_position: Vector3
var fire_part_position_offset: Vector3
var fire_part_out_time: float
var fire_part_return_time: float
var fire_part_locked: bool = false

signal shoot_visual_finished


func _init(owner: Node3D) -> void:
	_owner = owner


func play(rest_position: Vector3, rest_rotation: Vector3, is_aiming: bool) -> void:
	cancel(true)
	is_active = true
	var pos_offset := ads_shot_position_offset if is_aiming else hip_shot_position_offset
	var rot_offset := ads_shot_rotation_deg if is_aiming else hip_shot_rotation_deg
	var kick_pos := rest_position + pos_offset
	var kick_rot := rest_rotation + rot_offset

	_shoot_tween = _owner.create_tween()
	_shoot_tween.tween_property(_owner, "position", kick_pos, shoot_kick_out_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_shoot_tween.parallel().tween_property(_owner, "rotation_degrees", kick_rot, shoot_kick_out_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_shoot_tween.tween_property(_owner, "position", rest_position, shoot_return_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_shoot_tween.parallel().tween_property(_owner, "rotation_degrees", rest_rotation, shoot_return_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if fire_part and fire_part_position_offset.length() > 0.0:
		_fire_part_tween = _owner.create_tween()
		_fire_part_tween.tween_property(fire_part, "position", fire_part_rest_position + fire_part_position_offset, fire_part_out_time)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		if not fire_part_locked:
			_fire_part_tween.tween_property(fire_part, "position", fire_part_rest_position, fire_part_return_time)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	_shoot_state_tween = _owner.create_tween()
	_shoot_state_tween.tween_interval(get_duration())
	_shoot_state_tween.finished.connect(_on_finished)


func get_duration() -> float:
	var root_dur := maxf(0.0, shoot_kick_out_time) + maxf(0.0, shoot_return_time)
	var part_dur := 0.0
	if fire_part and fire_part_position_offset.length() > 0.0:
		part_dur = maxf(0.0, fire_part_out_time) + maxf(0.0, fire_part_return_time)
	return maxf(root_dur, part_dur)


func cancel(_restore_rest: bool) -> void:
	if _shoot_tween:
		_shoot_tween.kill()
		_shoot_tween = null
	if _fire_part_tween:
		_fire_part_tween.kill()
		_fire_part_tween = null
	if _shoot_state_tween:
		_shoot_state_tween.kill()
		_shoot_state_tween = null
	is_active = false
	# Note: restore_rest is a hint for the caller; this class does not
	# know the rest pose. The caller applies it after cancel().


func release_fire_part_lock() -> void:
	if not fire_part_locked or fire_part == null:
		return
	fire_part_locked = false
	if _fire_part_tween:
		_fire_part_tween.kill()
		_fire_part_tween = null
	_fire_part_tween = _owner.create_tween()
	_fire_part_tween.tween_property(fire_part, "position", fire_part_rest_position, fire_part_return_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fire_part_tween.finished.connect(func(): _fire_part_tween = null)


func _on_finished() -> void:
	is_active = false
	shoot_visual_finished.emit()
