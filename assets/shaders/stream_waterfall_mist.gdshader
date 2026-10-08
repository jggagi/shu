shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float elapsed = 0.0;
uniform float brightness = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 0.2) = 0.08;

void fragment() {
	// A soft, fixed ellipse lets the host place the cloud at the waterfall foot.
	vec2 ellipse_point = vec2((UV.x - 0.5) / 0.47, (UV.y - 0.5) / 0.32);
	float radius = length(ellipse_point);
	float silhouette = 1.0 - smoothstep(0.78, 1.03, radius);

	// Low-amplitude internal bands drift while the outer silhouette stays still.
	float drift = elapsed * 0.20;
	float wisp_a = sin(UV.x * 12.0 + UV.y * 7.0 - drift);
	float wisp_b = sin(UV.x * 21.0 - UV.y * 9.0 - drift * 0.63 + 0.8);
	float density = clamp(0.70 + 0.15 * wisp_a + 0.08 * wisp_b, 0.42, 0.94);
	float alpha = silhouette * density * opacity * clamp(brightness, 0.0, 1.2) * COLOR.a;
	vec3 mist_color = vec3(0.90, 0.96, 0.96) * world_tint.rgb * brightness;
	COLOR = vec4(mist_color, alpha);
}
