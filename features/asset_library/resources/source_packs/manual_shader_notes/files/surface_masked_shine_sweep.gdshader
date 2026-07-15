shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float line_smoothness : hint_range(0.001, 0.1, 0.001) = 0.045;
uniform float line_width : hint_range(0.0, 0.2, 0.001) = 0.09;
uniform float brightness : hint_range(0.0, 10.0, 0.01) = 3.0;
uniform float rotation_degrees : hint_range(-90.0, 90.0, 0.1) = 30.0;
uniform float distortion : hint_range(1.0, 2.0, 0.01) = 1.8;
uniform float speed : hint_range(-4.0, 4.0, 0.01) = 0.7;
uniform float position : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float position_min : hint_range(0.0, 1.0, 0.001) = 0.25;
uniform float position_max : hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float alpha : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D surface_texture : source_color, filter_linear;
uniform bool use_surface_alpha = true;

vec2 rotate_uv(vec2 uv, vec2 center, float rotation) {
	float angle = radians(rotation);
	mat2 rotation_matrix = mat2(
		vec2(cos(angle), -sin(angle)),
		vec2(sin(angle), cos(angle))
	);
	vec2 delta = uv - center;
	return rotation_matrix * delta + center;
}

void fragment() {
	vec2 center_uv = UV - vec2(0.5);
	float gradient_to_edge = max(abs(center_uv.x), abs(center_uv.y));
	gradient_to_edge = clamp(1.0 - gradient_to_edge * distortion, 0.0, 1.0);

	vec2 rotated_uv = rotate_uv(UV, vec2(0.5), rotation_degrees);
	float remapped_position = mix(position_min, position_max, position);
	float sweep_position = fract(TIME * speed + remapped_position);
	sweep_position = -2.0 + 4.0 * sweep_position;

	float line_distance = abs(rotated_uv.x + sweep_position);
	line_distance = sqrt(max(gradient_to_edge * line_distance, 0.0));

	float safe_smoothness = clamp(line_smoothness, 0.001, 1.0);
	float outer_edge = line_width + safe_smoothness;
	float inner_edge = max(line_width - safe_smoothness, 0.0);
	float shine_mask = clamp((outer_edge - line_distance) / max(outer_edge - inner_edge, 0.001), 0.0, 1.0);
	shine_mask = min(shine_mask * brightness, alpha);

	vec4 base_color = texture(TEXTURE, UV) * COLOR;
	float surface_alpha = 1.0;
	if (use_surface_alpha) {
		surface_alpha = texture(surface_texture, UV).a;
	}

	vec4 shine = vec4(shine_color.rgb * shine_mask, shine_color.a * shine_mask);
	COLOR = vec4(base_color.rgb * shine.rgb, base_color.a * shine.a * surface_alpha);
}
