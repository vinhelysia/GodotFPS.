extends PanelContainer

const Slot = preload("./Slot.tscn")

@export var inventory_name : String = ""

@export var color_can_swap : Color = Color.YELLOW
@export var color_can_not_place : Color = Color.DARK_RED
@export var color_can_place : Color = Color.LIME_GREEN

@onready var grid_container = $MarginContainer/VBoxContainer/GridContainer
@onready var label = $MarginContainer/VBoxContainer/Label
@onready var button_take_all: Button = $MarginContainer/VBoxContainer/Button_TakeAll

var slot_array = []
var first_slot : InventorySlotPD
var grabbed_slot : SlotPanel
var loaded_inventory_data : CogitoInventory
var currently_focused_slot : SlotPanel

func _ready():
	_apply_theme()
	_update_label()
	button_take_all.hide()


func set_inventory_data(inventory_data : CogitoInventory):
	if loaded_inventory_data and loaded_inventory_data != inventory_data \
			and loaded_inventory_data.inventory_updated.is_connected(populate_item_grid):
		loaded_inventory_data.inventory_updated.disconnect(populate_item_grid)
	loaded_inventory_data = inventory_data
	if !inventory_data.inventory_updated.is_connected(populate_item_grid):
		inventory_data.inventory_updated.connect(populate_item_grid)
	_update_label()
	populate_item_grid(inventory_data)

## Internal title is legacy chrome — section headers ("POCKETS", a corpse's
## display_name strip, etc.) now come from whatever column layout embeds
## this grid (see EquipmentPanel.tscn / Player_HUD.tscn's RightColumn), not
## from this label. Kept around (rather than deleted) since callers can still
## opt in by setting inventory_name.
func _update_label() -> void:
	label.text = inventory_name
	label.visible = inventory_name != ""


## Reuses EquipmentSlotUI's centralized theme constants (Scripts/Inventory/
## equipment_slot_ui.gd) so this grid's chrome matches the equipment slots
## instead of the stock light theme — no separate/new color values here.
func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = EquipmentSlotUI.COLOR_BG_FILLED
	panel_style.border_color = EquipmentSlotUI.COLOR_BORDER
	panel_style.set_border_width_all(EquipmentSlotUI.BORDER_WIDTH)
	panel_style.set_corner_radius_all(EquipmentSlotUI.CORNER_RADIUS)
	panel_style.shadow_size = 0
	add_theme_stylebox_override("panel", panel_style)

	label.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
	label.add_theme_font_size_override("font_size", EquipmentSlotUI.HEADER_FONT_SIZE)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = EquipmentSlotUI.COLOR_HEADER_BG
	btn_normal.border_color = EquipmentSlotUI.COLOR_BORDER
	btn_normal.set_border_width_all(EquipmentSlotUI.BORDER_WIDTH)
	btn_normal.set_corner_radius_all(EquipmentSlotUI.CORNER_RADIUS)
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = EquipmentSlotUI.COLOR_BG_FILLED.lightened(0.15)
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = EquipmentSlotUI.COLOR_BG_FILLED.lightened(0.05)
	button_take_all.add_theme_stylebox_override("normal", btn_normal)
	button_take_all.add_theme_stylebox_override("hover", btn_hover)
	button_take_all.add_theme_stylebox_override("pressed", btn_pressed)
	button_take_all.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)
	button_take_all.add_theme_color_override("font_hover_color", EquipmentSlotUI.COLOR_AMMO_TEXT)


func clear_inventory_data(inventory_data : CogitoInventory):
	if inventory_data.inventory_updated.is_connected(populate_item_grid):
		inventory_data.inventory_updated.disconnect(populate_item_grid)
	if loaded_inventory_data == inventory_data:
		loaded_inventory_data = null
	slot_array.clear()

func populate_item_grid(inventory_data : CogitoInventory) -> void:
	CogitoGlobals.debug_log(true,"InventoryUI.gd", "Populate_item_grid called." )
	
	for child in grid_container.get_children():
		child.queue_free()
	
	# Clearing array for gamepad navigation.
	slot_array.clear()
	
	if inventory_data.grid:
		# set grid container columns to the width (x) of the inventory
		grid_container.columns = inventory_data.inventory_size.x
	
	var index = 0
	for slot_data in inventory_data.inventory_slots:
		var slot = Slot.instantiate()
		grid_container.add_child(slot)
		# Filling array for gamepad navigation.
		slot_array.append(slot)
	
		slot.slot_clicked.connect(inventory_data.on_slot_clicked)
		slot.slot_pressed.connect(inventory_data.on_slot_button_pressed)
		slot.highlight_slot.connect(highlight_slots)
		slot.using_grid(inventory_data.grid)
	
		if slot_data:
			slot.is_rotated = slot_data.is_rotated
			slot.set_slot_data(slot_data, index, false, grid_container.columns)
			slot.set_hotbar_icon()
			
		index += 1
	
	override_slot_focus_neighbors()
	
	if inventory_data.grid:
		apply_slot_icon_regions()


func override_slot_focus_neighbors():
	var index = 0
	for slot in slot_array:
		# SETTING LEFT NEIGHBOR
		if index != 0:
			slot.set_focus_neighbor(SIDE_LEFT, slot_array[index-1].get_path())
		
		# SETTING RIGHT NEIGHBOR
		if index != slot_array.size() - 1:
			slot.set_focus_neighbor(SIDE_RIGHT, slot_array[index+1].get_path())
			
		# SETTING UP NEIGHBOR:
		if (index - loaded_inventory_data.inventory_size.x) >= 0: #This checks if the selected slot is NOT already in the top row.
			slot.set_focus_neighbor(SIDE_TOP, slot_array[index - loaded_inventory_data.inventory_size.x].get_path())

		# SETTING UP DOWN NEIGHOR:
		if (index + loaded_inventory_data.inventory_size.x) < slot_array.size(): #This checks that the slot is NOT already in the bottom row.
			slot.set_focus_neighbor(SIDE_BOTTOM, slot_array[index + loaded_inventory_data.inventory_size.x].get_path() )

		index += 1



func apply_slot_icon_regions():
	var added_items = []
	for slot in slot_array:
		if slot.item_data and not added_items.has(slot.origin_index):
			added_items.append(slot.origin_index)
			var sd := loaded_inventory_data.get_slot_data(slot.origin_index)
			var rotated := sd.is_rotated if sd else false
			apply_item_icons(slot.item_data, slot.origin_index, rotated)
		else:
			continue


func apply_item_icons(item_data: InventoryItemPD, origin_index: int, is_rotated: bool = false):
	var icon_slot_size := Vector2i(item_data.item_size)
	if is_rotated:
		icon_slot_size = Vector2i(icon_slot_size.y, icon_slot_size.x)
	for x in icon_slot_size.x:
		for y in icon_slot_size.y:
			var target_idx: int = origin_index + x + (y * grid_container.columns)
			if target_idx >= slot_array.size():
				continue
			var target_slot: SlotPanel = slot_array[target_idx]
			if target_slot.item_data == null:
				target_slot.item_data = item_data
			target_slot.is_rotated = is_rotated
			CogitoGlobals.debug_log(true,"InventoryUI.gd","apply_item_icons: item_data=" + item_data.name + " set_icon_region(" + str(x) + "," + str(y) + ") rotated=" + str(is_rotated))
			if is_rotated:
				target_slot.set_icon_region_rotated(x, y)
			else:
				target_slot.set_icon_region(x, y)


func detach_grabbed_slot():
	for slot in slot_array:
		slot.selection_panel.hide()
	grabbed_slot = null


func highlight_slots(index: int, highlight: bool):
	if !grabbed_slot or !grabbed_slot.item_data or !grabbed_slot.grid:
		return

	var base_size := Vector2i(grabbed_slot.item_data.item_size)
	var highlight_size: Vector2i
	if grabbed_slot.grid:
		highlight_size = Vector2i(base_size.y, base_size.x) if grabbed_slot.is_rotated else base_size
	else:
		highlight_size = Vector2i(1, 1)
	var item_intersections = count_intersecting_items(index, highlight_size)
	for x in highlight_size.x:
		for y in highlight_size.y:
			if out_of_bounds(index, x, y):
				continue
			var selection = slot_array[index + x + (y*grid_container.columns)].selection_panel
			if highlight:
				selection.show()
			else:
				selection.hide()
	change_slot_colours(highlight_size, index, item_intersections)


func change_slot_colours(slot_group: Vector2i, index, item_intersections):
	for x in slot_group.x:
		for y in slot_group.y:
			if out_of_bounds(index, x, y):
				continue
			var selection = slot_array[index + x + (y*grid_container.columns)].selection_panel
			selection.modulate = set_colour(item_intersections)


# count intersections to check if item can be swapped out
func count_intersecting_items(index: int, intersect_size: Vector2i):
	var intersecting_origins = []
	for x in intersect_size.x:
		for y in intersect_size.y:
			if out_of_bounds(index, x, y):
				return -1
			var adj_item = slot_array[index + x + (y*grid_container.columns)]
			if not adj_item:
				continue
			if adj_item.origin_index != -1 and not intersecting_origins.has(adj_item.origin_index):
				intersecting_origins.append(adj_item.origin_index)
	return intersecting_origins.size()


func set_colour(item_intersections):
	if item_intersections == -1 or item_intersections > 1:
		return color_can_not_place
	elif item_intersections == 1:
		return color_can_swap
	else:
		return color_can_place


func out_of_bounds(index: int, x, y):
	# check outside of y bounds
	if (index + x + (y*grid_container.columns)) >= slot_array.size():
		return true
	var right_edge: int = index + x
	# check row does not shift
	if (int(index / grid_container.columns) != int(right_edge / grid_container.columns)):
		return true
	return false


func _on_visibility_changed():
	# This is here because to prevent a dead end signal error in the inspector.
	pass
