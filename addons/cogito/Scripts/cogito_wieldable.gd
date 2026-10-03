extends Node3D
class_name CogitoWieldable

@export_group("General Wieldable Settings")
## Item resource that this wieldable refers to.
var item_reference : WieldableItemPD
## Visible parts of the wieldable. Used to hide/show on equip/unequip.
@export var wieldable_mesh : Node3D
## Time in seconds to fully aim down sights (ADS). Each weapon can override this.
@export var ads_time: float = 0.2

@export_group("Sprint Motion")
## Enables shared sprint motion on the Wieldables container for this wieldable.
@export var enable_sprint_motion: bool = false
## Container-space pose offset applied while sprinting.
@export var sprint_position_offset: Vector3 = Vector3(0.08, -0.1, 0.05)
## Container-space pose rotation applied while sprinting.
@export var sprint_rotation_offset_deg: Vector3 = Vector3(8.0, 0.0, 6.0)
## Time to tween into the sprint pose.
@export var sprint_enter_time: float = 0.12
## Time to tween back out of the sprint pose.
@export var sprint_exit_time: float = 0.1
## Additive procedural bob translation applied while sprinting.
@export var sprint_bob_position_amplitude: Vector3 = Vector3(0.006, 0.01, 0.0)
## Additive procedural bob rotation applied while sprinting.
@export var sprint_bob_rotation_amplitude_deg: Vector3 = Vector3(0.4, 0.0, 1.2)
## Oscillation speed for sprint bob.
@export var sprint_bob_speed: float = 9.0

@export_group("Animations")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio_stream_player_3d = $AudioStreamPlayer3D

@export var anim_equip: String = "equip"
@export var anim_unequip: String = "unequip"
@export var anim_action_primary: String = "action_primary"
@export var anim_action_secondary: String = "action_secondary"
@export var anim_reload: String = "reload"

var player_interaction_component : PlayerInteractionComponent

### Every wieldable needs the following functions:
### equip(_player_interaction_component), unequip(), action_primary(), action_secondary(), reload()

func _ready():
	if wieldable_mesh:
		wieldable_mesh.hide()


# Function called when wieldable is unequipped.
func equip(_player_interaction_component: PlayerInteractionComponent):
	animation_player.play(anim_equip)
	player_interaction_component = _player_interaction_component


# Function called when wieldable is unequipped.
func unequip():
	animation_player.play(anim_unequip)


# Primary action called by the Player Interaction Component when flashlight is wielded.
func action_primary(_passed_item_reference:InventoryItemPD, _is_released: bool):
	pass


# Secondary action called by the Player Interaction Component when flashlight is wielded.
func action_secondary(_is_released: bool):
	pass


# Function called when wieldable reload is attempted
func reload():
	pass


## Shared sprint-motion hook for ADS-capable wieldables.
func cancel_ads_for_sprint() -> void:
	pass


## Shared sprint-motion hook so the container can query ADS state safely.
func is_ads_active() -> bool:
	return false


## Shared sprint-motion hook so the container can stay out of local wieldable animations.
func should_suspend_container_motion() -> bool:
	return animation_player != null and animation_player.is_playing()
