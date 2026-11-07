extends "res://tests/cultivation_engine_ambush_render.gd"
## Observe shipped UI actions and the rendered hit sequence, never alter rules.
var _observed_windups: Array[Dictionary] = []
var _observed_pointing: Array[Dictionary] = []

func _run() -> void:
	output = "res://.local/qa/ambush-feedback/render"
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
	_check(DisplayServer.get_name() != "headless", "Feedback review uses a rendered Compatibility window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-checkpoints-%d" % OS.get_process_id())))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "Feedback candidate opens the actual encounter")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	_check_threats()
	await _capture("00-threats.png")
	await _click("Skill_push")
	await _hover_tile([4, 3])
	await _capture("01-push-preview.png")
	var stage: Control = _view().get("_stage")
	stage.connect("feedback_changed", _observe_feedback)
	var sequence: int = int(app.get("_session").snapshot().sequence)
	await _mouse(_view().audit_tile_center([4, 3]), true)
	_check(bool(_view().audit_snapshot().busy), "The attack keeps action input busy through its animation")
	_check(not _observed_windups.is_empty() and str(_observed_windups[0].phase) == "windup", "The real attack enters windup before its damage feedback")
	_check(not _observed_windups.is_empty() and int(_observed_windups[0].display_hp) == 14 and int(_observed_windups[0].rule_hp) == 9, "Displayed health waits for the hit while rules commit only once")
	var committed: Dictionary = _battle().duplicate(true)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	await process_frame
	_check(_battle() == committed, "Space during windup cannot begin a hidden enemy phase")
	_check((_view().ui_control("InspectCharactersButton") as Button).disabled and (_view().ui_control("RestartButton") as Button).disabled, "Inspection and restart stay gated during the action")
	await _capture("02-early-action.png")
	await _wait_for_phase(["push", "recovery"])
	_check(int(stage.call("audit").presented_hp.brute) == 9, "The first hit visibly applies its exact five damage including barricade collision")
	await _capture("03-impact.png")
	await _idle()
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0 and not _has_feedback("push") and _has_feedback("collision") and _has_feedback("barricade_destroyed"), "Barricade collision reports the stop, bonus damage and destroyed obstacle")
	_check(str(stage.get("actor_nodes").player.get("_mode")) == "idle", "The original Jiang phrase completes its recovery")
	_check(int(app.get("_session").snapshot().sequence) == sequence, "Hit animation adds no host settlement")
	_check_threats()
	await _capture("04-push-threats.png")
	await _tile([4, 3])
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	await _tile([5, 4])
	_check(_plan("blade").interrupted and _has_feedback("interrupt"), "Interrupt visibly cancels the actual enemy plan")
	_check(not _observed_pointing.is_empty() and _observed_pointing[0].source_clip == "TinglanInterrupt" and _observed_pointing[0].left_hand_variant == "pointing" and _observed_pointing[0].sword_visible, "A real battle interrupt drives the unique pointing clip and hand while retaining one sword")
	_check_threats()
	await _capture("05-interrupt.png")
	await _click("EndRoundButton")
	_check(int(_battle().objective.hp) == 15 and _has_feedback("objective_hit") and _has_feedback("miss"), "Enemy playback distinguishes a real objective hit from a displaced miss")
	_check(int(stage.call("audit").presented_hp.objective) == 15, "Objective display and authoritative health agree after playback")
	await _capture("06-objective-hit.png")
	await _click("Unit_player")
	await _click("Skill_push")
	var collisions_before_free_push: int = _feedback_count("collision")
	await _tile([5, 3])
	_check(_unit("brute").pos == [7, 3] and int(_unit("brute").hp) == 6 and _has_feedback("push") and _feedback_count("collision") == collisions_before_free_push, "The next free knockback travels two cells without inventing another collision")
	await _tile([6, 3])
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _tile([5, 4])
	await _click("EndRoundButton")
	await _click("Unit_player")
	await _click("Skill_push")
	await _hover_tile([7, 3])
	_check("撞" in str(_view().audit_snapshot().feedback), "The real blocked-push preview warns about collision")
	await _capture("07-collision-preview.png")
	await _tile([7, 3])
	_check(_unit("brute").pos == [8, 3] and int(_unit("brute").hp) == 1 and _has_feedback("collision"), "A boundary collision shows its bonus and exact final HP without moving beyond the board")
	_check_threats()
	await _capture("08-collision-result.png")
	await _tile([7, 3])
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _tile([5, 4])
	await _click("EndRoundButton")
	await _click("Unit_player")
	await _click("Skill_push")
	await _tile([8, 3])
	var history: Array = stage.call("audit").feedback_history
	_check(int(_unit("brute").hp) == 0 and not stage.get("actor_nodes").brute.visible, "A lethal blocked shove visibly removes the defeated enemy")
	_check(str(history[-1].type) == "collision" and "1" in str(history[-1].text) and "退场" in str(history[-1].text), "Lethal collision explains the HP-capped total without an invented extra hit")
	await _capture("09-lethal-collision.png")
	await _click("RestartButton")
	await _click("Unit_tinglan")
	await _click("Skill_guard")
	_check(_has_feedback("guard"), "Guard has a visible reduction cue")
	await _click("EndRoundButton")
	_check(int(_unit("tinglan").hp) == 16, "Guard presentation preserves the real three-point reduction")
	await _capture("10-guard-result.png")
	await _click("Unit_player")
	_check_layout()
	_finish()


func _observe_feedback(_text: String, _tone: String) -> void:
	var audit: Dictionary = _view().get("_stage").call("audit")
	if str(audit.presentation_phase) == "windup":
		_observed_windups.append({"phase": audit.presentation_phase, "display_hp": audit.presented_hp.brute, "rule_hp": _unit("brute").hp})
		if str(audit.active_event.get("unit_id", "")) == "tinglan" and str(audit.active_event.get("skill_id", "")) == "interrupt":
			_observed_pointing.append(_view().get("_stage").get("actor_nodes").tinglan.call("get_animation_audit"))


func _wait_for_phase(phases: Array) -> void:
	var deadline: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and bool(_view().audit_snapshot().busy):
		if str(_view().get("_stage").call("audit").presentation_phase) in phases:
			return
		await process_frame
	_check(false, "Expected rendered hit phase was observed")


func _feedback_count(kind: String) -> int:
	var count := 0
	for entry: Dictionary in _view().get("_stage").call("audit").feedback_history:
		if str(entry.type) == kind:
			count += 1
	return count


func _has_feedback(kind: String) -> bool:
	for entry: Dictionary in _view().get("_stage").call("audit").feedback_history:
		if str(entry.type) == kind:
			return true
	return false


func _check_threats() -> void:
	var expected_cells: Array = []
	var expected_damage: int = 0
	var expected_count: int = 0
	for plan: Dictionary in _battle().plans:
		if bool(plan.interrupted) or int(_unit(str(plan.unit_id)).hp) <= 0:
			continue
		for cell: Array in plan.cells:
			if not expected_cells.has(cell):
				expected_cells.append(cell)
		if (_battle().objective.pos as Array) in plan.cells:
			expected_damage += int(plan.damage)
			expected_count += 1
	var actual_cells: Array = _view().get("_stage").call("audit").danger_cells
	_check(actual_cells.size() == expected_cells.size() and expected_cells.all(func(cell: Array) -> bool: return actual_cells.has(cell)), "Danger marks equal every real active attack cell, including changed or cancelled plans")
	var threat: Dictionary = _view().audit_snapshot().objective_threat
	_check(int(threat.get("damage", -1)) == mini(int(_battle().objective.hp), expected_damage) and int(threat.get("count", -1)) == expected_count, "The objective warning equals actual active-plan coverage and bounded damage")
