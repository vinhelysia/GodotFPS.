class_name CorpseContainer extends CogitoContainer

## Tarkov-style corpse loot node. Holds the SAME CogitoEquipment/CogitoInventory
## instances the dead NPC actually fought with (handed over by reference from
## NPCLootComponent at death, BEFORE this node enters the tree) — no
## flattening, no duplication.
##
## `pockets`' setter aliases the inherited `inventory_data` (CogitoContainer)
## to the same instance, so every existing call site that expects
## external_inventory_owner.inventory_data (take-all, inventory_button_press
## connect, CogitoContainer._ready()'s own apply_initial_inventory() call)
## keeps working with zero changes and zero null checks — it's just reading
## the NPC's real pockets instead of a container-local one.
##
## Follows the loot_chest.tscn / LootDropContainer interactable pattern
## (interact -> toggle_inventory signal -> player HUD -> inventory_interface
## .set_external_inventory), but only the pieces actually needed here — no
## despawn timers/logic (out of scope for a corpse).

@export var equipment: CogitoEquipment
@export var pockets: CogitoInventory:
	set(value):
		pockets = value
		inventory_data = value

## Group tag set on mannequin_ragdoll.tscn's root — see _ensure_ragdoll().
const RAGDOLL_GROUP := "corpse_ragdoll"
const RAGDOLL_SCENE := preload("res://addons/cogito/CogitoNPC/mannequin_ragdoll.tscn")
## Topmost PhysicalBone3D in the rig: there is no "DEF-head" physical bone (the
## skeleton has that bone, the simulator does not), so the head volume rides the neck.
const BONE_HEAD := "DEF-neck"
const BONE_TORSO := "DEF-spine.002"
const BONE_PELVIS := "DEF-hips"
## Bone tracking (Task 2) only runs within this range of the player — matches
## the loot-anywhere-on-body requirement without paying a per-frame cost for
## every corpse in the level.
const TRACK_RADIUS := 5.0
## Adopt a death-spawned ragdoll only if it is still this close (same death spot).
const ADOPT_RADIUS := 2.0

@onready var head_shape: CollisionShape3D = $HeadShape
@onready var torso_shape: CollisionShape3D = $TorsoShape
@onready var pelvis_shape: CollisionShape3D = $PelvisShape

var _player: Node3D
var _bone_head: PhysicalBone3D
var _bone_torso: PhysicalBone3D
var _bone_pelvis: PhysicalBone3D
var _owned_ragdoll: Node3D


func _ready() -> void:
	# Skip CogitoContainer._ready(): apply_initial_inventory() re-inits an empty
	# grid and would wipe save-injected pockets before set_state can resync them.
	# Do only the interactable/group wiring the loot UI actually needs.
	add_to_group("external_inventory")
	add_to_group("interactable")
	add_to_group("loot_bag")
	add_to_group("Persist")
	interaction_nodes = find_children("", "InteractionComponent", true)
	interaction_text = tr(text_when_closed)
	object_state_updated.emit(interaction_text)
	call_deferred("_set_up_references")


## Deferred so this doesn't run while the scene tree is still mid-setup for
## whatever spawned this corpse. Ragdoll is claimed/spawned even if Player is
## missing; HUD connect is separate and skipped until a Player exists.
func _set_up_references() -> void:
	_ensure_ragdoll()
	_try_connect_hud()


func _try_connect_hud() -> void:
	_player = get_tree().get_first_node_in_group("Player")
	if _player == null:
		return
	# Untyped find: avoid hard dependency on CogitoPlayerHudManager global class
	# during headless suite load order.
	var player_hud: Node = _player.find_child("Player_HUD", true, true)
	if player_hud == null or not player_hud.has_method("toggle_inventory_interface"):
		return
	var cb := Callable(player_hud, "toggle_inventory_interface")
	if not toggle_inventory.is_connected(cb):
		toggle_inventory.connect(cb)


## Own exactly one ragdoll under this corpse (auto-freed with the corpse).
## Prefer the unclaimed mannequin_ragdoll CogitoHealthAttribute already spawned
## at the death position; otherwise spawn a fresh one. PhysicalBone poses are
## never persisted — reload always rebinds / re-spawns.
func _ensure_ragdoll() -> void:
	if _owned_ragdoll != null and is_instance_valid(_owned_ragdoll):
		return

	var best: Node3D = null
	var best_dist := INF
	for ragdoll in get_tree().get_nodes_in_group(RAGDOLL_GROUP):
		if ragdoll.get_meta("claimed", false):
			continue
		if ragdoll.get_parent() == self:
			best = ragdoll as Node3D
			best_dist = 0.0
			break
		var dist: float = (ragdoll as Node3D).global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = ragdoll as Node3D

	if best != null and best_dist > ADOPT_RADIUS:
		best = null

	if best == null:
		best = RAGDOLL_SCENE.instantiate() as Node3D
		add_child(best)
		best.global_position = global_position
		best.global_rotation = global_rotation
	else:
		best.set_meta("claimed", true)
		if best.get_parent() != self:
			best.reparent(self, true)

	_owned_ragdoll = best
	_bind_ragdoll_bones(best)


func _bind_ragdoll_bones(ragdoll: Node3D) -> void:
	# Track the PhysicalBone3D nodes, NOT Skeleton3D.get_bone_global_pose(): a
	# PhysicalBoneSimulator3D drives the skin, but the skeleton's bone poses keep
	# reporting the *animated* (standing) pose. Tracking those left the three loot
	# volumes standing in an invisible column at the death spot while the body lay
	# on the floor a metre away — the only place an interaction ray still crossed
	# that column was the bottom sphere, so a corpse could only be looted by aiming
	# at its feet. The physical bones ARE the simulation, so they cannot drift.
	var simulator := ragdoll.get_node_or_null(
		"Rig/SkeletonRagdoll/PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	if simulator == null:
		push_warning("CorpseContainer (%s): ragdoll has no PhysicalBoneSimulator3D — loot volumes will not follow the corpse." % name)
		return

	_bone_head = null
	_bone_torso = null
	_bone_pelvis = null
	for child in simulator.get_children():
		var bone := child as PhysicalBone3D
		if bone == null:
			continue
		match bone.bone_name:
			BONE_HEAD:
				_bone_head = bone
			BONE_TORSO:
				_bone_torso = bone
			BONE_PELVIS:
				_bone_pelvis = bone

	if _bone_head == null or _bone_torso == null or _bone_pelvis == null:
		push_warning("CorpseContainer (%s): ragdoll is missing one of the tracked physical bones (%s / %s / %s) — that loot volume will not follow the corpse." % [
			name, BONE_HEAD, BONE_TORSO, BONE_PELVIS])


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > TRACK_RADIUS:
		return
	_track_bone(head_shape, _bone_head)
	_track_bone(torso_shape, _bone_torso)
	_track_bone(pelvis_shape, _bone_pelvis)


## Sphere volumes — position is all that matters, so don't drag the bone's rotation
## (or its scale) onto the shape.
func _track_bone(shape: CollisionShape3D, bone: PhysicalBone3D) -> void:
	if bone == null or not is_instance_valid(bone):
		return
	shape.global_position = bone.global_position


## CogitoContainer.save() (read-only base) has no idea `equipment` exists —
## its returned dict only carries what CogitoContainer itself knows about
## (inventory_data, display_name, transform, etc.), so without this override
## `equipment` would silently vanish on the next save/load cycle even though
## `pockets`/inventory_data survives fine (CogitoSceneState round-trips the
## WHOLE saved dict through Godot's own ResourceSaver/ResourceLoader, which
## natively handles nested Resource graphs like CogitoEquipment/
## InventorySlotPD/InventoryItemPD — the gap is purely "the base save()
## doesn't emit this key", not a serialization limitation). Overriding
## save() to add one extra key — not touching the save system itself — is
## the same pattern LootDropContainer.gd already uses for its own extra
## fields (start_time/end_time/time_left/initial_spawn).
## PhysicalBone poses are intentionally NOT saved.
func save() -> Dictionary:
	var node_data: Dictionary = super.save()
	node_data["equipment"] = equipment
	return node_data


## Called (deferred) by CogitoSceneManager.load_scene_state() after restoring
## this node's saved properties. That restore loop does
## new_object.set("inventory_data", ...) directly — bypassing the `pockets`
## setter above — so `pockets` itself would read null post-load even though
## inventory_data (the same data) is correctly restored. Re-sync it here.
## Also verifies the save() fix above actually worked: if `equipment` still
## comes back null (e.g. a save file written before this fix existed), this
## does NOT crash — it just logs once so the gap is visible instead of silent.
## Re-claims/spawns the owned ragdoll (poses not persisted) and retries HUD.
func set_state() -> void:
	super.set_state()
	pockets = inventory_data
	if equipment == null:
		push_warning("CorpseContainer (%s): 'equipment' came back null after a save/load cycle — this corpse's equipped weapon/gear did not survive (pockets should still be intact)." % name)
	_ensure_ragdoll()
	_try_connect_hud()
