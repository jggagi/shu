shader_type canvas_item;
render_mode unshaded, blend_mix;

// One shared, seamless low-frequency texture; no TIME so static freezes exactly.
uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform float cloud_time = 0.0;
uniform float speed_uv = 0.004;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.18;
uniform float distortion : hint_range(0.0, 0.006) = 0.004;
uniform float density_cycle_seconds = 24.0;
uniform float phase = 0.0;
uniform vec4 cloud_tint : source_color = vec4(0.97, 0.97, 0.94, 1.0);

void fragment() {
	vec2 uv = UV;
	uv.x -= cloud_time * speed_uv;
	uv += distortion * vec2(sin(UV.y * 5.0 + cloud_time * 0.065 + phase),
		cos(UV.x * 6.0 + cloud_time * 0.045 + phase));
	// Long, broken washes rather than round cotton clouds or a horizontal stripe.
	float wash = texture(cloud_noise, vec2(uv.x * 2.8, uv.y * 0.62) + vec2(phase, 0.17)).r;
	float bend = texture(cloud_noise, vec2(uv.x * 2.8, 0.31 + phase)).r;
	float center = 0.46 + (bend - 0.5) * 0.8;
	float envelope = 1.0 - smoothstep(0.045, 0.26, abs(UV.y - center));
	float broken_wash = smoothstep(0.30, 0.60, wash);
	float breathing = 0.90 + 0.10 * sin(cloud_time * 6.283185 / density_cycle_seconds + phase);
	float alpha = envelope * broken_wash * cloud_alpha * breathing;
	COLOR = vec4(cloud_tint.rgb * COLOR.rgb, alpha * COLOR.a);
}
