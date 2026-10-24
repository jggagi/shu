extends SceneTree
## Actual Compatibility renderer and actor-clock integration checks for the staged scene.

var scene
var output := ""
var report := {"checks": [], "captures": [], "failures": 0}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	call_deferred("run")


func snapshot(instance: Object) -> PackedByteArray:
	var values: Dictionary = {}
	for property: Dictionary in instance.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = instance.get(property.name)
	return var_to_bytes(values)


func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	if not ok:
		report.failures += 1
		push_error(label)


func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name)) == OK, "saved " + name)
	report.captures.append({"file": name, "size": [image.get_width(), image.get_height()], "state": scene.qa_state()})
	return image


func character_region(image: Image) -> Image:
	var rect := Rect2i(int(image.get_width() * 0.56), int(image.get_height() * 0.33), int(image.get_width() * 0.30), int(image.get_height() * 0.44))
	return image.get_region(rect)


func neutral_match(left: Image, right: Image, label: String) -> void:
	var a := character_region(left).get_data()
	var b := character_region(right).get_data()
	var changed_channels := 0
	var maximum := 0
	for index in a.size():
		var difference := absi(int(a[index]) - int(b[index]))
		if difference > 0:
			changed_channels += 1
		maximum = maxi(maximum, difference)
	if not report.has("neutral_pixel_comparisons"):
		report["neutral_pixel_comparisons"] = []
	report.neutral_pixel_comparisons.append({"label": label, "max_channel_difference": maximum, "changed_channels": changed_channels})
	# Saved neutral renders have identical alpha; <=15 pixels differ by <=2 color levels.
	check(maximum <= 2 and changed_channels <= 128, label + " matches within two-level raster rounding")


func run() -> void:
	if output.is_empty() or not output.is_absolute_path():
		push_error("Absolute --output directory required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/demos/jiang_sword_cycle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var state_before := snapshot(scene.state)
	check(scene._idle_frames.size() == 60 and scene._action_frames.size() == 180, "60-frame idle and 180-frame action clips load")
	check(is_equal_approx(scene.IDLE_SECONDS, 2.0) and is_equal_approx(scene.ACTION_SECONDS, 6.0), "clip durations derive from 30 fps frame counts")
	check(scene._resized_anchor.distance_to(Vector2(245.22732544, 466.50038784)) < 0.001, "shared source foot anchor is retained")
	check(scene._cycle_actor.get_child_count() == 1 and scene._cycle_actor.get_child(0) == scene._cycle_sprite, "one character Sprite2D presents the Jiang clips")
	check(scene._art_nodes.has(scene._cycle_actor) and scene._art_nodes.has(scene._contact_shadow), "actor and approved contact shadow participate in world grading")

	for size in [Vector2i(1152, 720), Vector2i(960, 600)]:
		root.size = size
		scene.reset_review()
		var idle := await capture("%dx%d-idle-neutral.png" % [size.x, size.y])
		scene.seek_action_frame(0)
		var action_neutral := await capture("%dx%d-action-neutral.png" % [size.x, size.y])
		neutral_match(idle, action_neutral, "idle/action neutral at %dx%d" % [size.x, size.y])
		scene.seek_action_frame(52)
		await capture("%dx%d-action-mid.png" % [size.x, size.y])
		scene.seek_action_frame(179)
		var action_final := await capture("%dx%d-action-final.png" % [size.x, size.y])
		neutral_match(action_neutral, action_final, "action start/end at %dx%d" % [size.x, size.y])
		scene.reset_review()
		scene._process(59.0 / 30.0)
		var idle_final := await capture("%dx%d-idle-final.png" % [size.x, size.y])
		# Freeze the same world clock before comparing the idle endpoint textures.
		scene._apply_actor_frame(0)
		var idle_restart := await capture("%dx%d-idle-restart.png" % [size.x, size.y])
		neutral_match(idle_final, idle_restart, "idle wrap at %dx%d" % [size.x, size.y])

	# Start away from neutral, settle in 0.25 seconds, and ignore repeated requests.
	scene.reset_review()
	scene._process(20.0 / 30.0)
	check(scene.qa_state().frame_index == 20, "idle breathing advances on its native 30 fps clock")
	check(scene.practice(), "practice starts from an idle frame")
	check(scene.qa_state().actor_state == "settle" and scene.qa_state().busy, "non-neutral practice enters the settle phase")
	check(not scene.practice(), "repeated practice is ignored while settling")
	scene._process(0.25)
	check(scene.qa_state().actor_state == "action" and scene.qa_state().frame_index == 0 and scene.qa_state().phase == "起势", "settle reaches neutral before action frame zero")
	check(not scene.practice(), "repeated practice is ignored during action")
	scene.seek_action_frame(43)
	check(scene.qa_state().phase == "起势", "phase remains 起势 at action frame 43")
	scene.seek_action_frame(44)
	check(scene.qa_state().phase == "出剑", "phase changes to 出剑 at action frame 44")
	scene.seek_action_frame(59)
	check(scene.qa_state().phase == "出剑", "phase remains 出剑 at action frame 59")
	scene.seek_action_frame(60)
	check(scene.qa_state().phase == "收势", "phase changes to 收势 at action frame 60")
	scene.seek_action_frame(101)
	check(scene.qa_state().phase == "收势", "phase remains 收势 at action frame 101")
	scene.seek_action_frame(102)
	check(scene.qa_state().phase == "回位", "phase changes to 回位 at action frame 102")
	scene.seek_action_frame(50)
	check(scene.qa_state().phase == "出剑", "action status shows the sword strike phase")
	scene.seek_action_frame(100)
	check(scene.qa_state().phase == "收势", "action status shows the recovery phase")
	scene.seek_action_frame(160)
	check(scene.qa_state().phase == "回位", "action status shows return-to-neutral phase")
	scene.seek_action_frame(0)
	scene.qa_motion_paused = false

	# Actor speed scales only the actor clock; the painterly world keeps its own clock.
	check(scene.set_speed(0.5), "half speed is accepted")
	scene._process(2.0)
	check(scene.qa_state().frame_index == 30 and is_equal_approx(scene.qa_state().action_time_seconds, 1.0), "half speed advances the action at half rate")
	check(scene.set_speed(1.0), "normal speed is accepted")
	scene._process(0.5)
	check(scene.qa_state().frame_index == 45 and is_equal_approx(scene.qa_state().action_time_seconds, 1.5), "normal speed advances the action at native rate")

	# Static freezes current imagery, environment transitions, actor frame and both clocks.
	check(scene.set_time("you", true) and scene.set_weather("light_rain", true), "time and weather transitions can be started")
	scene.set_dynamic(false)
	check(not scene.practice(), "practice is disabled in Static")
	var frozen_state: Dictionary = scene.qa_state()
	var frozen_environment := snapshot(scene.environment_presenter)
	for size in [Vector2i(1152, 720), Vector2i(960, 600)]:
		root.size = size
		var static_a := await capture("%dx%d-static-a.png" % [size.x, size.y])
		scene._process(0.7)
		var static_b := await capture("%dx%d-static-b.png" % [size.x, size.y])
		check(static_a.get_data() == static_b.get_data(), "Static images are byte-identical at %dx%d" % [size.x, size.y])
		check(scene.qa_state() == frozen_state and snapshot(scene.environment_presenter) == frozen_environment, "Static preserves actor and environment transition state at %dx%d" % [size.x, size.y])
	scene.set_dynamic(true)
	scene._process(0.25)
	check(scene.qa_state().frame_index == 52 and is_equal_approx(scene.qa_state().action_time_seconds, 1.75), "Resume continues the action from its exact frozen frame")
	check(scene.environment_presenter.time_profile_id == "you" and scene.environment_presenter.weather_id == "light_rain", "Resume retains selected time and weather")
	scene._process(4.25)
	check(scene.qa_state().actor_state == "idle" and scene.qa_state().frame_index == 0 and not scene.qa_state().busy, "six-second action returns to idle frame zero")
	check(scene.qa_state().cycle_count == 1, "one completed action increments one cycle")
	await capture("960x600-returned-idle.png")

	# The idle clip is a native two-second loop; all six times and three weather profiles remain available.
	scene._process(1.0)
	check(scene.qa_state().frame_index == 30, "idle reaches its half-cycle at one second")
	scene._process(1.0)
	check(scene.qa_state().frame_index == 0, "idle returns to neutral after two seconds")
	for option: Dictionary in scene.TIME_OPTIONS:
		check(scene.set_time(str(option.id), false) and scene.qa_state().time_profile_id == str(option.id), "time profile applies: " + str(option.label))
	for option: Dictionary in scene.WEATHER_OPTIONS:
		check(scene.set_weather(str(option.id), false) and scene.qa_state().weather_id == str(option.id), "weather profile applies: " + str(option.label))
	check(scene.set_time("you", false) and scene.set_weather("light_rain", false), "dusk rain applies to the complete cycle")
	check(scene._cycle_actor.modulate != Color.WHITE and scene._cycle_actor.modulate == scene._contact_shadow.modulate, "actor and contact shadow receive dusk world tint")
	await capture("960x600-dusk-rain-idle.png")
	scene.reset_review()
	scene._process(0.4)
	check(scene.practice(), "a second practice can start from returned idle")
	scene._process(6.25)
	check(scene.qa_state().cycle_count == 1 and scene.qa_state().actor_state == "idle" and not scene.qa_state().busy, "repeated complete practice returns to idle")

	scene.set_speed(0.5)
	scene.set_dynamic(false)
	scene.reset_review()
	check(scene.qa_state().actor_state == "idle" and scene.qa_state().frame_index == 0 and scene.qa_state().cycle_count == 0, "presentation reset restores idle neutral")
	check(scene.qa_state().playback_speed == 1.0 and scene.qa_state().dynamic_enabled, "presentation reset restores normal Dynamic mode")
	check(scene.qa_state().time_profile_id == "wu" and scene.qa_state().weather_id == "clear" and scene.presentation_time == 0.0, "presentation reset restores the approved noon-clear environment")
	check(snapshot(scene.state) == state_before and scene.qa_state().state_unchanged, "all DemoState script variables remain unchanged")
	report["status"] = "PASS" if report.failures == 0 else "FAIL"
	var file := FileAccess.open(output.path_join("scene-verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("JIANG_SWORD_CYCLE_SCENE: %d checks, %d captures, %d failures" % [report.checks.size(), report.captures.size(), report.failures])
	quit(0 if report.failures == 0 else 1)
