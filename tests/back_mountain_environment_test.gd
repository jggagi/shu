extends SceneTree

const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const ENVIRONMENT_CONFIG_PATH := "res://assets/data/back_mountain_environment.json"
const EXPECTED_TIME_PROFILES := ["mao", "chen", "si", "wu", "shen", "you"]
const EXPECTED_WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const ENVIRONMENT_KEYS := [
	"brightness", "world_tint", "sky_tint", "sky_strength", "far_contrast",
	"mist_multiplier", "far_cloud_multiplier", "valley_cloud_multiplier",
	"cloud_shadow_strength", "rain_amount", "wind_strength"
]

var game: Control
var failures := 0
var checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "standalone back mountain scene loads")
	if packed == null:
		_finish()
		return

	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	check(game.state != null and game.environment_presenter != null, "scene exposes DemoState and Environment v1 presenter")
	check(game.environment_config is Dictionary and not game.environment_config.is_empty(), "scene exposes the loaded Environment v1 configuration")
	check(game.environment_adapter != null, "scene exposes the environment material adapter")
	if game.state == null or game.environment_presenter == null or game.environment_adapter == null:
		_finish()
		return

	game.qa_motion_paused = true
	game.set_process(false)
	game.set_dynamic(false)
	game.set_lighting(false)
	var presenter = game.environment_presenter
	var config: Dictionary = game.environment_config
	var config_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ENVIRONMENT_CONFIG_PATH))
	check(config == config_file, "scene uses the checked-in Environment v1 configuration")
	var expected_times: Array = game.state.rules.times
	var time_mapping: Dictionary = config.get("time_mapping", {})
	check(expected_times.size() == EXPECTED_TIME_PROFILES.size(), "DemoState exposes the six configured cultivation times")
	check(time_mapping.size() == EXPECTED_TIME_PROFILES.size(), "time_mapping defines one profile for every cultivation time")
	for time_index in range(mini(expected_times.size(), EXPECTED_TIME_PROFILES.size())):
		var label := str(expected_times[time_index])
		var expected_profile := str(EXPECTED_TIME_PROFILES[time_index])
		check(str(time_mapping.get(label, "")) == expected_profile, "time_mapping maps %s to %s" % [label, expected_profile])
		game.state.time_index = time_index
		game.refresh_environment(false)
		check(str(presenter.time_profile_id) == expected_profile, "refresh_environment selects %s from authoritative DemoState time" % expected_profile)

	for time_index in range(mini(expected_times.size(), EXPECTED_TIME_PROFILES.size())):
		for weather_id in EXPECTED_WEATHER_IDS:
			game.state.time_index = time_index
			presenter.set_weather(weather_id, false)
			game.set_night_preview(false, false)
			game.refresh_environment(false)
			var first_composition: Dictionary = presenter.get_current_environment().duplicate(true)
			game.refresh_environment(false)
			var repeated_composition: Dictionary = presenter.get_current_environment().duplicate(true)
			check(first_composition == repeated_composition, "time/weather composition %s + %s is deterministic" % [EXPECTED_TIME_PROFILES[time_index], weather_id])

	# The two independent clocks produce the same midpoint regardless of how the
	# same elapsed duration is partitioned across calls.
	var stepped_once = load("res://scripts/environment_presenter.gd").new()
	var stepped_many = load("res://scripts/environment_presenter.gd").new()
	stepped_once.configure(config)
	stepped_many.configure(config)
	for sample_presenter in [stepped_once, stepped_many]:
		sample_presenter.set_time_profile("you", true)
		sample_presenter.set_weather("light_rain", true)
	stepped_once.advance(4.0)
	for _step in 8:
		stepped_many.advance(0.5)
	check(stepped_once.get_current_environment() == stepped_many.get_current_environment(), "partitioned advances produce the same independent time/weather midpoint")

	var weather_buttons: Dictionary = game.weather_buttons
	var weather_ids := _sorted_keys(weather_buttons)
	check(weather_ids == EXPECTED_WEATHER_IDS, "weather controls expose exactly clear, cloudy, and light_rain")
	var weather_profiles: Dictionary = config.get("weather_profiles", {})
	check(_sorted_keys(weather_profiles) == EXPECTED_WEATHER_IDS, "weather configuration exposes exactly the three supported profiles")
	check(game.night_button is Button, "night preview has a visible Button control")
	check(game.environment_adapter.rain_material is ShaderMaterial, "environment adapter exposes the rain shader material")
	check(game.environment_adapter.shadow_material is ShaderMaterial, "environment adapter exposes the cloud-shadow shader material")
	check(game.environment_adapter.far_material is ShaderMaterial, "environment adapter exposes the far-art shader material")

	# Use a full synthetic DemoState fixture so every current and future script
	# property, including tea session/progress data, is covered by comparisons.
	game.state.day = 3
	game.state.time_index = 0
	game.state.energy = 67
	game.state.cultivation = 29
	game.state.understanding = 4
	game.state.lesson_bonus = 6
	game.state.dialogue_open = true
	game.state.tea_accepted = true
	game.state.tea_seen = {"tea.cup_first": true}
	game.state.tea_stage_complete = false
	game.state.tea_quest_complete = false
	# Cover parallel story fields when present without requiring story changes in
	# an independent Back Mountain archive built on the existing A/B DemoState.
	var optional_story_fields := {
		"tea_scene_id": "tea.old_courtyard", "tea_c_seen": {"tea.ledger": true}, "tea_c_complete": false,
		"tea_story_stage": 2, "tea_story_seen": {"D": true}, "tea_story_page": 1,
		"tea_story_object": "tea.medicine_pot", "tea_story_token": 8,
		"tea_ending_step": 1, "_tea_ending_first_fill_msec": 23,
	}
	var saved_fields := _full_state_snapshot()
	for field in optional_story_fields:
		if saved_fields.has(field):
			game.state.set(field, optional_story_fields[field])
	game.state.tea_action_done = {"tea.cup_first": "repair"}
	game.state.tea_active = true
	game.state.tea_session = 19
	game.state._tea_read_counter = 3
	game.state._tea_pending_object_id = "tea.cup_second"
	game.state._tea_pending_read_token = 3
	game.refresh_environment(false)
	var state_before_presentation := _full_state_snapshot()
	var time_before_determinism: String = str(presenter.time_profile_id)
	var environment_first: Dictionary = presenter.get_current_environment().duplicate(true)
	for key in ENVIRONMENT_KEYS:
		check(environment_first.has(key), "composed environment contains %s" % key)
	game.refresh_environment(false)
	var environment_second: Dictionary = presenter.get_current_environment().duplicate(true)
	check(environment_first == environment_second, "equal time/weather/night inputs compose deterministically")
	check(str(presenter.time_profile_id) == time_before_determinism, "deterministic composition preserves selected time profile")
	check(_full_state_snapshot() == state_before_presentation, "composition preserves all DemoState and tea properties")

	var current_before_invalid: Dictionary = presenter.get_current_environment().duplicate(true)
	var target_before_invalid: Dictionary = presenter.get_target_environment().duplicate(true)
	var time_before_invalid := str(presenter.time_profile_id)
	var weather_before_invalid := str(presenter.weather_id)
	var invalid_weather_accepted: bool = game.set_weather("not_a_weather", false)
	var invalid_profile_accepted = presenter.set_time_profile("not_a_time", false)
	check(not invalid_weather_accepted and not bool(invalid_profile_accepted), "invalid weather and time profile IDs are rejected")
	check(str(presenter.time_profile_id) == time_before_invalid and str(presenter.weather_id) == weather_before_invalid, "invalid IDs leave selected time and weather unchanged")
	check(presenter.get_current_environment() == current_before_invalid and presenter.get_target_environment() == target_before_invalid, "invalid IDs leave current and target environment unchanged")

	game.set_weather("cloudy", true)
	game.set_night_preview(true, true)
	game.set_dynamic(true)
	presenter.advance(0.4)
	game.set_dynamic(false)
	presenter.advance(0.4)
	check(_full_state_snapshot() == state_before_presentation, "weather, night, dynamic mode, and transition advancement preserve full DemoState including tea")
	check(str(presenter.weather_id) == "cloudy" and bool(presenter.night_preview), "weather and night presentation choices remain selected after dynamic toggles")

	# Retargeting while weather is partway through must preserve the current
	# composed frame, finish the shorter time transition, and leave weather moving.
	game.set_weather("clear", false)
	presenter.set_time_profile("mao", false)
	game.set_night_preview(false, false)
	game.set_weather("cloudy", true)
	presenter.advance(2.0)
	var interrupted_frame: Dictionary = presenter.get_current_environment().duplicate(true)
	game.state.time_index = 4
	game.refresh_environment(true)
	var retargeted_frame: Dictionary = presenter.get_current_environment().duplicate(true)
	check(interrupted_frame == retargeted_frame, "retargeting time during weather transition causes no visual parameter jump")
	var transition_state_snapshot := _full_state_snapshot()
	presenter.advance(1.2)
	check(str(presenter.time_profile_id) == "shen", "short time transition reaches the authoritative Shen profile")
	check(presenter.get_current_environment() != presenter.get_target_environment(), "short time transition does not finish the independent eight-second weather blend")
	check(_full_state_snapshot() == transition_state_snapshot, "interrupted independent transitions preserve every DemoState property")
	presenter.set_weather("light_rain", false)
	var rain_before_clear: Dictionary = presenter.get_current_environment().duplicate(true)
	presenter.set_weather("clear", true)
	check(presenter.get_current_environment() == rain_before_clear, "rain-to-clear transition preserves its starting frame")
	presenter.advance(4.0)
	var rain_release_mid: Dictionary = presenter.get_current_environment()
	check(is_equal_approx(float(rain_release_mid.rain_amount), 0.0), "rain amount reaches clear after its four-second release")
	check(rain_release_mid != presenter.get_target_environment(), "rain release completes while the remaining weather blend continues")
	check(_full_state_snapshot() == transition_state_snapshot, "rain release preserves every DemoState property")
	game.state.time_index = 0
	game.refresh_environment(false)
	check(_full_state_snapshot() == state_before_presentation, "restoring the Mao fixture preserves all other DemoState properties")

	# Lighting OFF must still write every environment control into the real shader
	# materials, including the weather and cloud layers.
	game.set_lighting(false)
	presenter.finish_transition()
	var environment: Dictionary = presenter.get_current_environment()
	game.environment_adapter.apply_environment(environment)
	var far_material: ShaderMaterial = game.environment_adapter.far_material
	var rain_material: ShaderMaterial = game.environment_adapter.rain_material
	var shadow_material: ShaderMaterial = game.environment_adapter.shadow_material
	var expected_tint := Color(
		float(environment.world_tint.r) * float(environment.brightness),
		float(environment.world_tint.g) * float(environment.brightness),
		float(environment.world_tint.b) * float(environment.brightness),
		1.0)
	check(not game.lighting_enabled, "uniform application is checked with Lighting disabled")
	check(game._displayed_tint == expected_tint, "Lighting OFF applies world tint and brightness to painted art")
	check(is_equal_approx(float(far_material.get_shader_parameter("far_contrast")), float(environment.far_contrast)), "Lighting OFF applies far contrast to its shader uniform")
	check(is_equal_approx(float(far_material.get_shader_parameter("sky_strength")), float(environment.sky_strength)), "Lighting OFF applies sky strength to its shader uniform")
	check(far_material.get_shader_parameter("sky_tint") == environment.sky_tint, "Lighting OFF applies sky tint to its shader uniform")
	check(is_equal_approx(float(rain_material.get_shader_parameter("rain_amount")), float(environment.rain_amount)), "Lighting OFF applies rain amount to its shader uniform")
	check(is_equal_approx(float(shadow_material.get_shader_parameter("cloud_min_brightness")), 1.0 - float(environment.cloud_shadow_strength)), "Lighting OFF applies cloud-shadow strength to its shader uniform")
	var cloud_config: Dictionary = game.config.get("clouds", {})
	var cloud_bases := [float(cloud_config.get("far_alpha", 0.0)), float(cloud_config.get("valley_alpha", 0.0)) * 0.8, float(cloud_config.get("valley_alpha", 0.0))]
	for cloud_index in range(game._cloud_materials.size()):
		var cloud_multiplier := float(environment.far_cloud_multiplier if cloud_index == 0 else environment.valley_cloud_multiplier)
		var expected_alpha := clampf(cloud_bases[cloud_index] * cloud_multiplier, 0.0, 0.85)
		var actual_alpha := float(game._cloud_materials[cloud_index].get_shader_parameter("cloud_alpha"))
		check(is_equal_approx(actual_alpha, expected_alpha), "Lighting OFF applies composed cloud multiplier to layer %d" % cloud_index)
	for mist_index in range(game._mist_materials.size()):
		var expected_density := clampf(float(game.config.mist_density) * float(environment.mist_multiplier) * game._mist_layer_factor(mist_index), 0.0, 0.3)
		var actual_density := float(game._mist_materials[mist_index].get_shader_parameter("mist_density"))
		check(is_equal_approx(actual_density, expected_density), "Lighting OFF applies composed mist multiplier to layer %d" % mist_index)
	game.set_dynamic(true)
	if not game._gust_schedule.is_empty():
		var gust: Dictionary = game._gust_schedule[0]
		var wind_time := float(gust.start) + float(gust.duration) * 0.5
		game.seek_presentation(wind_time)
		game._sync_shader_times()
		var expected_wind := float(game.config.get("gust_wind_strength", 0.06)) * float(environment.wind_strength)
		check(is_equal_approx(float(game._near_material.get_shader_parameter("wind_strength")), expected_wind), "Lighting OFF applies weather wind strength to near foliage motion")
		check(is_equal_approx(float(game._hair_material.get_shader_parameter("wind_strength")), expected_wind), "Lighting OFF applies weather wind strength to actor hair motion")
	game.set_dynamic(false)
	check(_full_state_snapshot() == state_before_presentation, "shader uniform application preserves all DemoState and tea properties")

	# A genuine action settles the rules time synchronously; the environment target
	# must immediately use that actual state index even while the action is busy.
	game.state.reset()
	game.config.training_seconds = 0.05
	game.set_dynamic(false)
	game.set_weather("clear", false)
	game.set_night_preview(false, false)
	game.set_process(true)
	var training: Dictionary = game.request_training()
	check(bool(training.get("ok", false)) and game.busy, "training fixture begins through the real request path")
	var training_time_label := str(game.state.rules.times[game.state.time_index])
	var training_profile := str(time_mapping.get(training_time_label, ""))
	check(str(presenter.time_profile_id) == training_profile, "training immediately targets the newly settled authoritative time profile")
	var training_deadline := Time.get_ticks_msec() + 2500
	while game.busy and Time.get_ticks_msec() < training_deadline:
		await process_frame
	check(not game.busy, "short training fixture returns to idle")
	game.set_process(false)
	check(game.reset_demo(), "environment state test can reset after training")
	presenter.finish_transition()
	check(int(game.state.time_index) == 0 and str(presenter.time_profile_id) == "mao", "reset restores initial DemoState and Mao environment profile")
	check(str(presenter.weather_id) == "clear" and not bool(presenter.night_preview), "reset clears night preview and keeps the selected clear weather")

	_finish()

func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _full_state_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for property in game.state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value = game.state.get(name)
		if value is Dictionary or value is Array:
			snapshot[name] = value.duplicate(true)
		else:
			snapshot[name] = value
	snapshot["time_text"] = game.state.time_text()
	return snapshot

func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)

func _finish() -> void:
	print("BACK_MOUNTAIN_ENVIRONMENT_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
