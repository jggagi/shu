shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D mist_noise : repeat_enable;
uniform float mist_time = 0.0;
uniform float mist_density : hint_range(0.0, 0.3) = 0.12;
uniform vec4 mist_tint : source_color = vec4(0.87, 0.91, 0.89, 1.0);

void fragment() {
	vec2 drift_uv = UV + vec2(mist_time * 0.006, sin(mist_time * 0.12 + UV.y * 3.0) * 0.012);
	float noise_value = texture(mist_noise, drift_uv).r;
	float ridge = smoothstep(0.24, 0.82, noise_value + sin(UV.y * 8.0 - mist_time * 0.08) * 0.08);
	float top_fade = smoothstep(0.0, 0.2, UV.y);
	float bottom_fade = 1.0 - smoothstep(0.7, 1.0, UV.y);
	float alpha = ridge * top_fade * bottom_fade * mist_density;
	COLOR = vec4(mist_tint.rgb * COLOR.rgb, alpha * COLOR.a);
}
