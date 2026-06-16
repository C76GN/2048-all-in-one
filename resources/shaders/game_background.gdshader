shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.030, 0.052, 0.070, 1.0);
uniform vec4 accent_color : source_color = vec4(0.185, 0.165, 0.330, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.035, 0.300, 0.315, 1.0);
uniform vec4 warm_color : source_color = vec4(0.560, 0.390, 0.180, 1.0);
uniform float grid_strength : hint_range(0.0, 0.25) = 0.0;
uniform float glow_strength : hint_range(0.0, 0.6) = 0.085;
uniform float vignette_strength : hint_range(0.0, 0.9) = 0.24;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.055;
uniform float grain_strength : hint_range(0.0, 0.12) = 0.014;
uniform float stipple_strength : hint_range(0.0, 0.12) = 0.004;
uniform float flow_scale : hint_range(0.5, 8.0) = 2.4;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.007;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise_scaled(vec2 uv, float scale) {
	vec2 cell = floor(uv * scale);
	vec2 f = fract(uv * scale);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 uv) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		value += value_noise_scaled(uv * frequency, 1.0) * amplitude;
		frequency *= 2.05;
		amplitude *= 0.5;
		uv = mat2(vec2(0.86, -0.50), vec2(0.50, 0.86)) * uv;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered_uv = uv - vec2(0.5);
	float slow_pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;

	vec2 flow_uv = centered_uv * flow_scale;
	float t = TIME * 0.035;
	flow_uv += vec2(
		sin((flow_uv.y + t) * 2.1),
		cos((flow_uv.x - t * 0.7) * 1.9)
	) * 0.22;
	flow_uv += vec2(
		fbm(flow_uv + vec2(1.7, t)) - 0.5,
		fbm(flow_uv + vec2(-2.1, -t * 0.8)) - 0.5
	) * 0.58;

	float field = fbm(flow_uv + vec2(t, -t * 0.6));
	float ribbon = smoothstep(0.30, 0.88, field);
	float ember = smoothstep(0.62, 0.96, fbm(flow_uv * 0.72 + vec2(-t * 0.45, t * 0.22)));
	float depth = smoothstep(0.12, 0.92, length(centered_uv + vec2(0.08, -0.03)));

	vec3 color = base_color.rgb;
	color = mix(color, secondary_color.rgb, ribbon * 0.36);
	color = mix(color, accent_color.rgb, (1.0 - ribbon) * 0.22 + ember * 0.10);
	color = mix(color, warm_color.rgb, ember * 0.055);
	color = mix(color, base_color.rgb * 0.50, depth * 0.22);

	float grain = hash(FRAGCOORD.xy + vec2(TIME * 37.0, TIME * -19.0));
	float dust = step(0.997, hash(FRAGCOORD.xy * 0.73 + TIME));
	float scanline = sin(FRAGCOORD.y * 3.14159265);
	float vignette = smoothstep(0.26, 0.92, length(centered_uv));

	color += (grain - 0.5) * grain_strength;
	color += dust * warm_color.rgb * stipple_strength;
	color *= 1.0 - scanline_strength * (scanline * 0.5 + 0.5);
	color += glow_strength * 0.02 * slow_pulse;
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(color, base_color.a);
}
