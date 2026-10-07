shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/window_mask.gdshaderinc"

uniform vec2 patch_origin = vec2(550.0, 26.0);
uniform vec2 patch_size = vec2(250.0, 225.0);
uniform vec2 anchor_0 = vec2(11.0, 52.0);
uniform vec2 anchor_1 = vec2(80.0, 7.0);
uniform vec2 anchor_2 = vec2(175.0, 6.0);
uniform vec3 bead_fill = vec3(0.0);
uniform vec3 drop_age = vec3(-1.0);
uniform float fall_seconds = 1.0;
uniform float fall_distance = 175.0;
uniform float opacity = 0.65;

varying vec4 vertex_modulation;

const vec3 WATER_COLOR = vec3(0.79, 0.87, 0.89);

void vertex() {
	vertex_modulation = COLOR;
}

float ellipse_coverage(vec2 point, vec2 center, vec2 radii) {
	vec2 safe_radii = max(radii, vec2(0.001));
	float distance_to_edge = length((point - center) / safe_radii);
	float softness = max(fwidth(distance_to_edge), 0.02);
	return 1.0 - smoothstep(1.0 - softness, 1.0 + softness, distance_to_edge);
}

float bead_coverage(vec2 point, vec2 anchor, float fill) {
	float amount = clamp(fill, 0.0, 1.0);
	if (amount <= 0.0) {
		return 0.0;
	}
	float height = 3.0 * amount;
	float radius = 1.7 * sqrt(amount);
	vec2 center = anchor + vec2(0.0, height * 0.5);
	return ellipse_coverage(point, center, vec2(radius, height * 0.5)) * amount;
}

float tapered_tail_coverage(vec2 from_head, float tail_length) {
	float along_tail = -from_head.y;
	float progress = clamp(along_tail / max(tail_length, 0.001), 0.0, 1.0);
	float half_width = mix(0.72, 0.16, progress);
	float softness = max(fwidth(from_head.x), 0.25);
	float across = 1.0 - smoothstep(half_width - softness, half_width + softness, abs(from_head.x));
	float along = smoothstep(-softness, softness, along_tail)
		* (1.0 - smoothstep(tail_length - softness, tail_length + softness, along_tail));
	return across * along;
}

float falling_drop_coverage(vec2 point, vec2 anchor, float age) {
	if (age < 0.0 || fall_seconds <= 0.0 || age >= fall_seconds) {
		return 0.0;
	}
	float progress = clamp(age / fall_seconds, 0.0, 1.0);
	float travel = fall_distance * progress * progress;
	vec2 head = anchor + vec2(0.0, travel);
	float fade = 1.0 - smoothstep(0.72, 0.96, progress);
	float head_coverage = ellipse_coverage(point, head, vec2(1.6, 2.4));
	float tail_coverage = tapered_tail_coverage(point - head, mix(3.0, 8.0, progress));
	return max(head_coverage, tail_coverage * 0.42) * fade;
}

void fragment() {
	vec2 point = UV * patch_size;
	float bead = max(
		max(bead_coverage(point, anchor_0, bead_fill.x), bead_coverage(point, anchor_1, bead_fill.y)),
		bead_coverage(point, anchor_2, bead_fill.z)
	);
	float drop = max(
		max(falling_drop_coverage(point, anchor_0, drop_age.x), falling_drop_coverage(point, anchor_1, drop_age.y)),
		falling_drop_coverage(point, anchor_2, drop_age.z)
	);
	float opening = window_mask(point + patch_origin);
	float alpha = max(bead, drop) * opacity * opening;
	COLOR = vec4(WATER_COLOR, alpha) * vertex_modulation;
}
