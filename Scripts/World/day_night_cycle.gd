extends Node
## Scene-owned clock and lighting. Pauses with Town; no persistent world clock.

@export_range(1.0, 120.0, 1.0) var cycle_minutes: float = 30.0
@export_range(0.0, 24.0, 0.25) var start_hour: float = 8.0
@export var running: bool = true
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var night_lights: Array[Light3D] = []
@export_range(0.05, 2.0, 0.05) var update_interval: float = 0.25
@export_range(-180.0, 180.0, 1.0) var sun_azimuth: float = -35.0
@export var day_sun_energy: float = 1.15
@export var day_ambient_energy: float = 1.0
@export var night_ambient_energy: float = 0.65
@export var sun_day_color: Color = Color(0.9, 0.93, 1.0)
@export var sun_horizon_color: Color = Color(1.0, 0.67, 0.39)
@export var sky_day_color: Color = Color(0.55, 0.62, 0.7)
@export var horizon_day_color: Color = Color(0.7, 0.74, 0.78)
@export var sky_night_color: Color = Color(0.17, 0.2, 0.28)
@export var horizon_night_color: Color = Color(0.22, 0.25, 0.32)
@export var ambient_day_color: Color = Color(0.67, 0.73, 0.8)
@export var ambient_night_color: Color = Color(0.24, 0.32, 0.5)

var current_hour: float
var _night_energies: Array[float] = []
var _since_update: float = 0.0


func _ready() -> void:
	if sun == null or world_environment == null or world_environment.environment == null:
		push_error("DayNightCycle requires a sun and WorldEnvironment.")
		set_process(false)
		return
	# Avoid modifying a cached/shared Environment when a second Town is created.
	world_environment.environment = world_environment.environment.duplicate(true)
	for light in night_lights:
		_night_energies.append(light.light_energy if is_instance_valid(light) else 0.0)
	set_hour(start_hour)


func _process(delta: float) -> void:
	if not running:
		return
	current_hour = fposmod(current_hour + delta * 24.0 / (maxf(cycle_minutes, 1.0) * 60.0), 24.0)
	_since_update += delta
	if _since_update >= maxf(update_interval, 0.05):
		_since_update = 0.0
		_apply_lighting()


func set_hour(hour: float) -> void:
	if not is_finite(hour):
		push_warning("DayNightCycle ignored a non-finite hour.")
		return
	current_hour = fposmod(hour, 24.0)
	if is_instance_valid(world_environment) and world_environment.environment != null:
		_apply_lighting()


func _apply_lighting() -> void:
	# Options can replace this resource when AO is applied or restored.
	var environment := world_environment.environment
	var sky := environment.sky.sky_material as ProceduralSkyMaterial if environment.sky != null else null
	var elevation := sin((current_hour - 6.0) * TAU / 24.0)
	var daylight := smoothstep(-0.12, 0.18, elevation)
	sun.rotation_degrees = Vector3(-(current_hour - 6.0) * 15.0, sun_azimuth, 0.0)
	sun.light_energy = day_sun_energy * daylight
	sun.light_color = sun_horizon_color.lerp(sun_day_color, clampf(elevation, 0.0, 1.0))
	environment.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, daylight)
	environment.ambient_light_color = ambient_night_color.lerp(ambient_day_color, daylight)
	environment.fog_light_color = horizon_night_color.lerp(horizon_day_color, daylight)
	environment.fog_light_energy = lerpf(0.02, 0.6, daylight)
	if sky != null:
		sky.sky_top_color = sky_night_color.lerp(sky_day_color, daylight)
		sky.sky_horizon_color = horizon_night_color.lerp(horizon_day_color, daylight)
		sky.ground_horizon_color = sky.sky_horizon_color
	for index in night_lights.size():
		var light := night_lights[index]
		if is_instance_valid(light):
			light.light_energy = _night_energies[index] * (1.0 - daylight)
			light.visible = daylight < 0.99
