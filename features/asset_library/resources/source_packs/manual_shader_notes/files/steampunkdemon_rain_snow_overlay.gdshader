// Rain and Snow shader by Brian Smith (steampunkdemon.itch.io)
// License: MIT
shader_type canvas_item;

uniform float rain_amount : hint_range(1.0, 1024.0, 1.0) = 200.0;
uniform float near_rain_length : hint_range(0.01, 1.0) = 0.2;
uniform float far_rain_length : hint_range(0.01, 1.0) = 0.1;
uniform float near_rain_width : hint_range(0.1, 1.0) = 1.0;
uniform float far_rain_width : hint_range(0.1, 1.0) = 0.5;
uniform float near_rain_transparency : hint_range(0.0, 1.0) = 1.0;
uniform float far_rain_transparency : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rain_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float base_rain_speed : hint_range(0.1, 1.0) = 0.5;
uniform float additional_rain_speed : hint_range(0.1, 1.0) = 0.5;
uniform float slant : hint_range(-1.0, 1.0) = 0.2;
uniform bool use_blurred_trail = false;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float time_offset = 10000.0;

void fragment() {
	float time = time_offset + TIME;
	float line_count = max(1.0, rain_amount);
	float remainder = mod(UV.x - UV.y * slant, 1.0 / line_count);
	vec2 rain_uv = vec2((UV.x - UV.y * slant) - remainder, 0.0);
	float random_line = fract(sin(rain_uv.x * line_count));
	rain_uv.y = fract(UV.y + random_line);

	float length_value = mix(far_rain_length, near_rain_length, random_line);
	float width_value = mix(far_rain_width, near_rain_width, random_line);
	float alpha_value = mix(far_rain_transparency, near_rain_transparency, random_line);
	float speed_value = base_rain_speed + additional_rain_speed * random_line;
	float fall_position = fract(rain_uv.y - time * speed_value);
	float line_mask = step(remainder * line_count, width_value);
	float drop_mask = step(1.0 - length_value, fall_position);
	if (use_blurred_trail) {
		drop_mask = smoothstep(1.0 - length_value, 1.0, fall_position);
	}

	float alpha = drop_mask * alpha_value * line_mask * opacity;
	COLOR = vec4(rain_color.rgb, rain_color.a * alpha);
}
