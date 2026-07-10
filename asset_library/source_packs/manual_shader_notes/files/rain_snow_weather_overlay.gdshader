shader_type canvas_item;

uniform int count : hint_range(0, 512, 1) = 150;
uniform float slant : hint_range(-0.2, 0.2, 0.001) = -0.01;
uniform float speed : hint_range(0.0, 160.0, 0.1) = 50.0;
uniform float blur : hint_range(0.0005, 0.1, 0.0005) = 0.002;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 streak_size = vec2(0.005, 0.2);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool use_texture_alpha = false;

float line_sdf(vec2 p, vec2 size) {
	vec2 d = abs(p) - size;
	return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0)));
}

float hash_1(float x) {
	return fract(sin(x * 18.34) * 51.78);
}

float hash_2(float x) {
	return fract(sin(x * 25.42) * 21.24);
}

void fragment() {
	vec2 safe_size = max(abs(streak_size) * 0.1, vec2(0.0001));
	float time = TIME + 1000.0;
	vec2 uv = UV;
	uv.x += uv.y * slant;

	float mask = 0.0;
	for (int i = 1; i <= count; i++) {
		float fi = float(i);
		float h1 = hash_1(fi);
		float h2 = hash_2(fi);
		float slant_offset = h1 * uv.y * -slant;
		float x_position = h1 * 1.2 - 0.1;
		float y_speed = max(h2 * speed, x_position * speed);
		vec2 position = vec2(x_position + slant_offset, -mod(-y_speed * time * 0.1, -1.0));
		float sdf = line_sdf(uv - position, safe_size);
		mask += clamp(-sdf / blur, 0.0, 1.0);
	}

	float texture_alpha = 1.0;
	if (use_texture_alpha) {
		texture_alpha = texture(TEXTURE, UV).a;
	}
	COLOR = vec4(color.rgb, clamp(mask, 0.0, 1.0) * color.a * opacity * texture_alpha);
}
