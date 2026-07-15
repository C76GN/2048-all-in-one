shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 shine_color : source_color = vec4(1.0);
uniform float shine_angle : hint_range(0.0, 180.0, 0.1) = 45.0;
uniform float shine_speed : hint_range(0.01, 10.0, 0.01) = 0.3;
uniform float shine_delay : hint_range(0.0, 5.0, 0.1) = 0.0;
uniform bool shine_reverse = false;

uniform float line_width : hint_range(0.0, 0.2) = 0.09;
uniform float line_smoothness : hint_range(0.001, 0.1) = 0.045;
uniform float brightness : hint_range(0.0, 10.0) = 3.0;
uniform float distortion : hint_range(1.0, 3.0) = 2.0;
uniform float lens_strength : hint_range(0.0, 0.1) = 0.05;

void fragment() {
	vec2 uv = UV;
	float angle_rad = radians(shine_angle);
	vec2 shine_dir = normalize(vec2(cos(angle_rad), -sin(angle_rad)));
	vec2 shine_normal = vec2(-shine_dir.y, shine_dir.x);

	vec2 center_uv = uv - vec2(0.5);
	float gradient_to_edge = 1.0 - max(abs(center_uv.x), abs(center_uv.y)) * distortion;
	gradient_to_edge = clamp(gradient_to_edge, 0.0, 1.0);

	float safe_shine_speed = max(shine_speed, 0.01);
	float cycle_duration = (1.0 / safe_shine_speed) + shine_delay;
	float time_in_cycle = mod(TIME, cycle_duration);
	float shine_progress = clamp(time_in_cycle * safe_shine_speed, 0.0, 1.0);
	if (shine_reverse) {
		shine_progress = 1.0 - shine_progress;
	}

	float offset = mix(-1.5, 1.5, shine_progress);
	vec2 shine_origin = vec2(0.5) + shine_normal * offset;
	float distance_to_line = dot(uv - shine_origin, shine_normal);
	float smoothness = clamp(line_smoothness, 0.001, 1.0);
	float half_width = line_width * 0.5;
	float shine = smoothstep(-half_width - smoothness, -half_width, distance_to_line)
		- smoothstep(half_width, half_width + smoothness, distance_to_line);

	vec2 lens_offset = shine * lens_strength * shine_normal;
	vec4 base_color = texture(TEXTURE, uv + lens_offset);
	if (base_color.a <= 0.0) {
		discard;
	}

	shine *= base_color.a;
	float final_intensity = clamp(shine * gradient_to_edge * brightness, 0.0, shine_color.a);
	vec3 final_color = mix(base_color.rgb, shine_color.rgb, final_intensity);
	COLOR = vec4(final_color, base_color.a);
}
