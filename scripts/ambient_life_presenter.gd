extends RefCounted
class_name AmbientLifePresenter

const EVENT_ORDER := ["birds", "squirrel", "cat", "fish"]
const QUICK_EVENTS := ["birds", "squirrel", "fish"]
const TWILIGHT_PROFILES := ["shen", "you"]
const EPSILON := 0.000001

var enabled := true
var auto_enabled := true
var elapsed := 0.0
var next_due: Dictionary = {}

var _config: Dictionary = {}
var _seed := 0
var _rng := RandomNumberGenerator.new()
var _environment := {
	"time_profile_id": "mao",
	"weather_id": "cloudy",
	"night_preview": false,
	"dynamic_enabled": false,
}
var _capabilities: Dictionary = {}
var _active_events: Dictionary = {}
var _serial := 0
var _forced_serial := -2


func configure(data: Dictionary, seed: int = -1) -> void:
	_config = data.duplicate(true)
	_seed = seed if seed != -1 else int(_config.get("seed", 0))
	_initialize_schedule()


func observe(environment: Dictionary, capabilities: Dictionary) -> void:
	_environment = {
		"time_profile_id": str(environment.get("time_profile_id", "mao")),
		"weather_id": str(environment.get("weather_id", "cloudy")),
		"night_preview": bool(environment.get("night_preview", false)),
		"dynamic_enabled": bool(environment.get("dynamic_enabled", false)),
	}
	_capabilities = capabilities.duplicate(true)
	for kind in _active_events.keys():
		if (not bool(_environment.dynamic_enabled) and QUICK_EVENTS.has(kind)) or not _context_allows(str(kind)):
			_active_events.erase(kind)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_active_events.clear()


func can_spawn(kind: String) -> bool:
	return bool(_environment.dynamic_enabled) and _context_allows(kind)


func advance(delta: float, foreground_attention_busy: bool = false) -> Array:
	var requests: Array = []
	var step := maxf(delta, 0.0)
	if step <= 0.0 or not enabled or not bool(_environment.dynamic_enabled):
		return requests
	if not auto_enabled:
		elapsed += step
		for kind in next_due:
			next_due[kind] = float(next_due[kind]) + step
		_expire_events()
		return requests

	var target_time := elapsed + step
	while true:
		var boundary := target_time
		for kind in EVENT_ORDER:
			if next_due.has(kind):
				var due := float(next_due[kind])
				if due < boundary:
					boundary = maxf(elapsed, due)
		for event in _active_events.values():
			var event_end := float(event.start) + float(event.duration)
			if event_end < boundary:
				boundary = maxf(elapsed, event_end)
		elapsed = boundary
		_expire_events()
		for kind in EVENT_ORDER:
			if next_due.has(kind) and float(next_due[kind]) <= elapsed + EPSILON:
				_resolve_opportunity(kind, foreground_attention_busy, requests)
		if elapsed >= target_time - EPSILON and not _has_due_at_current_time():
			break
	return requests


func force_event(kind: String) -> Dictionary:
	if not EVENT_ORDER.has(kind) or not can_spawn(kind):
		return {}
	if kind != "cat":
		for active_kind in _active_events.keys():
			if QUICK_EVENTS.has(active_kind):
				_active_events.erase(active_kind)
	elif _active_events.has("cat"):
		_active_events.erase("cat")

	var settings := _kind_config(kind)
	var duration_bounds := _float_bounds(settings, "duration_min", "duration_max")
	var count_bounds := _count_bounds(settings)
	var event := _make_event(kind, (duration_bounds.x + duration_bounds.y) * 0.5, clampi(2, count_bounds.x, count_bounds.y), true)
	_active_events[kind] = event.duplicate(true)
	auto_enabled = false
	return event.duplicate(true)


func resume_auto() -> void:
	for kind in _active_events.keys():
		if bool(_active_events[kind].get("forced", false)):
			_active_events.erase(kind)
	auto_enabled = true


func reset() -> void:
	_initialize_schedule()


func get_active_events() -> Dictionary:
	return _active_events.duplicate(true)


func _initialize_schedule() -> void:
	elapsed = 0.0
	auto_enabled = true
	next_due.clear()
	_active_events.clear()
	_serial = 0
	_forced_serial = -2
	_rng.seed = _seed
	for kind in EVENT_ORDER:
		var settings := _kind_config(kind)
		if not settings.is_empty() and bool(settings.get("enabled", false)):
			next_due[kind] = _sample_interval(kind)


func _resolve_opportunity(kind: String, foreground_attention_busy: bool, requests: Array) -> void:
	var settings := _kind_config(kind)
	var can_start := not foreground_attention_busy and _context_allows(kind) and not _active_events.has(kind)
	if kind != "cat" and _has_active_quick_event():
		can_start = false
	var accepted := false
	var duration := 0.0
	var count := 0
	if can_start:
		var chance := _weather_chance(kind)
		if TWILIGHT_PROFILES.has(str(_environment.time_profile_id)):
			chance *= clampf(float(_config.get("twilight_multiplier", 1.0)), 0.0, 1.0)
		if chance >= 1.0:
			accepted = true
		elif chance > 0.0:
			accepted = _rng.randf() < chance
	if accepted:
		duration = _sample_duration(kind)
		count = _rng.randi_range(_count_bounds(settings).x, _count_bounds(settings).y)
		var event := _make_event(kind, duration, count, false)
		_active_events[kind] = event.duplicate(true)
		requests.append(event.duplicate(true))
	next_due[kind] = elapsed + _sample_interval(kind) + (duration if accepted else 0.0)


func _make_event(kind: String, duration: float, count: int, forced: bool) -> Dictionary:
	var serial := _forced_serial if forced else _serial + 1
	if forced:
		_forced_serial -= 1
	else:
		_serial = serial
	return {
		"kind": kind,
		"start": elapsed,
		"duration": duration,
		"count": count,
		"serial": serial,
		"forced": forced,
	}


func _context_allows(kind: String) -> bool:
	var settings := _kind_config(kind)
	if not enabled or settings.is_empty() or not bool(settings.get("enabled", false)):
		return false
	if not bool(_capabilities.get(kind, false)):
		return false
	if bool(_environment.night_preview):
		if kind != "cat" or not bool(_capabilities.get("cat_night_allowed", false)):
			return false
	if kind == "cat" and str(_environment.weather_id) == "light_rain" and not bool(_capabilities.get("cat_sheltered", false)):
		return false
	return _weather_chance(kind) > 0.0


func _weather_chance(kind: String) -> float:
	var settings := _kind_config(kind)
	var weather_chances: Dictionary = settings.get("weather_chance", {})
	return clampf(float(weather_chances.get(str(_environment.weather_id), 0.0)), 0.0, 1.0)


func _kind_config(kind: String) -> Dictionary:
	var value: Variant = _config.get(kind, {})
	return value if value is Dictionary else {}


func _sample_interval(kind: String) -> float:
	var bounds := _float_bounds(_kind_config(kind), "interval_min", "interval_max")
	return maxf(0.001, _rng.randf_range(bounds.x, bounds.y))


func _sample_duration(kind: String) -> float:
	var bounds := _float_bounds(_kind_config(kind), "duration_min", "duration_max")
	return maxf(0.0, _rng.randf_range(bounds.x, bounds.y))


func _float_bounds(settings: Dictionary, low_key: String, high_key: String) -> Vector2:
	var low := maxf(0.0, float(settings.get(low_key, 0.0)))
	var high := maxf(low, float(settings.get(high_key, low)))
	return Vector2(low, high)


func _count_bounds(settings: Dictionary) -> Vector2i:
	var low := maxi(1, int(settings.get("count_min", 1)))
	var high := maxi(low, int(settings.get("count_max", low)))
	return Vector2i(low, high)


func _has_active_quick_event() -> bool:
	for kind in QUICK_EVENTS:
		if _active_events.has(kind):
			return true
	return false


func _has_due_at_current_time() -> bool:
	for kind in EVENT_ORDER:
		if next_due.has(kind) and float(next_due[kind]) <= elapsed + EPSILON:
			return true
	return false


func _expire_events() -> void:
	for kind in _active_events.keys():
		var event: Dictionary = _active_events[kind]
		if float(event.start) + float(event.duration) <= elapsed + EPSILON:
			_active_events.erase(kind)
