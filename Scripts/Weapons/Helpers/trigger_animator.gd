## Animates a trigger mesh child via Z-rotation tweens.
## Extracted from cogito_weapon.gd to isolate trigger animation lifecycle.
class_name TriggerAnimator
extends RefCounted

const TWEEN_DURATION: float = 0.06

var _owner: Node3D
var _trigger_mesh: Node3D = null
var _tween: Tween = null
var press_time: float = -1.0


func _init(owner: Node3D) -> void:
	_owner = owner
	_trigger_mesh = owner.get_node_or_null("trigger") as Node3D


func has_trigger() -> bool:
	return _trigger_mesh != null


func pull(target_z_deg: float) -> void:
	if _trigger_mesh == null:
		return
	_kill_tween()
	_tween = _owner.create_tween()
	_tween.tween_property(_trigger_mesh, "rotation_degrees:z", target_z_deg, TWEEN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func release_delayed(target_z_deg: float, delay: float) -> void:
	if _trigger_mesh == null:
		return
	_kill_tween()
	_tween = _owner.create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_property(_trigger_mesh, "rotation_degrees:z", target_z_deg, TWEEN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _kill_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = null
