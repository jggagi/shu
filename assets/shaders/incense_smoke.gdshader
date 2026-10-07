shader_type canvas_item;
render_mode unshaded;

uniform vec2 smoke_origin = vec2(36.0, 97.0);
uniform vec2 patch_size = vec2(76.0, 104.0);
uniform float rise_pixels = 87.0;
uniform float curl_pixels = 3.4;
uniform float wind_drift_pixels = 4.0;
uniform float elapsed = 0.0;
uniform float wind_strength = 0.0;
uniform float wind_direction = 1.0;
uniform float attention_gain = 1.0;
uniform float opacity = 0.30;
uniform sampler2D smoke_noise;
uniform vec4 smoke_color : source_color = vec4(0.87, 0.86, 0.82, 1.0);

float center_x_at(float t) {
	float curl_envelope = sin(t * 3.14159265);
	float curl = sin(t * 4.8 - elapsed * 0.62) * curl_pixels * curl_envelope;
	curl += sin(t * 8.1 - elapsed * 0.43 + 0.9) * curl_pixels * 0.20 * curl_envelope;
	float wind = wind_direction * wind_strength * wind_drift_pixels * t * t;
	return smoke_origin.x + curl + wind;
}

void fragment() {
	vec2 point = UV * patch_size;
	float t = clamp((smoke_origin.y - point.y) / max(rise_pixels, 0.001), 0.0, 1.0);
	float above_origin = step(point.y, smoke_origin.y);
	float center_x = center_x_at(t);
	float width = mix(1.45, 0.28, smoothstep(0.0, 0.86, t));
	float distance_from_stroke = abs(point.x - center_x);
	float stroke = 1.0 - smoothstep(max(width - 0.35, 0.05), width + 0.75, distance_from_stroke);
	float tip_fade = 1.0 - smoothstep(0.72, 0.87, t);
	vec2 noise_uv = fract(UV * vec2(2.1, 3.5) + vec2(elapsed * 0.009, elapsed * 0.11));
	float wispy_variation = mix(0.82, 1.04, texture(smoke_noise, noise_uv).r);
	float busy_attenuation = mix(0.82, 1.0, clamp(attention_gain, 0.0, 1.0));
	float alpha = stroke * tip_fade * above_origin * wispy_variation * busy_attenuation * opacity;
	COLOR = vec4(smoke_color.rgb, clamp(alpha, 0.0, 0.30));
}
