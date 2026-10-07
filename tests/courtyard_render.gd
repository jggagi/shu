extends SceneTree

const Scene = preload("res://scenes/demos/mountain_gate_courtyard.tscn")
var game
var failures: Array[String] = []
var captures: Array[String] = []
const OUT := "res://.local/qa/courtyard-v1/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1440,900)
	game = Scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	step(3.5)
	await capture("01-composition-cloudy")
	var host_before := host_state()
	game.set_time_preview(2)
	game.set_weather_preview("clear")
	step(5.0)
	await capture("02-clear")
	game.set_weather_preview("cloudy")
	step(5.0)
	await capture("03-cloudy")
	game.set_weather_preview("light_rain")
	step(5.0)
	await capture("04-light-rain")
	for i in 6:
		game.set_time_preview(i)
		step(2.0)
		await capture("time-%d-rain" % i)
	check(host_before == host_state(),"Time/weather preview preserved full DemoState")
	game.reset_scene()
	step(5.0)
	await capture("05-wind-before")
	step(2.0)
	await capture("06-wind-crest")
	step(5.0)
	await capture("07-wind-calm")
	step(14.0)
	await capture("08-cat-route")
	game.toggle_dynamic()
	var frozen: Dictionary = game.get_snapshot()
	await capture("09-static-a")
	step(3.0)
	await capture("10-static-b")
	check(game.environment.elapsed == float(frozen.environment.elapsed),"Static environment clock frozen")
	var a := Image.load_from_file(ProjectSettings.globalize_path(OUT+"09-static-a.png"))
	var b := Image.load_from_file(ProjectSettings.globalize_path(OUT+"10-static-b.png"))
	check(a.get_data() == b.get_data(),"Static rendered image identical")
	game.toggle_dynamic()
	step(0.5)
	await capture("11-resume")
	step(11.0)
	await capture("12-cat-sit-or-return")
	game.reset_scene()
	step(3.5)
	root.size=Vector2i(1200,750)
	await process_frame
	await capture("13-small-window")

	game.reset_scene()
	check(game.preview_time_index == -1 and game.weather_id == "cloudy" and game.dynamic_enabled,"Reset restores preview defaults")
	check(game.environment.elapsed == 0.0,"Reset clears presentation clocks")
	await capture("14-reset")
	var report := {"renderer":RenderingServer.get_rendering_device(),"display":DisplayServer.get_name(),"captures":captures,"failures":failures,"snapshot":game.get_snapshot(),"note":"Time advancement accelerated for pose/effect captures; no natural-frequency or human acceptance claim."}
	FileAccess.open(OUT+"render-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Courtyard render: %d captures; %d failures" % [captures.size(),failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func step(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(remaining,1.0/60.0)
		game.advance_presentation(delta)
		remaining -= delta

func capture(name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var path := OUT+name+".png"
	var img := root.get_texture().get_image()
	check(img.save_png(path)==OK,"Save "+name)
	captures.append(name+".png")
	FileAccess.open(OUT+name+".json",FileAccess.WRITE).store_string(JSON.stringify(game.get_snapshot(),"\t"))

func host_state() -> Dictionary:
	var result: Dictionary = {}
	for p in game.state.get_property_list():
		if int(p.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[p.name]=game.state.get(p.name)
	return result.duplicate(true)

func check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
