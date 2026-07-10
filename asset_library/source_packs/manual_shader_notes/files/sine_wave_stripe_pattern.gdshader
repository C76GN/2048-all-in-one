shader_type canvas_item;

uniform float frequency : hint_range(0.1, 32.0, 0.01) = 1.5;
uniform float speed : hint_range(-40.0, 40.0, 0.01) = 10.0;
uniform float direction : hint_range(-1.0, 1.0, 0.01) = 1.0;
uniform float edge_softness : hint_range(0.001, 1.0, 0.001) = 0.08;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 color_1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_2 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool use_texture_alpha = true;

void fragment() {
	vec2 safe_scale = max(abs(uv_scale), vec2(0.001));
	vec2 pattern_uv = UV * safe_scale;
	float wave = sin(pattern_uv.x * frequency * TAU + TIME * speed * direction);
	float mask = smoothstep(-edge_softness, edge_softness, wave);
	vec4 pattern_color = mix(color_2, color_1, mask);

	float texture_alpha = 1.0;
	if (use_texture_alpha) {
		texture_alpha = texture(TEXTURE, UV).a;
	}
	COLOR = vec4(pattern_color.rgb, pattern_color.a * opacity * texture_alpha);
}
