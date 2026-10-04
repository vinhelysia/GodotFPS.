extends Control
## Presentation only. Hub owns saving, destination validation and scene changes.

signal deploy_requested
signal close_requested


func _ready() -> void:
	var commands: Array[Button] = [
		%TownButton, %DeployButton, $Backdrop/Center/Panel/Margin/Content/Buttons/CloseButton,
	]
	for command in commands:
		command.focus_entered.connect(_set_command_cursor.bind(command, true))
		command.focus_exited.connect(_set_command_cursor.bind(command, false))


func show_destination(display_name: String) -> void:
	%TownButton.text = "  " + display_name.to_upper()
	if %TownButton.has_focus():
		_set_command_cursor(%TownButton, true)
	%TownButton.button_pressed = true
	visible = true
	%TownButton.grab_focus.call_deferred()


func _set_command_cursor(command: Button, focused: bool) -> void:
	var label := command.text.trim_prefix("> ").trim_prefix("  ")
	if focused:
		command.text = "> " + label
	else:
		command.text = "  " + label


func _on_town_pressed() -> void:
	# Town is the only available destination in this first version.
	%TownButton.button_pressed = true


func _on_deploy_pressed() -> void:
	deploy_requested.emit()


func _on_close_pressed() -> void:
	close_requested.emit()
