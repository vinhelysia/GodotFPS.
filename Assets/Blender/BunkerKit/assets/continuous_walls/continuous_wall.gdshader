shader_type spatial;

// Authoritative source UV families: R=Plaster, G=Damp, B=other/hardware.
uniform sampler2D families : filter_nearest, repeat_disable;
uniform sampler2D source_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_orm : filter_linear_mipmap, repeat_disable;

// Inspector colors are sRGB; shader receives the documented linear palette.
uniform vec4 concrete_color : source_color = vec4(0.767375658, 0.767375658, 0.764252299, 1.0);
uniform vec4 plaster_color : source_color = vec4(0.865042028, 0.862374457, 0.854305832, 1.0);
uniform vec4 skirting_color : source_color = vec4(0.642166502, 0.642166502, 0.638225431, 1.0);
uniform float detail_strength : hint_range(0.0, 0.1, 0.001) = 0.018;
uniform float detail_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float wear_strength : hint_range(0.0, 0.3, 0.005) = 0.07;
uniform float wear_scale : hint_range(0.1, 2.0, 0.05) = 0.65;
uniform float wear_cutoff : hint_range(0.5, 0.94, 0.01) = 0.72;
uniform float wear_height : hint_range(0.1, 1.0, 0.05) = 0.6;
varying vec3 world_position;

float lattice_value(vec3 cell) {
	vec3 value = fract(cell * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

// Fixed 3D value field: adjacent modules sample the same physical coordinates.
float world_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 weight = fract(point);
	weight = weight * weight * (3.0 - 2.0 * weight);
	float bottom = mix(
		mix(lattice_value(cell), lattice_value(cell + vec3(1.0, 0.0, 0.0)), weight.x),
		mix(lattice_value(cell + vec3(0.0, 1.0, 0.0)), lattice_value(cell + vec3(1.0, 1.0, 0.0)), weight.x), weight.y);
	float top = mix(
		mix(lattice_value(cell + vec3(0.0, 0.0, 1.0)), lattice_value(cell + vec3(1.0, 0.0, 1.0)), weight.x),
		mix(lattice_value(cell + vec3(0.0, 1.0, 1.0)), lattice_value(cell + vec3(1.0, 1.0, 1.0)), weight.x), weight.y);
	return mix(bottom, top, weight.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 family = texture(families, UV).rgb;
	if (family.b > 0.5) {
		// Keep hardware's UV finish and original raw ORM channels unchanged.
		ALBEDO = texture(source_albedo, UV).rgb;
		vec3 orm = texture(source_orm, UV).rgb;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	} else {
		float plaster = step(0.5, family.r);
		// Damp faces on tall lintels become concrete, not a stripe above doors.
		float skirting = step(0.5, family.g) * (1.0 - step(1.0, world_position.y));
		vec3 base_color = mix(concrete_color.rgb, plaster_color.rgb, plaster);
		base_color = mix(base_color, skirting_color.rgb, skirting);
		float detail = (world_noise(world_position * detail_scale + vec3(11.7, 4.3, 8.1)) - 0.5) * 2.0;
		float lower_wall = 1.0 - smoothstep(0.0, wear_height, world_position.y);
		float wear = smoothstep(wear_cutoff, 0.95, world_noise(world_position * wear_scale + vec3(31.4, 7.8, 19.2))) * lower_wall;
		ALBEDO = base_color * (1.0 + detail * detail_strength - wear * wear_strength);
		ROUGHNESS = clamp(mix(0.91, 0.9, plaster) + wear * 0.04, 0.0, 1.0);
		METALLIC = 0.0;
	}
}
