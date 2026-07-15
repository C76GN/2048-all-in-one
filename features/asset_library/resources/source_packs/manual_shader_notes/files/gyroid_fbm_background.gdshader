// Original Shadertoy source: https://www.shadertoy.com/view/mtfBRr
// Credits to Leon Denise: https://leon196.github.io/
// Twitter/X: https://twitter.com/leondenise
shader_type canvas_item;

uniform vec2 canvas_ratio = vec2(0.8, 0.6);
uniform float scale : hint_range(0.01, 4.0, 0.01) = 0.5;
uniform float speed : hint_range(0.0, 8.0, 0.01) = 1.0;
uniform vec3 direction = vec3(1.0, 1.0, 0.0);
uniform float distortion : hint_range(0.0, 4.0, 0.01) = 0.5;
uniform float layers : hint_range(1.0, 12.0, 0.1) = 2.0;
uniform float shades : hint_range(1.0, 12.0, 1.0) = 3.0;
uniform int steps : hint_range(1, 16, 1) = 6;
uniform vec4 tint_color : source_color = vec4(0.459, 0.765, 1.0, 1.0);

float gyroid(vec3 seed) {
	return dot(sin(seed), cos(seed.yzx));
}

float fbm(vec3 seed) {
	float result = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 16; i++) {
		if (i >= steps) {
			break;
		}
		seed += direction * TIME * speed * 0.01 / amplitude;
		seed.z += result * distortion;
		result += gyroid(seed / amplitude) * amplitude;
		amplitude *= 0.5;
	}
	return result;
}

void fragment() {
	vec2 ratio = max(canvas_ratio, vec2(0.001));
	vec2 position = (2.0 * UV - ratio) / ratio.y;
	float shape = fbm(vec3(position * scale, 0.0));
	float gradient = fract(shape * layers);
	float shade = round(pow(gradient, 4.0) * shades) / max(1.0, shades);
	vec3 color = mix(tint_color.rgb * mix(0.6, 0.8, gradient), vec3(1.0), shade);
	COLOR = vec4(color, tint_color.a);
}
