class_name FirearmMechanicalState
extends RefCounted

const SAVE_VERSION: int = 1

# Configuration parameters (static, configured via configure())
var magazine_capacity: int = 30
var chamber_capacity: int = 1
var auto_chambers_on_empty_reload: bool = true
var locks_open_on_empty: bool = false

# Current state (dynamic)
var magazine_rounds: int = 0
var chamber_rounds: int = 0
var bolt_locked_open: bool = false


func configure(config: Dictionary) -> void:
	magazine_capacity = config.get("magazine_capacity", 30)
	chamber_capacity = config.get("chamber_capacity", 1)
	auto_chambers_on_empty_reload = config.get("auto_chambers_on_empty_reload", true)
	locks_open_on_empty = config.get("locks_open_on_empty", false)
	_clamp_dynamic_state()


func reconstruct_from_total(total: int) -> void:
	# Reconstruct mechanical state from Cogito's total saved charge
	bolt_locked_open = false
	if total <= 0:
		chamber_rounds = 0
		magazine_rounds = 0
	elif total == 1:
		if chamber_capacity > 0:
			chamber_rounds = 1
			magazine_rounds = 0
		else:
			chamber_rounds = 0
			magazine_rounds = 1
	else:
		if chamber_capacity > 0:
			chamber_rounds = chamber_capacity
			magazine_rounds = total - chamber_capacity
		else:
			chamber_rounds = 0
			magazine_rounds = total
	
	_clamp_dynamic_state()


func to_save_dict() -> Dictionary:
	_clamp_dynamic_state()
	return {
		"version": SAVE_VERSION,
		"magazine_rounds": magazine_rounds,
		"chamber_rounds": chamber_rounds,
		"bolt_locked_open": bolt_locked_open,
	}


func restore_from_save_dict(state: Dictionary) -> bool:
	if state.is_empty() or int(state.get("version", 0)) != SAVE_VERSION:
		return false
	magazine_rounds = int(state.get("magazine_rounds", 0))
	chamber_rounds = int(state.get("chamber_rounds", 0))
	bolt_locked_open = state.get("bolt_locked_open", false) == true
	_clamp_dynamic_state()
	return true


func can_fire() -> bool:
	return chamber_rounds > 0


## No magazine (capacity 0) means the weapon can only be hand-loaded one round
## into the chamber — the magazine attachment is what makes it feed.
func has_no_magazine() -> bool:
	return magazine_capacity <= 0


func has_reload_room() -> bool:
	if has_no_magazine():
		return chamber_rounds < chamber_capacity
	return magazine_rounds < magazine_capacity


func fire_round() -> void:
	if chamber_rounds > 0:
		chamber_rounds -= 1


func cycle_action() -> void:
	# Cycle next round from magazine to chamber if chamber is empty and magazine has rounds
	if chamber_rounds < chamber_capacity and magazine_rounds > 0:
		var rounds_to_chamber := mini(chamber_capacity - chamber_rounds, magazine_rounds)
		chamber_rounds += rounds_to_chamber
		magazine_rounds -= rounds_to_chamber


func finish_reload_tactical(reserve_rounds: int) -> int:
	if has_no_magazine():
		return _hand_load_chamber(reserve_rounds)
	# Refill magazine from reserve, keeping chamber round intact
	var rounds_needed := magazine_capacity - magazine_rounds
	var actual_loaded := mini(reserve_rounds, rounds_needed)
	magazine_rounds += actual_loaded
	return actual_loaded


func finish_reload_empty(reserve_rounds: int) -> int:
	# Refill from complete empty state
	if reserve_rounds <= 0:
		return 0
	if has_no_magazine():
		return _hand_load_chamber(reserve_rounds)

	var actual_consumed := 0
	if auto_chambers_on_empty_reload:
		# Auto chambering: 1 round feeds to chamber, rest goes to magazine
		var max_capacity := magazine_capacity + chamber_capacity
		var rounds_to_load := mini(reserve_rounds, max_capacity)
		actual_consumed = rounds_to_load
		
		if rounds_to_load > 0:
			if chamber_capacity > 0:
				chamber_rounds = chamber_capacity
				magazine_rounds = rounds_to_load - chamber_capacity
			else:
				chamber_rounds = 0
				magazine_rounds = rounds_to_load
	else:
		# No auto chambering (e.g. manual bolt cycle required first)
		# Magazine fills up, chamber remains empty
		var rounds_needed := magazine_capacity - magazine_rounds
		var actual_loaded := mini(reserve_rounds, rounds_needed)
		magazine_rounds += actual_loaded
		actual_consumed = actual_loaded
		
	return actual_consumed


## Single-loads the chamber when no magazine is fitted. Ignores
## auto_chambers_on_empty_reload: with no magazine there is nothing to feed
## from, so the round goes straight into the chamber by hand.
func _hand_load_chamber(reserve_rounds: int) -> int:
	var loaded := mini(reserve_rounds, chamber_capacity - chamber_rounds)
	chamber_rounds += loaded
	return loaded


func get_loaded_total() -> int:
	return magazine_rounds + chamber_rounds


func is_empty() -> bool:
	return magazine_rounds == 0 and chamber_rounds == 0


func _clamp_dynamic_state() -> void:
	magazine_rounds = clampi(magazine_rounds, 0, magazine_capacity)
	chamber_rounds = clampi(chamber_rounds, 0, chamber_capacity)
	if not locks_open_on_empty:
		bolt_locked_open = false
	elif not is_empty():
		bolt_locked_open = false
