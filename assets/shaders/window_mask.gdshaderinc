// Coordinates in the logical 1416 x 526 scene, before viewport scaling.
// The three main openings follow the unequal bamboo-blind heights.
float soft_rect(vec2 p, vec4 r) {
	vec2 lo = smoothstep(r.xy, r.xy + vec2(3.0), p);
	vec2 hi = vec2(1.0) - smoothstep(r.zw - vec2(3.0), r.zw, p);
	return lo.x * lo.y * hi.x * hi.y;
}
float window_mask(vec2 p) {
	float a = soft_rect(p, vec4(265.0, 68.0, 574.0, 365.0));
	float b = soft_rect(p, vec4(574.0, 28.0, 833.0, 365.0));
	float c = soft_rect(p, vec4(833.0, 28.0, 979.0, 365.0));
	float d = soft_rect(p, vec4(1057.0, 26.0, 1140.0, 356.0));
	return max(max(a, b), max(c, d));
}
