extends BTAction

## Shoot the target. Returns FAILURE when: ammo <= 0, target out of engage
## range, or no line of sight. The CombatActions selector then tries Reload
## or MoveTo.
##
## Damage / fire rate / magazine size come from the agent's equipped weapon
## (HostileNPC.equipped_wieldable / equipped_weapon_data) — the SAME resources
## the player's real guns use. Accuracy / reaction / LOS grace / engage range
## come from the agent's ai_profile (faction skill), NOT the weapon, so the
## same gun feels different in different hands.
##
## Reaction beat: one deliberate pause at the START of each engagement
## (guarded by combat_reacted on the blackboard — persists across re-entries
## within the same COMBAT session; cleared by perception on RELAXED).
##
## Burst fire: rounds are grouped into bursts of ai_profile.burst_rounds_min-
## max, separated by a burst_pause_min-max pause — trigger discipline, not
## a full reposition (see btc_should_strafe.gd / bt_strafe.gd for that).

@export var shoot_sound: AudioStream
@export var muzzle_flash_scene: PackedScene
@export var debug_shoot: bool = false

var _fire_timer: float = 0.0
var _reaction_timer: float = 0.0
var _has_reacted: bool = false
var _los_lost_timer: float = 0.0
var _rounds_left_in_burst: int = 0
var _burst_pause_timer: float = 0.0

## Layers 1|2|5 — Environment + Interactables (doors/props) + Player.
## Matches Weapon_Resource.COLLISION_MASK_DAMAGE for world, plus the player body layer.
## Without layer 2, scav bullets pass through closed doors the perception LOS still treats as cover.
const HITSCAN_MASK: int = (1 << 0) | (1 << 1) | (1 << 4)


func _enter() -> void:
	var npc := agent as HostileNPC
	_fire_timer = (npc.effective_fire_cooldown() if npc else 0.8) * 0.5
	_los_lost_timer = 0.0
	_has_reacted = blackboard.get_var(&"combat_reacted", false)
	if not _has_reacted:
		_reaction_timer = npc.ai_profile.reaction_delay if npc and npc.ai_profile else 0.3
	# Fresh burst each time this task (re)becomes active.
	_rounds_left_in_burst = 0
	_burst_pause_timer = 0.0


func _tick(delta: float) -> Status:
	var target: Variant = blackboard.get_var(&"target", null)
	if not is_instance_valid(target) or not target is Node3D:
		return FAILURE

	var npc := agent as HostileNPC
	if npc == null:
		return FAILURE
	var profile: AIProfile = npc.ai_profile

	npc.face_direction((target as Node3D).global_position)
	_brake(npc, delta)

	var engage_range: float = profile.preferred_engage_range if profile else 18.0
	var range_margin: float = profile.range_margin if profile else 2.0
	var dist: float = npc.global_position.distance_to((target as Node3D).global_position)
	if dist > engage_range + range_margin:
		if debug_shoot:
			print("[shoot] FAIL range dist=%.1f" % dist)
		return FAILURE

	var ammo: int = blackboard.get_var(&"ammo", npc.magazine_size())
	if ammo <= 0:
		if debug_shoot:
			print("[shoot] FAIL ammo=0 -> reload")
		return FAILURE

	var muzzle_pos := _get_muzzle_pos(npc)
	var aim_pos := _get_aim_pos(target as Node3D)
	# LOS grace: tolerate brief line-of-sight loss (player strafing a cover
	# edge, muzzle shifting) instead of bailing to chase immediately.
	var los_grace: float = profile.los_grace if profile else 0.4
	if not _result_hits_target(_cast_ray(npc, muzzle_pos, aim_pos), target as Node3D):
		_los_lost_timer += delta
		if _los_lost_timer >= los_grace:
			if debug_shoot:
				print("[shoot] FAIL no-LOS %.2fs -> chase" % _los_lost_timer)
			return FAILURE
		return RUNNING
	_los_lost_timer = 0.0

	# Reaction beat — once per COMBAT engagement
	if not _has_reacted:
		_reaction_timer -= delta
		if _reaction_timer <= 0.0:
			_has_reacted = true
			blackboard.set_var(&"combat_reacted", true)
		return RUNNING

	# Burst pause — a deliberate gap between bursts (trigger discipline),
	# separate from the larger-scale strafe/reposition beat.
	if _burst_pause_timer > 0.0:
		_burst_pause_timer -= delta
		return RUNNING

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = npc.effective_fire_cooldown()
		if _rounds_left_in_burst <= 0:
			_rounds_left_in_burst = _roll_burst_rounds(npc)
		if debug_shoot:
			print("[shoot] FIRE ammo=%d dist=%.1f burst_left=%d" % [ammo, dist, _rounds_left_in_burst])
		_shoot(npc, target as Node3D, muzzle_pos, dist)
		ammo -= 1
		blackboard.set_var(&"ammo", ammo)
		var shots: int = blackboard.get_var(&"shots_fired_since_strafe", 0, false)
		blackboard.set_var(&"shots_fired_since_strafe", shots + 1)
		_rounds_left_in_burst -= 1
		if _rounds_left_in_burst <= 0:
			_burst_pause_timer = _roll_burst_pause(npc)
		if ammo <= 0:
			return FAILURE

	return RUNNING


func _roll_burst_rounds(npc: HostileNPC) -> int:
	var profile: AIProfile = npc.ai_profile
	var lo: int = profile.burst_rounds_min if profile else 2
	var hi: int = profile.burst_rounds_max if profile else 4
	return randi_range(mini(lo, hi), maxi(lo, hi))


func _roll_burst_pause(npc: HostileNPC) -> float:
	var profile: AIProfile = npc.ai_profile
	var lo: float = profile.burst_pause_min if profile else 0.3
	var hi: float = profile.burst_pause_max if profile else 0.8
	return randf_range(minf(lo, hi), maxf(lo, hi))


func _brake(npc: HostileNPC, delta: float) -> void:
	var rate: float = delta * npc.sprint_speed * 6.0
	npc.velocity.x = move_toward(npc.velocity.x, 0.0, rate)
	npc.velocity.z = move_toward(npc.velocity.z, 0.0, rate)
	if not npc.is_on_floor():
		npc.velocity += npc.get_gravity() * delta
	npc.move_and_slide()


func _get_muzzle_pos(npc: HostileNPC) -> Vector3:
	var muzzle: Node3D = npc.get_node_or_null("Muzzle")
	if is_instance_valid(muzzle):
		return muzzle.global_position
	return npc.global_position + Vector3(0.0, 1.4, 0.0)


func _get_aim_pos(target: Node3D) -> Vector3:
	# Crouch/slide and stand-up transitions use the short collider. Its center
	# stays hittable while the head is still interpolating between poses.
	if target is CogitoPlayer and not target.crouching_collision_shape.disabled:
		return target.crouching_collision_shape.global_position
	# Preserve the existing standing aim and fallback for other targets.
	return target.global_position + Vector3(0.0, 0.5, 0.0)


func _cast_ray(npc: HostileNPC, from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = npc.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [npc.get_rid()]
	params.collision_mask = HITSCAN_MASK
	return space.intersect_ray(params)


func _result_hits_target(result: Dictionary, target: Node3D) -> bool:
	# Empty ray = nothing on the mask between muzzle and aim — not a free LOS pass.
	# Treating empty as clear let scavs "see" through gaps when the player body
	# wasn't on the mask or the aim point slipped past the collider.
	if result.is_empty():
		return false
	var hit: Object = result["collider"]
	return hit == target or (hit is Node and (hit as Node).is_in_group(&"Player"))


## Base spread (from ai_profile.spread(), accuracy-derived) widened by:
## - distance: harder to hold a precise sight picture on a small far target.
## - this NPC's own movement: firing while moving is less precise (bt_shoot
##   already brakes to a stop before firing, so this is mostly a no-op today,
##   but stays correct if that ever changes).
## - the target's lateral (perpendicular-to-aim) speed: a strafing target is
##   harder to hit than one standing still or closing straight on.
## - the weapon's attachments: whatever tames recoil for the player tightens an
##   NPC's group by the same factor (foregrip 0.85 = 15% tighter).
func _spread_magnitude(npc: HostileNPC, target: Node3D, aim_dir: Vector3, dist: float) -> float:
	var profile: AIProfile = npc.ai_profile
	var base: float = profile.spread() if profile else 0.5
	var engage_range: float = profile.preferred_engage_range if profile else 18.0

	var dist_t: float = clampf(dist / maxf(engage_range, 0.01), 0.0, 1.0)
	var dist_mult: float = lerpf(1.0, 1.5, dist_t)

	var shooter_speed: float = Vector3(npc.velocity.x, 0.0, npc.velocity.z).length()
	var shooter_mult: float = clampf(1.0 + shooter_speed / 6.0, 1.0, 1.8)

	var target_velocity := Vector3.ZERO
	if "main_velocity" in target:
		target_velocity = target.main_velocity
	elif "velocity" in target:
		target_velocity = target.velocity
	var right := aim_dir.cross(Vector3.UP)
	var lateral_speed: float = 0.0
	if right.length_squared() > 0.0001:
		lateral_speed = absf(Vector3(target_velocity.x, 0.0, target_velocity.z).dot(right.normalized()))
	var target_mult: float = clampf(1.0 + lateral_speed / 4.0, 1.0, 2.0)

	var weapon_mult: float = 1.0
	if npc.equipped_wieldable:
		weapon_mult = npc.equipped_wieldable.attachment_multiplier(&"recoil_multiplier")

	return base * dist_mult * shooter_mult * target_mult * weapon_mult


func _shoot(npc: HostileNPC, target: Node3D, muzzle_pos: Vector3, dist: float) -> void:
	var aim_pos := _get_aim_pos(target)
	var aim_dir := (aim_pos - muzzle_pos).normalized()
	if debug_shoot:
		print("[shoot] GEOM npc_pos=%s muzzle=%s target=%s(%s) aim_pos=%s aim_dir=%s" % [
			npc.global_position, muzzle_pos, target.name, target.global_position, aim_pos, aim_dir])

	# Higher ai_profile.accuracy (0-1) = better shooter = LESS spread, further
	# widened by distance / this NPC's own movement / the target's lateral
	# (strafing) speed — all independent of accuracy itself.
	var spread_magnitude: float = _spread_magnitude(npc, target, aim_dir, dist)
	var damage: float = npc.weapon_damage()

	var right := aim_dir.cross(Vector3.UP).normalized()
	var up := right.cross(aim_dir).normalized()
	var spread := right * randf_range(-spread_magnitude, spread_magnitude) \
				+ up * randf_range(-spread_magnitude * 0.5, spread_magnitude * 0.5)
	var fire_dir := (aim_dir + spread).normalized()

	if shoot_sound and is_instance_valid(Audio):
		Audio.play_sound_3d(shoot_sound, false).global_position = muzzle_pos

	var se := npc.get_node_or_null("/root/SoundEvents")
	if se:
		se.sound_emitted.emit(muzzle_pos, npc.gunshot_loudness(), &"gunshot", npc)

	if muzzle_flash_scene:
		var flash := muzzle_flash_scene.instantiate() as Node3D
		npc.get_tree().current_scene.add_child(flash)
		flash.global_position = muzzle_pos
		if fire_dir != Vector3.ZERO:
			flash.look_at(muzzle_pos + fire_dir)

	var result := _cast_ray(npc, muzzle_pos, muzzle_pos + fire_dir * 50.0)
	if debug_shoot:
		if result.is_empty():
			print("[shoot] BULLET MISS — ray hit nothing")
		elif not _result_hits_target(result, target):
			var missed: Object = result["collider"]
			print("[shoot] BULLET MISS — hit %s instead of player" % [missed.name if missed is Node else str(missed)])
		else:
			print("[shoot] BULLET HIT")
	if not result.is_empty() and _result_hits_target(result, target):
		var hit: Object = result["collider"]
		if hit.has_method("decrease_attribute"):
			hit.decrease_attribute("health", damage)
		elif hit.has_method("take_damage"):
			hit.take_damage(damage)
		elif hit.has_signal("damage_received"):
			var dir: Vector3 = (target.global_position - npc.global_position).normalized()
			hit.damage_received.emit(damage, dir, target.global_position)
