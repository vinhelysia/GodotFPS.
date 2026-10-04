@tool
extends CogitoDoor

## Cogito interaction/save state, with poses restored from the imported door animation.
var _configuration_valid: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var native_body: Node3D = self
	if not native_body is AnimatableBody3D:
		_disable_interaction("Attach this script to the moving AnimatableBody3D pivot.")
		return

	# Validate before Cogito's get_node(animation_player), so a bad path stays inert.
	anim_player = get_node_or_null(animation_player) as AnimationPlayer
	if anim_player == null:
		_disable_interaction("animation_player must point to an AnimationPlayer.")
		return
	var animation_root := anim_player.get_node_or_null(anim_player.root_node)
	if animation_root == null or (animation_root != self and not animation_root.is_ancestor_of(self)):
		_disable_interaction("AnimationPlayer root_node must contain this door pivot.")
		return
	if door_type != DoorType.ANIMATED or reverse_opening_anim_for_close:
		_disable_interaction("Use ANIMATED with separate opening and closing clips.")
		return
	if get_node_or_null("AudioStreamPlayer3D") == null:
		_disable_interaction("The door requires a direct AudioStreamPlayer3D child.")
		return
	for clip_name: String in [opening_animation, closing_animation]:
		if clip_name.is_empty() or not anim_player.has_animation(clip_name):
			_disable_interaction("Missing door animation: " + clip_name)
			return
		var clip := anim_player.get_animation(clip_name)
		if clip.length <= 0.0 or clip.loop_mode != Animation.LOOP_NONE:
			_disable_interaction("Door animations must have positive length and must not loop: " + clip_name)
			return

	_configuration_valid = true
	super()
	anim_player.animation_finished.connect(_on_animation_finished)
	set_state()


func open_door(interactor: Node3D, swing_override: int = 0) -> void:
	if not _configuration_valid or is_open or anim_player.is_playing():
		return
	is_moving = true
	super(interactor, swing_override)


func close_door(interactor: Node3D) -> void:
	if not _configuration_valid or not is_open or anim_player.is_playing():
		return
	is_moving = true
	super(interactor)


func set_to_open_position() -> void:
	if _configuration_valid:
		_restore_animation_pose(anim_player.get_animation(opening_animation).length)


func set_to_closed_position() -> void:
	if _configuration_valid:
		_restore_animation_pose(0.0)


func _restore_animation_pose(time_seconds: float) -> void:
	# Restoring is a teleport. Motion sync would leave the old collider for one tick.
	var native_body: Node3D = self
	var body := native_body as AnimatableBody3D
	var was_synchronized := body.sync_to_physics
	var body_rid := body.get_rid()
	var previous_mode := PhysicsServer3D.body_get_mode(body_rid)
	body.sync_to_physics = false
	# Jolt queues kinematic targets. A static pose change applies the restore immediately.
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	# seek applies every imported track; stop(true) keeps that pose without playback.
	anim_player.play(opening_animation)
	anim_player.seek(time_seconds, true)
	anim_player.stop(true)
	body.force_update_transform()
	PhysicsServer3D.body_set_mode(body_rid, previous_mode)
	body.sync_to_physics = was_synchronized
	is_moving = false


func _on_animation_finished(clip_name: StringName) -> void:
	if clip_name == opening_animation or clip_name == closing_animation:
		is_moving = false


func _disable_interaction(message: String) -> void:
	push_error("%s: %s" % [get_path(), message])
	for component: InteractionComponent in find_children("", "InteractionComponent", true):
		component.is_disabled = true
