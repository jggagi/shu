extends SceneTree
## Native Compatibility renderer + actual Godot UI mouse events.
## Does not claim browser, physical input or device audio verification.

const Entry := preload("res://scenes/demos/cultivation_engine_v06_mountain_ambush.tscn")
var app: Control
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var output := "res://.local/qa/ambush/render"
var qa_size := Vector2i(1152, 720)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	_check(DisplayServer.get_name() != "headless", "Native rendered display is available")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("checkpoints-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The new slice opens directly in its two-versus-three encounter")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check((_battle().get("units", []) as Array).size() == 5, "Exactly two player units and three enemy units are present")
	_check(int(_battle().objective.hp) == 18 and int(_battle().round) == 1, "Fresh encounter objective and first round are correct")
	_check(str(app.get("_session").snapshot().phase) == "ambush", "The host is occupied by the current encounter")
	_check(not bool(app.get("_session").can_save()), "Saving is unavailable in the live battle")
	var stage: Control = _view().get("_stage")
	var definition: Dictionary = _view().get("_definition")
	for y: int in range(int(definition.height)):
		for x: int in range(int(definition.width)):
			var tile := [x, y]
			var point: Vector2 = stage.call("tile_to_screen", tile)
			var restored: Array = stage.call("screen_to_tile", point)
			_check(restored == tile, "Projected tile %d,%d round-trips through the actual camera" % [x, y])
			_check(Rect2(Vector2.ZERO, stage.size).has_point(point), "Playable tile %d,%d is visible" % [x, y])
	_check_layout()
	await _capture("00-arrival.png")
	await _click("RestartButton")
	_check(_battle().phase == "player" and int(_battle().round) == 1 and int(_battle().objective.hp) == 18, "Mid-battle restart opens a clean encounter")
	_check(int(app.get("_session").snapshot().sequence) == 1, "Mid-battle restart settles the abandoned attempt once")
	await _click("Skill_push")
	await _hover_tile([4, 3])
	_check(_view().audit_snapshot().action == "push", "The real skill button selects the knockback preview")
	await _capture("01-push-preview.png")
	await _tile([4, 3])
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "A mouse-selected knockback collides with and destroys the north barricade, stopping before it")
	await _capture("02-push-result.png")
	await _tile([4, 3])
	_check(_unit("player").pos == [4, 3], "A mouse-selected ground tile moves the player")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	await _capture("03-interrupt-preview.png")
	await _tile([5, 4])
	_check(_plan("blade").get("interrupted", false), "A mouse-selected interrupt cancels the knife fighter's intent")
	await _click("EndRoundButton")
	_check(int(_battle().round) == 2 and int(_battle().objective.hp) == 15, "The first enemy phase applies the redirected/interrupt rules and only the arrow hits the objective")
	await _capture("04-enemy-phase.png")
	# Finish a real four-round win through UI, using the same shipped data.
	await _click("Unit_player")
	await _click("Skill_push")
	await _tile([5, 3])
	await _tile([6, 3])
	_check(_unit("brute").pos == [7, 3] and _unit("player").pos == [6, 3], "Next-round free knockback lets the player traverse the broken barricade cell")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _tile([5, 4])
	await _click("EndRoundButton")
	await _click("Unit_player")
	await _click("Skill_push")
	await _tile([7, 3])
	await _tile([7, 3])
	await _click("Unit_tinglan")
	await _click("Skill_strike")
	await _tile([5, 4])
	await _click("EndRoundButton")
	await _click("Unit_player")
	await _click("Skill_strike")
	await _tile([8, 3])
	await _click("EndRoundButton")
	_check(_battle().phase == "won" and int(_battle().objective.hp) > 0, "UI gameplay protects the objective through the fourth enemy round")
	var session: RefCounted = app.get("_session")
	_check(int(session.snapshot().sequence) == 2 and session.ambush_context().settled, "Victory submits exactly one host receipt")
	await _capture("05-victory.png")
	await _click("RetryButton")
	_check(_battle().phase == "player" and int(_battle().round) == 1 and int(_battle().objective.hp) == 18, "The real retry button starts a clean local encounter")
	_check(int(session.snapshot().sequence) == 2, "Retry does not duplicate the previous award/time receipt")
	for index: int in range(3):
		await _click("EndRoundButton")
	_check(_battle().phase == "lost", "Ignoring threats can really lose the protection objective")
	_check(int(session.snapshot().sequence) == 3, "Defeat also submits exactly one host receipt")
	await _capture("06-defeat.png")
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()), "Return closes the battle presentation")
	_check(session.snapshot().scene == "shanxia_town" and session.snapshot().phase == "result", "Return retains the same host and its real result in town")
	await _capture("07-return-to-town.png")
	var saved: Dictionary = app.get("_store").save_session(session)
	_check(saved.get("ok", false), "The post-battle safe result checkpoint saves")
	var state_before: Dictionary = session.snapshot()
	var loaded: Dictionary = app.get("_store").load_session(session)
	_check(loaded.get("ok", false) and session.snapshot() == state_before and session.battle() == null, "Loading a post-battle checkpoint neither replays the battle nor changes its receipt")
	await _host_click("ResultContinueButton")
	var walker: Control = app.call("ui_control", "TownWalker")
	_check(walker != null, "Returning from combat retains the real town walker")
	if walker != null:
		var local: Vector2 = walker.call("logical_to_local", Vector2(160, 260))
		await _mouse(walker.get_global_transform_with_canvas() * local, true)
		var deadline := Time.get_ticks_msec() + 20000
		while str(session.snapshot().scene) != "tingyu_corridor" and Time.get_ticks_msec() < deadline:
			await process_frame
		await process_frame
		await process_frame
	_check(session.snapshot().scene == "tingyu_corridor", "After battle the same player can walk to the exit and return to the mentor")
	if session.snapshot().scene == "tingyu_corridor":
		await _host_click("ResultContinueButton")
		await _host_click("ActionButton_talk_mentor")
		for index: int in range(4):
			await _host_click("DialogContinueButton")
		_check(session.snapshot().phase == "event" and session.snapshot().event.node == "choice", "The same-scene mentor dialogue still reaches its real choice after combat")
		await _capture("08-mentor-choice.png")
		await _host_click("ChoiceButton_take_lesson")
		for index: int in range(3):
			await _host_click("DialogContinueButton")
		_check(session.snapshot().flags.mentor_lesson_heard and session.snapshot().stats.energy == 92, "The mentor choice settles its original cost and returns a real result")
		await _capture("09-mentor-result.png")
	_finish()


func _view() -> Control:
	return app.get("_ambush_view") as Control if is_instance_valid(app) else null


func _battle() -> Dictionary:
	return _view().audit_snapshot().battle if is_instance_valid(_view()) else {}


func _unit(id: String) -> Dictionary:
	for member: Dictionary in _battle().get("units", []):
		if member.id == id:
			return member
	return {}


func _barricade(id: String) -> Dictionary:
	for gate: Dictionary in _battle().get("barricades", []):
		if str(gate.id) == id:
			return gate
	return {}


func _plan(id: String) -> Dictionary:
	for plan: Dictionary in _battle().get("plans", []):
		if plan.unit_id == id:
			return plan
	return {}


func _check_layout() -> void:
	var rects: Dictionary = _view().audit_snapshot().controls
	var bounds := Rect2(Vector2.ZERO, app.size)
	for id: String in rects:
		var rect: Rect2 = rects[id]
		_check(bounds.encloses(rect) and rect.size.x > 0 and rect.size.y > 0, "Visible control %s stays inside the usable canvas" % id)
	_check(not (rects.AmbushStage as Rect2).intersects(rects.EndRoundButton), "End-round control does not cover the playfield")
	_check(not (rects.Skill_push as Rect2).intersects(rects.Skill_guard), "Skill buttons do not overlap")
	_check((rects.AmbushStage as Rect2).size.y >= app.size.y * 0.56, "The playfield retains at least 56 percent of usable canvas height")
	for id: String in ["Skill_pierce", "Skill_sweep"]:
		if not rects.has(id):
			continue
		for other: String in ["MoveButton", "Skill_strike", "Skill_push", "Skill_guard", "Skill_sweep"]:
			if other != id and rects.has(other):
				_check(not (rects[id] as Rect2).intersects(rects[other]), "New skill %s keeps its own clickable area apart from %s" % [id, other])


func _click(id: String) -> void:
	var control: Control = _view().ui_control(id) if is_instance_valid(_view()) else null
	_check(control != null and control.is_visible_in_tree() and not (control as BaseButton).disabled, "UI control %s is available" % id)
	if control == null or not control.is_visible_in_tree() or (control as BaseButton).disabled:
		print("CONTROL_FAILURE_CONTEXT: ", id, " ", JSON.stringify(_view().audit_snapshot() if is_instance_valid(_view()) else {}))
		return
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	await _idle()


func _host_click(id: String) -> void:
	var control: Control = app.call("ui_control", id)
	_check(control != null and control.is_visible_in_tree() and not (control as BaseButton).disabled, "Host UI control %s is available" % id)
	if control == null or not control.is_visible_in_tree() or (control as BaseButton).disabled:
		return
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	await process_frame
	await process_frame


func _hover_tile(tile: Array) -> void:
	if not is_instance_valid(_view()):
		_check(false, "Encounter view exists for tile hover")
		return
	await _mouse(_view().audit_tile_center(tile), false)


func _tile(tile: Array) -> void:
	if not is_instance_valid(_view()):
		_check(false, "Encounter view exists for tile click")
		return
	await _mouse(_view().audit_tile_center(tile), true)
	await _idle()


func _mouse(canvas_point: Vector2, click: bool) -> void:
	var actual: Vector2 = root.get_final_transform() * canvas_point
	var motion := InputEventMouseMotion.new()
	motion.position = actual
	motion.global_position = actual
	root.push_input(motion)
	await process_frame
	if click:
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = actual
			event.global_position = actual
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event)
			await process_frame


func _idle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	for frame: int in range(3):
		await process_frame
	while is_instance_valid(_view()) and bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not is_instance_valid(_view()) or not bool(_view().audit_snapshot().busy), "Presentation completes within its real-time deadline")
	# Container sorting follows the snapshot refresh at the end of an animation.
	await process_frame
	await process_frame


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(output.path_join(filename))
	_check(image.save_png(path) == OK, "Native frame captured: " + filename)
	captures.append({"file": path, "size": [image.get_width(), image.get_height()], "sha256": FileAccess.get_sha256(path)})


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		print("FAIL: " + description)


func _finish() -> void:
	var report := {"test": "mountain_ambush_render", "checks": checks, "failures": failures,
		"captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(),
		"input": "Godot root.push_input mouse events, not physical input or browser", "result": "PASS" if failures.is_empty() else "FAIL"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH RENDER: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
