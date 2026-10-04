extends Node3D

@export_range(0.05, 1.0) var minimum_brightness: float = 0.55
@export_range(0.03, 1.0) var update_interval: float = 0.12

@onready var light: OmniLight3D = $Light
@onready var model: MeshInstance3D = $Model/ceiling_bulb
@onready var timer: Timer = $Timer
var lens: StandardMaterial3D
var base_light_energy: float
var base_emission: float
var random := RandomNumberGenerator.new()

func _ready() -> void:
	random.randomize()
	base_light_energy = light.light_energy
	for surface in model.mesh.get_surface_count():
		var material: Material = model.get_active_material(surface)
		if material is StandardMaterial3D and material.emission_enabled:
			# Each fixture owns its brightness; shared GLB material remains unchanged.
			lens = material.duplicate()
			model.set_surface_override_material(surface, lens)
			base_emission = lens.emission_energy_multiplier
			break
	if lens == null:
		push_error("Flickering fixture has no emissive lens material")
		return
	timer.timeout.connect(_flicker)
	timer.start(update_interval)

func _flicker() -> void:
	var brightness: float = random.randf_range(0.88, 1.0)
	if random.randf() < 0.15:
		brightness = random.randf_range(minimum_brightness, 0.8)
	_apply_brightness(brightness)
	timer.start(update_interval * random.randf_range(0.65, 1.35))

func _apply_brightness(brightness: float) -> void:
	brightness = clampf(brightness, minimum_brightness, 1.0)
	light.light_energy = base_light_energy * brightness
	lens.emission_energy_multiplier = base_emission * brightness
