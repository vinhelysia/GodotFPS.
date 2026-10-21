# Read-only MCP run() body: expand SceneState resources without instantiating nodes.
var source = "res://Scene/Hideout/bunker_prototype_16x20.tscn"
var packed = ResourceLoader.load(source,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
var nodes = {}
var instances = {}
var pending = [{"state":packed.get_state(),"base":"","priority":0,"source":source}]
var keep = ["transform","position","rotation","rotation_degrees","scale","mesh","shape","visible","disabled","process_mode","disable_mode","collision_layer","root_node","is_open","opening_animation","script","text","size","metadata/bunker_zone","metadata/source_name"]
while not pending.is_empty():
	var task = pending.pop_back()
	var state = task.state
	var inherited = state.get_base_scene_state()
	if inherited != null:
		pending.append({"state":inherited,"base":task.base,"priority":task.priority+1,"source":task.source})
	for i in range(state.get_node_count()):
		var local_path = str(state.get_node_path(i)).trim_prefix("./")
		if local_path == ".":
			local_path = ""
		var path = task.base + ("/" if not task.base.is_empty() and not local_path.is_empty() else "") + local_path
		if path == "Player" or path.begins_with("Player/"):
			continue
		if not nodes.has(path):
			nodes[path] = {"type":"","props":{},"priorities":{},"source":task.source}
		var node = nodes[path]
		var native_type = str(state.get_node_type(i))
		if not native_type.is_empty():
			node.type = native_type
		for j in range(state.get_node_property_count(i)):
			var key = str(state.get_node_property_name(i,j))
			if key not in keep and not key.begins_with("libraries/"):
				continue
			if not node.priorities.has(key) or task.priority < node.priorities[key]:
				node.props[key] = state.get_node_property_value(i,j)
				node.priorities[key] = task.priority
		var instance = state.get_node_instance(i)
		if instance != null:
			if task.priority == 0:
				instances[path] = instance.resource_path
			pending.append({"state":instance.get_state(),"base":path,"priority":task.priority+1,"source":instance.resource_path})
var vec = func(v): return [snappedf(v.x,0.000001),snappedf(v.y,0.000001),snappedf(v.z,0.000001)]
var transforms = {}
var sorted_paths = nodes.keys()
sorted_paths.sort_custom(func(a,b): return a.length() < b.length())
for path in sorted_paths:
	var props = nodes[path].props
	var local = props.get("transform",Transform3D.IDENTITY) as Transform3D
	if props.has("position"):
		local.origin = props.position
	if props.has("rotation") or props.has("rotation_degrees"):
		var rot = props.get("rotation",Vector3.ZERO)
		if props.has("rotation_degrees"):
			rot = props.rotation_degrees * PI / 180.0
		local.basis = Basis.from_euler(rot).scaled(local.basis.get_scale())
	if props.has("scale"):
		local.basis = Basis.from_euler(local.basis.get_euler()).scaled(props.scale)
	var parent = path.get_slice("/",0) if not path.contains("/") else path.left(path.rfind("/"))
	if not path.contains("/"):
		parent = ""
	transforms[path] = (transforms.get(parent,Transform3D.IDENTITY) * local) if not path.is_empty() else local
var mesh_rows = []
var shape_rows = []
var animation_rows = []
var warnings = []
var serialize_bounds = func(points):
	var minv = Vector3(INF,INF,INF)
	var maxv = Vector3(-INF,-INF,-INF)
	for point in points:
		minv = minv.min(point)
		maxv = maxv.max(point)
	return {"min":vec.call(minv),"max":vec.call(maxv)}
var section = func(faces,world):
	var segments = []
	for i in range(0,faces.size(),3):
		var triangle = [world*faces[i],world*faces[i+1],world*faces[i+2]]
		var hits = []
		for e in range(3):
			var a = triangle[e]
			var b = triangle[(e+1)%3]
			if (a.y <= 1.0 and b.y > 1.0) or (b.y <= 1.0 and a.y > 1.0):
				var p = a.lerp(b,(1.0-a.y)/(b.y-a.y))
				hits.append([snappedf(p.x,0.00001),snappedf(p.z,0.00001)])
		if hits.size() == 2 and hits[0] != hits[1]:
			segments.append(hits)
	return segments
for path in sorted_paths:
	var node = nodes[path]
	var props = node.props
	var world = transforms[path]
	var mesh = props.get("mesh") as Mesh
	var shape = props.get("shape") as Shape3D
	if mesh != null or shape != null:
		var points = []
		var faces = PackedVector3Array()
		var row = {"path":path,"type":node.type,"source":node.source,"origin":vec.call(world.origin),"basis":[vec.call(world.basis.x),vec.call(world.basis.y),vec.call(world.basis.z)]}
		if mesh != null:
			var aabb = mesh.get_aabb()
			for k in range(8):
				points.append(world*aabb.get_endpoint(k))
			row["local_aabb"] = {"min":vec.call(aabb.position),"max":vec.call(aabb.end)}
			var visible = props.get("visible",true)
			var ancestor = path
			while not ancestor.is_empty():
				if nodes.has(ancestor) and not nodes[ancestor].props.get("visible",true):
					visible = false
				ancestor = ancestor.left(ancestor.rfind("/")) if ancestor.contains("/") else ""
			row["visible"] = visible
			if path.begins_with("Architecture/wall") or path.begins_with("Architecture/column") or path.begins_with("Architecture/door_frame"):
				faces = mesh.get_faces()
		else:
			row["shape_type"] = shape.get_class()
			row["disabled"] = props.get("disabled",false)
			var body_path = path.left(path.rfind("/"))
			row["body_path"] = body_path
			row["collision_layer"] = nodes.get(body_path,{}).get("props",{}).get("collision_layer",1)
			var cursor = path
			var removed = false
			while not cursor.is_empty():
				if nodes.has(cursor) and nodes[cursor].props.get("process_mode",0) == 4:
					removed = true
				cursor = cursor.left(cursor.rfind("/")) if cursor.contains("/") else ""
			row["removed_by_disabled_ancestor"] = removed
			if shape is BoxShape3D:
				var aabb = AABB(-shape.size*0.5,shape.size)
				for k in range(8):
					points.append(world*aabb.get_endpoint(k))
			elif shape is ConvexPolygonShape3D:
				for p in shape.points:
					points.append(world*p)
			elif shape is ConcavePolygonShape3D:
				faces = shape.get_faces()
				for p in faces:
					points.append(world*p)
			elif shape is CylinderShape3D or shape is CapsuleShape3D or shape is SphereShape3D:
				var radius = shape.radius
				var height = shape.height if not shape is SphereShape3D else radius*2.0
				for k in range(32):
					for y in [-height/2.0,height/2.0]:
						points.append(world*Vector3(radius*cos(k*TAU/32.0),y,radius*sin(k*TAU/32.0)))
			else:
				warnings.append("Unsupported shape: "+path+" "+shape.get_class())
		if not points.is_empty():
			row["world_bounds"] = serialize_bounds.call(points)
			row["projection_points"] = points.map(func(p): return [snappedf(p.x,0.00001),snappedf(p.z,0.00001)])
			if not faces.is_empty() and path.begins_with("Architecture/"):
				row["section_y1_segments"] = section.call(faces,world)
			if mesh != null:
				mesh_rows.append(row)
			else:
				shape_rows.append(row)
	if node.type == "AnimationPlayer" and (path.contains("door_leaf__") or path.contains("hermetic_door__")):
		for key in props:
			if not key.begins_with("libraries/"):
				continue
			var library = props[key] as AnimationLibrary
			for animation_name in library.get_animation_list():
				var anim = library.get_animation(animation_name)
				var tracks = []
				for t in range(anim.get_track_count()):
					var keys = []
					for k in range(anim.track_get_key_count(t)):
						var value = anim.track_get_key_value(t,k)
						var serialized = str(value)
						if value is Quaternion:
							serialized = [value.x,value.y,value.z,value.w]
						elif value is Vector3:
							serialized = vec.call(value)
						keys.append({"time":anim.track_get_key_time(t,k),"value":serialized})
					tracks.append({"type":anim.track_get_type(t),"path":str(anim.track_get_path(t)),"keys":keys})
				animation_rows.append({"player_path":path,"root_node":str(props.get("root_node",NodePath(".."))),"name":str(animation_name),"length":anim.length,"tracks":tracks})
var placement_rows = []
for path in instances:
	var world = transforms[path]
	placement_rows.append({"path":path,"resource":instances[path],"origin":vec.call(world.origin),"basis":[vec.call(world.basis.x),vec.call(world.basis.y),vec.call(world.basis.z)]})
_mcp_print(JSON.stringify({"source":source,"method":"SceneState resources only; no Node instantiated or editor state mutated","cut_height_m":1.0,"node_count":nodes.size(),"placements":placement_rows,"meshes":mesh_rows,"collisions":shape_rows,"door_animations":animation_rows,"warnings":warnings}))
