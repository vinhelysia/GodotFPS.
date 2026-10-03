extends Resource
class_name NPCLoadout

## Rollable spawn kit for a HostileNPC: one weapon (weighted pick), independent
## gear pieces, spare-magazine reserve ammo, and a pocket-loot table rolled at
## SPAWN time (not on death — the NPC actually carries this loot, so death
## just drops what's already in its pockets; see npc_loot_component.gd).
##
## Create one .tres per archetype (e.g. scav_loadout.tres) and assign it to a
## HostileNPC's `loadout` export. No loadout assigned = the NPC keeps using
## its plain equipped_wieldable/equipped_weapon_data exports exactly as
## before — this resource is purely additive.

@export var weapon_options: Array[NPCWeaponOption] = []
@export var gear_options: Array[NPCGearOption] = []

@export_group("Reserve Ammo")
## Reserve = rolled mag count * the chosen weapon's charge_max, carried in
## pockets as one ammo stack.
@export var spare_magazines_min: int = 1
@export var spare_magazines_max: int = 3

@export_group("Pocket Loot")
## Junk rolled straight into pockets at spawn (replaces the old death-time
## loot table roll — the NPC now drops what it actually carried).
@export var pocket_loot_table: LootTable
@export var pocket_loot_rolls_min: int = 0
@export var pocket_loot_rolls_max: int = 2


## Rolls this loadout into a plain result Dictionary for the NPC to consume:
## {
##   "weapon_option": NPCWeaponOption or null,
##   "gear_items": Array[GearItemPD],
##   "attachments": Array[AttachmentItemPD],
##   "spare_magazines": int,
##   "pocket_loot_rolls": int,
## }
func roll(rng: RandomNumberGenerator) -> Dictionary:
	var weapon_option := _roll_weighted_weapon(rng)

	var attachments: Array[AttachmentItemPD] = []
	if weapon_option:
		var filled_attachment_slots: Dictionary = {}
		for attachment in weapon_option.attachment_options:
			if attachment == null or filled_attachment_slots.has(attachment.attachment_slot):
				continue
			if rng.randf() <= weapon_option.attachment_chance:
				attachments.append(attachment)
				filled_attachment_slots[attachment.attachment_slot] = true

	var gear_items: Array[GearItemPD] = []
	var filled_slots: Dictionary = {}
	for option in gear_options:
		if option == null or option.gear_item == null:
			continue
		if filled_slots.has(option.gear_item.gear_slot):
			continue
		if rng.randf() <= option.chance:
			gear_items.append(option.gear_item)
			filled_slots[option.gear_item.gear_slot] = true

	var spare_magazines: int = 0
	if weapon_option:
		spare_magazines = rng.randi_range(
			mini(spare_magazines_min, spare_magazines_max),
			maxi(spare_magazines_min, spare_magazines_max)
		)

	var pocket_loot_rolls: int = rng.randi_range(
		mini(pocket_loot_rolls_min, pocket_loot_rolls_max),
		maxi(pocket_loot_rolls_min, pocket_loot_rolls_max)
	)

	return {
		"weapon_option": weapon_option,
		"gear_items": gear_items,
		"attachments": attachments,
		"spare_magazines": spare_magazines,
		"pocket_loot_rolls": pocket_loot_rolls,
	}


func _roll_weighted_weapon(rng: RandomNumberGenerator) -> NPCWeaponOption:
	var total_weight: float = 0.0
	for option in weapon_options:
		if option:
			total_weight += maxf(option.weight, 0.0)
	if total_weight <= 0.0:
		return null

	var roll_point: float = rng.randf() * total_weight
	var accum: float = 0.0
	for option in weapon_options:
		if option == null:
			continue
		accum += maxf(option.weight, 0.0)
		if roll_point <= accum:
			return option
	return null
