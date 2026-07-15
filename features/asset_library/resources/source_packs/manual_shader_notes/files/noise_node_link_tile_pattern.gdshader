shader_type canvas_item;

uniform float separation : hint_range(0.005, 0.2, 0.001) = 0.05;
uniform float radius : hint_range(0.001, 0.1, 0.001) = 0.006;
uniform float min_thickness_ratio : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float speed : hint_range(0.0, 0.2, 0.001) = 0.04;
uniform bool tilt_45 = true;
uniform bool use_screen_space = false;
uniform float direction_degrees : hint_range(-180.0, 180.0, 0.1) = -45.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform vec4 line_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform vec4 background_color : source_color = vec4(0.0, 0.8, 0.4, 0.0);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool use_texture_alpha = true;

float cross_2d(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

vec2 rotate_uv(vec2 uv, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
}

float get_line(vec2 uv, vec2 point_1, vec2 point_2, vec2 dir) {
	vec2 segment = point_2 - point_1;
	float segment_length = max(length(segment), 0.0001);
	float line_dist = abs(cross_2d(segment, point_1 - uv)) / segment_length;
	float t = clamp(dot(uv - point_1, segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);

	vec2 midpoint = (point_1 + point_2) * 0.5;
	float sample = smoothstep(0.0, 1.0, texture(noise_texture, midpoint - dir * speed * TIME).r);
	float range = max((sample - 0.5) * 2.0 + 0.5, 0.0);
	float min_thickness = radius * min_thickness_ratio * range;
	float max_thickness = radius * 0.95;
	float line_thickness = mix(max_thickness, min_thickness, exp(-pow((t - 0.5) * 4.0, 2.0)));

	float line = step(line_dist, line_thickness * 0.8);
	line *= step(0.2, sample);
	return line;
}

void fragment() {
	float direction_radians = radians(direction_degrees);
	vec2 dir = vec2(sin(direction_radians), cos(direction_radians));
	vec2 pattern_uv = UV;

	if (use_screen_space) {
		float ratio = SCREEN_PIXEL_SIZE.x / max(SCREEN_PIXEL_SIZE.y, 0.000001);
		pattern_uv = vec2(SCREEN_UV.x, SCREEN_UV.y * ratio);
	} else {
		pattern_uv *= max(abs(uv_scale), vec2(0.001));
	}

	pattern_uv += dir * speed * TIME;
	if (tilt_45) {
		pattern_uv = rotate_uv(pattern_uv, PI * 0.25);
	}

	vec2 point_1 = vec2(floor(pattern_uv.x / separation), round(pattern_uv.y / separation)) * separation;
	vec2 point_2 = vec2(point_1.x + separation, point_1.y);
	vec2 cross_point_1 = vec2(round(pattern_uv.x / separation), floor(pattern_uv.y / separation)) * separation;
	vec2 cross_point_2 = vec2(cross_point_1.x, cross_point_1.y + separation);

	float circle_1 = step(distance(pattern_uv, point_1), radius);
	float circle_2 = step(distance(pattern_uv, point_2), radius);
	float circle_3 = step(distance(pattern_uv, cross_point_1), radius);
	float circle_4 = step(distance(pattern_uv, cross_point_2), radius);
	float line_1 = get_line(pattern_uv, point_1, point_2, dir);
	float line_2 = get_line(pattern_uv, cross_point_1, cross_point_2, dir);

	float shape = max(max(max(circle_1, circle_2), max(circle_3, circle_4)), max(line_1, line_2));
	vec4 pattern_color = mix(background_color, line_color, shape);

	float texture_alpha = 1.0;
	if (use_texture_alpha) {
		texture_alpha = texture(TEXTURE, UV).a;
	}
	COLOR = vec4(pattern_color.rgb, pattern_color.a * opacity * texture_alpha);
}
