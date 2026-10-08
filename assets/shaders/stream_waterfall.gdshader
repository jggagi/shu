shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float elapsed = 0.0;
uniform float brightness = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform sampler2D painting : filter_linear;
uniform vec2 flow_origin = vec2(830.0, 190.0);
uniform vec2 flow_size = vec2(65.0, 110.0);
uniform float flow_strength : hint_range(0.0, 1.0) = 0.55;

varying vec2 scene_point;

void vertex() {
	scene_point = VERTEX;
}

float moving_segment(float phase, float start, float end) {
	float along = fract(phase);
	float leading_edge = smoothstep(start, start + 0.11, along);
	float trailing_edge = 1.0 - smoothstep(end - 0.12, end, along);
	return leading_edge * trailing_edge;
}

void fragment() {
	// Keep the flow detail attached to the authored world-space Polygon2D.
	// The small wobble changes the internal pattern by less than one logical pixel.
	vec2 detail_point = scene_point + vec2(
		sin((scene_point.y - flow_origin.y) * 0.15 + elapsed * 0.21) * 0.70,
		sin((scene_point.x - flow_origin.x) * 0.18 - elapsed * 0.17) * 0.60
	);
	vec2 local = (detail_point - flow_origin) / flow_size;
	vec2 paint_uv = scene_point / vec2(1280.0, 720.0);
	vec3 painted = texture(painting, paint_uv).rgb;

	float inside_bounds = step(0.0, local.x) * step(local.x, 1.0)
		* step(0.0, local.y) * step(local.y, 1.0);
	float side_fade = smoothstep(0.0, 0.10, local.x)
		* (1.0 - smoothstep(0.90, 1.0, local.x));
	float top_bottom_fade = smoothstep(0.0, 0.075, local.y)
		* (1.0 - smoothstep(0.90, 1.0, local.y));
	float edge_fade = inside_bounds * side_fade * top_bottom_fade;

	float lane_a = 1.0 - smoothstep(1.35, 2.85, abs((local.x - 0.20) * flow_size.x));
	float lane_b = 1.0 - smoothstep(1.15, 2.55, abs((local.x - 0.51) * flow_size.x));
	float lane_c = 1.0 - smoothstep(1.45, 3.00, abs((local.x - 0.82) * flow_size.x));
	float shade_a = 1.0 - smoothstep(1.15, 2.70, abs((local.x - 0.27) * flow_size.x));
	float shade_b = 1.0 - smoothstep(1.10, 2.65, abs((local.x - 0.59) * flow_size.x));
	float shade_c = 1.0 - smoothstep(1.20, 2.80, abs((local.x - 0.90) * flow_size.x));

	// Phase advances toward larger y, so each irregular ribbon travels downward.
	float phase_slow = (detail_point.y - elapsed * 15.0) / 43.0;
	float phase_middle = (detail_point.y - elapsed * 23.0) / 31.0;
	float phase_fast = (detail_point.y - elapsed * 31.0) / 52.0;
	float highlight = lane_a * moving_segment(phase_slow + 0.05, 0.03, 0.72)
		* 0.76;
	highlight += lane_b * moving_segment(phase_fast + 0.39, 0.16, 0.86) * 0.68;
	highlight += lane_c * moving_segment(phase_middle + 0.73, 0.08, 0.67) * 0.72;
	float shadow = shade_a * moving_segment(phase_middle + 0.42, 0.12, 0.79) * 0.55;
	shadow += shade_b * moving_segment(phase_slow + 0.67, 0.18, 0.84) * 0.52;
	shadow += shade_c * moving_segment(phase_fast + 0.11, 0.04, 0.69) * 0.50;

	float luminance = dot(painted, vec3(0.299, 0.587, 0.114));
	float cool_water = max(painted.g, painted.b) - painted.r;
	float painted_water = smoothstep(0.52, 0.76, luminance)
		* mix(0.78, 1.0, smoothstep(-0.05, 0.14, cool_water));
	float intensity = clamp(highlight * 0.40 + shadow * 1.10, 0.0, 0.85);
	float alpha = intensity * flow_strength * painted_water * edge_fade
		* clamp(brightness, 0.0, 1.2) * COLOR.a;

	vec3 grade = world_tint.rgb * brightness;
	vec3 source_grade = painted * grade;
	vec3 light_color = mix(source_grade, vec3(0.96, 0.99, 0.98) * grade, 0.68);
	vec3 shade_color = source_grade * vec3(0.48, 0.66, 0.70);
	float light_share = highlight / max(highlight + shadow * 2.0, 0.001);
	vec3 ripple_color = mix(shade_color, light_color, light_share);
	COLOR = vec4(ripple_color, alpha);
}
