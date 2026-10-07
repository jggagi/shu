extends RefCounted
class_name AmbientCatMotion


static func idle_pose(
	age: float,
	wind: float,
	time_profile: String,
	weather_id: String,
	motion: Dictionary,
	attention_busy: bool = false
) -> int:
	if attention_busy or weather_id == "light_rain":
		return 0
	var phase := fposmod(maxf(age, 0.0), maxf(float(motion.get("cat_cycle_seconds", 30.0)), 0.001))
	var head_begin := float(motion.get("cat_head_begin", 6.0))
	var head_seconds := float(motion.get("cat_head_seconds", 3.0))
	var glance_allowed: bool = time_profile in ["mao", "chen"] or weather_id == "cloudy"
	if glance_allowed and phase >= head_begin and phase < head_begin + head_seconds:
		return 1 if phase < head_begin + 1.0 or phase >= head_begin + 2.0 else 2
	var tail_begin := float(motion.get("cat_tail_begin", 12.0))
	var tail_seconds := float(motion.get("cat_tail_seconds", 2.0))
	if wind > 0.1 and phase >= tail_begin and phase < tail_begin + tail_seconds:
		return 3 if int((phase - tail_begin) * lerpf(1.0, 2.0, clampf(wind, 0.0, 1.0))) % 2 == 0 else 0
	var active_allowed: bool = not (time_profile in ["si", "wu"] and weather_id == "clear")
	var groom_begin := float(motion.get("cat_groom_begin", 15.0))
	var groom_seconds := float(motion.get("cat_groom_seconds", 2.0))
	if active_allowed and phase >= groom_begin and phase < groom_begin + groom_seconds:
		return 4 if int((phase - groom_begin) * 2.0) % 2 == 0 else 0
	var play_begin := float(motion.get("cat_play_begin", 19.0))
	var play_seconds := float(motion.get("cat_play_seconds", 4.5))
	if active_allowed and phase >= play_begin and phase < play_begin + play_seconds:
		return 6 if phase < play_begin + 1.6 or phase >= play_begin + 3.0 else 5
	return 0
