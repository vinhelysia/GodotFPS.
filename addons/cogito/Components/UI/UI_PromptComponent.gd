extends Control
class_name UiPromptComponent

@onready var interaction_button: Node = $HBoxContainer/Container/InteractionButton
@onready var interaction_text: RichTextLabel = $HBoxContainer/InteractionText
@onready var input_icon_container: Control = $HBoxContainer/Container

## Crosshair-centric prompts: the crosshair swapping to interaction_crosshair IS the
## "you can interact" signal, so a per-prompt key icon just repeats it. Label only.
## Set true to bring the key icons back.
@export var show_input_icon: bool = false

func set_prompt(interaction_name:String,input_map_name:String):
	# action_name stays set even when the icon is hidden — _unhandled_input() below and
	# UiHoldComponent.start_holding() both key off it.
	interaction_button.action_name = input_map_name
	interaction_text.text = interaction_name
	interaction_button.update_input_icon()
	input_icon_container.visible = show_input_icon


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(interaction_button.action_name):
		self_modulate = Color(0.059, 0.533, 0.482, 1.0)
	if event.is_action_released(interaction_button.action_name):
		self_modulate = Color.WHITE


func discard_prompt():
	#await get_tree().create_timer(.1).timeout
	queue_free()
