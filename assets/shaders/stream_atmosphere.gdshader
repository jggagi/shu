shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
uniform float mist_amount = 0.0;
uniform float rain_amount = 0.0;
uniform float brightness = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform float sky_strength = 0.0;
uniform vec2 air_polygon[12];
uniform int air_point_count = 0;
uniform float edge_feather = 30.0;
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
varying vec2 scene_point;
void vertex() { scene_point = VERTEX; }

float air_edge_distance(vec2 point) {
	float nearest_distance = 1000000.0;
	for (int i = 0; i < air_point_count; i++) {
		int j = (i + 1) % air_point_count;
		vec2 edge_start = air_polygon[i];
		vec2 edge_end = air_polygon[j];
		bool on_outer_border =
			(abs(edge_start.x) < 0.5 && abs(edge_end.x) < 0.5)
			|| (abs(edge_start.x - 1280.0) < 0.5 && abs(edge_end.x - 1280.0) < 0.5)
			|| (abs(edge_start.y) < 0.5 && abs(edge_end.y) < 0.5)
			|| (abs(edge_start.y - 720.0) < 0.5 && abs(edge_end.y - 720.0) < 0.5);
		if (!on_outer_border) {
			vec2 edge = edge_end - edge_start;
			float edge_length_squared = dot(edge, edge);
			float along = clamp(dot(point - edge_start, edge) / max(edge_length_squared, 0.0001), 0.0, 1.0);
			nearest_distance = min(nearest_distance, length(point - (edge_start + edge * along)));
		}
	}
	return nearest_distance;
}

void fragment() {
	vec2 p = scene_point;
	float band = smoothstep(160.0, 270.0, p.y) * (1.0 - smoothstep(385.0, 465.0, p.y));
	float cloud = 0.5 + 0.24 * sin(p.x * 0.012 + elapsed * 0.035) + 0.16 * sin(p.x * 0.023 - elapsed * 0.019 + p.y * 0.016);
	float mist = band * cloud * mist_amount * 0.17;
	float column = floor((p.x - p.y * 0.08) / 24.0);
	float dx = mod(p.x - p.y * 0.08, 24.0) - (5.0 + hash(column) * 13.0);
	float dy = mod(p.y - elapsed * 205.0 + hash(column + 1.0) * 190.0, 190.0);
	float rain = (1.0 - smoothstep(0.25, 0.85, abs(dx))) * smoothstep(0.0, 2.0, dy) * (1.0 - smoothstep(12.0, 17.0, dy));
	float air_mask = 1.0;
	if (air_point_count >= 3) {
		air_mask = smoothstep(0.0, max(edge_feather, 0.0001), air_edge_distance(scene_point));
	}
	vec2 uv = scene_point / vec2(1280.0, 720.0);
	float sky = (1.0 - smoothstep(0.0, 0.4, uv.y)) * smoothstep(0.28, 0.48, uv.x);
	vec3 tint = mix(world_tint.rgb, sky_tint.rgb, sky * sky_strength);
	COLOR = vec4(vec3(0.80, 0.88, 0.89) * tint * brightness, (mist + rain * rain_amount * 0.55) * air_mask);
}
