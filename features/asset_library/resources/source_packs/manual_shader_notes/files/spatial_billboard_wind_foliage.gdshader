shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;

uniform bool billboard = false;

uniform sampler2D shape_texture;
uniform sampler2D shape_atlas;
uniform bool use_atlas = false;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;

group_uniforms Wind;
uniform sampler2D wind_texture;
uniform vec2 wind_velocity = vec2(1.0, 0.0);

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.1;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform int alpha_mode : hint_enum("Smooth", "Dithered", "Cut") = 0;

varying flat int instance_index;
varying vec3 world_pos;

float bayer4(vec2 pixel) {
	vec2 p = mod(floor(pixel), 4.0);
	int x = int(p.x);
	int y = int(p.y);
	int index = x + y * 4;
	float threshold = 0.0;
	if (index == 0) {
		threshold = 0.0;
	} else if (index == 1) {
		threshold = 8.0;
	} else if (index == 2) {
		threshold = 2.0;
	} else if (index == 3) {
		threshold = 10.0;
	} else if (index == 4) {
		threshold = 12.0;
	} else if (index == 5) {
		threshold = 4.0;
	} else if (index == 6) {
		threshold = 14.0;
	} else if (index == 7) {
		threshold = 6.0;
	} else if (index == 8) {
		threshold = 3.0;
	} else if (index == 9) {
		threshold = 11.0;
	} else if (index == 10) {
		threshold = 1.0;
	} else if (index == 11) {
		threshold = 9.0;
	} else if (index == 12) {
		threshold = 15.0;
	} else if (index == 13) {
		threshold = 7.0;
	} else if (index == 14) {
		threshold = 13.0;
	} else {
		threshold = 5.0;
	}
	return (threshold + 0.5) / 16.0;
}

vec2 get_atlas_uv(vec2 uv, int index, int size) {
	int tile_count = size * size;
	int wrapped_index = index % tile_count;
	float x = float(wrapped_index % size);
	float y = float(wrapped_index / size);
	vec2 tile_size = 1.0 / vec2(float(size));
	return uv * tile_size + vec2(x, y) * tile_size;
}

float randomf(int index, int seed) {
	return sin(float(index + seed)) * 0.5 + 0.5;
}

float sample_wind_noise() {
	vec2 wind_uv = world_pos.xz * 0.03 - vec2(TIME * 0.01) * wind_velocity;
	return texture(wind_texture, wind_uv).r;
}

vec3 wind(vec2 uv) {
	float sampled_wind = sample_wind_noise();
	float wind_affect = pow(1.0 - uv.y, 2.0);
	vec3 value = vec3(
		sampled_wind * wind_velocity.x,
		0.0,
		sampled_wind * wind_velocity.y
	) * 0.25;
	return value * wind_affect;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	instance_index = INSTANCE_ID;

	if (billboard) {
		mat4 billboard_matrix = mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]
		);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard_matrix;
		VERTEX += (VIEW_MATRIX * vec4(wind(UV), 0.0)).xyz;
	} else {
		VERTEX += wind(UV);
	}

	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float shape_value = texture(shape_texture, UV).r;
	if (use_atlas) {
		vec2 sampled_atlas_uv = get_atlas_uv(UV, instance_index, 2);
		shape_value = texture(shape_atlas, sampled_atlas_uv).r;
	}

	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	if (randomf(instance_index, 1) < random_variation) {
		noise_value += 0.4;
	}

	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));
	ALBEDO = color.rgb;

	if (alpha_mode == 0) {
		ALPHA = shape_value;
		return;
	}

	float alpha_range = max(alpha_cut_end - alpha_cut_start, 0.001);
	float alpha = clamp((shape_value - alpha_cut_start) / alpha_range, 0.0, 1.0);
	if (alpha_mode == 1) {
		alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
		if (alpha < 0.1) {
			discard;
		}
		ALPHA = 1.0;
		return;
	}

	if (alpha < 0.5) {
		discard;
	}
	ALPHA = 1.0;
}

void light() {
	float ndotl = dot(LIGHT, NORMAL) * ATTENUATION;
	DIFFUSE_LIGHT += vec3(ndotl);
}
