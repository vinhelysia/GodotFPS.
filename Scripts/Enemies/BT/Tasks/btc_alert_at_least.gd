extends BTCondition

## Guard: returns SUCCESS when alert >= min_level.
## Alert enum: RELAXED=0, SUSPICIOUS=1, COMBAT=2

@export var min_level: int = 2  # COMBAT by default

func _tick(_delta: float) -> Status:
	var alert: int = blackboard.get_var(&"alert", 0)
	return SUCCESS if alert >= min_level else FAILURE
