shader_type canvas_item;

uniform float spacing : hint_range(0.01, 0.40, 0.001) = 0.08;
uniform float thickness : hint_range(0.001, 0.10, 0.001) = 0.02;
uniform float noise_frequency : hint_range(1.0, 64.0, 0.1) = 18.0;
uniform float jitter_amplitude : hint_range(0.0, 0.06, 0.001) = 0.008;
uniform float hatch_angle : hint_range(0.0, 180.0, 0.1) = 135.0;
uniform float progress : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform float outline_width : hint_range(0.0, 0.10, 0.001) = 0.02;
uniform float corner_radius : hint_range(0.0, 0.20, 0.001) = 0.025;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 hatch_color : source_color = vec4(0.184, 0.188, 0.216, 0.22);
uniform vec4 outline_color : source_color = vec4(0.184, 0.188, 0.216, 0.30);
uniform vec4 background_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform bool fill_background = false;

vec2 hash22(vec2 p) {
	float h1 = sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123;
	float h2 = sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123;
	return fract(vec2(h1, h2));
}

vec2 noise2d(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 a = hash22(i);
	vec2 b = hash22(i + vec2(1.0, 0.0));
	vec2 c = hash22(i + vec2(0.0, 1.0));
	vec2 d = hash22(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sd_round_box(vec2 p, vec2 center, vec2 half_size, float radius) {
	vec2 d = abs(p - center) - half_size + vec2(radius);
	vec2 md = max(d, vec2(0.0));
	float outside = length(md) - radius;
	float inside = min(max(d.x, d.y), 0.0);
	return outside + inside;
}

vec2 rotate_uv(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

float shade_hatch_sdf(float distance_to_shape, vec2 p, float angle) {
	vec2 rotated = rotate_uv(p, angle);
	float safe_spacing = max(spacing, 0.001);
	float stripe_index = floor(rotated.y / safe_spacing);
	float local_y = rotated.y - (stripe_index + 0.5) * safe_spacing;
	float jitter = (noise2d(vec2(rotated.x * noise_frequency, stripe_index)).x - 0.5) * jitter_amplitude;
	float distance_to_stripe = abs(local_y + jitter) - thickness;
	float stripe_aa = max(fwidth(distance_to_stripe), 0.0001);
	float stripe_mask = smoothstep(0.0, stripe_aa, -distance_to_stripe);
	float shape_aa = max(fwidth(distance_to_shape), 0.0001);
	float shape_mask = smoothstep(0.0, shape_aa, -distance_to_shape);
	return stripe_mask * shape_mask;
}

float contour_mask(float distance_to_shape) {
	float width = fwidth(distance_to_shape) + outline_width;
	return 1.0 - smoothstep(0.0, width, abs(distance_to_shape));
}

bool is_progressed(vec2 uv) {
	float theta = radians(hatch_angle);
	float direction_span = abs(sin(theta) - cos(theta));
	float diagonal_progress = abs(uv.x * sin(theta) - uv.y * cos(theta));
	return diagonal_progress <= direction_span * progress;
}

vec4 alpha_over(vec4 base, vec4 top) {
	float out_alpha = top.a + base.a * (1.0 - top.a);
	if (out_alpha <= 0.001) {
		return vec4(0.0);
	}
	vec3 out_color = (
		top.rgb * top.a
		+ base.rgb * base.a * (1.0 - top.a)
	) / out_alpha;
	return vec4(out_color, out_alpha);
}

void fragment() {
	vec2 safe_scale = max(abs(uv_scale), vec2(0.001));
	vec2 uv = UV / safe_scale;
	vec2 center = vec2(0.5);
	vec2 half_size = vec2(0.5 - outline_width);
	float distance_to_shape = sd_round_box(uv, center, half_size, corner_radius);

	float hatch_mask = shade_hatch_sdf(distance_to_shape, uv, radians(hatch_angle));
	float outline_mask = contour_mask(distance_to_shape);
	if (!is_progressed(uv)) {
		hatch_mask = 0.0;
	}

	vec4 base_layer = background_color;
	if (!fill_background) {
		base_layer.a = 0.0;
	}
	vec4 hatch_layer = vec4(hatch_color.rgb, hatch_color.a * hatch_mask);
	vec4 outline_layer = vec4(outline_color.rgb, outline_color.a * outline_mask);
	COLOR = alpha_over(alpha_over(base_layer, hatch_layer), outline_layer);
}
