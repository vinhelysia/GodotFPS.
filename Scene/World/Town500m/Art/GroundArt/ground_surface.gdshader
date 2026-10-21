shader_type spatial;
render_mode cull_disabled;

uniform sampler2D road_leaf_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D ground_context_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D variation_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D v2_ground_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D v2_road_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D v2_detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool v2_enabled = true;
uniform vec4 v2_bounds = vec4(-198.0, 5.0, -130.0, 90.0);
uniform float v2_feather : hint_range(1.0, 10.0) = 5.0;
uniform float v2_detail_strength : hint_range(0.0, 1.0) = 0.65;
uniform bool global_coverage = true;
uniform vec4 pilot_bounds = vec4(-198.0, 5.0, -130.0, 90.0);
uniform float pilot_feather : hint_range(0.1, 10.0) = 4.0;
uniform bool surface_is_road = false;
uniform vec4 original_color : source_color = vec4(0.42, 0.39, 0.33, 1.0);
uniform vec4 dry_grass_color : source_color = vec4(0.51, 0.478, 0.314, 1.0);
uniform vec4 faded_grass_color : source_color = vec4(0.396, 0.451, 0.329, 1.0);
uniform vec4 soil_color : source_color = vec4(0.463, 0.376, 0.286, 1.0);
uniform vec4 compacted_color : source_color = vec4(0.349, 0.294, 0.243, 1.0);
uniform vec4 leaf_color : source_color = vec4(0.588, 0.455, 0.282, 1.0);
uniform vec4 damp_color : source_color = vec4(0.271, 0.247, 0.212, 1.0);
uniform vec4 moss_color : source_color = vec4(0.322, 0.388, 0.282, 1.0);
uniform vec4 asphalt_color : source_color = vec4(0.420, 0.396, 0.361, 1.0);
uniform vec4 gravel_color : source_color = vec4(0.490, 0.443, 0.357, 1.0);
uniform float detail_scale : hint_range(0.1, 3.0) = 0.70;
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.22;
uniform float road_shoulder_width : hint_range(0.5, 2.0) = 1.4;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 point = world_position.xz;
	vec2 edge = min(point - pilot_bounds.xy, pilot_bounds.zw - point);
	float coverage = global_coverage ? 1.0 : smoothstep(0.0, pilot_feather, min(edge.x, edge.y));
	ALBEDO = original_color.rgb;
	ROUGHNESS = surface_is_road ? 0.9 : 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.50;
	if (coverage > 0.0) {
		vec2 map_uv = (point + vec2(250.0)) / 500.0;
		vec4 roads = texture(road_leaf_mask, map_uv);
		vec4 context = texture(ground_context_mask, map_uv);
		vec3 road_distance = roads.rgb * 12.0 - vec3(6.0);
		float nearest_road = context.a * 12.0 - 6.0;
		vec2 variation = texture(variation_mask, map_uv).rg;
		float broad = variation.r;
		float patches = variation.g;
		float edge_wear = (patches - 0.5) * 0.85;
		float road_clear = smoothstep(0.05, road_shoulder_width + broad * 0.55, nearest_road + edge_wear);
		float grass = smoothstep(0.26, 0.71, broad * 0.72 + patches * 0.28);
		grass *= road_clear * (1.0 - context.g * 0.96);
		grass *= smoothstep(0.25, 0.70, abs(world_normal.y));
		float leaves = roads.a * smoothstep(0.28, 0.66, patches) * road_clear;
		float moisture = max(context.r * (0.48 + broad * 0.52), context.g * smoothstep(0.57, 0.85, broad) * 0.42);
		float moss = context.b * moisture * smoothstep(0.40, 0.78, patches) * road_clear * 0.55;
		vec2 detail_uv = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * point * detail_scale;
		detail_uv += vec2(broad - 0.5, patches - 0.5) * 0.65;
		vec3 detail = texture(detail_albedo, detail_uv).rgb;
		float texture_luma = dot(detail, vec3(0.2126, 0.7152, 0.0722));
		float grain = clamp(texture_luma * 1.8, 0.0, 1.0);
		vec3 soil = mix(soil_color.rgb, compacted_color.rgb, (1.0 - road_clear) * 0.70 + context.g * 0.23);
		float dryness = smoothstep(4.0, 18.0, world_position.y);
		vec3 grass_tone = mix(faded_grass_color.rgb, dry_grass_color.rgb, clamp(0.30 + dryness * 0.50 + broad * 0.35, 0.0, 1.0));
		grass_tone *= mix(0.76, 1.22, texture_luma);
		vec3 ground = mix(soil, grass_tone, grass);
		ground = mix(ground, leaf_color.rgb * mix(0.82, 1.12, grain), leaves * 0.78);
		ground = mix(ground, moss_color.rgb, moss);
		ground = mix(ground, damp_color.rgb, moisture * 0.58);
		ground *= mix(0.84, 1.10, broad) * mix(0.94, 1.06, grain);
		float road_weight = 0.0;
		vec3 finish = ground;
		if (surface_is_road) {
			// Both sides evaluate the same ground at the edge; the mesh remains opaque.
			float asphalt = 1.0 - smoothstep(-0.20, 0.20, road_distance.x);
			float gravel = 1.0 - smoothstep(-0.20, 0.20, road_distance.y);
			float edge_start = mix(-0.65 + edge_wear * 0.18, -1.05 + edge_wear * 0.30, gravel);
			edge_start = mix(edge_start, -1.40 + edge_wear * 0.35, asphalt);
			float edge_end = mix(-0.16, -0.20, max(asphalt, gravel));
			road_weight = 1.0 - smoothstep(edge_start, edge_end, nearest_road);
			vec3 road = mix(compacted_color.rgb, gravel_color.rgb, gravel);
			road = mix(road, asphalt_color.rgb, asphalt);
			// Continuous worn patches instead of per-triangle colors or repeating leaf dots.
			float wear = smoothstep(0.50, 0.75, broad + patches * 0.13);
			road = mix(road, soil_color.rgb, wear * 0.32);
			road *= mix(0.90, 1.10, grain) * mix(0.94, 1.04, patches);
			road = mix(road, damp_color.rgb, moisture * 0.35);
			finish = mix(ground, road, road_weight);
		}
		ALBEDO = mix(original_color.rgb, finish, coverage);
		SPECULAR = mix(0.5, 0.2, coverage);
		float roughness_detail = texture(detail_roughness, detail_uv).r;
		float roughness = mix(0.84, 0.98, roughness_detail) - moisture * 0.28;
		vec2 v2_edge = min(point - v2_bounds.xy, v2_bounds.zw - point);
		float v2 = v2_enabled ? smoothstep(0.0, v2_feather, min(v2_edge.x, v2_edge.y)) : 0.0;
		vec3 small_normal = vec3(0.0, 0.0, 1.0);
		if (v2 > 0.0) {
			vec2 tile_uv = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * point * 0.25;
			vec3 micro = texture(v2_ground_detail, tile_uv).rgb;
			vec3 road_micro = texture(v2_road_detail, tile_uv).rgb;
			float shoulder = smoothstep(0.08, 1.2 + patches * 0.65, nearest_road + (micro.r - 0.5) * 0.18 + (patches - 0.5) * 0.3);
			// Close soil/grass tones and fine coverage replace large two-colour blobs.
			float grass_cover = clamp(0.58 + (patches - 0.5) * 0.18 + (micro.r - 0.5) * 0.70, 0.15, 0.85);
			grass_cover *= shoulder * (1.0 - context.g * 0.94) * smoothstep(0.25, 0.70, abs(world_normal.y));
			vec3 dry_tone = mix(soil_color.rgb, mix(faded_grass_color.rgb, dry_grass_color.rgb, 0.72), 0.48);
			vec3 earth = mix(soil_color.rgb, compacted_color.rgb, (1.0 - shoulder) * 0.55 + context.g * 0.15);
			earth *= mix(0.80, 1.16, micro.r);
			vec3 turf = dry_tone * mix(0.84, 1.16, clamp(texture_luma * 4.0, 0.0, 1.0));
			vec3 improved = mix(earth, turf, grass_cover);
			improved = mix(improved, soil_color.rgb * 1.16, micro.g * (1.0 - grass_cover) * 0.38);
			float tree_litter = roads.a * (0.35 + patches * 0.65) * shoulder;
			improved = mix(improved, leaf_color.rgb * mix(0.78, 1.08, micro.r), micro.b * tree_litter);
			improved = mix(improved, moss_color.rgb, moss * (0.4 + micro.r * 0.6));
			improved = mix(improved, damp_color.rgb, moisture * 0.32);
			improved *= mix(0.97, 1.03, broad);
			if (surface_is_road) {
				float asphalt = 1.0 - smoothstep(-0.20, 0.20, road_distance.x);
				float gravel = 1.0 - smoothstep(-0.20, 0.20, road_distance.y);
				vec3 road_tone = mix(compacted_color.rgb, gravel_color.rgb, gravel);
				road_tone = mix(road_tone, asphalt_color.rgb, asphalt);
				road_tone *= mix(0.72, 1.22, road_micro.r);
				road_tone = mix(road_tone, soil_color.rgb, road_micro.b * 0.12);
				road_tone *= 1.0 - road_micro.g * asphalt * smoothstep(0.38, 0.60, patches) * 0.30;
				road_tone = mix(road_tone, gravel_color.rgb * 1.15, micro.g * (0.12 + gravel * 0.25));
				float wear_band = (1.0 - smoothstep(0.07, 0.23, abs(nearest_road + 1.1))) * asphalt * road_micro.b;
				road_tone *= 1.0 - wear_band * 0.06;
				improved = mix(improved, road_tone, road_weight);
			}
			ALBEDO = mix(ALBEDO, improved, v2);
			roughness = mix(roughness, clamp(0.78 + micro.r * 0.18 - moisture * 0.12, 0.62, 1.0), v2);
			small_normal = texture(v2_detail_normal, tile_uv).xyz * 2.0 - 1.0;
		}
		ROUGHNESS = mix(surface_is_road ? 0.9 : 1.0, clamp(roughness, 0.52, 1.0), coverage);
		// No source UVs exist: construct a slope-aware world basis before view conversion.
		vec3 normal_sample = texture(detail_normal, detail_uv).xyz * 2.0 - 1.0;
		normal_sample = mix(normal_sample, small_normal, v2);
		normal_sample.xy = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * normal_sample.xy;
		vec3 base_normal = normalize(world_normal);
		vec3 tangent = normalize(abs(base_normal.y) > 0.2 ? vec3(base_normal.y, -base_normal.x, 0.0) : vec3(1.0, 0.0, 0.0));
		vec3 bitangent = normalize(cross(base_normal, tangent));
		float normal_amount = mix(detail_normal_strength * (0.45 + grass * 0.55) * (1.0 - road_weight * 0.65), v2_detail_strength, v2);
		vec3 perturbed = normalize(base_normal + (tangent * normal_sample.x - bitangent * normal_sample.y) * normal_amount);
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(perturbed, 0.0)).xyz, coverage));
	}
}
