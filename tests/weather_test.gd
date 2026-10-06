extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Presenter := preload("res://scripts/environment_presenter.gd")
const WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const WEATHER_LABELS := {"clear": "晴", "cloudy": "多云", "light_rain": "小雨"}

var game: Control
var weather: Node
var failures := 0
var checks := 0
var profile_by_time_index: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "Tingyu main scene loads")
	if packed == null:
		_finish()
		return

	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	weather = game.weather
	check(weather.presenter is Presenter, "Tingyu adapter exposes the shared EnvironmentPresenter")
	if not weather.presenter is Presenter:
		_finish()
		return

	weather.motion_paused = true
	weather.set_process(false)
	check(weather.enabled and weather.phase == "多云" and weather.presenter.weather_id == "cloudy", "scene starts Dynamic in the selected cloudy profile")
	var original_state := _state_snapshot()
	await _check_runtime_profiles_and_bounds()
	_check_transition_and_static_contract()
	check(_state_snapshot() == original_state, "profile selection and Static/Dynamic QA preserve every gameplay property")

	# The QA profile sweeps changed presentation targets only. Reach the real
	# default again through the game's existing reset control before gameplay.
	await _press_reset()
	check(weather.enabled and weather.phase == "多云", "real reset restores Dynamic cloudy presentation")
	check(weather.presenter.time_profile_id == profile_by_time_index.get(0, ""), "reset follows the real Mao time index")
	await _exercise_real_cultivation_actions()
	await _exercise_tea_object_view()
	await _press_reset()
	check(game.state.day == 1 and game.state.time_index == 0 and game.state.energy == 100 and game.state.cultivation == 0, "reset clears the real cultivation run")
	check(not game.state.tea_active and not game.state.tea_accepted and game.state.tea_seen.is_empty() and game.state.tea_story_seen.is_empty(), "reset clears real Tea progress and object view")
	check(weather.enabled and weather.phase == "多云" and weather.presenter.time_profile_id == profile_by_time_index.get(0, ""), "reset snaps the adapter to Dynamic cloudy Mao")

	print("WEATHER_TESTS: %d checks, %d failures" % [checks, failures])
	_finish()

func _check_runtime_profiles_and_bounds() -> void:
	var before := _state_snapshot()
	var count: int = game.state.rules.times.size()
	check(count == 6, "DemoState retains six real cultivation time slots")
	for index in range(count):
		check(weather.set_time_index(index, false), "time slot %d maps to a runtime profile" % index)
		var profile_id := str(weather.presenter.time_profile_id)
		check(not profile_id.is_empty(), "time slot %d resolves to a named profile" % index)
		profile_by_time_index[index] = profile_id
		for weather_id in WEATHER_IDS:
			check(weather.set_weather(weather_id, false), "runtime profile accepts weather %s" % weather_id)
			weather.advance_environment(0.0)
			check(weather.phase == WEATHER_LABELS[weather_id], "weather %s uses its Chinese phase label" % weather_id)
			_check_safe_environment("time %d / %s" % [index, weather_id])
			check(_state_snapshot() == before, "time/weather pair %d/%s preserves all gameplay properties" % [index, weather_id])
	check(profile_by_time_index.size() == count and _unique_value_count(profile_by_time_index) == count, "all six real time slots select distinct loaded profiles")
	check(weather.presenter.get_current_environment().brightness >= weather.presenter._min_brightness, "presenter applies its runtime minimum brightness")

	var selected_weather := str(weather.presenter.weather_id)
	var motion_clock := float(weather.elapsed)
	var weather_seconds := float(weather.presenter._weather_seconds)
	weather.advance_environment(weather_seconds * 3.0)
	check(weather.presenter.weather_id == selected_weather, "elapsed environment motion does not auto-cycle weather")
	check(is_equal_approx(float(weather.elapsed), motion_clock), "QA pause freezes the motion clock while profile time advances")
	check(_state_snapshot() == before, "runtime profile timing does not mutate gameplay state")

func _check_transition_and_static_contract() -> void:
	var time_seconds := float(weather.presenter._time_seconds)
	var weather_seconds := float(weather.presenter._weather_seconds)
	var rain_release_seconds := float(weather.presenter._rain_release_seconds)
	check(time_seconds > 0.0 and weather_seconds > 0.0 and rain_release_seconds >= 0.0 and rain_release_seconds <= weather_seconds, "transition durations come from the loaded scene profile")

	weather.set_dynamic(true)
	weather.set_time_index(0, false)
	weather.set_weather("cloudy", false)
	var time_start: Dictionary = weather.presenter.get_current_environment()
	weather.set_time_index(1, true)
	var time_target: Dictionary = weather.presenter.get_target_environment()
	weather.advance_environment(time_seconds * 0.5)
	var time_mid: Dictionary = weather.presenter.get_current_environment()
	check(time_mid != time_start and time_mid != time_target, "time profile blends through a visible midpoint")
	_check_safe_environment("time transition midpoint")
	var time_before_interrupt: Dictionary = weather.presenter.get_current_environment()
	weather.set_time_index(2, true)
	check(weather.presenter.get_current_environment() == time_before_interrupt, "interrupting a time blend does not snap the current composition")
	weather.advance_environment(time_seconds)
	check(weather.presenter.get_current_environment() == weather.presenter.get_target_environment(), "interrupted time blend reaches the latest target")

	weather.set_weather("light_rain", false)
	var rain_start: Dictionary = weather.presenter.get_current_environment()
	weather.set_weather("clear", true)
	var weather_target: Dictionary = weather.presenter.get_target_environment()
	weather.advance_environment(weather_seconds * 0.5)
	var weather_mid: Dictionary = weather.presenter.get_current_environment()
	check(weather_mid != rain_start and weather_mid != weather_target, "weather profile blends through a visible midpoint")
	_check_safe_environment("weather transition midpoint")
	var weather_before_interrupt: Dictionary = weather.presenter.get_current_environment()
	weather.set_weather("cloudy", true)
	check(weather.presenter.get_current_environment() == weather_before_interrupt, "interrupting a weather blend does not snap the current composition")
	weather.set_weather("light_rain", false)
	weather.set_weather("clear", true)
	weather.advance_environment(rain_release_seconds)
	check(float(weather.presenter.get_current_environment().rain_amount) <= 0.001, "rain releases on the runtime profile's shorter fade")
	weather.advance_environment(weather_seconds)
	check(weather.presenter.get_current_environment() == weather.presenter.get_target_environment(), "weather blend reaches its latest target")

	weather.set_weather("cloudy", false)
	weather.set_dynamic(false)
	var held_elapsed := float(weather.elapsed)
	var static_start: Dictionary = weather.presenter.get_current_environment()
	weather.set_weather("light_rain", true)
	weather.advance_environment(weather_seconds * 0.5)
	check(not weather.enabled and weather.presenter.weather_id == "light_rain", "Static accepts a new weather request and stays Static")
	check(is_equal_approx(float(weather.elapsed), held_elapsed), "Static freezes environment motion while weather continues blending")
	check(weather.presenter.get_current_environment() != static_start, "Static weather request keeps transitioning")
	weather.advance_environment(weather_seconds)
	var settled: Dictionary = weather.presenter.get_current_environment()
	_check_safe_environment("settled Static rain")
	var rain_visible: bool = not weather.rain_nodes.is_empty()
	for rain in weather.rain_nodes:
		rain_visible = rain_visible and rain.visible
	check(rain_visible, "Static keeps settled rain visible")
	var mist_visible := false
	for layer in weather.mist_layers:
		mist_visible = mist_visible or layer.visible
	check(mist_visible, "Static keeps settled mist visible")
	var materials_retained := true
	for item in weather.lit:
		materials_retained = materials_retained and item.art.material == item.weather
	for layer in weather.mist_layers:
		materials_retained = materials_retained and layer.material is ShaderMaterial
	for rain in weather.rain_nodes:
		materials_retained = materials_retained and rain.material is ShaderMaterial
	materials_retained = materials_retained and weather.bamboo.material == weather.bamboo_material
	check(materials_retained, "Static retains painted-world, mist, rain, and bamboo materials")
	check(not weather.mist_layers.is_empty(), "scene retains its authored mist layers in Static")
	check(is_equal_approx(float(weather.elapsed), held_elapsed), "settling Static rain still holds the motion clock")
	check(settled == weather.presenter.get_target_environment(), "Static settles its selected environment profile")

	weather.set_time_index(0, true)
	var static_time_before: Dictionary = weather.presenter.get_current_environment()
	weather.advance_environment(time_seconds)
	check(weather.presenter.get_current_environment() != static_time_before, "Static also blends a requested time profile")
	check(is_equal_approx(float(weather.elapsed), held_elapsed), "Static time blending does not advance motion")

	weather.set_weather("cloudy", false)
	weather.next_phase()
	check(not weather.enabled and weather.presenter.weather_id == "light_rain", "next phase advances from cloudy to rain without leaving Static")
	weather.next_phase()
	check(not weather.enabled and weather.presenter.weather_id == "clear", "next phase advances from rain to clear without leaving Static")
	weather.next_phase()
	check(not weather.enabled and weather.presenter.weather_id == "cloudy", "next phase wraps to cloudy and remains Static")
	weather.toggle()
	check(weather.enabled and weather.presenter.weather_id == "cloudy", "Dynamic resumes without resetting the selected weather")
	var dynamic_start := float(weather.elapsed)
	weather.motion_paused = false
	weather.advance_environment(0.25)
	check(float(weather.elapsed) > dynamic_start, "Dynamic resumes advancing the motion clock")
	weather.set_dynamic(false)
	var dynamic_held := float(weather.elapsed)
	weather.advance_environment(weather_seconds)
	check(not weather.enabled and is_equal_approx(float(weather.elapsed), dynamic_held), "Static freezes the motion clock after Dynamic resumes")
	weather.toggle()
	check(weather.enabled, "Dynamic can be restored after a Static comparison")
	weather.motion_paused = true
	weather.set_process(false)

func _exercise_real_cultivation_actions() -> void:
	var rules: Dictionary = game.state.rules
	game.train_button.emit_signal("pressed")
	await _wait_until_idle()
	check(game.state.energy == 78 and game.state.cultivation == 12, "real training button settles the original 100 to 78 / 0 to 12 result")
	check(game.state.time_index == (2 % game.state.rules.times.size()), "real training advances its authored two time slots")
	_assert_time_profile_matches_state("after training")

	game.mentor_button.emit_signal("pressed")
	check(game.state.dialogue_open, "real mentor button opens the original dialogue")
	var before_dialogue_weather := _state_snapshot()
	_exercise_presentation_only("while dialogue choices are open")
	check(_state_snapshot() == before_dialogue_weather, "weather and Static controls preserve every property while choices are open")
	game.choices[2].emit_signal("pressed")
	check(not game.state.dialogue_open and game.state.energy == 78 and game.state.time_index == 2, "real cancel choice closes dialogue without settling energy or time")

	game.mentor_button.emit_signal("pressed")
	game.choices[0].emit_signal("pressed")
	check(game.awaiting_continue and game.state.energy == 70 and game.state.cultivation == 12 and game.state.understanding == 1 and game.state.lesson_bonus == 6, "real breathing choice preserves its original 70 energy and one-time +6 bonus")
	_assert_time_profile_matches_state("after breathing choice")
	var before_continue_weather := _state_snapshot()
	_exercise_presentation_only("while mentor result awaits Continue")
	check(_state_snapshot() == before_continue_weather, "weather and Static controls preserve every property while Continue is pending")
	game.continue_button.emit_signal("pressed")
	check(not game.awaiting_continue and not game.state.dialogue_open, "real Continue returns to the cultivation loop")

	game.train_button.emit_signal("pressed")
	await _wait_until_idle()
	check(game.state.energy == 48 and game.state.cultivation == 30 and game.state.lesson_bonus == 0, "real training consumes the one-time bonus for the original 48 energy / 30 progress result")
	_assert_time_profile_matches_state("after bonus training")
	game.rest_button.emit_signal("pressed")
	check(game.state.energy == 82 and game.state.cultivation == 30, "real rest restores 34 energy for the original 82 / 30 state")
	_assert_time_profile_matches_state("after rest")
	game.mentor_button.emit_signal("pressed")
	game.choices[1].emit_signal("pressed")
	check(game.awaiting_continue and game.state.energy == 74 and game.state.understanding == 2 and game.state.lesson_bonus == 0, "real mountain choice settles its original cost without a breathing bonus")
	_assert_time_profile_matches_state("after mountain choice")
	game.continue_button.emit_signal("pressed")
	check(not game.awaiting_continue, "real Continue closes the mountain result screen")
	check(rules.times.size() == 6, "real action checks preserve the six-slot cultivation clock")

func _exercise_presentation_only(label: String) -> void:
	var before := _state_snapshot()
	weather.set_weather("light_rain", true)
	weather.advance_environment(float(weather.presenter._weather_seconds) * 0.5)
	weather.set_dynamic(false)
	weather.advance_environment(float(weather.presenter._weather_seconds) * 0.5)
	weather.toggle()
	weather.toggle()
	check(not weather.enabled and weather.phase == "小雨", "%s keeps the requested rainy Static profile" % label)
	check(_state_snapshot() == before, "%s presentation changes do not mutate gameplay" % label)

func _exercise_tea_object_view() -> void:
	game._open_tea()
	game.tea_accept.emit_signal("pressed")
	await process_frame
	check(game.state.tea_active and game.state.tea_accepted, "Tea branch enters through its real acceptance button")
	game.tea_hotspots["tea.cup_first"].emit_signal("pressed")
	await process_frame
	check(game.state.tea_seen.has("tea.cup_first") and game.object_popover.visible, "original first-cup button opens its object action view")
	var object_view_state := _state_snapshot()
	_exercise_presentation_only("while the Tea object view is open")
	check(_state_snapshot() == object_view_state, "weather and Static controls preserve every Tea property and object view")

func _press_reset() -> void:
	var button := _find_button_by_text(game, "重新开始")
	check(button != null, "cultivation screen exposes its real reset button")
	if button != null:
		button.emit_signal("pressed")
	await process_frame
	weather.motion_paused = true
	weather.set_process(false)

func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

func _wait_until_idle() -> void:
	for _attempt in range(40):
		if not game.busy:
			return
		await create_timer(0.05).timeout
	check(not game.busy, "training animation reaches its settled UI state")

func _assert_time_profile_matches_state(label: String) -> void:
	var index := int(game.state.time_index)
	check(weather.presenter.time_profile_id == profile_by_time_index.get(index, ""), "%s environment follows the actual DemoState time index" % label)

func _state_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for property in game.state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = game.state.get(property.name)
		if value is Object:
			continue
		snapshot[str(property.name)] = _deep_copy(value)
	return snapshot

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:
			copy[key] = _deep_copy(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for item in value:
			copy.append(_deep_copy(item))
		return copy
	return value

func _check_safe_environment(label: String) -> void:
	var values: Dictionary = weather.presenter.get_current_environment()
	var brightness := float(values.get("brightness", -1.0))
	var minimum := float(weather.presenter._min_brightness)
	var rain := float(values.get("rain_amount", -1.0))
	check(brightness >= minimum and brightness <= 1.25, "%s brightness remains within safe profile bounds" % label)
	check(rain >= 0.0 and rain <= 1.0, "%s rain amount remains normalized" % label)

func _unique_value_count(values: Dictionary) -> int:
	var unique: Dictionary = {}
	for key in values:
		unique[str(values[key])] = true
	return unique.size()

func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func _finish() -> void:
	print("WEATHER_TEST_RESULT: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
