extends ShapeCast3D

## Default assumed radius for sphere shape.
@export var sphere_shape_default_radius : float = 0.5
## Default assumed multiplier for shape (applied margin = item_size * margin_multiplier)
@export var margin_multiplier : float = 0.1

## Configure the drop probe shape to a sphere with the given radius.
## Call force_shapecast_update() is included — callers may call it again
## after setting target_position if needed.
func configure_drop_probe(radius: float) -> void:
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	margin = radius * margin_multiplier
	shape = sphere_shape
	force_shapecast_update()


## Helper function to always get raycast destination point
func get_shapecast_item_drop_position(distance_offset: float, _item_size: float = sphere_shape_default_radius) -> Vector3:
	var new_sphereshape : SphereShape3D = SphereShape3D.new()
	new_sphereshape.radius = _item_size
	new_sphereshape.margin = _item_size * margin_multiplier
	shape = new_sphereshape
	
	var shapecast_safety_offset = get_closest_collision_safe_fraction()
	var destination_point = self.global_position + (self.target_position.z - distance_offset) * get_viewport().get_camera_3d().get_global_transform().basis.z
	return destination_point
