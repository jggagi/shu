shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform float cloud_time = 0.0;
uniform float cloud_min_brightness : hint_range(0.7, 1.0) = 0.88;
uniform float envelope_seconds : hint_range(4.0, 60.0) = 16.0;
uniform vec2 drift_rate = vec2(0.00065, 0.00022);

void fragment() {
	float period = max(envelope_seconds, 0.01);
	float envelope = 0.5 - 0.5 * cos(TAU * cloud_time / period);
	vec2 drifted_uv = UV + drift_rate * cloud_time;
	float noise_value = texture(cloud_noise, drifted_uv).r;
	float cloud_shape = smoothstep(0.35, 0.75, noise_value);
	float brightness = mix(1.0, cloud_min_brightness, cloud_shape * envelope);
	COLOR = vec4(vec3(brightness), 1.0);
}
