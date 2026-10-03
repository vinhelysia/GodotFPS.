extends Node3D
class_name CogitoPerception
## Shared NPC vision — proximity + FOV cone + multi-point line-of-sight.
## Attach as a child of a CogitoNPC. Owns `Host.attention_target` and drives the
## NPC state machine into "chase" when the target is spotted; clears on loss.
##
## PHASE 1: vision only (FOV + LOS). Hearing, awareness accumulator, last-known
## position and squad alerts come in later phases — see docs/project/Roadmap.md.

@export_group("Vision")
## Max distance the NPC can see (metres).
@export var sight_range: float = 25.0
## Total horizontal field-of-view cone (degrees). Target outside = invisible.
@export_range(10.0, 360.0, 1.0, "suffix:°") var fov_degrees: float = 120.0
## Eye height above the NPC origin — ray origin for LOS.
@export var eye_height: float = 1.6
## Seconds the target must stay visible before the NPC reacts.
## (Flat for Phase 1; Phase 2 scales this by distance/pose/movement.)
@export var time_to_notice: float = 0.5
## Seconds the target can stay unseen before the NPC loses it and stands down.
@export var lose_time: float = 4.0
## Group name of things this NPC hunts.
@export var target_group: StringName = &"Player"

@export_group("Line of Sight")
## Physics layers LOS rays test against (world + target). Default = layers 1 & 2.
@export_flags_3d_physics var los_mask: int = 3

var _host: CogitoNPC
var _sm: Node
var _target: Node3D = null
var _seen_time: float = 0.0
var _unseen_time: float = 0.0
var _alerted: bool = false


func _ready() -> void:
	_host = get_parent() as CogitoNPC
	if _host == null:
		push_error("CogitoPerception must be a child of a CogitoNPC.")
		set_physics_process(false)
		return
	_sm = _host.get_node_or_null("NPC_State_Machine")


func _physics_process(delta: float) -> void:
	var target := _find_target()
	var can_see := target != null and _can_see(target)

	if can_see:
		_target = target
		_unseen_time = 0.0
		_seen_time += delta
		if not _alerted and _seen_time >= time_to_notice:
			_spot(target)
	else:
		_seen_time = 0.0
		if _alerted:
			_unseen_time += delta
			if _unseen_time >= lose_time:
				_lose()


func _find_target() -> Node3D:
	var nodes := get_tree().get_nodes_in_group(target_group)
	if nodes.is_empty():
		return null
	return nodes[0] as Node3D


## True when target is within range, inside the FOV cone, AND has clear LOS
## to either the head or the chest.
func _can_see(target: Node3D) -> bool:
	var eye := global_position + Vector3.UP * eye_height
	var to_target := target.global_position - eye
	if to_target.length() > sight_range:
		return false

	# FOV cone — measured horizontally against NPC forward (-Z).
	var forward := -_host.global_transform.basis.z
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	if flat_to.length() > 0.01:
		var angle := rad_to_deg(forward.angle_to(flat_to.normalized()))
		if angle > fov_degrees * 0.5:
			return false

	# Multi-point LOS — head first (uses player's head node when available), then chest.
	return _los_clear(eye, _aim_point(target, 1.6)) or _los_clear(eye, _aim_point(target, 1.0))


func _aim_point(target: Node3D, height: float) -> Vector3:
	if height >= 1.5:
		var head_val: Variant = target.get("head")
		if head_val is Node3D and is_instance_valid(head_val):
			return (head_val as Node3D).global_position
	return target.global_position + Vector3.UP * height


func _los_clear(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = los_mask
	params.exclude = [_host.get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return true
	var collider: Object = hit["collider"]
	return collider == _target or (collider is Node and (collider as Node).is_in_group(target_group))


func _spot(target: Node3D) -> void:
	_alerted = true
	_host.attention_target = target
	if _sm and _is_idle_or_patrol():
		_sm.goto("chase")


func _lose() -> void:
	_alerted = false
	_seen_time = 0.0
	_unseen_time = 0.0
	_host.attention_target = null


func _is_idle_or_patrol() -> bool:
	if _sm == null:
		return false
	var s: String = _sm.current
	return s == "idle" or s == "patrol_on_path" or s == "move_to_random_pos"
