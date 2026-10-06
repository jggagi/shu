extends SceneTree

const Presenter = preload("res://scripts/ambient_life_presenter.gd")
const CONFIG_PATH := "res://assets/data/back_mountain_ambient_life.json"
const KINDS := ["birds", "squirrel", "cat", "fish"]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	check(not source.is_empty(), "ambient-life config loads")
	if source.is_empty():
		_finish()
		return
	var source_snapshot := source.duplicate(true)
	_test_fixed_schedule(source)
	_test_partition_determinism(source)
	_test_force_pause_resume_and_reset(source)
	_test_observation_gates(source)
	_test_missing_fish_capability(source)
	_test_twilight_and_attention(source)
	check(source == source_snapshot, "presenter operations do not mutate source config")
	_finish()


func _test_fixed_schedule(source: Dictionary) -> void:
	var config := _fixed_config(source)
	var presenter = _new_presenter(config, 17)
	presenter.observe(_environment(), _capabilities())
	check(presenter.next_due.get("birds") == 1.0 and presenter.next_due.get("squirrel") == 1.0 and presenter.next_due.get("cat") == 1.0, "each enabled kind gets an independent initial deadline")
	check(not presenter.next_due.has("fish") or presenter.next_due.get("fish") == 3.0, "disabled production fish has no deadline; enabled fixture fish has its own deadline")
	var requests: Array = presenter.advance(1.0)
	check(_kinds(requests) == ["birds", "cat"], "stable tie order accepts birds first and lets the quiet cat coexist")
	var active: Dictionary = presenter.get_active_events()
	check(active.has("birds") and active.has("cat") and not active.has("squirrel"), "at most one quick event is active while cat remains independent")
	check(is_equal_approx(float(presenter.next_due.birds), 4.0), "accepted quick event schedules its next opportunity after duration plus interval")
	check(is_equal_approx(float(presenter.next_due.squirrel), 2.0), "collision rejection reschedules after the interval only")
	check(is_equal_approx(float(presenter.next_due.cat), 7.0), "accepted quiet event schedules after its duration plus interval")
	var event: Dictionary = active.birds
	check(event.kind == "birds" and event.start == 1.0 and event.duration == 2.0 and event.count >= 1 and event.count <= 3 and not event.forced, "automatic event includes its configured request fields")
	active.birds.count = 99
	check(int(presenter.get_active_events().birds.count) != 99, "active event results are deep copies")

	var busy_presenter = _new_presenter(config, 17)
	busy_presenter.observe(_environment(), _capabilities())
	check(busy_presenter.advance(1.0, true).is_empty(), "foreground attention suppresses all new events")
	check(busy_presenter.get_active_events().is_empty(), "busy suppression creates no active event")
	check(is_equal_approx(float(busy_presenter.next_due.birds), 2.0), "busy rejection advances only the opportunity interval")
	check(_kinds(busy_presenter.advance(1.0)) == ["birds", "cat"], "automatic opportunities resume after attention clears")


func _test_partition_determinism(source: Dictionary) -> void:
	var config := _fixed_config(source)
	var once = _new_presenter(config, 20261006)
	var partitioned = _new_presenter(config, 20261006)
	var env := _environment()
	var caps := _capabilities()
	once.observe(env, caps)
	partitioned.observe(env, caps)
	var one_step_requests: Array = once.advance(240.0)
	var many_step_requests: Array = []
	for _step in 480:
		many_step_requests.append_array(partitioned.advance(0.5))
	check(one_step_requests == many_step_requests, "same seed produces identical scheduled requests across delta partitions")
	check(once.get_active_events() == partitioned.get_active_events(), "partitioned runs finish with identical active events")
	check(once.next_due == partitioned.next_due and is_equal_approx(once.elapsed, partitioned.elapsed), "partitioned runs finish with identical deadlines and event time")


func _test_force_pause_resume_and_reset(source: Dictionary) -> void:
	var config := _fixed_config(source)
	var snapshot := config.duplicate(true)
	var forced = _new_presenter(config, 31)
	var control = _new_presenter(config, 31)
	forced.observe(_environment(), _capabilities())
	control.observe(_environment(), _capabilities())
	var deadlines: Dictionary = forced.next_due.duplicate(true)
	var rng_state: int = forced._rng.state
	var bird: Dictionary = forced.force_event("birds")
	var cat: Dictionary = forced.force_event("cat")
	var squirrel: Dictionary = forced.force_event("squirrel")
	check(not bird.is_empty() and bird.forced and bird.duration == 2.0 and bird.count == 2 and bird.serial == -2, "forced event uses its fixed midpoint, count, and reserved negative serial")
	check(not cat.is_empty() and cat.serial == -3 and int(cat.count) == 1, "forced cat clamps count two to its configured range")
	check(not squirrel.is_empty() and squirrel.serial == -4, "forcing a quick event replaces the other quick event")
	check(forced.get_active_events().has("cat") and forced.get_active_events().has("squirrel") and not forced.get_active_events().has("birds"), "forced quick replacement preserves quiet cat")
	check(not forced.auto_enabled and forced.next_due == deadlines, "accepted force pauses auto without changing deadlines")
	check(forced._rng.state == rng_state, "force consumes no scheduler RNG state")
	forced.resume_auto()
	check(forced.auto_enabled and forced.get_active_events().is_empty(), "resume clears forced events and resumes auto")
	var after_force: Array = forced.advance(120.0)
	var control_events: Array = control.advance(120.0)
	check(after_force == control_events, "forced QA events leave automatic RNG and serial streams unchanged")
	check(config == snapshot, "forced and automatic scheduling leave copied config immutable")

	var paused = _new_presenter(config, 44)
	paused.observe(_environment(), _capabilities())
	paused.force_event("cat")
	var before_pause_advance: Dictionary = paused.next_due.duplicate(true)
	paused.advance(2.0)
	for kind in before_pause_advance:
		check(is_equal_approx(float(paused.next_due[kind]), float(before_pause_advance[kind]) + 2.0), "paused auto deadline for %s shifts with event time" % kind)
	check(is_equal_approx(paused.elapsed, 2.0) and paused.get_active_events().has("cat"), "auto pause still advances active event time")
	paused.set_enabled(false)
	check(paused.get_active_events().is_empty(), "disabling clears active events")
	var fresh = _new_presenter(config, 44)
	paused.reset()
	check(not paused.enabled and paused.auto_enabled and paused.elapsed == 0.0 and paused.get_active_events().is_empty(), "reset preserves enabled state and restores auto/time/events")
	check(paused.next_due == fresh.next_due, "reset restarts the fixed seed and initial deadlines")
	check(paused.force_event("birds").is_empty(), "disabled presenter rejects forced events")
	paused.advance(3.0)
	check(paused.elapsed == 0.0, "disabled presenter does not advance event time")


func _test_observation_gates(source: Dictionary) -> void:
	var presenter = _new_presenter(source, 53)
	var caps := _capabilities()
	presenter.observe(_environment("shen", "light_rain", false, true), caps)
	check(not presenter.can_spawn("birds") and not presenter.can_spawn("squirrel"), "rain-zero weather chances gate birds and squirrels")
	check(not presenter.can_spawn("cat"), "rain blocks exposed cat")
	check(presenter.force_event("birds").is_empty() and presenter.force_event("cat").is_empty(), "force respects weather restrictions")
	caps.cat_sheltered = true
	presenter.observe(_environment("shen", "light_rain", false, true), caps)
	check(presenter.can_spawn("cat"), "sheltered cat remains valid in rain")
	var rainy_cat: Dictionary = presenter.force_event("cat")
	check(not rainy_cat.is_empty(), "forced sheltered cat is allowed in rain")

	caps.cat_night_allowed = false
	presenter.observe(_environment("you", "clear", true, true), caps)
	check(presenter.get_active_events().is_empty() and not presenter.can_spawn("cat"), "night immediately cancels cat without night permission")
	caps.cat_night_allowed = true
	presenter.observe(_environment("you", "clear", true, true), caps)
	check(presenter.can_spawn("cat") and not presenter.can_spawn("birds") and not presenter.can_spawn("fish"), "night permits only a capability-approved cat")
	var night_cat: Dictionary = presenter.force_event("cat")
	check(not night_cat.is_empty(), "forced night cat respects its capability")
	presenter.observe(_environment("you", "clear", true, false), caps)
	check(presenter.get_active_events().has("cat"), "static mode preserves an otherwise valid cat")
	var frozen_time: float = presenter.elapsed
	check(presenter.advance(20.0).is_empty() and presenter.elapsed == frozen_time and presenter.get_active_events().has("cat"), "static mode freezes time and the quiet cat")
	check(presenter.force_event("cat").is_empty(), "static mode rejects forced event starts")
	presenter.observe(_environment("you", "clear", false, true), caps)
	check(presenter.get_active_events().has("cat"), "leaving static mode resumes the existing cat")

	var quick = _new_presenter(source, 54)
	quick.observe(_environment(), caps)
	check(not quick.force_event("birds").is_empty(), "clear weather can start birds")
	quick.observe(_environment("mao", "light_rain", false, true), caps)
	check(not quick.get_active_events().has("birds"), "newly illegal rain immediately cancels birds")


func _test_missing_fish_capability(source: Dictionary) -> void:
	var config := _fixed_config(source)
	var presenter = _new_presenter(config, 61)
	var caps := _capabilities()
	caps.fish = false
	presenter.observe(_environment(), caps)
	check(not presenter.can_spawn("fish") and presenter.force_event("fish").is_empty(), "missing fish capability blocks automatic and forced fish")
	caps.fish = true
	presenter.observe(_environment(), caps)
	check(presenter.can_spawn("fish") and not presenter.force_event("fish").is_empty(), "fish can be scheduled when the host explicitly supplies its capability")


func _test_twilight_and_attention(source: Dictionary) -> void:
	var config := _fixed_config(source)
	config.twilight_multiplier = 0.0
	var automatic = _new_presenter(config, 71)
	automatic.observe(_environment("shen", "clear", false, true), _capabilities())
	check(automatic.can_spawn("birds"), "twilight probability reduction does not disable the capability control")
	check(automatic.advance(1.0).is_empty(), "twilight multiplier is applied only to scheduled probability")
	var forced = _new_presenter(config, 71)
	forced.observe(_environment("you", "clear", false, true), _capabilities())
	check(not forced.force_event("birds").is_empty(), "force bypasses twilight probability while respecting time/weather eligibility")


func _new_presenter(config: Dictionary, seed: int = -1):
	var presenter = Presenter.new()
	presenter.configure(config, seed)
	return presenter


func _fixed_config(source: Dictionary) -> Dictionary:
	var config := source.duplicate(true)
	config["twilight_multiplier"] = 1.0
	for kind in KINDS:
		var settings: Dictionary = config.get(kind, {}).duplicate(true)
		settings["enabled"] = true
		settings["interval_min"] = 3.0 if kind == "fish" else 1.0
		settings["interval_max"] = settings["interval_min"]
		settings["duration_min"] = 5.0 if kind == "cat" else 2.0 if kind in ["birds", "fish"] else 1.0
		settings["duration_max"] = settings["duration_min"]
		settings["count_min"] = 1
		settings["count_max"] = 3 if kind in ["birds", "fish"] else 1
		settings["weather_chance"] = {"clear": 1.0, "cloudy": 1.0, "light_rain": 1.0}
		config[kind] = settings
	return config


func _environment(time_id: String = "mao", weather: String = "clear", night: bool = false, dynamic: bool = true) -> Dictionary:
	return {"time_profile_id": time_id, "weather_id": weather, "night_preview": night, "dynamic_enabled": dynamic}


func _capabilities(sheltered: bool = false, night_allowed: bool = false) -> Dictionary:
	return {
		"birds": true,
		"squirrel": true,
		"cat": true,
		"fish": true,
		"cat_sheltered": sheltered,
		"cat_night_allowed": night_allowed,
	}


func _kinds(events: Array) -> Array:
	var kinds: Array = []
	for event in events:
		kinds.append(str(event.kind))
	return kinds


func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func _finish() -> void:
	print("AMBIENT_LIFE_PRESENTER_TESTS: " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
