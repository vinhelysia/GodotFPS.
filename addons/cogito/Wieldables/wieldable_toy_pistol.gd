extends CogitoWieldable

@export_group("Pistol Settings")
## Path to the projectile prefab scene
@export var projectile_prefab : PackedScene
## Speed the projectile spawns with
@export var projectile_velocity : float
## Node the projectile spawns at
@onready var bullet_point = %Bullet_Point

## The Field Of View change when aiming down sight. In degrees.
@export var ads_fov = 65
@export var default_position : Vector3

@export_group("Audio")
@export var sound_primary_use : AudioStream
@export var sound_secondary_use : AudioStream
@export var sound_reload : AudioStream

@export_group("Recoil Settings")
@export var recoil_values := Vector3(0.15, 0.08, 0.0)
@export var aim_recoil_values := Vector3(0.05, 0.03, 0.0)

const POOL_SIZE := 50
var projectile_pool := []
var _last_index := -1

var inventory_item_reference : WieldableItemPD


func _get_recoil_node():
	if not player_interaction_component:
		return null
	return player_interaction_component.get_parent().get_node_or_null("Body/Neck/Head/CameraRecoil")


func equip(_player_interaction_component: PlayerInteractionComponent):
	animation_player.play(anim_equip)
	player_interaction_component = _player_interaction_component
	var rn = _get_recoil_node()
	if rn:
		rn.set_recoil(recoil_values)
		rn.set_aim_recoil(aim_recoil_values)


func _ready() -> void:
	# Here, we pre-instantiate `POOL_SIZE` bullets and store them in the `bullets` array.
	for i in POOL_SIZE:
		projectile_pool.append(projectile_prefab.instantiate())


func get_projectile() -> Node3D:
	# Cycle the index between `0` (included) and `POOL_SIZE` (excluded).
	_last_index = wrapi(_last_index + 1, 0, POOL_SIZE)
	return projectile_pool[_last_index]


# This gets called by player interaction compoment when the wieldable is equipped and primary action is pressed
func action_primary(_passed_item_reference : InventoryItemPD, _is_released: bool):
	inventory_item_reference = _passed_item_reference
	
	if _is_released:
		return
	
	# Not firing if animation player is playing. This enforces fire rate.
	if animation_player.is_playing():
		return
	
	if inventory_item_reference.charge_current <= 0: # Can't fire if empty + send hint.
		inventory_item_reference.send_empty_hint()
		return
	
	# Sound and animation
	animation_player.play(anim_action_primary)
	audio_stream_player_3d.stream = sound_primary_use
	audio_stream_player_3d.play()
	
	_passed_item_reference.subtract(1) #Reducing ammo count

	var rn = _get_recoil_node()
	if rn: rn.recoil_fire(false)

	# Gettting camera_collision pos from player interaction component:
	var _camera_collision = player_interaction_component.Get_Camera_Collision()
	var Direction = (_camera_collision - bullet_point.get_global_transform().origin).normalized()
	
	# Spawning projectile
	var Projectile = get_projectile()
	bullet_point.add_child(Projectile)
	Projectile.set_global_position(Vector3(bullet_point.global_position.x,bullet_point.global_position.y,bullet_point.global_position.z))
	Projectile.global_transform.basis = bullet_point.global_transform.basis
	Projectile.damage_amount = _passed_item_reference.wieldable_damage
	Projectile.set_linear_velocity(Direction * projectile_velocity)
	Projectile.Direction = Direction
	Projectile.reparent(get_tree().get_current_scene())


func action_secondary(is_released:bool):
	var camera = get_viewport().get_camera_3d()
	if is_released:
		# ADS Camera Zoom OUT
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera,"fov", 75, ads_time)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(self,"position", default_position, ads_time)

		# Re-activating crosshair
		player_interaction_component.update_crosshair.emit(true)
	else:
		# ADS Camera Zoom IN
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera,"fov", ads_fov, ads_time)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(self,"position", Vector3(0,default_position.y,default_position.z), ads_time)

		# Deactivating crosshair
		player_interaction_component.update_crosshair.emit(false)


# Function called when wieldable reload is attempted
func reload():
	animation_player.play(anim_reload)
	audio_stream_player_3d.stream = sound_reload
	audio_stream_player_3d.play()
