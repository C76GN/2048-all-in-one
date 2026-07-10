shader_type canvas_item;

uniform vec4 fore_color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform vec4 back_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float pattern_scale : hint_range(1.0, 32.0, 0.5) = 10.0;
uniform float rotation_degrees : hint_range(-180.0, 180.0, 0.1) = 45.0;
uniform float speed : hint_range(0.0, 8.0, 0.01) = 1.0;
uniform float contrast : hint_range(0.0, 2.0, 0.01) = 0.95;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
	vec2 texture_size = 1.0 / max(TEXTURE_PIXEL_SIZE, vec2(0.000001));
	float aspect = texture_size.y / texture_size.x;
	vec2 uv = UV;
	uv -= vec2(0.5, 0.5 * aspect);
	float rotation = radians(rotation_degrees);
	mat2 rotation_matrix = mat2(
		vec2(cos(rotation), -sin(rotation)),
		vec2(sin(rotation), cos(rotation))
	);
	uv = rotation_matrix * uv;
	uv += vec2(0.5, 0.5 * aspect);
	uv.y += 0.5 * (1.0 - aspect);

	vec2 position = pattern_scale * uv;
	vec2 repeated = fract(position);
	float line_distance = 2.0 * min(
		min(repeated.x, 1.0 - repeated.x),
		min(repeated.y, 1.0 - repeated.y)
	);
	float square_distance = length((floor(position) + vec2(0.5)) - vec2(pattern_scale * 0.5));
	float edge = (TIME * speed - square_distance * 0.5) * 0.5;
	edge = 2.0 * fract(edge * 0.5);
	float value = fract(line_distance * 2.0);
	value = mix(value, 1.0 - value, step(1.0, edge));
	edge = pow(abs(1.0 - edge), 2.0);
	value = smoothstep(edge - 0.05, edge, contrast * value);
	value += square_distance * 0.1;

	vec4 color = mix(back_color, fore_color, clamp(value, 0.0, 1.0));
	COLOR = vec4(color.rgb, color.a * opacity);
}
