extends PanelContainer

@onready var wieldable_icon: TextureRect = $MarginContainer/VBoxContainer/WieldableData/WieldableIcon
@onready var wieldable_charge_label: Label = $MarginContainer/VBoxContainer/WieldableData/WieldableChargeLabel
@onready var ammo_icon: TextureRect = $MarginContainer/VBoxContainer/AmmoData/AmmoIcon
@onready var ammo_label: Label = $MarginContainer/VBoxContainer/AmmoData/AmmoLabel

@onready var ammo_data: HBoxContainer = $MarginContainer/VBoxContainer/AmmoData


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Function to update the displayed numbers and icons
func update_wieldable_data(wieldable_item: WieldableItemPD, _carried_ammo:int, _ammo_item: AmmoItemPD):
	if wieldable_item.wieldable_data_icon:
		wieldable_icon.texture = wieldable_item.wieldable_data_icon
	else:
		wieldable_icon.texture = wieldable_item.icon
		
	if wieldable_item.no_reload:
		wieldable_charge_label.text = ""
	else:
		var display_text : String = str(int(wieldable_item.charge_current))
		# Read metadata if firearm mechanics are configured
		if wieldable_item.has_meta("magazine_capacity") and wieldable_item.has_meta("chamber_capacity"):
			var mag_cap : int = wieldable_item.get_meta("magazine_capacity")
			var cham_cap : int = wieldable_item.get_meta("chamber_capacity")
			var current : int = int(wieldable_item.charge_current)
			# Only display as mag+chamber when weapon is fully loaded (mag full + chamber loaded)
			if current == mag_cap + cham_cap and cham_cap > 0:
				display_text = str(mag_cap) + "+" + str(cham_cap)
		wieldable_charge_label.text = display_text
	
	# Hides ammo data ui elements if player doesn't have any ammo in their inventory (or if wieldable doesn't use ammo)
	if _ammo_item:
		ammo_data.show()
		ammo_icon.texture = _ammo_item.icon
		ammo_label.text = str(_carried_ammo)
	else:
		ammo_data.hide()
	
