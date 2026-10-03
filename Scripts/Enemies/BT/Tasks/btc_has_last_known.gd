extends BTCondition

## Guard: returns SUCCESS when there is a known position to investigate.

func _tick(_delta: float) -> Status:
	return SUCCESS if blackboard.get_var(&"has_last_known", false) else FAILURE
