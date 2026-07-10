shader_type canvas_item;

uniform float factor : hint_range(0.0, 1.0) = 0.0;
uniform float luminance_cutoff : hint_range(0.0, 1.0) = 0.0;
uniform bool use_factor = true;
uniform bool invert = false;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform sampler2D display_texture : filter_linear, repeat_disable;

void fragment() {
	vec4 sample_color = texture(mask_texture, UV);
	float luminance = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	float cutoff = luminance_cutoff;
	if (use_factor) {
		cutoff = factor;
	}
	bool filter = luminance > cutoff;
	if (invert) {
		filter = !filter;
	}

	if (filter) {
		COLOR = texture(display_texture, UV);
	} else {
		COLOR = vec4(1.0, 1.0, 1.0, 0.0) * texture(display_texture, UV);
	}
}
