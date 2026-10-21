shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 original_color : source_color = vec4(0.42, 0.39, 0.33, 1.0);
uniform vec4 soil_color : source_color = vec4(0.36, 0.32, 0.26, 1.0);
uniform vec4 grass_color : source_color = vec4(0.30, 0.335, 0.24, 1.0);

// All positions and distances are world X/Z metres, independent of terrain chunks.
uniform vec2 pilot_center = vec2(-130.0, 10.0);
uniform vec2 pilot_half_extents = vec2(30.0, 35.0);
uniform float pilot_feather : hint_range(0.1, 10.0, 0.1) = 5.0;
uniform vec4 road_segment = vec4(-160.23, 21.59, -60.23, 10.23);
uniform float road_half_width : hint_range(0.1, 8.0, 0.1) = 4.0;
uniform float verge_width : hint_range(1.0, 3.0, 0.1) = 2.0;
uniform vec4 approach_segment = vec4(-142.0, -9.7, -138.723, 19.1468);
uniform float approach_half_width : hint_range(0.1, 2.0, 0.1) = 0.9;
uniform vec2 foundation_center = vec2(-142.0, -17.0);
uniform vec2 foundation_half_extents = vec2(5.0, 4.0);
uniform float foundation_apron : hint_range(0.8, 1.5, 0.1) = 1.0;
uniform vec2 apartment_center = vec2(-172.0, 60.0);
uniform vec2 apartment_half_extents = vec2(24.0, 30.0);
uniform vec2 apartment_foundation_center = vec2(-165.0, 60.0);
uniform vec2 apartment_foundation_half_extents = vec2(8.1, 20.25);
uniform vec4 apartment_approach_a = vec4(-188.75, 63.5, -180.0, 63.5);
uniform vec4 apartment_approach_b = vec4(-180.0, 63.5, -175.4, 60.0);
uniform vec4 apartment_approach_c = vec4(-175.4, 60.0, -174.909, 60.0);

varying vec2 world_xz;

float cell_hash(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float smooth_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float lower = mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), blend.x);
	float upper = mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0)), blend.x);
	return mix(lower, upper, blend.y);
}

float segment_distance(vec2 point, vec4 segment) {
	vec2 direction = segment.zw - segment.xy;
	float along = clamp(dot(point - segment.xy, direction) / max(dot(direction, direction), 0.001), 0.0, 1.0);
	return length(point - (segment.xy + direction * along));
}

float rectangle_boundary(vec2 point, vec2 center, vec2 half_extents) {
	vec2 edges = half_extents - abs(point - center);
	return min(edges.x, edges.y);
}

float foundation_distance(vec2 point, vec2 center, vec2 half_extents) {
	vec2 edges = abs(point - center) - half_extents;
	return length(max(edges, vec2(0.0))) + min(max(edges.x, edges.y), 0.0);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float boundary_distance = max(rectangle_boundary(world_xz, pilot_center, pilot_half_extents), rectangle_boundary(world_xz, apartment_center, apartment_half_extents));
	ALBEDO = original_color.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;

	if (boundary_distance > 0.0) {
		float broad_noise = smooth_noise(world_xz * 0.18);
		float patch_noise = smooth_noise(world_xz * 0.67 + vec2(19.3, 7.1));
		// The irregular edge recedes inside the rectangle; nothing spills into other zones.
		float pilot_weight = smoothstep(0.0, pilot_feather, max(boundary_distance - broad_noise * 1.4, 0.0));
		float edge_variation = (patch_noise - 0.5) * 0.7;
		float road_distance = segment_distance(world_xz, road_segment);
		float road_grass = smoothstep(road_half_width + 0.15, road_half_width + verge_width, road_distance + edge_variation);
		float approach_distance = segment_distance(world_xz, approach_segment);
		approach_distance = min(approach_distance, segment_distance(world_xz, apartment_approach_a));
		approach_distance = min(approach_distance, segment_distance(world_xz, apartment_approach_b));
		approach_distance = min(approach_distance, segment_distance(world_xz, apartment_approach_c));
		float approach_grass = smoothstep(approach_half_width, approach_half_width + 0.65, approach_distance + edge_variation * 0.3);
		float apron_distance = min(foundation_distance(world_xz, foundation_center, foundation_half_extents), foundation_distance(world_xz, apartment_foundation_center, apartment_foundation_half_extents));
		float foundation_grass = smoothstep(foundation_apron * 0.6, foundation_apron + 0.5, apron_distance + edge_variation * 0.2);
		float grass_weight = smoothstep(0.24, 0.72, broad_noise * 0.7 + patch_noise * 0.3);
		grass_weight *= road_grass * approach_grass * foundation_grass;

		vec3 grass_sample = texture(grass_texture, world_xz * 0.45).rgb;
		float grass_detail = dot(grass_sample, vec3(0.2126, 0.7152, 0.0722));
		vec3 soil = soil_color.rgb * mix(0.93, 1.05, patch_noise);
		vec3 grass = grass_color.rgb * mix(0.94, 1.06, grass_detail);
		vec3 ground = mix(soil, grass, grass_weight);

		ALBEDO = mix(original_color.rgb, ground, pilot_weight);
		ROUGHNESS = mix(1.0, mix(0.90, 1.0, patch_noise), pilot_weight);
	}
}
