shader_type canvas_item;

uniform vec3 color_one : source_color = vec3(0.96, 0.89, 0.72);
uniform vec3 color_two : source_color = vec3(0.78, 0.66, 0.47);
uniform float angle : hint_range(-180.0, 180.0, 0.1) = 20.0;
uniform float line_count : hint_range(1.0, 80.0, 0.1) = 20.0;
uniform float speed : hint_range(-40.0, 40.0, 0.01) = 10.0;
uniform float blur : hint_range(0.001, 2.0, 0.001) = 0.15;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

vec2 rotate_uv(vec2 uv, float rotation_angle) {
	float radians_angle = radians(rotation_angle);
	float cos_angle = cos(radians_angle);
	float sin_angle = sin(radians_angle);
	mat2 rotation_matrix = mat2(
		vec2(cos_angle, -sin_angle),
		vec2(sin_angle, cos_angle)
	);
	return uv * rotation_matrix;
}

float stripe(vec2 uv) {
	return cos(-TIME * speed + uv.y * -line_count * 0.5);
}

void fragment() {
	vec2 uv = UV;
	vec2 resolution = 1.0 / TEXTURE_PIXEL_SIZE;
	float aspect = resolution.x / resolution.y;
	uv.x *= aspect;
	uv = rotate_uv(uv, angle);

	float stripe_value = stripe(uv);
	float stripe_mask = smoothstep(-blur, blur, stripe_value);
	vec3 pattern_color = mix(color_one, color_two, stripe_mask);
	COLOR = vec4(pattern_color, opacity) * texture(TEXTURE, UV);
}
