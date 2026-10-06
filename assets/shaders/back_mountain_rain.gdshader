shader_type canvas_item;
render_mode unshaded, blend_mix;

// The existing corridor rain is window-mask-bound; this small wash is scene-local.
uniform float rain_time = 0.0;
uniform float rain_amount = 0.0;
uniform vec4 rain_tint : source_color = vec4(0.78, 0.83, 0.84, 1.0);
float hash(float p) { return fract(sin(p * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = UV * vec2(1440.0, 716.0);
	float x_slant = p.x - p.y * 0.10;
	float column = floor(x_slant / 17.0);
	float center = 17.0 * (0.2 + hash(column + 5.0) * 0.6);
	float x = mod(x_slant, 17.0);
	float y = mod(p.y - rain_time * 250.0 + hash(column) * 140.0, 140.0);
	float length = 16.0 + hash(column + 19.0) * 12.0;
	// About one rendered pixel wide at 960x600, rather than a subpixel trace.
	float line = (1.0 - smoothstep(0.55, 1.65, abs(x - center))) * smoothstep(0.0, 2.0, y)
		* (1.0 - smoothstep(length - 2.0, length, y)) * (1.0 - y / length);
	// Scene layering places rain behind the opaque pine, ledge and seated actor.
	float distance_fade = 1.0 - smoothstep(0.56, 0.90, UV.y);
	float alpha = max(line, 0.0) * rain_amount * 0.70 * distance_fade;
	COLOR = vec4(rain_tint.rgb, alpha);
}
