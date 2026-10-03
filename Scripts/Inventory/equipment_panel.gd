extends HBoxContainer

## Layout-only companion to EquipmentPanel.tscn. Applies EquipmentSlotUI's
## centralized theme constants to the parts of this scene that aren't
## EquipmentSlotUI instances (the two wrapper panels, the headers) so no
## color/size value is duplicated outside equipment_slot_ui.gd. All data
## wiring (binding a CogitoEquipment instance, reparenting pockets UIs) is
## done by inventory_interface.gd, not here — this panel doesn't know or
## care whether it's showing the player's or a corpse's equipment.
##
## Two instances of this scene can exist at once (player's, embedded in the
## inventory tab; a corpse's, shown externally) since nothing here hardcodes
## a specific CogitoEquipment — see equipment_slot_ui.gd's set_equipment().

## Set false for a standalone/external panel (e.g. a corpse's) where pockets
## are shown by a separate InventoryUI elsewhere — hides RightPanel entirely
## instead of leaving an empty, unpopulated pockets placeholder on screen.
@export var show_pockets: bool = true
## Overall panel header shown above the equipment column (e.g. "BODY" or a
## corpse's display_name). Empty = hidden (the player's embedded panel
## doesn't need one; it's already inside a labeled inventory tab).
@export var header_text: String = ""

@onready var left_panel: PanelContainer = $LeftPanel
@onready var right_panel: PanelContainer = $RightPanel
@onready var spacer: Control = $Spacer
@onready var panel_header: Label = $LeftPanel/LeftMargin/LeftContentVBox/PanelHeaderLabel
@onready var pockets_header: Label = $RightPanel/RightMargin/RightVBox/PocketsHeader
@onready var pockets_slot: Control = $RightPanel/RightMargin/RightVBox/PocketsSlot


func _ready() -> void:
	var wrapper_style := StyleBoxFlat.new()
	wrapper_style.bg_color = EquipmentSlotUI.COLOR_PANEL_WRAPPER
	wrapper_style.border_color = EquipmentSlotUI.COLOR_BORDER
	wrapper_style.set_border_width_all(EquipmentSlotUI.BORDER_WIDTH)
	wrapper_style.set_corner_radius_all(EquipmentSlotUI.CORNER_RADIUS)
	left_panel.add_theme_stylebox_override("panel", wrapper_style)
	right_panel.add_theme_stylebox_override("panel", wrapper_style)

	set_header_text(header_text)

	if show_pockets:
		pockets_header.text = "POCKETS"
		pockets_header.add_theme_font_size_override("font_size", EquipmentSlotUI.HEADER_FONT_SIZE)
		pockets_header.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
	else:
		right_panel.hide()
		spacer.hide()


## Public (not just _ready()-time) so inventory_interface.gd can (re)label
## this panel per-corpse ("BODY"/display_name) after it's already in the
## tree — the header text isn't known until a specific corpse is looted.
func set_header_text(text: String) -> void:
	header_text = text
	if text != "":
		panel_header.text = text.to_upper()
		panel_header.add_theme_font_size_override("font_size", EquipmentSlotUI.HEADER_FONT_SIZE)
		panel_header.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
		panel_header.show()
	else:
		panel_header.hide()


## Placeholder container that should receive the pre-existing player_inv_tab
## children (pockets grid + external container area). Only meaningful when
## show_pockets is true.
func get_pockets_slot() -> Control:
	return pockets_slot


## Every EquipmentSlotUI in this panel, keyed by slot_id.
func collect_equipment_slots() -> Dictionary:
	var result: Dictionary = {}
	for node in find_children("*", "EquipmentSlotUI", true, false):
		var slot := node as EquipmentSlotUI
		if slot:
			result[slot.slot_id] = slot
	return result
