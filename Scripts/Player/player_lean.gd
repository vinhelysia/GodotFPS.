extends Node
## Tarkov-style hold-to-lean. Asymmetric: right lean peeks further with less body exposure.
##
## Transform ownership: only applies *deltas* of our own contribution on Head
## (position.x / rotation.z). Recoil/trauma shake on the same Head node use the
## same subtract-previous / add-current pattern — absolute writes would erase them.

@export var enabled: bool = true
@export_group("Motion")
@export var lateral_amount: float = 0.38
@export var roll_degrees: float = 12.0
@export var smooth_speed: float = 12.0
@export var crouch_lean_scale: float = 0.85

@export_group("Wall Clearance")
## Probe radius for the lean wall check. Must stay comfortably above the camera's near plane
## (0.05) — the probe is what stops the lean, so anything smaller lets the near plane into the
## wall before the lean is cut.
@export var wall_probe_radius: float = 0.25

@export_group("Asymmetry (right advantage)")
## Multiplier on camera lateral when leaning right / left.
@export var right_lateral_scale: float = 1.2
@export var left_lateral_scale: float = 1.0
## Collision lateral as fraction of *camera* lateral for that side.
@export var right_collision_fraction: float = 0.38
@export var left_collision_fraction: float = 0.55
## Roll scale per side (right slightly less for cleaner ADS).
@export var right_roll_scale: float = 0.85
@export var left_roll_scale: float = 1.0

## Smoothed lean amount in [-1, 1]. +1 = full right.
var lean_amount: float = 0.0

## Currently applied lean contribution on Head (so we can remove/replace without clobbering peers).
var _applied_pos_x: float = 0.0
var _applied_rot_z: float = 0.0
var _applied_coll_x: float = 0.0

var _player: CharacterBody3D
var _head: Node3D
var _stand_col: CollisionShape3D
var _crouch_col: CollisionShape3D
var _stand_base_x: float = 0.0
var _crouch_base_x: float = 0.0
## Built once — cast_motion() is called every physics frame.
var _probe: PhysicsShapeQueryParameters3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_warning("PlayerLean: parent is not CharacterBody3D")
		set_physics_process(false)
		return
	_head = _player.get_node_or_null("Body/Neck/Head") as Node3D
	_stand_col = _player.get_node_or_null("StandingCollisionShape") as CollisionShape3D
	_crouch_col = _player.get_node_or_null("CrouchingCollisionShape") as CollisionShape3D
	if not _head:
		push_warning("PlayerLean: Head not found")
		set_physics_process(false)
		return
	if _stand_col:
		_stand_base_x = _stand_col.position.x
	if _crouch_col:
		_crouch_base_x = _crouch_col.position.x

	var sphere := SphereShape3D.new()
	sphere.radius = wall_probe_radius
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = sphere
	_probe.collision_mask = 3  # Environment + Interactables (doors count as walls here).
	_probe.collide_with_areas = false


func _exit_tree() -> void:
	# Remove our contribution if the node leaves mid-lean.
	_clear_applied()


## Save the neutral pose without changing the live lean or other Head contributions.
func get_neutral_head_transform() -> Transform3D:
	var pose := _head.transform
	pose.origin.x -= _applied_pos_x
	if not is_zero_approx(_applied_rot_z):
		var neutral_rotation := _head.rotation
		neutral_rotation.z -= _applied_rot_z
		pose.basis = Basis.from_euler(neutral_rotation, _head.rotation_order).scaled_local(_head.scale)
	return pose


## Absolute save restoration replaces Head; discard our old deltas first.
func reset() -> void:
	_clear_applied()
	lean_amount = 0.0


func _physics_process(delta: float) -> void:
	if not enabled or not _player or not _head:
		return

	var target := _compute_target()
	# Cut the lean short of geometry BEFORE smoothing, so the existing filter ramps the block
	# in and out. Clamping the applied pose instead would pop the moment the wall cleared.
	if not is_zero_approx(target):
		target *= _wall_clearance(_desired_offsets(target).x)
	var k := 1.0 - exp(-smooth_speed * delta)
	lean_amount = lerpf(lean_amount, target, k)
	_apply_pose(lean_amount)


## Fraction of a full lean that is actually free of geometry.
##
## The collision box CANNOT be what keeps the camera out of walls: the box only follows a
## fraction of the lean (that IS the peek advantage). At full right lean the camera sits
## 0.456 m out while the box moves 0.173 m — against a 0.3 m half-width that leaves 17 mm of
## margin, less than the camera's 0.05 m near plane. So the camera clipped straight through.
## Sweep the real geometry instead, always from the UNLEANED head, so the result never depends
## on the lean it is clamping.
func _wall_clearance(want_x: float) -> float:
	if _probe == null or is_zero_approx(want_x):
		return 1.0
	var neck := _head.get_parent() as Node3D
	var world := _player.get_world_3d()
	if neck == null or world == null or world.direct_space_state == null:
		return 1.0

	var neutral := _head.position
	neutral.x -= _applied_pos_x
	_probe.transform = Transform3D(Basis(), neck.global_transform * neutral)
	_probe.motion = neck.global_basis.x.normalized() * want_x
	_probe.exclude = [_player.get_rid()]

	# cast_motion -> [safe_fraction, unsafe_fraction]; [1, 1] when nothing is hit.
	var hit := world.direct_space_state.cast_motion(_probe)
	if hit.size() != 2:
		return 1.0
	return clampf(hit[0], 0.0, 1.0)


func _compute_target() -> float:
	# Block when UI / dead / sitting / free-look / sprint / slide.
	if _player.get("is_movement_paused") == true:
		return 0.0
	if _player.get("is_dead") == true:
		return 0.0
	if _player.get("is_sitting") == true:
		return 0.0
	if _player.get("is_free_looking") == true:
		return 0.0
	if _player.get("is_sprinting") == true:
		return 0.0
	var sliding: Timer = _player.get("sliding_timer") as Timer
	if sliding and not sliding.is_stopped():
		return 0.0

	var left := Input.is_action_pressed("lean_left")
	var right := Input.is_action_pressed("lean_right")
	if left and right:
		return 0.0
	if left:
		return -1.0
	if right:
		return 1.0
	return 0.0


func _desired_offsets(amount: float) -> Vector3:
	## Returns Vector3(cam_x, rot_z_rad, coll_x).
	if absf(amount) < 0.0001:
		return Vector3.ZERO

	var is_right := amount > 0.0
	var lat_scale := right_lateral_scale if is_right else left_lateral_scale
	var coll_frac := right_collision_fraction if is_right else left_collision_fraction
	var roll_scale := right_roll_scale if is_right else left_roll_scale

	var crouch_mul := 1.0
	if _player.get("is_crouching") == true:
		crouch_mul = crouch_lean_scale

	var cam_x := amount * lateral_amount * lat_scale * crouch_mul
	var roll := -amount * deg_to_rad(roll_degrees) * roll_scale * crouch_mul
	var coll_x := amount * lateral_amount * lat_scale * coll_frac * crouch_mul
	return Vector3(cam_x, roll, coll_x)


func _apply_pose(amount: float) -> void:
	var desired := _desired_offsets(amount)
	var want_x := desired.x
	var want_rz := desired.y
	var want_coll := desired.z

	# Additive: only move by the change in *our* contribution.
	var dx := want_x - _applied_pos_x
	var drz := want_rz - _applied_rot_z
	if absf(dx) > 0.0000001:
		_head.position.x += dx
	if absf(drz) > 0.0000001:
		_head.rotation.z += drz

	_applied_pos_x = want_x
	_applied_rot_z = want_rz
	_applied_coll_x = want_coll
	_set_collision_x(want_coll)


func _clear_applied() -> void:
	if is_instance_valid(_head):
		_head.position.x -= _applied_pos_x
		_head.rotation.z -= _applied_rot_z
	_applied_pos_x = 0.0
	_applied_rot_z = 0.0
	_applied_coll_x = 0.0
	_set_collision_x(0.0)


func _set_collision_x(offset_x: float) -> void:
	# Collision is owned solely by lean (recoil does not touch it) — absolute is fine.
	if _stand_col:
		_stand_col.position.x = _stand_base_x + offset_x
	if _crouch_col:
		_crouch_col.position.x = _crouch_base_x + offset_x
