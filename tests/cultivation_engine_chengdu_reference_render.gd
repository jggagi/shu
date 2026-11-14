extends "res://tests/cultivation_engine_chengdu_large_render.gd"
## Reuses the actual-window mouse/key, capture, walking and trace tools. No
## direct camera movement, player state assignment or gameplay click_at calls.

const ReferenceScenePath := "res://scenes/demos/cultivation_engine_chengdu_reference.tscn"
const ReferenceWorldData := "res://assets/data/chengdu-reference-layout.json"
var full_map_clicks := 0

func _run() -> void:
	output_dir = "res://.local/qa/chengdu-reference/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "reference native acceptance uses an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ReferenceWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_reference_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(ReferenceScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_reference" and _state().scene == "tingyu_corridor", "reference city starts in the original cultivation scene with its own package identity")
	await _flow()
	_finish()

func _flow() -> bool:
	if not await _click("ActionButton_talk_mentor"):
		return false
	for _line: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	if not await _click("ChoiceButton_take_lesson") or not await _close_event():
		return false
	check(int(_state().stats.energy) == 92 and int(_state().slot) == 1, "original same-scene mentor choice retains its original outcome")
	if not await _click("ActionButton_go_to_town"):
		return false
	check(_state().scene == "chengdu_city" and _state().phase == "result", "one-slot journey arrives south of Wanli bridge with its explicit receipt")
	if not await _check_modal_input() or not await _close_event():
		return false
	initial_camera = _large_audit().get("camera_center", Vector2.ZERO)
	var initial := _state()
	await _check_large_view()
	await _capture("00_reference_wanli_south.png", "south bank arrival faces the real Wanli bridge and south gate")
	# A full-map click crosses the actual bridge; later clicks use the small map.
	if not await _full_map_move(Vector2(2600, 2920)):
		return false
	region_visits.append("south_gate")
	await _check_large_view()
	await _capture("01_reference_south_gate.png", "actual northbound walking crosses Wanli bridge toward the aligned south gate")
	if not await _visible_ground_step() or not await _map_move(Vector2(2600, 1510)):
		return false
	region_visits.append("north_precinct")
	await _check_large_view()
	await _capture("02_reference_inner_precinct.png", "the same avenue reaches the northern inner precinct without a scene transition")
	if not await _map_move(Vector2(1700, 2040)):
		return false
	region_visits.append("mohe")
	await _check_large_view()
	await _capture("03_reference_mohe.png", "continuous streets lead around the actual blocking pond to Mohe and Sanhua")
	# The district visit point coincides with the Daci interaction. Approach safe
	# nearby ground first, then deliberately click the visible landmark itself.
	if not await _full_map_move(Vector2(3730, 2110)):
		return false
	region_visits.append("daci")
	check(_state().scene == "chengdu_city" and _state().counts == initial.counts and _state().sequence == initial.sequence and _state().slot == initial.slot and _state().stats == initial.stats, "bridge, gate, northern precinct, pond and eastern temple are continuous free walking")
	await _check_large_view()
	await _capture("04_reference_daci.png", "the eastern temple forecourt is reached by real route following")
	if not await _large_interact("reference_daci_temple") or not await _close_event():
		return false
	if not await _map_move(Vector2(4220, 2350)):
		return false
	region_visits.append("east_river")
	await _check_large_view()
	await _capture("05_reference_east_river.png", "the east-side route reaches the Qingyuan riverside")
	if not await _large_interact("river_umbrella") or not await _click("ChoiceButton_take") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_carrying) and not bool(_large_audit().get("river_umbrella_visible", true)), "the deliberate choice carries one umbrella and removes its river prop")
	var saved := _state()
	if not await _click("CityMenuButton") or not await _click("SaveButton") or not await _click("CityMenuCloseButton"):
		return false
	refresh_checkpoint = {"capture": "06_reference_saved_river.png", "state": saved,
		"scene": "chengdu_city", "position": saved.exploration.positions.chengdu_city,
		"expected_flags": saved.flags, "map_collapsed": false, "map_detail": false}
	await _capture("06_reference_saved_river.png", "real save/refresh checkpoint on the east river while carrying the umbrella")
	if not await _large_interact("lanes_teahouse_door"):
		return false
	check(_state().scene == "chengdu_teahouse" and _state().phase == "ready" and _state().exploration.positions.chengdu_teahouse == [640, 240], "actual pond-side back door arrives immediately ready at the north indoor entrance")
	await _check_city_geometry()
	await _capture("07_reference_tea_back.png", "the pond-side rear street enters the real back doorway")
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_return") or not await _close_event():
		return false
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_revisit") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_returned) and int(_state().counts.get("return_river_umbrella", 0)) == 1 and bool(_city_stage_audit().get("returned_umbrella_visible", false)), "return and revisit leave one remembered umbrella visibly on the stand")
	await _capture("08_reference_returned.png", "the carried umbrella returns once to the existing lost-property stand")
	if not await _interact("tea_market_exit"):
		return false
	check(_state().scene == "chengdu_city" and _state().phase == "ready" and _state().exploration.positions.chengdu_city == [2120, 2510], "front exit returns immediately ready to a different point in the same outdoor scene")
	await _check_large_view()
	await _capture("09_reference_tea_front.png", "the shop front returns to the school-side street with the rear door elsewhere")
	# Exercise the opposite direction too, observing both visible door approaches.
	if not await _large_interact("market_teahouse_door"):
		return false
	check(_state().phase == "ready" and _state().exploration.positions.chengdu_teahouse == [640, 570], "real front door enters at its separate southern indoor arrival")
	if not await _interact("tea_lanes_exit"):
		return false
	check(_state().scene == "chengdu_city" and _state().phase == "ready" and _state().exploration.positions.chengdu_city == [2120, 1990], "real back exit returns to the pond bank without a fee or extra result click")
	await _capture("09a_reference_tea_back_exit.png", "both directions through the shop use distinct outdoor door positions")
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(_state() == saved, "actual load after walking far and returning the umbrella restores every saved field and the earlier river position")
	await _capture("10_reference_checkpoint_restored.png", "full checkpoint restores the far river coordinates, carried state, clock and receipts")
	if not await _map_move(Vector2(2600, 3360)) or not await _large_interact("gate_mountain_exit") or not await _close_event():
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().slot) == 3 and int(_state().stats.energy) == 92, "return from the actual southern exit charges only the original one-slot travel fee")
	if not await _click("CityMenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().stats.energy) == 100 and not bool(_state().flags.chengdu_umbrella_carrying) and not bool(_state().flags.chengdu_umbrella_returned), "confirmed reset starts a fresh shared cultivation/city run")
	await _capture("11_reference_restarted.png", "explicit reset retains the original cultivation entry and clears the city task")
	return true

func _title_click(local_x: float) -> void:
	var control := app.call("ui_control", "CityMap") as Control
	var actual: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * Vector2(local_x, 14))
	await _dispatch_mouse(actual, {"surface": "CityMapTitle"})

func _map_expanded(expanded: bool) -> void:
	var control := app.call("ui_control", "CityMap") as Control
	if control == null:
		return
	if expanded:
		if bool(control.get("_collapsed")):
			await _title_click(control.size.x * 0.5)
		elif bool(control.get("_detail")):
			await _title_click(control.size.x * 0.5)
	elif not bool(control.get("_collapsed")):
		await _title_click(control.size.x - 28)

func _full_map_move(point: Vector2) -> bool:
	await _map_expanded(true)
	var control := app.call("ui_control", "CityMap") as Control
	await _title_click(control.size.x * 0.5)
	check(bool(control.get("_detail")) and not bool(control.get("_collapsed")), "real header click opens the full reference map")
	await _capture("map_%02d_reference_full.png" % full_map_clicks, "actual expanded map shows the reference city before a route click")
	var started := Time.get_ticks_usec()
	if not await _raw_map_click(point):
		return false
	var accepted_after := Time.get_ticks_usec()
	check(not bool(control.get("_detail")), "legal full-map route click shrinks the map to keep the walking scene visible")
	full_map_clicks += 1
	var result := await _wait_walk(point, started)
	planning_samples.append({"destination": [point.x, point.y], "surface": "full_city_map", "input_dispatch_ms": float(accepted_after - started) / 1000.0, "complete_ms": float(Time.get_ticks_usec() - started) / 1000.0})
	await _map_expanded(false)
	return result

func _check_modal_input() -> bool:
	var before := _state()
	if not await _click("CityMenuButton"):
		return false
	await _raw_map_click(Vector2(2600, 2920))
	await _press_enter()
	for _frame: int in range(8):
		await process_frame
	check(_state() == before, "menu blocks a legal bridge route and Enter from acknowledging the paid result underneath")
	if not await _click("NewRunButton"):
		return false
	await _raw_map_click(Vector2(2600, 2920))
	await _press_enter()
	check(_state() == before, "confirmation blocks legal map walking and global Enter without replacing the run")
	return await _click("ConfirmCancelButton")

func _check_large_view() -> void:
	_sample_camera()
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var audit := _large_audit()
	check(all_camera_bounds_valid, "reference follow camera stays inside its real world bounds")
	check(audit.get("scene_size", Vector2.ZERO) == Vector2(5120, 3840), "reference world dimensions remain independent of the rendering window")
	check((stage.call("validate") as Array).is_empty(), "reference visible geometry agrees with real blocking footprints")
	var pack: Dictionary = app.call("_current_pack")
	var visible: Array = audit.get("visible_interaction_ids", [])
	check(visible.size() < pack.walks.scenes.chengdu_city.interactions.size(), "distant world labels stay offscreen")
	for id: String in visible:
		var raw: Array = pack.walks.scenes.chengdu_city.interactions[id].position
		var point := Vector2(float(raw[0]), float(raw[1]))
		var projected: Vector2 = stage.call("logical_to_screen", point, 0.0)
		check(Rect2(35, 35, 1210, 625).has_point(projected), "displayed target label belongs to visible ground: " + id)
		var local: Vector2 = walker.call("logical_to_local", point)
		var recovered: Vector2 = walker.call("local_to_logical", local)
		check(recovered.distance_to(point) < 1, "camera projection and actual input inverse agree: " + id)
	for key: String in ["player_screen", "player_head_screen"]:
		check(Rect2(0, 0, 1280, 720).has_point(audit.get(key, Vector2(-1, -1))), "followed character stays visible: " + key)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	frame_intervals_ms.sort()
	var total := 0.0
	for value: float in frame_intervals_ms:
		total += value
	var frame_report := {"sample_count": frame_intervals_ms.size(), "fps_cap": 60,
		"mean_ms": total / maxf(frame_intervals_ms.size(), 1),
		"p95_ms": frame_intervals_ms[int((frame_intervals_ms.size() - 1) * 0.95)] if not frame_intervals_ms.is_empty() else 0,
		"max_ms": frame_intervals_ms[-1] if not frame_intervals_ms.is_empty() else 0,
		"scope": "wall intervals during native QA walking including instrumentation; browser and physical-device performance unverified"}
	var report := {"test": "chengdu_reference_render", "checks": checks, "failures": failures, "failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y], "captures": captures, "external_input_trace": input_trace,
		"browser_refresh_checkpoint": refresh_checkpoint, "region_visits": region_visits,
		"full_map_clicks": full_map_clicks, "largest_camera_travel": largest_camera_distance,
		"camera_bounds_valid": all_camera_bounds_valid, "frame_time": frame_report,
		"map_click_timings": planning_samples, "walk_samples": _walk_samples,
		"display_server": DisplayServer.get_name(), "input_scope": "Godot mouse/key dispatch on an actual window; physical input unverified",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("chengdu-reference-render-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
	if app != null:
		root.remove_child(app)
		app.queue_free()
	await process_frame
	print("CHENGDU_REFERENCE_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
