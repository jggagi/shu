extends "res://tests/cultivation_engine_ambush_render.gd"
## Authored two-route encounter, actual UI mouse events and rendered playback.
## Rules remain authoritative; this does not claim browser or physical input QA.

var _windups: Array[Dictionary] = []
var _route_results: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/songfeng-barricade/render"
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
	_check(DisplayServer.get_name() != "headless", "Barricade UI uses a real rendered Compatibility window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-checkpoints-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The actual barricade encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	var session: RefCounted = app.get("_session")
	var host_before: Dictionary = session.snapshot().duplicate(true)
	var stage: Control = _view().get("_stage")
	_check_fresh()
	_check_layout()
	_check_threats()
	await _capture("00-two-barricades.png")
	# Route one: one ordinary sword strike opens a genuinely blocked route.
	await _click("Unit_tinglan")
	_check(not [6, 5] in _view().get("_battle").call("reachable", "tinglan"), "The live south barricade is absent from actual movement destinations")
	var before_blocked: Dictionary = _battle().duplicate(true)
	await _tile([6, 5])
	_check(_battle() == before_blocked and session.snapshot() == host_before, "Clicking a closed route cannot spend movement, action or host time")
	_check("木栅" in str(_view().audit_snapshot().feedback), "The blocked-route click explains the obstacle in the real UI")
	await _click("Skill_strike")
	var body_point: Vector2 = _visual_row("south_gate").get("body_screen", Vector2.ZERO)
	var ground_point: Vector2 = stage.call("tile_to_screen", [6, 5])
	_check(Rect2(Vector2.ZERO, stage.size).has_point(body_point) and body_point.y < ground_point.y - 1.0, "The real south-fence body target lies visibly above its ground-cell centre")
	_check(stage.call("_pointer_tile", body_point) == [6, 5], "The actual stage pointer entry resolves the raised fence body to its authored cell")
	var body_canvas: Vector2 = stage.get_global_transform_with_canvas() * body_point
	await _mouse(body_canvas, false)
	var preview: Dictionary = _view().audit_snapshot().preview
	_check(bool(preview.get("ok", false)) and str(preview.get("target_kind", "")) == "barricade" and str(preview.get("barricade_id", "")) == "south_gate", "Ordinary sword hover selects the actual south barricade")
	_check(int(preview.get("barricade_damage", -1)) == 6 and bool(preview.get("destroys_barricade", false)), "The direct-strike preview predicts six damage and an opened route")
	_check(_battle() == before_blocked and session.snapshot() == host_before, "The real barricade preview preserves exact authoritative state")
	await _capture("01-direct-opening-preview.png")
	stage.connect("feedback_changed", _observe_windup)
	await _mouse(body_canvas, true)
	_check(bool(_view().audit_snapshot().busy), "A real click on the raised wooden body starts the direct strike through the public UI")
	_check(not _windups.is_empty() and int(_windups[0].presented_hp) == 6 and int(_windups[0].rule_hp) == 0 and bool(_windups[0].standing_visible), "Rules commit once while the fence remains intact and at six displayed HP during windup")
	var committed: Dictionary = _battle().duplicate(true)
	await _mouse(body_canvas, true)
	_check(_battle() == committed and session.snapshot() == host_before, "Repeated real clicks during the strike do not add damage, moves or host settlement")
	await _idle()
	_check(int(_barricade("south_gate").hp) == 0 and bool(_unit("tinglan").acted) and not bool(_unit("tinglan").moved), "One direct strike destroys the south barricade, spending action while retaining movement")
	_check_gate_visual("south_gate", false)
	_check(_has_feedback("barricade_hit") and _has_feedback("barricade_destroyed"), "The direct strike announces the real hit and broken route")
	_check_status()
	_check([6, 5] in _view().get("_battle").call("reachable", "tinglan"), "The newly broken route becomes reachable in the same round")
	await _tile([6, 5])
	_check(_unit("tinglan").pos == [6, 5] and bool(_unit("tinglan").moved) and bool(_unit("tinglan").acted), "A real subsequent mouse click walks onto the newly opened route in the same round")
	_check(session.snapshot() == host_before, "Breaking and traversing a fence never settles the host")
	_check_threats()
	await _capture("02-direct-opening-crossed.png")
	await _first_push(false)
	await _finish_route(true, host_before)
	await _capture("03-direct-opening-victory.png")
	var terminal_host: Dictionary = session.snapshot().duplicate(true)
	var context: Dictionary = _view().get("_context")
	var duplicate: Dictionary = session.call("finish_ambush", str(context.run_id), str(context.operation_id))
	_check(bool(duplicate.get("duplicate", false)) and session.snapshot() == terminal_host, "A late completion callback after a real fence-route victory cannot settle twice")
	var old_viewport: WeakRef = weakref(stage.get("viewport"))
	var old_north: WeakRef = weakref(stage.get("barricade_nodes").north_gate)
	await _click("RetryButton")
	_check(old_viewport.get_ref() == null and old_north.get_ref() == null, "Retry releases the previous viewport and barricade models")
	_check(session.snapshot().sequence == terminal_host.sequence and session.snapshot().receipts == terminal_host.receipts, "Retry adds no duplicate victory receipt")
	_check_fresh()
	_check_layout()
	stage = _view().get("_stage")
	host_before = session.snapshot().duplicate(true)
	# Route two: the first shove breaks the north fence but stops before it.
	await _click("Skill_push")
	await _hover_tile([4, 3])
	preview = _view().audit_snapshot().preview
	_check(bool(preview.get("ok", false)) and str(preview.get("target_kind", "")) == "unit" and str(preview.get("collision_barricade_id", "")) == "north_gate" and preview.get("collision_barricade_pos", []) == [6, 3], "Knockback hover identifies the specific north barricade collision")
	_check(preview.get("push_to", []) == [5, 3] and int(preview.get("damage", -1)) == 5 and int(preview.get("barricade_damage", -1)) == 6 and bool(preview.get("destroys_barricade", false)), "The preview predicts the stop before the fence, enemy damage and complete barricade destruction")
	_check("停在栅前" in str(_view().audit_snapshot().feedback), "The real collision text warns that this strike cannot carry its victim through the fence")
	await _capture("04-collision-opening-preview.png")
	await _first_push(true)
	_check(int(_barricade("south_gate").hp) == 6, "North collision leaves the independent south route closed")
	_check_gate_visual("north_gate", false)
	_check_status()
	await _capture("05-collision-opening-result.png")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	await _tile([5, 4])
	_check(bool(_plan("blade").interrupted) and int(_unit("blade").hp) == 8, "The ordinary interrupt still cancels the real blade plan with exact damage")
	_check_threats()
	await _capture("06-interrupt-with-barricades.png")
	await _finish_route(false, host_before)
	await _capture("07-collision-control-victory.png")
	old_viewport = weakref(stage.get("viewport"))
	old_north = weakref(stage.get("barricade_nodes").north_gate)
	terminal_host = session.snapshot().duplicate(true)
	await _click("RetryButton")
	_check(old_viewport.get_ref() == null and old_north.get_ref() == null, "Second retry releases the completed collision-route world")
	_check(session.snapshot().sequence == terminal_host.sequence, "Second retry also preserves the single victory settlement")
	_check_fresh()
	_check_layout()
	await _capture("08-retry-restores-both.png")
	stage = _view().get("_stage")
	old_viewport = weakref(stage.get("viewport"))
	old_north = weakref(stage.get("barricade_nodes").north_gate)
	var sequence_before: int = int(session.snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_viewport.get_ref() == null and old_north.get_ref() == null, "Returning releases fence models and their render viewport")
	_check(session.snapshot().scene == "shanxia_town" and session.snapshot().phase == "result" and int(session.snapshot().sequence) == sequence_before + 1, "Withdrawing from the fresh retry retains town and settles that attempt exactly once")
	await _capture("09-barricade-return.png")
	_finish()


func _first_push(already_selected: bool) -> void:
	if not already_selected:
		await _click("Unit_player")
		await _click("Skill_push")
	await _tile([4, 3])
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "The executed collision exactly matches its stop, enemy damage and destroyed fence")
	await _tile([4, 3])
	_check(_unit("player").pos == [4, 3], "Jiang can follow to the newly vacated near-side cell")
	_check_threats()


func _finish_route(direct: bool, host_before: Dictionary) -> void:
	var session: RefCounted = app.get("_session")
	await _click("EndRoundButton")
	_check(int(_battle().round) == 2 and int(_battle().objective.hp) == 15, "The first enemy phase respects the displayed displaced or avoided attacks")
	_check(session.snapshot() == host_before, "The first enemy phase adds no host receipt")
	await _click("Unit_player")
	await _click("Skill_push")
	await _tile([5, 3])
	_check(_unit("brute").pos == [7, 3] and int(_unit("brute").hp) == 6, "The next-round push crosses the already broken fence for two free cells")
	await _tile([6, 3])
	_check(_unit("player").pos == [6, 3], "The actual player movement enters the destroyed north barricade cell")
	await _click("Unit_tinglan")
	if direct:
		await _tile([5, 5])
	await _click("Skill_interrupt")
	await _tile([5, 4])
	_check_threats()
	await _click("EndRoundButton")
	_check(int(_battle().round) == 3 and int(_battle().objective.hp) == 12 and session.snapshot() == host_before, "Second-round control preserves the objective and exact unsettled host")
	await _click("Unit_player")
	await _click("Skill_push")
	await _tile([7, 3])
	_check(_unit("brute").pos == [8, 3] and int(_unit("brute").hp) == 1, "Boundary collision keeps its original exact bonus and board limit")
	await _tile([7, 3])
	await _click("Unit_tinglan")
	await _click("Skill_strike")
	await _tile([5, 4])
	await _click("EndRoundButton")
	_check(int(_battle().round) == 4 and int(_battle().objective.hp) == 9 and session.snapshot() == host_before, "Third-round playback retains the single future terminal settlement")
	await _click("Unit_player")
	await _click("Skill_strike")
	await _tile([8, 3])
	if direct:
		await _click("Unit_tinglan")
		await _click("Skill_interrupt")
		await _tile([5, 4])
	await _click("EndRoundButton")
	_check(_battle().phase == "won" and int(_battle().objective.hp) == 6, "The authored %s route reaches a real four-round survival victory with six objective HP" % ("direct opening" if direct else "collision control"))
	var terminal: Dictionary = session.snapshot()
	_check(int(terminal.sequence) == int(host_before.sequence) + 1 and int(terminal.slot) == int(host_before.slot) + 1 and terminal.receipts.size() == host_before.receipts.size() + 1 and int(terminal.counts.get("ambush_win", 0)) == int(host_before.counts.get("ambush_win", 0)) + 1, "The route's terminal victory creates exactly one time charge, receipt and victory count")
	_route_results.append({"route": "direct_opening" if direct else "collision_control", "battle": _battle(), "host_before": host_before, "host_after": terminal})


func _check_fresh() -> void:
	_check(_battle().units.size() == 5 and _battle().barricades.size() == 2, "Fresh barricades remain separate from the original five combatants")
	_check(_barricade("north_gate").pos == [6, 3] and _barricade("south_gate").pos == [6, 5] and int(_barricade("north_gate").hp) == 6 and int(_barricade("south_gate").hp) == 6, "Every new encounter restores both authored barricades at six HP")
	_check(int(_battle().round) == 1 and int(_battle().objective.hp) == 18, "The new encounter retains the original round and objective defaults")
	var stage: Control = _view().get("_stage")
	_check(stage.get("barricade_nodes").size() == 2 and stage.get("actor_nodes").size() == 5, "The actual stage owns two fence roots and exactly five actor roots")
	for id: String in ["north_gate", "south_gate"]:
		_check_gate_visual(id, true)
	_check_status()


func _check_gate_visual(id: String, alive: bool) -> void:
	var stage: Control = _view().get("_stage")
	var gate: Node3D = stage.get("barricade_nodes").get(id) as Node3D
	_check(is_instance_valid(gate) and gate.position.is_finite(), "Fence %s has a finite actual model root" % id)
	var audit: Dictionary = stage.call("audit")
	var row: Dictionary = _visual_row(id)
	_check(not row.is_empty() and bool(row.get("alive", not alive)) == alive and bool(row.get("standing_visible", not alive)) == alive and bool(row.get("broken_visible", alive)) != alive and row.get("pos", []) == _barricade(id).pos, "Fence %s standing and broken models agree with authoritative status" % id)
	_check(int(audit.presented_barricade_hp.get(id, -1)) == int(_barricade(id).hp), "Fence %s displayed HP agrees after playback" % id)
	var visible_meshes := 0
	if gate != null:
		for mesh: MeshInstance3D in gate.find_children("*", "MeshInstance3D", true, false):
			if mesh.is_visible_in_tree() and mesh.mesh != null:
				visible_meshes += 1
	_check(visible_meshes > 0, "Fence %s has actual visible intact wood or broken remnants" % id)


func _check_status() -> void:
	var label: Label = _view().ui_control("BarricadeStatus") as Label
	_check(label != null and label.is_visible_in_tree(), "The real barricade status label stays visible")
	if label == null:
		return
	var expected: Array[String] = []
	for gate: Dictionary in _battle().barricades:
		expected.append(str(gate.name) + (" · 已破，可通行" if int(gate.hp) <= 0 else "  %d/%d · 可破坏" % [int(gate.hp), int(gate.max_hp)]))
	_check(label.text == "\n".join(expected), "Both live HP and opened-route text exactly reflect the current barricade state")


func _observe_windup(_text: String, _tone: String) -> void:
	var audit: Dictionary = _view().get("_stage").call("audit")
	if str(audit.presentation_phase) == "windup" and str(audit.active_event.get("target_id", "")) == "south_gate":
		_windups.append({"presented_hp": audit.presented_barricade_hp.south_gate, "rule_hp": _barricade("south_gate").hp, "standing_visible": _visual_row("south_gate").standing_visible})


func _visual_row(id: String) -> Dictionary:
	for row: Dictionary in _view().get("_stage").call("audit").barricades:
		if str(row.id) == id:
			return row
	return {}


func _has_feedback(kind: String) -> bool:
	for entry: Dictionary in _view().get("_stage").call("audit").feedback_history:
		if str(entry.type) == kind:
			return true
	return false


func _check_threats() -> void:
	var cells: Array = []
	var damage := 0
	var count := 0
	for plan: Dictionary in _battle().plans:
		if bool(plan.interrupted) or int(_unit(str(plan.unit_id)).hp) <= 0:
			continue
		for cell: Array in plan.cells:
			if not cells.has(cell):
				cells.append(cell)
		if _battle().objective.pos in plan.cells:
			damage += int(plan.damage)
			count += 1
	var actual: Array = _view().get("_stage").call("audit").danger_cells
	_check(actual.size() == cells.size() and cells.all(func(cell: Array) -> bool: return actual.has(cell)), "Rendered danger marks equal every actual active plan after route changes")
	var threat: Dictionary = _view().audit_snapshot().objective_threat
	_check(int(threat.get("damage", -1)) == mini(int(_battle().objective.hp), damage) and int(threat.get("count", -1)) == count, "The real objective warning agrees with displayed attack coverage and bounded damage")


func _finish() -> void:
	var report := {"test": "mountain_ambush_barricade_ui", "checks": checks, "failures": failures, "captures": captures, "routes": _route_results, "direct_strike_windups": _windups, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input mouse events; not physical input or browser", "result": "PASS" if failures.is_empty() else "FAIL"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH BARRICADE UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
