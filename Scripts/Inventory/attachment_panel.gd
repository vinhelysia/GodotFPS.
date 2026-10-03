extends PanelContainer
class_name AttachmentPanel

## Tarkov-style mod bench. Shows one weapon's attachment slots + its effective
## stats, and lets you fit/strip attachments by clicking (same grab-and-place
## cursor as the rest of the inventory).
##
## The panel owns no interaction logic: it binds an AttachmentEquipment (which
## presents the weapon's `attachments` dict as a CogitoEquipment) onto plain
## EquipmentSlotUI nodes, so inventory_interface's _on_equipment_slot_pressed()
## drives attach/detach exactly like it drives the gear panel.

const COLOR_GOOD: Color = Color(0.44, 0.78, 0.46)
const COLOR_BAD: Color = Color(0.85, 0.42, 0.4)
const COLOR_NEUTRAL: Color = Color(0.85, 0.85, 0.85)
const COLOR_WARNING: Color = Color(0.9, 0.66, 0.3)
const TITLE_FONT_SIZE: int = 13
const STAT_FONT_SIZE: int = 12

@onready var title_label: Label = $Margin/VBox/HeaderRow/TitleLabel
@onready var close_button: Button = $Margin/VBox/HeaderRow/CloseButton
@onready var warning_label: Label = $Margin/VBox/WarningLabel
@onready var stats_header: Label = $Margin/VBox/StatsHeader
@onready var stats_grid: GridContainer = $Margin/VBox/StatsGrid

var weapon_item: WieldableItemPD

var _equipment: AttachmentEquipment = AttachmentEquipment.new()
var _slots: Dictionary = {}  # slot_id -> EquipmentSlotUI
var _interface: Control


func _ready() -> void:
	var wrapper_style := StyleBoxFlat.new()
	wrapper_style.bg_color = EquipmentSlotUI.COLOR_PANEL_WRAPPER
	wrapper_style.border_color = EquipmentSlotUI.COLOR_BORDER
	wrapper_style.set_border_width_all(EquipmentSlotUI.BORDER_WIDTH)
	wrapper_style.set_corner_radius_all(EquipmentSlotUI.CORNER_RADIUS)
	add_theme_stylebox_override("panel", wrapper_style)

	for label: Label in [title_label, stats_header]:
		label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		label.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
	for child in stats_grid.get_children():
		var label := child as Label
		if label:
			label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
			if label.name.begins_with("Label_"):
				label.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
	warning_label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	warning_label.add_theme_color_override("font_color", COLOR_WARNING)

	close_button.pressed.connect(close)
	_slots = collect_slots()
	hide()


## Every EquipmentSlotUI in this panel, keyed by slot_id — same type-driven
## discovery equipment_panel.gd uses.
func collect_slots() -> Dictionary:
	var result: Dictionary = {}
	for node in find_children("*", "EquipmentSlotUI", true, false):
		var slot := node as EquipmentSlotUI
		if slot:
			result[slot.slot_id] = slot
	return result


func is_open() -> bool:
	return visible


## Binds the panel to a weapon. `inventory` is where stripped attachments and
## spilled magazine rounds land (always the player's pockets, even when modding
## a weapon that's still on a corpse).
func open(new_weapon: WieldableItemPD, inventory: CogitoInventory, interface: Control) -> void:
	if new_weapon == null:
		return
	weapon_item = new_weapon
	_interface = interface
	_equipment.bind(new_weapon, inventory)
	if not _equipment.changed_slot.is_connected(_on_changed_slot):
		_equipment.changed_slot.connect(_on_changed_slot)

	for slot_id in _slots:
		_slots[slot_id].set_equipment(_equipment, interface)

	title_label.text = "MODDING — " + new_weapon.name.to_upper()
	warning_label.visible = new_weapon.is_being_wielded
	_refresh_stats()
	show()


## Same weapon = toggle off; different weapon = rebind.
func toggle(new_weapon: WieldableItemPD, inventory: CogitoInventory, interface: Control) -> void:
	if visible and new_weapon == weapon_item:
		close()
	else:
		open(new_weapon, inventory, interface)


func close() -> void:
	hide()
	weapon_item = null
	clear_compat_highlight()


func _on_changed_slot(_slot_id: StringName) -> void:
	_refresh_stats()


func _refresh_stats() -> void:
	if weapon_item == null:
		return
	_set_stat("Damage", "%d" % int(weapon_item.get_effective_damage()), COLOR_NEUTRAL)
	_set_stat("Range", "%d m" % int(weapon_item.get_effective_range()), COLOR_NEUTRAL)

	var magazine := weapon_item.get_magazine()
	var capacity_text := "%d" % int(weapon_item.get_effective_charge_max())
	if magazine == null:
		capacity_text += "  (no magazine)"
	_set_stat("Capacity", capacity_text, COLOR_NEUTRAL if magazine else COLOR_BAD)

	# Recoil / ADS / loudness are shown as modifiers, not absolutes: their base
	# values live on the weapon's Weapon_Resource, which WieldableItemPD has no
	# reference to. Lower is better for all three.
	_set_delta_stat("Recoil", weapon_item.attachment_multiplier(&"recoil_multiplier"))
	_set_delta_stat("Ads", weapon_item.attachment_multiplier(&"ads_time_multiplier"))
	_set_delta_stat("Loudness", weapon_item.attachment_multiplier(&"loudness_multiplier"))


func _set_delta_stat(key: String, multiplier: float) -> void:
	var percent := int(round((multiplier - 1.0) * 100.0))
	if percent == 0:
		_set_stat(key, "—", COLOR_NEUTRAL)
		return
	_set_stat(key, "%+d%%" % percent, COLOR_GOOD if percent < 0 else COLOR_BAD)


func _set_stat(key: String, text: String, color: Color) -> void:
	var label := stats_grid.get_node_or_null("Value_" + key) as Label
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)


## Called whenever the cursor item changes: marks which slots would accept it
## and dims the ones that wouldn't. No-op when nothing relevant is grabbed.
func refresh_compat_highlight(grabbed_slot_data: InventorySlotPD) -> void:
	if not visible:
		return
	var is_attachment: bool = grabbed_slot_data != null \
			and grabbed_slot_data.inventory_item is AttachmentItemPD
	if not is_attachment:
		clear_compat_highlight()
		return
	for slot_id in _slots:
		var slot: EquipmentSlotUI = _slots[slot_id]
		var fits: bool = _equipment.can_equip(slot_id, grabbed_slot_data)
		slot.selection_panel.visible = fits
		slot.selection_panel.modulate = COLOR_GOOD
		slot.modulate.a = 1.0 if fits else 0.4


func clear_compat_highlight() -> void:
	for slot_id in _slots:
		var slot: EquipmentSlotUI = _slots[slot_id]
		slot.selection_panel.visible = false
		slot.selection_panel.modulate = Color.WHITE
		slot.modulate.a = 1.0
