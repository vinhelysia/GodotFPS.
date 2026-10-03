extends CogitoNPC
class_name HostileNPC

## Shared base for combat-capable NPCs (Scav, PMC, Raider, etc.).
## Skill "personality" (accuracy, alertness, vision/hearing) lives on
## `ai_profile`; weapon stats (damage, fire rate, magazine size) come from
## `equipped_wieldable` / `equipped_weapon_data` — the SAME resources the
## player's real weapons use. WHO this NPC is and who it's hostile/neutral/
## friendly towards lives on `faction` (see Faction.gd) — disposition is
## looked up against `player_faction`, the same generic lookup future
## NPC-vs-NPC combat will use. Adding a new faction archetype is just a new
## Faction .tres (+ optionally a new AIProfile/weapon) — no script changes.

@export var ai_profile: AIProfile
## Provides wieldable_damage / wieldable_range / charge_max (magazine size).
## If `loadout` is assigned, this gets OVERWRITTEN in _ready() by the rolled
## weapon (a per-instance duplicate) — leave unset when using a loadout.
@export var equipped_wieldable: WieldableItemPD
## Provides get_fire_cooldown() / get_fire_mode() (ballistics config).
## Same overwrite rule as equipped_wieldable when `loadout` is assigned.
@export var equipped_weapon_data: Weapon_Resource
## Who this NPC is. Determines hostility via faction.get_disposition_towards().
@export var faction: Faction
## Which Faction resource represents the player. Same .tres assigned across
## all NPCs — kept per-instance (not a singleton) so this stays simple and
## doesn't require touching CogitoPlayer.
@export var player_faction: Faction
## Optional spawn kit: rolls a weapon + gear + reserve ammo + pocket loot at
## _ready() into `equipment`/`pockets` below. Unset = legacy behavior — this
## NPC just uses whatever equipped_wieldable/equipped_weapon_data are set to
## in the editor, exactly as before this system existed.
@export var loadout: NPCLoadout
@export var debug_loadout: bool = false

@export_group("Weapon visual")
## Skeleton bone the weapon model rides. Empty = this NPC shows no weapon.
@export var weapon_bone: StringName = &"DEF-hand.R"
## Weapon pose in that bone's space, applied ON TOP of the model's own transform.
## There is no geometric invariant to derive this from the way an optic rail has
## one — set it by eye in the editor with a scav selected.
@export var weapon_offset: Transform3D = Transform3D.IDENTITY

@onready var bt_player: Node = $BTPlayer
## Live character model (Skeleton3D + Mannequin mesh + alert indicator).
## Hidden on death — the visible corpse becomes the ragdoll that
## CogitoHealthAttribute's spawn_on_death already spawns separately (see
## mannequin_ragdoll.tscn), not this frozen standing rig.
@onready var rig: Node3D = $Rig

## Timestamp (Time.get_ticks_msec()/1000.0) of the last time this NPC took
## damage. ScavPerception polls this (comparing against its own
## last-processed copy) to react to being shot even from outside FOV/hearing
## range, without HostileNPC touching the blackboard itself — handing the
## event to the sensor "via a variable", keeping perception the sole
## blackboard writer.
var last_hit_time: float = -999.0

## Only populated when `loadout` is assigned (see _apply_loadout()). Reused
## as-is (CogitoEquipment is owner-agnostic: equip()/unequip()/get_equipped()
## don't care whether the owner is the player or an NPC).
var equipment: CogitoEquipment
## Plain 4x2 grid, NOT PocketInventory — see _apply_loadout()'s comment for
## why the player-specific PocketInventory isn't reused here.
var pockets: CogitoInventory

## Set by CogitoSceneManager when restoring a saved Persist node. When true,
## skip loadout re-roll and keep equipment/pockets/ammo from the save blob.
var kit_from_save: bool = false
## Mag rounds in the BT blackboard at save time (-1 = unset / use full mag).
var saved_ammo: int = -1
## Health snapshot for save/load (-1 = old save / not restored — keep authored).
var health_current: float = -1.0
var health_max: float = -1.0

var _loadout_rng := RandomNumberGenerator.new()
var _weapon_visual: Node3D


func _enter_tree() -> void:
	# Parent enters before children. Disable Cogito NPC_State_Machine *before*
	# its _enter_tree → setup() → deferred start_state (idle→patrol). LimboAI
	# BTPlayer is the sole AI authority for HostileNPC / Scav.
	_disable_legacy_state_machine()


func _disable_legacy_state_machine() -> void:
	var sm: Node = get_node_or_null("NPC_State_Machine")
	if sm == null:
		return
	# ai_enabled gates setup start + goto/restart (see npc_state_machine.gd).
	sm.set("ai_enabled", false)
	sm.set("start_state", "")
	sm.set("current", "")
	sm.process_mode = Node.PROCESS_MODE_DISABLED


func _ready() -> void:
	super._ready()
	# Belt-and-suspenders if SM was re-enabled by a tool/scene override after enter.
	_disable_legacy_state_machine()
	# Lets mannequin_ragdoll.tscn except live NPCs from its physical bones'
	# collisions (both default to layer 1, same as Environment — see that
	# scene's _except_dynamic_actors()) without a dedicated physics layer.
	add_to_group("hostile_npc")
	var health := get_node_or_null("CogitoHealthAttribute")
	if health:
		health.death.connect(_on_death)
	# damage_received(damage_value, bullet_direction, bullet_position) — 3 args,
	# matching Weapon_Resource._deal_damage() (the player's shared hitscan/
	# damage code) and HitboxComponent.damage(), the two other places that
	# receive this signal.
	damage_received.connect(_on_damage_received)

	# Loadout is deferred so CogitoSceneManager can inject saved kit props
	# (equipment/pockets/kit_from_save/saved_ammo) after add_child/_ready and
	# before this runs. Rolling here would re-roll kits on every load and the
	# deferred pocket-loot roll would stack junk on top of restored pockets.
	call_deferred("_setup_loadout_and_ammo")


## Fresh spawn: roll loadout. Scene restore: keep saved kit, seed saved ammo.
func _setup_loadout_and_ammo() -> void:
	if kit_from_save:
		_apply_saved_kit()
		_apply_weapon_visual()
		return

	if loadout:
		_loadout_rng.randomize()
		_apply_loadout()
	else:
		# Loud on purpose. `loadout` also comes back null when its .tres failed to
		# PARSE (one dead ext_resource anywhere in the chain kills the whole
		# resource), and skipping quietly leaves `equipment`/`pockets` null — the
		# NPC fights fine but its corpse carries nothing, so looting silently does
		# nothing. That reads as a loot bug, not a missing-asset bug.
		push_error("HostileNPC (%s): no loadout resource — this NPC will have no equipment, no pockets and NOTHING TO LOOT. Check the output above for a failed .tres/.tscn load in the loadout's resource chain." % name)

	_seed_blackboard_ammo(magazine_size())
	_apply_weapon_visual()


## Hangs the equipped weapon's third-person model off the NPC's hand bone, with
## its muzzle attachments fitted, so a suppressed scav LOOKS suppressed.
##
## Uses WieldableItemPD.world_model — never drop_scene, which is the pickup
## RigidBody3D (collision + interaction; parenting that to a character adds a
## physics body and an interactable to the NPC).
func _apply_weapon_visual() -> void:
	if is_instance_valid(_weapon_visual):
		_weapon_visual.queue_free()
	_weapon_visual = null
	if equipped_wieldable == null or equipped_wieldable.world_model == null or weapon_bone == &"":
		return
	var mount := _weapon_bone_attachment()
	if mount == null:
		return
	_weapon_visual = equipped_wieldable.world_model.instantiate() as Node3D
	if _weapon_visual == null:
		return
	mount.add_child(_weapon_visual)
	# Multiply, don't overwrite: the drop models carry their own scale/rotation.
	_weapon_visual.transform = weapon_offset * _weapon_visual.transform
	_fit_weapon_visual_muzzle()


## Creates the weapon's BoneAttachment3D once, then reuses it.
func _weapon_bone_attachment() -> BoneAttachment3D:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var existing := skeleton.get_node_or_null("WeaponMount") as BoneAttachment3D
	if existing != null:
		return existing
	if skeleton.find_bone(String(weapon_bone)) < 0:
		push_warning("HostileNPC (%s): skeleton has no bone '%s' — no weapon visual." % [name, weapon_bone])
		return null
	var mount := BoneAttachment3D.new()
	mount.name = "WeaponMount"
	skeleton.add_child(mount)
	mount.bone_name = String(weapon_bone)  # resolves bone_idx, needs the parent
	return mount


## Muzzle devices only. The third-person models carry a Bullet_Point but no
## optic rail, and at NPC viewing distance a suppressor is the one silhouette
## that reads. Deliberately a small copy of cogito_weapon's version rather than
## a shared helper — the two mount onto different node layouts.
## ponytail: the built-in muzzle device is NOT hidden underneath (cogito_weapon
## does that via muzzle_hide_nodes). Give the third-person model the same export
## if the overlap ever shows at NPC range.
func _fit_weapon_visual_muzzle() -> void:
	var bullet_point := _weapon_visual.find_child("Bullet_Point", true, false) as Node3D
	if bullet_point == null:
		return
	for item in equipped_wieldable.get_attached_items():
		if item.attachment_slot != AttachmentItemPD.AttachmentSlot.MUZZLE or item.mount_scene == null:
			continue
		var node := item.mount_scene.instantiate() as Node3D
		if node == null:
			continue
		bullet_point.add_child(node)
		node.transform = Transform3D.IDENTITY


func _apply_saved_kit() -> void:
	if pockets:
		pockets.owner = self
	# Prefer the flat equipped_* props from the save blob; fall back to whatever
	# is still sitting in the equipment slots (older saves / partial restores).
	if equipped_wieldable == null and equipment != null:
		for slot_id: StringName in [&"primary_1", &"primary_2", &"holster", &"melee"]:
			var slot_data: InventorySlotPD = equipment.get_equipped(slot_id)
			if slot_data and slot_data.inventory_item is WieldableItemPD:
				equipped_wieldable = slot_data.inventory_item as WieldableItemPD
				break
	var ammo: int = saved_ammo if saved_ammo >= 0 else magazine_size()
	_seed_blackboard_ammo(ammo)
	kit_from_save = false


func _seed_blackboard_ammo(ammo: int) -> void:
	if bt_player and bt_player.blackboard:
		bt_player.blackboard.set_var(&"ammo", ammo)


## Persist transform/patrol path + live kit. Never restore NPC_State_Machine onto a BT scav.
func set_state() -> void:
	find_cogito_properties()
	load_patrol_points()
	# Do not call npc_state_machine.goto(saved_enemy_state).
	_disable_legacy_state_machine()
	# Belt-and-suspenders: if deferred setup already ran, this is a no-op for
	# kit_from_save=false; if it hasn't, apply saved kit here.
	if kit_from_save:
		_apply_saved_kit()
	_apply_saved_health()


func _apply_saved_health() -> void:
	# Old saves omit health keys → vars stay -1 → keep authored defaults.
	if health_current < 0.0 or health_max <= 0.0:
		return
	var health := get_node_or_null("CogitoHealthAttribute") as CogitoAttribute
	if health:
		health.set_attribute(health_current, health_max)


func save() -> Dictionary:
	if patrol_path:
		patrol_path_nodepath = patrol_path.get_path()
	# saved_enemy_state left empty: load must not revive legacy SM on this node.
	saved_enemy_state = ""
	var ammo_now: int = magazine_size()
	if bt_player and bt_player.blackboard:
		ammo_now = int(bt_player.blackboard.get_var(&"ammo", ammo_now))
	var health := get_node_or_null("CogitoHealthAttribute") as CogitoAttribute
	var h_cur: float = health.value_current if health else -1.0
	var h_max: float = health.value_max if health else -1.0
	return {
		"filename": get_scene_file_path(),
		"parent": get_parent().get_path(),
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_x": rotation.x,
		"rot_y": rotation.y,
		"rot_z": rotation.z,
		"patrol_path_nodepath": patrol_path_nodepath,
		"saved_enemy_state": "",
		"equipment": equipment,
		"pockets": pockets,
		"equipped_wieldable": equipped_wieldable,
		"equipped_weapon_data": equipped_weapon_data,
		"saved_ammo": ammo_now,
		"kit_from_save": true,
		"health_current": h_cur,
		"health_max": h_max,
	}


## Rolls `loadout` and wires the result into equipped_wieldable/
## equipped_weapon_data (the flat vars the BT tasks actually read),
## `equipment` (weapon + gear, slotted like the player's), and `pockets`
## (spare ammo + rolled junk).
##
## pockets is a plain CogitoInventory grid, not PocketInventory: PocketInventory's
## can_pick_up_slot_data()/pick_up_slot_data() auto-equip routing IS genuinely
## owner-agnostic (reads owner.equipment generically) and would work here too,
## but it's pure unused surface for this use case since weapon/gear are equipped
## directly via equipment.equip() below, never through pick_up_slot_data(). Its
## use_slot_data() sentinel-index path, however, calls
## slot_data.inventory_item.use(owner) for equipped items, which for a
## WieldableItemPD reaches into owner.player_interaction_component — an NPC has
## no such property, so that specific path would break if anything ever called
## it on an NPC's pockets. Nothing currently does (no NPC pocket-viewing UI
## exists — see npc_loot_component.gd's death-drop container, which is a
## separate non-grid inventory instead), but a plain grid carries none of that
## latent risk and needs none of PocketInventory's player-UI-oriented behavior.
func _apply_loadout() -> void:
	equipment = CogitoEquipment.new()
	pockets = CogitoInventory.new()
	pockets.grid = true
	pockets.inventory_size = Vector2i(4, 2)
	pockets.inventory_slots.resize(8)
	pockets.owner = self

	var result := loadout.roll(_loadout_rng)
	var weapon_option := result.get("weapon_option") as NPCWeaponOption
	var spare_magazines: int = result.get("spare_magazines", 0)

	if weapon_option and weapon_option.wieldable:
		var duped_wieldable: WieldableItemPD = pockets._duplicate_wieldable_item_for_inventory(weapon_option.wieldable)
		equipped_wieldable = duped_wieldable
		equipped_weapon_data = weapon_option.weapon_data

		var rolled_attachments: Array = result.get("attachments", [])
		# Rounds live in the magazine, so fitting a rolled one takes the default
		# magazine off — and with it the loadout's ammo. A rolled magazine has no
		# recorded contents of its own (loaded_rounds < 0), so put the rounds back
		# afterwards or every scav that rolls an RPK mag spawns with a dry gun.
		var magazine_rounds_before: int = duped_wieldable.get_magazine_rounds()
		for attachment: AttachmentItemPD in rolled_attachments:
			duped_wieldable.try_attach(attachment)
		var fitted_magazine: AttachmentItemPD = duped_wieldable.get_magazine()
		if fitted_magazine != null:
			duped_wieldable.set_magazine_rounds(
					mini(magazine_rounds_before, fitted_magazine.magazine_capacity))

		var weapon_slot_data := InventorySlotPD.new()
		weapon_slot_data.inventory_item = duped_wieldable
		weapon_slot_data.quantity = 1
		equipment.equip(_weapon_slot_to_equipment_slot(duped_wieldable.weapon_slot), weapon_slot_data)

		if spare_magazines > 0 and weapon_option.ammo_item:
			var ammo_slot_data := InventorySlotPD.new()
			ammo_slot_data.inventory_item = weapon_option.ammo_item
			ammo_slot_data.quantity = spare_magazines * int(duped_wieldable.get_effective_charge_max())
			pockets.pick_up_slot_data(ammo_slot_data)

	var gear_items: Array = result.get("gear_items", [])
	for gear_item: GearItemPD in gear_items:
		var gear_equipment_slot := _gear_slot_to_equipment_slot(gear_item.gear_slot)
		if gear_equipment_slot == &"":
			continue
		var gear_slot_data := InventorySlotPD.new()
		gear_slot_data.inventory_item = gear_item
		gear_slot_data.quantity = 1
		equipment.equip(gear_equipment_slot, gear_slot_data)

	var pocket_loot_rolls: int = result.get("pocket_loot_rolls", 0)
	if pocket_loot_rolls > 0 and loadout.pocket_loot_table:
		# LootGenerator needs to be added to the tree (get_tree() inside its
		# own _set_up_references()) — but _ready() runs while the scene tree
		# is still mid-setup for this whole subtree ("Parent node is busy
		# setting up children"), so a synchronous add_child() here fails.
		# Defer the whole roll to run once that setup finishes.
		_roll_pocket_loot.call_deferred(pocket_loot_rolls)

	if debug_loadout:
		var gear_names: Array = []
		for gear_item: GearItemPD in gear_items:
			gear_names.append(gear_item.name)
		print("[%s] Rolled loadout: weapon=%s gear=%s spare_mags=%d pocket_loot_rolls=%d" % [
			name,
			weapon_option.wieldable.name if weapon_option and weapon_option.wieldable else "none",
			gear_names,
			spare_magazines,
			pocket_loot_rolls,
		])


## Deferred half of the pocket-loot roll (see _apply_loadout()) — needs the
## NPC to actually be inside the tree, which isn't guaranteed yet at _ready()
## time.
func _roll_pocket_loot(pocket_loot_rolls: int) -> void:
	var lootgen := LootGenerator.new()
	get_tree().current_scene.add_child(lootgen)
	var rolled_loot: Array[LootDropEntry] = lootgen.generate(loadout.pocket_loot_table, pocket_loot_rolls)
	lootgen.call_deferred("queue_free")
	for entry in rolled_loot:
		if entry.inventory_item == null:
			continue
		var loot_slot_data := InventorySlotPD.new()
		loot_slot_data.inventory_item = entry.inventory_item
		loot_slot_data.quantity = randi_range(entry.quantity_min, entry.quantity_max)
		pockets.pick_up_slot_data(loot_slot_data)


## True if this NPC has at least 1 round of reserve ammo for its equipped
## weapon in pockets. Peek-only, doesn't consume anything — bt_reload.gd
## checks this BEFORE starting the reload wait so a doomed reload never
## plays out. NPCs without pockets (no loadout assigned) always report
## false here, but that's fine: bt_reload.gd only enforces finite ammo when
## pockets exist, so legacy NPCs never call this in the first place.
func has_reserve_ammo() -> bool:
	if pockets == null or equipped_wieldable == null:
		return false
	var ammo_name: String = equipped_wieldable.ammo_item_name
	for slot: InventorySlotPD in pockets.inventory_slots:
		if slot and slot.inventory_item and slot.inventory_item.name == ammo_name and slot.quantity > 0:
			return true
	return false


## Draws up to `rounds_needed` rounds from this NPC's pockets (matching
## equipped_wieldable.ammo_item_name), shrinking/removing the ammo stack via
## the inventory's own removal path (remove_slot_data — never hand-nulling a
## slot). Returns rounds actually taken, which may be less than requested
## (partial reload) or 0 (no pockets, or reserve ran out between the
## has_reserve_ammo() check and this call — nothing currently causes that,
## but the caller shouldn't assume it can't happen).
func take_reserve_ammo(rounds_needed: int) -> int:
	if pockets == null or equipped_wieldable == null or rounds_needed <= 0:
		return 0

	var ammo_name: String = equipped_wieldable.ammo_item_name
	var taken: int = 0
	for slot: InventorySlotPD in pockets.inventory_slots:
		if taken >= rounds_needed:
			break
		if slot == null or slot.inventory_item == null:
			continue
		if slot.inventory_item.name != ammo_name:
			continue
		var take_now: int = mini(rounds_needed - taken, slot.quantity)
		slot.quantity -= take_now
		taken += take_now
		if slot.quantity <= 0:
			pockets.remove_slot_data(slot)

	return taken


func _weapon_slot_to_equipment_slot(weapon_slot: int) -> StringName:
	match weapon_slot:
		0: return &"primary_1" # WieldableItemPD.WeaponSlot.PRIMARY
		1: return &"holster"   # WeaponSlot.HOLSTER
		2: return &"melee"     # WeaponSlot.MELEE
	return &"primary_1"


func _gear_slot_to_equipment_slot(gear_slot: int) -> StringName:
	match gear_slot:
		0: return &"body_armor" # GearItemPD.GearSlot.BODY_ARMOR
		1: return &"helmet"     # GearSlot.HELMET
		2: return &"eyewear"    # GearSlot.EYEWEAR
		3: return &"face_cover" # GearSlot.FACE_COVER
		4: return &"earpiece"   # GearSlot.EARPIECE
	return &""


func _on_damage_received(_damage_value: float, _direction: Vector3, _hit_position: Vector3) -> void:
	last_hit_time = Time.get_ticks_msec() / 1000.0


func _on_death() -> void:
	if is_instance_valid(bt_player):
		bt_player.active = false
	# The corpse owns persistence and loot after this signal. Keeping the source
	# NPC alive would leave active AI and allow save/load to recreate it.
	remove_from_group(&"Persist")
	remove_from_group(&"hostile_npc")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO

	var perception := get_node_or_null("Perception")
	if perception:
		if perception.has_method(&"shutdown"):
			perception.call(&"shutdown")
		else:
			perception.remove_from_group(&"npc_perception")
			perception.set_process(false)
			perception.set_physics_process(false)

	# Disable every child process immediately; NPCLootComponent has already
	# received the same death signal and hands the resources to the corpse before
	# this deferred free executes.
	process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(rig):
		rig.hide()
	call_deferred("queue_free")

## Magazine size for ammo bookkeeping. Falls back to a sane default if no
## weapon item is assigned yet (e.g. mid-setup in the editor).
func magazine_size() -> int:
	if equipped_wieldable:
		return int(equipped_wieldable.get_effective_charge_max())
	return 5


## Damage per hit. Falls back to a sane default if unassigned.
## Attachment-adjusted, same as the player's shot path — magazine_size() and
## gunshot_loudness() already read the effective values; this was the odd one out.
func weapon_damage() -> float:
	if equipped_wieldable:
		return equipped_wieldable.get_effective_damage()
	return 8.0


## Seconds between shots, adjusted by this AI's trigger skill (ai_profile).
func effective_fire_cooldown() -> float:
	var base_cooldown: float = equipped_weapon_data.get_fire_cooldown() if equipped_weapon_data else 0.8
	var skill: float = ai_profile.fire_rate_skill if ai_profile else 1.0
	return base_cooldown / maxf(skill, 0.01)


## How loud this NPC's shots are to other NPCs' hearing. Comes from the equipped
## weapon (same field the player's guns use) so a suppressed scav is quieter.
## Matches player path: base loudness * attachment loudness_multiplier.
func gunshot_loudness() -> float:
	var base: float = equipped_weapon_data.gunshot_loudness if equipped_weapon_data else 80.0
	if equipped_wieldable:
		return base * equipped_wieldable.attachment_multiplier(&"loudness_multiplier")
	return base


## No faction assigned = default to hostile (safe fallback so an unconfigured
## NPC still behaves like the original always-hostile Scav).
func is_hostile_to_player() -> bool:
	if faction == null:
		return true
	return faction.is_hostile_towards(player_faction)
