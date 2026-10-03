shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

const vec3 BLACK = vec3(0.0);

// -- Textures -----------------------------------------------------------------
/** Viewport texture from a 3D Camera - the scope's world view */
// REMOVED source_color to prevent double gamma/sRGB conversion
uniform sampler2D scope_texture : repeat_disable;
uniform bool scope_view_enabled = false;

// -- Scope Geometry ------------------------------------------------------------
uniform float scope_radius = 0.025;
uniform float reticle_depth = 2.0;
uniform float parallax_factor : hint_range(0.0, 0.3, 0.001) = 0.1;
uniform float view_edge_fade_factor : hint_range(0.0, 0.5, 0.001) = 0.05;

// -- Color Correction (NEW) ----------------------------------------------------
group_uniforms Color_Correction;
/** Exposure multiplier - lower = darker scope view */
uniform float scope_exposure : hint_range(0.1, 2.0, 0.01) = 0.7;
/** Gamma correction - higher = darker midtones */
uniform float scope_gamma : hint_range(0.5, 2.2, 0.01) = 1.0;
/** Contrast adjustment */
uniform float scope_contrast : hint_range(0.5, 1.5, 0.01) = 1.0;
/** Saturation adjustment */
uniform float scope_saturation : hint_range(0.0, 1.5, 0.01) = 1.0;

// -- Eyebox -------------------------------------------------------------------
group_uniforms Eyebox;
uniform float eyebox_position = 0.15;
uniform float eyebox_tolerance = 0.005;
uniform float eyebox_fade_distance = 0.05;

// -- Scope Shadow --------------------------------------------------------------
group_uniforms Scope_Shadow;
uniform float shadow_inner_radius : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float shadow_fade_factor = 0.2;
uniform float shadow_movement_factor : hint_range(0.5, 1.0, 0.01) = 1.0;

// -- Lens Effects --------------------------------------------------------------
group_uniforms Lens_Effects;
uniform float barrel_distortion : hint_range(0.0, 0.5, 0.01) = 0.08;
uniform float chromatic_aberration : hint_range(0.0, 0.02, 0.0005) = 0.004;
uniform float vignette_strength : hint_range(0.0, 1.5, 0.05) = 0.35;

// -- Reticle ------------------------------------------------------------------
group_uniforms Reticle;
/** Reticle color - default red to match reference */
uniform vec3 reticle_color : source_color = vec3(0.89, 0.15, 0.21);
/** Overall reticle opacity */
uniform float reticle_opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
/** Anti-alias softness in UV space - higher = softer edges */
uniform float reticle_aa : hint_range(0.001, 0.01, 0.001) = 0.003;

// -- Outer ring
/** Radius of the outer circle (in reticle UV space, 0-0.5) */
uniform float ring_radius : hint_range(0.05, 0.45, 0.01) = 0.18;
/** Thickness of the outer ring stroke */
uniform float ring_thickness : hint_range(0.005, 0.06, 0.001) = 0.025;

// -- Crosshair lines
/** Half-length of each crosshair arm */
uniform float cross_length : hint_range(0.02, 0.2, 0.005) = 0.085;
/** Gap between center and start of each arm */
uniform float cross_gap : hint_range(0.005, 0.1, 0.005) = 0.025;
/** Thickness of the crosshair lines */
uniform float cross_thickness : hint_range(0.001, 0.02, 0.001) = 0.004;

// -- Stadia caps (perpendicular end caps on crosshair arms)
/** Length of stadia cap lines */
uniform float stadia_length : hint_range(0.005, 0.05, 0.001) = 0.015;
/** Thickness of stadia cap lines */
uniform float stadia_thickness : hint_range(0.001, 0.01, 0.001) = 0.003;

// -- Center dot
/** Radius of the center aiming dot */
uniform float center_dot_radius : hint_range(0.002, 0.02, 0.001) = 0.007;

// -- BDC range dots (below center)
/** Number of BDC dots below center */
uniform int bdc_dot_count : hint_range(0, 6, 1) = 3;
/** Spacing between BDC dots */
uniform float bdc_dot_spacing : hint_range(0.01, 0.06, 0.005) = 0.025;
/** Starting offset below center */
uniform float bdc_dot_start : hint_range(0.02, 0.15, 0.005) = 0.04;
/** Radius of BDC dots */
uniform float bdc_dot_radius : hint_range(0.002, 0.015, 0.001) = 0.006;

// -- Ring marker dot (6 o'clock position on the outer ring)
/** Radius of the small dot on the ring at bottom */
uniform float ring_dot_radius : hint_range(0.002, 0.015, 0.001) = 0.005;

varying vec3 view;


// ============================================================================
// SDF PRIMITIVES - all return distance (negative = inside)
// ============================================================================

float sdf_ring(vec2 p, float radius, float thickness) {
	return abs(length(p) - radius) - thickness * 0.5;
}

float sdf_circle(vec2 p, float radius) {
	return length(p) - radius;
}

float sdf_box(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sdf_alpha(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}


// ============================================================================
// PROCEDURAL RETICLE
// ============================================================================

float draw_reticle(vec2 uv) {
	vec2 p = uv - 0.5;
	float alpha = 0.0;

	// Outer ring
	alpha = max(alpha, sdf_alpha(sdf_ring(p, ring_radius, ring_thickness), reticle_aa));

	// Center dot
	alpha = max(alpha, sdf_alpha(sdf_circle(p, center_dot_radius), reticle_aa));

	// Crosshair arms
	float arm_half_len = (cross_length - cross_gap) * 0.5;
	float arm_center = cross_gap + arm_half_len;

	// Top
	vec2 top_p = p - vec2(0.0, -arm_center);
	alpha = max(alpha, sdf_alpha(sdf_box(top_p, vec2(cross_thickness * 0.5, arm_half_len)), reticle_aa));

	// Left
	vec2 left_p = p - vec2(-arm_center, 0.0);
	alpha = max(alpha, sdf_alpha(sdf_box(left_p, vec2(arm_half_len, cross_thickness * 0.5)), reticle_aa));

	// Right
	vec2 right_p = p - vec2(arm_center, 0.0);
	alpha = max(alpha, sdf_alpha(sdf_box(right_p, vec2(arm_half_len, cross_thickness * 0.5)), reticle_aa));

	// Stadia caps
	float arm_end = cross_gap + (cross_length - cross_gap);

	// Top arm cap
	vec2 top_cap_p = p - vec2(0.0, -arm_end);
	alpha = max(alpha, sdf_alpha(sdf_box(top_cap_p, vec2(stadia_length * 0.5, stadia_thickness * 0.5)), reticle_aa));

	// Left arm cap
	vec2 left_cap_p = p - vec2(-arm_end, 0.0);
	alpha = max(alpha, sdf_alpha(sdf_box(left_cap_p, vec2(stadia_thickness * 0.5, stadia_length * 0.5)), reticle_aa));

	// Right arm cap
	vec2 right_cap_p = p - vec2(arm_end, 0.0);
	alpha = max(alpha, sdf_alpha(sdf_box(right_cap_p, vec2(stadia_thickness * 0.5, stadia_length * 0.5)), reticle_aa));

	// BDC range dots (below center)
	for (int i = 0; i < bdc_dot_count; i++) {
		float y_offset = bdc_dot_start + float(i) * bdc_dot_spacing;
		vec2 dot_p = p - vec2(0.0, y_offset);
		alpha = max(alpha, sdf_alpha(sdf_circle(dot_p, bdc_dot_radius), reticle_aa));
	}

	// Ring marker dot (6 o'clock on outer ring)
	vec2 ring_dot_p = p - vec2(0.0, ring_radius);
	alpha = max(alpha, sdf_alpha(sdf_circle(ring_dot_p, ring_dot_radius), reticle_aa));

	return alpha * reticle_opacity;
}


// ============================================================================
// SCOPE HELPERS
// ============================================================================

vec2 barrel(vec2 uv, float k) {
	vec2 centered = uv - 0.5;
	float r2 = dot(centered, centered);
	centered *= 1.0 + k * r2;
	return centered + 0.5;
}

vec2 get_depth_effect(vec2 uv, vec3 direction, float depth) {
	vec2 result = uv - direction.xy * (depth * 2.0);
	return (result - 0.5) * 0.5 + 0.5;
}

float get_scope_shadow_mask(vec2 uv, vec3 view_dir, float eye_dist) {
	float delta = eye_dist - eyebox_position;
	vec2 shifted = uv - view_dir.xy / -shadow_movement_factor;
	vec2 from_center = (shifted - 0.5) * 2.0;
	float dist = length(from_center);

	float fade_near = smoothstep(-eyebox_tolerance, -eyebox_tolerance - eyebox_fade_distance, delta);
	float fade_far  = smoothstep( eyebox_tolerance,  eyebox_tolerance + eyebox_fade_distance, delta);
	float distance_fade = max(fade_near, fade_far);

	float dynamic_radius = mix(0.0, shadow_inner_radius, 1.0 - distance_fade);
	return smoothstep(dynamic_radius - shadow_fade_factor, dynamic_radius, dist);
}

vec3 get_scope_shadow(vec2 uv, vec3 color, vec3 view_dir, float eye_dist) {
	float shadow = get_scope_shadow_mask(uv, view_dir, eye_dist);
	return mix(color, BLACK, shadow);
}

vec3 get_edge_fade(vec2 adj_uv, vec3 color) {
	float dist = length(adj_uv - 0.5);
	float edge_fade = smoothstep(0.5 - view_edge_fade_factor, 0.5, dist);
	float vignette = 1.0 - smoothstep(0.2, 0.55, dist) * vignette_strength;
	return mix(color, BLACK, edge_fade) * vignette;
}

vec3 sample_with_ca(sampler2D tex, vec2 uv, float ca_amount) {
	vec2 dir = uv - 0.5;
	float r = texture(tex, uv + dir * ca_amount).r;
	float g = texture(tex, uv).g;
	float b = texture(tex, uv - dir * ca_amount).b;
	return vec3(r, g, b);
}

float in_bounds(vec2 uv) {
	vec2 s = step(vec2(0.01), uv) * step(uv, vec2(0.99));
	return s.x * s.y;
}


// ============================================================================
// COLOR CORRECTION HELPERS (NEW)
// ============================================================================

vec3 apply_color_correction(vec3 color) {
	// Apply exposure
	color *= scope_exposure;
	
	// Apply contrast (around 0.5 midpoint)
	color = (color - 0.5) * scope_contrast + 0.5;
	
	// Apply gamma correction
	color = pow(max(color, vec3(0.0)), vec3(scope_gamma));
	
	// Apply saturation
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, scope_saturation);
	
	return clamp(color, vec3(0.0), vec3(1.0));
}


// ============================================================================
// VERTEX
// ============================================================================

void vertex() {
	view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz
	     - (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}


// ============================================================================
// FRAGMENT
// ============================================================================

void fragment() {
	float view_len_sq = dot(view, view);
	float radius_sq = scope_radius * scope_radius;
	if (view_len_sq > radius_sq) {
		discard;
	}

	float eye_distance = length(NODE_POSITION_WORLD - CAMERA_POSITION_WORLD);
	vec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT, -BINORMAL, NORMAL));

	// Depth + barrel distortion
	vec2 depth_uv = get_depth_effect(UV, view_dir, reticle_depth);
	vec2 scope_uv = barrel(depth_uv, barrel_distortion);

	// Parallax blend for the reticle
	vec2 reticle_uv = mix(depth_uv, UV, parallax_factor);

	// Scope world view
	vec3 scope_color;
	if (chromatic_aberration > 0.0) {
		scope_color = sample_with_ca(scope_texture, scope_uv, chromatic_aberration);
	} else {
		scope_color = texture(scope_texture, scope_uv).rgb;
	}

	// Apply color correction to match main camera (NEW)
	scope_color = apply_color_correction(scope_color);

	float scope_shadow = get_scope_shadow_mask(UV, view_dir, eye_distance);

	scope_color = mix(scope_color, BLACK, scope_shadow);
	scope_color = get_edge_fade(scope_uv, scope_color);

	// Procedural reticle overlay
	float ret_alpha = draw_reticle(reticle_uv)
		* in_bounds(depth_uv)
		* (1.0 - scope_shadow);

	ALPHA = 1.0;
	ALBEDO = scope_view_enabled ? mix(scope_color, reticle_color, ret_alpha) : vec3(0.0);
}
