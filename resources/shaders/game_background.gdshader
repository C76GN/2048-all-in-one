shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.18, 0.18, 0.18, 1.0);
uniform vec4 accent_color : source_color = vec4(0.95, 0.72, 0.36, 1.0);
uniform float grid_strength : hint_range(0.0, 0.25) = 0.08;
uniform float glow_strength : hint_range(0.0, 0.6) = 0.24;
uniform float vignette_strength : hint_range(0.0, 0.9) = 0.34;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.45;

float soft_grid(vec2 uv, float scale) {
	vec2 grid = abs(fract(uv * scale) - 0.5);
	float line = min(grid.x, grid.y);
	return 1.0 - smoothstep(0.0, 0.018, line);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float distance_from_center = length(centered_uv);
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float radial_glow = smoothstep(0.78, 0.0, distance_from_center);
	float grid = soft_grid(UV + vec2(TIME * 0.012, TIME * -0.008), 18.0);
	float vignette = smoothstep(0.28, 0.82, distance_from_center);

	vec3 color = base_color.rgb;
	color = mix(color, accent_color.rgb, radial_glow * glow_strength * (0.75 + pulse * 0.25));
	color += accent_color.rgb * grid * grid_strength;
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(color, base_color.a);
}
