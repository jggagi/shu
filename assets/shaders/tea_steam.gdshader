shader_type canvas_item;
render_mode unshaded;

uniform vec2 steam_origin = vec2(30.0, 71.0);
uniform float rise_pixels = 54.0;
uniform float curl_pixels = 2.4;
uniform float wind_drift_pixels = 3.5;
uniform float elapsed = 0.0;
uniform float wind_strength = 0.0;
uniform float wind_direction = 1.0;
uniform float attention_gain = 1.0;
uniform float opacity = 0.15;
uniform bool gust_active = false;
uniform vec4 steam_color : source_color = vec4(1.0, 0.95, 0.86, 1.0);

float segment_distance(vec2 point, vec2 start, vec2 finish) {
	vec2 segment = finish - start;
	float length_squared = max(dot(segment, segment), 0.0001);
	float along = clamp(dot(point - start, segment) / length_squared, 0.0, 1.0);
	return length(point - start - segment * along);
}

float wisp_distance(vec2 point, float side, float phase) {
	float nearest = 1000.0;
	vec2 previous = steam_origin + vec2(side * 3.0, 0.0);
	for (int index = 1; index <= 12; index++) {
		float t = float(index) / 12.0;
		float curl = sin(t * 5.4 + phase + elapsed * 0.72) * curl_pixels * sin(t * 3.14159);
		float gust_bend = gust_active ? sin(elapsed * 2.15 + 0.4) * 0.7 : 0.0;
		float wind_bend = wind_direction * wind_strength * wind_drift_pixels * t;
		vec2 next = steam_origin + vec2(side * 3.0 + curl + (gust_bend + wind_bend) * t, -rise_pixels * t);
		nearest = min(nearest, segment_distance(point, previous, next));
		previous = next;
	}
	return nearest;
}

float wisp_alpha(vec2 point, float side, float phase, float opacity_scale) {
	float t = clamp((steam_origin.y - point.y) / max(rise_pixels, 0.001), 0.0, 1.0);
	float fade_in = smoothstep(0.0, 0.06, t);
	float fade_out = 1.0 - smoothstep(0.78, 1.0, t);
	float intermittent = smoothstep(-0.2, 0.65, sin(elapsed * 0.7 + phase));
	float stroke = 1.0 - smoothstep(0.65, 2.3, wisp_distance(point, side, phase));
	return stroke * fade_in * fade_out * intermittent * opacity * attention_gain * opacity_scale;
}

void fragment() {
	vec2 point = UV * vec2(66.0, 78.0);
	float alpha = wisp_alpha(point, -1.0, 0.35, 0.82) + wisp_alpha(point, 1.0, 2.25, 0.82);
	COLOR = vec4(steam_color.rgb, clamp(alpha, 0.0, 0.46));
}
