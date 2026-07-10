shader_type canvas_item;

uniform vec4 color1 : source_color = vec4(0.74, 0.88, 0.85, 1.0);
uniform vec4 color2 : source_color = vec4(0.94, 0.86, 0.65, 1.0);
uniform float brightness : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float time_offset = 0.0;
uniform float time_rate : hint_range(0.0, 8.0, 0.01) = 1.0;
uniform float noise_amount : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float offset_x = 0.0;
uniform float flicker_threshold : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float alpha_steps : hint_range(1.0, 64.0, 1.0) = 20.0;

void fragment() {
	vec4 base_color = mix(color1, color2, texture(noise_texture, UV).r);
	float dist = 1.0 - distance(UV, vec2(0.5));
	float flicker_value = texture(noise_texture, vec2(TIME + time_offset, (TIME + time_offset) * 0.9)).r;
	if (flicker_value > flicker_threshold) {
		dist *= flicker_value / max(0.001, 1.0 - flicker_threshold) * 0.62;
	}

	float wave = cos(UV.x * 10.0 + TIME * time_rate + time_offset + offset_x) * 0.02;
	float pulse = cos(TIME * time_rate * 2.0 + time_offset * 2.0) * 0.03;
	float alpha = dist + wave + brightness + pulse;
	vec2 noise_uv = vec2(UV.x + time_offset * -0.1 + TIME * time_rate * -0.1 + offset_x, UV.y);
	float noise_sample = texture(noise_texture, noise_uv + vec2(brightness * 4.0)).r;
	alpha = (alpha * (2.0 - noise_amount) + noise_sample * noise_amount) / 2.0;
	alpha = round(alpha * alpha_steps) / alpha_steps;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(base_color.rgb, base_color.a * alpha);
}
