shader_type canvas_item;

uniform vec2 rect_size = vec2(180.0, 48.0);
uniform float radius : hint_range(0.0, 100.0) = 7.0;
uniform float thickness : hint_range(0.0, 20.0) = 3.0;
uniform vec4 color : source_color = vec4(0.5804, 0.2667, 0.1922, 1.0);
uniform float dash_count : hint_range(1.0, 50.0) = 18.0;
uniform float dash_ratio : hint_range(0.0, 1.0) = 0.54;
uniform float speed = 0.65;

const float HALF_PI = 1.57079632679;
const float PI_VALUE = 3.14159265359;
const float TWO_PI = 6.28318530718;

float rounded_box_sdf(vec2 point, vec2 half_size, float corner_radius) {
	vec2 q = abs(point) - half_size + corner_radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
}

float get_rounded_path_position(vec2 point, vec2 inner, float corner_radius, float total_len) {
	vec2 q = abs(point) - inner;
	float path_pos = 0.0;

	if (q.x > 0.0 && q.y > 0.0) {
		vec2 dir = sign(point);
		vec2 center_offset = dir * inner;
		vec2 rel = point - center_offset;
		float angle = 0.0;

		if (point.x > 0.0 && point.y < 0.0) {
			angle = atan(rel.x, -rel.y);
			path_pos = inner.x + angle * corner_radius;
		} else if (point.x > 0.0 && point.y > 0.0) {
			angle = atan(rel.y, rel.x);
			path_pos = inner.x + HALF_PI * corner_radius + inner.y * 2.0 + angle * corner_radius;
		} else if (point.x < 0.0 && point.y > 0.0) {
			angle = atan(-rel.x, rel.y);
			path_pos = inner.x + PI_VALUE * corner_radius + inner.y * 2.0 + inner.x * 2.0 + angle * corner_radius;
		} else {
			angle = atan(-rel.y, -rel.x);
			path_pos = inner.x + PI_VALUE * 1.5 * corner_radius + inner.y * 2.0 + inner.x * 2.0 + inner.y * 2.0 + angle * corner_radius;
		}
	} else {
		if (point.y <= -inner.y) {
			if (point.x >= 0.0) {
				path_pos = point.x;
			} else {
				path_pos = total_len + point.x;
			}
		} else if (point.x >= inner.x) {
			path_pos = inner.x + HALF_PI * corner_radius + (point.y + inner.y);
		} else if (point.y >= inner.y) {
			path_pos = inner.x + PI_VALUE * corner_radius + inner.y * 2.0 + (inner.x - point.x);
		} else if (point.x <= -inner.x) {
			path_pos = inner.x + PI_VALUE * 1.5 * corner_radius + inner.x * 2.0 + inner.y * 2.0 + (inner.y - point.y);
		}
	}

	return clamp(path_pos / max(total_len, 1.0), 0.0, 1.0);
}

void fragment() {
	vec2 size = max(rect_size, vec2(1.0));
	vec2 point = (UV - vec2(0.5)) * size;
	vec2 half_size = size * 0.5;
	float corner_radius = min(radius, min(half_size.x, half_size.y));
	float distance_to_edge = rounded_box_sdf(point, half_size, corner_radius);
	float border_mask = smoothstep(0.5, -0.5, abs(distance_to_edge + thickness * 0.5) - thickness * 0.5);

	vec2 inner = max(half_size - vec2(corner_radius), vec2(0.0));
	float total_len = 4.0 * (inner.x + inner.y) + TWO_PI * corner_radius;
	float normalized_path = get_rounded_path_position(point, inner, corner_radius, total_len);
	float segment = 1.0 / max(1.0, dash_count);
	float dash_offset = TIME * speed * 0.1;
	float dash_mod = mod(normalized_path + dash_offset, segment) / segment;
	float dash_mask = step(dash_mod, dash_ratio);

	COLOR = vec4(color.rgb, color.a * border_mask * dash_mask);
}
