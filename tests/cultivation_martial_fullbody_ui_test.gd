extends "res://tests/cultivation_martial_workshop_ui_test.gd"
## Actual root pointer input in the unchanged authored encounter. GPU is run by
## Root; source-time/resource observations are distinct from artistic acceptance.
var _fullbody_trials: Array[Dictionary] = []
var _battle_samples: Array[Dictionary] = []
var _fullbody_feedback: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/martial-fullbody/ui"
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
	_check(DisplayServer.get_name() != "headless", "Full-body action uses the actual native Compatibility renderer")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var loaded := Catalog.load_catalog()
	_check(bool(loaded.get("ok", false)), "The unchanged six-move catalog and its two enhanced variants load")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_catalog = loaded.catalog
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The real two-versus-three authored encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	_check(_unit("player").pos == [3, 3] and _unit("brute").pos == [4, 3] and int(_unit("brute").hp) == 14, "The test starts from the shipped adjacent brute without moving any fixture")
	await _capture("00-fullbody-authored-opening.png")
	await _illegal_target()
	await _real_fullbody_strike()
	await _click("RestartButton")
	_check(_unit("player").pos == [3, 3] and int(_unit("brute").hp) == 14 and not bool(_unit("player").acted), "Restart returns to the real opening and clears the consumed action")
	_check_battle_clean()
	_parent_before = _context()
	var battle_stage: Control = _view().get("_stage")
	var camera_before := _camera(battle_stage)
	var actors_before := _actors(battle_stage)
	await _open_workshop()
	if is_instance_valid(_workshop()):
		for id: String in ["sword_cleave", "palm_gale"]:
			await _workshop_footwork(id)
		var old_stage := _wstage()
		var old_viewport: WeakRef = weakref(old_stage.get("viewport"))
		await _wclick("WorkshopPlayButton")
		await _wait_elapsed(0.20)
		await _close_workshop()
		_check(old_viewport.get_ref() == null and _context() == _parent_before and _camera(battle_stage) == camera_before and _actors(battle_stage) == actors_before, "Closing a moving-foot preview frees its stage and restores exact battle authority, transforms and camera")
	_check_battle_clean()
	await _capture("08-fullbody-workshop-return.png")
	var viewport_ref: WeakRef = weakref(battle_stage.get("viewport"))
	var sequence := int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and viewport_ref.get_ref() == null, "Returning frees the actual battle viewport and its whole-body player")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Return settles only the abandoned attempt once in the original host")
	await _capture("09-fullbody-return-town.png")
	_finish()


func _illegal_target() -> void:
	await _click("Skill_strike")
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var stage: Control = _view().get("_stage")
	var begins := int(stage.call("workshop_audit").get("begin_count", 0))
	await _hover_tile([7, 2])
	_check(not bool(_view().audit_snapshot().preview.get("ok", true)), "Out-of-range archer is visibly rejected by the original range-one strike preview")
	await _mouse(_view().audit_tile_center([7, 2]), true)
	await _frames(3)
	_check(_battle() == before and app.get("_session").snapshot() == host and not bool(_view().audit_snapshot().busy), "An illegal strike consumes no action, damage, movement, host time or busy state")
	_check(int(stage.call("workshop_audit").get("begin_count", 0)) == begins, "Rejected targeting starts no hidden enhanced animation")


func _real_fullbody_strike() -> void:
	var stage: Control = _view().get("_stage")
	stage.connect("feedback_changed", _observe_fullbody_feedback)
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var camera_before := _camera(stage)
	var actor: Node3D = stage.get("actor_nodes").player
	var actor_position := actor.position
	var actor_process := actor.is_processing()
	var target: Node3D = stage.get("actor_nodes").brute
	var target_position := target.position
	var target_process := target.is_processing()
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and int(forecast.get("damage", -1)) == 6 and str(forecast.get("target_id", "")) == "brute", "The new visible slash keeps the original exact range-one, single-target, six-damage forecast")
	await _capture("01-fullbody-strike-forecast.png")
	var baseline_player: Dictionary = stage.call("workshop_audit")
	await _mouse(_view().audit_tile_center([4, 3]), true)
	var committed := _battle().duplicate(true)
	_check(bool(_view().audit_snapshot().busy) and int(_unit("brute").hp) == 8 and int(stage.call("audit").presented_hp.brute) == 14, "The host commits one six-damage action while the visible HP waits for the actual sword impact")
	_check(str((_view().ui_control("Skill_strike") as Button).text).contains("落雁斩"), "The real combat button identifies the visible falling-sword form")
	for id: String in ["Skill_strike", "MoveButton", "EndRoundButton", "RestartButton", "ReturnButton", "MartialWorkshopButton"]:
		_check((_view().ui_control(id) as BaseButton).disabled, "The complete action gates real control " + id)
	_raw_fullbody_click("Skill_strike")
	_raw_fullbody_click("EndRoundButton")
	_raw_fullbody_click("RestartButton")
	_check(_battle() == committed and app.get("_session").snapshot() == host, "Repeated root pointer input during preparation cannot duplicate damage, move a unit or start another round")
	var enhanced := Catalog.find_move(_catalog, "sword_cleave", "enhanced")
	var hold_rows: Array[Dictionary] = []
	var first_hit_source := -1.0
	var first_hit_elapsed := -1.0
	var saw_recovery := false
	var saw_post_hold_source := false
	var captured_prepare := false
	var captured_hit := false
	var captured_recovery := false
	var deferred_captures: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 8000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		# Observe the completed rendered frame itself. In the impact interval,
		# never await the multi-frame screenshot helper or encode/write a PNG:
		# those operations previously hid the remaining hold observations.
		await RenderingServer.frame_post_draw
		var audit: Dictionary = stage.call("audit")
		var player: Dictionary = stage.call("workshop_audit")
		var row := {"elapsed": player.get("elapsed", 0.0), "source_seconds": player.get("source_seconds", 0.0), "active": player.get("active", false), "phase": audit.presentation_phase, "presented_hp": audit.presented_hp.brute, "hold": player.get("impact_hold_active", false), "recoil_targets": player.get("recoil_targets", []), "actor_animation": actor.call("get_animation_audit"), "target_mode": target.get("_mode"), "target_pose_seconds": target.get("_pose_time"), "actor_position": actor.position, "target_position": target.position, "process_frame": Engine.get_process_frames(), "observation_usec": Time.get_ticks_usec()}
		_battle_samples.append(row)
		if bool(player.get("active", false)):
			_check(str(player.get("move_id", "")) == "sword_cleave" and str(player.get("variant_id", "")) == "enhanced" and str(player.get("animation_asset", "")) == str(enhanced.animation.asset), "Actual combat uses the populated enhanced falling-sword clip rather than a presentation preview or old attack")
			_check(absf(float(player.get("total", 0.0)) - 1.82) < 0.0001 and absf(float(player.get("impact_hold_seconds", 0.0)) - 0.07) < 0.0001, "Combat alone retains full recovery and the explicit seventy-millisecond impact hold")
		if int(audit.presented_hp.brute) == 8 and first_hit_elapsed < 0.0:
			first_hit_elapsed = float(player.get("elapsed", 0.0))
			first_hit_source = float(player.get("source_seconds", 0.0))
		if bool(player.get("impact_hold_active", false)):
			row["actual_skeleton_pose"] = _bone_pose(actor)
			row["actual_target_body_transform"] = (target.get("body") as Node3D).transform
			hold_rows.append(row)
		if float(player.get("source_seconds", 0.0)) > 0.76:
			saw_post_hold_source = true
		if str(audit.presentation_phase) == "recovery" and float(player.get("elapsed", 0.0)) > 1.0:
			saw_recovery = true
		if not captured_prepare and float(player.get("elapsed", 0.0)) >= 0.27 and float(player.get("elapsed", 0.0)) < 0.55:
			captured_prepare = true
			_defer_current_capture(deferred_captures, "02-fullbody-step-and-raise.png", player)
		elif not captured_hit and bool(player.get("impact_hold_active", false)) and hold_rows.size() >= 2:
			# GPU readback itself can block for a whole hold. Complete the
			# two pure pose/audit observations before reading the hit image.
			captured_hit = true
			_defer_current_capture(deferred_captures, "03-fullbody-synchronized-impact.png", player)
		elif not captured_recovery and saw_recovery:
			captured_recovery = true
			_defer_current_capture(deferred_captures, "04-fullbody-recovery.png", player)
		await process_frame
	await _idle()
	_save_deferred_captures(deferred_captures)
	_check(first_hit_elapsed >= 0.66 and first_hit_elapsed < 0.79 and absf(first_hit_source - 0.66) < 0.04, "Visible damage is observed at the authored sword landing, never during preparation")
	_check(hold_rows.size() >= 2, "The real render loop observes multiple impact-hold frames")
	if hold_rows.size() >= 2:
		var first: Dictionary = hold_rows[0]
		var last: Dictionary = hold_rows[-1]
		_check(float(last.elapsed) > float(first.elapsed) and absf(float(last.source_seconds) - float(first.source_seconds)) < 0.00001 and absf(float(first.source_seconds) - 0.66) < 0.00001, "Presentation seconds advance while the actual body source clock stays on the exact sword-impact pose")
		_check(first.actual_skeleton_pose == last.actual_skeleton_pose and first.actual_target_body_transform == last.actual_target_body_transform, "Both actual sword bones and target recoil stay still during the shared impact hold")
		_check(str(first.target_mode) == "hit" and not (first.recoil_targets as Array).is_empty(), "The enemy enters its real hit reaction under the same unified presentation owner")
	_check(saw_post_hold_source and saw_recovery, "The body resumes after impact and remains busy through its real follow-through and recovery")
	_check(_battle() == committed and int(_unit("brute").hp) == 8 and int(_battle().revision) == int(before.revision) + 1 and bool(_unit("player").acted) and not bool(_unit("player").moved), "The entire motion consumes exactly one original attack and no movement or extra damage")
	_check(app.get("_session").snapshot() == host and _battle().objective == before.objective and _battle().plans == before.plans and _battle().barricades == before.barricades, "Full-body motion changes no host settlement, protected objective, enemy plans or barricades")
	for id: String in ["player", "tinglan", "brute", "blade", "archer"]:
		_check(_unit(id).pos == _find_unit(before.units, id).pos, "Physical footwork never changes the authoritative board position of " + id)
	_check(actor.position == actor_position and target.position == target_position and actor.is_processing() == actor_process and target.is_processing() == target_process and _camera(stage) == camera_before, "Real combat restores actor roots, process ownership and the playable camera after recovery")
	_check(_fullbody_feedback.filter(func(row): return row.kind == "attack").size() == 1 and _fullbody_feedback.filter(func(row): return row.kind == "hit").size() == 1, "One real action announces exactly one attack and one target hit")
	_check(int(stage.call("workshop_audit").get("begin_count", 0)) == int(baseline_player.get("begin_count", 0)) + 1, "The actual battle starts the unified source player exactly once")
	_check_battle_clean()
	await _capture("05-fullbody-strike-result.png")
	_fullbody_trials.append({"kind": "authored_real_combat", "preview": forecast, "before": before, "after": _battle().duplicate(true), "first_hit_elapsed": first_hit_elapsed, "first_hit_source": first_hit_source, "impact_hold_samples": hold_rows.size(), "feedback": _fullbody_feedback.duplicate(true), "samples": _battle_samples.duplicate(true)})


func _defer_current_capture(pending: Array[Dictionary], filename: String, player: Dictionary) -> void:
	# Called only after frame_post_draw. Keep the exact image in memory while
	# the action runs; encoding, disk writes and hashes happen after recovery.
	pending.append({"filename": filename, "image": root.get_texture().get_image(),
		"elapsed": player.get("elapsed", 0.0), "source_seconds": player.get("source_seconds", 0.0),
		"process_frame": Engine.get_process_frames(), "observation_usec": Time.get_ticks_usec()})


func _save_deferred_captures(pending: Array[Dictionary]) -> void:
	for row: Dictionary in pending:
		var image := row.image as Image
		var path := ProjectSettings.globalize_path(output.path_join(str(row.filename)))
		_check(image.save_png(path) == OK, "Native completed-frame image saved after recovery: " + str(row.filename))
		captures.append({"file": path, "size": [image.get_width(), image.get_height()], "sha256": FileAccess.get_sha256(path),
			"captured_elapsed": row.elapsed, "captured_source_seconds": row.source_seconds,
			"captured_process_frame": row.process_frame, "captured_observation_usec": row.observation_usec,
			"method": "Image readback after frame_post_draw; PNG encoding/write/hash deferred until action completed"})
	pending.clear()


func _workshop_footwork(id: String) -> void:
	await _wclick("WorkshopMove_" + id)
	await _choose("WorkshopVariantChoice", 0)
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.08)
	await _wclick("WorkshopPauseButton")
	await _seek_pointer(0.0)
	var actor: Node3D = _wstage().get("actor_nodes")[str(_move(id).actor)]
	var initial := _actual_feet(actor)
	var active := "foot.R" if id == "sword_cleave" else "foot.L"
	var support := "foot.L" if active == "foot.R" else "foot.R"
	var max_travel := 0.0
	var max_lift := 0.0
	var max_original_drift := 0.0
	var max_support_drift := 0.0
	var rows: Array[Dictionary] = []
	for fraction: float in [0.0, 0.16, 0.30, 0.45, 0.60, 0.80, 1.0]:
		await _seek_pointer(fraction)
		var original := _player().duplicate(true)
		var original_feet := _actual_feet(actor)
		for foot: String in ["foot.L", "foot.R"]:
			max_original_drift = maxf(max_original_drift, (original_feet[foot] as Vector3).distance_to(initial[foot]))
		await _wclick("WorkshopVariantCompareButton")
		var enhanced := _player().duplicate(true)
		var actual := _actual_feet(actor)
		_check(bool(enhanced.paused) and str(enhanced.variant_id) == "enhanced" and absf(float(enhanced.elapsed) - float(original.elapsed)) < 0.00001 and absf(float(enhanced.source_seconds) - float(original.source_seconds)) < 0.00001, id + " footwork comparison keeps the same paused presentation and source clocks")
		_check(is_zero_approx(float(enhanced.get("impact_hold_seconds", 0.0))), id + " independent workshop timing remains unchanged by the combat-only hit hold")
		max_travel = maxf(max_travel, (actual[active] as Vector3).distance_to(initial[active]))
		max_lift = maxf(max_lift, (actual[active] as Vector3).y - (initial[active] as Vector3).y)
		max_support_drift = maxf(max_support_drift, (actual[support] as Vector3).distance_to(initial[support]))
		if is_equal_approx(fraction, 1.0):
			_check((actual[active] as Vector3).distance_to(initial[active]) <= 0.00005, id + " active foot returns to its original neutral anchor at the real final pose")
		if is_equal_approx(fraction, 0.16):
			await _capture("06-" + id + "-lifted-step.png")
		rows.append({"fraction": fraction, "original": original, "enhanced": enhanced, "original_actual_feet": original_feet, "enhanced_actual_feet": actual})
		await _wclick("WorkshopVariantCompareButton")
	_check(max_original_drift <= 0.001 and max_support_drift <= 0.00005, id + " retains both original planted anchors and the enhanced support foot within its existing strict contract")
	_check(max_travel >= 0.15 and max_lift >= 0.035, id + " enhanced real skeleton has meaningful foot travel and lift rather than a renamed planted clip")
	_check(_context() == _parent_before, id + " all same-time footwork comparisons preserve exact underlying gameplay state")
	await _wclick("WorkshopStopButton")
	_check_cleanup()
	_fullbody_trials.append({"kind": "workshop_footwork", "id": id, "max_actual_travel_m": max_travel, "max_actual_lift_m": max_lift, "max_original_drift_m": max_original_drift, "max_enhanced_support_drift_m": max_support_drift, "samples": rows})


func _actual_feet(actor: Node3D) -> Dictionary:
	var adapter: Node3D = actor.call("workshop_adapter")
	var rig := adapter.get("skeleton") as Skeleton3D
	rig.force_update_all_bone_transforms()
	var result := {}
	for foot: String in ["foot.L", "foot.R"]:
		result[foot] = rig.get_bone_global_pose(rig.find_bone(foot)).origin
	return result


func _observe_fullbody_feedback(_text: String, _tone: String) -> void:
	var audit: Dictionary = _view().get("_stage").call("audit")
	if audit.feedback_history.is_empty():
		return
	var kind := str(audit.feedback_history[-1].type)
	if kind in ["attack", "hit"]:
		_fullbody_feedback.append({"kind": kind, "event": audit.active_event, "presented_hp": audit.presented_hp, "player": _view().get("_stage").call("workshop_audit"), "at_ms": audit.feedback_history[-1].at_ms})


func _raw_fullbody_click(id: String) -> void:
	var control: Control = _view().ui_control(id)
	var at: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)


func _check_battle_clean() -> void:
	var stage: Control = _view().get("_stage")
	var player: Dictionary = stage.call("workshop_audit")
	var audit: Dictionary = stage.call("audit")
	_check(not bool(_view().audit_snapshot().busy) and not bool(player.get("active", true)) and int(player.get("live_audio", -1)) == 0 and int(player.get("live_fx", -1)) == 0, "Recovered battle releases its busy gate and all unified-player transient resources")
	_check(int(audit.skill_fx.mesh_count) == 0 and int(audit.palm_impact.live_nodes) == 0 and int(audit.combat_light.light_count) == 0 and (player.get("recoil_targets", []) as Array).is_empty(), "Actual effects, lights and manually owned target reactions are cleared")
	_check(not (_view().ui_control("RestartButton") as BaseButton).disabled and not (_view().ui_control("ReturnButton") as BaseButton).disabled and not (_view().ui_control("MartialWorkshopButton") as BaseButton).disabled, "Complete recovery restores restart, return and workshop input")


func _finish() -> void:
	var report := {"test": "martial_fullbody_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input pointer and popup input in the unchanged authored encounter; no direct signal emissions", "catalog_sha256": _catalog.get("catalog_sha256", ""), "trials": _fullbody_trials, "boundary": "Native Compatibility source-clock, action settlement and actual skeleton/recoil scheduling proof. Artistic quality, browser, Windows, physical input and heard device audio are separate gates."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("MARTIAL FULLBODY UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
