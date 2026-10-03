extends BTAction

## Look left and right at the investigation point, then clear the investigation
## target and return SUCCESS so the NPC can go back to patrol.
## Preemption by a higher-priority COMBAT guard is handled by the reactive
## root BTSelector — no alert checks needed here.

@export var look_time: float = 4.0

var _timer: float = 0.0
var _phase_timer: float = 0.0
var _look_left: bool = true


func _enter() -> void:
	_timer = look_time
	_phase_timer = 0.0
	_look_left = true


func _tick(delta: float) -> Status:
	var npc: CogitoNPC = agent as CogitoNPC
	if npc == null:
		return FAILURE

	_timer -= delta
	if _timer <= 0.0:
		blackboard.set_var(&"has_last_known", false)
		return SUCCESS

	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_phase_timer = 1.5
		_look_left = not _look_left

	var forward := -npc.global_transform.basis.z
	var angle := 45.0 if _look_left else -45.0
	var look_target := npc.global_position + forward.rotated(Vector3.UP, deg_to_rad(angle)).normalized() * 5.0
	npc.face_direction(look_target)

	var rate: float = delta * npc.sprint_speed * 6.0
	npc.velocity.x = move_toward(npc.velocity.x, 0.0, rate)
	npc.velocity.z = move_toward(npc.velocity.z, 0.0, rate)
	if not npc.is_on_floor():
		npc.velocity += npc.get_gravity() * delta
	npc.move_and_slide()
	npc.update_animations(delta)
	return RUNNING
