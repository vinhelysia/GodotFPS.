extends InventoryItemPD
class_name AttachmentItemPD

# Append-only: the int values are the keys of WieldableItemPD.attachments and
# ride save files. Never reorder or insert.
enum AttachmentSlot { OPTIC, MUZZLE, GRIP, STOCK, MAGAZINE }

@export var attachment_slot: AttachmentSlot

@export_group("Stat Modifiers")
@export var recoil_multiplier: float = 1.0
@export var ads_time_multiplier: float = 1.0
## Scales the gunshot loudness heard by NPC perception (suppressor < 1).
@export var loudness_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var range_multiplier: float = 1.0

@export_group("Optic")
## Camera FOV while ADS. -1 = keep the weapon's own ads_fov.
@export var ads_fov_override: float = -1.0
## Added to the weapon's ads_position to line the eye up with this optic.
@export var ads_position_offset: Vector3 = Vector3.ZERO

@export_group("Muzzle")
@export var suppresses_muzzle_flash: bool = false

@export_group("Magazine")
## Rounds this magazine feeds, NOT counting the chamber (AK 30-rnd mag = 30).
## A weapon with no magazine attached can only be hand-loaded one round.
@export var magazine_capacity: int = 0
## The ammo this magazine is chambered for. Must match the weapon's
## ammo_item_name or the magazine won't seat. Also used to return loose rounds
## to the pockets when the magazine is stripped.
@export var magazine_ammo_item: AmmoItemPD
## Rounds sitting in THIS magazine while it is off a weapon. -1 = no recorded
## contents (a freshly authored .tres, a world spawn, an NPC loadout roll), which
## fits onto a weapon without injecting or removing any ammo. A magazine that has
## been detached always carries a real count >= 0, so its rounds ride with it.
## Only meaningful on a per-instance copy — see duplicate_instance().
@export var loaded_rounds: int = -1
## Where this instance was duplicated from. A duplicated Resource has an empty
## resource_path, and WieldableItemPD.attachments stores paths, so without this a
## fitted magazine would be stored as "" and vanish. See get_source_path().
@export var origin_path: String = ""
## Swapped onto the weapon's built-in magazine MeshInstance3D nodes (see
## cogito_weapon.magazine_mesh_nodes). Null = keep the weapon's own mesh, which
## is what the default magazine wants.
## ponytail: assumes the replacement shares the original's pivot and rough
## silhouette. A 75-round drum will need its own reload animation pass.
@export var magazine_mesh: Mesh

@export_group("Mounting")
## Scene spawned on the weapon when attached. Null = data-only stat mod (grip/stock v1).
@export var mount_scene: PackedScene
## WieldableItemPD.name entries this fits ("AK-47", "M700"...). Empty = fits every weapon.
@export var compatible_weapons: Array[String] = []


## The .tres this item is (or was copied from). Duplicates lose resource_path,
## and WieldableItemPD.attachments keys off the path, so always store this.
##
## origin_path wins on purpose: saving the inventory serializes a duplicate
## INLINE and Godot then stamps it with a sub-resource path into the save file
## ("user://save.tres::Resource_0knfi"). Trusting resource_path there would make
## every magazine unattachable after a load — the path guard rejects it.
func get_source_path() -> String:
	return origin_path if not origin_path.is_empty() else resource_path


## Per-instance copy. Magazines need one because their round count is instance
## state, while load() hands out one shared resource per .tres.
func duplicate_instance() -> AttachmentItemPD:
	var copy := duplicate(false) as AttachmentItemPD
	copy.origin_path = get_source_path()
	return copy


func fits(weapon_item: WieldableItemPD) -> bool:
	if weapon_item == null:
		return false
	if not compatible_weapons.is_empty() and not weapon_item.name in compatible_weapons:
		return false
	# Magazines are caliber-specific on top of the platform check.
	if attachment_slot == AttachmentSlot.MAGAZINE and magazine_ammo_item != null:
		return magazine_ammo_item.name == weapon_item.ammo_item_name
	return true
