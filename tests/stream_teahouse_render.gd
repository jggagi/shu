extends SceneTree

const OUTPUT := "res://.local/qa/stream-teahouse-v1.3"
var game: Control
var checks := 0
var failures := 0
var captures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = load("res://scenes/demos/stream_teahouse.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.qa_motion_paused = true
	check(DisplayServer.get_name() != "headless", "actual windowed Compatibility render")
	check(game.cat.sprite != null, "cat atlas loaded")
	check(game.cat.hotspot.disabled == false, "resident pet hotspot available")
	for weather in ["clear", "cloudy", "light_rain"]:
		game.reset_scene()
		game.set_weather(weather, false)
		for index in 6:
			game.set_time_index(index, false)
			game.advance_presentation(2.0)
			await capture("%s_%s.png" % [weather, game.TIMES[index]])
			check(game.presenter.time_profile_id == game.TIMES[index], "time profile " + game.TIMES[index])
	check(game.cat.hotspot.disabled, "exposed bank cat disables petting in rain")
	check(is_zero_approx(game.cat._weather_alpha), "exposed cat faded in rain")
	game.reset_scene()
	game.set_weather("clear", false)
	game.advance_presentation(13)
	await capture("cat_outbound.png")
	var contact: Vector2 = game.cat.motion.global_position()
	check(game.cat.motion.is_walking(), "cat uses authored stone path")
	var elapsed: float = game.presentation_time
	var phase: float = game.cat.motion.activity_elapsed
	game.dynamic_button.emit_signal("pressed")
	game.advance_presentation(3)
	check(not game.dynamic_enabled, "real Static button")
	check(game.presentation_time == elapsed, "water and atmosphere clock freeze")
	check(game.cat.motion.activity_elapsed == phase, "cat route clock freeze")
	check(game.cat.motion.global_position().is_equal_approx(contact), "cat stays at current contact position")
	check(game.cat.pose_index == 13, "travel pauses in standing pose")
	check(game.cat.hotspot.disabled, "Static disables interaction")
	await capture("static_a.png")
	game.advance_presentation(2)
	await capture("static_b.png")
	var a := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/static_a.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/static_b.png"))
	check(a.get_data() == b.get_data(), "complete Static frame identical after two presentation seconds")
	game.dynamic_button.emit_signal("pressed")
	game.advance_presentation(2)
	check(game.presentation_time > elapsed, "Resume advances water")
	check(game.cat.motion.activity_elapsed > phase, "Resume advances same cat route")
	check(not game.cat.motion.global_position().is_equal_approx(contact), "Resume moves from paused bank contact")
	await capture("resume.png")
	var before_pet: Vector2 = game.cat.motion.global_position()
	game.cat.hotspot.emit_signal("pressed")
	check(game.cat.pose_index == 7, "real cat hotspot triggers pet pose")
	check(game.feedback_remaining > 0, "pet response caption")
	game.advance_presentation(1)
	check(game.cat.motion.global_position().is_equal_approx(before_pet), "pet holds path position")
	await capture("pet.png")
	game.advance_presentation(2)
	check(game.cat.pet_remaining == 0, "pet response finishes")
	# Advance enough to view the return gait.
	game.reset_scene()
	game.advance_presentation(55)
	await capture("cat_return.png")
	check(game.cat.motion.facing_x() < 0, "return direction uses mirrored poses")
	# Explicit time/weather changes keep transitions while motion stays frozen.
	game.set_dynamic(false)
	var frozen: float = game.presentation_time
	game.set_time_index(5)
	game.set_weather("light_rain")
	game.advance_presentation(5)
	check(game.presenter.get_current_environment() == game.presenter.get_target_environment(), "profile transitions finish in Static")
	check(game.presentation_time == frozen, "changing profile preserves motion freeze")
	await capture("static_weather_change.png")
	game.water.material = null
	game.water.color = Color(1, 0, 0, 0.3)
	await capture("qa_water_mask.png")
	game.water.material = game.water_material
	game.water.color = Color.WHITE
	game.reset_button.emit_signal("pressed")
	check(game.time_index == 0 and game.weather_id == "cloudy" and game.dynamic_enabled, "real Reset restores initial selections")
	check(game.presentation_time == 0 and game.cat.pet_remaining == 0, "Reset clears all presentation phases")
	await capture("reset.png")
	game.set_weather("clear", false)
	game.set_time_index(3, false)
	await capture("flow_a.png")
	game.advance_presentation(2)
	await capture("flow_b.png")
	var flow_a := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/flow_a.png"))
	var flow_b := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/flow_b.png"))
	var viewport_scale := Vector2(root.size) / game.size
	var water_corner: Vector2 = game.world.to_global(Vector2(1030, 575)) * viewport_scale
	var sample_size: Vector2 = Vector2(180, 100) * game.world.scale * viewport_scale
	var sample := Rect2i(Vector2i(water_corner), Vector2i(sample_size))
	check(flow_a.get_region(sample).get_data() != flow_b.get_region(sample).get_data(), "actual clear water pixels change between dynamic frames")
	# Isolate new distant-waterfall motion so mist/rain/cat cannot satisfy this check.
	game.reset_scene()
	game.set_weather("clear", false)
	game.set_time_index(3, false)
	game.set_dynamic(false)
	game.waterfall_mist.visible = false
	game.waterfall.visible = false
	await capture("waterfall_original.png")
	game.waterfall.visible = true
	await capture("waterfall_a.png")
	game.waterfall_material.set_shader_parameter("elapsed", 0.65)
	await capture("waterfall_b.png")
	var fall_a := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/waterfall_a.png"))
	var fall_b := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/waterfall_b.png"))
	var fall_corner: Vector2 = game.world.to_global(Vector2(844, 187)) * viewport_scale
	var fall_size: Vector2 = Vector2(52, 94) * game.world.scale * viewport_scale
	check(fall_a.get_region(Rect2i(Vector2i(fall_corner), Vector2i(fall_size))).get_data() != fall_b.get_region(Rect2i(Vector2i(fall_corner), Vector2i(fall_size))).get_data(), "isolated waterfall pixels move with controlled elapsed")
	var mountain_corner: Vector2 = game.world.to_global(Vector2(770, 200)) * viewport_scale
	var mountain_size: Vector2 = Vector2(55, 100) * game.world.scale * viewport_scale
	check(fall_a.get_region(Rect2i(Vector2i(mountain_corner), Vector2i(mountain_size))).get_data() == fall_b.get_region(Rect2i(Vector2i(mountain_corner), Vector2i(mountain_size))).get_data(), "adjacent mountain pixels remain identical during isolated waterfall flow")
	game.waterfall.material = null
	game.waterfall.color = Color(1, 0, 0, 0.65)
	await capture("qa_waterfall_mask.png")
	game.waterfall.material = game.waterfall_material
	game.waterfall.color = Color.WHITE
	game.waterfall_mist.visible = true
	game.reset_scene()
	game.set_weather("clear", false)
	game.set_time_index(3, false)
	for frame in 16:
		game.advance_presentation(0.12)
		await capture("waterfall_motion_%02d.png" % frame)
	# Isolate river advection from the waterfall, atmosphere and resident cat.
	game.reset_scene()
	game.set_weather("clear", false)
	game.set_time_index(3, false)
	game.set_dynamic(false)
	game.water.visible = false
	await capture("river_original.png")
	game.water.visible = true
	await capture("river_a.png")
	game.water_material.set_shader_parameter("elapsed", 1.0)
	await capture("river_b.png")
	var river_a := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/river_a.png"))
	var river_b := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/river_b.png"))
	for region in [Rect2(790, 454, 70, 22), Rect2(1025, 570, 110, 90)]:
		var region_corner: Vector2 = game.world.to_global(region.position) * viewport_scale
		var region_size: Vector2 = region.size * game.world.scale * viewport_scale
		check(river_a.get_region(Rect2i(Vector2i(region_corner), Vector2i(region_size))).get_data() != river_b.get_region(Rect2i(Vector2i(region_corner), Vector2i(region_size))).get_data(), "isolated river pixels flow at " + str(region.position))
	var bank_corner: Vector2 = game.world.to_global(Vector2(480, 535)) * viewport_scale
	var bank_size: Vector2 = Vector2(180, 70) * game.world.scale * viewport_scale
	check(river_a.get_region(Rect2i(Vector2i(bank_corner), Vector2i(bank_size))).get_data() == river_b.get_region(Rect2i(Vector2i(bank_corner), Vector2i(bank_size))).get_data(), "stone bank remains pixel-identical during isolated river motion")
	game.set_dynamic(true)
	for frame in 24:
		game.advance_presentation(0.12)
		await capture("river_motion_%02d.png" % frame)
	# Actual dusk mist difference at the previously visible hard diagonal edge.
	game.reset_scene()
	game.set_time_index(5, false)
	game.set_weather("light_rain", false)
	game.advance_presentation(2.0)
	game.set_dynamic(false)
	game.atmosphere_material.set_shader_parameter("rain_amount", 0.0)
	await capture("dusk_mist.png")
	game.atmosphere.visible = false
	await capture("dusk_no_mist.png")
	var dusk_mist := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/dusk_mist.png"))
	var dusk_base := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/dusk_no_mist.png"))
	var edge_point: Vector2 = game.world.to_global(Vector2(530, 415)) * viewport_scale
	var edge_delta: float = dusk_mist.get_pixelv(Vector2i(edge_point)).r - dusk_base.get_pixelv(Vector2i(edge_point)).r
	check(absf(edge_delta) < 2.0 / 255.0, "dusk mist fades to original painting at authored diagonal edge")
	var interior_point: Vector2 = game.world.to_global(Vector2(750, 340)) * viewport_scale
	check(dusk_mist.get_pixelv(Vector2i(interior_point)) != dusk_base.get_pixelv(Vector2i(interior_point)), "mist remains visible inside the mountain valley")
	game.atmosphere.visible = true
	game._apply_environment()
	await capture("dusk_static_a.png")
	game.advance_presentation(2.0)
	await capture("dusk_static_b.png")
	var dusk_a := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/dusk_static_a.png"))
	var dusk_b := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "/dusk_static_b.png"))
	check(dusk_a.get_data() == dusk_b.get_data(), "complete dusk Static frames identical")
	root.size = Vector2i(960, 600)
	await process_frame
	await process_frame
	await capture("small_960x600.png")
	check(game.cat.hotspot.get_global_rect().has_point(game.cat.hotspot.global_position + game.cat.hotspot.size / 2), "hotspot still has nonempty bounds")
	var report := {"checks": checks, "failures": failures, "captures": captures,
		"renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}
	var output := FileAccess.open(OUTPUT + "/render-report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print("STREAM_TEAHOUSE_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	check(rendered.save_png(ProjectSettings.globalize_path(OUTPUT + "/" + filename)) == OK, "saved " + filename)
	captures.append(filename)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS: " if condition else "FAIL: ") + label)
