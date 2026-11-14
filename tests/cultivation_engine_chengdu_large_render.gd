extends "res://tests/cultivation_engine_chengdu_render.gd"
## Real mouse/key dispatch through the scene and the clickable city map. No
## camera, actor-position, Session-state, or game click_at calls are injected.

const LargeScenePath := "res://scenes/demos/cultivation_engine_chengdu_large.tscn"
const LargeLayout := "res://assets/data/chengdu-large-layout.json"
var large_layout: Dictionary = {}
var region_visits: Array[String] = []
var refresh_checkpoint: Dictionary = {}
var frame_intervals_ms: Array[float] = []
var planning_samples: Array[Dictionary] = []
var initial_camera := Vector2.ZERO
var largest_camera_distance := 0.0
var all_camera_bounds_valid := true

func _run() -> void:
	output_dir = "res://.local/qa/chengdu-large/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "large-world native acceptance uses an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LargeLayout))
	large_layout = layout.scenes.chengdu_city
	test_store_dir = "user://chengdu_large_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(LargeScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_large" and _state().scene == "tingyu_corridor", "large candidate starts in an isolated original cultivation scene")
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
	check(int(_state().stats.energy) == 92 and int(_state().slot) == 1, "original same-scene mentor choice retains its cost and outcome")
	if not await _click("ActionButton_go_to_town"):
		return false
	check(_state().scene == "chengdu_city" and _state().phase == "result", "paid journey retains its explicit result at the large-world entrance")
	if not await _check_modal_input() or not await _close_event():
		return false
	var initial := _state()
	initial_camera = _large_audit().get("camera_center", Vector2.ZERO)
	# City-map clicks are real surface input. The walking controller still plans
	# and follows every route while the world camera continuously follows it.
	for region: Dictionary in large_layout.regions:
		var point := Vector2(float(region.visit_point[0]), float(region.visit_point[1]))
		if not await _map_move(point):
			return false
		region_visits.append(str(region.id))
		check(_state().scene == "chengdu_city" and _state().counts == initial.counts and _state().sequence == initial.sequence and _state().slot == initial.slot and _state().stats == initial.stats, "actual travel between outdoor districts settles no action, scene change or game time")
		var location := app.call("ui_control", "CityLocationLabel") as Label
		check(location != null and location.text.contains(str(region.label)), "current district label follows the actual world position: " + str(region.id))
		await _check_large_view()
		await _capture("01_region_" + str(region.id) + ".png", "actual continuous walking and follow camera in " + str(region.label))
	check(region_visits.size() == 5 and largest_camera_distance > 1200.0, "five regions share one continuous map while the camera moves across the larger world")
	# Also click visible main-scene stone ground, excluding the minimap overlay.
	if not await _visible_ground_step():
		return false
	if not await _large_interact("river_umbrella") or not await _click("ChoiceButton_take") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_carrying), "the actual river choice collects the umbrella once")
	var saved := _state()
	if not await _click("CityMenuButton") or not await _click("SaveButton") or not await _click("CityMenuCloseButton"):
		return false
	# UI re-creation leaves the map expanded, matching a real refresh/continue.
	refresh_checkpoint = {"capture": "02_large_saved_river.png", "state": saved,
		"scene": "chengdu_city", "position": saved.exploration.positions.chengdu_city,
		"expected_flags": saved.flags, "map_collapsed": false}
	await _capture("02_large_saved_river.png", "real save/refresh point in the large river district while carrying the umbrella")
	for point: Vector2 in [Vector2(3280, 1020), Vector2(2720, 1020), Vector2(1940, 1020)]:
		if not await _map_move(point):
			return false
	if not await _large_interact("lanes_teahouse_door"):
		return false
	check(_state().scene == "chengdu_teahouse" and _state().exploration.positions.chengdu_teahouse == [640, 240], "actual back doorway enters the existing tea interior from its north side")
	if not await _close_event():
		return false
	await _check_city_geometry()
	await _capture("03_large_rear_door.png", "north street enters the tea shop through its real back doorway")
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_return") or not await _close_event():
		return false
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_revisit") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_returned) and int(_state().counts.get("return_river_umbrella", 0)) == 1, "return and revisit preserve exactly one completed umbrella consequence")
	await _capture("04_large_umbrella_returned.png", "the umbrella is physically back on the stand after the alternate outdoor route")
	if not await _interact("tea_market_exit") or not await _close_event():
		return false
	check(_state().scene == "chengdu_city" and _state().exploration.positions.chengdu_city == [1600, 1540], "front door returns to a different point in the same large outdoor scene")
	await _check_large_view()
	await _capture("04a_large_front_door.png", "leaving the same tea interior through its front door returns to the market side of the continuous outdoor world")
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(_state() == saved, "actual load after walking far away and returning the umbrella restores the exact far position and earlier carried state")
	await _capture("05_large_checkpoint_restored.png", "the river checkpoint restores exact world coordinates, resources, task flags and receipts")
	if not await _map_move(Vector2(440, 1760)) or not await _large_interact("gate_mountain_exit") or not await _close_event():
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().slot) == 3 and int(_state().stats.energy) == 92, "return to the original mentor charges only the original one-slot travel fee")
	if not await _click("CityMenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().stats.energy) == 100 and not bool(_state().flags.chengdu_umbrella_carrying), "confirmed reset restores a genuine fresh cultivation and city run")
	await _capture("06_large_restarted.png", "explicit reset clears the large-world task and keeps the original cultivation entry")
	return true

func _raw_map_click(point: Vector2) -> bool:
	var control := app.call("ui_control", "CityMap") as Control
	if control == null:
		check(false, "clickable city map is available")
		return false
	var local: Vector2 = control.call("logical_to_local", point)
	var actual: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
	return await _dispatch_mouse(actual, {"surface": "CityMap", "logical": [point.x, point.y]})

func _dispatch_mouse(actual: Vector2, metadata: Dictionary) -> bool:
	var record := metadata.duplicate()
	record.merge({"type": "click", "x": actual.x, "y": actual.y, "time_ms": Time.get_ticks_msec() - _trace_start}, true)
	input_trace.append(record)
	var motion := InputEventMouseMotion.new()
	motion.position = actual
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = actual
		event.global_position = actual
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	return true

func _map_expanded(expanded: bool) -> void:
	var control := app.call("ui_control", "CityMap") as Control
	if control == null or bool(control.get("_collapsed")) != expanded:
		return
	var actual: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * Vector2(control.size.x * 0.5, 14))
	await _dispatch_mouse(actual, {"surface": "CityMapTitle"})

func _map_move(point: Vector2) -> bool:
	await _map_expanded(true)
	var started := Time.get_ticks_usec()
	if not await _raw_map_click(point):
		return false
	var accepted_after := Time.get_ticks_usec()
	var result := await _wait_walk(point, started)
	planning_samples.append({"destination": [point.x, point.y], "input_dispatch_ms": float(accepted_after - started) / 1000.0,
		"complete_ms": float(Time.get_ticks_usec() - started) / 1000.0})
	await _map_expanded(false)
	return result

func _wait_walk(goal: Vector2, started: int) -> bool:
	var deadline := Time.get_ticks_msec() + 65000
	var previous_tick := Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_intervals_ms.append(float(now - previous_tick) / 1000.0)
		previous_tick = now
		var state := _state()
		if state.scene != "chengdu_city" or state.phase != "ready":
			check(false, "map ground click must not trigger a hidden interaction or leave the outdoor scene")
			return false
		var at := Vector2(float(state.exploration.positions.chengdu_city[0]), float(state.exploration.positions.chengdu_city[1]))
		_walk_samples += 1
		if _walk_samples % 6 == 0:
			_sample_camera()
		var walker := app.call("ui_control", "TownWalker") as Control
		if at.distance_to(goal) <= 3.0 and (walker.get("route") as Array).is_empty():
			for _settle: int in range(12):
				await process_frame
			_sample_camera()
			check(true, "actual map click reaches its far ground destination in %.2fs" % (float(now - started) / 1000000.0))
			return true
	check(false, "actual far-ground walking completes within its real-time bound")
	return false

func _large_interact(id: String) -> bool:
	var pack: Dictionary = app.call("_current_pack")
	var item: Dictionary = pack.walks.scenes.chengdu_city.interactions[id]
	var target := Vector2(float(item.position[0]), float(item.position[1]))
	var state := _state()
	var nav = load("res://addons/cultivation_mode/town_navigation.gd").new()
	nav.configure(pack.walks.scenes.chengdu_city)
	var at := Vector2(float(state.exploration.positions.chengdu_city[0]), float(state.exploration.positions.chengdu_city[1]))
	var path: Array = nav.route(at, target, 190.0)
	check(not path.is_empty(), "real navigation supplies a safe nearby view of " + id)
	if path.is_empty() or not await _map_move(path[-1]):
		return false
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	check(bool(stage.call("is_target_visible", id)), "target is actually visible before its main-scene click: " + id)
	return await _interact(id)

func _visible_ground_step() -> bool:
	var walker := app.call("ui_control", "TownWalker") as Control
	var pack: Dictionary = app.call("_current_pack")
	var state := _state()
	var at := Vector2(float(state.exploration.positions.chengdu_city[0]), float(state.exploration.positions.chengdu_city[1]))
	var nav = load("res://addons/cultivation_mode/town_navigation.gd").new()
	nav.configure(pack.walks.scenes.chengdu_city, false)
	for offset: Vector2 in [Vector2(100, 0), Vector2(-100, 0), Vector2(0, 100), Vector2(0, -100)]:
		var goal := at + offset
		if not nav.clear_segment(at, goal):
			continue
		var local: Vector2 = walker.call("logical_to_local", goal)
		if not Rect2(Vector2(40, 40), walker.size - Vector2(80, 80)).has_point(local):
			continue
		var global := walker.get_global_transform_with_canvas() * local
		var city_map := app.call("ui_control", "CityMap") as Control
		if city_map != null and city_map.get_global_rect().has_point(global):
			continue
		var near_interaction := false
		for item: Dictionary in pack.walks.scenes.chengdu_city.interactions.values():
			near_interaction = near_interaction or goal.distance_to(Vector2(float(item.position[0]), float(item.position[1]))) < 130
		if near_interaction:
			continue
		var started := Time.get_ticks_usec()
		if not await _ground(goal):
			return false
		return await _wait_walk(goal, started)
	check(false, "a safe visible main-scene ground point exists outside the minimap overlay")
	return false

func _large_audit() -> Dictionary:
	var walker := app.call("ui_control", "TownWalker") as Control
	return walker.get("_stage").call("audit") if walker != null else {}

func _sample_camera() -> void:
	var audit := _large_audit()
	var center: Vector2 = audit.get("camera_center", Vector2.ZERO)
	largest_camera_distance = maxf(largest_camera_distance, center.distance_to(initial_camera))
	var limits: Array = audit.get("camera_limits", [])
	all_camera_bounds_valid = all_camera_bounds_valid and limits.size() == 4
	if limits.size() == 4:
		all_camera_bounds_valid = all_camera_bounds_valid and center.x >= float(limits[0]) - 0.1 and center.x <= float(limits[2]) + 0.1 and center.y >= float(limits[1]) - 0.1 and center.y <= float(limits[3]) + 0.1

func _check_large_view() -> void:
	_sample_camera()
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var audit := _large_audit()
	check(all_camera_bounds_valid, "actual follow camera remains inside its authored world bounds")
	check(audit.get("scene_size", Vector2.ZERO) == Vector2(3840, 2160), "render window is independent of the larger scene size")
	check((stage.call("validate") as Array).is_empty(), "large-world visible solids remain consistent with authored navigation")
	var pack: Dictionary = app.call("_current_pack")
	var visible: Array = audit.get("visible_interaction_ids", [])
	check(visible.size() < pack.walks.scenes.chengdu_city.interactions.size(), "offscreen labels are excluded instead of overlaying every world interaction")
	for id: String in visible:
		var raw: Array = pack.walks.scenes.chengdu_city.interactions[id].position
		var point := Vector2(float(raw[0]), float(raw[1]))
		var projected: Vector2 = stage.call("logical_to_screen", point, 0.0)
		check(Rect2(35, 35, 1210, 625).has_point(projected), "drawn target label belongs to currently visible ground: " + id)
		var local: Vector2 = walker.call("logical_to_local", point)
		var recovered: Vector2 = walker.call("local_to_logical", local)
		check(recovered.distance_to(point) < 1.0, "follow-camera interaction projection and input inverse agree: " + id)
	var player_screen: Vector2 = audit.get("player_screen", Vector2(-1, -1))
	check(Rect2(0, 0, 1280, 720).has_point(player_screen), "the followed player remains inside the actual render window")

func _press_enter() -> void:
	input_trace.append({"type": "key", "key": "Enter", "time_ms": Time.get_ticks_msec() - _trace_start})
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = pressed
		root.push_input(key)
		await process_frame

func _check_modal_input() -> bool:
	var before := _state()
	if not await _click("CityMenuButton"):
		return false
	await _raw_map_click(Vector2(1940, 1700))
	await _press_enter()
	for _frame: int in range(8):
		await process_frame
	check(_state() == before, "open menu blocks minimap walking and Enter from acknowledging the paid result underneath")
	if not await _click("NewRunButton"):
		return false
	await _raw_map_click(Vector2(1940, 1700))
	await _press_enter()
	check(_state() == before, "confirmation blocks both minimap and global Enter without replacing or advancing the run")
	return await _click("ConfirmCancelButton")

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	frame_intervals_ms.sort()
	var frame_sum := 0.0
	for value: float in frame_intervals_ms:
		frame_sum += value
	var frame_report := {"sample_count": frame_intervals_ms.size(), "fps_cap": 60,
		"mean_ms": frame_sum / maxf(frame_intervals_ms.size(), 1),
		"p95_ms": frame_intervals_ms[int((frame_intervals_ms.size() - 1) * 0.95)] if not frame_intervals_ms.is_empty() else 0,
		"max_ms": frame_intervals_ms[-1] if not frame_intervals_ms.is_empty() else 0,
		"scope": "wall intervals sampled during this native QA walking, including instrumentation; no browser or device performance claim"}
	var report := {"test": "chengdu_large_render", "checks": checks, "failures": failures, "failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y], "captures": captures, "external_input_trace": input_trace,
		"browser_refresh_checkpoint": refresh_checkpoint, "region_visits": region_visits,
		"largest_camera_travel": largest_camera_distance, "camera_bounds_valid": all_camera_bounds_valid,
		"frame_time": frame_report, "map_click_timings": planning_samples, "walk_samples": _walk_samples,
		"display_server": DisplayServer.get_name(), "input_scope": "Godot mouse/key dispatch on real window, including city-map clicks; physical devices unverified",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("chengdu-large-render-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
	if app != null:
		root.remove_child(app)
		app.queue_free()
	await process_frame
	print("CHENGDU_LARGE_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
