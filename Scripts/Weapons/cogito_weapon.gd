extends CogitoWieldable
class_name CogitoFirearm
## Thin orchestrator bridging Weapon_Resource types into Cogito's wieldable system.
## Delegates fire logic, post-fire visuals, anim transitions, and reset to
## weapon_data virtuals; motion to helper RefCounted objects.
##
## Usage:
## 1. Create a wieldable scene (Node3D root with AnimationPlayer + AudioStreamPlayer3D + mesh).
## 2. Attach this script to the root.
## 3. Assign a Weapon_Resource (or subclass) to weapon_data.
## 4. Create a WieldableItemPD inventory item:
##    - charge_max = magazine size
##    - charge_current = starting ammo in magazine
##    - wieldable_damage = damage per hit/pellet
##    - wieldable_range = hitscan/camera ray distance
##    - wieldable_scene = this weapon scene
##    - ammo_item_name = name of the AmmoItemPD in inventory
## 5. Add a Marker3D named "Bullet_Point" (unique name) as the muzzle origin.

enum ShootMotionMode { ANIMATION, TWEEN }
enum ShellEjectTiming { ON_FIRE, ON_CYCLE }
## Mutually-exclusive action states. CYCLING is bolt-action cycle-between-shots.
enum WeaponState { IDLE, CYCLING, RELOADING }
# ── EXPORTS (names preserved for .tscn compatibility) ────────────────────────

@export_group("Weapon Configuration")
## The Weapon_Resource that defines fire mode, recoil, and type-specific data.
@export var weapon_data: Weapon_Resource
@export_group("Shell Ejection")
@export var shell_casing_scene: PackedScene
@export_enum("On Fire", "On Cycle") var shell_eject_timing: int = ShellEjectTiming.ON_FIRE
@export var max_shell_casings: int = 10
@onready var shell_eject_point: Marker3D = get_node_or_null("%shell_eject_point") as Marker3D
@export_group("Muzzle")
## Marker3D where bullets/projectiles spawn. Set via unique name %Bullet_Point.
@onready var bullet_point: Marker3D = get_node_or_null("%Bullet_Point") as Marker3D
## Strong-hand grip / pistol-grip pivot for obstruction roll/yaw. Unique name %Grip_Point.
@onready var grip_point: Marker3D = get_node_or_null("%Grip_Point") as Marker3D
## Muzzle flash scene to spawn on each shot (first-person view).
## Use any muzzle_flash_0N.tscn or short_flash_0N.tscn from Scene/VFX/MuzzleFlash.
@export var muzzle_flash_scene: PackedScene
@export var muzzle_flash_scale: float = 1.0

@export_group("Audio")
@export var sound_shoot: AudioStream
@export var sound_reload: AudioStream

@export_group("ADS Settings")
## Camera FOV when aiming down sights.
@export var ads_fov: float = 65.0
## Default local position of the weapon (hip-fire). Used to tween back from ADS.
@export var default_position: Vector3
## ADS position offset. X is always forced to 0 (centered). Adjust Y and Z only.
@export var ads_position: Vector3 = Vector3(0, 0, 0)
## Recoil vector while aiming. If zero, uses hip recoil scaled by 0.4.
@export var aim_recoil_values: Vector3 = Vector3.ZERO
## Time used when sprint interrupts ADS. Keeps sprint responsive without snapping.
@export_range(0.0, 0.5, 0.01) var ads_to_sprint_time: float = 0.12

@export_group("Shoot Motion")
@export_enum("Animation", "Tween") var shoot_motion_mode: int = ShootMotionMode.TWEEN
@export var hip_shot_position_offset: Vector3 = Vector3.ZERO
@export var hip_shot_rotation_deg: Vector3 = Vector3.ZERO
@export var ads_shot_position_offset: Vector3 = Vector3.ZERO
@export var ads_shot_rotation_deg: Vector3 = Vector3.ZERO
@export var shoot_kick_out_time: float = 0.03
@export var shoot_return_time: float = 0.06
@export var block_ads_during_shot_tween: bool = true

@export_group("Fire Part Motion")
@export var fire_part_node: NodePath
@export var fire_part_position_offset: Vector3 = Vector3.ZERO
@export var fire_part_out_time: float = 0.03
@export var fire_part_return_time: float = 0.06

@export_group("Extra Animations")
## Shoot animation while ADS (leave empty to reuse primary).
@export var anim_shoot_ads: String = "action_primary_ads"
## Reload animation when magazine is completely empty.
@export var anim_reload_empty: String = "reload_empty"
## Reload animation when magazine is completely empty while ADSing.
@export var anim_reload_empty_ads: String = "reload_empty_ads"
## Reload animation while ADSing.
@export var anim_reload_ads: String = "reload_ads"
## Bolt-cycle animation while ADS (leave empty to fall back to boltCycleAnimation).
@export var bolt_cycle_animation_ads: String = "bolt_cycle_ads"

@export_group("Bolt Tween")
## Assign the bolt handle mesh node (e.g. Cylinder_001). When set, bolt cycle uses tweens.
## Tween parameters (positions, rotations, durations) live in BoltAction_Resource.
@export var bolt_part_node: NodePath

@export_group("Pistol Parts")
## Node mesh của hammer. Khi set + weapon_data là Pistol_Resource → chạy hammer tween khi bắn.
@export var hammer_part_node: NodePath

@export_group("Trigger Animation")
## Z-rotation (degrees) the trigger mesh rotates to when the mouse is held.
@export var trigger_pull_rotation: float = -20.0
## Minimum time (seconds) the trigger stays pulled.
@export var trigger_min_hold_time: float = 0.1

@export_group("Obstruction")
## When the gun's collision box hits a wall, rotate it around %Grip_Point (handle stays fixed).
@export var enable_obstruction: bool = true
## Cross-section of the gun's obstruction box: x = width, y = height. Length is not set here —
## it is measured every frame from %Grip_Point to %Bullet_Point, so it always matches the model.
## Height is kept small on purpose: a tall box false-triggers on floors when aiming down.
@export var obstruction_box_size: Vector2 = Vector2(0.14, 0.10)
## Pull toward body at full obstruction.
@export_range(0.0, 0.8, 0.01) var obstruction_pull_back: float = 0.28
## Yaw around grip at full obstruction; muzzle swings screen-left.
@export_range(0.0, 90.0, 0.5) var obstruction_yaw_deg: float = 55.0
## Roll around grip at full obstruction.
@export_range(0.0, 90.0, 0.5) var obstruction_roll_deg: float = 35.0
## Extra lateral slide toward screen-left at full obstruction.
@export_range(0.0, 0.5, 0.01) var obstruction_side: float = 0.18
## Optional pitch around grip (usually 0).
@export_range(0.0, 90.0, 0.5) var obstruction_pitch_deg: float = 0.0
## Exp smoothing speed (slower = less spray/lean flicker snap).
@export_range(1.0, 40.0, 0.5) var obstruction_smooth_speed: float = 12.0
## Auto-exit ADS when jammed. Set ≥1.0 to disable.
@export_range(0.0, 1.0, 0.01) var obstruction_ads_break_threshold: float = 0.85

@export_group("Attachments")
## MeshInstance3D nodes holding the built-in magazine. A fitted magazine that
## carries a magazine_mesh swaps their mesh IN PLACE — the reload animation
## drives these nodes' position/rotation/visible, so a magazine parented to a
## static marker instead would sit still while the animation pulls the mag out.
@export var magazine_mesh_nodes: Array[NodePath] = []
## Hidden while a muzzle attachment with a mount_scene is fitted, so the built-in
## muzzle device doesn't clip through the suppressor spawned at %Bullet_Point.
@export var muzzle_hide_nodes: Array[NodePath] = []


## Grip pivot in this firearm's local space (fallback: origin / approximate handle).
func get_grip_local_position() -> Vector3:
	if grip_point != null and is_instance_valid(grip_point):
		return grip_point.position
	return Vector3(0.0, -0.06, 0.05)

# ── Constants ────────────────────────────────────────────────────────────────

const ADS_RECOIL_SCALE: float = 0.4
const RECOIL_THRESHOLD: float = 0.001

# ── HELPERS (instantiated in _ready, not scene nodes) ────────────────────────

var _shoot_motion: ShootMotionController
var _trigger: TriggerAnimator
var _ads: ADSController
var _ammo: AmmoManager

# ── INTERNAL STATE ───────────────────────────────────────────────────────────

var _state: WeaponState = WeaponState.IDLE
var _mechanics: FirearmMechanicalState = null
var _trigger_held: bool = false
var _fire_cooldown: float = 0.0
var _sprint_blocked_press: bool = false
var _item_ref: WieldableItemPD
var _rest_rotation_degrees: Vector3 = Vector3.ZERO
var _post_fire_cycle_tween: Tween = null
var _bolt_part: Node3D = null
var _bolt_cycle_tween: Tween = null
var _bolt_root_tween: Tween = null
var _bolt_pre_cycle_rest_rot: Vector3 = Vector3.ZERO
var _hammer_part: Node3D = null
var _hammer_tween: Tween = null
var _audio_reload: AudioStreamPlayer3D
var _reload_mechanics_snapshot: Dictionary = {}
var _setup_valid: bool = false
var _obstruction_blocked: bool = false

# Effective ADS values = exports modified by the item's attachments (per-instance).
# Recomputed on equip; attachments only change while holstered.
@onready var _eff_ads_fov: float = ads_fov
@onready var _eff_ads_time: float = ads_time
@onready var _eff_ads_position: Vector3 = ads_position
var _flash_suppressed: bool = false
# NodePath -> Mesh authored in the scene, cached before the first magazine swap.
var _builtin_magazine_meshes: Dictionary = {}


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	if wieldable_mesh:
		wieldable_mesh.hide()
	if animation_player:
		animation_player.animation_finished.connect(_on_anim_finished)
	_audio_reload = AudioStreamPlayer3D.new()
	_audio_reload.bus = audio_stream_player_3d.bus if audio_stream_player_3d else "Master"
	add_child(_audio_reload)

	_trigger = TriggerAnimator.new(self)
	_ads = ADSController.new(self)
	_shoot_motion = ShootMotionController.new(self)
	_shoot_motion.shoot_visual_finished.connect(_on_shoot_visual_finished)
	_ammo = AmmoManager.new(null)
	_setup_valid = _validate_required_setup()
	if not _setup_valid:
		set_physics_process(false)
		return
	_sync_shoot_motion_config()
	_capture_rest_state()
	if bolt_part_node != NodePath(""):
		_bolt_part = get_node_or_null(bolt_part_node) as Node3D
	if hammer_part_node != NodePath(""):
		_hammer_part = get_node_or_null(hammer_part_node) as Node3D


func _physics_process(delta: float) -> void:
	if not _setup_valid or weapon_data == null:
		return

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	# Movement pauses do not pause the world (inventory/dialogue), so stop held
	# fire ourselves. Clearing the latch also prevents firing again when UI closes.
	if _trigger_held and _is_player_input_blocked():
		action_primary(_item_ref, true)

	# Auto-fire loop — only when state is IDLE (not reloading/cycling).
	if _trigger_held and _state == WeaponState.IDLE and _fire_cooldown <= 0.0:
		if _is_player_sprinting():
			_trigger_held = false
		elif _item_ref and _mechanics != null and _mechanics.can_fire():
			_try_fire()
		else:
			_trigger_held = false


# ── CogitoWieldable interface ────────────────────────────────────────────────

func equip(_player_interaction_component: PlayerInteractionComponent) -> void:
	player_interaction_component = _player_interaction_component
	_item_ref = item_reference
	if _ammo:
		_ammo.set_pic(player_interaction_component)
	if not _setup_valid:
		_trigger_held = false
		return
	_apply_attachment_visuals()
	_compute_effective_ads()
	_reset_state()
	_shoot_motion.cancel(false)
	
	# Initialize mechanical state
	_mechanics = FirearmMechanicalState.new()
	if weapon_data and _item_ref:
		# The fitted magazine — not the Weapon_Resource — decides how much the
		# weapon feeds. No magazine = chamber only (see FirearmMechanicalState).
		var config := weapon_data.get_mechanics_config()
		var magazine := _item_ref.get_magazine()
		config["magazine_capacity"] = magazine.magazine_capacity if magazine else 0
		_mechanics.configure(config)
		_restore_mechanics_from_item()
		# Set metadata for HUD displays
		_item_ref.set_meta("magazine_capacity", _mechanics.magazine_capacity)
		_item_ref.set_meta("chamber_capacity", _mechanics.chamber_capacity)
		_apply_mechanics_visual_state()
		_commit_mechanics_to_item()

	if animation_player:
		animation_player.play(anim_equip)
	_configure_recoil()


func unequip() -> void:
	if not _setup_valid or _shoot_motion == null or _ads == null:
		_trigger_held = false
		_state = WeaponState.IDLE
		return

	if _state == WeaponState.RELOADING and not _reload_mechanics_snapshot.is_empty() and _mechanics:
		_mechanics.restore_from_save_dict(_reload_mechanics_snapshot)
	_reload_mechanics_snapshot.clear()
	_commit_mechanics_to_item()

	if _bolt_cycle_tween:
		_bolt_cycle_tween.kill()
		_bolt_cycle_tween = null
	if _bolt_root_tween:
		_bolt_root_tween.kill()
		_bolt_root_tween = null
	if _hammer_tween:
		_hammer_tween.kill()
		_hammer_tween = null
	if _post_fire_cycle_tween:
		_post_fire_cycle_tween.kill()
		_post_fire_cycle_tween = null
	_shoot_motion.cancel(true)
	_apply_mechanics_visual_state()
	_apply_rest_pose()
	_trigger_held = false
	_state = WeaponState.IDLE
	_sprint_blocked_press = false
	if _ads.is_aiming:
		_ads.exit(weapon_data, _eff_ads_fov, _eff_ads_time, default_position,
				block_ads_during_shot_tween, _shoot_motion.is_active, true,
				player_interaction_component)
	else:
		_ads.cancel_tweens_and_snap(weapon_data, _eff_ads_fov, default_position, _eff_ads_position)
	if animation_player:
		animation_player.play(anim_unequip)


func action_primary(_passed_item_reference: InventoryItemPD, _is_released: bool) -> void:
	_item_ref = _passed_item_reference as WieldableItemPD
	if not _setup_valid or weapon_data == null:
		_trigger_held = false
		return

	if _is_released:
		_trigger_held = false
		if not _sprint_blocked_press:
			var elapsed: float = Time.get_ticks_msec() / 1000.0 - _trigger.press_time
			var delay: float = maxf(0.0, trigger_min_hold_time - elapsed)
			_trigger.release_delayed(0.0, delay)
		_sprint_blocked_press = false
		return

	if _is_player_sprinting() or _is_player_input_blocked():
		_sprint_blocked_press = true
		return

	_sprint_blocked_press = false
	_trigger.press_time = Time.get_ticks_msec() / 1000.0
	_trigger.pull(trigger_pull_rotation)

	var mode := weapon_data.get_fire_mode()

	# AUTO weapons: flag continuous fire, attempt first shot immediately
	if mode == Weapon_Resource.FireMode.AUTO:
		if _item_ref and (_mechanics == null or not _mechanics.can_fire()):
			_item_ref.send_empty_hint()
			return
		_trigger_held = true
		_try_fire()
		return

	# All other modes: single shot on press
	_try_fire()


func action_secondary(_is_released: bool) -> void:
	if not _setup_valid or weapon_data == null or _ads == null:
		return
	if _is_released:
		if _bolt_root_tween:
			_bolt_root_tween.kill()
			_bolt_root_tween = null
			rotation_degrees = _bolt_pre_cycle_rest_rot
		_ads.exit(weapon_data, _eff_ads_fov, _eff_ads_time, default_position,
				block_ads_during_shot_tween, _shoot_motion.is_active, false,
				player_interaction_component)
	else:
		if player_interaction_component != null and player_interaction_component.is_consumable_action_active():
			return
		if _is_player_sprinting() or _obstruction_blocked or _ads.is_view_blocked():
			return
		if _bolt_root_tween:
			_bolt_root_tween.kill()
			_bolt_root_tween = null
			rotation_degrees = _bolt_pre_cycle_rest_rot
		_ads.enter(weapon_data, _eff_ads_fov, _eff_ads_time, _eff_ads_position, default_position,
				block_ads_during_shot_tween, _shoot_motion.is_active,
				animation_player, player_interaction_component)


func reload() -> void:
	if player_interaction_component != null and player_interaction_component.is_consumable_action_active():
		return
	if not _setup_valid or weapon_data == null or animation_player == null or _state != WeaponState.IDLE or animation_player.is_playing():
		return
	if _item_ref == null:
		return

	# Mechanics-based ammo needed checks. With no magazine fitted, "reload" means
	# hand-loading the chamber, so has_reload_room() covers both cases.
	var has_room := _mechanics == null or _mechanics.has_reload_room()
	if not has_room or _ammo.get_available_ammo(_item_ref) <= 0:
		return

	_shoot_motion.cancel(true)
	_apply_rest_pose()
	if not _play_anim(_get_reload_animation_name()):
		return
	if _mechanics:
		_reload_mechanics_snapshot = _mechanics.to_save_dict()
	_state = WeaponState.RELOADING
	_play_reload_sound()


func cancel_ads_for_sprint() -> void:
	_cancel_ads_with_duration(ads_to_sprint_time)


## A collision exit must not wait for a shot tween to finish.
func cancel_ads_for_obstruction() -> void:
	_cancel_ads_with_duration(ads_to_sprint_time, true)


func set_obstruction_blocked(blocked: bool) -> void:
	_obstruction_blocked = blocked
	if blocked:
		cancel_ads_for_obstruction()


func _cancel_ads_with_duration(duration: float, force: bool = false) -> void:
	if _ads == null or weapon_data == null:
		return
	if _ads.is_aiming:
		if _bolt_root_tween:
			_bolt_root_tween.kill()
			_bolt_root_tween = null
			rotation_degrees = _bolt_pre_cycle_rest_rot
		_ads.exit(weapon_data, _eff_ads_fov, _eff_ads_time, default_position,
				block_ads_during_shot_tween and not force, _shoot_motion.is_active, false,
				player_interaction_component, duration)


func is_ads_active() -> bool:
	return _ads != null and _ads.is_aiming


func should_suspend_container_motion() -> bool:
	return (animation_player != null and animation_player.is_playing()) \
		or _state != WeaponState.IDLE \
		or _trigger_held \
		or (_shoot_motion != null and _shoot_motion.is_active)


# ── Fire logic ───────────────────────────────────────────────────────────────

func _try_fire() -> void:
	if not _setup_valid or bullet_point == null or player_interaction_component == null:
		_trigger_held = false
		return
	if _is_player_sprinting() or _is_player_input_blocked():
		_trigger_held = false
		return
	# State gate replaces the old _is_reloading + _bolt_is_cycled + _pump_ready
	# guard chain: any non-IDLE state blocks fire.
	if weapon_data == null or _state != WeaponState.IDLE or _fire_cooldown > 0.0:
		return
	if _item_ref == null or _mechanics == null or not _mechanics.can_fire():
		if _item_ref:
			_item_ref.send_empty_hint()
		_trigger_held = false
		return

	var mode := weapon_data.get_fire_mode()

	if _uses_animation_shoot_motion() and mode != Weapon_Resource.FireMode.AUTO and _is_shoot_animation_playing():
		return

	# ── Execute shot ─────────────────────────────────────────────────────────

	# Consume ammo from mechanical chamber
	_mechanics.fire_round()
	# If weapon does not require manual cycling (semi-auto / auto), cycle immediately
	if weapon_data and not weapon_data.manual_cycle_required:
		_mechanics.cycle_action()
		# Slide-lock / bolt-lock on last round empty
		if _mechanics.is_empty() and weapon_data.locks_open_on_empty:
			_mechanics.bolt_locked_open = true
			_shoot_motion.fire_part_locked = true
	_commit_mechanics_to_item()

	# Visual (must be after mechanics state updates so slide-lock is detected before tween building)
	_play_shoot_visual()

	# Sound
	if sound_shoot:
		audio_stream_player_3d.stream = sound_shoot
		audio_stream_player_3d.play()

	var sound_events = get_node_or_null("/root/SoundEvents")
	if sound_events:
		var emitter: Node = null
		if player_interaction_component:
			emitter = player_interaction_component.get_parent()
		var loudness: float = weapon_data.gunshot_loudness \
				* (_item_ref.attachment_multiplier(&"loudness_multiplier") if _item_ref else 1.0)
		sound_events.sound_emitted.emit(bullet_point.global_position, loudness, &"gunshot", emitter)

	# Muzzle flash (first-person view)
	_spawn_muzzle_flash_fpv()

	# Delegate fire to resource (polymorphic dispatch)
	var ctx := _build_fire_context()
	if ctx.is_empty():
		_trigger_held = false
		return
	weapon_data.fire(ctx)
	if shell_eject_timing == ShellEjectTiming.ON_FIRE and not weapon_data.handles_own_shell_eject(self):
		_spawn_shell_casing()

	# Recoil
	_apply_recoil()

	# Cooldown (polymorphic)
	_fire_cooldown = weapon_data.get_fire_cooldown()

	# Type-specific post-fire visuals + state (bolt cycle, hammer, slide-lock).
	weapon_data.play_post_fire_visual(self)


func _build_fire_context() -> Dictionary:
	if not _setup_valid or bullet_point == null or player_interaction_component == null:
		return {}
	var aim_point := _resolve_aim_point()
	var shot_range := 1000.0
	if _item_ref and _item_ref.wieldable_range > 0.0:
		shot_range = _item_ref.get_effective_range()
	return {
		"bullet_point": bullet_point,
		# Legacy key kept for any resource that still reads camera_collision.
		"camera_collision": aim_point,
		"aim_point": aim_point,
		"shot_range": shot_range,
		"is_aiming": _ads.is_aiming,
		"item_ref": _item_ref,
		"player_interaction_component": player_interaction_component,
		"world_3d": get_world_3d(),
		"viewport": get_viewport(),
		"scene_tree": get_tree(),
	}


## Crosshair aim point in world space (camera ray). The bullet still leaves the
## barrel — fire code uses muzzle→aim_point so hip-fire has realistic offset.
func _resolve_aim_point() -> Vector3:
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	var shot_range := 1000.0
	if _item_ref and _item_ref.wieldable_range > 0.0:
		shot_range = _item_ref.get_effective_range()

	if camera == null:
		# Fallback to Cogito helper (no mask control).
		return player_interaction_component.Get_Camera_Collision()

	var viewport_size := get_viewport().get_visible_rect().size
	var screen_center := viewport_size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)
	var ray_end := ray_origin + ray_dir * shot_range

	var params := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	if player_interaction_component.player_rid:
		params.exclude = [player_interaction_component.player_rid]
	# Same mask as damage: Environment + Interactables (not corpse loot volumes).
	params.collision_mask = Weapon_Resource.COLLISION_MASK_DAMAGE
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		return hit["position"]
	return ray_end


# ── Shoot visual ─────────────────────────────────────────────────────────────

func _play_shoot_visual() -> bool:
	if _uses_animation_shoot_motion():
		animation_player.play(_get_shoot_animation_name())
		return true
	# Full-auto: restarting the kick tween every round cancels mid-return and
	# snaps the viewmodel. Keep one kick alive until it finishes.
	if _shoot_motion != null and _shoot_motion.is_active:
		return false
	var rest_pos := _ads.get_rest_position(weapon_data, _eff_ads_position, default_position)
	_shoot_motion.play(rest_pos, _rest_rotation_degrees, _ads.is_aiming)
	return false


func _on_shoot_visual_finished() -> void:
	_apply_rest_pose()


func _get_shoot_visual_duration() -> float:
	return _shoot_motion.get_duration()


# ── Post-fire cycling ────────────────────────────────────────────────────────
## Schedule a post-fire callback after a delay (e.g. shoot-tween duration).
## Resources call this to start their bolt/pump cycle when shoot motion finishes.
func _schedule_post_fire_cycle(delay: float, on_cycle: Callable) -> void:
	if _post_fire_cycle_tween:
		_post_fire_cycle_tween.kill()
	_post_fire_cycle_tween = create_tween()
	if delay > 0.0:
		_post_fire_cycle_tween.tween_interval(delay)
	_post_fire_cycle_tween.finished.connect(on_cycle)


## Wait `delay` seconds, then call `on_done`.  Used by resources whose cycle
## animation is missing (fallback to a timed completion).
func _complete_cycle_after_delay(delay: float, on_done: Callable) -> void:
	if delay <= 0.0:
		on_done.call()
		return
	_post_fire_cycle_tween = create_tween()
	_post_fire_cycle_tween.tween_interval(delay)
	_post_fire_cycle_tween.finished.connect(on_done)


# ── Animation callbacks ──────────────────────────────────────────────────────

func _on_anim_finished(anim_name: StringName) -> void:
	# Connected in _ready() before validation runs — stay fail-closed here too.
	if not _setup_valid:
		return

	# Reload finished — restock magazine and clear state.
	if _is_reload_animation(anim_name):
		_finish_reload_with_mechanics()
		_state = WeaponState.IDLE
		_capture_rest_state()

	# Per-type anim transitions (bolt cycle, slide-lock release, etc.).
	if weapon_data:
		weapon_data.on_anim_finished(self, anim_name)

	# Equip finished
	if anim_name == anim_equip:
		_capture_rest_state()


func _finish_reload_with_mechanics() -> void:
	if _item_ref == null or _mechanics == null:
		return
	var is_empty_reload := _mechanics.is_empty()
	var rounds_needed: int
	if _mechanics.has_no_magazine():
		rounds_needed = _mechanics.chamber_capacity - _mechanics.chamber_rounds
	elif is_empty_reload:
		# Auto-chamber empty reload fills chamber + magazine (capacity + chamber).
		# Asking only for magazine_capacity left guns at 30/31 after a "full" reload.
		if _mechanics.auto_chambers_on_empty_reload:
			rounds_needed = _mechanics.magazine_capacity + _mechanics.chamber_capacity
		else:
			rounds_needed = _mechanics.magazine_capacity
	else:
		rounds_needed = _mechanics.magazine_capacity - _mechanics.magazine_rounds

	# Consume ammo from inventory
	var consumed := _ammo.consume_ammo(_item_ref, rounds_needed)
	if consumed > 0:
		var actual_loaded: int
		if is_empty_reload:
			actual_loaded = _mechanics.finish_reload_empty(consumed)
		else:
			actual_loaded = _mechanics.finish_reload_tactical(consumed)
		_mechanics.bolt_locked_open = false

		# Return unused ammo to inventory
		var unused := consumed - actual_loaded
		if unused > 0:
			_ammo.return_ammo(_item_ref, unused)

	_reload_mechanics_snapshot.clear()
	_commit_mechanics_to_item()
	_apply_mechanics_visual_state()


func on_cycle_complete() -> void:
	if _mechanics:
		_mechanics.cycle_action()
		# Slide-lock / bolt-lock on last round empty
		if _mechanics.is_empty() and weapon_data and weapon_data.locks_open_on_empty:
			_mechanics.bolt_locked_open = true
			_shoot_motion.fire_part_locked = true
		_commit_mechanics_to_item()


func _commit_mechanics_to_item() -> void:
	if _item_ref == null or _mechanics == null:
		return
	var state := _mechanics.to_save_dict()
	if _item_ref.has_method("set_firearm_mechanical_state"):
		_item_ref.set_firearm_mechanical_state(state)
	var total := _mechanics.get_loaded_total()
	_item_ref.charge_current = float(total)
	# Safely check and call update wieldable data on WieldableItemPD
	if _item_ref.get("is_being_wielded") == true:
		_item_ref.update_wieldable_data(player_interaction_component)
	_item_ref.charge_changed.emit()


func _restore_mechanics_from_item() -> void:
	if _mechanics == null:
		return
	var restored := false
	if _item_ref and _item_ref.has_method("has_firearm_mechanical_state") and _item_ref.has_firearm_mechanical_state():
		var state: Dictionary = _item_ref.get_firearm_mechanical_state()
		# charge_current is only a MIRROR of this dict — except the "charge loose
		# rounds into a gun" paths (WieldableItemPD.add(): dragging ammo onto the
		# weapon, or picking ammo up while wielding it) bump charge_current alone.
		# When the two disagree, charge_current is the newer truth; restoring the
		# stale dict here would silently destroy the rounds just loaded.
		var state_total: int = int(state.get("magazine_rounds", 0)) + int(state.get("chamber_rounds", 0))
		if state_total == int(_item_ref.charge_current):
			restored = _mechanics.restore_from_save_dict(state)
	if restored:
		return
	var total := int(_item_ref.charge_current) if _item_ref else 0
	_mechanics.reconstruct_from_total(total)
	if _mechanics.is_empty() and weapon_data and weapon_data.locks_open_on_empty:
		# Legacy saves only stored charge_current. This inference may be wrong for an
		# old manually-closed empty weapon, but preserves the common empty-slide-lock case.
		_mechanics.bolt_locked_open = true


## Re-reads the item after something OUTSIDE the weapon changed its ammo (the
## inventory charging loose rounds into it). Without this the live mechanics keep
## the old count and the next _commit_mechanics_to_item() writes it straight back
## over the rounds that were just loaded.
func sync_mechanics_from_item() -> void:
	if _mechanics == null or _item_ref == null:
		return
	_restore_mechanics_from_item()
	_apply_mechanics_visual_state()
	_commit_mechanics_to_item()


func _apply_mechanics_visual_state() -> void:
	if _mechanics == null or _shoot_motion == null:
		return
	var should_lock_fire_part := _mechanics.bolt_locked_open
	_shoot_motion.fire_part_locked = should_lock_fire_part
	if _shoot_motion.fire_part == null:
		return
	if should_lock_fire_part:
		_shoot_motion.fire_part.position = _shoot_motion.fire_part_rest_position + _shoot_motion.fire_part_position_offset
	else:
		_shoot_motion.fire_part.position = _shoot_motion.fire_part_rest_position


# ── Helpers ──────────────────────────────────────────────────────────────────

## Play `anim_name` only if the AnimationPlayer really has it. Returns false (and warns)
## otherwise, so callers never latch a WeaponState that only `animation_finished` can clear.
func _play_anim(anim_name: String) -> bool:
	if animation_player == null or anim_name == "" or not animation_player.has_animation(anim_name):
		push_warning("cogito_weapon: %s has no animation '%s'" % [name, anim_name])
		return false
	animation_player.play(anim_name)
	return true


func _validate_required_setup() -> bool:
	var missing := PackedStringArray()
	if weapon_data == null:
		missing.append("weapon_data")
	if bullet_point == null:
		missing.append("%Bullet_Point Marker3D")
	if animation_player == null:
		missing.append("AnimationPlayer")
	if audio_stream_player_3d == null:
		missing.append("AudioStreamPlayer3D")

	# Configured-but-dangling optional wiring: warn loudly, don't brick the weapon —
	# every consumer already degrades gracefully when these resolve to null.
	# ponytail: warn-only; promote to fail-closed if a silent-null ever ships a bug.
	for entry: Array in [["fire_part_node", fire_part_node], ["bolt_part_node", bolt_part_node],
			["hammer_part_node", hammer_part_node]]:
		var path: NodePath = entry[1]
		if path != NodePath("") and (get_node_or_null(path) as Node3D) == null:
			push_warning("cogito_weapon: %s has %s = '%s' but no Node3D there." % [name, entry[0], path])
	if shell_casing_scene != null and shell_eject_point == null:
		push_warning("cogito_weapon: %s has shell_casing_scene but no %%shell_eject_point Marker3D." % name)

	if missing.is_empty():
		return true
	push_error("cogito_weapon: disabling %s; missing required setup: %s" % [name, ", ".join(missing)])
	return false


func _configure_recoil() -> void:
	var rn := _get_recoil_node()
	if rn and weapon_data:
		var recoil_mult: float = _item_ref.attachment_multiplier(&"recoil_multiplier") if _item_ref else 1.0
		var hip: Vector3 = Vector3(weapon_data.recoilVertical, weapon_data.recoilHorizontal, 0.0) * recoil_mult
		rn.set_recoil(hip)
		var aim: Vector3 = aim_recoil_values * recoil_mult if aim_recoil_values.length() > RECOIL_THRESHOLD else hip * ADS_RECOIL_SCALE
		rn.set_aim_recoil(aim)
		rn.return_speed = weapon_data.recoilRecovery


# ── Attachments ──────────────────────────────────────────────────────────────

## Spawns mount_scene visuals for the item's attachments and caches derived
## flags. Called on equip — attachments only change while holstered, so no
## live-refresh path is needed. Optics are added as DIRECT children of the
## weapon root so ADSController's ScopeController child discovery finds them.
func _apply_attachment_visuals() -> void:
	_clear_attachment_visuals()
	_flash_suppressed = false
	if _item_ref == null:
		return
	var optic_mount := get_node_or_null("%Optic_Mount") as Node3D
	var muzzle_mounted := false
	for item in _item_ref.get_attached_items():
		if item.suppresses_muzzle_flash:
			_flash_suppressed = true
		if item.mount_scene == null:
			continue
		var node := item.mount_scene.instantiate() as Node3D
		if node == null:
			continue
		node.add_to_group("attachment_visual")
		match item.attachment_slot:
			AttachmentItemPD.AttachmentSlot.OPTIC:
				if optic_mount == null:
					push_warning("cogito_weapon: %s has optic '%s' but no %%Optic_Mount marker." % [name, item.name])
					node.free()
					continue
				add_child(node)
				node.global_transform = optic_mount.global_transform
				if node is ScopeController:
					node.view_obstructed.connect(cancel_ads_for_obstruction)
			AttachmentItemPD.AttachmentSlot.MUZZLE:
				if bullet_point == null:
					node.free()
					continue
				bullet_point.add_child(node)
				node.transform = Transform3D.IDENTITY
				muzzle_mounted = true
			_:
				# Data-only slots (grip/stock v1) shouldn't carry a scene.
				node.free()
	_apply_magazine_mesh(_item_ref.get_magazine())
	_set_nodes_visible(muzzle_hide_nodes, not muzzle_mounted)


func _clear_attachment_visuals() -> void:
	for node in find_children("*", "", true, false):
		if node.is_in_group("attachment_visual"):
			node.get_parent().remove_child(node)
			node.queue_free()
	_apply_magazine_mesh(null)
	_set_nodes_visible(muzzle_hide_nodes, true)


## Swaps the built-in magazine mesh for the fitted magazine's own. Null (or a
## magazine with no mesh of its own) restores what the scene authored. Only the
## `mesh` property changes, so the animation tracks that drive these nodes'
## transform and visibility keep working untouched.
func _apply_magazine_mesh(magazine: AttachmentItemPD) -> void:
	var swap_in: Mesh = magazine.magazine_mesh if magazine != null else null
	for path in magazine_mesh_nodes:
		var mesh_node := get_node_or_null(path) as MeshInstance3D
		if mesh_node == null:
			continue
		if not _builtin_magazine_meshes.has(path):
			_builtin_magazine_meshes[path] = mesh_node.mesh
		mesh_node.mesh = swap_in if swap_in != null else _builtin_magazine_meshes[path]


func _set_nodes_visible(paths: Array[NodePath], is_visible: bool) -> void:
	for path in paths:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			node.visible = is_visible


## Effective ADS values = weapon exports modified by the equipped optic.
func _compute_effective_ads() -> void:
	_eff_ads_fov = ads_fov
	_eff_ads_time = ads_time
	_eff_ads_position = ads_position
	if _item_ref == null:
		return
	_eff_ads_time = ads_time * _item_ref.attachment_multiplier(&"ads_time_multiplier")
	var optic: AttachmentItemPD = _item_ref.get_attachment_item(AttachmentItemPD.AttachmentSlot.OPTIC)
	if optic:
		if optic.ads_fov_override > 0.0:
			_eff_ads_fov = optic.ads_fov_override
		_eff_ads_position = ads_position + optic.ads_position_offset


func _apply_recoil() -> void:
	var rn := _get_recoil_node()
	if rn:
		rn.recoil_fire(_ads.is_aiming)


func _get_recoil_node() -> Node3D:
	if not player_interaction_component:
		return null
	var player := player_interaction_component.get_parent()
	if not player:
		return null
	return player.find_child("CameraRecoil", true, false) as Node3D


func _is_player_sprinting() -> bool:
	if not player_interaction_component:
		return false
	var player := player_interaction_component.get_parent()
	return player != null and player.get("is_sprinting") == true


func _is_player_input_blocked() -> bool:
	if player_interaction_component == null:
		return false
	var player := player_interaction_component.get_parent()
	return player != null and (player.get("is_movement_paused") == true \
			or player.get("is_showing_ui") == true or player.get("is_dead") == true \
			or player_interaction_component.is_consumable_action_active())


func _get_reload_animation_name() -> String:
	var is_empty := _mechanics != null and _mechanics.is_empty()
	if _ads.is_aiming:
		if is_empty and anim_reload_empty_ads != "":
			return anim_reload_empty_ads
		if anim_reload_ads != "":
			return anim_reload_ads
		if is_empty and anim_reload_empty != "":
			return anim_reload_empty
	if is_empty and anim_reload_empty != "":
		return anim_reload_empty
	return anim_reload


func _is_reload_animation(anim_name: StringName) -> bool:
	return anim_name == anim_reload \
		or anim_name == anim_reload_empty \
		or (anim_reload_ads != "" and anim_name == anim_reload_ads) \
		or (anim_reload_empty_ads != "" and anim_name == anim_reload_empty_ads)


func _uses_animation_shoot_motion() -> bool:
	if shoot_motion_mode != ShootMotionMode.ANIMATION:
		return false
	var shoot_anim := _get_shoot_animation_name()
	return shoot_anim != "" and animation_player.has_animation(shoot_anim)


func _get_shoot_animation_name() -> String:
	if _ads.is_aiming and anim_shoot_ads != "" and animation_player.has_animation(anim_shoot_ads):
		return anim_shoot_ads
	return anim_action_primary


func _is_shoot_animation_name(anim_name: StringName) -> bool:
	return anim_name == anim_action_primary or (anim_shoot_ads != "" and anim_name == anim_shoot_ads)


func _is_shoot_animation_playing() -> bool:
	return animation_player.is_playing() and _is_shoot_animation_name(animation_player.current_animation)


func _sync_shoot_motion_config() -> void:
	_shoot_motion.hip_shot_position_offset = hip_shot_position_offset
	_shoot_motion.hip_shot_rotation_deg = hip_shot_rotation_deg
	_shoot_motion.ads_shot_position_offset = ads_shot_position_offset
	_shoot_motion.ads_shot_rotation_deg = ads_shot_rotation_deg
	_shoot_motion.shoot_kick_out_time = shoot_kick_out_time
	_shoot_motion.shoot_return_time = shoot_return_time
	_shoot_motion.fire_part_position_offset = fire_part_position_offset
	_shoot_motion.fire_part_out_time = fire_part_out_time
	_shoot_motion.fire_part_return_time = fire_part_return_time
	_resolve_fire_part()


func _resolve_fire_part() -> void:
	_shoot_motion.fire_part = null
	if fire_part_node != NodePath(""):
		_shoot_motion.fire_part = get_node_or_null(fire_part_node) as Node3D
	if _shoot_motion.fire_part:
		_shoot_motion.fire_part_rest_position = _shoot_motion.fire_part.position


func _capture_rest_state() -> void:
	_rest_rotation_degrees = rotation_degrees
	if _shoot_motion != null and _shoot_motion.fire_part_locked:
		return
	_resolve_fire_part()


func _apply_rest_pose() -> void:
	position = _ads.get_rest_position(weapon_data, _eff_ads_position, default_position)
	rotation_degrees = _rest_rotation_degrees
	if _shoot_motion.fire_part and not _shoot_motion.fire_part_locked:
		_shoot_motion.fire_part.position = _shoot_motion.fire_part_rest_position


func _reset_state() -> void:
	_state = WeaponState.IDLE
	_obstruction_blocked = false
	_fire_cooldown = 0.0
	_trigger_held = false
	_sprint_blocked_press = false
	_ads.is_aiming = false
	if _bolt_cycle_tween:
		_bolt_cycle_tween.kill()
		_bolt_cycle_tween = null
	if _bolt_root_tween:
		_bolt_root_tween.kill()
		_bolt_root_tween = null
	if _hammer_tween:
		_hammer_tween.kill()
		_hammer_tween = null
	# Per-type rest snap (bolt forward+locked, hammer rest, etc.).
	if weapon_data:
		weapon_data.on_reset(self)
	_shoot_motion.fire_part_locked = false
	_capture_rest_state()

func _play_reload_sound() -> void:
	if not sound_reload:
		return
	_audio_reload.stream = sound_reload
	_audio_reload.play()


func _spawn_muzzle_flash_fpv() -> void:
	if _flash_suppressed or muzzle_flash_scene == null or bullet_point == null:
		return
	var flash := muzzle_flash_scene.instantiate() as Node3D
	if flash == null:
		return
	flash.scale = Vector3.ONE * muzzle_flash_scale
	# Parent under the muzzle marker so the flash follows the gun.
	bullet_point.add_child(flash)
	flash.transform = Transform3D.IDENTITY
	# ~7 frames at 60 fps — long enough for GPUParticles3D to emit + render a visible burst,
	# short enough to avoid catching VFXController's second loop cycle (stale particles).
	# weakref prevents "lambda capture freed" error if weapon is unequipped before timeout.
	var flash_ref: WeakRef = weakref(flash)
	get_tree().create_timer(0.05, false).timeout.connect(func():
		var f: Object = flash_ref.get_ref()
		if f != null:
			f.call("queue_free")
	)


func _spawn_shell_casing() -> void:
	if shell_casing_scene == null or shell_eject_point == null:
		return

	var shell_instance := shell_casing_scene.instantiate() as ShellCasingFx
	if shell_instance == null:
		push_warning("shell_casing_scene root must be ShellCasingFx.")
		return

	if player_interaction_component:
		var player := player_interaction_component.get_parent()
		if "main_velocity" in player:
			shell_instance.player_velocity = player.main_velocity
		shell_instance.player_node = player

	var world_root := get_tree().current_scene
	if world_root == null:
		return

	world_root.add_child(shell_instance)
	shell_instance.global_transform = shell_eject_point.global_transform

	var active_shells := get_tree().get_nodes_in_group("shell_casings")
	if active_shells.size() > max_shell_casings:
		active_shells[0].queue_free()
