extends "res://tests/cultivation_engine_ambush_render.gd"
## Presentation-only palm-wind tool experiment. The existing interrupt pose is
## a visual reference, not a new palm martial art or an authoritative attack.
var _demos: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/palm-vfx/render"
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
	_check(DisplayServer.get_name() != "headless", "Palm-wind sample uses an actual Compatibility render window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The unchanged two-versus-three encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	await _choose_palm_style(1)
	_check_layout()
	_check_palm_layout()
	_check_fresh()
	await _capture("00-palm-sample-arrival.png")
	# Pause scenery through its real control so the new short effect remains
	# easy to compare. This does not stop the battle or its presentation clock.
	await _click("EnvironmentMotionButton")
	await _demo("enabled_sound_control", "01-palm-flight.png", "02-palm-impact.png", "03-palm-restored.png")
	await _click("SoundToggleButton")
	_check(bool(_view().audit_snapshot().sound_muted), "The existing sound control can be muted normally")
	await _demo("muted_sound_control", "", "04-palm-muted-impact.png", "")
	await _click("SoundToggleButton")
	await _demo("repeat_after_unmute", "", "05-palm-repeat-impact.png", "")
	await _restart_check()
	_check_fresh()
	await _capture("06-palm-retry-defaults.png")
	var stage: Control = _view().get("_stage")
	var viewport_ref: WeakRef = weakref(stage.get("viewport"))
	var helper_ref: WeakRef = weakref(stage.get("_palm_vfx"))
	var sequence: int = int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and viewport_ref.get_ref() == null and helper_ref.get_ref() == null, "Leaving frees the actual palm helper and rendered battle viewport")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Leaving still settles the abandoned battle once through the original host")
	await _capture("07-palm-return-town.png")
	_finish()


func _check_fresh() -> void:
	_check(_battle().units.size() == 5 and int(_battle().objective.hp) == 18 and int(_battle().round) == 1 and _unit("player").pos == [3, 3] and _unit("blade").pos == [5, 4], "Palm sample retains the exact authored encounter opening")
	for id: String in ["PalmVfxReplayButton", "Skill_pierce", "Skill_sweep", "Skill_push", "SoundToggleButton", "SkillPreviewChoice", "PalmStyleChoice"]:
		var control: BaseButton = _view().ui_control(id) as BaseButton
		_check(control != null and control.is_visible_in_tree() and not control.disabled and control.focus_mode == Control.FOCUS_NONE, "Fresh UI exposes the available " + id)
	var helper := _palm()
	_check(bool(helper.get("ready", false)) and not bool(helper.get("active", true)) and int(helper.get("live_nodes", -1)) == 0, "Prepared palm assets create no idle effect nodes")
	_check(not (helper.get("assets", {}) as Dictionary).is_empty(), "Palm audit identifies the actual authored asset paths")
	_check(not bool(_view().audit_snapshot().sound_muted), "Restart restores the original enabled sound control default")
	_check(not bool(app.get("_session").can_save()), "Palm preview does not bypass the live-battle save restriction")
	var skill_ids: Array = ((_view().get("_definition") as Dictionary).skills as Array).map(func(skill: Dictionary) -> String: return str(skill.id))
	_check(skill_ids == ["strike", "push", "interrupt", "guard", "pierce", "sweep", "palm"], "The empty-space sample retains the approved combat catalog including the independent real palm skill")


func _demo(label: String, flight_file: String, impact_file: String, restored_file: String) -> void:
	var stage: Control = _view().get("_stage")
	var before := _context()
	var actors_before := _actors(stage)
	var camera_before := _camera(stage)
	var presented_hp: Dictionary = (stage.call("audit").presented_hp as Dictionary).duplicate(true)
	var feedback_before: Array = (stage.call("audit").feedback_history as Array).duplicate(true)
	var sound_before := _sound_count(stage)
	var helper_before := _palm()
	var muted_before: bool = bool(_view().audit_snapshot().sound_muted)
	var control: Control = _view().ui_control("PalmVfxReplayButton")
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	_check(bool(_view().audit_snapshot().busy) and bool(_view().audit_snapshot().replaying), "Palm sample owns the existing UI presentation busy gate")
	for id: String in ["PalmVfxReplayButton", "CombatLightReplayButton", "CombatLightModeButton", "LightingModeButton", "RestartButton", "ReturnButton", "EndRoundButton", "InspectCharactersButton", "Skill_pierce", "Skill_sweep", "Skill_push", "Unit_player", "Unit_tinglan", "MoveButton", "SoundToggleButton", "SkillPreviewChoice", "PalmStyleChoice"]:
		var button: BaseButton = _view().ui_control(id) as BaseButton
		_check(button != null and button.disabled, "Palm preview busy gate disables " + id)
	_raw_click("PalmVfxReplayButton")
	_raw_click("EndRoundButton")
	_raw_click("Skill_pierce")
	_raw_click("SoundToggleButton")
	await _key(KEY_SPACE)
	_check(_context() == before and bool(_view().audit_snapshot().sound_muted) == muted_before, "Repeated pointer and keyboard input during the sample cannot act, advance a round or change mute")
	var saw_flight := false
	var saw_impact := false
	var saw_peak := false
	var reference_pose := false
	var flight_sample: Dictionary = {}
	var impact_entry: Dictionary = {}
	var peak: Dictionary = {}
	var max_nodes := 0
	var deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(_view()) and bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		var helper := _palm()
		var animation: Dictionary = (stage.get("actor_nodes").tinglan as Node3D).call("get_animation_audit")
		reference_pose = reference_pose or (str(animation.get("mode", "")) == "attack" and str(animation.get("skill_id", "")) == "interrupt")
		max_nodes = maxi(max_nodes, int(helper.get("live_nodes", 0)))
		if bool(helper.get("active", false)) and int(helper.get("live_nodes", 0)) > 0 and float(helper.get("elapsed", 0.0)) >= 0.12 and int(helper.get("impact_count", 0)) == int(helper_before.get("impact_count", 0)) and not saw_flight:
			saw_flight = true
			flight_sample = helper.duplicate(true)
			_check(int(helper.get("visible_nodes", 0)) > 0, "The flight sample has visible native effect geometry after its initial fade-in")
			if not flight_file.is_empty():
				await _capture(flight_file)
		if int(helper.get("impact_count", 0)) == int(helper_before.get("impact_count", 0)) + 1 and not saw_impact:
			saw_impact = true
			impact_entry = helper.duplicate(true)
			_check(_context() == before and (stage.call("audit").presented_hp as Dictionary) == presented_hp, "Visible palm impact changes no host, battle or presented HP")
		if saw_impact and bool(helper.get("active", false)) and float(helper.get("elapsed", 0.0)) >= 0.44 and not saw_peak:
			saw_peak = true
			peak = helper.duplicate(true)
			_check(int(helper.get("impact_frame", -1)) >= 1 and int(helper.get("impact_frame", -1)) <= 20 and int(helper.get("visible_nodes", 0)) > 0, "The delayed impact sample uses a nonempty authored atlas frame and visible native geometry")
			_check(_context() == before and (stage.call("audit").presented_hp as Dictionary) == presented_hp, "The later visible impact frame still changes no host, battle or presented HP")
			if not impact_file.is_empty():
				await _capture(impact_file)
		await process_frame
	_check(not bool(_view().audit_snapshot().busy), "Palm sample finishes within six seconds")
	await _idle()
	var after := _palm()
	_check(saw_flight and saw_impact and saw_peak and max_nodes > 0, "The real rendered sample has separate visible flight, impact entry and nonempty atlas peak samples")
	_check(reference_pose, "The sample uses the existing Tinglan interrupt pose as its labelled visual reference")
	_check(int(after.get("begin_count", -1)) == int(helper_before.get("begin_count", 0)) + 1 and int(after.get("impact_count", -1)) == int(helper_before.get("impact_count", 0)) + 1 and int(after.get("finish_count", -1)) == int(helper_before.get("finish_count", 0)) + 1, "One pointer activation produces exactly one begin, impact and completion")
	_check(not bool(after.get("active", true)) and int(after.get("live_nodes", -1)) == 0, "The sample returns to zero live effect nodes after every replay")
	_check(_context() == before and (stage.call("audit").presented_hp as Dictionary) == presented_hp and (stage.call("audit").feedback_history as Array) == feedback_before, "Completing the sample leaves authority, HP and combat-event history unchanged")
	_check(_actors(stage) == actors_before and _camera(stage) == camera_before, "The sample restores every actor transform, visibility, process flag and the exact playable camera")
	_check(str((stage.get("actor_nodes").tinglan as Node3D).call("get_animation_audit").get("mode", "")) == "idle", "Tinglan returns to the existing idle animation")
	_check(_sound_count(stage) == sound_before and bool(_view().audit_snapshot().sound_muted) == muted_before, "This silent visual experiment schedules no audio and preserves the existing sound setting")
	for id: String in ["PalmVfxReplayButton", "Skill_pierce", "Skill_sweep", "SoundToggleButton", "SkillPreviewChoice", "EndRoundButton"]:
		_check(not (_view().ui_control(id) as BaseButton).disabled, "Finished sample restores " + id)
	if not restored_file.is_empty():
		await _capture(restored_file)
	_demos.append({"label": label, "flight": flight_sample, "impact_entry": impact_entry, "peak": peak, "flight_seen": saw_flight, "impact_seen": saw_impact, "peak_seen": saw_peak, "max_live_nodes": max_nodes, "context_exact": _context() == before, "actors_exact": _actors(stage) == actors_before, "camera_exact": _camera(stage) == camera_before, "sound_delta": _sound_count(stage) - sound_before, "after": after})


func _restart_check() -> void:
	var stage: Control = _view().get("_stage")
	var viewport_ref: WeakRef = weakref(stage.get("viewport"))
	var helper_ref: WeakRef = weakref(stage.get("_palm_vfx"))
	var sequence: int = int(app.get("_session").snapshot().sequence)
	await _click("RestartButton")
	_check(viewport_ref.get_ref() == null and helper_ref.get_ref() == null, "Restart frees the prior palm helper and rendered battle viewport")
	_check(int(app.get("_session").snapshot().sequence) == sequence + 1, "Restart still settles the abandoned attempt exactly once")
	_check_layout()
	_check_palm_layout()
	var helper := _palm()
	_check(int(helper.get("begin_count", -1)) == 0 and int(helper.get("impact_count", -1)) == 0 and int(helper.get("finish_count", -1)) == 0, "A fresh battle owns fresh bounded presentation counters")


func _check_palm_layout() -> void:
	var rects: Dictionary = _view().audit_snapshot().controls
	_check(rects.has("PalmVfxReplayButton"), "The new palm sample button participates in the actual layout audit")
	if not rects.has("PalmVfxReplayButton"):
		return
	var palm_rect: Rect2 = rects.PalmVfxReplayButton
	_check(Rect2(Vector2.ZERO, app.size).encloses(palm_rect) and palm_rect.size.x > 0.0 and palm_rect.size.y > 0.0, "The complete palm sample button remains inside the usable canvas")
	for id: String in rects:
		if id != "PalmVfxReplayButton":
			_check(not palm_rect.intersects(rects[id] as Rect2), "The palm sample button keeps its clickable area clear of " + id)


func _palm() -> Dictionary:
	return _view().get("_stage").call("audit").get("palm_vfx", {})


func _context() -> Dictionary:
	var audit: Dictionary = _view().audit_snapshot()
	return {"host": app.get("_session").snapshot().duplicate(true), "battle": _battle().duplicate(true), "selected": audit.selected, "action": audit.action, "preview": audit.preview.duplicate(true), "preview_skill": audit.preview_skill}


func _actors(stage: Control) -> Dictionary:
	var result := {}
	for id: String in stage.get("actor_nodes"):
		var actor: Node3D = stage.get("actor_nodes")[id]
		result[id] = {"transform": actor.transform, "processing": actor.is_processing(), "visible": actor.visible}
	return result


func _camera(stage: Control) -> Dictionary:
	var camera: Camera3D = stage.get("camera")
	return {"transform": camera.transform, "size": camera.size, "near": camera.near, "far": camera.far, "projection": camera.projection}


func _sound_count(stage: Control) -> int:
	return int(stage.call("audit").get("skill_fx", {}).get("audio_play_count", -1))


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _raw_click(id: String) -> void:
	var button: Control = _view().ui_control(id)
	var at: Vector2 = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)


func _finish() -> void:
	var report := {"test": "mountain_ambush_palm_vfx_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input pointer and keyboard events under native Compatibility, not browser or physical input", "scope": "Presentation-only Effekseer palm-wind and Material Maker dust experiment using the existing interrupt pose as a reference; no new palm martial art, rules, damage or sound", "audio_boundary": "No new sound is authored or scheduled; existing Dummy counters are checked only for unchanged scheduling", "demos": _demos}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH PALM VFX UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(1 if not failures.is_empty() else 0)

func _choose_palm_style(index: int) -> void:
	var before := _context()
	await _click("PalmStyleChoice")
	var choice := _view().ui_control("PalmStyleChoice") as OptionButton
	var popup := choice.get_popup()
	_check(popup.visible and popup.is_embedded(), "The real palm style popup opens through pointer input")
	await _click_popup_row(popup, index)
	_check(choice.selected == index and int(_view().audit_snapshot().palm_style) == index and _context() == before, "The actual palm style popup changes no battle or host state")

func _click_popup_row(popup: PopupMenu, index: int) -> void:
	# Confirmed by the isolated 4.7.2 diagnostic: embedded Window coordinates
	# are logical canvas units, so route the pointer through root's final scale.
	var panel: StyleBox = popup.get_theme_stylebox("panel")
	var top: float = panel.get_margin(SIDE_TOP) * popup.content_scale_factor
	var bottom: float = panel.get_margin(SIDE_BOTTOM) * popup.content_scale_factor
	var local := Vector2(float(popup.size.x) * 0.5, top + (float(popup.size.y) - top - bottom) * (float(index) + 0.5) / float(popup.item_count))
	var at: Vector2 = root.get_final_transform() * (Vector2(popup.position) + local)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = Vector2(1, 1)
	motion.velocity = Vector2(60, 60)
	motion.window_id = root.get_window_id()
	root.push_input(motion)
	await process_frame
	_check(popup.get_focused_item() == index, "The actual menu pointer hovers the requested visible row")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.window_id = root.get_window_id()
		root.push_input(event)
		await process_frame

