shader_type canvas_item;

uniform float aspect = 8.0;
uniform vec4 progress_color : source_color = vec4(0.61960787, 0.8235294, 0.80784315, 1.0);
uniform vec4 background_color : source_color = vec4(0.94509804, 0.8862745, 0.74509805, 1.0);
uniform vec4 outline_color : source_color = vec4(0.34901962, 0.2901961, 0.27058825, 1.0);
uniform float progress : hint_range(0.0, 1.0, 0.001) = 0.0;

const float CORNER_RADIUS = 0.20;
const float GRAIN_DARKNESS = 0.014;
const vec4 WHITE_COLOR = vec4(1.0);
const float GRADIENT_LENGTH = 0.06;
const float STAR_SIZE = 20.0;
const float EDGE_SOFTNESS = 0.005;
const float BORDER_SIZE = 0.095;

float sd_box(vec2 pos, vec2 half_size) {
	vec2 d = abs(pos) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_rounded_box(vec2 pos, vec2 half_size, float radius) {
	return sd_box(pos, half_size) - radius;
}

float sd_star(vec2 point, float radius) {
	const vec2 v1 = vec2(0.809016994, -0.587785252);
	const vec2 v2 = vec2(-0.809016994, -0.587785252);
	const vec2 v3 = vec2(0.309016994, -0.951056516);
	const float k1z = 0.726542528;

	point.x = abs(point.x);
	point -= 2.0 * max(dot(v1, point), 0.0) * v1;
	point -= 2.0 * max(dot(v2, point), 0.0) * v2;
	point.x = abs(point.x);
	point.y -= radius;
	return length(point - v3 * clamp(dot(point, v3), 0.0, k1z * radius))
		* sign(point.y * v3.x - point.x * v3.y);
}

float sd_rounded_star(vec2 point, float radius, float corner_radius) {
	return sd_star(point, radius) - corner_radius;
}

void fragment() {
	float safe_aspect = max(aspect, 0.001);
	vec2 aspect_scale = vec2(safe_aspect, 1.0);
	vec2 half_size = vec2(0.5) * aspect_scale;
	vec2 pos = UV * aspect_scale - half_size;
	float rect_distance = sd_rounded_box(pos, half_size - CORNER_RADIUS, CORNER_RADIUS);

	if (UV.x <= progress) {
		COLOR = progress_color;

		float position_gradient = UV.x - (progress - GRADIENT_LENGTH);
		float normalized_position = clamp(position_gradient / GRADIENT_LENGTH, 0.0, 1.0);
		COLOR += WHITE_COLOR * normalized_position * 0.16;

		float shift = TIME * STAR_SIZE;
		vec2 grid_coord = (FRAGCOORD.xy + vec2(-shift, shift)) / STAR_SIZE;
		const mat2 rot36 = mat2(vec2(0.8090, -0.5878), vec2(0.5878, 0.8090));
		grid_coord *= rot36;
		float index_y = floor(grid_coord.y);
		vec2 fraction = fract(grid_coord);
		if (mod(index_y, 2.0) == 1.0) {
			fraction.x = fract(grid_coord.x + 0.5);
		}

		vec2 star_pos = fraction - vec2(0.5);
		float star_distance = sd_rounded_star(star_pos, 0.4, 0.02);
		if (star_distance < 0.0) {
			COLOR.rgb *= 0.93;
		}
	} else {
		float grain = mod(floor(FRAGCOORD.x * 0.3) + floor(FRAGCOORD.y * 0.3), 3.0);
		COLOR = vec4(background_color.rgb - vec3(grain * GRAIN_DARKNESS), background_color.a);
	}

	float border_alpha = 1.0 - smoothstep(BORDER_SIZE - EDGE_SOFTNESS, BORDER_SIZE, abs(rect_distance));
	COLOR = mix(COLOR, outline_color, border_alpha);

	float smoothed_alpha = 1.0 - smoothstep(0.0, EDGE_SOFTNESS, rect_distance);
	COLOR.a *= smoothed_alpha;
}
