extends "res://tests/cultivation_engine_chengdu_render.gd"
## Actual Godot mouse-event dispatch, separate from physical device acceptance.
## Uses real walking and door clicks; never assigns Session or actor positions.

var visited_districts: Array[String] = []
var traversed_exits: Array[String] = []
var refresh_checkpoint: Dictionary = {}

func _run() -> void:
	output_dir = "res://.local/qa/chengdu/loops-native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "city loop acceptance runs on an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	test_store_dir = "user://chengdu_loops_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = ChengduScene.instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu" and _state().scene == "tingyu_corridor", "loops begin in an isolated genuine new run")
	await _flow()
	_finish()

func _flow() -> bool:
	if not await _click("ActionButton_go_to_town") or not await _close_event():
		return false
	visited_districts.append(str(_state().scene))
	var arrival := _state()
	check(arrival.scene == "chengdu_gate", "explicit journey starts at the west gate")
	await _capture("00_gate_two_choices.png", "west gate offers the market or the craft lane without task unlocks")
	await _check_city_geometry()
	# First river route leaves via the northern lane, then returns by the market.
	for edge: Dictionary in [
		{"id": "gate_lanes_exit", "scene": "chengdu_lanes", "entry": "from_gate"},
		{"id": "lanes_square_exit", "scene": "chengdu_square", "entry": "from_lanes"},
		{"id": "square_river_exit", "scene": "chengdu_river", "entry": "from_square"},
		{"id": "river_market_exit", "scene": "chengdu_market", "entry": "from_east"},
		{"id": "market_gate_exit", "scene": "chengdu_gate", "entry": "from_east"}]:
		if not await _door(edge):
			return false
		if edge.scene in ["chengdu_lanes", "chengdu_square", "chengdu_river"]:
			await _check_city_geometry()
			await _capture("01_loop_" + str(edge.scene) + ".png", "actual lane-first route through a distinct district")
	check(_state().scene == "chengdu_gate", "lane-square-river-market route closes a real walking loop")
	# Save the completed loop at its genuine gate-side arrival. Browser replay can
	# refresh at this capture before continuing the exact same mouse trace.
	var saved_loop := _state()
	if not await _click("CityMenuButton") or not await _click("SaveButton") or not await _click("CityMenuCloseButton"):
		return false
	refresh_checkpoint = {"capture": "02_saved_gate_loop.png", "scene": "chengdu_gate", "state": saved_loop,
		"expected_flags": saved_loop.flags, "position": saved_loop.exploration.positions.chengdu_gate}
	await _capture("02_saved_gate_loop.png", "safe browser-refresh checkpoint after completing the outdoor loop; return to the same east gate position")
	# Pass through the teahouse from the lane door to the market-facing front door.
	for edge: Dictionary in [
		{"id": "gate_lanes_exit", "scene": "chengdu_lanes", "entry": "from_gate"},
		{"id": "lanes_teahouse_door", "scene": "chengdu_teahouse", "entry": "from_lanes"}]:
		if not await _door(edge):
			return false
	check(_state().scene == "chengdu_teahouse", "a real back doorway opens the existing shop")
	await _check_city_geometry()
	await _capture("03_teahouse_back_door.png", "player entered the tea shop from the lane, with its separate market exit visible")
	if not await _door({"id": "tea_market_exit", "scene": "chengdu_market", "entry": "from_teahouse"}):
		return false
	await _capture("04_shop_front_exit.png", "crossing the shop returns to its front entrance in the market")
	check(visited_districts.size() == 6, "actual input visits all six distinct districts")
	var final := _state()
	check(final.day == arrival.day and final.slot == arrival.slot and final.stats == arrival.stats and final.flags == arrival.flags, "all loop walks and shop crossings leave time, resources and task flags unchanged")
	check(int(final.counts.get("gate_to_lanes", 0)) == 2 and int(final.counts.get("river_to_market", 0)) == 1, "the completed loop and subsequent shop route are real independent spatial trips")
	check(int(final.counts.get("enter_teahouse_back", 0)) == 1 and int(final.counts.get("leave_teahouse", 0)) == 1, "back-door entry and front-door exit settle as separate real spatial actions")
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(_state() == saved_loop, "actual menu load after walking through another shop door restores the exact saved map, foot point, flags, counts and receipts")
	await _capture("05_loop_checkpoint_restored.png", "the completed-loop checkpoint restores after a different route through the tea shop")
	return true

func _door(edge: Dictionary) -> bool:
	var before := _state()
	if not await _interact(str(edge.id)):
		return false
	var state := _state()
	var pack: Dictionary = app.call("_current_pack")
	check(state.scene == edge.scene, "actual door click changes to the chosen neighboring district: " + str(edge.id))
	if state.scene != edge.scene:
		return false
	check(state.phase == "ready", "free district crossing immediately returns control without a result-confirmation click: " + str(edge.id))
	var authored: Array = pack.walks.scenes[edge.scene].entries[edge.entry]
	var point: Array = [int(authored[0]), int(authored[1])]
	check(state.exploration.positions[edge.scene] == point, "actual walking arrives at its designed side: " + str(edge.id))
	check(state.day == before.day and state.slot == before.slot and state.stats == before.stats and state.flags == before.flags, "this actual city crossing is free: " + str(edge.id))
	traversed_exits.append(str(edge.id))
	if not visited_districts.has(str(edge.scene)):
		visited_districts.append(str(edge.scene))
	return await _close_event()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report := {"test": "chengdu_loops_render", "checks": checks, "failures": failures, "failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y], "captures": captures, "external_input_trace": input_trace,
		"visited_districts": visited_districts, "traversed_exits": traversed_exits,
		"browser_refresh_checkpoint": refresh_checkpoint,
		"walk_samples": _walk_samples, "display_server": DisplayServer.get_name(),
		"input_scope": "Godot root.push_input mouse events on a real window; physical mouse, device sound and other platforms unverified",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("chengdu-loops-render-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
	if app != null:
		root.remove_child(app)
		app.queue_free()
	await process_frame
	print("CHENGDU_LOOPS_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
