shader_type canvas_item;

uniform float cell_size : hint_range(1.0, 100.0, 0.1) = 25.0;
uniform vec4 color_1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_2 : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec2 pos = FRAGCOORD.xy / max(cell_size, 1.0);
	float row = floor(pos.x);
	float row_variant = mod(row, 2.0);
	float wave_a = cos(TIME * speed - 45.0);
	float wave_b = sin(TIME * speed - 45.0);
	float time_offset = mix(wave_a, wave_b, row_variant);

	pos.y -= time_offset;
	vec2 cell = floor(pos);

	float pattern_mask = mod(cell.x + mod(cell.y, 2.0), 2.0);
	vec4 pattern_color = mix(color_1, color_2, pattern_mask);
	COLOR = vec4(pattern_color.rgb, pattern_color.a * opacity) * texture(TEXTURE, UV);
}
