extends Control
class_name DetectionIndicator
## Stealth "eye": reads the highest detection_level across all hostile NPC
## sensors and draws a ring that fills green -> yellow -> red as an enemy spots
## the player. Fixes the "Announce Change" gap — the player gets a warning
## between "unseen" and "shot at" instead of only finding out via incoming fire.
##
## ponytail: polls the npc_perception group each frame (a handful of NPCs).
## Fine at this scale; switch to a signal on the COMBAT rising edge if NPC
## counts ever get large.

const RADIUS: float = 20.0
const THICKNESS: float = 4.0
const SPOTTED_COLOR := Color(1.0, 0.15, 0.1)
const AWARE_COLOR := Color(1.0, 0.85, 0.1)
const FAINT_COLOR := Color(0.55, 1.0, 0.55)

## How fast the drawn value chases the real one, so the ring eases instead of
## snapping (nicer feel; the underlying detection is already smooth but can jump
## to 1.0 on a hit reaction).
@export var lerp_speed: float = 8.0

var _level: float = 0.0


func _process(delta: float) -> void:
	var target := _max_detection()
	_level = move_toward(_level, target, lerp_speed * delta) if target < _level \
			else lerpf(_level, target, clampf(lerp_speed * delta, 0.0, 1.0))
	queue_redraw()


func _max_detection() -> float:
	var m: float = 0.0
	for p in get_tree().get_nodes_in_group(&"npc_perception"):
		if p.has_method(&"is_hostile_sensor") and p.is_hostile_sensor():
			m = maxf(m, p.detection_level())
	return m


func _draw() -> void:
	if _level <= 0.02:
		return
	var center := size * 0.5
	var col: Color
	if _level >= 0.5:
		col = AWARE_COLOR.lerp(SPOTTED_COLOR, (_level - 0.5) * 2.0)
	else:
		col = FAINT_COLOR.lerp(AWARE_COLOR, _level * 2.0)
	col.a = clampf(_level + 0.25, 0.0, 1.0)

	# Backing ring (so the fill reads on any background).
	draw_arc(center, RADIUS, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.45 * col.a), THICKNESS + 2.0, true)
	# Fill sweeps clockwise from the top, proportional to detection.
	draw_arc(center, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * _level, 40, col, THICKNESS, true)
