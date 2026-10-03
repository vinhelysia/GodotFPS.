extends Area3D

signal extraction_completed

@export_range(0.1, 60.0) var countdown_seconds: float = 5.0
@export var status_label: Label

var player: CogitoPlayer
var time_left: float = 0.0
var counting_down: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	status_label.hide()


func _on_body_entered(body: Node3D) -> void:
	if body is CogitoPlayer:
		player = body


func _on_body_exited(body: Node3D) -> void:
	if body == player:
		cancel_extraction()
		player = null
		status_label.hide()


func _physics_process(delta: float) -> void:
	if not _can_extract():
		cancel_extraction()
		status_label.hide()
		return
	status_label.show()
	if counting_down:
		time_left = maxf(0.0, time_left - delta)
		status_label.text = "Extracting: %.1f s — stay in the zone" % time_left
		if time_left == 0.0:
			cancel_extraction()
			extraction_completed.emit()
	else:
		var binding := InputHelper.get_keyboard_or_joypad_input_for_action("interact")
		status_label.text = "[%s] Extract — %.0f s" % [InputHelper.get_label_for_input(binding), countdown_seconds]
		if Input.is_action_just_pressed("interact"):
			start_extraction()


func _can_extract() -> bool:
	return is_instance_valid(player) and overlaps_body(player) \
		and not player.is_dead and player.player_attributes["health"].value_current > 0.0 \
		and not player.is_showing_ui and not player.is_movement_paused \
		and not CogitoSceneManager.is_currently_loading


func start_extraction() -> void:
	if _can_extract() and not counting_down:
		time_left = countdown_seconds
		counting_down = true


func cancel_extraction() -> void:
	counting_down = false
	time_left = 0.0
