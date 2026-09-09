shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.94902, 0.91373, 0.81176, 1.0);
uniform vec4 ink_color : source_color = vec4(0.14510, 0.13725, 0.12157, 1.0);
uniform vec4 accent_color : source_color = vec4(0.8, 0.23137, 0.18431, 1.0);
uniform vec2 node_resolution = vec2(1280.0, 720.0);
uniform float factor : hint_range(0.0, 1.0) = 0.0;
uniform bool reverse_progress = false;

void fragment() {
	float progress = reverse_progress ? 1.0 - factor : factor;
	float edge = mix(-0.03, 1.09, progress);
	float sheet_position = UV.x + UV.y * 0.055;
	float pixel_width = 1.0 / max(node_resolution.x, 1.0);
	float coverage = 1.0 - smoothstep(edge - pixel_width, edge + pixel_width, sheet_position);
	float from_edge = edge - sheet_position;
	float ink_rule = 1.0 - smoothstep(0.0, pixel_width * 3.0, abs(from_edge - 0.008));
	float red_rule = 1.0 - smoothstep(0.0, pixel_width * 2.0, abs(from_edge - 0.018));
	vec3 color = mix(base_color.rgb, ink_color.rgb, ink_rule);
	color = mix(color, accent_color.rgb, red_rule);
	COLOR = vec4(color, coverage * base_color.a);
}
