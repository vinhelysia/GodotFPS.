extends Resource
class_name Weapon_Resource


@export var weaponName: String
@export_group("Recoil")
@export var recoilVertical: float
@export var recoilHorizontal: float
@export var recoilRecovery: float = 5.0


@export_flags("Hitscan", "Projectile") var Type
@export var bulletProjectileToLoad: PackedScene
@export var weaponVelocity: int

@export_group("Audio")
## How loud a shot is to NPC hearing (SoundEvents propagation radius scales with
## this). Suppressed / small-caliber weapons should set this lower for stealth;
## it does not affect the audible SFX volume, only AI perception range.
@export var gunshot_loudness: float = 80.0

@export_group("Firearm Mechanics")
@export var magazine_capacity: int = 30
@export var chamber_capacity: int = 1
@export var locks_open_on_empty: bool = false
@export var auto_chambers_on_empty_reload: bool = true
@export var manual_cycle_required: bool = false

func get_mechanics_config() -> Dictionary:
	return {
		"magazine_capacity": magazine_capacity,
		"chamber_capacity": chamber_capacity,
		"auto_chambers_on_empty_reload": auto_chambers_on_empty_reload,
		"locks_open_on_empty": locks_open_on_empty,
	}

# ── Fire Type (matches @export_flags bit positions) ───────────────────────────
enum FireType { HITSCAN = 1, PROJECTILE = 2 }

# ── Fire Mode (live weapons: AR=AUTO, bolt=BOLT_ACTION, pistol=SEMI) ───────────
enum FireMode { SEMI, AUTO, BOLT_ACTION }

func get_fire_mode() -> FireMode:
	return FireMode.SEMI

# ── Virtual: Fire cooldown ─────────────────────────────────────────────────────
## Seconds between shots. Subclasses override for RPM-based or trigger-reset values.
func get_fire_cooldown() -> float:
	return 0.1


# ── Virtual: Fire dispatch ─────────────────────────────────────────────────────
## Execute the actual shot. Default dispatches hitscan or projectile based on Type.
## ctx keys: bullet_point, camera_collision, is_aiming, item_ref,
##           player_interaction_component, world_3d, viewport, scene_tree
func fire(ctx: Dictionary) -> void:
	match Type:
		FireType.HITSCAN: _hitscan_fire(ctx)
		FireType.PROJECTILE: _projectile_fire(ctx)


# ── Virtual: Post-fire visual ─────────────────────────────────────────────────
## Called after a confirmed shot. Run any type-specific visual side-effects
## (bolt root tween, hammer tween, slide-lock detection).
func play_post_fire_visual(_weapon: Node) -> void:
	pass


# ── Virtual: Animation finished ───────────────────────────────────────────────
## Called from the weapon's _on_anim_finished. Use to react to bolt-cycle
## animations completing without polluting the orchestrator with type checks.
func on_anim_finished(_weapon: Node, _anim_name: StringName) -> void:
	pass


# ── Virtual: Reset state on equip ─────────────────────────────────────────────
## Called from the weapon's _reset_state. Snap mechanical parts to rest pose.
func on_reset(_weapon: Node) -> void:
	pass


# ── Virtual: Shell ejection ownership ─────────────────────────────────────────
## True if this resource drives its own shell-eject timing (e.g. bolt-action
## with a timed shell_eject_delay). When true, the orchestrator skips its
## ON_FIRE shell spawn so the resource can do it at the right moment.
func handles_own_shell_eject(_weapon: Node) -> bool:
	return false


# ── Virtual: ADS overrides ────────────────────────────────────────────────────
## Negative = use weapon's ads_fov export.
func get_ads_fov_override() -> float:
	return -1.0

## Negative = use weapon's ads_time export.
func get_ads_duration_override() -> float:
	return -1.0

func is_scope_weapon() -> bool:
	return false


# ── Shared fire implementations ───────────────────────────────────────────────

## Layers 1|2 (Environment|Interactables) only — matches bt_shoot.gd's NPC
## hitscan mask. Deliberately excludes layer 3 ("Corpse", CorpseContainer's
## loot-anywhere-on-body volumes) so bullets pass through corpses instead of
## being absorbed by their interact shapes.
const COLLISION_MASK_DAMAGE: int = 0b0011
const HITSCAN_OVERSHOOT: float = 2.0
const MIN_SHOT_DIR_LEN_SQ: float = 0.0001

## Semi-realistic: always spawn / cast from the muzzle (%Bullet_Point). Aim point
## comes from the camera (crosshair) so hip-fire has natural bore-offset.
## Returns { origin, direction, aim_point, range }.
func _resolve_muzzle_shot(ctx: Dictionary) -> Dictionary:
	var bullet_point: Marker3D = ctx["bullet_point"]
	var origin: Vector3 = bullet_point.global_position
	var aim_point: Vector3 = ctx.get("camera_collision", origin + Vector3.FORWARD)
	if ctx.has("aim_point"):
		aim_point = ctx["aim_point"]

	var to_aim := aim_point - origin
	var direction: Vector3
	if to_aim.length_squared() > MIN_SHOT_DIR_LEN_SQ:
		direction = to_aim.normalized()
	else:
		# Degenerate (aim on muzzle): fire along barrel forward (-Z of marker).
		direction = -bullet_point.global_transform.basis.z.normalized()
		if direction.length_squared() < MIN_SHOT_DIR_LEN_SQ:
			direction = Vector3.FORWARD

	var shot_range: float = float(ctx.get("shot_range", 1000.0))
	return {
		"origin": origin,
		"direction": direction,
		"aim_point": aim_point,
		"range": maxf(shot_range, 1.0),
	}


func _hitscan_fire(ctx: Dictionary) -> void:
	var pic: PlayerInteractionComponent = ctx["player_interaction_component"]
	var item_ref: WieldableItemPD = ctx["item_ref"]
	var shot := _resolve_muzzle_shot(ctx)
	var origin: Vector3 = shot["origin"]
	var direction: Vector3 = shot["direction"]
	var end: Vector3 = origin + direction * (float(shot["range"]) + HITSCAN_OVERSHOOT)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	if pic and pic.player_rid:
		query.exclude = [pic.player_rid]
	query.collision_mask = COLLISION_MASK_DAMAGE
	var world: World3D = ctx["world_3d"]
	var result := world.direct_space_state.intersect_ray(query)
	if result:
		_deal_damage(result.collider, direction, result.position, item_ref)


func _projectile_fire(ctx: Dictionary) -> void:
	if bulletProjectileToLoad == null:
		return
	var item_ref: WieldableItemPD = ctx["item_ref"]
	var scene_tree: SceneTree = ctx["scene_tree"]
	var shot := _resolve_muzzle_shot(ctx)
	var origin: Vector3 = shot["origin"]
	var direction: Vector3 = shot["direction"]

	var proj := bulletProjectileToLoad.instantiate()
	scene_tree.current_scene.add_child(proj)
	# Spawn at muzzle; face flight direction so the mesh leaves the barrel.
	if direction.length_squared() > MIN_SHOT_DIR_LEN_SQ:
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		proj.global_transform = Transform3D(Basis.looking_at(direction, up), origin)
	else:
		proj.global_position = origin
	if "damage_amount" in proj:
		proj.damage_amount = item_ref.get_effective_damage()
	if proj is RigidBody3D:
		(proj as RigidBody3D).linear_velocity = direction * float(weaponVelocity)
	elif proj.has_method("set_linear_velocity"):
		proj.set_linear_velocity(direction * weaponVelocity)
	if "Direction" in proj:
		proj.Direction = direction

static func _deal_damage(collider: Node, direction: Vector3, hit_position: Vector3, item_ref: WieldableItemPD) -> void:
	if collider.has_signal("damage_received"):
		collider.damage_received.emit(item_ref.get_effective_damage(), direction, hit_position)
