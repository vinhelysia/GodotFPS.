extends CanvasLayer

signal continue_requested
signal retry_save_requested


func show_result(extracted: bool, saved: bool) -> void:
	%Outcome.text = "Extracted" if extracted else "Dead"
	%GearSummary.text = "Carried kit kept.\nStash preserved." if extracted else "All carried gear lost.\nStash preserved."
	visible = true
	set_save_status(saved)


func set_save_status(saved: bool) -> void:
	%SaveStatus.text = "Progress saved." if saved else "Save failed — this result is not saved.\nRetry before leaving Hub."
	%RetrySaveButton.visible = not saved
	%ContinueButton.text = "Continue" if saved else "Continue (unsaved)"
	if visible:
		var button: Button = %ContinueButton if saved else %RetrySaveButton
		button.grab_focus.call_deferred()


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _on_retry_save_pressed() -> void:
	retry_save_requested.emit()
