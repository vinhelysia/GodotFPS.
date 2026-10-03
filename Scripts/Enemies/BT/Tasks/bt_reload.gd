extends BTAction

## Reload. Returns FAILURE immediately if ammo > 0 (nothing to reload).
## This lets the CombatActions selector fall through to Shoot first.
##
## Magazine size comes from the agent's equipped weapon (charge_max); reload
## speed comes from the agent's ai_profile (faction skill) — NOT the weapon.
##
## Retreats straight away from the target while reloading instead of
## braking to a stop — never caught standing still and exposed mid-reload.
##
## Finite ammo: an NPC with pockets (loadout assigned) draws the refill from
## npc.take_reserve_ammo() instead of getting a free full mag. If reserve is
## empty, this bails BEFORE the reload wait (no doomed reload animation) —
## with ammo still at 0 and reloading still false, the CombatActions
## selector's existing FAILURE-cascade naturally falls through to
## MoveToTarget on its own; no BT structure changes needed. NPCs without
## pockets (no loadout) keep the old free-refill behavior forever.

@export var reload_sound: AudioStream

var _timer: float = 0.0
var _skip: bool = false


func _enter() -> void:
	var npc := agent as HostileNPC
	var mag_size: int = npc.magazine_size() if npc else 5
	var ammo: int = blackboard.get_var(&"ammo", mag_size)
	var reloading: bool = blackboard.get_var(&"reloading", false)
	if ammo > 0 and not reloading:
		_skip = true
		return

	if npc and npc.pockets != null and not npc.has_reserve_ammo():
		blackboard.set_var(&"no_reserve_ammo", true)
		_skip = true
		return

	_skip = false
	blackboard.set_var(&"reloading", true)
	_timer = npc.ai_profile.reload_time if npc and npc.ai_profile else 2.5

	if npc and reload_sound and is_instance_valid(Audio):
		Audio.play_sound_3d(reload_sound, false).global_position = npc.global_position


func _tick(delta: float) -> Status:
	if _skip:
		return FAILURE

	var npc: HostileNPC = agent as HostileNPC

	_timer -= delta
	if _timer <= 0.0:
		var mag_size: int = npc.magazine_size() if npc else 5
		if npc and npc.pockets != null:
			var refill: int = npc.take_reserve_ammo(mag_size)
			blackboard.set_var(&"ammo", refill)
			blackboard.set_var(&"no_reserve_ammo", refill <= 0)
		else:
			blackboard.set_var(&"ammo", mag_size)
			blackboard.set_var(&"no_reserve_ammo", false)
		blackboard.set_var(&"reloading", false)
		return SUCCESS

	if npc:
		_move_while_reloading(npc, delta)

	return RUNNING


func _move_while_reloading(npc: HostileNPC, delta: float) -> void:
	var target: Variant = blackboard.get_var(&"target", null, false)
	var move_dir := Vector3.ZERO
	if is_instance_valid(target) and target is Node3D:
		move_dir = npc.global_position - (target as Node3D).global_position
		move_dir.y = 0.0
		if move_dir.length_squared() > 0.0001:
			move_dir = move_dir.normalized()
		else:
			move_dir = Vector3.ZERO
		npc.face_direction((target as Node3D).global_position)

	if not npc.is_on_floor():
		npc.velocity += npc.get_gravity() * delta

	if move_dir != Vector3.ZERO:
		npc.velocity.x = move_dir.x * npc.walk_speed
		npc.velocity.z = move_dir.z * npc.walk_speed
	else:
		var rate: float = delta * npc.sprint_speed * 6.0
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, rate)
		npc.velocity.z = move_toward(npc.velocity.z, 0.0, rate)

	npc.move_and_slide()
	npc.update_animations(delta)
