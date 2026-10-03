extends BTCondition

## Guard: SUCCESS once enough consecutive shots have been fired that it's
## time to reposition (bt_strafe resets the counter on completion). This is
## the tree-level "when to strafe" decision — bt_strafe.gd itself no longer
## gates on internal randf()/cooldown checks.

func _tick(_delta: float) -> Status:
	var npc := agent as HostileNPC
	var threshold: int = npc.ai_profile.strafe_after_shots if npc and npc.ai_profile else 2
	var shots: int = blackboard.get_var(&"shots_fired_since_strafe", 0, false)
	return SUCCESS if shots >= threshold else FAILURE
