extends Resource
class_name NPCGearOption

## One gear piece inside an NPCLoadout's gear_options. Independently rolled
## (not a weighted single-pick like weapons) — target equipment slot comes
## from gear_item.gear_slot, not from anything set here.

@export var gear_item: GearItemPD
## Independent chance [0,1] this piece is rolled in. If two options target
## the same gear_slot, only the first one rolled true wins (see
## NPCLoadout.roll()) — avoid this by not overlapping slots per loadout.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.4
