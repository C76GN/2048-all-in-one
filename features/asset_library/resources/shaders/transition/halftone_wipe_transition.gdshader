shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.9569, 0.9294, 0.8667, 1.0);
uniform vec4 ink_color : source_color = vec4(0.1843, 0.1882, 0.2157, 1.0);
uniform vec4 accent_color : source_color = vec4(0.6196, 0.8588, 0.8353, 1.0);
uniform vec2 node_resolution = vec2(1280.0, 720.0);
uniform float factor : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool reverse_progress = false;
uniform float width : hint_range(0.02, 0.8, 0.01) = 0.14;
uniform float angle_degrees : hint_range(-180.0, 180.0, 1.0) = -9.0;
uniform float dot_tiling : hint_range(8.0, 96.0, 1.0) = 34.0;
uniform float dot_radius : hint_range(0.08, 0.45, 0.01) = 0.18;
uniform float shape_tiling : hint_range(4.0, 64.0, 1.0) = 18.0;
uniform float shape_rotation : hint_range(-180.0, 180.0, 1.0) = -8.0;
uniform vec2 shape_scroll = vec2(0.018, 0.004);
uniform float shape_feathering : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float shape_threshold : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float shape_influence : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float grain_strength : hint_range(0.0, 0.08, 0.001) = 0.010;
uniform float band_strength : hint_range(0.0, 0.35, 0.01) = 0.11;
uniform float fill_opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float edge_opacity : hint_range(0.0, 1.0, 0.01) = 0.96;
uniform float edge_strength : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float registration_offset : hint_range(0.0, 0.08, 0.001) = 0.012;

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
	return 1.0 - smoothstep(radius, radius + 0.055, length(centered));
}

float hatch_pattern(vec2 uv) {
	float stripe = abs(fract((uv.x + uv.y) * 22.0) - 0.5);
	return 1.0 - smoothstep(0.055, 0.105, stripe);
}

float shape_mask_pattern(vec2 uv) {
	vec2 cell_id = floor(uv);
	vec2 local = fract(uv) - vec2(0.5);
	float diamond = 1.0 - smoothstep(0.28, 0.38, abs(local.x) + abs(local.y));
	float keep = step(0.48, hash(cell_id));
	return diamond * keep;
}

void fragment() {
	vec2 resolution = max(node_resolution, vec2(1.0));
	float aspect = resolution.y / resolution.x;
	vec2 aspect_uv = ((UV - vec2(0.5)) * vec2(1.0, aspect)) + vec2(0.5);
	vec2 rotated_uv = rotate_uv(aspect_uv, vec2(0.5), radians(angle_degrees));

	float effective_factor = factor;
	if (reverse_progress) {
		effective_factor = 1.0 - factor;
	}
	float progress = mix(-width, 1.0 + width, effective_factor);

	vec2 shape_uv = rotate_uv(
		(aspect_uv + TIME * shape_scroll) * vec2(shape_tiling, shape_tiling * max(aspect, 0.001)),
		vec2(0.5),
		radians(shape_rotation)
	);
	float shape_value = shape_mask_pattern(shape_uv);
	float shape_feather = max(shape_feathering, 0.001);
	float shaped_mask = smoothstep(
		shape_threshold - shape_feather,
		shape_threshold + shape_feather,
		shape_value
	);
	float cell_jitter = hash(floor(shape_uv)) - 0.5;
	float shaped_gradient = rotated_uv.x + cell_jitter * width * 0.20;
	shaped_gradient += (shaped_mask - 0.5) * width * shape_influence;

	float edge_softness = max(width * 0.12, 0.002);
	float fill_alpha = 1.0 - smoothstep(
		progress - edge_softness,
		progress + edge_softness,
		shaped_gradient
	);
	float edge_distance = abs(shaped_gradient - progress);
	float leading_edge = 1.0 - smoothstep(width * 0.08, width * 0.52, edge_distance);
	float edge_alpha = leading_edge * edge_strength;

	vec2 dot_uv = rotated_uv * vec2(dot_tiling, dot_tiling * max(aspect, 0.001));
	float dots = dot_pattern(dot_uv, dot_radius);
	float hatch = hatch_pattern(rotated_uv);
	float cyan_edge = 1.0 - smoothstep(
		width * 0.06,
		width * 0.26,
		abs(shaped_gradient - progress - registration_offset)
	);
	float magenta_edge = 1.0 - smoothstep(
		width * 0.06,
		width * 0.26,
		abs(shaped_gradient - progress + registration_offset)
	);

	float paper_noise = hash(floor(FRAGCOORD.xy * 0.68));
	vec3 color = base_color.rgb + (paper_noise - 0.5) * grain_strength;
	color = mix(color, accent_color.rgb, cyan_edge * 0.24 + dots * edge_alpha * band_strength);
	color = mix(color, vec3(0.82, 0.32, 0.44), magenta_edge * 0.16);
	color = mix(color, ink_color.rgb, hatch * edge_alpha * 0.10);

	float fill_coverage = fill_alpha * fill_opacity;
	float stippled_edge = edge_alpha * edge_opacity * mix(0.52, 1.0, dots);
	float combined_alpha = clamp(max(fill_coverage, stippled_edge), 0.0, 1.0);
	COLOR = vec4(color, base_color.a * combined_alpha);
}
