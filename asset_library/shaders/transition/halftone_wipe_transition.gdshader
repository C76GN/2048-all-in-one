shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.9569, 0.9294, 0.8667, 1.0);
uniform vec4 ink_color : source_color = vec4(0.1843, 0.1882, 0.2157, 1.0);
uniform vec4 accent_color : source_color = vec4(0.6196, 0.8588, 0.8353, 1.0);
uniform vec2 node_resolution = vec2(1280.0, 720.0);
uniform float factor : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float width : hint_range(0.02, 0.8, 0.01) = 0.28;
uniform float angle_degrees : hint_range(-180.0, 180.0, 1.0) = -12.0;
uniform float dot_tiling : hint_range(8.0, 96.0, 1.0) = 38.0;
uniform float dot_radius : hint_range(0.08, 0.45, 0.01) = 0.20;
uniform float shape_tiling : hint_range(4.0, 64.0, 1.0) = 16.0;
uniform float shape_rotation : hint_range(-180.0, 180.0, 1.0) = -8.0;
uniform vec2 shape_scroll = vec2(0.045, 0.012);
uniform float shape_feathering : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform float shape_threshold : hint_range(0.0, 1.0, 0.01) = 0.54;
uniform float shape_influence : hint_range(0.0, 1.0, 0.01) = 0.54;
uniform float grain_strength : hint_range(0.0, 0.08, 0.001) = 0.014;
uniform float band_strength : hint_range(0.0, 0.35, 0.01) = 0.14;
uniform float fill_opacity : hint_range(0.0, 1.0, 0.01) = 0.90;
uniform float edge_opacity : hint_range(0.0, 1.0, 0.01) = 0.98;
uniform float edge_strength : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float registration_offset : hint_range(0.0, 0.08, 0.001) = 0.018;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 rotate_uv(vec2 uv, vec2 pivot, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	mat2 rotation = mat2(vec2(c, -s), vec2(s, c));
	return ((uv - pivot) * rotation) + pivot;
}

float dot_pattern(vec2 uv, float radius) {
	vec2 centered = fract(uv) - vec2(0.5);
	float distance_to_center = length(centered);
	return 1.0 - smoothstep(radius, radius + 0.035, distance_to_center);
}

float hatch_pattern(vec2 uv) {
	float first = 1.0 - smoothstep(0.030, 0.055, abs(fract((uv.x + uv.y) * 18.0) - 0.5));
	float second = 1.0 - smoothstep(0.030, 0.055, abs(fract((uv.x - uv.y) * 18.0) - 0.5));
	return max(first, second);
}

float box_stamp(vec2 local, vec2 half_size) {
	vec2 distance_to_edge = abs(local) - half_size;
	float outside = length(max(distance_to_edge, vec2(0.0)));
	float inside = min(max(distance_to_edge.x, distance_to_edge.y), 0.0);
	return 1.0 - smoothstep(0.0, 0.055, outside + inside);
}

float diamond_stamp(vec2 local, float size) {
	return 1.0 - smoothstep(size, size + 0.060, abs(local.x) + abs(local.y));
}

float stripe_stamp(vec2 local) {
	float stripe = abs(fract((local.x + local.y) * 4.0) - 0.5);
	float stripe_mask = 1.0 - smoothstep(0.16, 0.22, stripe);
	float crop = box_stamp(local, vec2(0.38, 0.38));
	return stripe_mask * crop;
}

float shape_mask_pattern(vec2 uv, vec2 pixel_coord) {
	vec2 cell_id = floor(uv);
	vec2 local = fract(uv) - vec2(0.5);
	float selector = hash(cell_id);
	float square = box_stamp(local, vec2(0.35, 0.35));
	float diamond = diamond_stamp(local, 0.42);
	float stripe = stripe_stamp(local);
	float stamp = mix(square, diamond, step(0.36, selector));
	stamp = mix(stamp, max(stamp, stripe), step(0.68, selector));
	float print_dropout = step(0.10, hash(cell_id + floor(pixel_coord * 0.12)));
	return stamp * print_dropout;
}

void fragment() {
	vec2 resolution = max(node_resolution, vec2(1.0));
	float aspect = resolution.y / resolution.x;
	vec2 uv = UV;
	vec2 aspect_uv = ((uv - vec2(0.5)) * vec2(1.0, aspect)) + vec2(0.5);
	vec2 rotated_uv = rotate_uv(aspect_uv, vec2(0.5), radians(angle_degrees));

	float paper_noise = hash(floor(FRAGCOORD.xy * 0.72));
	float print_jitter = (hash(floor(FRAGCOORD.xy * 0.18)) - 0.5) * 0.030;
	float gradient = clamp(rotated_uv.x + print_jitter, 0.0, 1.0);
	float progress = mix(-width, 1.0 + width, factor);

	vec2 shape_uv = rotate_uv(
		(aspect_uv + TIME * shape_scroll) * vec2(shape_tiling, shape_tiling * max(aspect, 0.001)),
		vec2(0.5),
		radians(shape_rotation)
	);
	float shape_value = shape_mask_pattern(shape_uv, FRAGCOORD.xy);
	float shape_feather = max(shape_feathering, 0.001);
	float shaped_mask = smoothstep(
		shape_threshold - shape_feather,
		shape_threshold + shape_feather,
		shape_value
	);
	float shaped_gradient = clamp(gradient + (shaped_mask - 0.5) * width * shape_influence, 0.0, 1.0);
	float fill_alpha = 1.0 - smoothstep(progress - width, progress + width, shaped_gradient);
	float edge_width = max(width * 0.32, 0.001);
	float edge_distance = abs(shaped_gradient - progress);
	float leading_edge = 1.0 - smoothstep(0.0, edge_width, edge_distance);
	float trail_edge = 1.0 - smoothstep(0.0, width * 0.74, abs(shaped_gradient - progress + width * 0.48));
	float edge_alpha = max(leading_edge, trail_edge * 0.42) * edge_strength;

	vec2 dot_uv = rotated_uv * vec2(dot_tiling, dot_tiling * aspect);
	float dots = dot_pattern(dot_uv, dot_radius) * step(0.26, hash(floor(dot_uv)));
	float cyan_edge = 1.0 - smoothstep(0.0, edge_width, abs(shaped_gradient - progress - registration_offset));
	float magenta_edge = 1.0 - smoothstep(0.0, edge_width, abs(shaped_gradient - progress + registration_offset));
	float edge_band = clamp(max(edge_alpha, max(cyan_edge, magenta_edge) * 0.72), 0.0, 1.0);
	float hatch = hatch_pattern(rotated_uv) * edge_band;
	float shape_edge = shaped_mask * edge_band;

	vec3 color = base_color.rgb;
	color += (paper_noise - 0.5) * grain_strength;
	color = mix(color, accent_color.rgb, cyan_edge * 0.28 + hatch * band_strength + shape_edge * 0.18);
	color = mix(color, vec3(0.82, 0.32, 0.44), magenta_edge * 0.24);
	color = mix(color, ink_color.rgb, leading_edge * 0.10 + dots * (0.10 + edge_band * 0.48));

	float fill_coverage = fill_alpha * fill_opacity;
	float edge_coverage = edge_alpha * edge_opacity;
	float dot_coverage = dots * edge_band * 0.38;
	float combined_alpha = clamp(max(max(fill_coverage, edge_coverage), dot_coverage), 0.0, 1.0);

	COLOR = vec4(color, base_color.a * combined_alpha);
}
