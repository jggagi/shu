extends SceneTree

const Presenter := preload("res://scripts/ambient_life_presenter.gd")

var failures := 0
var checks: Dictionary = {}
var game: Control
var life: Node
var marker_root: Node2D
var initial_state: Dictionary = {}
var initial_schedule: Dictionary = {}
var initial_config: Dictionary = {}


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
	check(game.ambient_life != null and game.ambient_life.presenter != null, "Tingyu exposes its Ambient Life adapter and presenter")
	if game.ambient_life == null or game.ambient_life.presenter == null:
		_finish()
		return

	life = game.ambient_life
	game.set_process(false)
	game.weather.set_process(false)
	life.set_process(false)
	game.weather.motion_paused = true
	game.set_ambient_life_enabled(true)
	game.weather.set_dynamic(true)
	life.reset()
	life.observe_environment()
	initial_state = _state_snapshot()
	initial_config = life.config.duplicate(true)
	initial_schedule = life.presenter.next_due.duplicate(true)

	marker_root = game.cultivation_scene.get_node_or_null("AmbientCapabilities") as Node2D
	check(marker_root != null, "Tingyu mounts authored ambient capability markers under the cultivation scene")
	if marker_root == null:
		_finish()
		return

	var bird_lane := marker_root.get_node_or_null("BirdLane") as Path2D
	check(bird_lane != null and bird_lane.curve != null and bird_lane.curve.get_point_count() >= 2 and bird_lane.curve.get_baked_length() > 0.0, "BirdLane has a usable authored flight path")
	if bird_lane == null:
		_finish()
		return
	var cat_spots := _cat_spots()
	var sunny_unsheltered: Array[Marker2D] = []
	var sheltered: Array[Marker2D] = []
	for spot in cat_spots:
		check(spot.has_meta("sunny") and spot.has_meta("sheltered"), "%s declares sunny and sheltered placement traits" % spot.name)
		if bool(spot.get_meta("sunny", false)) and not bool(spot.get_meta("sheltered", true)):
			sunny_unsheltered.append(spot)
		if bool(spot.get_meta("sheltered", false)):
			sheltered.append(spot)
	check(not sunny_unsheltered.is_empty(), "scene authors a sunny, exposed cat place")
	check(not sheltered.is_empty(), "scene authors a sheltered rain cat place")

	var capabilities: Dictionary = life.get_capabilities()
	for kind in ["birds", "cat", "squirrel", "fish"]:
		check(capabilities.has(kind), "capabilities report %s" % kind)
	check(bool(capabilities.get("birds", false)) and bool(capabilities.get("cat", false)), "authored lane and cat places enable only the selected lives")
	check(not bool(capabilities.get("squirrel", true)) and not bool(capabilities.get("fish", true)), "Tingyu does not enable squirrel or fish")
	var config: Dictionary = life.config
	var bird_config: Dictionary = config.get("birds", {})
	var cat_config: Dictionary = config.get("cat", {})
	var squirrel_config: Dictionary = config.get("squirrel", {})
	var fish_config: Dictionary = config.get("fish", {})
	check(bool(bird_config.get("enabled", false)) and bool(cat_config.get("enabled", false)), "scene config enables birds and cat")
	check(not bool(squirrel_config.get("enabled", false)) and not bool(fish_config.get("enabled", false)), "scene config disables squirrel and fish")
	if not bool(capabilities.get("birds", false)) or not bool(capabilities.get("cat", false)) or config.is_empty():
		_finish()
		return

	_test_marker_refresh(bird_lane, cat_spots)
	_test_weather_gates_and_cat_places(sunny_unsheltered, sheltered)
	_test_seeded_schedule_and_busy_gate(capabilities)
	await _test_host_attention_and_quiet_cat()
	await _test_reset()
	await _test_cat_weather_retirement_fade()
	_test_static_dynamic()
	await _test_birds_under_busy_and_static()
	await _test_natural_cloudy_cat()

	_finish()


func _test_marker_refresh(bird_lane: Path2D, cat_spots: Array[Marker2D]) -> void:
	var lane_parent := bird_lane.get_parent()
	lane_parent.remove_child(bird_lane)
	life.refresh_capabilities()
	life.observe_environment()
	check(not bool(life.get_capabilities().get("birds", true)), "removing BirdLane removes the birds capability")
	check(not game.force_ambient_life("birds"), "controller cannot force birds without BirdLane")
	lane_parent.add_child(bird_lane)
	life.refresh_capabilities()
	life.observe_environment()
	check(bool(life.get_capabilities().get("birds", false)), "restoring BirdLane restores the birds capability")

	var removed_parents: Array[Node] = []
	for spot in cat_spots:
		removed_parents.append(spot.get_parent())
		spot.get_parent().remove_child(spot)
	life.refresh_capabilities()
	life.observe_environment()
	check(not bool(life.get_capabilities().get("cat", true)), "removing all CatSpot markers removes the cat capability")
	for i in cat_spots.size():
		removed_parents[i].add_child(cat_spots[i])
	life.refresh_capabilities()
	life.observe_environment()
	check(bool(life.get_capabilities().get("cat", false)), "restoring CatSpot markers restores the cat capability")


func _test_weather_gates_and_cat_places(sunny_unsheltered: Array[Marker2D], sheltered: Array[Marker2D]) -> void:
	var wu_index := _time_index("午时")
	check(wu_index >= 0, "sunny cat fixture uses a real DemoState midday slot")
	if wu_index < 0:
		return

	_set_environment("clear", wu_index, true)
	life.reset()
	life.observe_environment()
	check(game.weather.presenter.time_profile_id == "wu", "clear cat fixture observes the sunny Wu profile")
	check(life.presenter.can_spawn("birds") and life.presenter.can_spawn("cat"), "clear weather permits birds and cat")
	var before_clear_force := _state_snapshot()
	check(game.force_ambient_life("birds"), "clear-weather bird force fixture is accepted")
	var forced_birds: Dictionary = life.presenter.get_active_events().get("birds", {})
	check(not forced_birds.is_empty() and bool(forced_birds.get("forced", false)), "forced bird fixture is explicitly marked forced")
	check(_state_snapshot() == before_clear_force, "clear forced bird presentation leaves every DemoState field unchanged")

	life.reset()
	life.observe_environment()
	var before_sunny_cat := _state_snapshot()
	check(game.force_ambient_life("cat"), "clear-weather cat force fixture is accepted")
	check(life.cat_spot != null and sunny_unsheltered.has(life.cat_spot), "clear sunny cat selects an authored sunny, unsheltered place")
	var forced_cat: Dictionary = life.presenter.get_active_events().get("cat", {})
	check(not forced_cat.is_empty() and bool(forced_cat.get("forced", false)), "forced cat fixture is explicitly marked forced")
	life.advance(0.25)
	check(_state_snapshot() == before_sunny_cat, "clear cat placement and motion leave every DemoState field unchanged")

	_set_environment("cloudy", wu_index, true)
	life.reset()
	life.observe_environment()
	check(life.presenter.can_spawn("birds") and life.presenter.can_spawn("cat"), "cloudy weather permits the configured bird and cat opportunities")

	_set_environment("light_rain", wu_index, true)
	life.reset()
	life.observe_environment()
	check(not life.presenter.can_spawn("birds") and not game.force_ambient_life("birds"), "rain suppresses birds and rejects the force fixture")
	var before_rain_cat := _state_snapshot()
	check(game.force_ambient_life("cat"), "rain permits the cat because a sheltered place is authored")
	check(life.cat_spot != null and sheltered.has(life.cat_spot) and bool(life.cat_spot.get_meta("sheltered", false)), "rain cat selects only a sheltered place")
	life.advance(0.25)
	check(_state_snapshot() == before_rain_cat, "rain cat placement and motion leave every DemoState field unchanged")


func _test_seeded_schedule_and_busy_gate(capabilities: Dictionary) -> void:
	var seed := int(life.config.get("seed", -1))
	check(seed >= 0, "Tingyu ambient config declares a deterministic seed")
	if seed < 0:
		return

	var bird_settings: Dictionary = life.config.get("birds", {})
	var bird_chances: Dictionary = bird_settings.get("weather_chance", {})
	check(float(bird_chances.get("clear", 0.0)) > float(bird_chances.get("cloudy", 0.0)) and float(bird_chances.get("cloudy", 0.0)) > 0.0, "bird config gives cloudy a lower nonzero chance than clear")
	check(is_equal_approx(float(bird_chances.get("light_rain", -1.0)), 0.0), "bird config disables automatic rain events")
	var schedule_config := _fast_bird_config(life.config)
	var clear_requests := _simulate_birds(schedule_config, capabilities, "clear", seed)
	var cloudy_requests := _simulate_birds(schedule_config, capabilities, "cloudy", seed)
	var rain_requests := _simulate_birds(schedule_config, capabilities, "light_rain", seed)
	check(clear_requests.size() > cloudy_requests.size(), "fixed-seed interval window yields fewer cloudy than clear bird events")
	check(rain_requests.is_empty(), "fixed-seed rain interval window yields zero automatic bird events")
	var automatic_records_are_unforced := true
	for event in clear_requests + cloudy_requests + rain_requests:
		automatic_records_are_unforced = automatic_records_are_unforced and not bool(event.get("forced", true))
	check(automatic_records_are_unforced, "automatic scheduler output is marked non-forced")
	var clear_replay := _simulate_birds(schedule_config, capabilities, "clear", seed)
	check(clear_requests == clear_replay, "replaying the same seed reproduces the complete event sequence")
	check(life.config == initial_config, "scheduler fixtures do not mutate the adapter config")
	var scene_sequence := _simulate_scene_events(life.config, capabilities, "clear", seed)
	var scene_replay := _simulate_scene_events(life.config, capabilities, "clear", seed)
	check(not scene_sequence.is_empty() and scene_sequence == scene_replay, "same scene seed reproduces a nonempty cat/bird event sequence")

	var busy_presenter = Presenter.new()
	busy_presenter.configure(life.config, seed)
	busy_presenter.observe(_environment("clear"), capabilities)
	var state_before_busy_schedule := _state_snapshot()
	var busy_requests: Array = []
	for _step in 960:
		busy_requests.append_array(busy_presenter.advance(0.25, true))
	check(busy_requests.is_empty() and busy_presenter.get_active_events().is_empty(), "busy foreground suppresses every new automatic event in the fixed window")
	check(_state_snapshot() == state_before_busy_schedule, "busy scheduler fixture preserves every DemoState field")

	life.reset()
	_set_environment("clear", 0, true)
	life.observe_environment()
	var automatic_event: Dictionary = {}
	for _step in 960:
		life.advance(0.25)
		var active: Dictionary = life.presenter.get_active_events()
		for kind in active:
			if not bool(active[kind].get("forced", true)):
				automatic_event = active[kind]
				break
		if not automatic_event.is_empty():
			break
	check(not automatic_event.is_empty(), "fixed seed and simulated deltas produce an automatic Tingyu event")
	if not automatic_event.is_empty():
		check(not bool(automatic_event.get("forced", true)), "automatic Tingyu event is distinguishable from force fixtures")
		check(int(automatic_event.get("serial", 0)) > 0, "automatic event uses the nonnegative scheduler serial stream")
	check(_state_snapshot() == initial_state, "automatic scheduling preserves every DemoState field")


func _test_host_attention_and_quiet_cat() -> void:
	_set_environment("clear", 0, true)
	await _press_reset()
	life.reset()
	game.weather.set_dynamic(true)
	game.weather.set_weather("clear", false)
	life.observe_environment()
	game.set_process(true)
	game.weather.set_process(false)
	life.presenter.next_due["cat"] = float(life.presenter.elapsed) + 0.05
	game.train_button.emit_signal("pressed")
	check(game.busy and game.foreground_attention_busy(), "real cultivation animation marks foreground attention busy")
	var training_state := _state_snapshot()
	await create_timer(0.15).timeout
	check(game.busy, "real training tween remains Busy while its first schedule deadline passes")
	check(life.presenter.get_active_events().is_empty(), "host busy getter suppresses automatic events during cultivation animation")
	check(_state_snapshot() == training_state, "cultivation-busy ambient advancement preserves every gameplay field")
	await _wait_for_train_completion()
	check(not game.busy and not game.foreground_attention_busy(), "real training tween clears Busy through its natural completion")
	var post_train_state := _state_snapshot()
	var resumed_event := await _wait_for_realtime_automatic_cat()
	check(not resumed_event.is_empty() and not bool(resumed_event.get("forced", true)), "Dynamic scheduler can start an automatic cat after real training completes")
	check(_state_snapshot() == post_train_state, "post-training automatic ambient scheduling preserves every gameplay field")
	game.set_process(false)

	_set_environment("clear", 0, true)
	life.reset()
	life.observe_environment()
	check(not game.foreground_attention_busy(), "training busy gate is clear before the dialogue fixture")
	game._ask()
	check(game.state.dialogue_open and game.foreground_attention_busy(), "real dialogue state is observed by the host busy getter")
	var busy_dialogue_state := _state_snapshot()
	for _step in 960:
		life.advance(0.25)
	check(life.presenter.get_active_events().is_empty(), "host busy getter suppresses automatic events during dialogue")
	check(_state_snapshot() == busy_dialogue_state, "dialogue-gated scheduler preserves every gameplay field")
	game._cancel()
	check(not game.foreground_attention_busy(), "cancel clears the dialogue attention gate")

	life.reset()
	check(game.force_ambient_life("cat"), "busy-pose fixture starts an active cat event")
	var cat_root := life.visual_nodes.get("cat") as Node2D
	var cat_sprite := cat_root.get_child(0) as Sprite2D if cat_root != null and cat_root.get_child_count() > 0 else null
	check(cat_sprite != null and cat_sprite.texture is AtlasTexture, "Tingyu cat visual exposes its authored atlas sprite")
	if cat_sprite == null or not (cat_sprite.texture is AtlasTexture):
		return

	game._ask()
	check(game.state.dialogue_open and game.foreground_attention_busy(), "real mentor dialogue marks foreground attention busy")
	var dialogue_state := _state_snapshot()
	life.advance(7.0)
	check(life.presenter.get_active_events().has("cat") and _cat_pose_index(cat_sprite) == 0, "active cat stays on its resting frame during dialogue")
	check(_state_snapshot() == dialogue_state, "dialogue busy advancement preserves every gameplay field")

	game._choose("breathing")
	check(game.awaiting_continue and game.foreground_attention_busy(), "real choice-result wait is observed by the host busy getter")
	var choice_state := _state_snapshot()
	life.advance(0.25)
	check(life.presenter.get_active_events().has("cat") and _cat_pose_index(cat_sprite) == 0, "cat remains resting while the choice result awaits Continue")
	check(_state_snapshot() == choice_state, "choice-result ambient advancement preserves every gameplay field")
	game._continue()
	check(not game.foreground_attention_busy(), "Continue clears the dialogue attention gate")

	life.reset()
	game._open_tea()
	game.tea_accept.emit_signal("pressed")
	await process_frame
	check(game.state.tea_active and game.state.tea_accepted and game.foreground_attention_busy(), "accepted Tea interaction is observed by the host busy getter")
	game.tea_hotspots["tea.cup_first"].emit_signal("pressed")
	await process_frame
	check(game.object_popover.visible and game.foreground_attention_busy(), "real Tea object inspection remains foreground-busy")
	var tea_state := _state_snapshot()
	game.tea_hotspots["tea.cup_second"].emit_signal("pressed")
	await process_frame
	check(game.state.tea_stage_complete, "real second-cup inspection completes the first Tea stage")
	game.tea_paths["tea.path_old_courtyard"].emit_signal("pressed")
	await process_frame
	game.tea_hotspots["tea.household"].emit_signal("pressed")
	await process_frame
	game.tea_hotspots["tea.ledger"].emit_signal("pressed")
	await process_frame
	check(game.state.tea_c_complete, "real household and ledger inspections complete the courtyard stage")
	var close_tea_view := InputEventKey.new()
	close_tea_view.keycode = KEY_ESCAPE
	close_tea_view.pressed = true
	game._unhandled_key_input(close_tea_view)
	await process_frame
	game.tea_paths["tea.story_next"].emit_signal("pressed")
	await process_frame
	check(game.state.tea_story_stage == 1, "real story route enters the first narrative stage")
	game.tea_hotspots["tea.medical_early"].emit_signal("pressed")
	await process_frame
	var page_button: Button = game.object_popover.buttons.get("page:%d" % game.state.tea_story_token)
	check(page_button != null, "real medical record exposes its token-bound next-page action")
	if page_button != null:
		page_button.emit_signal("pressed")
		await process_frame
		await process_frame
	check(game.state.tea_story_object == "tea.medical_early" and game.state.tea_story_page == 1 and game.state.tea_story_seen.has("tea.medical_early"), "real medical narrative action records an open past-reading state")
	check(game.tea_memory.visible and game.foreground_attention_busy(), "open Tea past reading remains foreground-busy")
	tea_state = _state_snapshot()
	for _attempt in 12:
		life.presenter.next_due["cat"] = float(life.presenter.elapsed) + 0.01
		life.advance(0.02)
	check(life.presenter.get_active_events().is_empty(), "Tea narrative Busy suppresses imminent automatic cat opportunities")
	check(_state_snapshot() == tea_state, "Tea narrative ambient advancement preserves every gameplay field")


func _test_cat_weather_retirement_fade() -> void:
	var wu_index := _time_index("午时")
	check(wu_index >= 0, "rain retirement fixture uses a real DemoState midday slot")
	if wu_index < 0:
		return
	await _press_reset()
	_set_environment("clear", wu_index, true)
	life.reset()
	var state_before := _state_snapshot()
	check(game.force_ambient_life("cat"), "sunny rain-retirement fixture starts a cat")
	life.advance(1.25)
	var cat_root := life.visual_nodes.get("cat") as Node2D
	var original_spot: Marker2D = life.cat_spot
	var original_event: Dictionary = life.presenter.get_active_events().get("cat", {})
	var serial := int(original_event.get("serial", 0))
	var alpha_before_rain := float(cat_root.modulate.a) if cat_root != null else -1.0
	check(cat_root != null and cat_root.visible and original_spot != null and sunny_unsheltered_spot(original_spot), "sunny cat is fully placed before the weather transition")
	check(alpha_before_rain > 0.0 and is_equal_approx(alpha_before_rain, float(life.config.visuals.cat_alpha)), "rain fixture begins after cat fade-in has settled")
	game.weather.set_weather("light_rain", true)
	life.observe_environment()
	check(cat_root.visible and life.cat_spot == original_spot, "rain transition keeps the existing exposed cat visible at its original spot")
	check(is_equal_approx(float(cat_root.modulate.a), alpha_before_rain), "rain transition preserves existing cat alpha at fade start")
	var rain_state := _state_snapshot()
	life.advance(0.4)
	var alpha_fade_mid := float(cat_root.modulate.a)
	check(cat_root.visible and life.cat_spot == original_spot and alpha_fade_mid > 0.0 and alpha_fade_mid < alpha_before_rain, "rain retirement fades the exposed cat in place")
	check(_state_snapshot() == rain_state, "rain fade-in-progress preserves every gameplay field")
	game.weather.set_dynamic(false)
	life.observe_environment()
	var alpha_static := float(cat_root.modulate.a)
	check(cat_root.visible and is_equal_approx(alpha_static, alpha_fade_mid), "Static preserves partial rain-fade visibility and alpha")
	life.advance(0.6)
	check(is_equal_approx(float(cat_root.modulate.a), alpha_static), "Static freezes the partial rain-retirement fade")
	game.weather.set_dynamic(true)
	life.observe_environment()
	check(is_equal_approx(float(cat_root.modulate.a), alpha_static), "Dynamic resumes the rain fade without an alpha jump")
	life.advance(0.2)
	check(cat_root.visible and life.cat_spot == original_spot and float(cat_root.modulate.a) < alpha_static, "Dynamic continues the same cat's fade-out in place")
	life.advance(0.7)
	check(not cat_root.visible and life.cat_spot == original_spot, "completed rain retirement hides the cat without teleporting it")
	var retired_event: Dictionary = life.presenter.get_active_events().get("cat", {})
	check(not retired_event.is_empty() and int(retired_event.get("serial", 0)) == serial, "retired cat remains latched to its original event serial")
	life.advance(0.25)
	check(not cat_root.visible and int(life.presenter.get_active_events().get("cat", {}).get("serial", 0)) == serial, "same cat event stays retired until its serial changes")
	game.weather.set_weather("clear", false)
	life.observe_environment()
	check(not cat_root.visible and life.cat_spot == original_spot, "retired sunny cat stays hidden when weather returns to clear")
	check(int(life.presenter.get_active_events().get("cat", {}).get("serial", 0)) == serial, "dry weather does not replace the retired event serial")
	check(game.force_ambient_life("cat"), "a new cat event can start after the retired encounter")
	var replacement_event: Dictionary = life.presenter.get_active_events().get("cat", {})
	check(int(replacement_event.get("serial", serial)) != serial and cat_root.visible and life.cat_spot != null, "new cat serial clears retirement and becomes visible normally")
	check(_state_snapshot() == rain_state, "complete rain retirement preserves every gameplay field")


func sunny_unsheltered_spot(spot: Marker2D) -> bool:
	return bool(spot.get_meta("sunny", false)) and not bool(spot.get_meta("sheltered", true))


func _test_birds_under_busy_and_static() -> void:
	await _press_reset()
	_set_environment("clear", 0, true)
	life.reset()
	life.observe_environment()
	check(game.force_ambient_life("birds"), "bird completion fixture starts a real distant flight")
	var bird_root := life.visual_nodes.get("birds") as Node2D
	var flight: Dictionary = life.presenter.get_active_events().get("birds", {})
	var flight_duration := float(flight.get("duration", 0.0))
	check(bird_root != null and bird_root.visible and flight_duration > 0.0, "forced bird event is visible and has an authored flight duration")
	game.mentor_button.emit_signal("pressed")
	await process_frame
	check(game.state.dialogue_open and game.foreground_attention_busy(), "real mentor dialogue is Busy during the bird flight")
	var busy_state := _state_snapshot()
	var flight_serial := int(flight.get("serial", 0))
	var start_position := bird_root.position
	var start_alpha := float(bird_root.modulate.a)
	life.advance(0.5)
	var progressed_flight: Dictionary = life.presenter.get_active_events().get("birds", {})
	check(bird_root.visible and int(progressed_flight.get("serial", 0)) == flight_serial and bird_root.position != start_position and float(bird_root.modulate.a) > start_alpha, "in-flight bird visibly progresses during mentor Busy")
	life.advance(maxf(0.0, flight_duration - 0.5) + 0.25)
	check(life.presenter.get_active_events().is_empty() and not bird_root.visible, "an in-flight bird completes during mentor Busy")
	check(_state_snapshot() == busy_state, "bird completion during dialogue preserves every gameplay field")
	game._cancel()
	await _press_reset()
	_set_environment("clear", 0, true)
	life.reset()
	life.observe_environment()
	check(game.force_ambient_life("birds"), "Static fixture starts a second in-flight bird")
	life.advance(0.5)
	check(bird_root.visible, "second bird is visible before Static")
	game.weather.set_dynamic(false)
	life.observe_environment()
	check(life.presenter.get_active_events().is_empty() and not bird_root.visible, "Static clears an active flight immediately")
	game.weather.set_dynamic(true)
	life.observe_environment()
	life.advance(0.25)
	check(life.presenter.get_active_events().is_empty() and not bird_root.visible, "Dynamic does not resurrect a bird cleared by Static")


func _test_natural_cloudy_cat() -> void:
	await _press_reset()
	game.set_process(false)
	game.weather.set_process(false)
	check(game.weather.presenter.time_profile_id == "mao" and game.weather.presenter.weather_id == "cloudy", "natural cat fixture starts in default Dynamic cloudy Mao")
	life.reset()
	life.observe_environment()
	var first_state := _state_snapshot()
	var first_events := _simulate_until_cloudy_cat()
	var first_cat: Dictionary = life.presenter.get_active_events().get("cat", {})
	check(not first_cat.is_empty() and not bool(first_cat.get("forced", true)) and float(life.presenter.elapsed) <= 75.0, "default cloudy schedule produces an unforced cat within 75 simulated seconds")
	check(first_events.size() > 0 and _state_snapshot() == first_state, "natural cloudy cat simulation preserves the complete DemoState snapshot")
	await _press_reset()
	var replay_state := _state_snapshot()
	check(life.presenter.get_active_events().is_empty() and life.presenter.next_due == initial_schedule, "real reset clears the cat and restores the initial seeded deadlines")
	var replay_events := _simulate_until_cloudy_cat()
	var replay_cat: Dictionary = life.presenter.get_active_events().get("cat", {})
	check(replay_events == first_events and not replay_cat.is_empty() and not bool(replay_cat.get("forced", true)), "real reset replays the same unforced cloudy cat sequence")
	check(_state_snapshot() == replay_state, "replayed cloudy schedule preserves the complete DemoState snapshot")


func _simulate_until_cloudy_cat() -> Array:
	var events: Array = []
	for _step in 300:
		events.append_array(life.advance(0.25))
		if life.presenter.get_active_events().has("cat"):
			break
	return events


func _wait_for_train_completion() -> void:
	for _attempt in 40:
		if not game.busy:
			break
		await create_timer(0.025).timeout
	check(not game.busy, "real training tween reaches its natural idle state")


func _wait_for_realtime_automatic_cat() -> Dictionary:
	for _attempt in 40:
		var active: Dictionary = life.presenter.get_active_events()
		if active.has("cat") and not bool(active.cat.get("forced", true)):
			return active.cat
		life.presenter.next_due["cat"] = float(life.presenter.elapsed) + 0.01
		await create_timer(0.05).timeout
	return {}


func _test_static_dynamic() -> void:
	_set_environment("clear", 0, true)
	life.reset()
	life.observe_environment()
	var state_before_static := _state_snapshot()
	check(game.force_ambient_life("cat"), "static fixture starts a resting cat")
	var cat_root := life.visual_nodes.get("cat") as Node2D
	var cat_sprite := cat_root.get_child(0) as Sprite2D if cat_root != null and cat_root.get_child_count() > 0 else null
	var bird_root := life.visual_nodes.get("birds") as Node2D
	check(cat_sprite != null and bird_root != null, "Static/Dynamic fixture exposes cat and bird visual roots")
	if cat_sprite == null or bird_root == null:
		return
	life.advance(0.25)
	var fade_in_alpha := float(cat_root.modulate.a)
	check(fade_in_alpha > 0.0 and fade_in_alpha < float(life.config.visuals.cat_alpha), "Dynamic cat enters Static with a partial fade-in alpha")

	game.weather.set_dynamic(false)
	life.observe_environment()
	check(not game.force_ambient_life("birds"), "Static rejects a new bird event")
	var static_elapsed := float(life.presenter.elapsed)
	var static_deadlines: Dictionary = life.presenter.next_due.duplicate(true)
	check(is_equal_approx(float(cat_root.modulate.a), fade_in_alpha), "switching to Static preserves the current fade-in alpha")
	life.advance(5.0)
	check(is_equal_approx(float(life.presenter.elapsed), static_elapsed), "Static freezes the ambient schedule clock")
	check(not life.presenter.auto_enabled and life.presenter.next_due == static_deadlines, "Static preserves the paused fixture deadlines")
	check(not bird_root.visible, "Static hides the bird pass")
	check(life.presenter.get_active_events().has("cat") and cat_root.visible and _cat_pose_index(cat_sprite) == 0, "Static preserves the visible cat on its resting frame")
	check(is_equal_approx(float(cat_root.modulate.a), fade_in_alpha), "Static freezes the partial cat fade-in")

	game.weather.set_dynamic(true)
	life.observe_environment()
	check(is_equal_approx(float(cat_root.modulate.a), fade_in_alpha), "Dynamic resumes from the same partial cat alpha")
	life.advance(0.25)
	check(float(cat_root.modulate.a) > fade_in_alpha, "Dynamic continues the cat fade-in from the frozen elapsed time")
	var cat_event: Dictionary = life.presenter.get_active_events().get("cat", {})
	var cat_duration := float(cat_event.get("duration", 0.0))
	life.advance(maxf(0.0, cat_duration - float(life.presenter.elapsed) - 0.4))
	var lifetime_fade_alpha := float(cat_root.modulate.a)
	check(cat_root.visible and lifetime_fade_alpha > 0.0 and lifetime_fade_alpha < float(life.config.visuals.cat_alpha), "cat reaches a partial natural lifetime fade before Static")
	game.weather.set_dynamic(false)
	life.observe_environment()
	var lifetime_static_elapsed := float(life.presenter.elapsed)
	check(is_equal_approx(float(cat_root.modulate.a), lifetime_fade_alpha), "Static begins the natural lifetime fade with unchanged alpha")
	life.advance(0.3)
	check(is_equal_approx(float(life.presenter.elapsed), lifetime_static_elapsed) and is_equal_approx(float(cat_root.modulate.a), lifetime_fade_alpha), "Static freezes natural lifetime fade elapsed time and alpha")
	game.weather.set_dynamic(true)
	life.observe_environment()
	check(is_equal_approx(float(cat_root.modulate.a), lifetime_fade_alpha), "Dynamic resumes natural lifetime fade without an alpha jump")
	life.advance(0.2)
	check(cat_root.visible and float(cat_root.modulate.a) < lifetime_fade_alpha, "Dynamic continues the natural lifetime fade-out")
	life.advance(0.3)
	check(not cat_root.visible and life.presenter.get_active_events().is_empty(), "natural cat event expires after its resumed fade-out")
	game.resume_ambient_life_auto()
	check(life.presenter.auto_enabled and life.presenter.get_active_events().is_empty(), "resume clears the force fixture and re-enables the automatic scheduler")
	var dynamic_elapsed := float(life.presenter.elapsed)
	life.advance(0.25)
	check(life.presenter.auto_enabled and float(life.presenter.elapsed) > dynamic_elapsed, "Dynamic resumes the automatic scheduler clock")
	check(_state_snapshot() == state_before_static, "Static/Dynamic presentation preserves every DemoState field")


func _test_reset() -> void:
	var before_reset := _state_snapshot()
	check(before_reset != initial_state, "dialogue and Tea fixtures changed state before the reset check")
	await _press_reset()
	var after_reset := _state_snapshot()
	var reset_gameplay := after_reset.duplicate(true)
	var initial_gameplay := initial_state.duplicate(true)
	# These counters invalidate stale async Tea callbacks, so reset must advance
	# them instead of reusing the initial values. All other state is reset exactly.
	for token in ["tea_session", "tea_story_token"]:
		reset_gameplay.erase(token)
		initial_gameplay.erase(token)
	check(reset_gameplay == initial_gameplay, "real reset restores all gameplay properties while preserving monotonic Tea invalidation tokens")
	check(int(after_reset.get("tea_session", 0)) > int(initial_state.get("tea_session", 0)) and int(after_reset.get("tea_story_token", 0)) > int(initial_state.get("tea_story_token", 0)), "reset advances stale-callback invalidation tokens")
	check(life.presenter.enabled and life.presenter.auto_enabled and is_zero_approx(float(life.presenter.elapsed)) and life.presenter.get_active_events().is_empty(), "reset restores the enabled automatic schedule with no active events")
	check(life.presenter.next_due == initial_schedule, "reset restores the initial seeded schedule deadlines")
	check(life.config == initial_config, "reset preserves the scene ambient config")
	check(game.weather.enabled and game.weather.presenter.time_profile_id == "mao" and game.weather.presenter.weather_id == "cloudy", "reset restores Dynamic cloudy Mao environment")


func _press_reset() -> void:
	var button := _find_button_by_text(game, "重新开始")
	check(button != null, "Tingyu exposes its real reset button")
	if button != null:
		button.emit_signal("pressed")
	await process_frame


func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null


func _set_environment(weather_id: String, time_index: int, dynamic: bool) -> void:
	game.weather.set_dynamic(dynamic)
	game.weather.set_time_index(time_index, false)
	game.weather.set_weather(weather_id, false)
	game.weather.presenter.finish_transition()
	life.observe_environment()


func _time_index(label: String) -> int:
	var times: Array = game.state.rules.get("times", [])
	return times.find(label)


func _cat_spots() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	for child in marker_root.get_children():
		if child is Marker2D and str(child.name).begins_with("CatSpot_"):
			result.append(child)
	return result


func _fast_bird_config(source: Dictionary) -> Dictionary:
	var config := source.duplicate(true)
	config["squirrel"] = {"enabled": false}
	config["cat"] = {"enabled": false}
	config["fish"] = {"enabled": false}
	var birds: Dictionary = config.get("birds", {}).duplicate(true)
	birds["enabled"] = true
	birds["interval_min"] = 1.0
	birds["interval_max"] = 1.0
	birds["duration_min"] = 0.0
	birds["duration_max"] = 0.0
	birds["count_min"] = 1
	birds["count_max"] = 1
	config["birds"] = birds
	return config


func _simulate_birds(config: Dictionary, capabilities: Dictionary, weather_id: String, seed: int) -> Array:
	var presenter = Presenter.new()
	presenter.configure(config, seed)
	presenter.observe(_environment(weather_id), capabilities)
	var events: Array = []
	for _step in 480:
		events.append_array(presenter.advance(0.5))
	return events


func _simulate_scene_events(config: Dictionary, capabilities: Dictionary, weather_id: String, seed: int) -> Array:
	var presenter = Presenter.new()
	presenter.configure(config, seed)
	presenter.observe(_environment(weather_id), capabilities)
	var events: Array = []
	for _step in 960:
		events.append_array(presenter.advance(0.25))
	return events


func _environment(weather_id: String) -> Dictionary:
	return {
		"time_profile_id": "mao",
		"weather_id": weather_id,
		"night_preview": false,
		"dynamic_enabled": true,
	}


func _state_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	if game == null or game.state == null:
		return snapshot
	for property in game.state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = game.state.get(property.name)
		snapshot[str(property.name)] = _deep_copy(value)
	snapshot["time_text"] = game.state.time_text()
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


func _cat_pose_index(sprite: Sprite2D) -> int:
	var texture := sprite.texture as AtlasTexture
	return int(texture.get_meta("pose_index", -1)) if texture != null else -1


func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)


func _finish() -> void:
	if is_instance_valid(game):
		game.set_process(false)
		game.queue_free()
		await process_frame
	var report := {"checks": checks, "failure_count": failures}
	print("TINGYU_AMBIENT_LIFE_TEST: %d checks, %d failures (%s)" % [checks.size(), failures, "PASS" if failures == 0 else "FAIL"])
	print(JSON.stringify(report, "  "))
	quit(0 if failures == 0 else 1)
