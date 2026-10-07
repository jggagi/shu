extends SceneTree

# Short windowed Compatibility capture of real Tingyu consumer paths.
const OUTPUT_DIR := "res://.local/qa/tingyu-ambient-life-v1"

var game: Control
var checks := 0
var failures := 0
var captures: Array[String] = []
var check_results: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 720)
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	check(DisplayServer.get_name().to_lower() != "headless", "capture uses an actual windowed display server")
	check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).to_lower().contains("compat"), "project render method is Compatibility")
	if failures > 0:
		_finish(output_path)
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "Tingyu main scene loads")
	if packed == null:
		_finish(output_path)
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	game.weather.motion_paused = true
	game.weather.set_process(false)
	game.weather.set_weather("clear", false)
	await _capture(output_path, "00_clear_base.png")

	check(game.force_ambient_life("cat"), "clear weather accepts a forced cat encounter")
	game.ambient_life.advance(1.25)
	await process_frame
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	check(cat_root.visible, "clear cat appears in the Tingyu foreground")
	check(game.ambient_life.cat_spot != null and game.ambient_life.cat_spot.name == "CatSpot_SunnyThreshold", "clear cat chooses the authored sunny threshold")
	await _capture(output_path, "01_clear_cat.png")

	game.weather.set_weather("light_rain", false)
	check(game.force_ambient_life("cat"), "rain accepts the sheltered cat encounter")
	game.ambient_life.advance(1.25)
	await process_frame
	check(cat_root.visible, "rain cat remains visible under shelter")
	check(game.ambient_life.cat_spot != null and game.ambient_life.cat_spot.name == "CatSpot_Eave", "rain cat uses the authored eave spot")
	await _capture(output_path, "02_rain_cat.png")

	game.weather.set_weather("clear", false)
	check(game.force_ambient_life("birds"), "clear weather accepts distant birds")
	game.ambient_life.advance(1.5)
	await process_frame
	var birds_root: Node2D = game.ambient_life.visual_nodes.birds
	check(birds_root.visible, "birds appear in the window sky")
	var visible_birds := 0
	for bird in birds_root.get_children():
		visible_birds += int((bird as Sprite2D).visible)
	check(visible_birds > 0, "at least one bird sprite is rendered")
	await _capture(output_path, "03_birds.png")

	# Start a fresh cat, then open the real mentor dialogue. The active event may
	# remain, but foreground attention keeps its pose asleep.
	game.set_ambient_life_enabled(true)
	game.ambient_life.reset()
	game.weather.set_weather("clear", false)
	check(game.force_ambient_life("cat"), "busy-state fixture starts a cat")
	game.ambient_life.advance(1.25)
	game.mentor_button.emit_signal("pressed")
	await process_frame
	await process_frame
	check(game.foreground_attention_busy(), "real mentor choice screen marks foreground attention busy")
	check(cat_root.visible and _cat_pose() == 0, "cat sleeps during mentor choices")
	await _capture(output_path, "04_dialogue_busy.png")
	game.choices[2].emit_signal("pressed")
	await process_frame

	# Follow the real Tea entry and object-selection buttons. The original
	# cultivation scene is hidden but remains the cat's only visual parent.
	game.tea_entry.emit_signal("pressed")
	await process_frame
	game.tea_accept.emit_signal("pressed")
	await process_frame
	game.tea_hotspots["tea.cup_first"].emit_signal("pressed")
	await process_frame
	check(game.state.tea_active and game.state.tea_accepted and game.object_popover.visible, "real Tea object flow is active")
	check(not game.cultivation_scene.visible and game.tea_scene.visible, "Tea scene switch hides Tingyu scene")
	check(cat_root.get_parent() == game.foreground_root and not cat_root.is_visible_in_tree(), "ambient cat stays inside its hidden Tingyu foreground during Tea")
	await _capture(output_path, "05_tea_busy.png")
	game._tea_cancel()
	await process_frame

	# Static retains the cat but fixes it to frame zero; Dynamic advances the
	# same art into the established head-lift pose without changing game state.
	game.set_process(false)
	game._reset()
	game.weather.set_weather("clear", false)
	check(game.force_ambient_life("cat"), "static comparison starts a fresh cat")
	game.ambient_life.advance(1.25)
	check(is_equal_approx(float(game.ambient_life.visual_nodes.cat.modulate.a), float(game.ambient_life.config.visuals.cat_alpha)), "static comparison waits for the cat fade-in to settle")
	game.weather.set_dynamic(false)
	game.ambient_life.advance(0.25)
	check(cat_root.visible and _cat_pose() == 0, "Static preserves a visible still cat")
	await _capture(output_path, "06_static.png")
	game.weather.set_dynamic(true)
	game.ambient_life.advance(14.25) # Settled 1.25s + 14.25s = the head-lift window at 15.5s.
	check(cat_root.visible and _cat_pose() == 1, "Dynamic resumes the authored head-lift pose")
	await _capture(output_path, "07_dynamic_resume.png")

	await _capture_sunny_cat_rain_retirement(output_path)
	await _capture_static_dynamic_partial_alpha(output_path)
	await _capture_real_training_busy(output_path)
	await _capture_simulated_cloudy_auto_cat(output_path)

	# Dialog and reset snapshots ensure ambient events do not affect the game
	# state, and reset clears the event via the actual Reset button.
	var state_before_reset := _state_snapshot()
	game.ambient_life.advance(0.5)
	check(_state_snapshot() == state_before_reset, "ambient time leaves the full DemoState unchanged")
	game._reset()
	await process_frame
	check(game.ambient_life.presenter.get_active_events().is_empty(), "real reset clears active ambient events")
	check(not cat_root.visible and not birds_root.visible, "real reset hides ambient visuals")
	await _capture(output_path, "08_reset_cloudy.png")

	_finish(output_path)


func _cat_pose() -> int:
	var sprite := game.ambient_life.visual_nodes.cat.get_child(0) as Sprite2D
	return int(sprite.texture.get_meta("pose_index", 0))


func _state_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for property in game.state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = game.state.get(property.name)
		if value is Object:
			continue
		snapshot[str(property.name)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return snapshot


func _capture_sunny_cat_rain_retirement(output_path: String) -> void:
	game.set_process(false)
	game.weather.set_process(false)
	game._reset()
	game.weather.set_weather("clear", false)
	game.ambient_life.set_enabled(true)
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	var state_before := _state_snapshot()
	check(game.force_ambient_life("cat"), "rain-retirement render starts a forced sunny cat")
	game.ambient_life.advance(1.25)
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	var original_spot: Marker2D = game.ambient_life.cat_spot
	var original_event: Dictionary = game.ambient_life.presenter.get_active_events().get("cat", {})
	var serial := int(original_event.get("serial", 0))
	var start_alpha := float(cat_root.modulate.a)
	check(cat_root.visible and original_spot != null and original_spot.name == "CatSpot_SunnyThreshold", "sunny cat is visible at its authored threshold before rain")
	check(is_equal_approx(start_alpha, float(game.ambient_life.config.visuals.cat_alpha)), "sunny-cat rain fixture begins at full alpha")
	game.weather.set_weather("light_rain", true)
	game.ambient_life.observe_environment()
	check(cat_root.visible and game.ambient_life.cat_spot == original_spot, "rain fade begins with the cat visible at the same spot")
	check(is_equal_approx(float(cat_root.modulate.a), start_alpha), "rain fade begins without an alpha jump")
	check(_state_snapshot() == state_before, "rain fade start preserves every DemoState property")
	await _capture(output_path, "09_rain_fade_start.png")
	game.ambient_life.advance(0.6)
	game.weather.advance_environment(0.6)
	var mid_alpha := float(cat_root.modulate.a)
	check(cat_root.visible and game.ambient_life.cat_spot == original_spot and mid_alpha > 0.0 and mid_alpha < start_alpha, "rain fade midpoint keeps the cat in place at partial alpha")
	check(_state_snapshot() == state_before, "rain fade midpoint preserves every DemoState property")
	await _capture(output_path, "10_rain_fade_mid.png")
	game.ambient_life.advance(0.7)
	game.weather.advance_environment(0.7)
	var retired_event: Dictionary = game.ambient_life.presenter.get_active_events().get("cat", {})
	check(not cat_root.visible and game.ambient_life.cat_spot == original_spot, "rain fade end hides the cat without relocating its encounter")
	check(not retired_event.is_empty() and int(retired_event.get("serial", 0)) == serial, "rain-faded encounter remains latched to the same event serial")
	check(_state_snapshot() == state_before, "rain fade end preserves every DemoState property")
	await _capture(output_path, "11_rain_fade_end.png")


func _capture_static_dynamic_partial_alpha(output_path: String) -> void:
	game.set_process(false)
	game.weather.set_process(false)
	game._reset()
	game.weather.set_weather("clear", false)
	game.ambient_life.set_enabled(true)
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	var state_before := _state_snapshot()
	check(game.force_ambient_life("cat"), "partial-alpha fixture starts a forced cat")
	game.ambient_life.advance(0.25)
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	var dynamic_alpha := float(cat_root.modulate.a)
	check(cat_root.visible and dynamic_alpha > 0.0 and dynamic_alpha < float(game.ambient_life.config.visuals.cat_alpha), "Dynamic cat enters Static during fade-in at partial alpha")
	game.weather.set_dynamic(false)
	game.ambient_life.observe_environment()
	check(is_equal_approx(float(cat_root.modulate.a), dynamic_alpha), "switching to Static preserves partial alpha")
	game.ambient_life.advance(0.5)
	check(is_equal_approx(float(cat_root.modulate.a), dynamic_alpha), "Static freezes partial fade-in alpha")
	check(_state_snapshot() == state_before, "Static partial-alpha fixture preserves every DemoState property")
	await _capture(output_path, "12_static_partial_alpha.png")
	game.weather.set_dynamic(true)
	game.ambient_life.observe_environment()
	check(is_equal_approx(float(cat_root.modulate.a), dynamic_alpha), "Dynamic resumes with no alpha jump")
	game.ambient_life.advance(0.25)
	check(float(cat_root.modulate.a) > dynamic_alpha, "Dynamic continues the same cat fade-in")
	check(_state_snapshot() == state_before, "Dynamic partial-alpha fixture preserves every DemoState property")
	await _capture(output_path, "13_dynamic_partial_alpha_resume.png")


func _capture_real_training_busy(output_path: String) -> void:
	game.set_process(false)
	game.weather.set_process(false)
	game._reset()
	game.weather.set_dynamic(true)
	game.weather.set_time_index(0, false)
	game.weather.set_weather("cloudy", false)
	game.ambient_life.set_enabled(true)
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	game.ambient_life.presenter.next_due["cat"] = float(game.ambient_life.presenter.elapsed) + 0.01
	game.set_process(true)
	game.train_button.emit_signal("pressed")
	check(game.busy and game.foreground_attention_busy(), "real Train button starts the Busy animation before the first automatic deadline")
	var busy_state := _state_snapshot()
	await create_timer(0.12).timeout
	check(game.busy and game.ambient_life.presenter.get_active_events().is_empty(), "real training Busy suppresses the imminent automatic event")
	check(_state_snapshot() == busy_state, "ambient processing during real training Busy preserves every gameplay property")
	await _capture(output_path, "14_real_train_busy.png")
	await _wait_for_training_idle()
	check(not game.busy and not game.foreground_attention_busy(), "render fixture observes natural training tween completion")
	game.set_process(false)


func _capture_simulated_cloudy_auto_cat(output_path: String) -> void:
	game.set_process(false)
	game.weather.set_process(false)
	game._reset()
	game.weather.set_dynamic(true)
	game.weather.set_time_index(0, false)
	game.weather.set_weather("cloudy", false)
	game.ambient_life.set_enabled(true)
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	var state_before := _state_snapshot()
	var events: Array = []
	for _step in 300:
		events.append_array(game.ambient_life.advance(0.25))
		if game.ambient_life.presenter.get_active_events().has("cat"):
			break
	var cat_event: Dictionary = game.ambient_life.presenter.get_active_events().get("cat", {})
	check(not cat_event.is_empty() and not bool(cat_event.get("forced", true)) and float(game.ambient_life.presenter.elapsed) <= 75.0, "default cloudy adapter produces an unforced cat within 75 simulated seconds")
	if not cat_event.is_empty():
		game.ambient_life.advance(1.25)
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	check(cat_root.visible and game.ambient_life.cat_spot != null, "simulated automatic cloudy cat is visibly placed in the scene")
	check(events.size() > 0 and _state_snapshot() == state_before, "simulated automatic event sequence preserves every gameplay property")
	await _capture(output_path, "15_simulated_cloudy_auto_cat.png")
	await _capture_you_rain_sheltered_cat(output_path)


func _capture_you_rain_sheltered_cat(output_path: String) -> void:
	game.set_process(false)
	game.weather.set_process(false)
	game._reset()
	game.weather.set_time_index(5, false)
	game.weather.set_weather("light_rain", false)
	game.weather.presenter.finish_transition()
	game.ambient_life.set_enabled(true)
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	var state_before := _state_snapshot()
	check(game.weather.presenter.time_profile_id == "you" and game.weather.presenter.weather_id == "light_rain", "You sheltered-cat fixture settles the real You rain environment")
	check(game.force_ambient_life("cat"), "You rain capture starts a forced sheltered cat")
	game.ambient_life.advance(1.25)
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	var spot: Marker2D = game.ambient_life.cat_spot
	check(cat_root.visible and spot != null and spot.name == "CatSpot_Eave" and bool(spot.get_meta("sheltered", false)), "You rain cat remains visible at the authored sheltered eave")
	check(_state_snapshot() == state_before, "You rain sheltered-cat presentation preserves every DemoState property")
	await _capture(output_path, "16_you_rain_sheltered_cat.png")


func _wait_for_training_idle() -> void:
	for _attempt in 40:
		if not game.busy:
			break
		await create_timer(0.025).timeout
	check(not game.busy, "real training tween reaches its natural idle state")


func _capture(output_path: String, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output_path.path_join(filename)
	var error := image.save_png(path)
	check(error == OK and not image.is_empty(), "saved rendered frame %s" % filename)
	captures.append(filename)


func check(condition: bool, label: String) -> void:
	checks += 1
	check_results[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func _finish(output_path: String) -> void:
	var report := {"checks": checks, "failure_count": failures, "captures": captures, "check_results": check_results}
	var report_file := FileAccess.open(output_path.path_join("render-report.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "  ") + "\n")
	print("TINGYU_AMBIENT_LIFE_RENDER: %d checks, %d captures, %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)
