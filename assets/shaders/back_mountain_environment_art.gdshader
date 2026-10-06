shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float far_contrast = 1.0;
uniform vec4 sky_tint : source_color = vec4(0.9, 0.9, 0.85, 1.0);
uniform float sky_strength = 0.0;

void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	// A distant ink wash softens peaks; the sky deepens separately at night.
	vec3 haze = mix(vec3(0.70, 0.75, 0.73), sky_tint.rgb, 0.35);
	vec3 mountains = mix(haze, painted.rgb, far_contrast);
	float sky_mask = 1.0 - smoothstep(0.02, 0.52, UV.y);
	vec3 washed = mix(mountains, sky_tint.rgb, sky_mask * sky_strength);
	COLOR = vec4(washed * COLOR.rgb, painted.a * COLOR.a);
}
