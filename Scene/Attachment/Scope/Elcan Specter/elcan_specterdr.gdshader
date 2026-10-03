shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

const vec3 BLACK = vec3(0.0);

// -- Textures -----------------------------------------------------------------
uniform sampler2D scope_texture : repeat_disable;
uniform bool scope_view_enabled = false;

// -- Scope Geometry ------------------------------------------------------------
uniform float scope_radius = 0.025;
uniform float reticle_depth = 2.0;
uniform float parallax_factor : hint_range(0.0, 0.3, 0.001) = 0.1;
uniform float view_edge_fade_factor : hint_range(0.0, 0.5, 0.001) = 0.05;

// -- Color Correction ----------------------------------------------------------
group_uniforms Color_Correction;
uniform float scope_exposure : hint_range(0.1, 2.0, 0.01) = 0.7;
uniform float scope_gamma : hint_range(0.5, 2.2, 0.01) = 1.0;
uniform float scope_contrast : hint_range(0.5, 1.5, 0.01) = 1.0;
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

// -- ELCAN SpecterDR Reticle ---------------------------------------------------
group_uniforms Reticle;
/** Main etched reticle color. Reference is black. */
uniform vec3 reticle_color : source_color = vec3(0.0, 0.0, 0.0);
/** Illuminated center cross color. */
uniform vec3 illumination_color : source_color = vec3(1.0, 0.03, 0.02);
uniform float reticle_opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float illumination_opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
/** AA softness in reticle UV space. */
uniform float reticle_aa : hint_range(0.0002, 0.006, 0.0001) = 0.0010;
/** Uniform scale for the whole ELCAN drawing. 1.0 matches the supplied reference. */
uniform float elcan_scale : hint_range(0.5, 2.0, 0.01) = 1.0;
/** Move the reticle in lens UV space. */
uniform vec2 elcan_offset = vec2(0.0, 0.0);
uniform bool show_bdc_numbers = true;
uniform bool show_rangefinder = true;
uniform bool show_rangefinder_numbers = true;

varying vec3 view;


// ============================================================================
// SDF PRIMITIVES
// ============================================================================

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

float box_alpha(vec2 p, vec2 center, vec2 half_size, float aa) {
	return sdf_alpha(sdf_box(p - center, half_size), aa);
}


// ============================================================================
// TINY PROCEDURAL DIGITS (7-segment style)
// Used only for the small BDC/range labels in the supplied reference.
// ============================================================================

float digit_alpha(vec2 p, vec2 center, int digit, float w, float h, float t, float aa) {
	vec2 q = p - center;
	float a = 0.0;

	float hx = w * 0.42;
	float vx = w * 0.46;
	float vy = h * 0.25;
	vec2 hs = vec2(hx, t * 0.5);
	vec2 vs = vec2(t * 0.5, h * 0.23);

	// A: top
	if (digit == 0 || digit == 2 || digit == 3 || digit == 5 || digit == 6 || digit == 7 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(0.0, -h * 0.5), hs, aa));
	}
	// B: upper-right
	if (digit == 0 || digit == 1 || digit == 2 || digit == 3 || digit == 4 || digit == 7 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(vx, -vy), vs, aa));
	}
	// C: lower-right
	if (digit == 0 || digit == 1 || digit == 3 || digit == 4 || digit == 5 || digit == 6 || digit == 7 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(vx, vy), vs, aa));
	}
	// D: bottom
	if (digit == 0 || digit == 2 || digit == 3 || digit == 5 || digit == 6 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(0.0, h * 0.5), hs, aa));
	}
	// E: lower-left
	if (digit == 0 || digit == 2 || digit == 6 || digit == 8) {
		a = max(a, box_alpha(q, vec2(-vx, vy), vs, aa));
	}
	// F: upper-left
	if (digit == 0 || digit == 4 || digit == 5 || digit == 6 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(-vx, -vy), vs, aa));
	}
	// G: middle
	if (digit == 2 || digit == 3 || digit == 4 || digit == 5 || digit == 6 || digit == 8 || digit == 9) {
		a = max(a, box_alpha(q, vec2(0.0, 0.0), hs, aa));
	}

	return a;
}

float two_digit_alpha(vec2 p, vec2 center, int tens, int ones, float w, float h, float t, float gap, float aa) {
	float xoff = (w + gap) * 0.5;
	float a = digit_alpha(p, center + vec2(-xoff, 0.0), tens, w, h, t, aa);
	a = max(a, digit_alpha(p, center + vec2(xoff, 0.0), ones, w, h, t, aa));
	return a;
}


// ============================================================================
// ELCAN SPECTERDR PROCEDURAL RETICLE
// Coordinates are matched to the supplied 1000x1000 transparent reference.
// p.x/p.y are UV offsets from optical center; +Y is downward.
// ============================================================================

float draw_elcan_black(vec2 uv) {
	vec2 p = (uv - 0.5 - elcan_offset) / max(elcan_scale, 0.001);
	float aa = reticle_aa / max(elcan_scale, 0.001);
	float a = 0.0;

	// --- Main crosshair ---------------------------------------------------------
	// Long, very thin upper post: roughly y = -0.176 .. -0.009
	a = max(a, box_alpha(p, vec2(0.0, -0.0925), vec2(0.0010, 0.0835), aa));

	// Thin inner horizontal stadia, with a center gap for the illuminated cross.
	a = max(a, box_alpha(p, vec2(-0.0490, 0.0), vec2(0.0400, 0.0015), aa));
	a = max(a, box_alpha(p, vec2( 0.0490, 0.0), vec2(0.0400, 0.0015), aa));

	// Heavy outer horizontal bars.
	a = max(a, box_alpha(p, vec2(-0.1330, 0.0), vec2(0.0440, 0.0035), aa));
	a = max(a, box_alpha(p, vec2( 0.1330, 0.0), vec2(0.0440, 0.0035), aa));

	// --- BDC ladder -------------------------------------------------------------
	// Thin vertical stem.
	a = max(a, box_alpha(p, vec2(0.0, 0.0500), vec2(0.0010, 0.0380), aa));

	// Horizontal ranging ticks. Their widths taper toward the bottom.
	a = max(a, box_alpha(p, vec2(0.0, 0.0120), vec2(0.0080, 0.0010), aa));
	a = max(a, box_alpha(p, vec2(0.0, 0.0210), vec2(0.0055, 0.0010), aa));
	a = max(a, box_alpha(p, vec2(0.0, 0.0320), vec2(0.0050, 0.0010), aa));
	a = max(a, box_alpha(p, vec2(0.0, 0.0450), vec2(0.0040, 0.0010), aa));
	a = max(a, box_alpha(p, vec2(0.0, 0.0570), vec2(0.0035, 0.0010), aa));
	a = max(a, box_alpha(p, vec2(0.0, 0.0760), vec2(0.0032, 0.0010), aa));

	// Heavy lower post: roughly y = 0.088 .. 0.175.
	a = max(a, box_alpha(p, vec2(0.0, 0.1315), vec2(0.0040, 0.0435), aa));

	// BDC labels at right: 3, 5, 6, 7, 8.
	if (show_bdc_numbers) {
		float dw = 0.0046;
		float dh = 0.0080;
		float dt = 0.0010;
		float dx = 0.0140;
		float daa = aa * 0.75;
		a = max(a, digit_alpha(p, vec2(dx, 0.0120), 3, dw, dh, dt, daa));
		a = max(a, digit_alpha(p, vec2(dx, 0.0320), 5, dw, dh, dt, daa));
		a = max(a, digit_alpha(p, vec2(dx, 0.0450), 6, dw, dh, dt, daa));
		a = max(a, digit_alpha(p, vec2(dx, 0.0570), 7, dw, dh, dt, daa));
		a = max(a, digit_alpha(p, vec2(dx, 0.0760), 8, dw, dh, dt, daa));
	}

	// --- Lower-left range estimator --------------------------------------------
	if (show_rangefinder) {
		// Main horizontal reference line.
		a = max(a, box_alpha(p, vec2(-0.1205, 0.1750), vec2(0.0585, 0.0008), aa));

		// Four short stepped bars beneath it.
		a = max(a, box_alpha(p, vec2(-0.1675, 0.1955), vec2(0.0115, 0.0010), aa));
		a = max(a, box_alpha(p, vec2(-0.1355, 0.1920), vec2(0.0110, 0.0010), aa));
		a = max(a, box_alpha(p, vec2(-0.1045, 0.1885), vec2(0.0105, 0.0010), aa));
		a = max(a, box_alpha(p, vec2(-0.0735, 0.1865), vec2(0.0105, 0.0010), aa));

		if (show_rangefinder_numbers) {
			float rw = 0.0042;
			float rh = 0.0070;
			float rt = 0.0009;
			float rg = 0.0015;
			float raa = aa * 0.70;
			a = max(a, two_digit_alpha(p, vec2(-0.1710, 0.1605), 3, 0, rw, rh, rt, rg, raa));
			a = max(a, two_digit_alpha(p, vec2(-0.1360, 0.1605), 4, 0, rw, rh, rt, rg, raa));
			a = max(a, two_digit_alpha(p, vec2(-0.1010, 0.1605), 5, 0, rw, rh, rt, rg, raa));
			a = max(a, two_digit_alpha(p, vec2(-0.0660, 0.1605), 6, 0, rw, rh, rt, rg, raa));
		}
	}

	return a * reticle_opacity;
}

float draw_elcan_illumination(vec2 uv) {
	vec2 p = (uv - 0.5 - elcan_offset) / max(elcan_scale, 0.001);
	float aa = reticle_aa / max(elcan_scale, 0.001);
	float a = 0.0;

	// The supplied reference has a small illuminated red '+' at optical center.
	a = max(a, box_alpha(p, vec2(0.0), vec2(0.0060, 0.0016), aa));
	a = max(a, box_alpha(p, vec2(0.0), vec2(0.0016, 0.0055), aa));

	return a * illumination_opacity;
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
// COLOR CORRECTION
// ============================================================================

vec3 apply_color_correction(vec3 color) {
	color *= scope_exposure;
	color = (color - 0.5) * scope_contrast + 0.5;
	color = pow(max(color, vec3(0.0)), vec3(scope_gamma));
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

	// Depth + barrel distortion.
	vec2 depth_uv = get_depth_effect(UV, view_dir, reticle_depth);
	vec2 scope_uv = barrel(depth_uv, barrel_distortion);

	// Parallax blend for the reticle.
	vec2 reticle_uv = mix(depth_uv, UV, parallax_factor);

	// Scope world view.
	vec3 scope_color;
	if (chromatic_aberration > 0.0) {
		scope_color = sample_with_ca(scope_texture, scope_uv, chromatic_aberration);
	} else {
		scope_color = texture(scope_texture, scope_uv).rgb;
	}

	scope_color = apply_color_correction(scope_color);

	float scope_shadow = get_scope_shadow_mask(UV, view_dir, eye_distance);
	scope_color = mix(scope_color, BLACK, scope_shadow);
	scope_color = get_edge_fade(scope_uv, scope_color);

	float visibility = in_bounds(depth_uv) * (1.0 - scope_shadow);
	float black_alpha = draw_elcan_black(reticle_uv) * visibility;
	float illum_alpha = draw_elcan_illumination(reticle_uv) * visibility;

	// Etched black reticle first, red illuminated center second.
	vec3 final_color = mix(scope_color, reticle_color, black_alpha);
	final_color = mix(final_color, illumination_color, illum_alpha);

	ALPHA = 1.0;
	ALBEDO = scope_view_enabled ? final_color : vec3(0.0);
}
