extends Node3D

## This gives broad control of wieldable sway strength. 1 = no change in raw sway amount.
@export_range(1,8) var sway_predivision: float = 3
## This gives more granular control of wieldable sway strength.
@export var sway_multiplier : float = .001
## How quickly passive sway settles back to neutral.
@export var sway_return_speed: float = 5.0
## Minimum horizontal speed before sprint motion engages.
@export var sprint_speed_threshold: float = 0.1
## Minimum time (seconds) between sprint state transitions. Prevents jitter when spamming sprint.
@export_range(0.0, 0.5, 0.01) var sprint_transition_cooldown: float = 0.15

const _WeaponObstruction = preload("res://Scripts/Weapons/Helpers/weapon_obstruction.gd")

var _sway_offset: Vector3 = Vector3.ZERO
var _sprint_pose_position: Vector3 = Vector3.ZERO
var _sprint_pose_rotation: Vector3 = Vector3.ZERO
var _sprint_bob_position: Vector3 = Vector3.ZERO
var _sprint_bob_rotation: Vector3 = Vector3.ZERO
var _sprint_time: float = 0.0
var _sprint_active: bool = false
var _sprint_transition_timer: float = 0.0
var _tracked_wieldable: CogitoWieldable = null
var _sprint_pose_tween: Tween = null
var _obstruction: RefCounted = _WeaponObstruction.new()


func _process(delta: float) -> void:
    var active_wieldable := _get_active_wieldable()
    if active_wieldable != _tracked_wieldable:
        _tracked_wieldable = active_wieldable
        reset_motion()

    _sprint_transition_timer += delta
    _update_sprint_state(active_wieldable)

    _sway_offset.x = lerp(_sway_offset.x, 0.0, delta * sway_return_speed)
    _sway_offset.y = lerp(_sway_offset.y, 0.0, delta * sway_return_speed)
    _update_sprint_bob(delta, active_wieldable)
    _update_obstruction(delta, active_wieldable)
    _apply_combined_motion()


func sway(sway_amount: Vector2) -> void:
    _sway_offset.x += (sway_amount.x / sway_predivision) * sway_multiplier
    _sway_offset.y += (sway_amount.y / sway_predivision) * sway_multiplier


func should_block_secondary_action() -> bool:
    return _should_activate_sprint(_get_active_wieldable())


func should_block_primary_action() -> bool:
    return _should_activate_sprint(_get_active_wieldable())


func interrupt_motion() -> void:
    _set_sprint_active(false, true, _get_active_wieldable())
    _apply_combined_motion()


func reset_motion() -> void:
    _kill_sprint_tween()
    _sprint_active = false
    _sprint_time = 0.0
    _sway_offset = Vector3.ZERO
    _sprint_pose_position = Vector3.ZERO
    _sprint_pose_rotation = Vector3.ZERO
    _sprint_bob_position = Vector3.ZERO
    _sprint_bob_rotation = Vector3.ZERO
    _obstruction.reset()
    position = Vector3.ZERO
    rotation_degrees = Vector3.ZERO


func _update_sprint_state(active_wieldable: CogitoWieldable) -> void:
    var should_sprint := _should_activate_sprint(active_wieldable)
    if should_sprint == _sprint_active:
        return
    if _sprint_transition_timer < sprint_transition_cooldown:
        return
    _sprint_transition_timer = 0.0
    _set_sprint_active(should_sprint, false, active_wieldable)


func _should_activate_sprint(active_wieldable: CogitoWieldable) -> bool:
    if not _can_apply_sprint_motion(active_wieldable):
        return false
    var player := _get_player()
    if player == null:
        return false
    if player.is_movement_paused or player.is_dead:
        return false
    if not player.is_sprinting:
        return false
    var horizontal_speed := Vector2(player.main_velocity.x, player.main_velocity.z).length()
    return horizontal_speed > sprint_speed_threshold


func _can_apply_sprint_motion(active_wieldable: CogitoWieldable) -> bool:
    return active_wieldable != null \
        and active_wieldable.enable_sprint_motion \
        and not active_wieldable.should_suspend_container_motion()


func _set_sprint_active(enabled: bool, immediate: bool, active_wieldable: CogitoWieldable) -> void:
    if enabled and active_wieldable == null:
        return

    if enabled and active_wieldable != null:
        active_wieldable.cancel_ads_for_sprint()

    _sprint_active = enabled
    if not enabled:
        _sprint_time = 0.0
        _sprint_bob_position = Vector3.ZERO
        _sprint_bob_rotation = Vector3.ZERO

    var target_position := Vector3.ZERO
    var target_rotation := Vector3.ZERO
    var duration := 0.0
    if enabled and active_wieldable != null:
        target_position = active_wieldable.sprint_position_offset
        target_rotation = active_wieldable.sprint_rotation_offset_deg
        duration = active_wieldable.sprint_enter_time
    elif active_wieldable != null:
        duration = active_wieldable.sprint_exit_time

    if immediate or duration <= 0.0:
        _kill_sprint_tween()
        _sprint_pose_position = target_position
        _sprint_pose_rotation = target_rotation
        return

    _kill_sprint_tween()
    _sprint_pose_tween = create_tween().set_parallel()
    _sprint_pose_tween.tween_property(self, "_sprint_pose_position", target_position, duration) \
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
    _sprint_pose_tween.tween_property(self, "_sprint_pose_rotation", target_rotation, duration) \
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _update_sprint_bob(delta: float, active_wieldable: CogitoWieldable) -> void:
    if not _sprint_active or active_wieldable == null or not active_wieldable.enable_sprint_motion:
        _sprint_bob_position = Vector3.ZERO
        _sprint_bob_rotation = Vector3.ZERO
        return

    _sprint_time += delta * maxf(active_wieldable.sprint_bob_speed, 0.0)
    var primary := sin(_sprint_time)
    var secondary := sin(_sprint_time * 0.5)

    var pos_amp := active_wieldable.sprint_bob_position_amplitude
    _sprint_bob_position = Vector3(
        secondary * pos_amp.x,
        abs(primary) * pos_amp.y,
        primary * pos_amp.z
    )

    var rot_amp := active_wieldable.sprint_bob_rotation_amplitude_deg
    _sprint_bob_rotation = Vector3(
        secondary * rot_amp.x,
        primary * rot_amp.y,
        primary * rot_amp.z
    )


func _update_obstruction(delta: float, active_wieldable: CogitoWieldable) -> void:
    if active_wieldable == null:
        _obstruction.reset()
        return
    # Prefer .get() — "in" can miss script exports on some Node cases.
    var enabled: Variant = active_wieldable.get("enable_obstruction")
    var player := _get_player()
    var cast := _get_obstruction_cast(player)
    if enabled != true or cast == null:
        _obstruction.reset()
        if active_wieldable is CogitoFirearm:
            active_wieldable.set_obstruction_blocked(false)
        return
    # `self` IS the Wieldables node — the probe measures the gun relative to it, so the
    # offsets _apply_combined_motion() writes below cannot feed back into the probe.
    var block_ads: bool = bool(_obstruction.tick(delta, cast, self, active_wieldable, player))
    if active_wieldable is CogitoFirearm:
        active_wieldable.set_obstruction_blocked(block_ads)


func _apply_combined_motion() -> void:
    # Sway/sprint base, then obstruction rotation PIVOTED around %Grip_Point:
    #   O' = O + grip - R * grip
    # so the handle stays put and the barrel swings (user intent).
    var base_pos: Vector3 = _sway_offset + _sprint_pose_position + _sprint_bob_position + _obstruction.pos_offset
    var base_rot: Vector3 = _sprint_pose_rotation + _sprint_bob_rotation
    var obs_rot: Vector3 = _obstruction.rot_offset_deg
    var grip: Vector3 = _obstruction.grip_local

    if grip.length_squared() > 0.000001 and obs_rot.length_squared() > 0.0001:
        var r: Basis = Basis.from_euler(Vector3(
            deg_to_rad(obs_rot.x),
            deg_to_rad(obs_rot.y),
            deg_to_rad(obs_rot.z)
        ))
        # Keep grip fixed in Wieldables parent space while applying R.
        base_pos = base_pos + grip - r * grip

    position = base_pos
    rotation_degrees = base_rot + obs_rot


# Sibling of this node under Head, NOT a child of it: Head is what lean/pitch/recoil move,
# so the cast tracks the gun; parenting it here would make _apply_combined_motion() shove the
# probe out of the wall it just detected.
func _get_obstruction_cast(player: CogitoPlayer) -> ShapeCast3D:
    if player == null:
        return null
    return player.get_node_or_null("Body/Neck/Head/WeaponObstructionCast") as ShapeCast3D


func _kill_sprint_tween() -> void:
    if _sprint_pose_tween:
        _sprint_pose_tween.kill()
        _sprint_pose_tween = null


func _get_active_wieldable() -> CogitoWieldable:
    if get_child_count() == 0:
        return null
    var child := get_child(0)
    if child is CogitoWieldable:
        return child as CogitoWieldable
    return null


func _get_player() -> CogitoPlayer:
    var current := get_parent()
    while current != null:
        if current is CogitoPlayer:
            return current as CogitoPlayer
        current = current.get_parent()
    return null
