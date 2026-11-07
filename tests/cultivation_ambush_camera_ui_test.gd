extends "res://tests/cultivation_martial_workshop_ui_test.gd"
## Real root pointer input against the shipped battle and modal workshop.
## Focus loss uses the lifecycle notification separately labelled in the report.
var _camera_trials: Array[Dictionary] = []
var _default_camera: Dictionary = {}


func _run() -> void:
	output = "res://.local/qa/ambush-camera/ui"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--qa-size="):
			var dimensions := argument.trim_prefix("--qa-size=").split("x")
			qa_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(DisplayServer.get_name() != "headless", "Camera controls use the actual native Compatibility renderer")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("camera-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The real two-versus-three encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	_default_camera = _camera(_stage()).duplicate(true)
	_check(bool(_ca().get("is_default", false)) and bool(_ca().get("input_enabled", false)), "A fresh battle starts in its original enabled tactical camera")
	_check_camera_bounds()
	_check_projection(true)
	await _capture("00-camera-default.png")
	await _orbit_and_cancel()
	await _zoom_and_ui_isolation()
	await _release_lifecycle()
	await _click("CameraResetButton")
	_check(_camera(_stage()) == _default_camera and bool(_ca().get("is_default", false)), "The visible reset button restores the exact original transform and orthographic size")
	await _drag(_board_point(), Vector2(48, -24), MOUSE_BUTTON_MIDDLE)
	await _transformed_targeting()
	await _click("RestartButton")
	_check(_camera(_stage()) == _default_camera and bool(_ca().get("is_default", false)), "Restart constructs the exact default tactical camera rather than retaining a stale drag")
	await _drag(_board_point(), Vector2(-58, 24), MOUSE_BUTTON_RIGHT)
	await _wheel(_board_point(), MOUSE_BUTTON_WHEEL_UP, 1)
	await _action_restore()
	await _workshop_independence()
	await _inspector_and_resize()
	await _click("CameraResetButton")
	_check(_camera(_stage()) == _default_camera and bool(_ca().get("is_default", false)), "Reset also restores the exact original camera after combat and the independent workshop")
	await _capture("08-camera-reset.png")
	var old_viewport: WeakRef = weakref(_stage().get("viewport"))
	var sequence := int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_viewport.get_ref() == null, "Returning releases the camera viewport and pointer owner")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Returning keeps the original host and settles the unfinished encounter exactly once")
	await _capture("09-camera-return-town.png")
	_finish()


func _stage() -> Control:
	return _view().get("_stage") as Control


func _ca() -> Dictionary:
	return (_stage().call("audit") as Dictionary).get("camera_control", {}).duplicate(true)


func _authority() -> Dictionary:
	return {"battle": _battle().duplicate(true), "host": app.get("_session").snapshot().duplicate(true)}


func _user_camera() -> Dictionary:
	var data := _ca()
	return {"yaw": data.get("yaw_degrees"), "pitch": data.get("pitch_degrees"), "zoom": data.get("zoom"), "transform": data.get("user_transform")}


func _board_point() -> Vector2:
	return _stage().get_global_transform_with_canvas() * (_stage().size * 0.5)


func _orbit_and_cancel() -> void:
	await _click("Skill_strike")
	var authority := _authority()
	var before := _camera(_stage())
	await _button_pair(_board_point(), MOUSE_BUTTON_RIGHT)
	_check(str(_view().audit_snapshot().action) == "move" and _camera(_stage()) == before, "A short right click cancels the selected skill without moving the camera")
	await _click("Skill_strike")
	await _drag(_board_point(), Vector2(75, -28), MOUSE_BUTTON_RIGHT)
	var first := _ca()
	_check(float(first.get("yaw_degrees", 0)) > 0 and float(first.get("pitch_degrees", 0)) > 0 and _camera(_stage()) != before, "Dragging right and upward actually orbits and raises the battle view")
	_check(str(_view().audit_snapshot().action) == "strike", "A real right drag keeps the selected skill instead of treating release as cancellation")
	_check(_authority() == authority, "Right-click cancellation and orbit spend no movement, action, HP, round, medicine or host time")
	_check_camera_bounds()
	_check_projection(false)
	await _capture("01-camera-right-raised.png")
	await _drag(_board_point(), Vector2(-140, 55), MOUSE_BUTTON_MIDDLE)
	_check(float(_ca().get("yaw_degrees", 0)) < 0 and float(_ca().get("pitch_degrees", 0)) < float(first.pitch_degrees), "A middle-button drag rotates in the opposite direction and changes pitch")
	_check(str(_view().audit_snapshot().action) == "strike" and _authority() == authority, "Middle-button orbit keeps the active skill and all authoritative state")
	_check_camera_bounds()
	_check_projection(false)
	await _capture("02-camera-left-lowered.png")
	_camera_trials.append({"kind": "orbit_and_cancel", "first": first, "second": _ca(), "authority_unchanged": _authority() == authority})


func _zoom_and_ui_isolation() -> void:
	var authority := _authority()
	await _wheel(_board_point(), MOUSE_BUTTON_WHEEL_UP, 30)
	_check_camera_bounds()
	var near := _ca()
	_check(absf(float(near.zoom) - float(near.zoom_limits[0])) < 0.000001, "Repeated wheel-up clamps at the declared close-view limit")
	await _capture("03-camera-close-limit.png")
	await _wheel(_board_point(), MOUSE_BUTTON_WHEEL_DOWN, 45)
	_check_camera_bounds()
	var far := _ca()
	_check(absf(float(far.zoom) - float(far.zoom_limits[1])) < 0.000001 and float(far.camera_size) > float(near.camera_size), "Repeated wheel-down clamps at the far limit and visibly expands the orthographic view")
	await _capture("04-camera-far-limit.png")
	var ui: Control = _view().ui_control("EndRoundButton")
	var ui_point := ui.get_global_transform_with_canvas() * (ui.size * 0.5)
	var user_before := _user_camera()
	await _wheel(ui_point, MOUSE_BUTTON_WHEEL_UP, 3)
	await _drag(ui_point, Vector2(20, 2), MOUSE_BUTTON_MIDDLE)
	await _drag(ui_point, Vector2(-20, -2), MOUSE_BUTTON_RIGHT)
	_check(_user_camera() == user_before and _authority() == authority, "Scrolling and dragging over battle controls cannot steer the board or issue an action")
	for index: int in range(5):
		await _drag(_board_point(), Vector2(95, -65), MOUSE_BUTTON_MIDDLE)
	_check_camera_bounds()
	var high := _ca()
	_check(absf(float(high.yaw_degrees) - float(high.yaw_limits[1])) < 0.000001 and absf(float(high.pitch_degrees) - float(high.pitch_limits[1])) < 0.000001, "Repeated real in-board drags clamp yaw and pitch at the upper limits")
	for index: int in range(5):
		await _drag(_board_point(), Vector2(-95, 65), MOUSE_BUTTON_MIDDLE)
	_check_camera_bounds()
	var low := _ca()
	_check(absf(float(low.yaw_degrees) - float(low.yaw_limits[0])) < 0.000001 and absf(float(low.pitch_degrees) - float(low.pitch_limits[0])) < 0.000001, "Opposite real in-board drags clamp at the lower limits without flipping the camera")
	_check(_authority() == authority, "All camera limits and UI pointer probes preserve exact battle and host authority")
	_camera_trials.append({"kind": "zoom_and_limits", "near": near, "far": far, "upper": high, "lower": low})


func _release_lifecycle() -> void:
	var authority := _authority()
	var start := _board_point()
	var outside := Vector2(app.size.x - 5, app.size.y - 5)
	await _drag(start, outside - start, MOUSE_BUTTON_RIGHT)
	_check(not bool(_ca().get("dragging", true)) and not bool(_ca().get("drag_pending", true)) and int(_ca().get("drag_button", -1)) == 0, "Releasing outside the board clears the captured drag and pending button")
	var released := _user_camera()
	await _motion(_board_point(), Vector2(35, 10), 0)
	_check(_user_camera() == released, "An ordinary pointer return after outside release cannot continue a stale camera drag")
	await _motion(_board_point(), Vector2.ZERO, 0)
	_raw_button(_board_point(), MOUSE_BUTTON_MIDDLE, true)
	await _motion(_board_point() + Vector2(12, 9), Vector2(12, 9), MOUSE_BUTTON_MASK_MIDDLE)
	_check(bool(_ca().get("dragging", false)), "A second real middle-button drag starts normally after outside release")
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await _frames(2)
	_check(not bool(_ca().get("dragging", true)) and not bool(_ca().get("drag_pending", true)) and int(_ca().get("drag_button", -1)) == 0, "The window-focus-loss lifecycle notification clears the live camera capture")
	_raw_button(_board_point(), MOUSE_BUTTON_MIDDLE, false)
	var lost := _user_camera()
	await _motion(_board_point() + Vector2(-12, -9), Vector2(-12, -9), 0)
	_check(_user_camera() == lost and _authority() == authority, "Pointer motion after lifecycle cancellation preserves the camera and all battle authority")
	_camera_trials.append({"kind": "outside_release_and_focus_notification", "notification": "root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)", "authority_unchanged": _authority() == authority})


func _transformed_targeting() -> void:
	_check_projection(false)
	await _click("MoveButton")
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	await _hover_tile([3, 4])
	_check(_stage().get("_hover") == [3, 4] and (_stage().get("_reach") as Array).has([3, 4]), "After orbit, actual hover and the highlighted reachable cells identify the intended movement tile")
	await _capture("05-camera-rotated-path-preview.png")
	var point: Vector2 = _view().audit_tile_center([3, 4])
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	var event: Dictionary = {}
	for queued: Dictionary in _stage().get("_events"):
		if str(queued.get("type", "")) == "move":
			event = queued.duplicate(true)
			break
	var path: Array = event.get("path", [])
	_check(str(event.get("type", "")) == "move" and path.size() >= 2 and path[0] == [3, 3] and path[-1] == [3, 4], "The actual pointer action queues the authoritative route between the intended logical tiles")
	_raw_button(point, MOUSE_BUTTON_LEFT, false)
	await _idle()
	_check(_unit("player").pos == [3, 4] and int(_battle().revision) == int(before.revision) + 1 and bool(_unit("player").moved) and not bool(_unit("player").acted), "A left click after orbit performs exactly one intended move with the original action budget")
	_check(app.get("_session").snapshot() == host and _battle().objective == before.objective, "Camera-aware movement spends no host time or medicine HP")


func _action_restore() -> void:
	await _click("Skill_strike")
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview
	_check(bool(forecast.get("ok", false)) and str(forecast.get("target_id", "")) == "brute" and int(forecast.get("damage", -1)) == 6, "Rotated and zoomed target picking still previews the real adjacent brute and exact sword damage")
	var camera_before := _camera(_stage())
	var user_before := _user_camera()
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	await _mouse(_view().audit_tile_center([4, 3]), true)
	_check(bool(_view().audit_snapshot().busy) and not bool(_ca().get("input_enabled", true)), "The real full-body sword action temporarily locks manual camera input")
	var committed := _battle().duplicate(true)
	var point := _board_point()
	_raw_drag(point, Vector2(60, -30), MOUSE_BUTTON_RIGHT)
	_raw_wheel(point, MOUSE_BUTTON_WHEEL_DOWN, 3)
	_raw_home()
	_check(_user_camera() == user_before and _battle() == committed and app.get("_session").snapshot() == host, "Right-drag, wheel and reset input while busy cannot alter user view or duplicate the committed action")
	var focus_seen := false
	var deadline := Time.get_ticks_msec() + 10000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		focus_seen = focus_seen or float((_stage().call("audit") as Dictionary).get("camera_action_blend", 0)) > 0.05
		await process_frame
	await _idle()
	_check(focus_seen, "Automatic sword presentation actually focuses the camera from the chosen user angle")
	_check(_camera(_stage()) == camera_before and _user_camera() == user_before and bool(_ca().get("input_enabled", false)), "Full recovery restores the exact user camera transform and zoom, with manual input enabled again")
	_check(int(_unit("brute").hp) == 8 and int(_battle().revision) == int(before.revision) + 1 and _battle() == committed, "The rotated real sword hits once for six damage and presentation never changes settled rules")
	await _capture("06-camera-after-sword-restored.png")
	_camera_trials.append({"kind": "real_sword_camera_restore", "camera_before": camera_before, "camera_after": _camera(_stage()), "focus_seen": focus_seen, "user": _user_camera()})


func _workshop_independence() -> void:
	var authority := _authority()
	var battle_camera := _camera(_stage())
	var battle_user := _user_camera()
	await _open_workshop()
	if not is_instance_valid(_workshop()):
		return
	_check(not bool(_ca().get("input_enabled", true)), "Opening the separate workshop locks the covered battle camera")
	await _choose("WorkshopCameraChoice", 1)
	_check(str(_player().camera_mode) == "front", "The workshop retains its independent front preset")
	var workshop_camera := _camera(_wstage())
	var point := _wstage().get_global_transform_with_canvas() * (_wstage().size * 0.5)
	await _drag(point, Vector2(35, -15), MOUSE_BUTTON_MIDDLE)
	await _wheel(point, MOUSE_BUTTON_WHEEL_UP, 2)
	_check(_camera(_wstage()) == workshop_camera and _camera(_stage()) == battle_camera and _user_camera() == battle_user, "Battle orbit controls cannot overwrite the independent workshop preset or the covered battle camera")
	await _choose("WorkshopCameraChoice", 2)
	_check(str(_player().camera_mode) == "side", "The existing side inspection preset remains usable")
	await _capture("07-camera-independent-workshop.png")
	await _close_workshop()
	_check(_camera(_stage()) == battle_camera and _user_camera() == battle_user and bool(_ca().get("input_enabled", false)) and _authority() == authority, "Returning from workshop preserves exact battle orbit, zoom, action and host state")


func _inspector_and_resize() -> void:
	var authority := _authority()
	var battle_camera := _camera(_stage())
	var user := _user_camera()
	await _click("InspectCharactersButton")
	var inspector: Control = _view().get("_character_inspector")
	_check(is_instance_valid(inspector) and not bool(_ca().get("input_enabled", true)), "The character inspection modal independently locks the covered battle camera")
	if is_instance_valid(inspector):
		_raw_home()
		_check(_camera(_stage()) == battle_camera and _user_camera() == user, "Reset keys inside character inspection cannot reset the covered tactical camera")
		var button: Control = inspector.call("ui_control", "CloseCharactersButton")
		await _mouse(button.get_global_transform_with_canvas() * (button.size * 0.5), true)
		await _frames(3)
	_check(_camera(_stage()) == battle_camera and bool(_ca().get("input_enabled", false)), "Closing character inspection returns exact battle view and pointer ownership")
	root.size = qa_size + Vector2i(32, 20)
	await _frames(5)
	_check(_user_camera() == user and _authority() == authority, "A real window resize preserves user orbit, zoom and all authoritative state")
	_check_camera_bounds()
	root.size = qa_size
	await _frames(5)
	_check(_camera(_stage()) == battle_camera and _user_camera() == user, "Restoring the original window dimensions restores the exact chosen camera framing")


func _check_camera_bounds() -> void:
	var data := _ca()
	for key: String in ["yaw_degrees", "pitch_degrees", "zoom"]:
		var limits_key := {"yaw_degrees": "yaw_limits", "pitch_degrees": "pitch_limits", "zoom": "zoom_limits"}[key] as String
		var limits: Array = data.get(limits_key, [])
		_check(limits.size() == 2 and is_finite(float(data.get(key, NAN))), "Camera value and declared limits are finite for " + key)
		if limits.size() == 2:
			_check(float(data[key]) >= float(limits[0]) - 0.000001 and float(data[key]) <= float(limits[1]) + 0.000001, "Camera remains within its declared limits for " + key)
	var camera := _stage().get("camera") as Camera3D
	_check(camera.transform.is_finite() and camera.size > 0 and is_finite(camera.size) and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Orbit remains a finite positive-size orthographic camera")
	_check(camera.global_basis.y.dot(Vector3.UP) > 0 and (-camera.global_basis.z).y < -0.05, "Bounded orbit retains upright screen axes and a downward view of the board")


func _check_projection(require_all: bool) -> void:
	var stage := _stage()
	var count := 0
	for y: int in range(7):
		for x: int in range(9):
			var tile := [x, y]
			var point: Vector2 = stage.call("tile_to_screen", tile)
			if not Rect2(Vector2.ZERO, stage.size).has_point(point):
				_check(not require_all, "The default view keeps authored tile on screen: " + str(tile))
				continue
			count += 1
			_check(stage.call("screen_to_tile", point) == tile, "Visible tile round-trips through the actual current camera: " + str(tile))
	_check(count == 63 if require_all else count >= 35, "The current tactical view retains a usable projected board")


func _button_pair(point: Vector2, button: MouseButton) -> void:
	await _motion(point, Vector2.ZERO, 0)
	_raw_button(point, button, true)
	await process_frame
	_raw_button(point, button, false)
	await _frames(2)


func _drag(point: Vector2, delta: Vector2, button: MouseButton) -> void:
	await _motion(point, Vector2.ZERO, 0)
	_raw_button(point, button, true)
	await process_frame
	await _motion(point + delta * 0.5, delta * 0.5, MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE)
	await _motion(point + delta, delta * 0.5, MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE)
	_raw_button(point + delta, button, false)
	await _frames(2)


func _motion(point: Vector2, relative: Vector2, buttons: int) -> void:
	_raw_motion(point, relative, buttons)
	await process_frame


func _raw_motion(point: Vector2, relative: Vector2, buttons: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(relative)
	event.button_mask = buttons
	root.push_input(event)


func _raw_button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (1 << (button - 1)) if pressed and button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE] else 0
	root.push_input(event)


func _raw_drag(point: Vector2, delta: Vector2, button: MouseButton) -> void:
	_raw_motion(point, Vector2.ZERO, 0)
	_raw_button(point, button, true)
	_raw_motion(point + delta, delta, MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE)
	_raw_button(point + delta, button, false)


func _wheel(point: Vector2, button: MouseButton, count: int) -> void:
	await _motion(point, Vector2.ZERO, 0)
	_raw_wheel(point, button, count)
	await _frames(2)


func _raw_wheel(point: Vector2, button: MouseButton, count: int) -> void:
	for index: int in range(count):
		_raw_button(point, button, true)
		_raw_button(point, button, false)


func _raw_home() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_HOME
		event.pressed = pressed
		root.push_input(event)


func _finish() -> void:
	var report := {"test": "ambush_camera_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual root.push_input mouse button, pointer motion, wheel and key input against real battle controls; focus-loss lifecycle notification labelled separately", "trials": _camera_trials, "boundary": "Native Compatibility manual camera, picking, authority isolation and automatic-focus restoration. Browser, physical input, artistic approval and long-run performance remain separate."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH CAMERA UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
