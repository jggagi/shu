extends RefCounted
class_name EnvironmentPresenter

const DEFAULT_TIME_SECONDS := 1.2
const DEFAULT_WEATHER_SECONDS := 8.0
const DEFAULT_MIN_BRIGHTNESS := 0.38
const TIME_PROFILE_IDS := ["mao", "chen", "si", "wu", "shen", "you"]
const WEATHER_PROFILE_IDS := ["clear", "cloudy", "light_rain"]

var time_profile_id := "mao"
var weather_id := "cloudy"
var night_preview := false

var _time_profiles: Dictionary = {}
var _night_profile: Dictionary = {}
var _weather_profiles: Dictionary = {}
var _min_brightness := DEFAULT_MIN_BRIGHTNESS
var _time_seconds := DEFAULT_TIME_SECONDS
var _weather_seconds := DEFAULT_WEATHER_SECONDS
var _rain_release_seconds := 4.0

var _time_current: Dictionary = {}
var _time_from: Dictionary = {}
var _time_target: Dictionary = {}
var _time_elapsed := 0.0
var _weather_current: Dictionary = {}
var _weather_from: Dictionary = {}
var _weather_target: Dictionary = {}
var _weather_elapsed := 0.0


func configure(data: Dictionary) -> void:
	_time_profiles = _parse_time_profiles(data.get("time_profiles", {}))
	_night_profile = _parse_time_profile(data.get("night_preview", {}))
	_weather_profiles = _parse_weather_profiles(data.get("weather_profiles", {}))
	_min_brightness = maxf(float(data.get("min_brightness", DEFAULT_MIN_BRIGHTNESS)), 0.0)

	var transition: Dictionary = data.get("transition", {})
	_time_seconds = maxf(float(transition.get("time_seconds", DEFAULT_TIME_SECONDS)), 0.0)
	_weather_seconds = maxf(float(transition.get("weather_seconds", DEFAULT_WEATHER_SECONDS)), 0.0)
	_rain_release_seconds = clampf(float(transition.get("rain_release_seconds", 4.0)), 0.0, _weather_seconds)

	time_profile_id = "mao"
	weather_id = "cloudy"
	night_preview = false
	_time_current = _time_profiles.get(time_profile_id, {}).duplicate(true)
	_time_target = _time_current.duplicate(true)
	_weather_current = _weather_profiles.get(weather_id, {}).duplicate(true)
	_weather_target = _weather_current.duplicate(true)
	_time_elapsed = _time_seconds
	_weather_elapsed = _weather_seconds


func set_time_profile(id: String, smooth: bool = true) -> bool:
	if not TIME_PROFILE_IDS.has(id) or not _time_profiles.has(id):
		return false
	var target: Dictionary = _night_profile if night_preview else _time_profiles[id]
	time_profile_id = id
	if smooth and _time_target == target:
		return true
	_start_transition(target, smooth, true)
	return true


func set_weather(id: String, smooth: bool = true) -> bool:
	if not WEATHER_PROFILE_IDS.has(id) or not _weather_profiles.has(id):
		return false
	var target: Dictionary = _weather_profiles[id]
	weather_id = id
	if smooth and _weather_target == target:
		return true
	_start_transition(target, smooth, false)
	return true


func set_night_preview(enabled: bool, smooth: bool = true) -> void:
	if night_preview == enabled:
		return
	night_preview = enabled
	var target: Dictionary = _night_profile if enabled else _time_profiles.get(time_profile_id, {})
	if smooth and _time_target == target:
		return
	_start_transition(target, smooth, true)


func advance(delta: float) -> void:
	var step := maxf(delta, 0.0)
	if _time_elapsed < _time_seconds:
		_time_elapsed = minf(_time_elapsed + step, _time_seconds)
		_time_current = _blend_profiles(_time_from, _time_target, clampf(_time_elapsed / _time_seconds, 0.0, 1.0))
		if _time_elapsed >= _time_seconds:
			_time_current = _time_target.duplicate(true)
	if _weather_elapsed < _weather_seconds:
		_weather_elapsed = minf(_weather_elapsed + step, _weather_seconds)
		_weather_current = _blend_profiles(_weather_from, _weather_target, clampf(_weather_elapsed / _weather_seconds, 0.0, 1.0))
		# Rain recedes before the slower cloud and mist wash clears.
		if float(_weather_target.get("rain_amount", 0.0)) < float(_weather_from.get("rain_amount", 0.0)):
			var rain_weight := 1.0 if _rain_release_seconds <= 0.0 else clampf(_weather_elapsed / _rain_release_seconds, 0.0, 1.0)
			_weather_current.rain_amount = lerpf(float(_weather_from.rain_amount), float(_weather_target.rain_amount), rain_weight)
		if _weather_elapsed >= _weather_seconds:
			_weather_current = _weather_target.duplicate(true)


func finish_transition() -> void:
	_time_current = _time_target.duplicate(true)
	_weather_current = _weather_target.duplicate(true)
	_time_elapsed = _time_seconds
	_weather_elapsed = _weather_seconds


func get_current_environment() -> Dictionary:
	return compose(_time_current, _weather_current, _min_brightness)


func get_target_environment() -> Dictionary:
	return compose(_time_target, _weather_target, _min_brightness)


static func compose(time: Dictionary, weather: Dictionary, min_brightness: float = DEFAULT_MIN_BRIGHTNESS) -> Dictionary:
	return {
		"brightness": maxf(min_brightness, float(time.get("brightness", 1.0)) * float(weather.get("brightness_multiplier", 1.0))),
		"world_tint": _as_color(time.get("world_tint", Color.WHITE)),
		"sky_tint": _as_color(time.get("sky_tint", Color.WHITE)).lerp(Color("#9ca9ab"), float(weather.get("overcast_strength", 0.0)) * 0.7),
		"sky_strength": 1.0 - (1.0 - float(time.get("sky_strength", 0.0))) * (1.0 - float(weather.get("overcast_strength", 0.0))),
		"far_contrast": float(time.get("far_contrast", 1.0)) * float(weather.get("far_contrast_multiplier", 1.0)),
		"mist_multiplier": float(time.get("mist_multiplier", 1.0)) * float(weather.get("mist_multiplier", 1.0)),
		"far_cloud_multiplier": float(weather.get("far_cloud_multiplier", 1.0)) * float(time.get("cloud_alpha_multiplier", 1.0)),
		"valley_cloud_multiplier": float(weather.get("valley_cloud_multiplier", 1.0)) * float(time.get("cloud_alpha_multiplier", 1.0)),
		"cloud_shadow_strength": float(weather.get("cloud_shadow_strength", 0.0)),
		"rain_amount": float(weather.get("rain_amount", 0.0)),
		"wind_strength": float(weather.get("wind_strength", 0.0)),
		"sun_opacity": float(time.get("sun_strength", 0.0)) * float(weather.get("sun_visibility", 0.0)),
		"sun_x": float(time.get("sun_x", 0.55)),
		"sun_y": float(time.get("sun_y", 0.08)),
		"sun_radius": float(time.get("sun_radius", 23.0)),
		"sun_warmth": float(time.get("sun_warmth", 0.0)),
	}


func _start_transition(target: Dictionary, smooth: bool, is_time: bool) -> void:
	var duration := _time_seconds if is_time else _weather_seconds
	if is_time:
		_time_from = _time_current.duplicate(true)
		_time_target = target.duplicate(true)
		if not smooth or duration <= 0.0:
			_time_current = _time_target.duplicate(true)
			_time_elapsed = duration
		else:
			_time_elapsed = 0.0
	else:
		_weather_from = _weather_current.duplicate(true)
		_weather_target = target.duplicate(true)
		if not smooth or duration <= 0.0:
			_weather_current = _weather_target.duplicate(true)
			_weather_elapsed = duration
		else:
			_weather_elapsed = 0.0


func _parse_time_profiles(profiles: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for id in profiles:
		var profile: Variant = profiles[id]
		if profile is Dictionary:
			parsed[str(id)] = _parse_time_profile(profile)
	return parsed


func _parse_time_profile(profile: Dictionary) -> Dictionary:
	var parsed := profile.duplicate(true)
	for key in ["world_tint", "sky_tint"]:
		if parsed.has(key):
			parsed[key] = _as_color(parsed[key])
	return parsed


func _parse_weather_profiles(profiles: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for id in profiles:
		var profile: Variant = profiles[id]
		if profile is Dictionary:
			var values: Dictionary = {}
			for key in profile:
				values[str(key)] = float(profile[key])
			parsed[str(id)] = values
	return parsed


static func _as_color(value: Variant) -> Color:
	return value if value is Color else Color(str(value))


func _blend_profiles(from_profile: Dictionary, to_profile: Dictionary, weight: float) -> Dictionary:
	var blended: Dictionary = {}
	for key in to_profile:
		var from_value: Variant = from_profile.get(key, to_profile[key])
		var to_value: Variant = to_profile[key]
		if from_value is Color and to_value is Color:
			blended[key] = from_value.lerp(to_value, weight)
		else:
			blended[key] = lerpf(float(from_value), float(to_value), weight)
	return blended
