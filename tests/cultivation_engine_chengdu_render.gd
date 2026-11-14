extends "res://tests/cultivation_engine_mentor_loop_render.gd"
## Native mouse-dispatch acceptance. Player checkpoints use a unique QA store.

const ChengduScene = preload("res://scenes/demos/cultivation_engine_chengdu.tscn")
var input_trace: Array[Dictionary] = []
var _trace_start := 0
var _walk_samples := 0


func _run() -> void:
	output_dir = "res://.local/qa/chengdu/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "city UI runs on an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	test_store_dir = "user://chengdu_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = ChengduScene.instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu" and _state().scene == "tingyu_corridor", "independent city pack begins in the original corridor")
	await _flow()
	_finish()


func _flow() -> bool:
	await _capture("00_corridor.png", "same-scene mentor and explicit city travel")
	if not await _click("ActionButton_talk_mentor"):
		return false
	for _line: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	if not await _click("ChoiceButton_take_lesson"):
		return false
	if not await _close_event():
		return false
	check(int(_state().stats.energy) == 92 and int(_state().slot) == 1, "mentor choice keeps its original cost")
	if not await _click("ActionButton_go_to_town"):
		return false
	check(_state().scene == "chengdu_gate" and int(_state().slot) == 2, "one travel action enters Chengdu from the west")
	await _capture("01_gate.png", "gate towers, city street and actual travel receipt")
	if not await _close_event():
		return false
	await _check_city_geometry()
	if not await _interact("gate_sign") or not await _close_event():
		return false
	if not await _interact("gate_market_exit") or not await _close_event():
		return false
	check(_state().scene == "chengdu_market", "east gate connects to the market")
	check(_state().exploration.positions.chengdu_market == [180, 480], "market entry preserves the arriving direction")
	await _capture("02_market.png", "market street with a visible teahouse entrance")
	await _check_city_geometry()
	if not await _interact("market_teahouse_door") or not await _close_event():
		return false
	check(_state().scene == "chengdu_teahouse", "walking to the door actually enters the shop")
	await _capture("03_teahouse.png", "walkable indoor tea tables and two separate people")
	await _check_city_geometry()
	if not await _interact("tea_keeper"):
		return false
	check(_state().phase == "event" and bool(_state().flags.chengdu_keeper_met), "walking near the keeper opens contextual choices")
	await _capture("04_keeper.png", "contextual encounter at the counter")
	if not await _click("ChoiceButton_see_rack"):
		return false
	if not await _click("CityMenuButton") or not await _click("NewRunButton"):
		return false
	var pending_confirmation := _state()
	input_trace.append({"type": "key", "key": "Space", "time_ms": Time.get_ticks_msec() - _trace_start})
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = pressed
		root.push_input(key)
		await process_frame
	check(_state() == pending_confirmation, "confirmation blocks Space from continuing the event underneath")
	if not await _click("ConfirmCancelButton") or not await _close_event():
		return false
	if not await _interact("tea_guest"):
		return false
	if not await _click("ChoiceButton_look_map") or not await _close_event():
		return false
	if not await _interact("tea_market_exit") or not await _close_event():
		return false
	check(_state().exploration.positions.chengdu_market == [640, 370], "leaving the shop returns to its actual doorway")
	if not await _interact("market_river_exit") or not await _close_event():
		return false
	await _capture("05_river.png", "riverfront with a distinct skyline and found umbrella")
	await _check_city_geometry()
	if not await _interact("river_umbrella") or not await _click("ChoiceButton_leave") or not await _close_event():
		return false
	check(not bool(_state().flags.chengdu_umbrella_taken), "declining the small errand leaves the umbrella available")
	if not await _interact("river_umbrella") or not await _click("ChoiceButton_take") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_carrying), "the deliberate choice picks up the umbrella once")
	check(not bool(_city_stage_audit().get("river_umbrella_visible", true)), "the picked umbrella actually disappears from the river hook")
	var carrying := _state()
	if not await _click("CityMenuButton"):
		return false
	var before_menu := _state()
	if not await _ground(Vector2(120, 480)):
		return false
	check(_state() == before_menu, "the open menu blocks all walking and spatial interaction")
	if not await _click("SaveButton"):
		return false
	await _capture("06_saved_menu.png", "safe checkpoint in the river lane while carrying the umbrella")
	if not await _click("CityMenuCloseButton"):
		return false
	await _capture("06a_saved_river.png", "browser reload acceptance checkpoint")
	# The browser replay reloads here and compares its real persisted state.
	if not await _interact("river_market_exit") or not await _close_event():
		return false
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(_state() == carrying, "loading restores the exact region, foot position, umbrella, clock and receipts")
	if not await _interact("river_market_exit") or not await _close_event():
		return false
	if not await _interact("market_teahouse_door") or not await _close_event():
		return false
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_return") or not await _close_event():
		return false
	check(bool(_state().flags.chengdu_umbrella_returned) and not bool(_state().flags.chengdu_umbrella_carrying), "returning the umbrella leaves one lasting city consequence")
	check(int(_state().counts.get("return_river_umbrella", 0)) == 1, "the return settles once")
	check(bool(_city_stage_audit().get("returned_umbrella_visible", false)), "the returned umbrella appears on the tea shop rack")
	await _capture("07_returned.png", "returned umbrella remains on the lost property stand")
	if not await _interact("tea_lost_property") or not await _click("ChoiceButton_revisit") or not await _close_event():
		return false
	check(int(_state().counts.get("return_river_umbrella", 0)) == 1, "revisiting does not settle again")
	check(int(_state().slot) == 2 and int(_state().stats.energy) == 92, "all city walking, visits, choices and reading preserve clock and resources")
	if not await _interact("tea_market_exit") or not await _close_event():
		return false
	if not await _interact("market_gate_exit") or not await _close_event():
		return false
	check(_state().exploration.positions.chengdu_gate == [1100, 480], "returning west enters the gate street from its east end")
	if not await _interact("gate_mountain_exit") or not await _close_event():
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().slot) == 3, "returning to the mentor charges only the original travel slot")
	if not await _click("ActionButton_go_to_mountain") or not await _close_event():
		return false
	if not await _click("ActionButton_pine_wind"):
		return false
	check(await _wait_for_phase("result", 1200), "original five-sword player completes normally after the city visit")
	if not await _close_event() or not await _click("ActionButton_return_to_corridor") or not await _close_event():
		return false
	check(int(_state().stats.sword) == 10 and int(_state().stats.energy) == 70, "city travel preserves original training and its single settlement")
	await _capture("08_mountain_return.png", "same cultivation session continues after the city")
	if not await _click("CityMenuButton") or not await _click("NewRunButton"):
		return false
	if not await _click("ConfirmAcceptButton"):
		return false
	check(_state().scene == "tingyu_corridor" and int(_state().stats.energy) == 100 and not bool(_state().flags.chengdu_umbrella_returned), "confirmed restart creates a fresh run and clears city memory")
	await _capture("09_restarted.png", "fresh run after explicit reset")
	return true


func _click(control_name: String) -> bool:
	var control: Control = await _fresh_control(control_name)
	if control != null:
		await _ensure_control_visible(control)
		var point: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
		input_trace.append({"type": "click", "control": control_name, "x": point.x, "y": point.y, "time_ms": Time.get_ticks_msec() - _trace_start})
	return await super._click(control_name)


func _ground(point: Vector2) -> bool:
	var walker := app.call("ui_control", "TownWalker") as Control
	if walker == null:
		check(false, "walking scene is present")
		return false
	var local: Vector2 = walker.call("logical_to_local", point)
	var actual: Vector2 = root.get_final_transform() * (walker.get_global_transform_with_canvas() * local)
	input_trace.append({"type": "click", "logical": [point.x, point.y], "x": actual.x, "y": actual.y, "time_ms": Time.get_ticks_msec() - _trace_start})
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


func _interact(id: String) -> bool:
	var pack: Dictionary = app.call("_current_pack")
	var map: Dictionary = pack.walks.scenes[_state().scene]
	var item: Dictionary = map.interactions[id]
	if not await _ground(Vector2(float(item.position[0]), float(item.position[1]))):
		return false
	var deadline := Time.get_ticks_msec() + 24000
	var safe := true
	var navigation = load("res://addons/cultivation_mode/town_navigation.gd").new()
	navigation.configure(map, false)
	var scene_id := str(_state().scene)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var state := _state()
		if state.scene != scene_id or state.phase != "ready":
			check(safe, "approach to " + id + " stays outside solid geometry")
			return true
		var at: Array = state.exploration.positions[scene_id]
		safe = safe and not navigation.blocked(Vector2(float(at[0]), float(at[1])))
		_walk_samples += 1
	check(false, "walking to " + id + " completes within its real-time bound")
	return false


func _close_event() -> bool:
	for _step: int in range(12):
		var phase := str(_state().get("phase", ""))
		if phase == "ready":
			return true
		if phase == "result":
			if not await _click("ResultContinueButton"):
				return false
		elif phase == "event" and _has_control("DialogContinueButton"):
			if not await _click("DialogContinueButton"):
				return false
		else:
			check(false, "reading has an explicit continue control")
			return false
	return false


func _check_city_geometry() -> void:
	await _check_layout("city", ["HeaderPanel", "ScenePanel", "CityMenuButton"])
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	check((stage.call("validate") as Array).is_empty(), "visible solids agree with navigation obstacles")
	var pack: Dictionary = app.call("_current_pack")
	for item: Dictionary in pack.walks.scenes[_state().scene].interactions.values():
		var point := Vector2(float(item.position[0]), float(item.position[1]))
		var local: Vector2 = walker.call("logical_to_local", point)
		var restored: Vector2 = walker.call("local_to_logical", local)
		check(Rect2(Vector2.ZERO, walker.size).has_point(local), "every actual street/NPC/door anchor stays visible")
		check(restored.distance_to(point) < 1.0, "projection preserves the actual interaction ground point")


func _city_stage_audit() -> Dictionary:
	var walker := app.call("ui_control", "TownWalker") as Control
	return walker.get("_stage").call("audit") if walker != null else {}


func _capture(filename: String, description: String) -> void:
	await super._capture(filename, description)
	input_trace.append({"type": "capture", "name": filename, "time_ms": Time.get_ticks_msec() - _trace_start})


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report := {"test": "chengdu_render", "checks": checks, "failures": failures, "failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y], "captures": captures, "external_input_trace": input_trace,
		"walk_samples": _walk_samples, "display_server": DisplayServer.get_name(), "result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("chengdu-render-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
	if app != null:
		root.remove_child(app)
		app.queue_free()
	await process_frame
	print("CHENGDU_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
