extends InventoryItemPD
class_name WieldableItemPD

# Signal that gets sent when the wiedlable charge changes. Currently used to update Slot UI
signal charge_changed()

enum WeaponSlot { PRIMARY, HOLSTER, MELEE }
@export var weapon_slot: WeaponSlot = WeaponSlot.PRIMARY

@export_group("Wieldable settings")
@export var wieldable_scene : PackedScene
## Icon that is displayed on the HUD when item is wielded. If NULL, the item icon will be used instead.
@export var wieldable_data_icon : Texture2D
## Square (1:1) icon used in the quickslot bar. If NULL, falls back to the default item icon.
@export var quickslot_icon : Texture2D
@export var wieldable_crosshair : Texture2D
## Check this if your wieldable doesn't use reload (for example melee weapons)
@export var no_reload : bool = false
## Message to display when wieldable is empty (no ammo in clip/no charge). Leave empty if you don't want to show any message.
@export var hint_on_empty: String
## The maximum charge of the item (this equals fully charged battery in a flashlight or magazine size in guns)
@export var charge_max : float
## Name of the item this item uses as Ammo. Needs to match exactly.
@export var ammo_item_name : String
## Current charge of item (aka how much is in the magazine).
@export var charge_current : float
## Used for weapons
@export var wieldable_range : float
## Used for weapons
@export var wieldable_damage : float
## Third-person model for whoever is holding this weapon — NPCs today. Distinct
## from wieldable_scene (the first-person rig, hidden until equipped) and from
## drop_scene (the pickup RigidBody3D, which carries collision + interaction and
## must never be parented to a character). Null = holder shows no weapon.
@export var world_model : PackedScene
@export var firearm_mechanical_state : Dictionary = {}
## Per-instance weapon attachments: int(AttachmentItemPD.AttachmentSlot) -> item resource path (String).
@export var attachments : Dictionary = {}

var wieldable_data_text : String

func use(target) -> bool:
	if target.is_in_group("external_inventory"):
		CogitoGlobals.debug_log(true,"WieldableItemPD.gd", "Can't use wieldable that is not in your inventory." )
		return false
		
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null:
		CogitoGlobals.debug_log(true,"WieldableItemPD.gd", "Bad target pass. Setting target to " + CogitoSceneManager._current_player_node.name )
		target = CogitoSceneManager._current_player_node

		
	player_interaction_component = target.player_interaction_component
	if player_interaction_component.carried_object != null:
		player_interaction_component.send_hint(null,"Can't equip item while carrying.")
		return false
	if is_being_wielded:
		CogitoGlobals.debug_log(true,"WieldableItemPD.gd", player_interaction_component.name + " is putting away wieldable " + name )
		put_away()
		return true
	else:
		CogitoGlobals.debug_log(true,"WieldableItemPD.gd", player_interaction_component.name + " is taking out wieldable " + name )
		take_out()
		return true


# Functions for WIELDABLES
func take_out():
	if player_interaction_component.is_changing_wieldables:
		return
	
	is_being_wielded = true
	update_wieldable_data(player_interaction_component)
	player_interaction_component.change_wieldable_to(self)


func put_away():
	if player_interaction_component.is_changing_wieldables:
		return
	
	is_being_wielded = false
	update_wieldable_data(player_interaction_component)
	player_interaction_component.change_wieldable_to(null)


func update_wieldable_data(_player_interaction_component : PlayerInteractionComponent):
	if _player_interaction_component: #Only update if something get's passed
		if is_being_wielded:
			if !no_reload:
				_player_interaction_component.updated_wieldable_data.emit(self,get_item_amount_in_inventory(ammo_item_name),get_ammo_item(ammo_item_name))
			else:
				_player_interaction_component.updated_wieldable_data.emit(self,0,null)
		else:
			_player_interaction_component.updated_wieldable_data.emit(null, 0, null)


func subtract(amount):
	charge_current -= amount
	if charge_current < 0:
		charge_current = 0

	_sync_wielded_weapon()
	if is_being_wielded:
		update_wieldable_data(player_interaction_component)

	charge_changed.emit()


## For a firearm, charge_current is only a mirror of firearm_mechanical_state —
## but add()/subtract() (charging loose rounds into a gun from the inventory, or
## picking ammo up while wielding it) mutate it on its own. If the weapon is in
## hand, its live mechanics must re-read the item right now: otherwise the next
## shot commits the stale round count straight back over what was just loaded.
## Loose loading also reconciles holstered state before a magazine can be detached.
func _sync_wielded_weapon() -> void:
	if not is_being_wielded or player_interaction_component == null:
		return
	var weapon_node = player_interaction_component.equipped_wieldable_node
	if weapon_node != null and weapon_node.has_method("sync_mechanics_from_item"):
		weapon_node.sync_mechanics_from_item()

func send_empty_hint():
	if hint_on_empty:
		player_interaction_component.send_hint(null, tr(name) + ": "+ tr(hint_on_empty) )


func add(amount):
	charge_current += amount
	var cap := get_effective_charge_max()
	if charge_current > cap:
		charge_current = cap

	_sync_stored_firearm_charge()
	_sync_wielded_weapon()
	if is_being_wielded:
		update_wieldable_data(player_interaction_component)
	charge_changed.emit()


## Use the existing re-equip rule only when a stored firearm's total was changed.
## Coherent chamber/bolt state is left alone; live firearms use their own configuration.
func _sync_stored_firearm_charge() -> void:
	if is_being_wielded and player_interaction_component != null:
		return
	if not has_firearm_mechanical_state():
		return
	var state := get_firearm_mechanical_state()
	var total := int(charge_current)
	var saved_total := int(state.get("magazine_rounds", 0)) + int(state.get("chamber_rounds", 0))
	if saved_total == total:
		return
	var chamber := mini(total, chamber_capacity())
	state["chamber_rounds"] = chamber
	state["magazine_rounds"] = total - chamber
	if total > 0:
		state["bolt_locked_open"] = false
	set_firearm_mechanical_state(state)


func has_firearm_mechanical_state() -> bool:
	return int(firearm_mechanical_state.get("version", 0)) == FirearmMechanicalState.SAVE_VERSION


func get_firearm_mechanical_state() -> Dictionary:
	return firearm_mechanical_state.duplicate(true)


func set_firearm_mechanical_state(state: Dictionary) -> void:
	if state.is_empty():
		clear_firearm_mechanical_state()
		return
	firearm_mechanical_state = state.duplicate(true)


func clear_firearm_mechanical_state() -> void:
	firearm_mechanical_state = {}


# Functions for ATTACHMENTS (mirror of the mechanical-state accessors above)
func get_attachments() -> Dictionary:
	return attachments.duplicate(true)


## Preferred content roots. Legacy res:// AttachmentItemPD outside these is still accepted.
const _ATTACHMENT_CONTENT_ROOTS := [
	"res://Scene/Items/Attachments/",
	"res://Scene/Attachment/",
]


func _is_allowed_attachment_path(path: String) -> bool:
	var cleaned := path.strip_edges()
	if cleaned.is_empty() or not cleaned.begins_with("res://") or cleaned.contains(".."):
		return false
	var simplified := cleaned.simplify_path()
	if not simplified.begins_with("res://"):
		return false
	if not (simplified.ends_with(".tres") or simplified.ends_with(".res")):
		return false
	if not ResourceLoader.exists(simplified):
		return false
	var under_root := false
	for root in _ATTACHMENT_CONTENT_ROOTS:
		if simplified.begins_with(root):
			under_root = true
			break
	var res = load(simplified)
	if not (res is AttachmentItemPD):
		return false
	# Prefer content roots; preserve safe legacy AttachmentItemPD elsewhere under res://.
	return under_root or simplified.begins_with("res://")


var _attachment_cache: Dictionary = {}


func set_attachments(new_attachments: Dictionary) -> void:
	_attachment_cache.clear()
	# Restrict restored paths to project res:// AttachmentItemPD resources.
	var cleaned: Dictionary = {}
	for slot in new_attachments.keys():
		var path := str(new_attachments[slot]).strip_edges()
		if path.is_empty():
			continue
		if not _is_allowed_attachment_path(path):
			push_warning("WieldableItemPD: rejected attachment path: " + path)
			continue
		cleaned[slot] = path.simplify_path()
	attachments = cleaned


func get_attachment_item(slot: int) -> AttachmentItemPD:
	if _attachment_cache.has(slot):
		return _attachment_cache[slot]
	var path: String = str(attachments.get(slot, ""))
	if path.is_empty() or not _is_allowed_attachment_path(path):
		return null
	var item := load(path) as AttachmentItemPD
	if item:
		_attachment_cache[slot] = item
	return item


func get_attached_items() -> Array[AttachmentItemPD]:
	var items: Array[AttachmentItemPD] = []
	for slot in attachments.keys():
		var item := get_attachment_item(int(slot))
		if item != null:
			items.append(item)
	return items


## Product of the given multiplier property across all attached items.
func attachment_multiplier(prop: StringName) -> float:
	var result := 1.0
	for item in get_attached_items():
		result *= float(item.get(prop))
	return result


func get_effective_damage() -> float:
	return wieldable_damage * attachment_multiplier(&"damage_multiplier")


func get_effective_range() -> float:
	return wieldable_range * attachment_multiplier(&"range_multiplier")


## Removes whatever is in `slot` and hands it back. THE single exit for every
## attachment: the modding panel, the X hotkey and an attach-over-a-swap all
## route here, so the magazine rule lives in one place.
##
## Rounds live in the magazine. A magazine therefore comes back as a per-instance
## copy carrying the rounds the weapon was feeding, and the weapon is left empty
## — no spilling loose rounds into the pockets, and nothing to clamp away when a
## smaller magazine takes its place.
func _take_attachment(slot: int) -> AttachmentItemPD:
	var item := get_attachment_item(slot)
	attachments.erase(slot)
	_attachment_cache.erase(slot)
	if item == null or slot != AttachmentItemPD.AttachmentSlot.MAGAZINE:
		return item
	var magazine := item.duplicate_instance()
	magazine.loaded_rounds = get_magazine_rounds()
	set_magazine_rounds(0)
	return magazine


## Attaches the item if compatible and not wielded. Returns the previous
## occupant of that slot (AttachmentItemPD) or null. Returns the passed item
## itself if the attach was rejected — caller keeps it.
func try_attach(attachment: AttachmentItemPD) -> AttachmentItemPD:
	if attachment == null or is_being_wielded or not attachment.fits(self):
		return attachment
	var slot := int(attachment.attachment_slot)
	var previous := _take_attachment(slot)
	attachments[slot] = attachment.get_source_path()
	_attachment_cache[slot] = attachment
	# A magazine with recorded contents pours them in. loaded_rounds < 0 means
	# "unknown" (world spawn / NPC roll / authored default) — leave the weapon's
	# own count alone, which is what this did before magazines held rounds.
	if slot == AttachmentItemPD.AttachmentSlot.MAGAZINE and attachment.loaded_rounds >= 0:
		set_magazine_rounds(mini(attachment.loaded_rounds, attachment.magazine_capacity))
	return previous


func get_magazine() -> AttachmentItemPD:
	return get_attachment_item(AttachmentItemPD.AttachmentSlot.MAGAZINE)


## Chamber size. Mirrored onto the item as meta by CogitoFirearm.equip(); every
## firearm in this project chambers 1, so that's the pre-equip fallback.
func chamber_capacity() -> int:
	return int(get_meta("chamber_capacity", 1))


## Total rounds the weapon can hold RIGHT NOW = magazine + chamber.
## No magazine attached = chamber only (the weapon can't feed).
func get_effective_charge_max() -> float:
	var mag := get_magazine()
	var mag_rounds := mag.magazine_capacity if mag else 0
	return float(mag_rounds + chamber_capacity())


## Rounds currently in the magazine. A weapon that has never been equipped has
## no mechanical state yet — there, charge_current is the only record of what's
## loaded, so derive the magazine count from it (chamber holds the rest).
func get_magazine_rounds() -> int:
	if has_firearm_mechanical_state():
		return int(firearm_mechanical_state.get("magazine_rounds", 0))
	return maxi(int(charge_current) - chamber_capacity(), 0)


## Writes the magazine round count back into the persisted mechanical state and
## keeps charge_current (what the HUD reads) in sync.
func set_magazine_rounds(rounds: int) -> void:
	rounds = maxi(rounds, 0)
	if has_firearm_mechanical_state():
		var state := get_firearm_mechanical_state()
		state["magazine_rounds"] = rounds
		set_firearm_mechanical_state(state)
		charge_current = float(rounds + int(state.get("chamber_rounds", 0)))
	else:
		var chamber := mini(int(charge_current), chamber_capacity())
		charge_current = float(rounds + chamber)
	charge_changed.emit()


## What detach_next() would remove, without removing it.
func peek_next_attachment() -> AttachmentItemPD:
	var slots := attachments.keys()
	slots.sort()
	for slot in slots:
		var item := get_attachment_item(int(slot))
		if item != null:
			return item
	return null


## Removes and returns the attachment in a specific slot (the modding panel
## detaches by slot; detach_next() is the blind quick-detach hotkey).
func detach(slot: int) -> AttachmentItemPD:
	if is_being_wielded:
		return null
	return _take_attachment(slot)


## Removes and returns the first attached item in AttachmentSlot enum order.
func detach_next() -> AttachmentItemPD:
	if is_being_wielded:
		return null
	var slots := attachments.keys()
	slots.sort()
	for slot in slots:
		var item := _take_attachment(int(slot))
		if item != null:
			return item
	return null


# Function to get the AmmoItemPD
func get_ammo_item(item_name_to_check_for: String) -> InventoryItemPD:
	var ammo_item : InventoryItemPD
	if player_interaction_component.get_parent().inventory_data != null:
		var inventory_to_check = player_interaction_component.get_parent().inventory_data
		for slot in inventory_to_check.inventory_slots:
			if slot != null and slot.inventory_item.name == item_name_to_check_for:
				ammo_item = slot.inventory_item
				
	return ammo_item


# Function to get the amount of ammo in the player inventory
func get_item_amount_in_inventory(item_name_to_check_for: String) -> int:
	var item_count : int = 0
	if player_interaction_component.get_parent().inventory_data != null:
		var inventory_to_check = player_interaction_component.get_parent().inventory_data
		for slot in inventory_to_check.inventory_slots:
			if slot != null and slot.inventory_item.name == item_name_to_check_for:
				item_count += slot.quantity
				
	return item_count


func save():
	var saved_item_data = {
		"resource" : self,
		"charge_current" : charge_current,
		"firearm_mechanical_state" : get_firearm_mechanical_state(),
		"attachments" : get_attachments(),
	}
	return saved_item_data


func build_wieldable_scene():
	var scene = wieldable_scene.instantiate()
	scene.item_reference = self
	return scene
