extends BTAction

## BTAction that makes the NPC face the target.

@export var target_var: StringName = &"target"

func _tick(_delta: float) -> Status:
	var target = blackboard.get_var(target_var, null, false)
	if not is_instance_valid(target) or not target is Node3D:
		return FAILURE

	var npc: CogitoNPC = agent as CogitoNPC
	if npc == null:
		return FAILURE

	npc.face_direction(target.global_position)
	return SUCCESS
