shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float elapsed = 0.0;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.0, 1.3) = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform sampler2D painting : filter_linear;
uniform vec2 river_polygon[24];
uniform int river_point_count = 0;
uniform vec2 flow_centers[5];
uniform float flow_strength = 0.8;
uniform float bank_feather = 12.0;

const vec2 LOGICAL_CANVAS_SIZE = vec2(1280.0, 720.0);
const vec2 RING_CELL_SIZE = vec2(108.0, 78.0);

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 river_coverage(vec2 point) {
	int count = clamp(river_point_count, 0, 24);
	if (count < 3) {
		return vec2(0.0);
	}

	float inside = 0.0;
	float nearest_bank = 10000.0;
	for (int i = 0; i < 24; i++) {
		if (i < count) {
			int next_index = (i + 1) % count;
			vec2 a = river_polygon[i];
			vec2 b = river_polygon[next_index];
			bool crosses_scanline = (a.y > point.y) != (b.y > point.y);
			if (crosses_scanline) {
				float crossing_x = a.x + (b.x - a.x) * (point.y - a.y) / (b.y - a.y);
				if (point.x < crossing_x) {
					inside = 1.0 - inside;
				}
			}

			bool canvas_edge =
				(abs(a.x) < 0.5 && abs(b.x) < 0.5)
				|| (abs(a.x - LOGICAL_CANVAS_SIZE.x) < 0.5 && abs(b.x - LOGICAL_CANVAS_SIZE.x) < 0.5)
				|| (abs(a.y) < 0.5 && abs(b.y) < 0.5)
				|| (abs(a.y - LOGICAL_CANVAS_SIZE.y) < 0.5 && abs(b.y - LOGICAL_CANVAS_SIZE.y) < 0.5);
			if (!canvas_edge) {
				vec2 segment = b - a;
				float segment_length_sq = max(dot(segment, segment), 0.0001);
				float along = clamp(dot(point - a, segment) / segment_length_sq, 0.0, 1.0);
				nearest_bank = min(nearest_bank, length(point - (a + segment * along)));
			}
		}
	}

	float feather = smoothstep(0.0, max(bank_feather, 0.001), nearest_bank);
	return vec2(inside, feather);
}

float river_center_x(float y) {
	if (y <= flow_centers[0].y) {
		return flow_centers[0].x;
	}
	for (int i = 0; i < 4; i++) {
		vec2 near_center = flow_centers[i];
		vec2 far_center = flow_centers[i + 1];
		if (y <= far_center.y) {
			float blend = smoothstep(near_center.y, far_center.y, y);
			return mix(near_center.x, far_center.x, blend);
		}
	}
	return flow_centers[4].x;
}

float downstream_coordinate(float y) {
	return 90.0 * log(1.0 + max(y - 440.0, 0.0) / 90.0);
}

float broken_crest(vec2 flow_point, vec2 tile_size, float seed_offset, float density, float width, float wave_amplitude) {
	vec2 grid = flow_point / tile_size;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float selected = step(hash(cell + vec2(seed_offset, seed_offset * 1.73)), density);
	float row = 0.22 + hash(cell + vec2(seed_offset + 4.3, 11.9)) * 0.56;
	float wave_phase = hash(cell + vec2(seed_offset + 23.7, 5.2)) * TAU;
	float wave_count = 0.65 + hash(cell + vec2(seed_offset + 17.1, 36.4)) * 1.1;
	float center = row + sin(local.x * TAU * wave_count + wave_phase) * wave_amplitude;
	float distance_flow = abs(local.y - center) * tile_size.y;
	float line = 1.0 - smoothstep(width, width + max(width * 0.8, 0.5), distance_flow);

	float start = 0.04 + hash(cell + vec2(seed_offset + 31.2, 19.6)) * 0.35;
	float finish = 0.61 + hash(cell + vec2(seed_offset + 52.8, 27.3)) * 0.34;
	float ends = smoothstep(start, start + 0.07, local.x)
		* (1.0 - smoothstep(finish - 0.07, finish, local.x));
	float shimmer = 0.90 + 0.10 * sin(elapsed * 0.72 + local.x * 3.4 + wave_phase);
	return line * ends * selected * shimmer;
}

float rain_ring(vec2 point) {
	vec2 cell = floor(point / RING_CELL_SIZE);
	vec2 random_position = vec2(
		0.22 + hash(cell + vec2(68.2, 9.4)) * 0.56,
		0.22 + hash(cell + vec2(13.7, 74.1)) * 0.56
	);
	vec2 center = (cell + random_position) * RING_CELL_SIZE;
	float eligible = step(hash(cell + vec2(91.3, 43.8)), 0.28);
	float phase = fract(elapsed / 5.2 + hash(cell + vec2(3.1, 107.7)));
	float age = phase * 5.2;
	float envelope = smoothstep(0.0, 0.22, age) * (1.0 - smoothstep(1.55, 2.0, age));
	float radius = 2.0 + age * 7.0;

	vec2 delta = point - center;
	float ellipse_distance = length(vec2(delta.x * 0.68, delta.y * 1.1));
	float ring_width = 0.9 + hash(cell + vec2(48.5, 62.1)) * 0.65;
	float crest = 1.0 - smoothstep(ring_width, ring_width + 1.15, abs(ellipse_distance - radius));
	float rain_gain = clamp(rain_amount, 0.0, 1.0);

	return crest * envelope * eligible * rain_gain * 0.30;
}

varying vec2 scene_point;
void vertex() {
	scene_point = VERTEX;
}

void fragment() {
	// The source image is sampled only to recognize water; its pixels are never displaced.
	vec2 point = scene_point;
	vec2 coverage = river_coverage(point);
	vec2 painting_uv = clamp(point / LOGICAL_CANVAS_SIZE, vec2(0.0), vec2(1.0));
	vec3 painted = texture(painting, painting_uv).rgb;
	float luminance = dot(painted, vec3(0.299, 0.587, 0.114));
	float cool_bias = max(painted.g, painted.b) - painted.r;
	float painted_water = smoothstep(0.025, 0.095, cool_bias)
		* smoothstep(0.18, 0.32, luminance)
		* (1.0 - smoothstep(0.96, 1.0, luminance));
	float water_area = coverage.x * coverage.y * painted_water;

	float depth = clamp((point.y - 440.0) / 280.0, 0.0, 1.0);
	float cross_flow_scale = mix(0.35, 1.0, depth);
	float cross_flow = (point.x - river_center_x(point.y)) / cross_flow_scale;
	float flow_v = downstream_coordinate(point.y) - elapsed * 9.0;
	vec2 flow_point = vec2(cross_flow, flow_v);

	float near_crests = broken_crest(flow_point, vec2(82.0, 18.0), 3.0, 0.52, 0.65, 0.055);
	float fine_crests = broken_crest(flow_point, vec2(55.0, 29.0), 37.0, 0.31, 0.82, 0.075);
	float thin_crest_alpha = clamp(near_crests * 0.72 + fine_crests * 0.44, 0.0, 1.0)
		* 0.40 * clamp(flow_strength, 0.0, 1.5);
	float reflection_rolls = broken_crest(flow_point, vec2(188.0, 42.0), 71.0, 0.34, 4.2, 0.095);
	float reflection_alpha = reflection_rolls * 0.25 * clamp(flow_strength, 0.0, 1.5);
	float ring_alpha = rain_ring(point);

	float grade_brightness = clamp(brightness, 0.0, 1.3);
	float base_coverage = water_area * grade_brightness * COLOR.a;
	float bright_alpha = thin_crest_alpha * base_coverage;
	float dark_alpha = reflection_alpha * base_coverage;
	ring_alpha *= base_coverage;

	vec3 grade = world_tint.rgb * grade_brightness;
	vec3 bright_color = mix(painted, vec3(0.95, 0.98, 0.94), 0.62) * grade;
	vec3 dark_color = painted * grade * vec3(0.55, 0.66, 0.68);
	vec3 ring_color = painted * grade * vec3(1.11, 1.22, 1.22);
	vec3 premultiplied = bright_color * bright_alpha;
	premultiplied += dark_color * dark_alpha * (1.0 - bright_alpha);
	premultiplied += ring_color * ring_alpha * (1.0 - bright_alpha) * (1.0 - dark_alpha);
	float alpha = 1.0 - (1.0 - bright_alpha) * (1.0 - dark_alpha) * (1.0 - ring_alpha);
	COLOR = vec4(premultiplied / max(alpha, 0.0001), alpha);
}
