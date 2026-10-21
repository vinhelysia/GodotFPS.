extends RefCounted
## Editor-only writer: saves static ground cover from the reviewed placement data.

const PLAN_PATH := "res://design/town-500m/phase9/vegetation-plan.json"
const OUTPUT_PATH := "res://Scene/World/Town500m/Art/GroundArt/ground_cover.tscn"


func build() -> Dictionary:
	assert(Engine.is_editor_hint() and not EditorInterface.is_playing_scene())
	assert(not OUTPUT_PATH in EditorInterface.get_open_scenes(), "Close the generated scene before replacing it")
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	assert(plan is Dictionary and plan.schema_version == 1 and plan.unit_scale)
	var root := Node3D.new()
	root.name = "TownGroundCover"
	root.set_meta("placement_plan", PLAN_PATH)
	root.set_meta("placement_sha256", FileAccess.get_sha256(PLAN_PATH))
	root.set_meta("visual_only", true)
	var rows := []
	var meshes_by_kind_height := {}
	var grass_material := StandardMaterial3D.new()
	grass_material.resource_name = "Opaque autumn vegetation"
	grass_material.albedo_color = Color.WHITE
	grass_material.vertex_color_use_as_albedo = true
	grass_material.roughness = 1.0
	grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grass_count := 0
	for patch in plan.grass.patches:
		assert(patch.count == patch.instances.size())
		var kind: String = patch.mesh_kind
		var mesh_key := "%s:%s" % [kind, patch.height_m]
		if not meshes_by_kind_height.has(mesh_key):
			meshes_by_kind_height[mesh_key] = _grass_mesh(kind, float(patch.height_m), grass_material)
		var row := _add_batch(root, patch.id, meshes_by_kind_height[mesh_key], null, patch.instances, 75.0, true)
		row["mesh_kind"] = kind
		row["height_m"] = patch.height_m
		rows.append(row)
		grass_count += patch.instances.size()
	for group in plan.reused_assets:
		var source: Node3D = load(group.source_wrapper).instantiate()
		assert(source.find_children("*", "CollisionObject3D", true, false).is_empty(), "Ground detail must not add physical obstacles")
		var meshes := source.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1)
		var mesh := meshes[0] as MeshInstance3D
		assert(mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count() == 1)
		var ancestor: Node3D = mesh
		while ancestor != null:
			assert(ancestor.transform.is_equal_approx(Transform3D.IDENTITY), "Retain imported scale and pose")
			ancestor = ancestor.get_parent() as Node3D
		var arrays := mesh.mesh.surface_get_arrays(0)
		assert((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 == group.expected_triangles)
		rows.append(_add_batch(root, group.id, mesh.mesh, mesh.get_active_material(0), group.instances, 110.0, false))
		source.free()
	assert(root.get_child_count() == plan.counts.multimeshes)
	assert(grass_count == plan.counts.grass_tufts)
	var instance_count := 0
	var triangle_count := 0
	for row in rows:
		instance_count += row.instances
		triangle_count += row.instanced_triangles
	assert(instance_count == plan.counts.grass_tufts + plan.counts.shrubs + plan.counts.debris)
	assert(triangle_count == plan.counts.total_visual_triangles)
	assert(root.find_children("*", "CollisionObject3D", true, false).is_empty())
	assert(root.find_children("*", "NavigationRegion3D", true, false).is_empty())
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT_PATH.get_base_dir()) == OK)
	var saved := ResourceSaver.save(packed, OUTPUT_PATH)
	root.free()
	assert(saved == OK)
	return {"scene": OUTPUT_PATH, "plan_sha256": FileAccess.get_sha256(PLAN_PATH), "batches": rows, "instances": instance_count, "instanced_triangles": triangle_count, "grass_materials": 1, "collision_objects": 0, "runtime_scripts": 0, "native_support": "Pending primary runtime rays; placement heights use canonical terrain"}


func _add_batch(root: Node3D, label: String, mesh: Mesh, material: Material, instances: Array, visible_to: float, grass: bool) -> Dictionary:
	assert(not instances.is_empty())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = grass
	multimesh.mesh = mesh
	multimesh.instance_count = instances.size()
	for index in instances.size():
		var row: Dictionary = instances[index]
		var point := Vector3(row.position_m[0], row.position_m[1], row.position_m[2])
		assert(point.x >= -198 and point.x <= -130 and point.z >= 5 and point.z <= 90)
		var up := Vector3(row.up[0], row.up[1], row.up[2]).normalized()
		var forward := Basis(Vector3.UP, deg_to_rad(row.yaw_deg)).z
		var right := up.cross(forward).normalized()
		var basis := Basis(right, up, right.cross(up))
		assert(basis.get_scale().is_equal_approx(Vector3.ONE))
		multimesh.set_instance_transform(index, Transform3D(basis, point))
		if grass:
			# Placement palette is sRGB; MultiMesh instance colors enter the linear renderer.
			multimesh.set_instance_color(index, Color(row.tint[0], row.tint[1], row.tint[2], row.tint[3]).srgb_to_linear())
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if grass else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.visibility_range_end = visible_to
	node.visibility_range_end_margin = 5.0
	root.add_child(node)
	node.owner = root
	var arrays := mesh.surface_get_arrays(0)
	var triangles := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return {"name": label, "instances": instances.size(), "mesh_triangles": triangles, "instanced_triangles": triangles * instances.size(), "unit_scale": true, "visibility_end_m": visible_to}


func _grass_mesh(kind: String, height_m: float, material: StandardMaterial3D) -> ArrayMesh:
	assert(kind in ["short", "dry", "tall", "weed"] and height_m > 0.0 and height_m <= 0.8)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	if kind == "weed":
		_weed_geometry(vertices, normals, indices, height_m)
	else:
		_blade_geometry(vertices, normals, indices, height_m, kind)
		if kind == "tall":
			_seedhead_geometry(vertices, normals, indices, height_m)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var expected_triangles := 30 if kind in ["tall", "weed"] else 12
	assert(indices.size() / 3 == expected_triangles)
	for point in vertices:
		assert(point.is_finite() and point.y >= 0.0 and point.y <= height_m + 0.00001)
	return mesh


func _blade_geometry(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, height_m: float, kind: String) -> void:
	for blade in 6:
		var angle := float(blade) * 2.399963
		var right := Vector3(cos(angle), 0, sin(angle))
		var lean_distance := 0.10 if kind == "dry" else 0.065
		var lean := Vector3(-sin(angle), 0, cos(angle)) * lean_distance
		var base := right * (0.02 + float(blade % 3) * 0.025)
		var width := 0.017 + float(blade % 2) * 0.005
		if kind == "dry":
			width *= 0.65
		var blade_height := height_m * (0.7 if kind == "tall" else 1.0)
		var tip := base + lean + Vector3.UP * blade_height * (0.55 + float(blade) * 0.09)
		var quad := [base - right * width, base + right * width, tip + right * width * 0.12, tip - right * width * 0.12]
		_append_quad(vertices, normals, indices, quad)


func _seedhead_geometry(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, height_m: float) -> void:
	for stem in 3:
		var angle := float(stem) * 2.399963 + 0.4
		var right := Vector3(cos(angle), 0, sin(angle))
		var base := right * (0.025 + float(stem) * 0.015)
		var tip := base + right * 0.065 + Vector3.UP * height_m * (0.78 + float(stem) * 0.11)
		_append_quad(vertices, normals, indices, [base - right * 0.004, base + right * 0.004, tip + right * 0.003, tip - right * 0.003])
		var head_base := tip - Vector3.UP * height_m * 0.18
		for turn in 2:
			var side := right if turn == 0 else Vector3(-right.z, 0, right.x)
			_append_quad(vertices, normals, indices, [head_base - side * 0.009, head_base + side * 0.009, tip + side * 0.015, tip - side * 0.015])


func _weed_geometry(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, height_m: float) -> void:
	for stem in 3:
		var angle := float(stem) * 2.399963
		var outward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-outward.z, 0, outward.x)
		var base := outward * 0.025
		var tip := base + outward * 0.045 + Vector3.UP * height_m * (0.72 + float(stem) * 0.14)
		_append_quad(vertices, normals, indices, [base - side * 0.004, base + side * 0.004, tip + side * 0.003, tip - side * 0.003])
		for leaf in 4:
			var leaf_angle := angle + float(leaf) * 2.399963
			var direction := Vector3(cos(leaf_angle), 0.22, sin(leaf_angle)).normalized()
			var across := Vector3(-direction.z, 0, direction.x).normalized()
			var root := base.lerp(tip, 0.20 + float(leaf) * 0.19)
			var length := 0.09 - float(leaf) * 0.009
			var middle := root + direction * length * 0.50
			_append_quad(vertices, normals, indices, [root, middle - across * 0.028, root + direction * length, middle + across * 0.028])


func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, points: Array) -> void:
	var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	var start := vertices.size()
	for point in points:
		vertices.append(point)
		normals.append(normal)
	indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
