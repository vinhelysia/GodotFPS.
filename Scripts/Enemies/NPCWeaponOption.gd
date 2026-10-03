extends Resource
class_name NPCWeaponOption

## One weapon choice inside an NPCLoadout's weapon_options. Pairing is
## explicit because WieldableItemPD does not reference its Weapon_Resource
## (that link only exists on the equipment slot / HostileNPC side).

@export var wieldable: WieldableItemPD
@export var weapon_data: Weapon_Resource
## Ammo item stacked into pockets as spare magazines (see
## NPCLoadout.spare_magazines_min/max). Should match wieldable.ammo_item_name.
@export var ammo_item: AmmoItemPD
## Relative pick weight when NPCLoadout.roll() picks a weapon. Weights are
## relative to each other, not required to sum to 1.
@export var weight: float = 1.0
## Attachments that may roll onto this weapon at spawn (each rolled
## independently at attachment_chance; first winner per slot type).
@export var attachment_options: Array[AttachmentItemPD] = []
@export_range(0.0, 1.0, 0.05) var attachment_chance: float = 0.25
