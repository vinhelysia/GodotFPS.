extends Node

## Renders inventory icons from geometry already in the project.
##
## Run (needs a REAL renderer — --headless uses the dummy driver and writes blank
## images):
##   godot --path . tools/render_item_icons.tscn
##
## Add a row to ICONS whenever a new attachment model lands: the source is either
## a scene to instance whole, or "scene.tscn::NodeName" to pull one MeshInstance3D
## out of a bigger scene. Everything else (framing, lighting, transparency) is
## handled here.

const SIZE: int = 256
const OUT_DIR := "res://Scene/Items/Attachments/"

## output png name -> source geometry
##
## Only the TAC30 has a clean, self-contained model today. Deliberately NOT here:
##   - the AK 30-round magazine: AK47.tscn's "7_62x39 ak47 mag 30rnd (steel)"
##     is a merged export — 3 surfaces spanning 1.52 units, carrying a magazine
##     plus two unrelated parts. Every surface renders the same cluttered blob,
##     so it needs splitting in Blender, not more code here.
##   - "ak47 muzzle brake": renders as an unrecognisable chunk; needs a proper
##     standalone model.
## The other 12 attachments have no geometry at all and stay on the name-fallback
## label until models land. Add a row per model as they arrive.
const ICONS := {
	"icon_tac30_scope.png":
		"res://Scene/Attachment/Scope/TAC30_1-4x24_riflescope/TAC30_1-4x24_riflescope.tscn",
}

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D


func _ready() -> void:
	_build_rig()
	for key in ICONS:
		var file_name := str(key)
		var subject := _load_subject(str(ICONS[key]))
		if subject == null:
			push_warning("render_item_icons: could not load %s" % str(ICONS[key]))
			continue
		_pivot.add_child(subject)
		_frame(subject)
		# Two frames: one to apply the transforms, one to render them.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		print("   (pivot children at capture: %d)" % _pivot.get_child_count())
		var path := OUT_DIR + file_name
		var err := image.save_png(path)
		print("%s  %s (%dx%d) opaque_px=%d" % ["ok  " if err == OK else "FAIL", path,
				image.get_width(), image.get_height(), _opaque_pixels(image)])
		# free(), not queue_free(): the deferred free lands too late and the previous
		# subject is still in frame when the next icon renders.
		subject.free()
	get_tree().quit()


## Cheap fingerprint of what actually landed in the image — a rig that renders
## nothing still saves a valid, empty PNG.
func _opaque_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				count += 1
	return count


func _build_rig() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	# Own world: otherwise the rig shares the main window's World3D and renders
	# whatever else happens to be in it.
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)

	# Three-quarter key light plus a fill, so a black suppressor doesn't render
	# as a black square on a transparent background.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -50, 0)
	key.light_energy = 1.6
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 140, 0)
	fill.light_energy = 0.7
	_viewport.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.9
	var camera_env := CameraAttributesPractical.new()
	_camera.environment = env
	_camera.attributes = camera_env


## Either a whole scene, or "path.tscn::NodeName" to lift one mesh out of it.
## Append "#N" to keep only surface N — several AK meshes are merged exports
## carrying unrelated parts in the same ArrayMesh (the 30-round magazine node
## holds 3 surfaces spanning 1.5 units), which renders as a cluttered icon.
func _load_subject(source: String) -> Node3D:
	if not source.contains("::"):
		return (load(source) as PackedScene).instantiate() as Node3D
	var parts := source.split("::")
	var node_name := parts[1]
	var surface := -1
	if node_name.contains("#"):
		var bits := node_name.split("#")
		node_name = bits[0]
		surface = int(bits[1])
	var host: Node3D = (load(parts[0]) as PackedScene).instantiate()
	var found := host.get_node_or_null(NodePath(node_name)) as MeshInstance3D
	var copy: MeshInstance3D = null
	if found != null and found.mesh != null:
		copy = MeshInstance3D.new()
		if surface < 0:
			copy.mesh = found.mesh
			for i in found.get_surface_override_material_count():
				copy.set_surface_override_material(i, found.get_surface_override_material(i))
		else:
			var single := ArrayMesh.new()
			single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, found.mesh.surface_get_arrays(surface))
			single.surface_set_material(0, found.mesh.surface_get_material(surface))
			copy.mesh = single
	host.free()
	return copy


## Points the camera at the subject from a three-quarter angle and zooms so the
## whole thing fits with a small margin, whatever scale the source model is at.
func _frame(subject: Node3D) -> void:
	var bounds := _bounds_of(subject)
	if bounds.size == Vector3.ZERO:
		return
	subject.position = -bounds.get_center()
	var radius: float = maxf(bounds.size.length() * 0.5, 0.001)
	_camera.size = radius * 2.1
	_camera.near = 0.001
	_camera.far = radius * 20.0
	var dir := Vector3(0.75, 0.45, 1.0).normalized()
	_camera.position = dir * radius * 4.0
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _bounds_of(node: Node3D) -> AABB:
	var total := AABB()
	var first := true
	var nodes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		nodes.append(node)
	for child in nodes:
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = (node.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total
