extends AudioStreamPlayer3D

class_name FootstepSurfaceDetector

@export var generic_fallback_footstep_profile : AudioStreamRandomizer
@export var footstep_material_library : FootstepMaterialLibrary
@export var generic_fallback_landing_profile : AudioStreamRandomizer
@export var landing_material_library : FootstepMaterialLibrary
var last_result
var parent_rid : RID
var _material_cache : Dictionary = {}


func _ready():
	parent_rid = get_parent().get_rid()
	if not generic_fallback_footstep_profile:
		printerr("FootstepSurfaceDetector - No generic fallback footstep profile is assigned")
	if not generic_fallback_landing_profile:
		printerr("FootstepSurfaceDetector - No generic fallback landing profile is assigned")

		
func play_footstep():
	_play_interaction("footstep")

func play_landing():
	_play_interaction("landing")

func _play_interaction(interaction_type: String):
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -1, 0))
	query.exclude = [parent_rid]
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		last_result = result
		if interaction_type == "footstep":
			if _play_by_footstep_surface(result.collider, interaction_type):
				return
			elif _play_by_material(result.collider, footstep_material_library, generic_fallback_footstep_profile, interaction_type):
				return
		elif interaction_type == "landing":
			if _play_by_landing_surface(result.collider, interaction_type):
				return
			elif _play_by_material(result.collider, landing_material_library, generic_fallback_landing_profile, interaction_type):
				return

func _play_by_footstep_surface(collider : Node3D, interaction_type: String) -> bool:
	#check for footstep surface as a child of the collider
	var footstep_surface_child : AudioStreamRandomizer = _get_footstep_surface_child(collider)
	#if a child footstep surface was found, then play the sound defined by it
	if footstep_surface_child:
		_play_footstep(footstep_surface_child, interaction_type)
		return true
	#handle footstep surface settings
	elif collider is FootstepSurface and collider.footstep_profile:
		_play_footstep(collider.footstep_profile, interaction_type)
		return true
	return false

func _play_by_landing_surface(collider: Node3D, interaction_type: String) -> bool:
	return _play_by_footstep_surface(collider, interaction_type)

func _play_by_material(collider: Node3D, material_library: FootstepMaterialLibrary, fallback_profile: AudioStreamRandomizer, interaction_type: String) -> bool:
	if material_library:
		#find surface material
		var material: Material = _get_surface_material(collider)
		#if a material was found
		if material:
			#get a profile from our library
			var profile: AudioStreamRandomizer = material_library.get_footstep_profile_by_material(material)
			#found profile, use it
			if profile:
				_play_footstep(profile, interaction_type)
				return true
	# If no specific material profile is found, play the fallback profile
	_play_footstep(fallback_profile, interaction_type)
	return false

func _get_footstep_surface_child(collider : Node3D) -> AudioStreamRandomizer:
	#find all children of the collider static body that are of type "FootstepSurface"
	var footstep_surfaces = collider.find_children("", "FootstepSurface")
	if footstep_surfaces:
		#use the first footstep_surface child found
		return footstep_surfaces[0].footstep_profile
	return null


func _get_surface_material(collider : Node3D) -> Material:
	if not collider:
		return null
		
	var collider_id = collider.get_instance_id()
	
	# Determine the cell for keying
	var cell = Vector3.ZERO
	var mesh_instance = null
	
	if collider is StaticBody3D or collider is RigidBody3D:
		if collider.get_parent() is MeshInstance3D:
			mesh_instance = collider.get_parent()
		else:
			var mesh_instances = collider.find_children("", "MeshInstance3D")
			if mesh_instances and len(mesh_instances) == 1:
				mesh_instance = mesh_instances[0]
				
	if mesh_instance and 'mesh' in mesh_instance and mesh_instance.mesh:
		if mesh_instance.mesh.get_surface_count() > 1:
			if last_result and last_result.has('position'):
				cell = last_result['position'].snapped(Vector3(0.25, 0.25, 0.25))
				
	var cache_key = str(collider_id) + "_" + str(cell)
	
	# Check cache
	if _material_cache.has(cache_key):
		var entry = _material_cache[cache_key]
		if entry.ref.get_ref():
			return entry.material
		else:
			_material_cache.erase(cache_key)
			
	# Resolve uncached
	var mat = _get_surface_material_uncached(collider)
	
	# Cache it
	_material_cache[cache_key] = {
		"ref": weakref(collider),
		"material": mat
	}
	
	# Cleanup stale entries if cache grows
	if _material_cache.size() > 50:
		for key in _material_cache.keys():
			var entry = _material_cache[key]
			if not entry.ref.get_ref():
				_material_cache.erase(key)
				
	return mat


func _get_surface_material_uncached(collider : Node3D) -> Material:
	var mesh_instance = null
	var meshes = []
	if collider is CSGShape3D:
		if collider is CSGCombiner3D:
			#composite mesh
			if collider.material_override:
				return collider.material_override
			meshes = collider.get_meshes()
		else:
			return collider.material
	elif collider is StaticBody3D or collider is RigidBody3D:
		#find all children of the collider static body that are of type "MeshInstance3D"
		#if there are multiple materials, just default to the first one found
		if collider.get_parent() is MeshInstance3D:
			mesh_instance = collider.get_parent()
		else:
			var mesh_instances = collider.find_children("", "MeshInstance3D")
			if mesh_instances:
				if len(mesh_instances) == 1:
					mesh_instance = mesh_instances[0]
				else:
					meshes = mesh_instances
	
	if meshes:
		#TODO: Handle multiple meshes
		mesh_instance = meshes[0]
	
	if mesh_instance and 'mesh' in mesh_instance:
		var mesh = mesh_instance.mesh
		if mesh.get_surface_count() == 0:
			return null
		elif mesh.get_surface_count() == 1:
			return mesh.surface_get_material(0)
		else:
			var face = null
			
			var ray = last_result['position'] - global_position
			var faces = mesh.get_faces()
			
			var aabb = mesh.get_aabb() as AABB
			var accuracy = round(4*aabb.size.length_squared()) # dynamically calculate a reasonable grid size
			var snap = aabb.size/accuracy # this will be the size of our units to snap to
			
			var coord = null
			
			for i in range(len(faces) / 3):
				# first, figure out what face we're standing on
				var face_idx = i * 3
				var a = mesh_instance.to_global(faces[face_idx])
				var b = mesh_instance.to_global(faces[face_idx+1])
				var c = mesh_instance.to_global(faces[face_idx+2])
				var ray_t = Geometry3D.ray_intersects_triangle(global_position,ray,a,b,c)
				if ray_t:
					face = faces.slice(face_idx,face_idx+3)
					# round out vert coordinates to avoid floating point errors
					coord = [round(faces[face_idx]/snap),round(faces[face_idx+1]/snap),round(faces[face_idx+2]/snap)]
					break
			var mat = null
			if face:
				for surface in range(mesh.get_surface_count()):
					var surf = mesh.surface_get_arrays(surface)[0]
					var has_vert_a = false
					var has_vert_b = false
					var has_vert_c = false
					for vert in surf:
						var vert_coord = round(vert/snap)
						has_vert_a = has_vert_a or vert_coord == coord[0]
						has_vert_b = has_vert_b or vert_coord == coord[1]
						has_vert_c = has_vert_c or vert_coord == coord[2]
						if has_vert_a and has_vert_b and has_vert_c:
							# we found it! note the material and break free!
							mat = mesh.surface_get_material(surface)
							break
					if has_vert_a and has_vert_b and has_vert_c:
						break
			return mat
	return null


func _play_footstep(profile : AudioStreamRandomizer, interaction_type: String):
	
	if interaction_type == "footstep":
		stream = profile
		play()
		
		var loudness: float = 10.0
		var parent: Node = get_parent()
		if parent:
			if parent.is_in_group("Player"):
				if parent.get("is_sprinting") == true:
					loudness = 20.0
				elif parent.get("is_crouching") == true:
					loudness = 5.0
			else:
				var vel = parent.get("velocity")
				var sprint_spd = parent.get("sprint_speed")
				if vel is Vector3 and sprint_spd is float:
					if vel.length() >= sprint_spd - 0.5:
						loudness = 20.0
		
		var sound_events = get_node_or_null("/root/SoundEvents")
		if sound_events:
			sound_events.sound_emitted.emit(global_position, loudness, &"footstep", parent)


	elif interaction_type == "landing":
		#Setup QuickAudio landing player so that it can use its own pitch/volume parameters
		var playerNode = get_parent()
		var LandingVolume = playerNode.LandingVolume
		var LandingPitch = playerNode.LandingPitch
		var LandingPlayer = Audio.play_sound_3d(profile, false)
		LandingPlayer.pitch_scale = LandingPitch
		LandingPlayer.volume_db = LandingVolume
		LandingPlayer.global_position = global_position
		LandingPlayer.play()
