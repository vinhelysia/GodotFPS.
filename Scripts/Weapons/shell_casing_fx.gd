class_name ShellCasingFx
extends RigidBody3D

@export var eject_speed: float = 3.0
@export var eject_up: float = 0.5
@export var spin_speed: float = 10.0
@export var despawn_delay: float = 3.0
## Local axis of the shell node that points in the ejection direction.
## +X = right, -Z = forward, -X = left. Tune this if shell ejects the wrong way.
@export var eject_local_axis: Vector3 = Vector3(1, 0, 0)

var player_velocity := Vector3.ZERO
var player_node: Node = null

func _ready() -> void:
	add_to_group("shell_casings")
	if player_node:
		add_collision_exception_with(player_node)
	call_deferred("_eject")
	get_tree().create_timer(despawn_delay).timeout.connect(queue_free)


func _eject() -> void:
	linear_velocity = player_velocity
	var eject_dir := (global_basis * eject_local_axis + global_basis.y * eject_up).normalized()
	apply_impulse(eject_dir * eject_speed)

	# Random tumble spin.
	angular_velocity = Vector3(
		randf_range(-spin_speed, spin_speed),
		randf_range(-spin_speed, spin_speed),
		randf_range(-spin_speed, spin_speed),
	)
