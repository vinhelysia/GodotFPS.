class_name SlotPanel extends PanelContainer

@onready var background_panel: Panel = $Background
@onready var texture_rect = $MarginContainer/TextureRect
@onready var quantity_label = $QuantityLabel
@onready var charge_label = $ChargeLabel
@onready var selection_panel = $Selected
## Corner "+N" marker for a weapon that has attachments fitted. Optional — a
## slot scene without the node simply never shows one.
@onready var mod_badge: Label = get_node_or_null("ModBadge")
## Shown in place of the icon for items that have no icon assigned yet, so an
## art-less item is still readable in the grid instead of an empty frame.
@onready var name_fallback: Label = get_node_or_null("NameFallback")

@export var highlight_color : Color
## AudioStream that plays when slot gets highlighted.
@export var sound_highlight : AudioStream

var item_data = null
var origin_index : int = -1
var grid : bool
var ammo_slot : bool
var quantity_slot : bool
var is_rotated: bool = false

signal slot_clicked(index: int, mouse_button: int)
signal slot_pressed(index: int, action: String)
signal highlight_slot(index: int, highlight: bool)


func using_grid(using_grid: bool):
	grid = using_grid


## Multi-cell items slice their icon per grid cell. An item with no icon assigned
## still has to sit in the grid (it just shows an empty frame) — get_region()
## would call get_image() on a null texture and take the whole inventory down.
func set_icon_region(x, y):
	if item_data == null or item_data.icon == null:
		return
	var region = item_data.get_region(x, y)
	texture_rect.texture = ImageTexture.create_from_image(region)
	_apply_item_background(Vector2i(x, y), false)


func set_icon_region_rotated(x: int, y: int):
	if item_data == null or item_data.icon == null:
		return
	var region = item_data.get_region_rotated(x, y)
	texture_rect.texture = ImageTexture.create_from_image(region)
	_apply_item_background(Vector2i(x, y), false)


func set_hotbar_icon():
	texture_rect.texture = item_data.icon
	_apply_item_background(Vector2i.ZERO, true)


func set_slot_data(slot_data: InventorySlotPD, index: int, moving: bool, x_size: int):
	item_data = slot_data.inventory_item
	_apply_item_background(Vector2i.ZERO, true)
	if moving:
		slot_data.origin_index = index
		origin_index = index
	else:
		origin_index = slot_data.origin_index
	
	# Set quantity and ammo slots if they sit in the top right or bottom right of the grid
	check_if_top_right_slot(slot_data, index)
	check_if_bottom_right_slot(slot_data, index, x_size)
	
	if slot_data.quantity > 1 and quantity_slot:
		quantity_label.text = "x%s" % slot_data.quantity
		quantity_label.show()
	else:
		quantity_label.hide()
		
	# Check if item is a WIELDABLE
	if item_data.has_signal("charge_changed") and not item_data.no_reload and ammo_slot:
		charge_label.text = str(int(item_data.charge_current))
		if !item_data.charge_changed.is_connected(_on_charge_changed):
			item_data.charge_changed.connect(_on_charge_changed)
		charge_label.show()
	else:
		if item_data.has_signal("charge_changed") and item_data.charge_changed.is_connected(_on_charge_changed):
			item_data.charge_changed.disconnect(_on_charge_changed)
		charge_label.hide()

	# Overlays only belong on the item's origin cell — a multi-cell item would
	# otherwise stamp one on every cell it covers.
	var on_origin_cell: bool = not grid or index == slot_data.origin_index
	refresh_overlays(on_origin_cell)


## Corner badge + no-icon name fallback. Public so a slot that repaints without
## set_slot_data (e.g. EquipmentSlotUI's empty branch) can clear them.
func refresh_overlays(on_origin_cell: bool) -> void:
	if mod_badge != null:
		# Duck-typed on purpose: this addon-side slot stays independent of the
		# project's WieldableItemPD/AttachmentItemPD. Any item exposing a
		# non-empty `attachments` Dictionary gets the badge.
		var attachments = item_data.get("attachments") if item_data else null
		if on_origin_cell and attachments is Dictionary and not attachments.is_empty():
			mod_badge.text = "+%d" % attachments.size()
			mod_badge.show()
		else:
			mod_badge.hide()

	if name_fallback != null:
		if on_origin_cell and item_data != null and item_data.icon == null:
			name_fallback.text = item_data.name
			name_fallback.show()
		else:
			name_fallback.hide()


func _apply_item_background(cell_coords: Vector2i, use_full_border: bool):
	if not item_data:
		background_panel.hide()
		return

	var background_color: Color = item_data.get_slot_background_color()
	var background_style := background_panel.get_theme_stylebox("panel")
	var background_style_flat := background_style.duplicate() as StyleBoxFlat
	background_style_flat.bg_color = background_color
	_set_background_border(background_style_flat, cell_coords, use_full_border)
	background_panel.add_theme_stylebox_override("panel", background_style_flat)
	background_panel.show()


func _set_background_border(background_style_flat: StyleBoxFlat, cell_coords: Vector2i, use_full_border: bool):
	background_style_flat.border_color = Color.BLACK
	if use_full_border:
		background_style_flat.border_width_left = 1
		background_style_flat.border_width_top = 1
		background_style_flat.border_width_right = 1
		background_style_flat.border_width_bottom = 1
		return

	var item_sz := Vector2i(item_data.item_size)
	if is_rotated:
		item_sz = Vector2i(item_sz.y, item_sz.x)
	background_style_flat.border_width_left = 1 if cell_coords.x == 0 else 0
	background_style_flat.border_width_top = 1 if cell_coords.y == 0 else 0
	background_style_flat.border_width_right = 1 if cell_coords.x == item_sz.x - 1 else 0
	background_style_flat.border_width_bottom = 1 if cell_coords.y == item_sz.y - 1 else 0


func check_if_top_right_slot(slot_data: InventorySlotPD, index: int):
	if not item_data:
		return
	var eff := Vector2i(item_data.item_size)
	if is_rotated:
		eff = Vector2i(eff.y, eff.x)
	if index == slot_data.origin_index + eff.x - 1:
		quantity_slot = true


func check_if_bottom_right_slot(slot_data: InventorySlotPD, index: int, x_size: int):
	if not item_data:
		return
	var eff := Vector2i(item_data.item_size)
	if is_rotated:
		eff = Vector2i(eff.y, eff.x)
	if index == slot_data.origin_index + eff.x - 1 + ((eff.y - 1) * x_size):
		ammo_slot = true


func _on_charge_changed():
	if item_data.has_signal("charge_changed"): #Making sure this is a wieldable.
		charge_label.text = str(int(item_data.charge_current)) 


func _on_gui_input(event: InputEvent):
	# Setting SLOT GAMPEAD INTERACTIONS HERE
	if event.is_action_pressed("inventory_move_item"):
		slot_pressed.emit(get_index(), "inventory_move_item")
		highlight_slot.emit(get_index(), true)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_use_item"):
		print("Slot.gd: inventory_use_item pressed on slot ", get_index())
		slot_pressed.emit(get_index(), "inventory_use_item")
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_drop_item"):
		slot_pressed.emit(get_index(), "inventory_drop_item")
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_assign_item"):
		slot_pressed.emit(get_index(), "inventory_assign_item")
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_rotate_item"):
		slot_pressed.emit(get_index(), "inventory_rotate_item")
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_detach_item"):
		slot_pressed.emit(get_index(), "inventory_detach_item")
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_mod_item"):
		slot_pressed.emit(get_index(), "inventory_mod_item")
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("interact") or event.is_action_pressed("interact2"):
		get_viewport().set_input_as_handled()



func set_grabbed_dimensions():
	var item_size := Vector2i(item_data.item_size) if grid else Vector2i(1, 1)
	if is_rotated:
		item_size = Vector2i(item_size.y, item_size.x)
	size = Vector2i(64 * item_size.x, 64 * item_size.y)
	if is_rotated:
		# Show the full icon pre-rotated 90° CW to match the swapped footprint
		var img: Image = item_data.icon.get_image().duplicate()
		img.rotate_90(CLOCKWISE)
		texture_rect.texture = ImageTexture.create_from_image(img)
		_apply_item_background(Vector2i.ZERO, true)
	else:
		set_hotbar_icon()



func set_selection(is_selected : bool):
	print(name, ": set_selection called. selection panel should be visible. (is_selected = ", is_selected, ")")
	selection_panel.visible = is_selected


func _on_mouse_entered():
	grab_focus()
	
func _on_mouse_exited():
	release_focus()
	
func _on_hidden():
	release_focus()
	
func _on_focus_entered() -> void:
	Audio.play_sound(sound_highlight)
	highlight_slot.emit(get_index(), true)
	$Panel.show()

func _on_focus_exited() -> void:
	highlight_slot.emit(get_index(), false)
	$Panel.hide()
