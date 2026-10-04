extends CanvasLayer
## Counts real elapsed time even though its parent raid world is disabled.

signal deployment_ready
signal quit_requested

var _deadline_ms: int = 0
var _counting: bool = false


func prepare(display_name: String) -> void:
	%Destination.text = display_name
	%Countdown.text = "Preparing deployment..."
	%QuitButton.disabled = true
	set_process(false)


func start_countdown(seconds: float) -> void:
	_deadline_ms = Time.get_ticks_msec() + int(maxf(seconds, 0.0) * 1000.0)
	_counting = true
	%QuitButton.disabled = false
	if seconds > 0.0:
		%QuitButton.grab_focus.call_deferred()
	set_process(true)
	_process(0.0)


func _process(_delta: float) -> void:
	if not _counting:
		return
	var seconds_left := maxf(float(_deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
	%Countdown.text = "DEPLOYING IN %d" % ceili(seconds_left)
	if seconds_left <= 0.0:
		_counting = false
		set_process(false)
		deployment_ready.emit()


func _on_quit_pressed() -> void:
	if not _counting:
		return
	_counting = false
	set_process(false)
	quit_requested.emit()
