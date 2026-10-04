extends SceneTree

# Captures the real Compatibility renderer; headless state tests cannot audit shaders.
var game: Control
var output := "res://.local/qa/weather3"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 720)
	OS.low_processor_usage_mode = false
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.0).timeout
	game.weather.motion_paused = true
	game.weather.set_dynamic(false)
	await _capture("static")
	var static_metrics: Dictionary = await _measure()
	game.weather.set_dynamic(true)
	game.weather.seek(4.0)
	await _capture("cloud")
	game.weather.seek(10.0)
	await _capture("wind")
	game.weather.seek(19.0)
	await create_timer(2.0).timeout
	await _capture("rain")
	await _capture("rain-frozen")
	for rain in game.weather.rain_nodes:
		rain.visible = false
	game.weather.set_process(false)
	await _capture("rain-disabled")
	for rain in game.weather.rain_nodes:
		rain.visible = true
	game.weather.set_process(true)
	var dynamic_metrics: Dictionary = await _measure()
	var report := {"renderer": RenderingServer.get_video_adapter_name(), "size": [1152,720], "static":static_metrics, "rain":dynamic_metrics}
	var file := FileAccess.open(output + "/render-metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("RENDER_METRICS: ", JSON.stringify(report))
	# Short, real rendered review clip: moving bamboo followed by outdoor rain.
	for i in range(24):
		game.weather.seek((10.0 if i < 12 else 19.0) + float(i % 12) * 0.25)
		await create_timer(0.25).timeout
		await _capture("clip-%02d" % i)
	print("WEATHER_RENDER: captures completed")
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output + "/" + label + ".png")
	if result != OK:
		push_error("Failed to save rendered frame: " + label)
		quit(1)

func _measure() -> Dictionary:
	# Performance monitors refresh periodically. Let screenshot readback/PNG
	# encoding leave the sampling window before collecting steady-state costs.
	for i in range(120):
		await process_frame
	var total := 0.0
	var peak := 0.0
	var draws := 0.0
	var weather_total := 0.0
	for i in range(120):
		await process_frame
		if game.weather.enabled:
			var start := Time.get_ticks_usec()
			game.weather._apply()
			weather_total += float(Time.get_ticks_usec() - start) / 1000.0
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		total += ms
		peak = maxf(peak, ms)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return {"samples":120,"process_mean_ms":total / 120.0,"process_peak_ms":peak,"draw_calls_mean":draws / 120.0,"weather_apply_mean_ms":weather_total / 120.0}
