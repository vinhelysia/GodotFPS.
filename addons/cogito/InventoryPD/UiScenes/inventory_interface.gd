extends Control

signal drop_slot_data(slot_data : InventorySlotPD)
signal inventory_open(is_true: bool)

@export var inventory_ui : Control
@onready var grabbed_slot_node = $GrabbedSlot
## Reparented (Player_HUD.tscn) into LayoutMargin/LayoutHBox/RightColumn so
## the corpse/chest pockets grid and equipment panel sit in one column
## instead of two independently-anchored floating blocks.
@onready var external_inventory_ui = $LayoutMargin/LayoutHBox/RightColumn/ExternalInventoryUI
## Shown alongside external_inventory_ui only for owners with a non-null
## `equipment` property (corpses) — see set_external_inventory(). Owners
## without one (fridge, chest, old containers) never touch this.
@onready var external_equipment_panel = $LayoutMargin/LayoutHBox/RightColumn/ExternalEquipmentPanel
## "POCKETS" section header above external_inventory_ui — only meaningful
## (and shown) alongside external_equipment_panel; see set_external_inventory().
@onready var external_pockets_header: Label = $LayoutMargin/LayoutHBox/RightColumn/ExternalPocketsHeader
@onready var hot_bar_inventory = $HotBarInventory
@onready var quick_slots : CogitoQuickslots = $QuickSlots
@onready var info_panel = $InfoPanel
@onready var item_name = $InfoPanel/MarginContainer/VBoxContainer/ItemName
@onready var item_description: Control = $InfoPanel/MarginContainer/VBoxContainer/ItemDescription
@onready var drop_prompt: Control = $InfoPanel/MarginContainer/VBoxContainer/HBoxDrop
## Keyboard hint for the mod bench, built in _ready() — see the note there.
var mod_prompt: Label
@onready var assign_prompt: Control = $InfoPanel/MarginContainer/VBoxContainer/HBoxAssign
@onready var use_prompt: Control = $InfoPanel/MarginContainer/VBoxContainer/HBoxUse
@onready var cogito_tab_menu: CogitoTabMenu = $LayoutMargin/LayoutHBox/CogitoTabMenu


## Sound that plays as a generic error.
@export var sound_error : AudioStream
@export var is_using_hotbar: bool = true

@export_group("Inventory Screen")
@export var nodes_to_show : Array[Node]
@export var nodes_to_hide : Array[Node]

var is_inventory_open : bool:
	set(value):
		is_inventory_open = value
		set_process_input(is_inventory_open)
		inventory_open.emit(is_inventory_open)
var grabbed_slot_data: InventorySlotPD
var external_inventory_owner : Node
var _external_inventory_button_press: Callable
var control_in_focus
## Weapon modding popup — instantiated in setup_equipment_ui(), hidden until a
## weapon slot is modded (inventory_mod_item). See attachment_panel.gd.
var attachment_panel: AttachmentPanel


func _ready():
	# Connect to signal that detects change of input device
	InputHelper.device_changed.connect(_on_input_device_change)
	# Calling this function once to set proper input icons
	_on_input_device_change(InputHelper.device,InputHelper.device_index)
	_external_inventory_button_press = on_inventory_button_press.bind(external_inventory_ui)

	is_inventory_open = false
	info_panel.hide()
	cogito_tab_menu.hide()

	grabbed_slot_node.set_mouse_filter(2) # Setting mouse filter to ignore.
	grabbed_slot_node.set_focus_mode(0) # Setting focus mode to none.
	grabbed_slot_node.visibility_changed.connect(update_grabbed_slot_position)

	# Register inventory_rotate_item if missing from project.godot (R key, same as reload —
	# safe because _input only fires when the inventory is open and consumes the event).
	if not InputMap.has_action("inventory_rotate_item"):
		InputMap.add_action("inventory_rotate_item")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event("inventory_rotate_item", ev)

	# Register inventory_detach_item if missing from project.godot (X key) —
	# same self-registration pattern as inventory_rotate_item above.
	if not InputMap.has_action("inventory_detach_item"):
		InputMap.add_action("inventory_detach_item")
		var ev_detach := InputEventKey.new()
		ev_detach.physical_keycode = KEY_X
		InputMap.action_add_event("inventory_detach_item", ev_detach)

	# Opens the weapon modding panel on the hovered/focused weapon (M key).
	if not InputMap.has_action("inventory_mod_item"):
		InputMap.add_action("inventory_mod_item")
		var ev_mod := InputEventKey.new()
		ev_mod.physical_keycode = KEY_M
		InputMap.action_add_event("inventory_mod_item", ev_mod)

	# ...and tell the player it exists. Hovering a weapon and pressing M was the
	# ONLY way into the mod bench, with no button, menu entry or hint anywhere on
	# screen. Built in code (not in Player_HUD.tscn) for the same reason the mod
	# panel itself is: the addon scene stays untouched. The existing HBox prompts
	# are mouse-button rows with key icons; a keyboard hint reads better as text.
	var info_rows := get_node_or_null("InfoPanel/MarginContainer/VBoxContainer")
	if info_rows:
		mod_prompt = Label.new()
		mod_prompt.name = "ModPrompt"
		mod_prompt.add_theme_font_size_override("font_size", 14)
		mod_prompt.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
		mod_prompt.hide()
		info_rows.add_child(mod_prompt)
	else:
		push_warning("inventory_interface: no InfoPanel rows — the mod-bench hint won't show.")

	# External equipment panel (corpses) — wired once here since the panel is
	# a static, always-present (hidden by default) node; set_external_inventory()
	# just rebinds WHICH CogitoEquipment its slots point to per owner.
	external_equipment_slots_ui = external_equipment_panel.collect_equipment_slots()
	for slot_id in external_equipment_slots_ui:
		var slot_node = external_equipment_slots_ui[slot_id]
		if not slot_node.equipment_slot_clicked.is_connected(_on_equipment_slot_pressed):
			slot_node.equipment_slot_clicked.connect(_on_equipment_slot_pressed)

	external_pockets_header.add_theme_font_size_override("font_size", EquipmentSlotUI.HEADER_FONT_SIZE)
	external_pockets_header.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)


func _on_input_device_change(_device, _device_index):
	if _device == "keyboard":
		drop_prompt.hide()
		assign_prompt.hide()
	else:
		drop_prompt.show()
		assign_prompt.show()


func open_inventory():
	if !is_inventory_open:
		is_inventory_open = true
		info_panel.hide()
		get_viewport().gui_focus_changed.connect(_on_focus_changed)
		#inventory_ui.show()
		#player_currencies_ui.show()
		
		for node in nodes_to_show:
			node.show()
		
		# Setting tab menu to the first tab (inventory)
		cogito_tab_menu.current_tab = 0
		
		if InputHelper.device_index != -1: # Check if gamepad is used
			inventory_ui.slot_array[0].grab_focus.call_deferred() # Grab focus of inventory slot for gamepad users.
#		inventory_interface.grabbed_slot_node.show()
#		inventory_interface.external_inventory_ui.show()

		for slot_panel in inventory_ui.slot_array:
			if !slot_panel.mouse_exited.is_connected(_slot_on_mouse_exit):
				slot_panel.mouse_exited.connect(_slot_on_mouse_exit)
	hot_bar_inventory.hide()


## Returns grabbed cursor item to player inventory. Fail-closed: only clears
## the cursor when quantity is fully consumed. Partial remainder stays grabbed.
func _try_return_grabbed_to_player() -> bool:
	if grabbed_slot_data == null:
		return true
	get_parent().player.inventory_data.pick_up_slot_data(grabbed_slot_data)
	if grabbed_slot_data.quantity <= 0:
		grabbed_slot_data = null
		update_grabbed_slot()
		return true
	update_grabbed_slot()
	return false


func close_inventory() -> bool:
	if not is_inventory_open:
		return true
	if not _try_return_grabbed_to_player():
		return false
	is_inventory_open = false
	get_viewport().gui_focus_changed.disconnect(_on_focus_changed)
	if control_in_focus:
		control_in_focus.release_focus()

	# Clearing out UI grabbed slot
	if inventory_ui.grabbed_slot:
		inventory_ui.detach_grabbed_slot()

	if attachment_panel:
		attachment_panel.close()

	for node in nodes_to_show:
		node.hide()
	#inventory_ui.hide()
	#player_currencies_ui.hide()

	if external_inventory_owner:
		external_inventory_owner.close()

	grabbed_slot_node.hide()
	info_panel.hide()
	external_inventory_ui.hide()
	external_equipment_panel.hide()
	external_pockets_header.hide()

	if is_using_hotbar:
		hot_bar_inventory.show()
	return true


func _on_focus_changed(control: Control):
	if !control.has_method("set_slot_data"):
		CogitoGlobals.debug_log(true,"inventory_interface.gd", "_on_focus_changed: Not a slot. returning.")
		return
	
	if control != null:
		control_in_focus = control
	
	# Quick check to see if this is a quickslot
	if control_in_focus.has_method("update_quickslot_data"):
		return
	
	if control_in_focus.item_data and !grabbed_slot_node.visible:
		item_name.text = control_in_focus.item_data.name
		item_description.text = control_in_focus.item_data.description
		info_panel.global_position = control_in_focus.global_position + Vector2(0,control_in_focus.size.y)
		
		if control_in_focus.item_data.is_droppable:
			drop_prompt.show()
		else: drop_prompt.hide()
		
		if !control_in_focus.item_data.has_method("use"):
			use_prompt.hide()
		else:
			use_prompt.show()

		_refresh_mod_prompt(control_in_focus.item_data)

		info_panel.show()
		if !control.mouse_exited.is_connected(_slot_on_mouse_exit):
			control.mouse_exited.connect(_slot_on_mouse_exit)
		
	else:
		info_panel.hide()
	
	# Updating the currently focused slot in the inventory_ui
	inventory_ui.currently_focused_slot = control_in_focus
	
	# How a grabbed item gets displayed.
	if grabbed_slot_node.visible:
		grabbed_slot_node.set_mouse_filter(2) # Setting mouse filter to ignore.
		grabbed_slot_node.set_focus_mode(0) # Setting focus mode to none.
		if InputHelper.device_index != -1: # Updating grabbed item position if using gamepad
			update_grabbed_slot_position()


## Only weapons can be modded, and only a weapon that carries something can have
## it stripped — so the hint says exactly what this item supports right now.
func _refresh_mod_prompt(item_data) -> void:
	if mod_prompt == null:
		return
	var weapon := item_data as WieldableItemPD
	if weapon == null:
		mod_prompt.hide()
		return
	mod_prompt.text = "[M] Modify   [X] Detach" if not weapon.attachments.is_empty() else "[M] Modify"
	mod_prompt.show()


func _slot_on_mouse_exit():
	info_panel.hide()


func update_grabbed_slot_position():
	# The grid frees and rebuilds every slot node on inventory_updated, so the
	# focused control can be gone (or never set) by the time the cursor ghost is
	# repositioned — dereferencing it then takes the whole inventory down.
	if control_in_focus == null or not is_instance_valid(control_in_focus):
		return
	grabbed_slot_node.global_position = control_in_focus.global_position + (control_in_focus.size / 2)


func _physics_process(_delta):
	if InputHelper.device_index == -1: #Checking for keyboard/mouse control.
		if grabbed_slot_node.visible:
			grabbed_slot_node.global_position = get_global_mouse_position() + Vector2(5, 5)
			return

		if info_panel.visible:
			info_panel.global_position = get_global_mouse_position() + Vector2(5, 5)


func set_external_inventory(_external_inventory_owner):
	if external_inventory_owner != _external_inventory_owner:
		clear_external_inventory()
	external_inventory_owner = _external_inventory_owner
	var inventory_data = external_inventory_owner.inventory_data

	inventory_data.owner = external_inventory_owner # Setting reference to external inventory owner node
#	inventory_data.inventory_interact.connect(on_inventory_interact)
	var inventory_button_callback := _external_inventory_button_press
	if not inventory_data.inventory_button_press.is_connected(inventory_button_callback):
		inventory_data.inventory_button_press.connect(inventory_button_callback)
	# No inventory_name here — the internal title label is legacy chrome
	# (see InventoryUI.gd); section headers now come from the column layout
	# ("POCKETS", a corpse's display_name strip on ExternalEquipmentPanel).
	external_inventory_ui.set_inventory_data(inventory_data)

	external_inventory_ui.show()
	external_inventory_ui.button_take_all.show()
	if !external_inventory_ui.button_take_all.pressed.is_connected(_on_take_all_pressed):
		external_inventory_ui.button_take_all.pressed.connect(_on_take_all_pressed)

	# Corpses (or anything else with a CogitoEquipment) additionally get an
	# equipment panel shown alongside the pockets grid above. Owners without
	# one (fridge, chest, old containers) leave this hidden — the flat-grid
	# path above is completely unchanged for them.
	var owner_equipment: Variant = external_inventory_owner.get("equipment")
	if owner_equipment is CogitoEquipment:
		for slot_id in external_equipment_slots_ui:
			external_equipment_slots_ui[slot_id].set_equipment(owner_equipment, self)
		var header: String = external_inventory_owner.display_name if external_inventory_owner.display_name != "" else "BODY"
		external_equipment_panel.set_header_text(header)
		external_equipment_panel.show()
		external_pockets_header.show()
	else:
		external_equipment_panel.hide()
		external_pockets_header.hide()


## Loot Component added
func get_external_inventory():
	return external_inventory_owner

func _on_take_all_pressed():
	var player = get_parent().player
	if not player:
		return

	var owner_equipment: Variant = external_inventory_owner.get("equipment")
	if owner_equipment is CogitoEquipment:
		_take_all_from_equipment(owner_equipment, player)

	external_inventory_owner.inventory_data.take_all_items(player.inventory_data)


## Best effort, equipment slots first then pockets (take_all_items() above,
## unchanged): unequip everything and try to place it on the player.
## PocketInventory.pick_up_slot_data() already does "equipment-routing first,
## pockets fallback" internally (and already fires the same auto-quickslot-
## bind signal on success for weapons), so this just has to sequence unequip
## -> try placing -> re-equip on failure. Whatever doesn't fit anywhere
## (player's own slots full too) stays equipped on the corpse.
func _take_all_from_equipment(source_equipment: CogitoEquipment, player: Node) -> void:
	var player_pockets: CogitoInventory = player.inventory_data
	for slot_id in source_equipment.slots.keys():
		var slot_data: InventorySlotPD = source_equipment.get_equipped(slot_id)
		if slot_data == null:
			continue
		source_equipment.unequip(slot_id)
		if not player_pockets.pick_up_slot_data(slot_data):
			source_equipment.equip(slot_id, slot_data)


func clear_external_inventory():
	if external_inventory_owner:
		var inventory_data = external_inventory_owner.inventory_data

#		inventory_data.inventory_interact.disconnect(on_inventory_interact)
		var inventory_button_callback := _external_inventory_button_press
		if inventory_data.inventory_button_press.is_connected(inventory_button_callback):
			inventory_data.inventory_button_press.disconnect(inventory_button_callback)
		for slot_node in external_equipment_slots_ui.values():
			slot_node.set_equipment(null, self)
		external_inventory_ui.inventory_name = ""
		external_inventory_ui.clear_inventory_data(inventory_data)
		external_inventory_ui.hide()
		external_equipment_panel.hide()
		external_pockets_header.hide()
		external_inventory_owner = null


var equipment_slots_ui: Dictionary = {}
var external_equipment_slots_ui: Dictionary = {}

func set_player_inventory_data(inventory_data : CogitoInventory):
	inventory_data.owner = CogitoSceneManager._current_player_node  # Setting player inventory owner reference to player node
	
#	inventory_data.inventory_interact.connect(on_inventory_interact)
	if !inventory_data.inventory_button_press.is_connected(on_inventory_button_press):
		inventory_data.inventory_button_press.connect(on_inventory_button_press.bind(inventory_ui))
	inventory_ui.set_inventory_data(inventory_data)
	if !is_using_hotbar:
		quick_slots.show()
		# Quickslots need reference to inventory when quickslot buttons are pressed
		quick_slots.inventory_reference = inventory_data
	else:
		quick_slots.hide()
	if !inventory_open.is_connected(quick_slots.update_inventory_status):
		inventory_open.connect(quick_slots.update_inventory_status)
	grabbed_slot_node.using_grid(inventory_data.grid)

	setup_equipment_ui()
	var player = CogitoSceneManager._current_player_node
	if player and player.get("equipment") != null:
		for slot_id in equipment_slots_ui:
			var slot_node = equipment_slots_ui[slot_id]
			slot_node.set_equipment(player.equipment, self)
			if not slot_node.equipment_slot_clicked.is_connected(_on_equipment_slot_pressed):
				slot_node.equipment_slot_clicked.connect(_on_equipment_slot_pressed)


func setup_equipment_ui():
	var player_inv_tab = get_node_or_null("LayoutMargin/LayoutHBox/CogitoTabMenu/TAB_player_inventory")
	if not player_inv_tab:
		return

	if player_inv_tab.has_node("EquipmentPanel"):
		return

	# Pockets now live as static siblings below the panel (PocketsHeader,
	# InventoryUI, PlayerCurrencies) instead of being swept into the panel's
	# own pockets placeholder — the column is too narrow (~460px) for the
	# equipment+pockets side-by-side layout, so show_pockets is off and the
	# panel is just inserted above them.
	var equip_panel = load("res://Scripts/Inventory/EquipmentPanel.tscn").instantiate()
	equip_panel.name = "EquipmentPanel"
	equip_panel.show_pockets = false
	player_inv_tab.add_child(equip_panel) # Enters tree now, so its @onready vars resolve.
	player_inv_tab.move_child(equip_panel, 0)

	equipment_slots_ui = equip_panel.collect_equipment_slots()

	var pockets_header: Label = player_inv_tab.get_node_or_null("PocketsHeader")
	if pockets_header:
		pockets_header.add_theme_font_size_override("font_size", EquipmentSlotUI.HEADER_FONT_SIZE)
		pockets_header.add_theme_color_override("font_color", EquipmentSlotUI.COLOR_HEADER_TEXT)

	setup_attachment_panel()


## Weapon modding popup. Added straight under InventoryInterface (not into a
## column) so it floats over the layout, and inserted right after LayoutMargin
## so GrabbedSlot and InfoPanel still draw on top of it. Its slots are plain
## EquipmentSlotUIs, so they route through the same _on_equipment_slot_pressed
## handler as the gear panel — only the bound CogitoEquipment differs.
func setup_attachment_panel() -> void:
	if attachment_panel != null:
		return
	attachment_panel = load("res://Scripts/Inventory/AttachmentPanel.tscn").instantiate()
	attachment_panel.name = "AttachmentPanel"
	add_child(attachment_panel)
	move_child(attachment_panel, get_node("LayoutMargin").get_index() + 1)

	for slot_node in attachment_panel.collect_slots().values():
		if not slot_node.equipment_slot_clicked.is_connected(_on_equipment_slot_pressed):
			slot_node.equipment_slot_clicked.connect(_on_equipment_slot_pressed)


## Opens/toggles the modding panel for whatever weapon is in the given slot.
func _mod_weapon_in_slot(slot_data: InventorySlotPD) -> void:
	if attachment_panel == null or slot_data == null:
		return
	var weapon_item := slot_data.inventory_item as WieldableItemPD
	if weapon_item == null:
		Audio.play_sound(sound_error)
		return
	# Attachments always come from / return to the player's pockets, even when
	# the weapon being modded is still lying on a corpse.
	attachment_panel.toggle(weapon_item, get_parent().player.inventory_data, self)


# Inventory handling on gamepad buttons
func on_inventory_button_press(inventory_data: CogitoInventory, index: int, action: String, local_inventory_ui):
	match [grabbed_slot_data, action]:
		[null, "inventory_move_item"]:
			# Check if item is being wielded before grabbing it.
			var temp_slot_data = inventory_data.get_slot_data(index)
			if temp_slot_data and temp_slot_data.inventory_item and temp_slot_data.inventory_item.is_being_wielded:
					Audio.play_sound(sound_error)
					CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't move item while its being wielded.")
			else:
				grabbed_slot_data = inventory_data.grab_slot_data(index)
		[_, "inventory_move_item"]:
			grabbed_slot_data = inventory_data.drop_slot_data(grabbed_slot_data, index)
		[null, "inventory_use_item"]:
			inventory_data.use_slot_data(index)
		[_, "inventory_use_item"]:
			print("Inventory_interface.gd: Gamepad use_item pressed while grabbed_slot_data. Calling drop_single_slot_data...")
			grabbed_slot_data = inventory_data.drop_single_slot_data(grabbed_slot_data, index)
		[null, "inventory_drop_item"]:
			var slot_to_drop = inventory_data.get_slot_data(index)
			if slot_to_drop:
				if !slot_to_drop.inventory_item.is_droppable:
					CogitoGlobals.debug_log(true, "inventory_interface.gd", "Item is not droppable.")
					Audio.play_sound(sound_error)
					return
				if slot_to_drop.inventory_item.has_method("update_wieldable_data") and slot_to_drop.inventory_item.is_being_wielded:
					Audio.play_sound(sound_error)
					CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop while wielding this item.")
				elif not slot_to_drop.inventory_item.drop_scene or slot_to_drop.inventory_item.drop_scene == "":
					Audio.play_sound(sound_error)
					get_parent().player.player_interaction_component.send_hint(null, "This item cannot be dropped (no drop scene configured).")
				else:
					if Input.is_key_pressed(KEY_CTRL):
						_show_drop_quantity_dialog(inventory_data, index, slot_to_drop)
					else:
						CogitoGlobals.debug_log(true, "inventory_interface.gd", "Dropping entire stack via keyboard/gamepad")
						var drop_data = slot_to_drop.duplicate()
						inventory_data.remove_slot_data(slot_to_drop)
						
						if not _drop_item(drop_data):
							Audio.play_sound(sound_error)
							inventory_data.pick_up_slot_data(drop_data)
							get_parent().player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
							CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop because there isn't enough space.")
						grabbed_slot_data = null
		
		[null, "inventory_assign_item"]: # Pressing "Assign quickslot" on gamepad
			CogitoGlobals.debug_log(true, "inventory_interface.gd", "Grabbing focus of quickslots.")
			grabbed_slot_data = inventory_data.grab_slot_data(index)
			quick_slots.quickslot_containers[0].grab_focus.call_deferred()
			
		[_, "inventory_assign_item"]: # When player cancels out assigning a quickslot on gamepad
			_try_return_grabbed_to_player()
		
		[_, "inventory_drop_item"]:
			Audio.play_sound(sound_error)
			CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop while moving an item.")
		[_, "inventory_rotate_item"]:
			rotate_item()
		[null, "inventory_detach_item"]:
			_detach_from_weapon_slot(inventory_data.get_slot_data(index))
			inventory_data.inventory_updated.emit(inventory_data)
		[null, "inventory_mod_item"]:
			_mod_weapon_in_slot(inventory_data.get_slot_data(index))

	# When connecting to the signal, we have bind the inventory_ui so we can use that to set focus.
	local_inventory_ui.slot_array[index].grab_focus()
	update_grabbed_slot()


## equipment_instance is whichever CogitoEquipment the clicked slot is bound
## to (player's or a corpse's — see equipment_slot_ui.gd's set_equipment()).
## "use"/"drop" only make sense for the player's own gear, so those actions
## are rejected outright for any other instance; "move" (the drag flow) works
## for both, letting items cross between the player and a corpse's equipment.
func _on_equipment_slot_pressed(equipment_instance: CogitoEquipment, slot_id: StringName, action: String):
	if equipment_instance == null:
		return
	var player = get_parent().player
	if not player or not player.get("equipment"):
		return

	# Guard by INSTANCE identity, not slot_id — "primary_1" etc. is the same
	# string whether it's the player's slot or a corpse's.
	var is_player_equipment: bool = equipment_instance == player.equipment

	# "move" crosses ownership (looting), and "mod" only opens a panel — both are
	# allowed on a corpse's gear. "use"/"drop" stay player-only.
	if not is_player_equipment and action != "inventory_move_item" and action != "inventory_mod_item":
		Audio.play_sound(sound_error)
		update_grabbed_slot()
		return

	match [grabbed_slot_data, action]:
		[null, "inventory_move_item"]:
			var slot_to_grab = equipment_instance.get_equipped(slot_id)
			if slot_to_grab:
				if slot_to_grab.inventory_item and slot_to_grab.inventory_item.is_being_wielded:
					Audio.play_sound(sound_error)
					player.player_interaction_component.send_hint(null, "Can't move item while it is being wielded.")
				else:
					grabbed_slot_data = equipment_instance.unequip(slot_id)
			else:
				Audio.play_sound(sound_error)
		[_, "inventory_move_item"]:
			# Dropping an attachment onto an equipped weapon attaches it
			# (player equipment only — corpse equipment is move-only, but the
			# attach is a safe convenience there too).
			var equipped := equipment_instance.get_equipped(slot_id)
			if grabbed_slot_data.inventory_item is AttachmentItemPD \
					and equipped and equipped.inventory_item is WieldableItemPD:
				grabbed_slot_data = player.inventory_data._attach_to_weapon(grabbed_slot_data, equipped.inventory_item)
			elif equipment_instance.can_equip(slot_id, grabbed_slot_data):
				var newly_equipped := grabbed_slot_data
				grabbed_slot_data = equipment_instance.equip(slot_id, grabbed_slot_data)
				# Player-only auto-quickslot-bind, mirroring PocketInventory
				# .pick_up_slot_data()'s auto-equip routing (which emits this
				# same signal when a weapon lands in an equipment slot via
				# the pockets grid). This covers the OTHER path — dragging
				# straight onto the equipment panel — so both paths behave
				# consistently. Never fires for a corpse (guarded above).
				if is_player_equipment:
					_notify_player_equipped(newly_equipped)
			else:
				Audio.play_sound(sound_error)
		[null, "inventory_use_item"]:
			var slot_data = equipment_instance.get_equipped(slot_id)
			if slot_data and slot_data.inventory_item and slot_data.inventory_item.has_method("use"):
				slot_data.inventory_item.use(player)
		[_, "inventory_use_item"]:
			Audio.play_sound(sound_error)
		[null, "inventory_drop_item"]:
			var slot_to_drop = equipment_instance.get_equipped(slot_id)
			if slot_to_drop:
				if slot_to_drop.inventory_item.has_method("update_wieldable_data") and slot_to_drop.inventory_item.is_being_wielded:
					Audio.play_sound(sound_error)
					player.player_interaction_component.send_hint(null, "Can't drop while wielding this item.")
				elif not slot_to_drop.inventory_item.drop_scene or slot_to_drop.inventory_item.drop_scene == "":
					Audio.play_sound(sound_error)
					player.player_interaction_component.send_hint(null, "This item cannot be dropped (no drop scene configured).")
				else:
					var drop_data = slot_to_drop.duplicate()
					equipment_instance.unequip(slot_id)
					if not _drop_item(drop_data):
						Audio.play_sound(sound_error)
						equipment_instance.equip(slot_id, drop_data)
						player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
		[_, "inventory_drop_item"]:
			Audio.play_sound(sound_error)
		[null, "inventory_detach_item"]:
			_detach_from_weapon_slot(equipment_instance.get_equipped(slot_id))
		[null, "inventory_mod_item"]:
			_mod_weapon_in_slot(equipment_instance.get_equipped(slot_id))

	update_grabbed_slot()


## Detaches the next attachment (enum order) from the weapon in slot_data and
## puts it into the player's pockets. One attachment per press.
func _detach_from_weapon_slot(slot_data: InventorySlotPD) -> void:
	var player = get_parent().player
	if slot_data == null or player == null:
		return
	var weapon_item := slot_data.inventory_item as WieldableItemPD
	if weapon_item == null or weapon_item.is_being_wielded or weapon_item.attachments.is_empty():
		Audio.play_sound(sound_error)
		return

	# A detached magazine keeps the rounds it was feeding, so there is nothing to
	# spill and no reason to refuse for lack of pocket space. If the magazine
	# itself doesn't fit, the fallback below puts it straight back on the weapon.
	var attachment: AttachmentItemPD = weapon_item.detach_next()
	if attachment == null:
		Audio.play_sound(sound_error)
		return
	var attachment_slot_data := InventorySlotPD.new()
	attachment_slot_data.inventory_item = attachment
	attachment_slot_data.quantity = 1
	if player.inventory_data.pick_up_slot_data(attachment_slot_data):
		player.player_interaction_component.send_hint(null, "Detached: " + attachment.name)
	else:
		# No pocket space — put it back on the weapon instead of losing it.
		weapon_item.try_attach(attachment)
		Audio.play_sound(sound_error)
		player.player_interaction_component.send_hint(null, "Not enough space to detach " + attachment.name + ".")


## Mirrors PocketInventory.pick_up_slot_data()'s auto-quickslot-bind signal
## for weapons equipped via a path that doesn't go through pick_up_slot_data
## (dragging straight onto the equipment panel). Only ever called for the
## player's own equipment (see the is_player_equipment guard at the call
## site) — never for a corpse's.
func _notify_player_equipped(slot_data: InventorySlotPD) -> void:
	if slot_data == null:
		return
	var inv_data: Variant = inventory_ui.get("loaded_inventory_data")
	if inv_data is CogitoInventory:
		inv_data.picked_up_new_inventory_item.emit(slot_data)


func update_grabbed_slot():
	if grabbed_slot_data:
		grabbed_slot_node.show()
		grabbed_slot_node.is_rotated = grabbed_slot_data.is_rotated
		grabbed_slot_node.set_slot_data(grabbed_slot_data, grabbed_slot_node.get_index(), true, 0)
		inventory_ui.grabbed_slot = grabbed_slot_node
		if external_inventory_ui.visible:
			external_inventory_ui.grabbed_slot = grabbed_slot_node
		grabbed_slot_node.set_grabbed_dimensions()
	else:
		grabbed_slot_node.hide()
		inventory_ui.detach_grabbed_slot()
		external_inventory_ui.detach_grabbed_slot()

	# Mod bench marks which of its slots would take the item now on the cursor.
	if attachment_panel:
		attachment_panel.refresh_compat_highlight(grabbed_slot_data)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_rotate_item") and grabbed_slot_data:
		get_viewport().set_input_as_handled()
		rotate_item()


func rotate_item() -> void:
	if not grabbed_slot_data:
		return
	var item_size := grabbed_slot_data.inventory_item.item_size
	if item_size.x == item_size.y:
		return
	grabbed_slot_data.is_rotated = not grabbed_slot_data.is_rotated
	update_grabbed_slot()


func _on_bind_grabbed_slot_to_quickslot(quickslotcontainer: CogitoQuickslotContainer):
	if grabbed_slot_data:
		CogitoGlobals.debug_log(true, "inventory_interface.gd", "Binding to quickslot container: " + str(grabbed_slot_data) + " -> " + str(quickslotcontainer) )
		#get_parent().player.inventory_data.pick_up_slot_data(grabbed_slot_data) #Swapped with line below
		quick_slots.bind_to_quickslot(grabbed_slot_data, quickslotcontainer)
		
		#inventory_ui.detach_grabbed_slot()
		#grabbed_slot_data = null
		#update_grabbed_slot()
	else:
		CogitoGlobals.debug_log(true, "inventory_interface.gd", "No grabbed slot data.")


# Grabbed slot data handling for mouse buttons
func _on_gui_input(event):
	if event is InputEventMouseButton \
		and event.is_pressed() \
		and grabbed_slot_data:
			
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if !grabbed_slot_data.inventory_item.is_droppable:
						Audio.play_sound(sound_error)
						CogitoGlobals.debug_log(true, "inventory_interface.gd", "This item isn't droppable.")
						return
					if grabbed_slot_data.inventory_item.has_method("update_wieldable_data") and grabbed_slot_data.inventory_item.is_being_wielded:
					#if grabbed_slot_data.inventory_item.ItemType.WIELDABLE and grabbed_slot_data.inventory_item.is_being_wielded:
						Audio.play_sound(sound_error)
						CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop while wielding this item.")
					else:
						var drop_data = grabbed_slot_data.duplicate()
						if not _drop_item(drop_data):
							Audio.play_sound(sound_error)
							get_parent().player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
							CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop because there isn't enough space.")
						else:
							grabbed_slot_data = null
					
				MOUSE_BUTTON_RIGHT:
					if !grabbed_slot_data.inventory_item.is_droppable:
						CogitoGlobals.debug_log(true, "inventory_interface.gd", "This item isn't droppable.")
						return
					if grabbed_slot_data.inventory_item.has_method("update_wieldable_data") and grabbed_slot_data.inventory_item.is_being_wielded:
						Audio.play_sound(sound_error)
						CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop while wielding this item.")
					else:
						var drop_data = grabbed_slot_data.create_single_slot_data(grabbed_slot_data.origin_index)
						if not _drop_item(drop_data):
							Audio.play_sound(sound_error)
							grabbed_slot_data.quantity += 1 # Refund the 1 item
							get_parent().player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
							CogitoGlobals.debug_log(true, "inventory_interface.gd", "Can't drop because there isn't enough space.")
						else:
							if grabbed_slot_data.quantity < 1:
								grabbed_slot_data = null
					
			update_grabbed_slot()


func _on_visibility_changed():
	# drop_slot_data is a no-op on the HUD side — return to inventory instead.
	if not visible and grabbed_slot_data:
		_try_return_grabbed_to_player()


func _on_inventory_ui_hidden() -> void:
	# Hides item info panel if the inventory UI screen gets hidden.
	info_panel.hide()


func _drop_item(slot_data: InventorySlotPD) -> bool:
	if not slot_data or not slot_data.inventory_item:
		return false
	if not slot_data.inventory_item.drop_scene or slot_data.inventory_item.drop_scene == "":
		push_error("inventory_interface.gd: drop_scene is not configured on " + slot_data.inventory_item.name)
		return false

	var player = get_parent().player
	var shape_cast = player.item_drop_shapecast
	var item_drop_distance_offset = player.get_node(player.player_hud).item_drop_distance_offset
	
	var scene_to_drop = load(slot_data.inventory_item.drop_scene)
	var dropped_item = scene_to_drop.instantiate()
		
	if not (dropped_item is CogitoObject):
		dropped_item.queue_free()
		return false
		
	var original_target_position: Vector3 = shape_cast.target_position
	
	var drop_radius: float = max(slot_data.inventory_item.item_drop_size, 0.05)
	var player_radius: float = player.radius
	var minimum_center_distance: float = player_radius + drop_radius
	
	shape_cast.configure_drop_probe(drop_radius)
	shape_cast.add_exception(player)
	
	# Overlap check — check if player is standing in geometry
	shape_cast.target_position = Vector3(0.0, 0.0, -0.001)
	shape_cast.force_shapecast_update()
	if shape_cast.is_colliding():
		shape_cast.target_position = original_target_position
		dropped_item.queue_free()
		return false
		
	var configured_distance: float = abs(original_target_position.z - item_drop_distance_offset)
	# probe_distance may be larger than configured_distance for large items —
	# this is intentional: large items need more clearance than the default drop distance.
	var probe_distance: float = max(configured_distance, minimum_center_distance + 0.25)
	
	# Forward space check
	shape_cast.target_position = Vector3(0.0, 0.0, -probe_distance)
	shape_cast.force_shapecast_update()
	var safe_fraction: float = shape_cast.get_closest_collision_safe_fraction()
	var safe_drop_distance: float = probe_distance * safe_fraction
	if safe_drop_distance < minimum_center_distance:
		shape_cast.target_position = original_target_position
		dropped_item.queue_free()
		return false
		
	# Compute final spawn position using ShapeCast forward direction
	var cast_forward: Vector3 = -shape_cast.global_transform.basis.z
	var final_drop_pos: Vector3 = shape_cast.global_position + safe_drop_distance * cast_forward
	
	# Restore target position before spawning
	shape_cast.target_position = original_target_position

	CogitoSceneManager._current_scene_root_node.add_child(dropped_item)
	dropped_item.global_rotation = player.body.global_rotation
	dropped_item.position = final_drop_pos

	Audio.play_sound(slot_data.inventory_item.sound_drop)

	dropped_item.find_interaction_nodes()
	for node in dropped_item.interaction_nodes:
		if "slot_data" in node:
			node.slot_data = slot_data

	return true


func _show_drop_quantity_dialog(inventory_data: CogitoInventory, index: int, slot_to_drop: InventorySlotPD):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Drop Quantity"
	
	# Add a margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "Select quantity of " + slot_to_drop.inventory_item.name + " to drop (1 - " + str(slot_to_drop.quantity) + "):"
	vbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.min_value = 1
	spinbox.max_value = slot_to_drop.quantity
	spinbox.value = 1
	spinbox.rounded = true
	spinbox.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(spinbox)
	
	margin.add_child(vbox)
	dialog.add_child(margin)
	
	# Connect to dialog confirmed signal
	dialog.confirmed.connect(func():
		var quantity_to_drop = int(spinbox.value)
		if quantity_to_drop > 0 and quantity_to_drop <= slot_to_drop.quantity:
			_perform_drop_quantity(inventory_data, index, slot_to_drop, quantity_to_drop)
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 120))


func _perform_drop_quantity(inventory_data: CogitoInventory, index: int, slot_to_drop: InventorySlotPD, quantity_to_drop: int):
	if quantity_to_drop == slot_to_drop.quantity:
		var drop_data = slot_to_drop.duplicate()
		inventory_data.remove_slot_data(slot_to_drop)
		if not _drop_item(drop_data):
			Audio.play_sound(sound_error)
			inventory_data.pick_up_slot_data(drop_data)
			get_parent().player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
	else:
		var drop_data = slot_to_drop.duplicate()
		drop_data.quantity = quantity_to_drop
		
		# Deduct from inventory slot
		slot_to_drop.quantity -= quantity_to_drop
		inventory_data.inventory_updated.emit(inventory_data)
		
		if not _drop_item(drop_data):
			Audio.play_sound(sound_error)
			slot_to_drop.quantity += quantity_to_drop
			inventory_data.inventory_updated.emit(inventory_data)
			get_parent().player.player_interaction_component.send_hint(null, "Not enough space to drop item.")
