extends SceneTree
const Cycle = preload("res://scripts/weather_cycle.gd")
var failures := 0
func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition: failures += 1
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var bounds := true
	for i in range(601):
		var values := Cycle.sample(float(i) * 0.1)
		for key in ["cloud", "wind", "rain"]:
			bounds = bounds and float(values[key]) >= 0.0 and float(values[key]) <= 1.0
	check(bounds, "two weather cycles stay within safe opacity/wind ranges")
	check(Cycle.sample(10.0).rain == 0.0 and Cycle.sample(19.0).rain > 0.99, "wind precedes rain and wet phase is reachable")
	check(Cycle.sample(0.0).cloud == Cycle.sample(30.0).cloud and Cycle.sample(29.999).cloud < 0.001, "loop clears smoothly without a light jump")
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.weather.motion_paused = true
	game.weather.seek(19.0)
	game._ask()
	var energy: int = game.state.energy
	var progress: int = game.state.cultivation
	var turn: String = game.state.time_text()
	game.weather.set_dynamic(false)
	check(game.state.dialogue_open and game.state.energy == energy and game.state.cultivation == progress and game.state.time_text() == turn, "static comparison preserves dialogue and cultivation state")
	var stopped: bool = not game.weather.is_processing()
	for rain in game.weather.rain_nodes:
		stopped = stopped and not rain.visible and rain.process_mode == Node.PROCESS_MODE_DISABLED
	for item in game.weather.lit:
		stopped = stopped and item.art.material == item.original
	check(stopped, "static mode stops weather work and restores original art materials")
	var held: float = game.weather.elapsed
	await process_frame
	check(game.weather.elapsed == held, "static mode holds presentation time")
	game.weather.set_dynamic(true)
	check(game.weather.phase == "山间小雨" and game.state.dialogue_open, "resuming weather keeps phase and conversation")
	game._cancel()
	game._rest()
	check(game.weather.elapsed == held and game.state.time_text() != turn, "cultivation turns and weather clock remain independent")
	print("WEATHER_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
