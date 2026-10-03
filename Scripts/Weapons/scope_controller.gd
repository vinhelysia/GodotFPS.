## Scope: magnification + procedural shader reticle on lens mesh.
## Attach to scope root (e.g. Tac3014x24Riflescope). Lens uses $Scope SubViewport.
@tool
class_name ScopeController
extends Node3D

signal view_obstructed

@export_group("Wall Clearance")
## Extra space around the scope camera's near plane, in world meters.
@export_range(0.0, 0.1, 0.005) var view_clearance_margin: float = 0.01

@export_group("Magnification")
@export_range(1.0, 32.0, 0.5, "suffix:x") var magnification: float = 4.0:
	set(value):
		magnification = clampf(value, 1.0, 32.0)
		_apply_magnification()

@export_range(30.0, 120.0, 1.0, "suffix:°") var base_fov_at_1x: float = 60.0:
	set(value):
		base_fov_at_1x = value
		_apply_magnification()

@export_group("ADS Sensitivity")
@export_range(0.1, 1.0, 0.01) var scope_sensitivity_multiplier: float = 0.6

func get_sensitivity_multiplier() -> float:
	return scope_sensitivity_multiplier

@export_group("Procedural Reticle / Color")
@export var reticle_color: Color = Color(0.89, 0.15, 0.21, 1.0):
	set(v): reticle_color = v; _set_shader("reticle_color", v)

@export_range(0.0, 1.0, 0.01) var reticle_opacity: float = 1.0:
	set(v): reticle_opacity = v; _set_shader("reticle_opacity", v)

@export_range(0.0, 0.01, 0.0001) var reticle_aa: float = 0.003:
	set(v): reticle_aa = v; _set_shader("reticle_aa", v)

@export_group("Procedural Reticle / Crosshair")
@export_range(0.0, 0.25, 0.001) var cross_length: float = 0.085:
	set(v): cross_length = v; _set_shader("cross_length", v)

@export_range(0.001, 0.02, 0.0005) var cross_thickness: float = 0.004:
	set(v): cross_thickness = v; _set_shader("cross_thickness", v)

@export_range(0.0, 0.1, 0.001) var cross_gap: float = 0.025:
	set(v): cross_gap = v; _set_shader("cross_gap", v)

@export_range(0.0, 0.02, 0.0005) var center_dot_radius: float = 0.007:
	set(v): center_dot_radius = v; _set_shader("center_dot_radius", v)

@export_group("Procedural Reticle / Ring")
@export_range(0.0, 0.5, 0.001) var ring_radius: float = 0.18:
	set(v): ring_radius = v; _set_shader("ring_radius", v)

@export_range(0.0, 0.1, 0.001) var ring_thickness: float = 0.025:
	set(v): ring_thickness = v; _set_shader("ring_thickness", v)

@export_range(0.0, 0.01, 0.0005) var ring_dot_radius: float = 0.005:
	set(v): ring_dot_radius = v; _set_shader("ring_dot_radius", v)

@export_group("Procedural Reticle / BDC Stadia")
@export_range(0, 10) var bdc_dot_count: int = 3:
	set(v): bdc_dot_count = v; _set_shader("bdc_dot_count", v)

@export_range(0.0, 0.02, 0.0005) var bdc_dot_radius: float = 0.006:
	set(v): bdc_dot_radius = v; _set_shader("bdc_dot_radius", v)

@export_range(0.0, 0.1, 0.001) var bdc_dot_spacing: float = 0.025:
	set(v): bdc_dot_spacing = v; _set_shader("bdc_dot_spacing", v)

@export_range(0.0, 0.15, 0.001) var bdc_dot_start: float = 0.04:
	set(v): bdc_dot_start = v; _set_shader("bdc_dot_start", v)

@export_range(0.0, 0.05, 0.0005) var stadia_length: float = 0.015:
	set(v): stadia_length = v; _set_shader("stadia_length", v)

@export_range(0.001, 0.01, 0.0005) var stadia_thickness: float = 0.003:
	set(v): stadia_thickness = v; _set_shader("stadia_thickness", v)

@export_group("Optics")
@export_range(0.0, 0.2, 0.001) var barrel_distortion: float = 0.04:
	set(v): barrel_distortion = v; _set_shader("barrel_distortion", v)

@export_range(0.0, 0.05, 0.001) var chromatic_aberration: float = 0.0:
	set(v): chromatic_aberration = v; _set_shader("chromatic_aberration", v)

@export_range(0.5, 1.5, 0.01) var scope_contrast: float = 0.98:
	set(v): scope_contrast = v; _set_shader("scope_contrast", v)

@export_range(0.1, 2.0, 0.01) var scope_exposure: float = 0.7:
	set(v): scope_exposure = v; _set_shader("scope_exposure", v)

@export_range(0.5, 2.0, 0.01) var scope_gamma: float = 1.1:
	set(v): scope_gamma = v; _set_shader("scope_gamma", v)

@export_range(0.0, 2.0, 0.01) var scope_saturation: float = 1.0:
	set(v): scope_saturation = v; _set_shader("scope_saturation", v)

@export_range(0.0, 0.5, 0.001) var scope_radius: float = 0.048:
	set(v): scope_radius = v; _set_shader("scope_radius", v)

@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.0:
	set(v): vignette_strength = v; _set_shader("vignette_strength", v)

@export_group("Optics / Eyebox")
@export_range(0.0, 1.0, 0.01) var eyebox_position: float = 0.2:
	set(v): eyebox_position = v; _set_shader("eyebox_position", v)

@export_range(0.0, 0.05, 0.001) var eyebox_fade_distance: float = 0.05:
	set(v): eyebox_fade_distance = v; _set_shader("eyebox_fade_distance", v)

@export_range(0.0, 0.02, 0.0005) var eyebox_tolerance: float = 0.005:
	set(v): eyebox_tolerance = v; _set_shader("eyebox_tolerance", v)

@export_range(0.0, 1.0, 0.01) var shadow_inner_radius: float = 0.8:
	set(v): shadow_inner_radius = v; _set_shader("shadow_inner_radius", v)

@export_range(0.0, 1.0, 0.01) var shadow_fade_factor: float = 0.3:
	set(v): shadow_fade_factor = v; _set_shader("shadow_fade_factor", v)

@onready var _scope_vp: SubViewport = $Scope
@onready var _scope_cam: Camera3D = $Scope/Camera3D
@onready var _lens_mesh: MeshInstance3D = $MeshInstance3D

var _shader_mat: ShaderMaterial = null
var _render_requested: bool = false
var _view_query: PhysicsShapeQueryParameters3D
var options_config_path: String = OptionsConstants.config_file_name


func _enter_tree() -> void:
	set_rendering_enabled(false)


func _ready() -> void:
	_resolve_nodes()
	set_rendering_enabled(false)
	if _lens_mesh != null:
		_shader_mat = _lens_mesh.material_override as ShaderMaterial
	if _shader_mat == null:
		push_warning("ScopeController: MeshInstance3D missing ShaderMaterial override on %s" % name)
	_apply_magnification()
	_set_shader("reticle_opacity", reticle_opacity)
	_set_shader("scope_view_enabled", false)
	if not Engine.is_editor_hint():
		add_to_group("scope_renderers")
		var config := ConfigFile.new()
		config.load(options_config_path)
		set_render_resolution(OptionsConstants.get_scope_resolution(config))
		RenderingServer.frame_pre_draw.connect(_update_view)


func _process(_delta: float) -> void:
	_update_view()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_update_view):
		RenderingServer.frame_pre_draw.disconnect(_update_view)


func _update_view() -> void:
	if Engine.is_editor_hint() or not _render_requested:
		return
	# Runs after the parent Wieldables pose; do not trust the lower barrel probe to protect optics.
	# frame_pre_draw also catches tweens, which run after node _process callbacks.
	var blocked := is_view_blocked(get_viewport().get_camera_3d())
	_apply_rendering(not blocked)
	if blocked:
		view_obstructed.emit()


func is_view_blocked(eye: Camera3D) -> bool:
	_resolve_nodes()
	# Detached/editor optics have no player camera to protect.
	if eye == null or _scope_cam == null or not is_inside_tree():
		return false
	if _view_query == null:
		_view_query = PhysicsShapeQueryParameters3D.new()
		_view_query.shape = SphereShape3D.new()
		_view_query.collision_mask = 0b0011 # Environment + Interactables, including doors.
		_view_query.collide_with_areas = false
	var sphere := _view_query.shape as SphereShape3D
	var aspect := float(maxi(_scope_vp.size.x, 1)) / maxi(_scope_vp.size.y, 1)
	var slope := tan(deg_to_rad(_scope_cam.fov) * 0.5)
	# Enclose the entire near plane, not just the camera center (which misses thin walls).
	var widest_aspect := maxf(aspect, 1.0 / aspect)
	var near_plane_radius := _scope_cam.near * sqrt(1.0 + slope * slope * (1.0 + widest_aspect * widest_aspect))
	sphere.radius = near_plane_radius + view_clearance_margin
	var exclude: Array[RID] = []
	var ancestor: Node = eye.get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			exclude.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	_view_query.exclude = exclude
	_view_query.transform = Transform3D(Basis.IDENTITY, eye.global_position)
	_view_query.motion = _scope_cam.global_position - eye.global_position
	var space := get_world_3d().direct_space_state
	# cast_motion ignores initial overlaps; check both endpoints as well as the swept path.
	if not space.intersect_shape(_view_query, 1).is_empty():
		return true
	var fractions := space.cast_motion(_view_query)
	if fractions.size() == 2 and fractions[0] < 1.0:
		return true
	_view_query.transform.origin = _scope_cam.global_position
	return not space.intersect_shape(_view_query, 1).is_empty()


func _resolve_nodes() -> void:
	if _scope_vp == null:
		_scope_vp = get_node_or_null("Scope") as SubViewport
		if _scope_vp == null:
			_scope_vp = get_node_or_null("SubViewport") as SubViewport
	if _scope_cam == null:
		_scope_cam = get_node_or_null("Scope/Camera3D") as Camera3D
		if _scope_cam == null and _scope_vp != null:
			_scope_cam = _scope_vp.get_node_or_null("Camera3D") as Camera3D
	if _lens_mesh == null:
		_lens_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D


func set_magnification(value: float) -> void:
	magnification = value


func get_scope_fov() -> float:
	_resolve_nodes()
	if _scope_cam:
		return _scope_cam.fov
	return base_fov_at_1x / magnification


func set_render_resolution(resolution: int) -> void:
	if resolution != 512 and resolution != 1024:
		resolution = OptionsConstants.default_scope_resolution
	_resolve_nodes()
	if _scope_vp != null:
		_scope_vp.size = Vector2i(resolution, resolution)


func set_rendering_enabled(enabled: bool) -> void:
	_render_requested = enabled
	set_process(enabled and not Engine.is_editor_hint())
	_resolve_nodes()
	_apply_rendering(enabled and not is_view_blocked(get_viewport().get_camera_3d()))


func _apply_rendering(enabled: bool) -> void:
	if _scope_vp == null:
		return
	_scope_vp.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	)
	# Disabling a SubViewport leaves its last image alive; also mask the lens to prevent stale views.
	_set_shader("scope_view_enabled", enabled)


func _apply_magnification() -> void:
	if not is_node_ready():
		return
	_resolve_nodes()
	if _scope_cam == null:
		return
	_scope_cam.fov = base_fov_at_1x / magnification


func _set_shader(param: String, value: Variant) -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter(param, value)
