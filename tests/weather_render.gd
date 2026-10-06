extends SceneTree

# Windowed Compatibility render audit for the Tingyu environment-only slice.
const OUTPUT_DIR := "res://.local/qa/tingyu-environment-v1"
const WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const WEATHER_LABELS := {"clear": "晴", "cloudy": "多云", "light_rain": "小雨"}

var game: Control
var weather: Node
var output_path := ""
var requested_window_size := Vector2i(1152, 720)
var failures := 0
var checks := 0
var report: Dictionary = {"captures": [], "checks": [], "pixel_deltas": {}}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 720)
	OS.low_processor_usage_mode = false
	output_path = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)

	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var display_server := DisplayServer.get_name()
	report["renderer"] = {"method": renderer_method, "adapter": RenderingServer.get_video_adapter_name(), "display_server": display_server}
	check(renderer_method.to_lower().contains("compat"), "project uses the Compatibility renderer")
	check(display_server.to_lower() != "headless", "render audit has a real windowed display server")
	if display_server.to_lower() == "headless":
		await _finish()
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "Tingyu main scene loads for real rendering")
	if packed == null:
		await _finish()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	weather = game.weather
	check(weather.presenter != null, "rendered Tingyu scene exposes its shared presenter")
	if weather.presenter == null:
		await _finish()
		return

	weather.motion_paused = true
	weather.set_process(false)
	await create_timer(0.8).timeout # Let the deterministic noise texture finish before capture.
	await _press_reset()
	check(root.size == Vector2i(1152, 720), "first render size is 1152 by 720")

	# Capture all six real time profiles. Each new slot is reached with the
	# original rest button; the test never writes DemoState.time_index.
	var seen_profiles: Dictionary = {}
	var time_count: int = game.state.rules.times.size()
	check(time_count == 6, "actual cultivation clock exposes six time slots")
	for slot in range(time_count):
		var actual_index := int(game.state.time_index)
		var profile_id := str(weather.presenter.time_profile_id)
		check(actual_index == slot and not profile_id.is_empty(), "real rest path reaches time slot %d / %s" % [actual_index, profile_id])
		seen_profiles[profile_id] = true
		var image: Image = await _capture("time-%02d-%s.png" % [actual_index, profile_id])
		check(not image.is_empty(), "time profile %s has a captured rendered frame" % profile_id)
		if slot + 1 < time_count:
			await _rest_to_next_time()
	check(seen_profiles.size() == time_count, "actual rests capture all six distinct time profiles")

	# Weather comparisons share the actual current host time. The profile is
	# read from the runtime presenter, so this harness follows config changes.
	var comparison_time_index := int(game.state.time_index)
	var comparison_profile := str(weather.presenter.time_profile_id)
	var weather_images: Dictionary = {}
	for weather_id in WEATHER_IDS:
		check(weather.set_weather(weather_id, false), "runtime weather profile %s is selectable" % weather_id)
		check(int(game.state.time_index) == comparison_time_index and weather.presenter.time_profile_id == comparison_profile, "weather %s comparison keeps the same real cultivation time" % weather_id)
		check(weather.phase == WEATHER_LABELS[weather_id], "weather %s displays its Chinese phase label" % weather_id)
		weather_images[weather_id] = await _capture("weather-%s-at-time-%02d.png" % [weather_id, comparison_time_index])
	var weather_delta := _pixel_delta(weather_images["clear"], weather_images["cloudy"])
	report.pixel_deltas["clear_cloudy_same_time"] = weather_delta
	check(weather_delta > 0, "clear and cloudy render differently at the same real time")
	weather_delta = _pixel_delta(weather_images["cloudy"], weather_images["light_rain"])
	report.pixel_deltas["cloudy_rain_same_time"] = weather_delta
	check(weather_delta > 0, "cloudy and rain render differently at the same real time")

	# A real rest wraps from slot five to Mao. Capture t=0, midpoint and end
	# with scene processing disabled and deterministic manual presenter ticks.
	weather.set_weather("cloudy", false)
	var time_seconds := float(weather.presenter._time_seconds)
	game.rest_button.emit_signal("pressed")
	await process_frame
	check(int(game.state.time_index) == 0 and weather.presenter.time_profile_id == "mao", "real rest reaches Mao and starts its time transition")
	await _capture("time-transition-00-start.png")
	weather.advance_environment(time_seconds * 0.5)
	await _capture("time-transition-01-mid.png")
	weather.advance_environment(time_seconds * 0.5)
	await _capture("time-transition-02-end.png")
	check(weather.presenter.get_current_environment() == weather.presenter.get_target_environment(), "real time transition settles at its runtime profile")

	var weather_seconds := float(weather.presenter._weather_seconds)
	weather.set_weather("light_rain", true)
	await _capture("rain-transition-00-start.png")
	weather.advance_environment(weather_seconds * 0.5)
	await _capture("rain-transition-01-mid.png")
	weather.advance_environment(weather_seconds * 0.5)
	await _capture("rain-transition-02-end.png")
	var rain_visible: bool = not weather.rain_nodes.is_empty()
	for rain in weather.rain_nodes:
		rain_visible = rain_visible and rain.visible
	check(rain_visible, "settled rain remains visible in the rendered scene")

	# Compare real shader frames under one settled rainy profile. Dynamic advances
	# the shader clock; Static retains the same populated frame and freezes it.
	weather.motion_paused = false
	weather.set_dynamic(true)
	weather.advance_environment(1.0)
	var dynamic_a: Image = await _capture("rain-dynamic-a.png")
	weather.advance_environment(1.5)
	var dynamic_b: Image = await _capture("rain-dynamic-b.png")
	var dynamic_delta := _pixel_delta(dynamic_a, dynamic_b)
	report.pixel_deltas["rain_dynamic_motion"] = dynamic_delta
	check(dynamic_delta > 0, "Dynamic rain changes rendered pixels as the environment clock advances")
	weather.set_dynamic(false)
	var static_a: Image = await _capture("rain-static-a.png")
	var static_elapsed := float(weather.elapsed)
	weather.advance_environment(1.5)
	var static_b: Image = await _capture("rain-static-b.png")
	var static_delta := _pixel_delta(static_a, static_b)
	report.pixel_deltas["rain_static_frozen"] = static_delta
	check(static_delta == 0 and is_equal_approx(float(weather.elapsed), static_elapsed), "Static rain frame and motion clock stay frozen")
	var material_retained := true
	for item in weather.lit:
		material_retained = material_retained and item.art.material == item.weather
	for layer in weather.mist_layers:
		material_retained = material_retained and layer.material is ShaderMaterial
	for rain in weather.rain_nodes:
		material_retained = material_retained and rain.material is ShaderMaterial
	var mist_visible := false
	for layer in weather.mist_layers:
		mist_visible = mist_visible or layer.visible
	check(mist_visible, "Static render retains visible mist")
	check(material_retained, "Static render retains painted-world, mist, and rain materials")

	# Exercise original action and mentor controls before capturing the actual
	# dialogue and result panels. These are real Button signals and state paths.
	await _press_reset()
	await _capture("reset-mao-cloudy-1152.png")
	game.train_button.emit_signal("pressed")
	await _wait_until_idle()
	weather.advance_environment(float(weather.presenter._time_seconds))
	check(game.state.energy == 78 and game.state.cultivation == 12, "real training action is visible in the rendered audit")
	await _capture("training-result-1152.png")
	game.mentor_button.emit_signal("pressed")
	await _capture("mentor-dialogue-1152.png")
	game.choices[0].emit_signal("pressed")
	weather.advance_environment(float(weather.presenter._time_seconds))
	check(game.awaiting_continue, "breathing choice opens the real mentor result screen")
	await _capture("mentor-breathing-result-1152.png")
	game.continue_button.emit_signal("pressed")
	game.mentor_button.emit_signal("pressed")
	game.choices[1].emit_signal("pressed")
	weather.advance_environment(float(weather.presenter._time_seconds))
	check(game.awaiting_continue, "mountain choice opens the real mentor result screen")
	await _capture("mentor-mountain-result-1152.png")

	# Repeat the important readable panels at the smaller supported audit size.
	await _press_reset()
	requested_window_size = Vector2i(920, 575)
	root.size = requested_window_size
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	check(root.size.x == requested_window_size.x and absi(root.size.y - requested_window_size.y) <= 1, "macOS window reaches the requested 920 by 575 size within one-pixel rounding")
	var smaller_capture: Image = await _capture("reset-mao-cloudy-920.png")
	check(absi(smaller_capture.get_width() - requested_window_size.x) <= 2 and absi(smaller_capture.get_height() - requested_window_size.y) <= 1, "saved smaller render records the actual near-requested viewport size")
	game.rest_button.emit_signal("pressed")
	await process_frame
	weather.advance_environment(float(weather.presenter._time_seconds))
	await _capture("rested-time-920.png")
	game.mentor_button.emit_signal("pressed")
	await _capture("mentor-dialogue-920.png")
	game.choices[0].emit_signal("pressed")
	weather.advance_environment(float(weather.presenter._time_seconds))
	check(game.awaiting_continue, "smaller-window breathing choice reaches the real result screen")
	await _capture("mentor-breathing-result-920.png")
	await _press_reset()
	await _capture("reset-after-actions-920.png")

	await _finish()

func _rest_to_next_time() -> void:
	var old_index := int(game.state.time_index)
	game.rest_button.emit_signal("pressed")
	await process_frame
	check(int(game.state.time_index) == (old_index + 1) % game.state.rules.times.size(), "real rest advances exactly one host time slot")
	weather.advance_environment(float(weather.presenter._time_seconds))

func _press_reset() -> void:
	var reset_button := _find_button_by_text(game, "重新开始")
	check(reset_button != null, "real reset button is available for the render harness")
	if reset_button != null:
		reset_button.emit_signal("pressed")
	await process_frame
	weather.motion_paused = true
	weather.set_process(false)
	weather.advance_environment(0.0)

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
	check(not game.busy, "rendered training action reaches its settled UI state")

func _capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output_path.path_join(label)
	var result := image.save_png(path)
	check(result == OK, "saved real rendered frame %s" % label)
	report.captures.append({"name": label, "requested_window_size": [requested_window_size.x, requested_window_size.y], "window_size": [root.size.x, root.size.y], "image_size": [image.get_width(), image.get_height()]})
	return image

func _pixel_delta(first: Image, second: Image) -> int:
	if first.get_size() != second.get_size():
		return -1
	# Ignore HUD and dialogue pixels so weather changes must reach the painted world.
	var rect := Rect2i(int(first.get_width() * 0.18), int(first.get_height() * 0.08), int(first.get_width() * 0.48), int(first.get_height() * 0.48))
	var a := first.get_region(rect).get_data()
	var b := second.get_region(rect).get_data()
	var changed := 0
	for offset in range(0, a.size(), 4):
		if a[offset] != b[offset] or a[offset + 1] != b[offset + 1] or a[offset + 2] != b[offset + 2] or a[offset + 3] != b[offset + 3]:
			changed += 1
	return changed

func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + label)
	report.checks.append({"ok": condition, "label": label})
	if not condition:
		failures += 1

func _finish() -> void:
	report["check_count"] = checks
	report["failure_count"] = failures
	var report_file := FileAccess.open(output_path.path_join("render-report.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "  ") + "\n")
	print("TINGYU_WEATHER_RENDER: %d checks, %d captures, %d failures" % [checks, report.captures.size(), failures])
	quit(0 if failures == 0 else 1)
