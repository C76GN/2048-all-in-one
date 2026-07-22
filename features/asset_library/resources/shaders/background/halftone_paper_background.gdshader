shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.914, 0.902, 0.863, 1.0);
uniform vec4 accent_color : source_color = vec4(0.620, 0.824, 0.808, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.831, 0.753, 0.482, 1.0);
uniform vec4 warm_color : source_color = vec4(0.718, 0.478, 0.459, 1.0);
uniform vec4 cell_color_1 : source_color = vec4(0.968, 0.956, 0.925, 0.18);
uniform vec4 cell_color_2 : source_color = vec4(0.850, 0.835, 0.792, 0.16);
uniform vec2 grid_size = vec2(192.0, 192.0);
uniform vec2 grid_scroll_speed = vec2(7.0, -3.5);
uniform float line_thickness : hint_range(0.0, 8.0) = 1.0;
uniform float dash_length : hint_range(0.0, 48.0) = 0.0;
uniform vec4 grid_color : source_color = vec4(0.349, 0.290, 0.271, 0.11);
uniform vec2 sub_grid_size = vec2(64.0, 64.0);
uniform float sub_line_thickness : hint_range(0.0, 20.0) = 0.85;
uniform float sub_dash_length : hint_range(0.0, 48.0) = 7.0;
uniform vec4 sub_grid_color : source_color = vec4(0.349, 0.290, 0.271, 0.14);
uniform float grid_strength : hint_range(0.0, 0.25) = 0.085;
uniform float glow_strength : hint_range(0.0, 0.6) = 0.0;
uniform float vignette_strength : hint_range(0.0, 0.9) = 0.045;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.0;
uniform float grain_strength : hint_range(0.0, 0.12) = 0.018;
uniform float stipple_strength : hint_range(0.0, 0.12) = 0.006;
uniform float flow_scale : hint_range(0.5, 8.0) = 1.35;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.0;
uniform vec2 cloud_pixelation = vec2(192.0, 108.0);
uniform vec2 cloud_scroll_speed_1 = vec2(0.0040, 0.0014);
uniform vec2 cloud_scroll_speed_2 = vec2(-0.0032, -0.0009);
uniform vec2 cloud_center_pos = vec2(0.5, 0.08);
uniform float cloud_position_impact : hint_range(0.0, 1.0) = 0.58;
uniform float cloud_strength : hint_range(0.0, 0.16) = 0.024;
uniform vec2 interaction_offset = vec2(0.0);
uniform vec2 interaction_direction = vec2(0.0);
uniform float interaction_energy : hint_range(0.0, 1.0) = 0.0;
uniform float interaction_phase : hint_range(0.0, 1.0) = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise_scaled(vec2 uv, float scale) {
	vec2 cell = floor(uv * scale);
	vec2 f = fract(uv * scale);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 uv) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		value += value_noise_scaled(uv * frequency, 1.0) * amplitude;
		frequency *= 2.05;
		amplitude *= 0.5;
		uv = mat2(vec2(0.84, -0.54), vec2(0.54, 0.84)) * uv;
	}
	return value;
}

float line_pattern(float value, float width) {
	float local = abs(fract(value) - 0.5);
	return 1.0 - smoothstep(width, width + 0.018, local);
}

float dot_pattern(vec2 uv, float radius) {
	vec2 centered = fract(uv) - vec2(0.5);
	float distance_to_center = length(centered);
	return 1.0 - smoothstep(radius, radius + 0.035, distance_to_center);
}

float grid_mask(vec2 pos, vec2 size, float thickness, float dash) {
	if (thickness <= 0.001 || size.x <= 0.001 || size.y <= 0.001) {
		return 0.0;
	}
	vec2 grid = abs(fract(pos / size - vec2(0.5)) - vec2(0.5)) * size;
	float line = 1.0 - smoothstep(thickness, thickness + 1.0, min(grid.x, grid.y));
	float dash_mask = 1.0;
	if (dash > 0.001) {
		dash_mask = step(fract((pos.x + pos.y) / (dash * 2.0)), 0.5);
	}
	return line * dash_mask;
}

float pixel_cloud_mask(vec2 uv) {
	vec2 safe_pixelation = max(cloud_pixelation, vec2(1.0));
	vec2 pixel_uv = floor(uv * safe_pixelation) / safe_pixelation;
	vec2 noise_uv_scale = pixel_uv;
	noise_uv_scale.x *= safe_pixelation.x / safe_pixelation.y;

	vec2 noise_uv_1 = fract(noise_uv_scale + TIME * cloud_scroll_speed_1);
	vec2 noise_uv_2 = fract(noise_uv_scale + vec2(13.17, -7.31) + TIME * cloud_scroll_speed_2);
	float noise_1 = value_noise_scaled(noise_uv_1, 5.0);
	float noise_2 = value_noise_scaled(noise_uv_2, 7.0);
	float noise_value = (noise_1 + noise_2) * 0.5;

	vec2 furthest = vec2(
		-min(sign(cloud_center_pos.x - 0.5), 0.0),
		-min(sign(cloud_center_pos.y - 0.5), 0.0)
	);
	float max_dist = max(distance(cloud_center_pos, furthest), 0.001);
	float dist = clamp(distance(pixel_uv, cloud_center_pos) / max_dist, 0.0, 1.0);
	float warped = mix(1.0 - noise_value, dist, cloud_position_impact);
	return smoothstep(0.18, 0.88, warped);
}

void fragment() {
	vec2 uv = clamp(UV + interaction_offset, vec2(0.0), vec2(1.0));
	vec2 centered_uv = uv - vec2(0.5);

	float paper_grain = hash(floor(FRAGCOORD.xy * 0.55));
	float soft_field = fbm(uv * flow_scale + vec2(0.11, -0.19));
	float cloud_mask = pixel_cloud_mask(uv);
	float side_mask = smoothstep(0.22, 0.48, abs(centered_uv.x));
	float column_mask = 1.0 - smoothstep(0.12, 0.34, abs(centered_uv.x));

	float band_local = fract(uv.y * 7.0);
	float band_mask = step(0.06, band_local) * step(band_local, 0.23);
	float alternate_band = step(0.5, fract(uv.y * 3.5));
	vec3 band_color = mix(secondary_color.rgb, accent_color.rgb, alternate_band);
	float hatch = max(
		line_pattern((uv.x * 32.0) + (uv.y * 18.0), 0.035),
		line_pattern((uv.x * 32.0) - (uv.y * 18.0), 0.035)
	);

	vec2 dot_uv = (uv * vec2(52.0, 32.0)) + vec2(0.25, 0.0);
	float dots = dot_pattern(dot_uv, 0.18) * step(0.58, hash(floor(dot_uv)));
	float registration_edge = line_pattern(uv.x * 20.0, 0.020) * line_pattern(uv.y * 12.0, 0.020);
	vec2 moving_grid_pos = world_pos + TIME * grid_scroll_speed;
	vec2 checker_pos = floor(moving_grid_pos / grid_size);
	float checker = mod(checker_pos.x + checker_pos.y, 2.0);
	vec4 checker_color = mix(cell_color_1, cell_color_2, checker);
	float sub_grid_mask = grid_mask(moving_grid_pos, sub_grid_size, sub_line_thickness, sub_dash_length);
	float main_grid_mask = grid_mask(moving_grid_pos, grid_size, line_thickness, dash_length);
	sub_grid_mask *= 1.0 - main_grid_mask;

	vec3 color = base_color.rgb;
	color = mix(color, vec3(1.0, 0.976, 0.925), column_mask * 0.50);
	color = mix(color, checker_color.rgb, checker_color.a * (0.25 + grid_strength * 2.0));
	color = mix(color, sub_grid_color.rgb, sub_grid_mask * sub_grid_color.a * (0.38 + grid_strength * 2.2));
	color = mix(color, grid_color.rgb, main_grid_mask * grid_color.a * (0.50 + grid_strength * 2.0));
	color = mix(color, accent_color.rgb, smoothstep(0.50, 0.86, soft_field) * 0.055);
	vec3 cloud_shadow = mix(base_color.rgb, accent_color.rgb, 0.28);
	vec3 cloud_highlight = mix(vec3(1.0, 0.976, 0.925), secondary_color.rgb, 0.12);
	vec3 cloud_color = mix(cloud_shadow, cloud_highlight, cloud_mask);
	color = mix(color, cloud_color, cloud_strength * (0.35 + cloud_mask * 0.65));
	float direction_length = length(interaction_direction);
	vec2 safe_direction = direction_length > 0.001
		? interaction_direction / direction_length
		: vec2(0.0);
	float directional_front = clamp(dot(centered_uv, safe_direction) + 0.5, 0.0, 1.0);
	vec3 interaction_color = mix(accent_color.rgb, warm_color.rgb, step(0.72, interaction_energy));
	vec2 interaction_tangent = vec2(-safe_direction.y, safe_direction.x);
	float impact_axis = dot(centered_uv, safe_direction);
	float impact_cross_axis = abs(dot(centered_uv, interaction_tangent));
	float impact_wave_position = mix(-0.62, 0.62, interaction_phase);
	float impact_wave = 1.0 - smoothstep(
		0.018,
		0.095,
		abs(impact_axis - impact_wave_position)
	);
	impact_wave *= 1.0 - smoothstep(0.34, 0.78, impact_cross_axis);
	color = mix(
		color,
		interaction_color,
		interaction_energy * (0.035 + directional_front * 0.075)
	);
	color = mix(
		color,
		mix(interaction_color, vec3(1.0, 0.976, 0.925), 0.42),
		impact_wave * interaction_energy * 0.24
	);
	color = mix(color, band_color, band_mask * side_mask * (0.30 + hatch * 0.24) * grid_strength * 5.0);
	color = mix(color, warm_color.rgb, dots * side_mask * 0.10);
	color = mix(color, secondary_color.rgb, registration_edge * side_mask * 0.035);

	float stipple = step(0.985, hash(FRAGCOORD.xy * 0.61));
	float scanline = line_pattern(FRAGCOORD.y * 0.45, 0.08);
	float vignette = smoothstep(0.50, 0.98, length(centered_uv));
	color += (paper_grain - 0.5) * grain_strength;
	color *= 1.0 - scanline * scanline_strength;
	color = mix(color, warm_color.rgb, stipple * stipple_strength);
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(color, base_color.a);
}
