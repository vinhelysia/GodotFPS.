class_name NPCLootComponent extends LootComponent

## Death-drop override for HostileNPCs with a loadout: spawns a CorpseContainer
## and hands it the NPC's OWN equipment/pockets instances by reference — no
## flattening, no duplication, no loot-table roll (pocket junk was already
## rolled at spawn by NPCLoadout). loot_table/amount_of_items_to_drop
## (inherited from LootComponent) are unused by this override; loot_bag_scene
## is reused as-is but should point at CorpseContainer.tscn, not a flat bag.
##
## _set_up_references() (base, connected via call_deferred in base _ready())
## already does `health_component_to_monitor.death.connect(_spawn_loot_container)`
## when spawning_logic == SPAWN_CONTAINER — GDScript resolves that to THIS
## override automatically, so no _ready()/_set_up_references() override is
## needed here.


func _get_configuration_warnings() -> PackedStringArray:
	# Base LootComponent requires loot_table; this override doesn't use one.
	return PackedStringArray()


func _spawn_loot_container() -> void:
	if not enabled:
		return

	var npc := get_parent() as HostileNPC
	if npc == null or npc.equipment == null:
		# No loadout was ever applied (legacy Scav without one) — nothing
		# real to drop. Deliberately not falling back to a loot-table roll:
		# that would silently reintroduce the old random-loot behavior for
		# an unmigrated NPC instead of making the missing setup visible.
		CogitoGlobals.debug_log(debug_prints, "NPCLootComponent", "No equipment/pockets on " + str(get_parent()) + " — nothing to drop (no loadout assigned).")
		return

	# Sync BEFORE handover: the corpse gets a live reference to the same
	# WieldableItemPD, so this write is visible there too, but doing it here
	# (not inside CorpseContainer) keeps "how ammo state is derived" a single
	# NPC-side concern.
	_sync_weapon_ammo(npc)

	var corpse := loot_bag_scene.instantiate() as CorpseContainer
	if corpse == null:
		push_error("NPCLootComponent: loot_bag_scene must be a CorpseContainer scene (got " + str(loot_bag_scene) + ").")
		return

	corpse.equipment = npc.equipment
	corpse.pockets = npc.pockets
	corpse.display_name = "Dead " + (npc.display_name if npc.display_name != "" else npc.cogito_name)
	corpse.text_when_closed = "Loot " + corpse.display_name
	corpse.text_when_open = "Loot " + corpse.display_name
	# Exact death position/rotation (no offset) — matches where CogitoHealthAttribute's
	# spawn_on_death spawns the ragdoll, so CorpseContainer._find_ragdoll_skeleton()'s
	# nearest-match search reliably finds this NPC's own ragdoll and not another one.
	corpse.position = get_parent().global_position
	corpse.rotation = get_parent().global_rotation
	get_tree().current_scene.call_deferred("add_child", corpse)

	CogitoGlobals.debug_log(debug_prints, "NPCLootComponent", "Spawned Corpse Container: " + str(corpse) + " at these coordinates: " + str(corpse.position))


## Writes the blackboard's real remaining magazine count into the dead NPC's
## weapon so the looted gun shows exactly the rounds it died with. Also builds
## a coherent firearm_mechanical_state — without it, equip can restore a stale
## spawn-time dict and disagree with charge_current.
func _sync_weapon_ammo(npc: HostileNPC) -> void:
	if npc.equipped_wieldable == null:
		return
	var bt: Node = npc.get_node_or_null("BTPlayer")
	if bt == null or bt.blackboard == null:
		return
	var current_ammo: int = int(bt.blackboard.get_var(&"ammo", int(npc.equipped_wieldable.get_effective_charge_max())))
	npc.equipped_wieldable.charge_current = float(current_ammo)
	# Prefer a real chamber+mag split when the weapon has been equipped before;
	# otherwise reconstruct from total so the next player equip is consistent.
	var mech := FirearmMechanicalState.new()
	var mag := npc.equipped_wieldable.get_magazine()
	var mag_cap: int = mag.magazine_capacity if mag else 0
	mech.configure({
		"magazine_capacity": mag_cap,
		"chamber_capacity": npc.equipped_wieldable.chamber_capacity(),
		"auto_chambers_on_empty_reload": true,
		"locks_open_on_empty": false,
	})
	mech.reconstruct_from_total(current_ammo)
	npc.equipped_wieldable.set_firearm_mechanical_state(mech.to_save_dict())
