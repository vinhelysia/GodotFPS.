extends CanvasLayer

signal retry_requested
signal quit_requested


func show_error() -> void:
	visible = true
	%RetryButton.grab_focus.call_deferred()


func _on_retry_pressed() -> void:
	retry_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
