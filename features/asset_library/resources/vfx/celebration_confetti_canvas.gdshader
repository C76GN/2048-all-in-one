shader_type canvas_item;
render_mode unshaded;

uniform vec4 col0 : source_color = vec4(0.6196, 0.8588, 0.8353, 1.0);
uniform vec4 col1 : source_color = vec4(0.9373, 0.8196, 0.3647, 1.0);
uniform vec4 col2 : source_color = vec4(0.8745, 0.2941, 0.6039, 1.0);
uniform vec4 col3 : source_color = vec4(0.5804, 0.2667, 0.1922, 1.0);
uniform vec4 col4 : source_color = vec4(0.2706, 0.3176, 0.3843, 1.0);
uniform vec4 col5 : source_color = vec4(0.9451, 0.8863, 0.7451, 1.0);
uniform vec4 col6 : source_color = vec4(0.6784, 0.6157, 0.3843, 1.0);
uniform vec4 col7 : source_color = vec4(0.1843, 0.1882, 0.2157, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.34;
uniform float grain_strength : hint_range(0.0, 0.25) = 0.08;

vec4 palette_color(float selector) {
	int index = int(clamp(selector, 0.0, 0.9999) * 8.0);
	if (index == 0) {
		return col0;
	}
	if (index == 1) {
		return col1;
	}
	if (index == 2) {
		return col2;
	}
	if (index == 3) {
		return col3;
	}
	if (index == 4) {
		return col4;
	}
	if (index == 5) {
		return col5;
	}
	if (index == 6) {
		return col6;
	}
	return col7;
}

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec4 paper_color = palette_color(COLOR.r);
	vec2 edge_distance = min(UV, vec2(1.0) - UV);
	float edge_mask = 1.0 - smoothstep(0.0, 0.16, min(edge_distance.x, edge_distance.y));
	float grain = hash(floor(UV * vec2(18.0, 12.0)) + FRAGCOORD.xy * 0.03) - 0.5;
	vec3 ink = paper_color.rgb;
	ink *= 1.0 - edge_mask * edge_strength;
	ink += grain * grain_strength;
	COLOR = vec4(ink, source.a * paper_color.a * COLOR.a);
}
