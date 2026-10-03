extends SlotPanel
class_name EquipmentSlotUI

## Escape-from-Tarkov-style equipment slot. Visual layer only — set_slot_data,
## charge_changed wiring, and grabbed-item rendering are all inherited from
## SlotPanel/Slot.gd unchanged. This script only adds the header strip, ammo
## counter, hotkey badge, and slot frame styling on top of that behavior.

enum SlotShape { GEAR_SQUARE, WEAPON_WIDE }

# ── Centralized theme values — the ONLY place these are defined ──────────
const COLOR_BG_FILLED: Color = Color(0.08, 0.08, 0.08, 0.85)
const COLOR_BG_EMPTY: Color = Color(0.05, 0.05, 0.05, 0.85)
const COLOR_BORDER: Color = Color(0.29, 0.29, 0.29)
const COLOR_HEADER_BG: Color = Color(0.03, 0.03, 0.03, 0.9)
const COLOR_HEADER_TEXT: Color = Color(0.72, 0.72, 0.72)
const COLOR_AMMO_TEXT: Color = Color(1, 1, 1)
const HEADER_FONT_SIZE: int = 11
const AMMO_FONT_SIZE: int = 16
const HOTKEY_FONT_SIZE: int = 10
const HOTKEY_BADGE_SIZE: Vector2 = Vector2(18, 18)
const HEADER_STRIP_HEIGHT: float = 16.0
const GEAR_SQUARE_SIZE: Vector2 = Vector2(92, 92)
const WEAPON_WIDE_SIZE: Vector2 = Vector2(232, 96)
const BORDER_WIDTH: int = 1
const CORNER_RADIUS: int = 0
## Wrapper panel behind the whole equipment column / pockets column
## (EquipmentPanel.tscn's LeftPanel/RightPanel) — shared here so
## equipment_panel.gd doesn't duplicate its own copy of this color.
const COLOR_PANEL_WRAPPER: Color = Color(0.02, 0.02, 0.02, 0.6)

@export var slot_id: StringName
@export var slot_shape: SlotShape = SlotShape.GEAR_SQUARE
@export var slot_label: String = ""
## Hotkey digit shown top-right ("1"-"4" on weapon slots). Empty = no badge.
@export var hotkey_text: String = ""

@onready var header_strip: PanelContainer = $HeaderStrip
@onready var header_label: Label = $HeaderStrip/HeaderMargin/HeaderLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var hotkey_badge: PanelContainer = $HotkeyBadge
@onready var hotkey_label: Label = $HotkeyBadge/HotkeyLabel

var equipment: CogitoEquipment
var inventory_interface: Control

## Carries the equipment instance this slot is bound to (player's or a
## corpse's) so a single shared handler in inventory_interface.gd can route
## the action to the right CogitoEquipment — no hardcoded player reference.
signal equipment_slot_clicked(equipment_instance: CogitoEquipment, slot_id: StringName, action: String)

var _tracked_inventory: CogitoInventory
var _tracked_item: Object
var _tracked_equipment: CogitoEquipment
var _style_filled: StyleBoxFlat
var _style_empty: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = WEAPON_WIDE_SIZE if slot_shape == SlotShape.WEAPON_WIDE else GEAR_SQUARE_SIZE

	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_build_frame_styles()
	_apply_frame_style(false)

	header_strip.custom_minimum_size = Vector2(0, HEADER_STRIP_HEIGHT)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = COLOR_HEADER_BG
	header_strip.add_theme_stylebox_override("panel", header_style)

	header_label.text = slot_label.to_upper()
	header_label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	header_label.add_theme_color_override("font_color", COLOR_HEADER_TEXT)

	ammo_label.add_theme_font_size_override("font_size", AMMO_FONT_SIZE)
	ammo_label.add_theme_color_override("font_color", COLOR_AMMO_TEXT)
	ammo_label.hide()

	if hotkey_text != "":
		hotkey_badge.custom_minimum_size = HOTKEY_BADGE_SIZE
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = COLOR_HEADER_BG
		badge_style.border_color = COLOR_BORDER
		badge_style.set_border_width_all(BORDER_WIDTH)
		badge_style.set_corner_radius_all(CORNER_RADIUS)
		hotkey_badge.add_theme_stylebox_override("panel", badge_style)
		hotkey_label.text = hotkey_text
		hotkey_label.add_theme_font_size_override("font_size", HOTKEY_FONT_SIZE)
		hotkey_badge.show()
	else:
		hotkey_badge.hide()


func _build_frame_styles() -> void:
	_style_filled = StyleBoxFlat.new()
	_style_filled.bg_color = COLOR_BG_FILLED
	_style_filled.border_color = COLOR_BORDER
	_style_filled.set_border_width_all(BORDER_WIDTH)
	_style_filled.set_corner_radius_all(CORNER_RADIUS)
	_style_filled.shadow_size = 0

	_style_empty = _style_filled.duplicate()
	_style_empty.bg_color = COLOR_BG_EMPTY


func _apply_frame_style(has_item: bool) -> void:
	add_theme_stylebox_override("panel", _style_filled if has_item else _style_empty)


## Can be called repeatedly with a DIFFERENT equipment instance (e.g. this
## same slot node showing corpse A, then corpse B) — disconnects from
## whatever was tracked before so a looted corpse's equipment doesn't stay
## referenced (and re-triggering update_slot() on us) forever after.
func set_equipment(in_equipment: CogitoEquipment, in_interface: Control) -> void:
	if _tracked_equipment and _tracked_equipment != in_equipment \
			and _tracked_equipment.changed_slot.is_connected(_on_equipment_changed):
		_tracked_equipment.changed_slot.disconnect(_on_equipment_changed)

	equipment = in_equipment
	_tracked_equipment = in_equipment
	inventory_interface = in_interface
	if equipment and not equipment.changed_slot.is_connected(_on_equipment_changed):
		equipment.changed_slot.connect(_on_equipment_changed)
	update_slot()

## Ammo counter also refreshes on the player's inventory_updated (e.g. ammo
## consumed from the inventory during reload), in addition to the direct
## per-item charge_changed tracking in _track_item_charge_changed() and
## equipment.changed_slot (equip/unequip).
func _connect_inventory_updated() -> void:
	if inventory_interface == null:
		return
	var inv_ui: Variant = inventory_interface.get("inventory_ui")
	if inv_ui == null:
		return
	var inv_data: Variant = inv_ui.get("loaded_inventory_data")
	if not (inv_data is CogitoInventory):
		return
	_set_tracked_inventory(inv_data)


func _set_tracked_inventory(inventory_data: CogitoInventory) -> void:
	if inventory_data == _tracked_inventory:
		return
	_disconnect_tracked_inventory()
	_tracked_inventory = inventory_data
	if not _tracked_inventory.inventory_updated.is_connected(_on_inventory_updated):
		_tracked_inventory.inventory_updated.connect(_on_inventory_updated)


func _disconnect_tracked_inventory() -> void:
	if _tracked_inventory and _tracked_inventory.inventory_updated.is_connected(_on_inventory_updated):
		_tracked_inventory.inventory_updated.disconnect(_on_inventory_updated)
	_tracked_inventory = null

func _on_inventory_updated(_inventory_data: CogitoInventory) -> void:
	_refresh_ammo_counter()
	# The "+N" mod badge can change without an equip/unequip — fitting an
	# attachment mutates the item in place, and only signals inventory_updated.
	refresh_overlays(true)


func _on_equipment_changed(changed_id: StringName) -> void:
	if changed_id == slot_id:
		update_slot()


func update_slot() -> void:
	var slot_data: InventorySlotPD = equipment.get_equipped(slot_id) if equipment else null
	if slot_data:
		# Use parent class set_slot_data with dummy index/size
		set_slot_data(slot_data, -1, false, 1)
		set_hotbar_icon()
		quantity_label.hide()
		charge_label.hide() # superseded visually by ammo_label below
		_apply_frame_style(true)
	else:
		item_data = null
		texture_rect.texture = null
		quantity_label.hide()
		charge_label.hide()
		background_panel.hide()
		refresh_overlays(true)  # item_data is null now → clears badge + name
		_apply_frame_style(false)

	_track_item_charge_changed()
	_refresh_ammo_counter()
	if equipment:
		_connect_inventory_updated()
	else:
		_disconnect_tracked_inventory()


## SlotPanel only connects charge_changed when its own ammo_slot flag is
## true, which is grid-cell math (bottom-right cell of a multi-cell item at
## a real index) that never comes out true for a single equipment slot
## (index always -1 here). So we track it ourselves, directly on whatever
## item is currently equipped, to get real per-shot ammo refreshes instead
## of only refreshing on equip/unequip/reload.
func _track_item_charge_changed() -> void:
	if item_data == _tracked_item:
		return
	if _tracked_item and _tracked_item.has_signal("charge_changed") \
			and _tracked_item.charge_changed.is_connected(_on_item_charge_changed):
		_tracked_item.charge_changed.disconnect(_on_item_charge_changed)
	_tracked_item = item_data
	if _tracked_item and _tracked_item.has_signal("charge_changed") \
			and not _tracked_item.charge_changed.is_connected(_on_item_charge_changed):
		_tracked_item.charge_changed.connect(_on_item_charge_changed)


func _on_item_charge_changed() -> void:
	_refresh_ammo_counter()


## Shows "current/max" for whatever is actually equipped — driven by the
## item's own charge_current/charge_max/no_reload, not by slot shape, so
## melee (no_reload) and gear (no charge_* at all) correctly show nothing.
func _refresh_ammo_counter() -> void:
	# A magazine carries its own rounds, so it gets the same counter a weapon does.
	var magazine := item_data as AttachmentItemPD
	if magazine != null and magazine.attachment_slot == AttachmentItemPD.AttachmentSlot.MAGAZINE:
		ammo_label.text = "%d/%d" % [maxi(magazine.loaded_rounds, 0), magazine.magazine_capacity]
		ammo_label.show()
		return
	if item_data == null or not ("charge_max" in item_data) or not ("charge_current" in item_data):
		ammo_label.hide()
		return
	if "no_reload" in item_data and item_data.no_reload:
		ammo_label.hide()
		return
	ammo_label.text = "%d/%d" % [int(item_data.charge_current), int(item_data.get_effective_charge_max())]
	ammo_label.show()


func _on_gui_input(event: InputEvent):
	if event.is_action_pressed("inventory_move_item"):
		equipment_slot_clicked.emit(equipment, slot_id, "inventory_move_item")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory_use_item"):
		equipment_slot_clicked.emit(equipment, slot_id, "inventory_use_item")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory_drop_item"):
		equipment_slot_clicked.emit(equipment, slot_id, "inventory_drop_item")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory_detach_item"):
		equipment_slot_clicked.emit(equipment, slot_id, "inventory_detach_item")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory_mod_item"):
		equipment_slot_clicked.emit(equipment, slot_id, "inventory_mod_item")
		get_viewport().set_input_as_handled()


func _on_focus_entered() -> void:
	if sound_highlight:
		Audio.play_sound(sound_highlight)
	var highlight_panel = get_node_or_null("Panel")
	if highlight_panel:
		highlight_panel.show()


func _on_focus_exited() -> void:
	var highlight_panel = get_node_or_null("Panel")
	if highlight_panel:
		highlight_panel.hide()
