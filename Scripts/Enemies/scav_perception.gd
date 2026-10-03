extends Node3D
class_name ScavPerception

## SENSOR ONLY — writes blackboard, never calls goto or moves the agent.
## Alert is a pure time-latch: once the player is seen, COMBAT holds for
## ai_profile.combat_hold seconds after the LAST successful sight check. Brief
## FOV/LOS flicker cannot drop alert to PATROL because the latch is time-based.
##
## Vision/hearing/alert TUNING lives on the host's `ai_profile` (AIProfile
## Resource) so different factions feel different without touching this script.

@export_group("Targeting")
@export_flags_3d_physics var los_mask: int = 3
@export var target_group: StringName = &"Player"

@export_group("Debug")
@export var debug_perception: bool = false

enum Alert { RELAXED = 0, SUSPICIOUS = 1, COMBAT = 2 }

# Fallback tuning used only if ai_profile is left unassigned (e.g. mid-setup).
const _DEFAULT_FOV_DEGREES: float = 110.0
const _DEFAULT_SIGHT_RANGE: float = 25.0
const _DEFAULT_EYE_HEIGHT: float = 1.6
const _DEFAULT_HEAR_K: float = 0.6
const _DEFAULT_COMBAT_HEARING_LOUDNESS: float = 30.0
const _DEFAULT_COMBAT_HOLD: float = 4.0
const _DEFAULT_CALLOUT_LOUDNESS: float = 35.0
const _DEFAULT_TIME_TO_DETECT_CLOSE: float = 0.2
const _DEFAULT_TIME_TO_DETECT_FAR: float = 2.0
const _DEFAULT_DETECT_DECAY_PER_SEC: float = 0.5

## Detection accumulator, 0..1. 0.4 = enough to go SUSPICIOUS (investigate);
## 1.0 = fully spotted, which refreshes last_seen_time and lets the existing
## COMBAT time-latch take over. Graduated so a distant/brief sighting doesn't
## instantly X-ray-spot the player the way a binary can-see check did.
var _detection: float = 0.0

var _host: HostileNPC
var _bb: Blackboard
var _prev_alert: int = -1
## Last _host.last_hit_time value we've already reacted to (avoids reacting
## to the same hit every physics tick).
var _last_processed_hit_time: float = -999.0


func _ready() -> void:
	_host = get_parent() as HostileNPC
	if _host == null:
		push_error("ScavPerception must be a child of a HostileNPC.")
		set_physics_process(false)
		return

	# So the player's detection HUD can poll every active sensor in one group.
	add_to_group(&"npc_perception")

	var bt := _host.get_node_or_null("BTPlayer")
	if bt:
		_bb = bt.blackboard

	var se := get_node_or_null("/root/SoundEvents")
	if se:
		se.sound_emitted.connect(_on_sound_emitted)

## Stops all external lifecycle hooks before the dead HostileNPC is freed.
func shutdown() -> void:
	set_process(false)
	set_physics_process(false)
	remove_from_group(&"npc_perception")
	var se := get_node_or_null("/root/SoundEvents")
	if se and se.sound_emitted.is_connected(_on_sound_emitted):
		se.sound_emitted.disconnect(_on_sound_emitted)

func _physics_process(delta: float) -> void:
	if _bb == null:
		var bt := _host.get_node_or_null("BTPlayer")
		if bt == null:
			return
		_bb = bt.blackboard

	# Non-hostile NPCs never escalate past RELAXED — they patrol and never
	# attack. NEUTRAL and FRIENDLY currently behave identically; that split is
	# reserved for future behavior (e.g. retaliation, following).
	if not _is_hostile():
		_bb.set_var(&"alert", Alert.RELAXED)
		_prev_alert = Alert.RELAXED
		return

	_check_hit_reaction()

	var now: float = Time.get_ticks_msec() / 1000.0

	# --- Vision: graduated detection accumulator (0..1), not a binary spot ---
	var t := _find_target()
	var can_see_target: bool = t != null and _can_see(t)
	_bb.set_var(&"target_visible", can_see_target)

	if can_see_target:
		var dist: float = global_position.distance_to(t.global_position)
		_detection = clampf(_detection + _detection_gain_rate(t, dist) * delta, 0.0, 1.0)
		# Rising edge only (while actively visible) — avoids fighting
		# bt_look_around's one-shot has_last_known=false clear with a stale
		# accumulator that's merely decaying, not freshly re-spotted.
		if _detection >= 0.4:
			_bb.set_var(&"has_last_known", true)
			_bb.set_var(&"last_known_pos", t.global_position)
		if _detection >= 1.0:
			_bb.set_var(&"target", t)
			_bb.set_var(&"last_seen_time", now)
	else:
		_detection = clampf(_detection - _detect_decay_per_sec() * delta, 0.0, 1.0)

	_bb.set_var(&"detection_level", _detection)

	# --- Alert (time-latch — immune to brief LOS flicker) ---
	var last_seen: float = _bb.get_var(&"last_seen_time", -999.0)
	var has_lk: bool = _bb.get_var(&"has_last_known", false)

	var alert: int
	if (now - last_seen) <= _combat_hold():
		alert = Alert.COMBAT
	elif has_lk:
		alert = Alert.SUSPICIOUS
	else:
		alert = Alert.RELAXED
		_bb.set_var(&"target", null)
		_bb.set_var(&"has_last_known", false)
		_bb.set_var(&"combat_reacted", false)
		_bb.set_var(&"shots_fired_since_strafe", 0)

	_bb.set_var(&"alert", alert)

	# Squad callout — shouted once, on the RELAXED/SUSPICIOUS -> COMBAT rising
	# edge only (never every tick while already in COMBAT).
	if alert == Alert.COMBAT and _prev_alert != Alert.COMBAT:
		_emit_squad_callout()

	if debug_perception and alert != _prev_alert:
		var names: PackedStringArray = ["RELAXED", "SUSPICIOUS", "COMBAT"]
		print("[%s] %s  visible=%s  det=%.2f  has_lk=%s  dt_seen=%.1fs" % [
			_host.name, names[alert], can_see_target, _detection, has_lk,
			now - last_seen if last_seen > -999.0 else INF,
		])
	_prev_alert = alert


## Reacts to being shot even from outside FOV/hearing range. Single-player:
## the attacker is always the player, and the damage_received signal carries
## no direction, so we approximate the investigation point as the player's
## real position plus some horizontal error (we "felt" the hit, we didn't
## pinpoint the shooter).
func _check_hit_reaction() -> void:
	if is_equal_approx(_host.last_hit_time, _last_processed_hit_time):
		return
	_last_processed_hit_time = _host.last_hit_time

	var player := _find_target()
	if player == null:
		return

	_detection = 1.0
	var now: float = Time.get_ticks_msec() / 1000.0

	var error := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if error.length_squared() < 0.0001:
		error = Vector3(1.0, 0.0, 0.0)
	error = error.normalized() * randf_range(2.0, 4.0)
	var approx_pos: Vector3 = player.global_position + error

	_bb.set_var(&"target", player)
	_bb.set_var(&"last_seen_time", now)
	_bb.set_var(&"has_last_known", true)
	_bb.set_var(&"last_known_pos", approx_pos)

	if debug_perception:
		print("[%s] HIT REACTION -> forcing COMBAT, approx_pos=%s" % [_host.name, approx_pos])


## Detection gain per second while actively visible. Scales from
## time_to_detect_close (near) to time_to_detect_far (at sight_range), then
## sped up further if the target is moving fast (e.g. sprinting).
func _detection_gain_rate(target: Node3D, dist: float) -> float:
	var t: float = clampf(dist / maxf(_sight_range(), 0.01), 0.0, 1.0)
	var base_time: float = lerpf(_time_to_detect_close(), _time_to_detect_far(), t)

	var target_speed: float = 0.0
	if "main_velocity" in target:
		target_speed = (target.main_velocity as Vector3).length()
	elif "velocity" in target:
		target_speed = (target.velocity as Vector3).length()
	# Sprinting (~6 m/s in this project) roughly halves the time needed.
	var movement_mult: float = clampf(1.0 + target_speed / 6.0, 1.0, 2.5)

	var effective_time: float = maxf(base_time / movement_mult, 0.01)
	return 1.0 / effective_time


## Shouts "contact!" the moment this NPC enters COMBAT. Only same-faction
## listeners react to it (see _on_voice_callout) — other factions don't
## understand/care about someone else's callout.
func _emit_squad_callout() -> void:
	var se := get_node_or_null("/root/SoundEvents")
	if se:
		se.sound_emitted.emit(global_position, _callout_loudness(), &"voice", _host)


func _find_target() -> Node3D:
	var nodes := get_tree().get_nodes_in_group(target_group)
	if nodes.is_empty():
		return null
	return nodes[0] as Node3D


func _can_see(target: Node3D) -> bool:
	var eye := global_position + Vector3.UP * _eye_height()
	var to_t := target.global_position - eye
	if to_t.length() > _sight_range():
		return false

	var forward := -_host.global_transform.basis.z
	var flat := Vector3(to_t.x, 0.0, to_t.z)
	if flat.length_squared() > 0.0001:
		if rad_to_deg(forward.angle_to(flat.normalized())) > _fov_degrees() * 0.5:
			return false

	# Multi-point LOS: head, chest, pelvis — pass target for hitbox-child check
	return _los_clear(eye, _aim_point(target, 1.6), target) \
		or _los_clear(eye, _aim_point(target, 1.0), target) \
		or _los_clear(eye, _aim_point(target, 0.4), target)


func _aim_point(target: Node3D, height: float) -> Vector3:
	if height >= 1.5:
		var h: Variant = target.get("head")
		if h is Node3D and is_instance_valid(h):
			return (h as Node3D).global_position
	return target.global_position + Vector3.UP * height


func _los_clear(from: Vector3, to: Vector3, target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = los_mask
	params.exclude = [_host.get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return true
	var c: Object = hit["collider"]
	# Accept the target itself, any node in target_group, or a child of the target
	# (handles HitboxComponent Area3D children that may lack the group tag).
	if c == target:
		return true
	if c is Node:
		var cn := c as Node
		if cn.is_in_group(target_group):
			return true
		if target.is_ancestor_of(cn):
			return true
	return false


func _on_sound_emitted(pos: Vector3, loudness: float, kind: StringName, emitter: Node) -> void:
	if emitter == _host or (emitter != null and _host.is_ancestor_of(emitter)):
		return
	if _bb == null:
		return
	if not _is_hostile():
		return

	if kind == &"voice":
		_on_voice_callout(pos, emitter)
		return

	var alert: int = _bb.get_var(&"alert", Alert.RELAXED)
	if alert == Alert.COMBAT and loudness < _combat_hearing_loudness():
		return

	var hear_k: float = _hear_k()
	var dist: float = global_position.distance_to(pos)
	if dist > loudness * hear_k:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	_bb.set_var(&"heard_pos", pos)
	_bb.set_var(&"heard_time", now)
	_bb.set_var(&"has_last_known", true)

	# Vision owns last_known_pos in COMBAT; hearing updates it otherwise.
	if alert != Alert.COMBAT:
		_bb.set_var(&"last_known_pos", pos)

	if debug_perception:
		print("[%s] HEARD loudness=%.0f dist=%.1f/%.1fm" % [
			_host.name, loudness, dist, loudness * hear_k,
		])


## Squad callout: only same-faction listeners react, and only up to
## SUSPICIOUS (never full COMBAT — last_seen_time is deliberately untouched,
## so the COMBAT time-latch can't fire from this alone). Since this can never
## push alert to COMBAT by itself, it can never trigger ANOTHER callout
## emission either (callouts only fire on the COMBAT rising edge) — no
## infinite echo chains between squadmates.
func _on_voice_callout(pos: Vector3, emitter: Node) -> void:
	var emitter_npc := emitter as HostileNPC
	if emitter_npc == null or emitter_npc.faction == null or _host.faction == null:
		return
	if emitter_npc.faction != _host.faction:
		return

	var dist: float = global_position.distance_to(pos)
	if dist > _callout_loudness() * _hear_k():
		return

	var alert: int = _bb.get_var(&"alert", Alert.RELAXED)
	if alert == Alert.COMBAT:
		return

	_bb.set_var(&"has_last_known", true)
	_bb.set_var(&"last_known_pos", pos)

	if debug_perception:
		print("[%s] SQUAD CALLOUT from %s -> SUSPICIOUS" % [_host.name, emitter_npc.name])


# ── Profile-driven tuning (with fallbacks if ai_profile is unassigned) ────────

func _fov_degrees() -> float:
	return _host.ai_profile.fov_degrees if _host.ai_profile else _DEFAULT_FOV_DEGREES

func _sight_range() -> float:
	return _host.ai_profile.sight_range if _host.ai_profile else _DEFAULT_SIGHT_RANGE

func _eye_height() -> float:
	return _host.ai_profile.eye_height if _host.ai_profile else _DEFAULT_EYE_HEIGHT

func _hear_k() -> float:
	return _host.ai_profile.hear_k if _host.ai_profile else _DEFAULT_HEAR_K

func _combat_hearing_loudness() -> float:
	return _host.ai_profile.combat_hearing_loudness if _host.ai_profile else _DEFAULT_COMBAT_HEARING_LOUDNESS

func _combat_hold() -> float:
	return _host.ai_profile.combat_hold if _host.ai_profile else _DEFAULT_COMBAT_HOLD

func _callout_loudness() -> float:
	return _host.ai_profile.callout_loudness if _host.ai_profile else _DEFAULT_CALLOUT_LOUDNESS

func _time_to_detect_close() -> float:
	return _host.ai_profile.time_to_detect_close if _host.ai_profile else _DEFAULT_TIME_TO_DETECT_CLOSE

func _time_to_detect_far() -> float:
	return _host.ai_profile.time_to_detect_far if _host.ai_profile else _DEFAULT_TIME_TO_DETECT_FAR

func _detect_decay_per_sec() -> float:
	return _host.ai_profile.detect_decay_per_sec if _host.ai_profile else _DEFAULT_DETECT_DECAY_PER_SEC

func _is_hostile() -> bool:
	return _host.is_hostile_to_player()


# ── Public (read by the player's detection HUD) ───────────────────────────────

## Current detection accumulator, 0..1 (0 = unseen, 1 = fully spotted).
func detection_level() -> float:
	return _detection

## Only hostile sensors should light up the player's "being spotted" indicator.
func is_hostile_sensor() -> bool:
	return _is_hostile()
