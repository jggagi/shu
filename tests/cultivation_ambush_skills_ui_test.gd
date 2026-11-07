extends "res://tests/cultivation_engine_ambush_render.gd"
## Original opening plus explicitly labelled, legally configured multi-target fixtures.
## Real native UI input; Dummy audio checks scheduling only, not heard sound.
var _trials: Array[Dictionary] = []
var _previews: Array[Dictionary] = []
var _feedback_samples: Array[Dictionary] = []

func _run() -> void:
	output = "res://.local/qa/ambush-skills/render"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output = arg.trim_prefix("--output-dir=")
		elif arg.begins_with("--qa-size="):
			var parts := arg.trim_prefix("--qa-size=").split("x")
			qa_size = Vector2i(int(parts[0]), int(parts[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(DisplayServer.get_name() != "headless", "Skills use a real rendered Compatibility window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()): break
	_check(is_instance_valid(_view()), "The real authored mountain-road encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_connect_stage()
	_check_layout()
	_check_fresh()
	await _capture("00-skills-arrival.png")
	await _click("EnvironmentMotionButton")
	await _preview_skill(1, "pierce", "Martial/CloudPierce", "01-pierce-presentation-preview.png")
	await _set_muted(true)
	await _preview_skill(2, "sweep", "Martial/ReturningSweep", "02-sweep-muted-presentation-preview.png")
	await _set_muted(false)
	await _cast("authored_opening", "pierce", ["brute"], 4, "03-authored-pierce-preview.png", "04-authored-pierce-impact.png", "05-authored-pierce-result.png")
	await _restart()
	_configure_fixture("pierce")
	await _set_muted(true)
	await _cast("QA_fixture_blade_moved_to_5_3", "pierce", ["brute", "blade"], 8, "06-two-enemy-pierce-preview.png", "07-two-enemy-pierce-muted-impact.png", "08-two-enemy-pierce-result.png")
	await _restart()
	_configure_fixture("sweep")
	await _cast("QA_fixture_blade_moved_to_4_4_goal_in_shape", "sweep", ["brute", "blade"], 6, "09-sweep-protected-objective-preview.png", "10-sweep-impact.png", "11-sweep-result.png")
	await _restart()
	_check_fresh()
	await _capture("12-retry-defaults.png")
	var stage: Control = _view().get("_stage")
	var old_viewport: WeakRef = weakref(stage.get("viewport"))
	var old_fx: WeakRef = weakref(stage.get("_skill_fx"))
	var old_light: WeakRef = weakref(stage.get("_combat_light"))
	var seq: int = int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_viewport.get_ref() == null and old_fx.get_ref() == null and old_light.get_ref() == null, "Returning frees both effects helpers and the rendered viewport")
	_check(app.get("_session").snapshot().scene == "shanxia_town" and int(app.get("_session").snapshot().sequence) == seq + 1, "Returning settles this attempt exactly once in the same host")
	await _capture("13-skills-return-town.png")
	_finish()

func _connect_stage() -> void:
	var stage: Control = _view().get("_stage")
	stage.connect("feedback_changed", _observe_feedback)

func _check_fresh() -> void:
	_check(_battle().units.size() == 5 and int(_battle().objective.hp) == 18 and _unit("player").pos == [3,3] and _unit("blade").pos == [5,4], "Fresh battle restores the unchanged authored opening")
	for id: String in ["Skill_pierce", "Skill_sweep", "Skill_strike", "Skill_push", "Skill_guard", "MoveButton", "SoundToggleButton", "SkillPreviewChoice"]:
		var control: BaseButton = _view().ui_control(id) as BaseButton
		_check(control != null and control.is_visible_in_tree() and not control.disabled and control.focus_mode == Control.FOCUS_NONE, "Fresh UI exposes the real available " + id)
	_check(not bool(_view().audit_snapshot().sound_muted) and not bool(_fx().muted), "Every new battle restores its enabled skill-sound default")
	_check_cleanup()

func _configure_fixture(skill: String) -> void:
	var before: Dictionary = app.get("_session").snapshot().duplicate(true)
	var fixture: Dictionary = (_view().get("_definition") as Dictionary).duplicate(true)
	fixture.units[3].pos = [5,3] if skill == "pierce" else [4,4]
	_check(bool(_view().get("_battle").call("configure", fixture).ok), "The labelled multi-target QA fixture passes the same public configuration validation")
	_view().call("_sync")
	_check(app.get("_session").snapshot() == before, "A QA fixture changes no host, save, time or receipt")

func _restart() -> void:
	var stage: Control = _view().get("_stage")
	var viewport_ref: WeakRef = weakref(stage.get("viewport"))
	var fx_ref: WeakRef = weakref(stage.get("_skill_fx"))
	var light_ref: WeakRef = weakref(stage.get("_combat_light"))
	var seq: int = int(app.get("_session").snapshot().sequence)
	await _click("RestartButton")
	_check(viewport_ref.get_ref() == null and fx_ref.get_ref() == null and light_ref.get_ref() == null, "Retry frees the old viewport, martial effects and combat light")
	_check(int(app.get("_session").snapshot().sequence) == seq + 1, "Retry settles exactly one abandoned attempt")
	_connect_stage()
	_check_layout()
	_check_fresh()

func _set_muted(muted: bool) -> void:
	var before: Dictionary = _context()
	var plays: int = int(_fx().audio_play_count)
	if bool(_fx().muted) != muted:
		await _click("SoundToggleButton")
	_check(bool(_view().audit_snapshot().sound_muted) == muted and bool(_fx().muted) == muted and bool(_fx().audio_enabled) != muted, "The actual sound button updates the real helper mute state")
	_check(_context() == before and int(_fx().audio_play_count) == plays, "Sound switching cannot consume an action or play a hidden test sound")

func _preview_skill(index: int, skill: String, clip: String, filename: String) -> void:
	var choice := _view().ui_control("SkillPreviewChoice") as OptionButton
	var before: Dictionary = _context()
	await _mouse(choice.get_global_transform_with_canvas() * (choice.size * 0.5), true)
	var popup: PopupMenu = choice.get_popup()
	_check(popup.visible, "Actual pointer input opens the skill-choice popup window")
	_check(popup.is_embedded(), "The inherited test window embeds the actual popup without changing the product setting")
	await _click_popup_row(popup, index)
	_check(str(_view().audit_snapshot().preview_skill) == skill and choice.selected == index and not popup.visible and _context() == before, "Actual popup row pointer input selects " + skill + " without changing the battle")
	var stage: Control = _view().get("_stage")
	var camera_before := _camera(stage)
	var actors_before := _actors(stage)
	var plays: int = int(_fx().audio_play_count)
	var muted: bool = bool(_fx().muted)
	var replay: Control = _view().ui_control("CombatLightReplayButton")
	await _mouse(replay.get_global_transform_with_canvas() * (replay.size * 0.5), true)
	_check(bool(_view().audit_snapshot().busy) and bool(_view().audit_snapshot().replaying), "The new-skill presentation preview owns the real busy gate")
	var peak := await _wait_impact(skill)
	_check(not peak.is_empty() and str(peak.animation.source_clip) == clip, "The preview samples its distinct baked source clip " + clip)
	if not peak.is_empty():
		_check_clip_resource(peak, clip)
		await _capture(filename)
	await _idle()
	_check(_context() == before and _actors(stage) == actors_before and _camera(stage) == camera_before, "New-skill presentation preview restores exact authority, actor transforms/process and camera")
	_check(int(_fx().audio_play_count) - plays == (0 if muted else 2), "Preview sound scheduling respects the actual mute state")
	_check_cleanup()
	_previews.append({"skill":skill,"muted":muted,"peak":peak,"context_exact":_context()==before,"actors_exact":_actors(stage)==actors_before,"camera_exact":_camera(stage)==camera_before,"audio_play_delta":int(_fx().audio_play_count)-plays})

func _cast(origin: String, skill: String, targets: Array, total: int, forecast_file: String, impact_file: String, settled_file: String) -> void:
	var stage: Control = _view().get("_stage")
	var before: Dictionary = _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	await _click("Skill_" + skill)
	await _hover_tile([4,3])
	var forecast: Dictionary = (_view().audit_snapshot().preview as Dictionary).duplicate(true)
	_check(bool(forecast.get("ok",false)) and _same_set(forecast.get("targets",[]),targets) and int(forecast.get("total_damage",-1)) == total, "Real skill hover matches the labelled " + origin + " target ledger")
	_check(forecast.get("affected_cells",[]) == forecast.get("cells",[]) and (stage.get("_preview") as Dictionary).get("cells",[]) == forecast.get("cells",[]), "The actual stage highlights the same full footprint as the rules preview")
	_check(("%d人" % targets.size()) in str(_view().audit_snapshot().feedback) and ("共 %d 伤害" % total) in str(_view().audit_snapshot().feedback), "The player-facing forecast includes every hit and the true total damage")
	await _capture(forecast_file)
	var camera_before := _camera(stage)
	var plays: int = int(_fx().audio_play_count)
	var muted: bool = bool(_fx().muted)
	var feedback_start := _feedback_samples.size()
	await _mouse(_view().audit_tile_center([4,3]), true)
	var committed: Dictionary = _battle().duplicate(true)
	for id: String in ["Skill_pierce","Skill_sweep","Skill_push","MoveButton","SoundToggleButton","SkillPreviewChoice","RestartButton","ReturnButton","EndRoundButton","PalmVfxReplayButton", "PalmStyleChoice"]:
		_check((_view().ui_control(id) as BaseButton).disabled, "Real attack busy gate disables " + id)
	_raw_click("Skill_"+skill)
	_raw_click("EndRoundButton")
	_raw_click("SoundToggleButton")
	await _key(KEY_SPACE)
	_check(_battle()==committed and app.get("_session").snapshot()==host and bool(_fx().muted)==muted, "Repeated real input cannot duplicate multi-target damage, advance a turn, or change sound while busy")
	var peak := await _wait_impact(skill)
	_check(not peak.is_empty() and str(peak.animation.source_clip) == ("Martial/CloudPierce" if skill=="pierce" else "Martial/ReturningSweep"), "The actual action uses its own baked source clip")
	if not peak.is_empty():
		_check_clip_resource(peak, "Martial/CloudPierce" if skill=="pierce" else "Martial/ReturningSweep")
		_check(bool(peak.fx.active) and int(peak.fx.visible_mesh_count)>0 and int(peak.fx.vertex_count)>0 and int(peak.light.light_count)==1, "The real blade-driven effect has geometry and uses only the existing combat light")
		_check(_same_set(peak.active_attack_cells,forecast.cells), "The actual attack presents the forecast area as one source action")
		await _capture(impact_file)
	await _idle()
	var action_feedback: Array = _feedback_samples.slice(feedback_start)
	_check(action_feedback.filter(func(row):return row.kind=="attack").size()==1 and action_feedback.filter(func(row):return row.kind=="hit").size()==targets.size(), "One real swing presents every target hit exactly once")
	for id: String in targets:
		_check(int(_unit(id).hp)==int(_find(before.units,id).hp)-int(forecast.damage_by_target[id]) and int(stage.call("audit").presented_hp[id])==int(_unit(id).hp), "Forecast, authoritative and presented HP agree for "+id)
	_check(_battle().objective==before.objective and _unit("tinglan")==_find(before.units,"tinglan") and _battle().barricades==before.barricades and _battle().plans==before.plans, "Area damage leaves allies, medicine, fences and existing enemy intents intact")
	_check(bool(_unit("player").acted) and not bool(_unit("player").moved) and int(_battle().revision)==int(before.revision)+1 and app.get("_session").snapshot()==host, "Multi-target action consumes one action and no movement, host time or extra settlement")
	_check(_camera(stage)==camera_before, "The actual new-skill action restores the exact playable camera")
	_check(int(_fx().audio_play_count)-plays==(0 if muted else 2), "One source swing schedules only its enabled whoosh and impact sounds, independent of target count")
	_check_cleanup()
	await _capture(settled_file)
	_trials.append({"origin":origin,"skill":skill,"preview":forecast,"muted":muted,"peak":peak,"feedback":action_feedback,"audio_play_delta":int(_fx().audio_play_count)-plays,"after":_battle().duplicate(true),"host_exact":app.get("_session").snapshot()==host,"camera_exact":_camera(stage)==camera_before})

func _wait_impact(skill: String) -> Dictionary:
	var deadline := Time.get_ticks_msec()+4000
	while is_instance_valid(_view()) and bool(_view().audit_snapshot().busy) and Time.get_ticks_msec()<deadline:
		var stage: Control = _view().get("_stage")
		var audit: Dictionary = stage.call("audit")
		if str(audit.combat_light.get("phase",""))=="impact" and bool(audit.skill_fx.get("active",false)) and str(audit.skill_fx.get("skill_id",""))==skill:
			var animation: Dictionary = stage.get("actor_nodes").player.call("get_animation_audit")
			return {"animation":{"source_clip":animation.get("source_clip",""),"elapsed":animation.get("elapsed",-1.0),"source_seconds":animation.get("source_seconds",-1.0),"animation_player_path":animation.get("animation_player_path","")},"fx":audit.skill_fx,"light":audit.combat_light,"active_attack_cells":audit.active_attack_cells}
		await process_frame
	_check(false,"The real "+skill+" impact is observed before completion")
	return {}

func _check_clip_resource(peak: Dictionary, clip: String) -> void:
	var player := root.get_node_or_null(NodePath(str(peak.animation.animation_player_path))) as AnimationPlayer
	var animation: Animation = player.get_animation(clip) if player != null and player.has_animation(clip) else null
	_check(animation != null and animation.length > 0.20 and animation.get_track_count() > 0 and absf(float(peak.animation.source_seconds)-0.13)<=0.025, "The reported clip is a real populated AnimationPlayer resource sampled near its authored impact pose")

func _observe_feedback(_text: String, _tone: String) -> void:
	var audit: Dictionary = _view().get("_stage").call("audit")
	if audit.feedback_history.is_empty(): return
	var kind := str(audit.feedback_history[-1].type)
	if kind in ["attack","hit"]:
		_feedback_samples.append({"kind":kind,"event":audit.active_event,"presented_hp":audit.presented_hp,"at_ms":audit.feedback_history[-1].at_ms})

func _check_cleanup() -> void:
	var fx := _fx()
	var light: Dictionary = _view().get("_stage").call("audit").combat_light
	_check(not bool(fx.active) and str(fx.phase)=="idle" and int(fx.mesh_count)==0 and int(fx.audio_player_count)==0, "Idle frees every martial-effect mesh and audio player")
	_check(not bool(light.active) and int(light.light_count)==0 and int(light.arc_mesh_count)==0, "Idle also frees the original transient combat light and arc")

func _fx() -> Dictionary:
	return _view().get("_stage").call("audit").get("skill_fx",{})

func _context() -> Dictionary:
	var audit: Dictionary = _view().audit_snapshot()
	return {"host":app.get("_session").snapshot().duplicate(true),"battle":_battle().duplicate(true),"selected":audit.selected,"action":audit.action,"preview":audit.preview.duplicate(true)}

func _camera(stage: Control) -> Dictionary:
	var c: Camera3D = stage.get("camera")
	return {"transform":c.transform,"size":c.size,"near":c.near,"far":c.far,"projection":c.projection}

func _actors(stage: Control) -> Dictionary:
	var result := {}
	for id: String in stage.get("actor_nodes"):
		var actor: Node3D = stage.get("actor_nodes")[id]
		result[id]={"transform":actor.transform,"processing":actor.is_processing(),"visible":actor.visible}
	return result

func _find(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.id)==id:return row
	return {}

func _same_set(a: Array,b: Array) -> bool:
	return a.size()==b.size() and a.all(func(value):return value in b)

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

func _key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.pressed=pressed
		root.push_input(event)
		await process_frame

func _raw_click(id: String) -> void:
	var button: Control = _view().ui_control(id)
	var at: Vector2 = root.get_final_transform()*(button.get_global_transform_with_canvas()*(button.size*.5))
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=at
		event.global_position=at
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event)

func _finish() -> void:
	var report := {"test":"mountain_ambush_martial_skills_ui","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"captures":captures,"window":[qa_size.x,qa_size.y],"display_server":DisplayServer.get_name(),"input":"Actual Godot root.push_input including scaled pointer clicks on embedded PopupMenu rows; native Compatibility, not browser or physical input","popup_boundary":"Uses the existing embedded-subwindow setting; no runtime configuration change or direct item selection API","audio_boundary":"Audio play counters/history under Dummy verify scheduling and mute, not heard audio","fixture_boundary":"Only authored_opening is the unchanged starting layout; explicitly labelled legal fixture trials reposition blade through public configure","presentation_previews":_previews,"actual_trials":_trials}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n")
	print("AMBUSH SKILLS UI: %d checks, %d failures, %d captures" % [checks,failures.size(),captures.size()])
	quit(1 if not failures.is_empty() else 0)
