extends "res://tests/cultivation_first_journey_render.gd"
## Full real-input chapter: 1152 completes the four-round win; 960 withdraws.
## Both routes retain the original host, actual practice, ending and save tests.

var unified_evidence: Dictionary = {}
var browser_trace: Array[Dictionary] = []


func _run() -> void:
	_parse_user_args()
	expected_victory = qa_size.x >= 1000
	await super._run()


func _trace(kind: String, value: Dictionary) -> void:
	var entry := value.duplicate(true)
	entry["type"] = kind
	entry["time_ms"] = Time.get_ticks_msec()
	browser_trace.append(entry)


func _click(control_name: String) -> bool:
	var control := await _fresh_control(control_name)
	if control == null:
		return false
	var point := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	_trace("click", {"name": control_name, "x": point.x, "y": point.y})
	return await super._click(control_name)


func _raw_click(canvas_point: Vector2) -> void:
	var point := root.get_final_transform() * canvas_point
	_trace("click", {"name": "overlay_block_check", "x": point.x, "y": point.y})
	await super._raw_click(canvas_point)


func _key_escape() -> void:
	_trace("key", {"key": "Escape"})
	await super._key_escape()


func _capture(filename: String, description: String) -> void:
	_trace("capture", {"name": filename, "description": description})
	await super._capture(filename, description)


func _walker() -> Control:
	return app.call("ui_control", "TownWalker") as Control


func _camera() -> Dictionary:
	return _walker().call("camera_audit") if is_instance_valid(_walker()) else {}


func _wait_zoom(target: float) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while is_instance_valid(_walker()) and absf(float(_camera().get("zoom", 0.0)) - target) > 0.001 and Time.get_ticks_msec() < deadline:
		await process_frame
	return _expect(is_instance_valid(_walker()) and absf(float(_camera().get("zoom", 0.0)) - target) <= 0.001, "real camera reaches the expected bounded view " + str(target))


func _walk_to_interaction(id: String) -> bool:
	if id == "tea_seller":
		var stage: Node = _walker().get("_stage")
		var painting: Node = stage.get("_painted_street")
		if not _expect(is_instance_valid(painting), "the actual journey stage contains the painted-street adapter"):
			return false
		var hero: Node = painting.get("_volume_character")
		var cast: Node = painting.get("_volume_cast")
		check(is_instance_valid(hero) and hero.find_children("*", "MeshInstance3D", true, false).size() >= 3, "the same chapter renders the actual skinned hero meshes")
		check(is_instance_valid(cast) and cast.find_children("*", "MeshInstance3D", true, false).size() >= 18, "the same chapter renders both volumetric NPCs")
		var before: Dictionary = _state()
		if not await _click("CameraZoomInButton") or not await _click("CameraZoomInButton"):
			return false
		check(absf(float(_camera().zoom) - 1.1) < 0.001 and _state() == before, "explicit zoom changes no journey date, progress or receipts")
		await _capture("03a_zoomed_street.png", "the chapter's actual new town before walking to its commission")
	elif id == "mountain_exit":
		check(absf(float(_camera().get("zoom", 0.0)) - 1.0) < 0.001, "returning from the battle starts with the complete street view")
	var target: Array = app.get("_session").pack.walks.scenes[_state().scene].interactions[id].position
	var local: Vector2 = _walker().call("logical_to_local", Vector2(target[0], target[1]))
	var click_point := root.get_final_transform() * (_walker().get_global_transform_with_canvas() * local)
	_trace("click", {"name": "TownWalker:" + id, "x": click_point.x, "y": click_point.y})
	if not await super._walk_to_interaction(id):
		return false
	if id == "tea_seller":
		check(str(_camera().get("focus_role", "")) == "tea_seller", "the original commission receipt focuses its actual nearby partner")
		if not await _wait_zoom(1.2):
			return false
		unified_evidence["commission_camera"] = _camera()
		await _capture("03b_commission_focus.png", "the existing escort commission is readable in the painted street")
	return true


func _close_result() -> bool:
	var focused: bool = _state().get("scene", "") == "shanxia_town" and str(_camera().get("focus_role", "")) == "tea_seller"
	if not await super._close_result():
		return false
	if focused:
		return await _wait_zoom(1.1)
	return true


func _check_default_page(label: String) -> void:
	await super._check_default_page(label)
	if label != "commission accepted":
		return
	var before: Dictionary = _state()
	var view := _camera()
	if not await _click("MenuButton") or not await _click("StreetMotionButton"):
		return
	check(not bool(_audit().get("street_motion", true)) and _state() == before, "the unified menu freezes street motion without a game action")
	if not await _click("StreetMotionButton") or not await _click("SaveButton") or not await _close_journey_menu():
		return
	check(_state() == before and absf(float(_camera().zoom) - float(view.zoom)) < 0.001, "a real town save and menu rebuild preserve progress and temporary camera")
	if not await _click("MenuButton") or not await _click("LoadButton") or not await _click("ConfirmAcceptButton") or not await _close_journey_menu():
		return
	check(_state() == before, "actual town checkpoint loading restores the exact existing journey state")
	check(absf(float(_camera().zoom) - float(view.zoom)) < 0.001, "same-run same-town loading retains its current temporary view")
	await _capture("04a_town_checkpoint.png", "commission and new town survive actual menu save and load")


func _resolve_journey_encounter() -> bool:
	if not expected_victory:
		return await super._resolve_journey_encounter()
	for command: Array in [
		["Unit_player"], ["Skill_push"], [4, 3], [4, 3],
		["Unit_tinglan"], ["Skill_interrupt"], [5, 4], ["EndRoundButton"],
		["Unit_player"], ["Skill_push"], [5, 3], [6, 3],
		["Unit_tinglan"], ["Skill_interrupt"], [5, 4], ["EndRoundButton"],
		["Unit_player"], ["Skill_push"], [7, 3], [7, 3],
		["Unit_tinglan"], ["Skill_strike"], [5, 4], ["EndRoundButton"],
		["Unit_player"], ["Skill_strike"], [8, 3], ["EndRoundButton"]
	]:
		if command.size() == 1:
			if not await _click(str(command[0])):
				return false
		else:
			var point: Vector2 = _battle_view().call("audit_tile_center", command)
			await _battle_tile(point)
		if not await _battle_idle():
			return false
	var battle: Dictionary = _battle_view().call("audit_snapshot").battle
	if not _expect(battle.phase == "won" and int(battle.objective.hp) > 0, "actual four-round mouse play protects the medicine and wins"):
		return false
	unified_evidence["actual_win"] = battle
	await _capture("05a_actual_victory.png", "the same chapter completes the real escort battle")
	return await _click("ReturnButton")


func _battle_tile(point: Vector2) -> void:
	var physical := root.get_final_transform() * point
	_trace("click", {"name": "BattleTile", "x": physical.x, "y": physical.y})
	var motion := InputEventMouseMotion.new()
	motion.position = physical
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = physical
		event.global_position = physical
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _battle_idle() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	for frame: int in range(3):
		await process_frame
	while is_instance_valid(_battle_view()) and bool(_battle_view().call("audit_snapshot").busy) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	await process_frame
	return _expect(not is_instance_valid(_battle_view()) or not bool(_battle_view().call("audit_snapshot").busy), "real combat presentation releases input within its deadline")


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report := {"test": "unified_first_journey", "checks": checks, "failures": failures,
		"failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y],
		"expected_victory": expected_victory, "captures": captures, "route_checkpoints": route_checkpoints,
		"unified_evidence": unified_evidence, "input_actions": input_actions, "layout_measurements": layout_measurements,
		"external_input_trace": browser_trace,
		"input_method": "Actual Godot root.push_input; no state injection or fabricated battle outcome",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("unified-journey-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("UNIFIED_JOURNEY_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)
