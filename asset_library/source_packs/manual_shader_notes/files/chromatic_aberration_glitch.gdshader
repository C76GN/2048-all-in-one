shader_type canvas_item;

uniform float aberration_intensity : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform vec2 red_displacement = vec2(1.0, 0.0);
uniform vec2 green_displacement = vec2(0.0, 0.0);
uniform vec2 blue_displacement = vec2(-1.0, 0.0);

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec2 red_uv = SCREEN_UV - red_displacement * aberration_intensity * SCREEN_PIXEL_SIZE;
	vec2 green_uv = SCREEN_UV - green_displacement * aberration_intensity * SCREEN_PIXEL_SIZE;
	vec2 blue_uv = SCREEN_UV - blue_displacement * aberration_intensity * SCREEN_PIXEL_SIZE;

	float red = texture(screen_texture, red_uv, 0.0).r;
	float green = texture(screen_texture, green_uv, 0.0).g;
	float blue = texture(screen_texture, blue_uv, 0.0).b;
	float alpha = texture(screen_texture, SCREEN_UV, 0.0).a;

	COLOR = vec4(red, green, blue, alpha);
}
