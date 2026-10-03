extends BTAction

## Patrol along the CogitoPatrolPath. The reactive BTSelector at root
## preempts this task automatically when a higher-priority guard succeeds —
## no self-abort logic needed here.

@export var patrol_point_wait_time: float = 3.0
@export var tolerance: float = 0.5
## After this many consecutive unreachable points, idle instead of spinning the path forever.
@export var max_unreachable_skips: int = 8

var _patrol_point_index: int = 0
var _wait_timer: float = 0.0
var _is_waiting: bool = false
var _unreachable_skips: int = 0


func _enter() -> void:
	var npc: CogitoNPC = agent as CogitoNPC
	if npc == null or npc.patrol_path == null:
		_is_waiting = true
		_wait_timer = 1.0
		return

	_is_waiting = false
	_wait_timer = 0.0
	_unreachable_skips = 0
	_set_destination(npc)


func _tick(delta: float) -> Status:
	var npc: CogitoNPC = agent as CogitoNPC
	if npc == null:
		return FAILURE

	if npc.patrol_path == null or npc.patrol_path.patrol_points.is_empty():
		npc.velocity = Vector3.ZERO
		npc.update_animations(delta)
		return SUCCESS

	var nav_agent: NavigationAgent3D = npc.navigation_agent_3d

	if _is_waiting:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, delta * npc.move_speed)
		npc.velocity.z = move_toward(npc.velocity.z, 0.0, delta * npc.move_speed)
		if not npc.is_on_floor():
			npc.velocity += npc.get_gravity() * delta
		npc.move_and_slide()
		npc.update_animations(delta)

		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_is_waiting = false
			_iterate_patrol_point(npc)
			_set_destination(npc)
		return RUNNING

	if not nav_agent.is_target_reachable():
		_unreachable_skips += 1
		if _unreachable_skips >= max_unreachable_skips:
			npc.velocity = Vector3.ZERO
			npc.update_animations(delta)
			return FAILURE
		_iterate_patrol_point(npc)
		_set_destination(npc)
		return RUNNING
	_unreachable_skips = 0

	if nav_agent.is_navigation_finished() or npc.global_position.distance_to(nav_agent.target_position) <= tolerance:
		_is_waiting = true
		_wait_timer = patrol_point_wait_time
		return RUNNING

	var next_position := nav_agent.get_next_path_position()

	if not npc.is_on_floor():
		npc.velocity += npc.get_gravity() * delta

	var direction := npc.global_position.direction_to(next_position)
	var face_dir := Vector3(
		npc.global_position.x + npc.velocity.x,
		npc.global_position.y,
		npc.global_position.z + npc.velocity.z,
	)

	if direction:
		npc.face_direction(face_dir)
		npc.velocity.x = direction.x * npc.move_speed
		npc.velocity.z = direction.z * npc.move_speed
	else:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, npc.move_speed)
		npc.velocity.z = move_toward(npc.velocity.z, 0.0, npc.move_speed)

	npc.move_and_slide()
	npc.update_animations(delta)
	return RUNNING


func _set_destination(npc: CogitoNPC) -> void:
	if npc.patrol_path and not npc.patrol_path.patrol_points.is_empty():
		var point := npc.patrol_path.patrol_points[_patrol_point_index]
		if is_instance_valid(point):
			npc.navigation_agent_3d.target_position = point.global_position


func _iterate_patrol_point(npc: CogitoNPC) -> void:
	if npc.patrol_path and not npc.patrol_path.patrol_points.is_empty():
		_patrol_point_index = (_patrol_point_index + 1) % npc.patrol_path.patrol_points.size()
