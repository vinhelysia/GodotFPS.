extends Weapon_Resource

class_name Pistol_Resource

func _init() -> void:
	locks_open_on_empty = true
	magazine_capacity = 15
	chamber_capacity = 1
	auto_chambers_on_empty_reload = true

@export_group("Pistol")
## Minimum time in seconds between trigger pulls (prevents holding fire).
@export var triggerResetTime: float = 0.15

@export_group("Pistol - Hammer Tween")
## Rotation (radians) của hammer ở trạng thái nghỉ.
@export var hammer_rest_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)
## Rotation (radians) của hammer khi đã cocked (giật ra sau khi bắn).
@export var hammer_cocked_rotation: Vector3 = Vector3(-1.0471975, 0.0, 0.0)
## Thời gian (giây) hammer quay ra sau.
@export var hammer_cock_duration: float = 0.05
## Thời gian (giây) hammer trở về nghỉ.
@export var hammer_return_duration: float = 0.12

@export_group("Pistol - Slide Lock")
## Bật/tắt slide-lock on empty. Tắt cho revolver / striker-fired designs.
@export var slide_lock_enabled: bool = true

func get_fire_mode() -> FireMode:
	return FireMode.SEMI

func get_fire_cooldown() -> float:
	return triggerResetTime


func play_post_fire_visual(weapon: Node) -> void:
	var firearm := weapon as CogitoFirearm
	# Slide-lock on last round.  Tells ShootMotionController to keep the
	# fire_part at its forward offset until reload completes.
	firearm._shoot_motion.fire_part_locked = slide_lock_enabled \
			and firearm._mechanics != null and firearm._mechanics.bolt_locked_open
	# Hammer cock-and-return tween.
	if firearm._hammer_part != null:
		run_pistol_parts_tween(firearm)


func on_anim_finished(weapon: Node, anim_name: StringName) -> void:
	# Release the slide-lock once reload finishes — fire_part returns to rest.
	var firearm := weapon as CogitoFirearm
	if firearm._is_reload_animation(anim_name):
		firearm._shoot_motion.release_fire_part_lock()


func on_reset(weapon: Node) -> void:
	var firearm := weapon as CogitoFirearm
	if firearm._hammer_part != null:
		firearm._hammer_part.rotation = hammer_rest_rotation


## Hammer cock-and-return tween. Relocated from cogito_weapon.gd so the shared
## orchestrator no longer downcasts to Pistol_Resource — same delegation style
## as the other virtuals here.
func run_pistol_parts_tween(firearm: CogitoFirearm) -> void:
	if firearm._hammer_part == null:
		return
	if firearm._hammer_tween:
		firearm._hammer_tween.kill()
	firearm._hammer_tween = firearm.create_tween().set_trans(Tween.TRANS_SINE)
	firearm._hammer_tween.tween_property(firearm._hammer_part, "rotation",
		hammer_cocked_rotation, hammer_cock_duration)
	firearm._hammer_tween.tween_property(firearm._hammer_part, "rotation",
		hammer_rest_rotation, hammer_return_duration)
	firearm._hammer_tween.finished.connect(func(): firearm._hammer_tween = null)
