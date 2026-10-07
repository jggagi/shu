// Small local UV displacement for the two original Tingyu actor sheets.
// strength_px is in source-texture pixels (idle <= 3.0, training <= 8.0; actor render scale is about 0.33).
// The caller supplies the source Texture2D pixel size and actor identity.
float actor_breath_box_weight(vec2 uv, vec4 bounds) {
	vec2 softness = vec2(0.012, 0.010);
	float inside_x = smoothstep(bounds.x, bounds.x + softness.x, uv.x)
		* (1.0 - smoothstep(bounds.z - softness.x, bounds.z, uv.x));
	float inside_y = smoothstep(bounds.y, bounds.y + softness.y, uv.y)
		* (1.0 - smoothstep(bounds.w - softness.y, bounds.w, uv.y));
	return inside_x * inside_y;
}

float actor_player_chest_weight(vec2 uv) {
	float chest = actor_breath_box_weight(uv, vec4(0.48, 0.59, 0.77, 0.83));
	float face = actor_breath_box_weight(uv, vec4(0.50, 0.27, 0.96, 0.63));
	float left_hand = actor_breath_box_weight(uv, vec4(0.29, 0.73, 0.67, 0.95));
	float right_hand = actor_breath_box_weight(uv, vec4(0.78, 0.51, 0.98, 0.75));
	float protected_features = max(face, max(left_hand, right_hand));
	return chest * (1.0 - protected_features);
}

float actor_mentor_chest_weight(vec2 uv) {
	float chest = actor_breath_box_weight(uv, vec4(0.42, 0.56, 0.80, 0.81));
	float face = actor_breath_box_weight(uv, vec4(0.29, 0.25, 0.83, 0.59));
	float beard_hand = actor_breath_box_weight(uv, vec4(0.34, 0.43, 0.65, 0.70));
	float lower_hand = actor_breath_box_weight(uv, vec4(0.48, 0.76, 0.79, 0.94));
	float protected_features = max(face, max(beard_hand, lower_hand));
	return chest * (1.0 - protected_features);
}

vec2 actor_breath_warp_uv(
	vec2 uv,
	vec2 source_pixel_size,
	float strength_px,
	float phase,
	bool mentor_actor
) {
	float chest_weight = mentor_actor
		? actor_mentor_chest_weight(uv)
		: actor_player_chest_weight(uv);
	float pulse = sin(phase);
	float center_x = mentor_actor ? 0.61 : 0.63;
	float horizontal_px = sign(uv.x - center_x) * strength_px * 0.5 * pulse * chest_weight;
	float lift_px = strength_px * 0.10 * pulse * chest_weight;
	// Opposing horizontal offsets gently expand the chest; the vertical lift
	// stays small. The soft body mask and explicit face/hand exclusions keep
	// facial features, hands, and the desk contact visually steady.
	return uv - vec2(horizontal_px, -lift_px) * source_pixel_size;
}
