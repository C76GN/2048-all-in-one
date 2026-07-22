shader_type canvas_item;

const int PARTICLE_COUNT = 88;

uniform float speed : hint_range(20.0, 500.0) = 105.0;
uniform float sway_strength : hint_range(0.0, 200.0) = 38.0;
uniform float sway_speed : hint_range(0.1, 5.0) = 1.15;
uniform float spin_speed : hint_range(0.0, 10.0) = 2.8;
uniform float piece_size : hint_range(2.0, 30.0) = 7.0;
uniform float aspect_ratio : hint_range(0.2, 3.0) = 1.85;
uniform vec2 resolution = vec2(1280.0, 720.0);
uniform float drain_started_at = -1.0;

uniform vec4 col0 : source_color = vec4(0.6196, 0.8588, 0.8353, 1.0);
uniform vec4 col1 : source_color = vec4(0.9373, 0.8196, 0.3647, 1.0);
uniform vec4 col2 : source_color = vec4(0.8745, 0.2941, 0.6039, 1.0);
uniform vec4 col3 : source_color = vec4(0.5804, 0.2667, 0.1922, 1.0);
uniform vec4 col4 : source_color = vec4(0.2706, 0.3176, 0.3843, 1.0);
uniform vec4 col5 : source_color = vec4(0.9451, 0.8863, 0.7451, 1.0);
uniform vec4 col6 : source_color = vec4(0.6784, 0.6157, 0.3843, 1.0);
uniform vec4 col7 : source_color = vec4(0.1843, 0.1882, 0.2157, 1.0);

float rand(float seed) {
	return fract(sin(seed * 127.1 + 311.7) * 43758.5453);
}

vec4 palette_color(float t) {
	int index = int(t * 8.0) % 8;
	if (index == 0) {
		return col0;
	}
	if (index == 1) {
		return col1;
	}
	if (index == 2) {
		return col2;
	}
	if (index == 3) {
		return col3;
	}
	if (index == 4) {
		return col4;
	}
	if (index == 5) {
		return col5;
	}
	if (index == 6) {
		return col6;
	}
	return col7;
}

vec2 rotate2d(vec2 value, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(c * value.x - s * value.y, s * value.x + c * value.y);
}

void fragment() {
	vec2 px = UV * resolution;
	vec4 out_color = vec4(0.0);

	for (int i = 0; i < PARTICLE_COUNT; i++) {
		float fi = float(i);

		float start_x = rand(fi * 1.234) * resolution.x;
		float my_speed = speed * (0.5 + rand(fi * 2.222));
		float my_sway_strength = sway_strength * (0.3 + rand(fi * 3.333) * 1.4);
		float my_sway_speed = sway_speed * (0.5 + rand(fi * 4.444) * 1.5);
		float my_sway_phase = rand(fi * 6.666) * TAU;
		float my_spin = spin_speed * (0.5 + rand(fi * 7.777) * 1.5) * (step(0.5, rand(fi * 8.888)) * 2.0 - 1.0);
		float my_size = piece_size * (0.55 + rand(fi * 0.123) * 0.85);
		float my_aspect_ratio = aspect_ratio * (0.72 + rand(fi * 0.456) * 0.56);
		float travel_distance = resolution.y + my_size * 4.0;
		float travel_time = travel_distance / max(my_speed, 0.001);
		float time_offset = rand(fi * 9.101) * travel_time;
		float particle_time = TIME + time_offset;
		float cycle = floor(particle_time / travel_time);
		float phase = fract(particle_time / travel_time);
		float cycle_visibility = 1.0;
		if (drain_started_at >= 0.0) {
			float drain_cycle = floor((drain_started_at + time_offset) / travel_time);
			cycle_visibility = 1.0 - step(drain_cycle + 0.5, cycle);
		}

		float center_y = mix(-my_size * 2.0, resolution.y + my_size * 2.0, phase);
		float center_x = start_x + my_sway_strength * sin(particle_time * my_sway_speed + my_sway_phase);
		float angle = particle_time * my_spin;

		vec2 delta = px - vec2(center_x, center_y);
		delta = rotate2d(delta, -angle);
		vec2 local = delta / vec2(my_size * my_aspect_ratio, my_size);
		float inside = step(max(abs(local.x), abs(local.y)), 1.0) * cycle_visibility;

		if (inside > 0.5) {
			float shimmer = 0.5 + 0.5 * sin(particle_time * my_spin * 2.0);
			vec4 base_color = palette_color(rand(fi * 0.321));
			vec4 lit_color = mix(base_color * 0.58, base_color, shimmer);
			lit_color.a = 0.92;
			out_color = mix(out_color, lit_color, inside);
		}
	}

	COLOR = out_color;
}
