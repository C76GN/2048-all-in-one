shader_type canvas_item;

uniform float shine_count : hint_range(1.0, 32.0, 1.0) = 8.0;
uniform float rotation_speed : hint_range(-12.0, 12.0, 0.01) = 3.0;
uniform float light_magnitude : hint_range(0.0, 6.0, 0.01) = 2.0;

uniform float filter_distance : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform float filter_magnitude : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform float filter_min_value : hint_range(0.0, 1.0, 0.001) = 0.75;
uniform float cut_inner_radius : hint_range(0.0, 0.5, 0.001) = 0.1;

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D noise_texture : source_color, repeat_enable, filter_linear;
uniform vec2 noise_speed = vec2(0.0, 0.0);
uniform float noise_magnitude : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform bool use_texture_alpha = true;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float distance_to_center = length(centered);
	if (distance_to_center > 0.5 || distance_to_center < cut_inner_radius) {
		COLOR = vec4(0.0);
		return;
	}

	float angle = atan(centered.y, centered.x);
	float ray_mask = abs(sin(angle * shine_count * 0.5 + TIME * rotation_speed));
	vec4 ray_color = shine_color * ray_mask;

	vec2 noise_uv = fract(UV + noise_speed * TIME);
	vec4 noise_color = smoothstep(vec4(0.0), vec4(1.0), texture(noise_texture, noise_uv)) * shine_color;
	vec4 mixed_color = mix(ray_color, noise_color, noise_magnitude);

	float brightness = max(max(mixed_color.r, mixed_color.g), mixed_color.b);
	if (brightness < filter_min_value) {
		COLOR = vec4(0.0);
		return;
	}

	float radial_alpha = clamp(
		((1.0 - filter_distance * 0.5) - distance_to_center * filter_magnitude) * light_magnitude,
		0.0,
		1.0
	);
	float texture_alpha = 1.0;
	if (use_texture_alpha) {
		texture_alpha = texture(TEXTURE, UV).a;
	}

	COLOR = vec4(mixed_color.rgb, mixed_color.a * radial_alpha * texture_alpha);
}
