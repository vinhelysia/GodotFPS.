extends RefCounted
## Editor-only: prepare(Town), bake_tile(0..3), then commit(); save Town in editor.

var region: NavigationRegion3D
var source: NavigationMeshSourceGeometryData3D
var template: NavigationMesh
var tiles: Array[NavigationMesh] = []
var measurements: Array[Dictionary] = []


func prepare(root: Node3D) -> Dictionary:
	assert(not EditorInterface.is_playing_scene())
	assert(root.scene_file_path == "res://Scene/Town.tscn")
	region = root.get_node("NavigationRegion3D")
	assert(region.global_transform.is_equal_approx(Transform3D.IDENTITY))
	template = region.navigation_mesh.duplicate()
	assert(is_equal_approx(template.cell_size, 0.1) and is_equal_approx(template.cell_height, 0.1))
	source = NavigationMeshSourceGeometryData3D.new()
	# The native geometry parser includes REMOVE-mode helpers even while their visual-only owner is disabled.
	var visual_shapes: Array[CollisionShape3D] = []
	for shape in region.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled:
			continue
		var body := shape.get_parent() as CollisionObject3D
		if body == null or body.disable_mode != CollisionObject3D.DISABLE_MODE_REMOVE:
			continue
		var ancestor: Node = shape
		while ancestor != null:
			if ancestor.process_mode != Node.PROCESS_MODE_INHERIT:
				if ancestor.process_mode == Node.PROCESS_MODE_DISABLED:
					visual_shapes.append(shape)
					shape.disabled = true
				break
			ancestor = ancestor.get_parent()
	NavigationServer3D.parse_source_geometry_data(template, source, region)
	for shape in visual_shapes:
		shape.disabled = false
	assert(source.has_data() and source.get_projected_obstructions().size() == 76)
	return {"source_indices": source.get_indices().size(), "source_bounds": str(source.get_bounds()), "roof_exclusions": source.get_projected_obstructions().size(), "visual_only_shapes_excluded": visual_shapes.size()}


func bake_tile(index: int) -> Dictionary:
	assert(index == tiles.size() and index < 4)
	var x: float = -250.0 + (index % 2) * 250.0
	var z: float = -250.0 + floori(index / 2.0) * 250.0
	var mesh: NavigationMesh = template.duplicate()
	mesh.clear()
	# Keep a common voxel origin; native border clipping retains exact tile edges.
	mesh.filter_baking_aabb = AABB(Vector3(x - 1, -5, z - 1), Vector3(252, 40, 252))
	mesh.border_size = 1.0
	mesh.edge_max_error = template.edge_max_error
	var started := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	assert(mesh.get_polygon_count() > 0, "Empty navigation tile " + str(index))
	for point in mesh.get_vertices():
		assert(point.x >= x - 0.0001 and point.x <= x + 250.0001 and point.z >= z - 0.0001 and point.z <= z + 250.0001, "Native border failed to clip tile")
	tiles.append(mesh)
	var result := {"tile": index, "bounds_xz": [x, z, x + 250, z + 250], "polygons": mesh.get_polygon_count(), "vertices": mesh.get_vertices().size(), "elapsed_ms": Time.get_ticks_msec() - started}
	measurements.append(result)
	return result


func commit() -> Dictionary:
	assert(tiles.size() == 4)
	var vertices := PackedVector3Array()
	var vertex_ids: Dictionary = {}
	var polygons: Array[PackedInt32Array] = []
	for tile in tiles:
		var mapping := PackedInt32Array()
		for point in tile.get_vertices():
			# 0.1mm keys only weld floating-point copies of the same native voxel vertex.
			var key := Vector3i(roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000))
			if not vertex_ids.has(key):
				vertex_ids[key] = vertices.size()
				vertices.append(point)
			else:
				assert(vertices[vertex_ids[key]].distance_to(point) < 0.0001)
			mapping.append(vertex_ids[key])
		for index in range(tile.get_polygon_count()):
			var polygon := PackedInt32Array()
			for corner in tile.get_polygon(index):
				assert(not mapping[corner] in polygon, "Degenerate welded polygon")
				polygon.append(mapping[corner])
			assert(polygon.size() >= 3)
			polygons.append(polygon)
	var seams := {"x": {}, "z": {}}
	var edge_owners: Dictionary = {}
	for polygon in polygons:
		for corner in range(polygon.size()):
			var a := polygon[corner]
			var b := polygon[(corner + 1) % polygon.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edge_owners[key] = int(edge_owners.get(key, 0)) + 1
			assert(edge_owners[key] <= 2, "Nonmanifold native polygon edge")
			for axis in ["x", "z"]:
				var component: int = 0 if axis == "x" else 2
				if absf(vertices[a][component]) < 0.0001 and absf(vertices[b][component]) < 0.0001:
					seams[axis][key] = int(seams[axis].get(key, 0)) + 1
	var seam_counts: Dictionary = {}
	for axis in seams:
		var joined := 0
		var unmatched: Array[Dictionary] = []
		for key in seams[axis]:
			var count: int = seams[axis][key]
			assert(count <= 2, "Nonmanifold tile edge")
			joined += int(count == 2)
			if count == 1:
				unmatched.append({"a": str(vertices[key.x]), "b": str(vertices[key.y])})
		assert(joined > 0, "No joined " + axis + " tile edges")
		# A cliff can end on a tile edge; native crossing tests must classify open edges.
		seam_counts[axis] = {"joined_edge_pairs": joined, "open_boundary_edges": unmatched}
	var merged: NavigationMesh = template.duplicate()
	merged.clear()
	merged.set_vertices(vertices)
	for polygon in polygons:
		merged.add_polygon(polygon)
	merged.edge_max_error = template.edge_max_error
	merged.resource_name = "Town500 offline tiles; tools/town500_bake_navigation.gd"
	region.navigation_mesh = merged
	return {"tiles": measurements, "vertices": vertices.size(), "polygons": polygons.size(), "seams": seam_counts, "nonmanifold_edges": 0, "runtime_regions": 1, "runtime_links": 0}
