shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.1, 0.001) = 0.08;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius : hint_range(0.0, 1.0, 0.001) = 0.25;
uniform float aberration : hint_range(0.0, 1.0, 0.001) = 0.425;
uniform float width : hint_range(0.0, 0.1, 0.0001) = 0.04;
uniform float feather : hint_range(0.0, 1.0, 0.001) = 0.135;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float aspect_ratio = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 scaled_uv = (screen_uv - vec2(0.0, 0.5)) / vec2(1.0, aspect_ratio) + vec2(0.0, 0.5);
	vec2 dist_center = scaled_uv - center;
	float dist = length(dist_center);
	float outer_mask = 1.0 - smoothstep(radius - feather, radius, dist);
	float inner_mask = smoothstep(radius - width - feather, radius - width, dist);
	float mask = outer_mask * inner_mask;
	vec2 dist_direction = dist_center / max(dist, 0.0001);
	vec2 offset = dist_direction * strength * mask;
	vec2 biased_uv = scaled_uv - offset;
	vec2 aberration_offset = offset * aberration * mask;
	vec2 final_uv = mix(screen_uv, biased_uv, mask);

	vec4 red = texture(screen_texture, final_uv + aberration_offset);
	vec4 blue = texture(screen_texture, final_uv - aberration_offset);
	vec4 original = texture(screen_texture, final_uv);
	vec4 distorted = vec4(red.r, original.g, blue.b, original.a);
	COLOR = mix(original, distorted, opacity);
}
