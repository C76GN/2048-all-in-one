shader_type canvas_item;

uniform vec3 background_colour : source_color = vec3(1.0);

/** Colour of grid lines. */
uniform vec3 grid_colour : source_color = vec3(0.7);

/** Colour of subdividing grid lines. */
uniform vec3 subdivision_colour : source_color = vec3(0.85);

/** Colour of horizontal origin line. */
uniform vec3 h_origin_colour : source_color = vec3(0.2, 0.2, 1.0);

/** Colour of vertical origin line. */
uniform vec3 v_origin_colour : source_color = vec3(1.0, 0.2, 0.2);

/** Position of origin in world space pixels. */
uniform vec2 origin_position = vec2(0.0, 0.0);

/** Target spacing according to pixels on screen. This is used as a target to choose what multiple. */
uniform float grid_spacing_pixels = 50.0;

/** How many subdivisions the grid lines have. */
uniform int subdivisions = 10;

/** Thickness of lines in pixels. */
uniform float line_thickness = 3.0;

/** Range that line is smoothed, from 0 = no smoothing, 1.0 = most smoothing. */
uniform float line_smooth : hint_range(0.0, 1.0, 0.01) = 0.5;

// Compares position to 0.0 to create a consistent line: 1.0 if in line, 0.0 if not.
float line_compare(float x, float uvx) {
	return 1.0 - smoothstep((1.0 - line_smooth) * line_thickness * x * 0.5, line_thickness * x * 0.5, abs(uvx));
}


// Rounds off uv according to spacing of lines and returns distance to nearest line.
vec2 moduloed_uv(vec2 uv, vec2 spacing) {
	vec2 m_uv = vec2(
		mod(uv.x + spacing.x * 0.5, spacing.x) - spacing.x * 0.5,
		mod(uv.y + spacing.y * 0.5, spacing.y) - spacing.y * 0.5
	);
	return m_uv;
}


// Compare against a given grid spacing; return 1.0 if on grid, 0.0 if not.
float grid_compare(vec2 uv, vec2 spacing, float ddx, float ddy) {
	vec2 g_uv = moduloed_uv(uv, spacing);
	float v_line = line_compare(ddx, g_uv.x);
	float h_line = line_compare(ddy, g_uv.y);
	return max(v_line, h_line);
}


// Used to pass world position from vertex function.
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec2 dx = dFdx(world_pos);
	vec2 dy = dFdy(world_pos);
	float ddx = length(vec2(dx.x, dy.x));
	float ddy = length(vec2(dx.y, dy.y));

	vec2 uv = world_pos - origin_position;

	float safe_subdivisions = max(float(subdivisions), 2.0);
	float grid_ratio_log = log(max(ddx, 0.0001)) / log(safe_subdivisions);
	float rounded_log = round(grid_ratio_log);
	float space_mult = pow(safe_subdivisions, rounded_log);
	vec2 spacing = vec2(grid_spacing_pixels) * space_mult;

	float on_grid = grid_compare(uv, spacing, ddx, ddy);
	float on_subgrid = grid_compare(uv, spacing / safe_subdivisions, ddx, ddy);
	float on_supgrid = grid_compare(uv, spacing * safe_subdivisions, ddx, ddy);

	float transition = clamp((grid_ratio_log - rounded_log) * 2.0 + 0.5, 0.0, 1.0);
	vec3 subgrid_line_colour = mix(subdivision_colour, background_colour, transition);
	vec3 grid_line_colour = mix(grid_colour, subdivision_colour, transition);
	grid_line_colour = mix(mix(subgrid_line_colour, grid_line_colour, on_grid), grid_colour, on_supgrid);

	float ov_line = line_compare(ddx, uv.x);
	float oh_line = line_compare(ddy, uv.y);
	grid_line_colour = mix(grid_line_colour, v_origin_colour, ov_line);
	grid_line_colour = mix(grid_line_colour, h_origin_colour, oh_line);

	COLOR = vec4(mix(background_colour, grid_line_colour, on_subgrid), 1.0);
}
