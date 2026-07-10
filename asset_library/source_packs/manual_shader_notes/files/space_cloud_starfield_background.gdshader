shader_type canvas_item;

uniform bool stars_on = true;
uniform bool stars_flicker = true;
uniform float time_scale_factor = 0.04;

uniform sampler2D noise_texture : repeat_enable, filter_linear;

uniform vec4 color_multiplier : source_color = vec4(1.0);
uniform vec4 color_multiplier_secondary : source_color = vec4(1.0);

uniform float brightness : hint_range(0.0, 3.0) = 1.2;
uniform float clouds_resolution : hint_range(0.0, 20.0) = 10.0;
uniform float clouds_intensity : hint_range(-0.06, 0.5) = 0.0;
uniform float waviness : hint_range(0.0, 10.0) = 0.5;
uniform float fragmentation : hint_range(0.0, 100.0) = 7.0;
uniform float distortion : hint_range(0.0, 10.0) = 1.5;
uniform float clouds_alpha : hint_range(0.4, 0.6) = 0.5;
uniform float movement : hint_range(0.7, 2.0) = 1.3;
uniform float octave_scale : hint_range(0.0, 10.0) = 1.4;
uniform float noise_uv_scale : hint_range(0.0, 0.01) = 0.01;

uniform float background_speed = 0.1;
uniform float midground_speed = 0.5;
uniform float foreground_speed = 1.0;

float local_time() {
	return TIME * time_scale_factor;
}

mat2 make_rotation(float theta) {
	float c = cos(theta);
	float s = sin(theta);
	return mat2(vec2(c, -s), vec2(s, c));
}

float sample_noise_r(vec2 x) {
	return texture(noise_texture, x * noise_uv_scale).r;
}

float sample_noise_g(vec2 y) {
	return texture(noise_texture, y * noise_uv_scale).g;
}

vec2 gradient_noise(vec2 p) {
	float ep = 0.09;
	float grad_x = sample_noise_r(vec2(p.x + ep, p.y)) - sample_noise_r(vec2(p.x - ep, p.y));
	float grad_y = sample_noise_g(vec2(p.x, p.y + ep)) - sample_noise_g(vec2(p.x, p.y - ep));
	return vec2(grad_x, grad_y);
}

float flow(vec2 p) {
	float z = 2.0;
	float rz = clouds_intensity;
	vec2 base_p = p;

	for (int index = 1; index < 7; index++) {
		float i = float(index);
		p += local_time() * 0.6;
		base_p += local_time() * 5.9;

		vec2 gradient = gradient_noise(i * p * 0.34 + local_time());
		gradient *= make_rotation(local_time() * 6.0 - (0.05 * p.x + 0.03 * p.y) * 90.0);
		p += gradient * waviness;

		rz += (sin(sample_noise_r(p) * fragmentation) * distortion + clouds_alpha) / z;
		p = mix(base_p, p, movement);
		z *= max(octave_scale, 0.001);
		p *= 2.0;
		base_p *= 1.9;
	}

	return max(abs(rz), 0.001);
}

float rand(vec2 st) {
	return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * clouds_resolution * clouds_resolution;

	vec2 background_p = p * background_speed;
	vec2 midground_p = p * midground_speed;
	vec2 foreground_p = p * foreground_speed;

	float red = 0.2 * sin(TIME * 0.1);
	float blue = 0.1;
	float green = 0.1;

	vec3 cloud_base = vec3(red, blue, green);
	vec3 col_background = cloud_base / flow(background_p);
	vec3 col_midground = cloud_base / flow(midground_p);
	vec3 col_foreground = cloud_base / flow(foreground_p);

	col_background = pow(col_background, vec3(brightness));
	col_midground = pow(col_midground, vec3(brightness));
	col_foreground = pow(col_foreground, vec3(brightness));

	float stars = 0.0;
	vec2 star_uv = UV * 100.0 + local_time() * background_speed * 20.0;
	vec2 grid_pos = floor(star_uv);
	vec2 local_pos = fract(star_uv);
	float rand_value = rand(grid_pos);
	if (rand_value > 0.965) {
		float dist = distance(local_pos, vec2(0.5));
		float intensity = smoothstep(0.05, 0.0, dist);
		float flicker = 1.0;
		if (stars_flicker) {
			flicker = 0.5 + 0.5 * sin(TIME * (rand_value * 3.0) + rand_value * 100.0);
		}
		stars = intensity * flicker * rand_value;
	}

	vec3 final_color = col_background + col_midground + col_foreground;
	if (stars_on) {
		final_color += vec3(stars);
	}

	COLOR = vec4(final_color * color_multiplier.rgb, 1.0) * color_multiplier_secondary;
}
