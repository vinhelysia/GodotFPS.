extends Weapon_Resource

class_name BoltAction_Resource

func _init() -> void:
	magazine_capacity = 5
	chamber_capacity = 1
	locks_open_on_empty = false
	manual_cycle_required = true
	auto_chambers_on_empty_reload = false

@export_group("Bolt Action")
## Animation name for the bolt cycling action played after each shot.
@export var boltCycleAnimation: String = "bolt_cycle"
## Duration of the bolt cycle in seconds (used as fallback if no animation).
@export var boltCycleDuration: float = 0.8

@export_group("Bolt Tween")
## Bolt handle rotation when locked/closed (radians). Match the rest keyframe in your AnimationPlayer.
@export var bolt_locked_rotation: Vector3 = Vector3(-0.39269873, 0.0, -1.570796)
## Bolt handle rotation when unlocked/open.
@export var bolt_unlocked_rotation: Vector3 = Vector3(-1.2234758, 0.0017453292, -1.5742869)
## Bolt position when fully forward (chambered).
@export var bolt_position_forward: Vector3 = Vector3(0.05584554, 0.059166227, 0.0)
## Bolt position when fully back (ejected).
@export var bolt_position_back: Vector3 = Vector3(-0.1278401, 0.059375823, -0.0010124445)
## Duration in seconds for each bolt phase.
@export var bolt_unlock_duration: float = 0.2
@export var bolt_pull_duration: float = 0.233
@export var bolt_hold_duration: float = 0.2
@export var bolt_push_duration: float = 0.167
@export var bolt_lock_duration: float = 0.233
## Root viewmodel position offset at peak of bolt cycle (applied relative to current position).
@export var bolt_root_position_offset: Vector3 = Vector3(-0.137, -0.032, 0.032)
## Root viewmodel rotation offset at peak of bolt cycle (radians, applied relative to current rotation).
@export var bolt_root_rotation_offset: Vector3 = Vector3(-0.2617994, 0.0174532, 0.034906585)
## Time to ease the viewmodel out to the bolt-cycle peak offset.
@export var bolt_root_out_duration: float = 0.5
## Time to ease the viewmodel back to its rest pose after the bolt closes.
@export var bolt_root_return_duration: float = 0.7

@export_group("Shell Ejection Timing")
## Seconds after bolt cycle starts before the shell casing is ejected.
## Default matches the moment the bolt finishes unlocking and starts pulling back.
## Only used when the weapon's Shell Eject Timing is set to On Cycle and bolt tween is active.
@export var shell_eject_delay: float = 0.267

func get_fire_mode() -> FireMode:
	return FireMode.BOLT_ACTION


func handles_own_shell_eject(weapon: Node) -> bool:
	# Bolt-action always handles its own eject — either through the bolt-tween
	# shell_eject_delay path or through the cycle animation. The orchestrator's
	# ON_FIRE eject would fire too early.
	return (weapon as CogitoFirearm)._bolt_part != null


func play_post_fire_visual(weapon: Node) -> void:
	var firearm := weapon as CogitoFirearm
	firearm._state = CogitoFirearm.WeaponState.CYCLING
	# Animation-shoot-motion mode chains the cycle in on_anim_finished instead.
	if firearm._uses_animation_shoot_motion():
		return
	firearm._schedule_post_fire_cycle(firearm._get_shoot_visual_duration(),
			_start_cycle.bind(firearm))


func on_anim_finished(weapon: Node, anim_name: StringName) -> void:
	var firearm := weapon as CogitoFirearm
	# Shoot animation finished → kick off the bolt cycle (animation shoot mode).
	if firearm._uses_animation_shoot_motion() and firearm._is_shoot_animation_name(anim_name):
		_start_cycle(firearm)
		return
	# Bolt-cycle animation finished → ready for next shot.
	if _is_bolt_cycle_anim(firearm, anim_name):
		firearm.on_cycle_complete()
		firearm._state = CogitoFirearm.WeaponState.IDLE
		firearm._capture_rest_state()


func on_reset(weapon: Node) -> void:
	var firearm := weapon as CogitoFirearm
	if firearm._bolt_part != null:
		firearm._bolt_part.position = bolt_position_forward
		firearm._bolt_part.rotation = bolt_locked_rotation


# ── Internal ─────────────────────────────────────────────────────────────────

## Drives the bolt-cycle viewmodel motion. Relocated from cogito_weapon.gd so the
## shared orchestrator stays weapon-type-agnostic (no `as BoltAction_Resource`).
## Reaches into `firearm` internals — the same delegation style the other virtuals
## (play_post_fire_visual/on_anim_finished) already use.
func run_bolt_tween(firearm: CogitoFirearm) -> void:
	if firearm._bolt_cycle_tween:
		firearm._bolt_cycle_tween.kill()
	if firearm._bolt_root_tween:
		firearm._bolt_root_tween.kill()

	# Capture rest transform now — works from any position (hip or ADS)
	var base_pos := firearm.position
	var base_rot := firearm.rotation

	# Save the authoritative rest rotation before any tweening.
	# Restored explicitly before _capture_rest_state() to prevent drift.
	firearm._bolt_pre_cycle_rest_rot = firearm._rest_rotation_degrees

	# Root viewmodel motion — eases to offset as bolt pulls back, returns as it closes
	firearm._bolt_root_tween = firearm.create_tween().set_trans(Tween.TRANS_SINE)
	firearm._bolt_root_tween.tween_property(firearm, "position",
		base_pos + bolt_root_position_offset, bolt_root_out_duration)
	firearm._bolt_root_tween.parallel().tween_property(firearm, "rotation",
		base_rot + bolt_root_rotation_offset, bolt_root_out_duration)
	firearm._bolt_root_tween.tween_property(firearm, "position", base_pos, bolt_root_return_duration)
	firearm._bolt_root_tween.parallel().tween_property(firearm, "rotation", base_rot, bolt_root_return_duration)

	# Shell ejection timed to bolt pull-back moment — always handled here for bolt tween.
	var shell_timer := firearm.create_tween()
	shell_timer.tween_interval(shell_eject_delay)
	shell_timer.tween_callback(firearm._spawn_shell_casing)

	# Bolt handle sequential tween
	firearm._bolt_cycle_tween = firearm.create_tween().set_trans(Tween.TRANS_SINE)
	# 1. Unlock: rotate handle up
	firearm._bolt_cycle_tween.tween_property(firearm._bolt_part, "rotation",
		bolt_unlocked_rotation, bolt_unlock_duration)
	# 2. Pause before pulling
	firearm._bolt_cycle_tween.tween_interval(0.067)
	# 3. Pull bolt back
	firearm._bolt_cycle_tween.tween_property(firearm._bolt_part, "position",
		bolt_position_back, bolt_pull_duration)
	# 4. Hold
	firearm._bolt_cycle_tween.tween_interval(bolt_hold_duration)
	# 5. Push bolt forward
	firearm._bolt_cycle_tween.tween_property(firearm._bolt_part, "position",
		bolt_position_forward, bolt_push_duration)
	# 6. Pause before locking
	firearm._bolt_cycle_tween.tween_interval(0.1)
	# 7. Lock: rotate handle down
	firearm._bolt_cycle_tween.tween_property(firearm._bolt_part, "rotation",
		bolt_locked_rotation, bolt_lock_duration)
	firearm._bolt_cycle_tween.finished.connect(func():
		firearm._bolt_cycle_tween = null
		if firearm._bolt_root_tween:
			firearm._bolt_root_tween.kill()
			firearm._bolt_root_tween = null
		# Restore rotation to pre-cycle rest value before _capture_rest_state() reads it
		firearm.rotation_degrees = firearm._bolt_pre_cycle_rest_rot
		firearm.on_cycle_complete()
		firearm._state = CogitoFirearm.WeaponState.IDLE
		firearm._capture_rest_state()
	)


func _start_cycle(firearm: CogitoFirearm) -> void:
	firearm._post_fire_cycle_tween = null
	if firearm._bolt_part != null:
		run_bolt_tween(firearm)
		return
	if firearm.shell_eject_timing == CogitoFirearm.ShellEjectTiming.ON_CYCLE:
		firearm._spawn_shell_casing()
	var anim := _get_cycle_anim_name(firearm)
	if anim != "" and firearm.animation_player.has_animation(anim):
		firearm.animation_player.play(anim)
	else:
		firearm._complete_cycle_after_delay(boltCycleDuration,
				_finish_cycle.bind(firearm))


func _finish_cycle(firearm: CogitoFirearm) -> void:
	firearm._post_fire_cycle_tween = null
	firearm.on_cycle_complete()
	firearm._state = CogitoFirearm.WeaponState.IDLE
	firearm._capture_rest_state()


func _get_cycle_anim_name(firearm: CogitoFirearm) -> String:
	if firearm._ads.is_aiming and firearm.bolt_cycle_animation_ads != "" \
			and firearm.animation_player.has_animation(firearm.bolt_cycle_animation_ads):
		return firearm.bolt_cycle_animation_ads
	return boltCycleAnimation


func _is_bolt_cycle_anim(firearm: CogitoFirearm, anim_name: StringName) -> bool:
	return anim_name == boltCycleAnimation \
		or (firearm.bolt_cycle_animation_ads != "" and anim_name == firearm.bolt_cycle_animation_ads)
