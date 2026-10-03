extends Node3D
## Weapon recoil node. Place as a child of Body/Neck/Head in the player scene.
##
## Pitch is applied on Head.rotation.x (same channel as mouse look).
## Yaw is applied on Body about world-up. Do not yaw in Head local space while
## leaned — local UP tilts with lean roll and spray snaps toward the lean side.
##
## Trauma shake stays additive on Head position / local roll (composes with lean).

# ── Constants ────────────────────────────────────────────────────────────────

const BURST_DRIFT_CAP_RATIO: float = 0.6
const FIRE_TRAUMA_HIP: float = 0.25
const FIRE_TRAUMA_ADS: float = 0.1
const HEAD_PITCH_CLAMP_DEG: float = 89.0

# ── Internal rotation tracking ───────────────────────────────────────────────

var current_rotation: Vector3
var target_rotation: Vector3
var _prev_rotation := Vector3.ZERO

# ── Per-weapon recoil vectors (set via set_recoil / set_aim_recoil on equip) ─

@export var recoil: Vector3
@export var aim_recoil: Vector3

# ── Tuning ───────────────────────────────────────────────────────────────────

@export var snappiness: float = 10.0
@export var return_speed: float = 5.0

# ── Burst / ramp-up settings ────────────────────────────────────────────────

## Number of shots before recoil reaches peak multiplier.
@export var recoil_ramp_shots: int = 4
## Maximum recoil multiplier reached after ramping up.
@export var recoil_ramp_max: float = 1.8
## Seconds without firing before shot counter resets (trigger gap).
@export var burst_reset_time: float = 0.4
## Extra horizontal drift magnitude per shot during sustained fire (radians).
@export var burst_drift_per_shot: float = 0.003

# ── Burst state ──────────────────────────────────────────────────────────────

var _shot_count: int = 0
var _burst_drift: float = 0.0
## Random side for this burst (+1 / -1). Avoids always-left bias that felt like a snap.
var _burst_side: float = 1.0
var _time_since_last_shot: float = 0.0

# ── Built-in camera shake ────────────────────────────────────────────────────

## Maximum positional shake offset (metres) applied to the parent Head node.
@export var shake_max_offset: Vector3 = Vector3(0.015, 0.02, 0.0)
## Maximum roll shake in degrees.
@export var shake_max_roll_deg: float = 1.5
## How fast trauma decays per second (higher = snappier recovery).
@export var shake_trauma_decay: float = 1.8
## Trauma is raised to this power before sampling — higher = more contrast.
@export var shake_trauma_power: float = 2.0
## Noise oscillation speed — higher = faster shake.
@export var shake_noise_frequency: float = 20.0

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite
var _shake_offset: Vector3 = Vector3.ZERO
var _shake_roll: float = 0.0

var _head_node: Node3D
var _body_node: Node3D


static func smoothing_weight(speed: float, delta: float) -> float:
	return 1.0 - exp(-maxf(speed, 0.0) * maxf(delta, 0.0))


func _ready() -> void:
	_head_node = get_parent() as Node3D
	_body_node = _resolve_body(_head_node)
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shake_noise.seed = randi()


func _resolve_body(head: Node3D) -> Node3D:
	if head == null:
		return null
	# Expected: Body/Neck/Head
	var neck := head.get_parent() as Node3D
	if neck == null:
		return null
	return neck.get_parent() as Node3D


func _process(delta: float) -> void:
	_time_since_last_shot += delta

	if _time_since_last_shot >= burst_reset_time:
		_shot_count = 0
		_burst_drift = 0.0

	target_rotation = target_rotation.lerp(Vector3.ZERO, smoothing_weight(return_speed, delta))
	current_rotation = current_rotation.lerp(target_rotation, smoothing_weight(snappiness, delta))

	var delta_rot := current_rotation - _prev_rotation
	_prev_rotation = current_rotation

	if _head_node and delta_rot.length() > 0.0001:
		_apply_recoil_deltas(delta_rot)

	_trauma = maxf(0.0, _trauma - shake_trauma_decay * delta)
	_shake_time += delta
	_apply_shake()


## Pitch on head local X; yaw on body world-Y. Does not touch head.rotation.z (lean/shake).
func _apply_recoil_deltas(delta_rot: Vector3) -> void:
	# Pitch — same channel mouse look uses; independent of lean roll.
	_head_node.rotation.x += delta_rot.x
	var pitch_lim := deg_to_rad(HEAD_PITCH_CLAMP_DEG)
	_head_node.rotation.x = clampf(_head_node.rotation.x, -pitch_lim, pitch_lim)

	# Yaw — world-up on body so lean roll cannot turn "yaw" into lateral snap.
	if _body_node:
		_body_node.rotate_y(delta_rot.y)
	else:
		# Fallback: neck if body missing
		var neck := _head_node.get_parent() as Node3D
		if neck:
			neck.rotate_y(delta_rot.y)

	# Optional roll recoil only if weapon data uses z (lean owns z otherwise).
	if absf(delta_rot.z) > 0.00001:
		_head_node.rotation.z += delta_rot.z


# ── Public API ───────────────────────────────────────────────────────────────

func recoil_fire(is_aiming: bool = false) -> void:
	_time_since_last_shot = 0.0
	_shot_count += 1
	if _shot_count == 1:
		_burst_side = 1.0 if randf() >= 0.5 else -1.0

	var ramp: float = clampf(float(_shot_count - 1) / float(maxi(recoil_ramp_shots - 1, 1)), 0.0, 1.0)
	var multiplier: float = lerpf(1.0, recoil_ramp_max, ramp)

	var drift_cap: float = absf(recoil.y) * BURST_DRIFT_CAP_RATIO
	_burst_drift = minf(_burst_drift + burst_drift_per_shot, drift_cap)

	var base := aim_recoil if is_aiming else recoil

	target_rotation += Vector3(
		base.x * multiplier,
		randf_range(-base.y, base.y) + _burst_drift * _burst_side,
		randf_range(-base.z, base.z)
	)

	var trauma_amount := FIRE_TRAUMA_ADS if is_aiming else FIRE_TRAUMA_HIP
	add_trauma(trauma_amount)


func set_recoil(new_recoil: Vector3) -> void:
	recoil = new_recoil


func set_aim_recoil(new_recoil: Vector3) -> void:
	aim_recoil = new_recoil


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _apply_shake() -> void:
	var parent := _head_node
	if not parent:
		return

	# Subtract previous contribution, then re-add — never absolute-write lean baseline.
	parent.position -= _shake_offset
	parent.rotation_degrees.z -= _shake_roll

	if _trauma <= 0.001:
		_shake_offset = Vector3.ZERO
		_shake_roll = 0.0
		return

	var shake: float = pow(_trauma, shake_trauma_power)
	var t: float = _shake_time * shake_noise_frequency
	_shake_offset = Vector3(
		_shake_noise.get_noise_2d(t, 0.0) * shake_max_offset.x * shake,
		_shake_noise.get_noise_2d(0.0, t) * shake_max_offset.y * shake,
		0.0
	)
	_shake_roll = _shake_noise.get_noise_2d(t, 100.0) * shake_max_roll_deg * shake

	parent.position += _shake_offset
	parent.rotation_degrees.z += _shake_roll
