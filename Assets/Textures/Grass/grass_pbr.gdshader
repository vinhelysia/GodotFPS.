shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale : hint_range(0.1, 50.0) = 1.0;

void fragment() {
	ALBEDO = texture(albedo_tex, UV * uv_scale).rgb * tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
