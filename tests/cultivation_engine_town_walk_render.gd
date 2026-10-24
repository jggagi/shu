extends "res://tests/cultivation_engine_mentor_loop_render.gd"

# Native rendered window, actual Godot mouse dispatch. This is not browser or
# physical-device evidence. Every checkpoint is written to a fresh QA folder.
const TownWalkScene := preload("res://scenes/demos/cultivation_engine_v04_town_walk.tscn")
const FLOOR := Rect2(60, 160, 1160, 490)
const BLOCKS := [Rect2(480, 330, 220, 150), Rect2(320, 175, 540, 95)]
var walked_samples: Array[Vector2] = []
var facings_seen: Array[String] = []


func _run() -> void:
	output_dir = "res://.local/qa/cultivation-engine-town-walk/render"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	check(DirAccess.make_dir_recursive_absolute(_absolute_output_dir()) == OK, "P1b capture directory is available")
	check(DisplayServer.get_name() != "headless", "P1b uses an actual native display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = TownWalkScene.instantiate() as Control
	root.add_child(app)
	await process_frame
	await process_frame
	test_store_dir = "user://town_walk_render_%d" % Time.get_ticks_usec()
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(test_store_dir)), "P1b allocates a fresh test-only checkpoint directory")
	app.get("_store").set("base_dir", test_store_dir)
	if await _click_sequence(["PackSelectButton_0", "PackStartButton_0"]):
		await _run_walk_flow()
	_finish()


func _click_sequence(names: Array[String]) -> bool:
	for control_name: String in names:
		if not await _click(control_name):
			return false
	return true


func _town() -> Dictionary:
	return _audit().get("town", {})


func _walker() -> Control:
	return app.call("ui_control", "TownWalker") as Control


func _ground_click(point: Vector2) -> bool:
	var walker: Control = _walker()
	if walker == null:
		check(false, "the rendered scene exposes its real TownWalker input surface")
		return false
	var local: Vector2 = walker.call("logical_to_local", point)
	var actual: Vector2 = root.get_final_transform() * (walker.get_global_transform_with_canvas() * local)
	var motion := InputEventMouseMotion.new()
	motion.position = actual
	motion.global_position = actual
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


func _position() -> Vector2:
	return _town().get("position", Vector2.ZERO)


func _position_safe(point: Vector2) -> bool:
	if not FLOOR.has_point(point):
		return false
	for block: Rect2 in BLOCKS:
		if block.grow(12.0).has_point(point):
			return false
	return true


func _wait_for_arrival(destination: Vector2, threshold: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + 18000
	var previous: Vector2 = _position()
	var route_length: float = 0.0
	var all_safe: bool = true
	var largest_step: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var current: Vector2 = _position()
		walked_samples.append(current)
		_record_facing()
		all_safe = all_safe and _position_safe(current)
		var step: float = previous.distance_to(current)
		route_length += step
		largest_step = maxf(largest_step, step)
		previous = current
		if current.distance_to(destination) <= threshold and (_town().get("route", []) as Array).is_empty():
			check(all_safe, "every rendered foot position stays on the floor and outside both solid buildings")
			check(largest_step < 70.0, "walking reaches its destination by continuous steps")
			check(route_length > 0.0, "the clicked destination produces real movement")
			return true
	check(false, "the clicked floor destination is reached within the bounded real-time wait")
	return false


func _wait_for_interaction(previous_count: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 18000
	var safe: bool = true
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _state().get("scene", "") != "shanxia_town":
			return true
		_record_facing()
		safe = safe and _position_safe(_position())
		if int(_town().get("interaction_count", 0)) > previous_count:
			check(safe, "the approach to the interaction respects solid obstacles")
			return true
	check(false, "walking close to the selected target completes one interaction")
	return false


func _record_facing() -> void:
	var facing: String = str(_town().get("facing", ""))
	if facing in ["up", "down", "left", "right"] and not facings_seen.has(facing):
		facings_seen.append(facing)


func _close_reading() -> bool:
	for _step: int in range(16):
		var phase: String = str(_state().get("phase", ""))
		if phase == "ready":
			return true
		if phase == "result":
			return await _click("ResultContinueButton")
		if phase == "event" and _has_control("DialogContinueButton"):
			if not await _click("DialogContinueButton"):
				return false
		else:
			check(false, "town reading exposes an ordinary continue control")
			return false
	check(false, "town reading finishes within its authored short interaction")
	return false


func _run_walk_flow() -> bool:
	check(_pack_id() == "shu_town_walk" and _state().get("scene", "") == "tingyu_corridor", "P1b starts in its own pack and original listening corridor")
	await _capture("00_corridor.png", "original corridor and explicit one-slot town travel")
	if not await _click("ActionButton_talk_mentor"):
		return false
	check(_button_disabled("ActionButton_go_to_town"), "mentor dialogue keeps travel behind the original busy gate")
	for _line: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	if not await _click_sequence(["ChoiceButton_take_lesson", "DialogContinueButton", "DialogContinueButton", "DialogContinueButton", "ResultContinueButton", "ActionButton_go_to_town"]):
		return false
	check(_state().get("scene", "") == "shanxia_town" and int(_state().get("slot", -1)) == 2, "one paid lesson and one outbound trip reach the town after two slots")
	check(int(_state().get("stats", {}).get("energy", -1)) == 92 and bool(_state().get("flags", {}).get("breathing_hint", false)), "travel preserves the lesson and its one-use bonus")
	await _capture("01_town_arrival.png", "full-body town avatar, town buildings and arrival result")
	if not await _click("ResultContinueButton"):
		return false
	await _check_layout("walkable town", ["HeaderPanel", "ScenePanel", "PhasePanel", "TownWalker"])
	var before_walk: Dictionary = _state()
	var initial_position: Vector2 = _position()
	check(initial_position.distance_to(Vector2(150, 560)) < 12.0, "a first visit starts at the declared town entry position")
	check(_position_safe(initial_position), "the town entry is on walkable ground")
	if not await _ground_click(Vector2(930, 300)):
		return false
	check((_town().get("route", []) as Array).size() > 1, "a click across the central obstacle plans a route with a detour")
	await _capture("02_obstacle_route.png", "walking around the central building toward the far side")
	if not await _wait_for_arrival(Vector2(930, 300)):
		return false
	check(_state().get("stats", {}) == before_walk.get("stats", {}) and _state().get("day", -1) == before_walk.get("day", -2) and _state().get("slot", -1) == before_walk.get("slot", -2), "ordinary walking spends no energy, growth or game time")
	check(_state().get("flags", {}) == before_walk.get("flags", {}), "ordinary floor walking does not invent story progress")
	await _capture("03_far_side.png", "the avatar has reached the other side of the building")
	var before_talk: Dictionary = _state()
	var talk_count: int = int(_town().get("interaction_count", 0))
	if not await _ground_click(Vector2(1010, 350)):
		return false
	check(int(_town().get("interaction_count", 0)) == talk_count, "a distant NPC click queues an approach before interaction")
	if not await _ground_click(Vector2(1010, 350)) or not await _wait_for_interaction(talk_count):
		return false
	check(int(_town().get("interaction_count", 0)) == talk_count + 1, "repeated NPC clicks produce a single close-range interaction")
	check(bool(_state().get("flags", {}).get("town_tea_greeted", false)), "the first NPC greeting records a persistent host-owned flag")
	check(_position().distance_to(Vector2(1010, 350)) <= 70.0, "NPC reading begins only inside its visible approach range")
	check(_state().get("stats", {}) == before_talk.get("stats", {}) and _state().get("slot", -1) == before_talk.get("slot", -2), "town conversation and reading keep the game clock and attributes")
	var busy_state: Dictionary = _state()
	if not await _ground_click(Vector2(160, 260)):
		return false
	await process_frame
	check(_state() == busy_state, "a target click during an active reading result cannot start another trip or mutate state")
	await _capture("04_npc_reading.png", "close-range NPC response with unchanged game time")
	if not await _close_reading() or not await _click("SaveButton"):
		return false
	var checkpoint: Dictionary = _state()
	var saved_position: Vector2 = _position()
	check(checkpoint.get("exploration", {}).get("positions", {}).has("shanxia_town"), "the safe checkpoint includes the session-owned town position")
	var sign_count: int = int(_town().get("interaction_count", 0))
	if not await _ground_click(Vector2(710, 560)) or not await _wait_for_interaction(sign_count) or not await _close_reading():
		return false
	check(bool(_state().get("flags", {}).get("town_sign_read", false)), "approaching the street sign records its readable-object flag")
	await _capture("05_street_sign.png", "town object is inspected after walking close")
	if not await _click_sequence(["LoadButton", "ConfirmAcceptButton"]):
		return false
	check(await _wait_for_snapshot(checkpoint, 90), "loading restores exact position, date, attributes, flags, counts and receipts")
	check(_position().distance_to(saved_position) < 2.0 and (_town().get("route", []) as Array).is_empty(), "restoration places the avatar at the saved feet without replaying its old route")
	await _capture("06_position_restored.png", "saved town position and safe context restored")
	var revisit_count: int = int(_town().get("interaction_count", 0))
	if not await _ground_click(Vector2(1010, 350)) or not await _wait_for_interaction(revisit_count):
		return false
	check(str(_state().get("last_result", {}).get("action_id", "")) == "greet_tea_seller_again", "the restored greeting flag selects the NPC's remembered response on a later visit")
	check(_state().get("stats", {}) == checkpoint.get("stats", {}) and _state().get("slot", -1) == checkpoint.get("slot", -2), "the remembered response remains free")
	if not await _close_reading():
		return false
	var before_return: Dictionary = _state()
	var return_count: int = int(_town().get("interaction_count", 0))
	if not await _ground_click(Vector2(160, 260)):
		return false
	check(_state().get("scene", "") == "shanxia_town" and _state().get("slot", -1) == before_return.get("slot", -2), "a distant exit click waits for approach before settling travel")
	if not await _ground_click(Vector2(160, 260)) or not await _wait_for_interaction(return_count):
		return false
	check(_state().get("scene", "") == "tingyu_corridor" and int(_state().get("slot", -1)) == 3, "the approached exit returns to the corridor and charges one further slot")
	check(_state().get("stats", {}) == before_return.get("stats", {}) and bool(_state().get("flags", {}).get("town_returned", false)), "return retains growth and records the host's return flag")
	check(int(_state().get("counts", {}).get("return_from_town", -1)) == 1, "repeated exit clicks settle the return once")
	check(facings_seen.size() == 4, "the actual clicked routes exercise up, down, left and right full-body movement")
	await _capture("07_returned_corridor.png", "original corridor after spatial town exit")
	if not await _click_sequence(["ResultContinueButton", "ActionButton_go_to_mountain", "ResultContinueButton", "ActionButton_pine_wind"]):
		return false
	check(_state().get("phase", "") == "performing" and _button_disabled("SaveButton"), "original sword performance and save gate remain after returning")
	await _capture("08_sword_after_walk.png", "original fixed-model sword action still plays")
	if not await _wait_for_phase("result", 240):
		check(false, "the original real sword presenter finishes normally")
		return false
	check(int(_state().get("stats", {}).get("energy", -1)) == 70 and int(_state().get("stats", {}).get("cultivation", -1)) == 6 and int(_state().get("stats", {}).get("sword", -1)) == 10, "the original sword spends 22 energy and consumes the saved lesson bonus once")
	if not await _click_sequence(["ResultContinueButton", "ActionButton_return_to_corridor", "ResultContinueButton", "ActionButton_report_practice", "ChoiceButton_with_lesson", "DialogContinueButton", "DialogContinueButton", "DialogContinueButton", "ResultContinueButton", "ActionButton_rest_practice", "ResultContinueButton", "SaveButton"]):
		return false
	var returned_checkpoint: Dictionary = _state()
	check(bool(returned_checkpoint.get("flags", {}).get("mentor_reported", false)), "the original mentor report remains completable after spatial exploration")
	if not await _click_sequence(["SwitchPackButton", "PackSelectButton_1", "PackStartButton_1", "ConfirmAcceptButton", "SaveButton", "SwitchPackButton", "PackSelectButton_0", "PackContinueButton_0"]):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(await _wait_for_snapshot(returned_checkpoint, 90), "saving the independent Stream pack preserves the full Shu checkpoint")
	await _capture("09_isolated_continuation.png", "Shu progress restored after using the separate Stream pack")
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var samples: Array = []
	for point: Vector2 in walked_samples:
		samples.append([point.x, point.y])
	var report: Dictionary = {"test": "cultivation_engine_town_walk_render", "checks": checks, "failures": failures, "failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "captures": captures, "walked_samples": samples, "facings_seen": facings_seen, "result": "PASS" if failures == 0 else "FAIL", "input_method": "Godot root.push_input; not OS physical input or browser"}
	var file := FileAccess.open(_absolute_output_dir().path_join("cultivation-engine-town-walk-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CULTIVATION_ENGINE_TOWN_WALK_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
