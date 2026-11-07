extends "res://tests/cultivation_engine_ambush_render.gd"
## Real native Compatibility UI events and actual light-node state.
## Light/shadow flags and screenshots do not establish shadow-pixel quality,
## browser performance, physical input or aesthetic acceptance.

var _replays: Array[Dictionary] = []
var _action_traces: Array[Dictionary] = []
var _hit_timing_samples: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/ambush-combat-light/render"
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
	_check(DisplayServer.get_name() != "headless", "Combat-light review uses a real rendered Compatibility window")
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
	_check(is_instance_valid(_view()), "The real mountain-road encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	_check_light_row_layout()
	var stage: Control = _view().get("_stage")
	_check(_view().audit_snapshot().has("combat_light_mode") and _view().audit_snapshot().has("replaying") and stage.call("audit").has("combat_light"), "The shipped view and stage expose their combat-light audit contract")
	if not stage.call("audit").has("combat_light"):
		_finish()
		return
	stage.connect("feedback_changed", _observe_hit_timing)
	var expected_timing := {"ready_seconds": 0.24, "strike_seconds": 0.10, "hit_stop_seconds": 0.08, "follow_through_seconds": 0.13, "recover_seconds": 0.30, "hit_at_seconds": 0.34, "total_seconds": 0.85, "source_hit_seconds": 0.13}
	var actual_timing: Dictionary = stage.call("audit").get("attack_timing", {})
	_check(expected_timing.keys().all(func(key: String) -> bool: return absf(float(actual_timing.get(key, -1.0)) - float(expected_timing[key])) < 0.000001), "The battle exposes the authored preparation, strike, hit-stop, follow-through and recovery timing")
	_check_mode(2)
	_check_effect_idle()
	_check(bool(stage.call("lighting_audit").enhanced), "A fresh encounter retains enhanced environmental lighting")
	await _capture("00-combat-light-idle.png")
	# Freeze scenery through the shipped UI, leaving combat and replay active.
	var unchanged: Dictionary = _authoritative_context()
	await _click("EnvironmentMotionButton")
	_check(_authoritative_context() == unchanged, "The scenery toggle preserves exact authoritative state")
	var landscape: Node3D = stage.get("_landscape")
	_check(bool(landscape.call("audit").static), "Scenery remains independently static during the lighting experiment")
	var frozen_elapsed: float = float(landscape.call("audit").elapsed)
	var initial_light_count: int = _actual_light_count(stage)
	# Cycle from the default 2 to 0, then exercise all modes through real buttons.
	await _cycle_mode(0)
	for mode: int in [0, 1, 2]:
		if mode > 0:
			await _cycle_mode(mode)
		await _replay(mode, "%02d-replay-mode-%d.png" % [mode + 1, mode], true)
		_check(_actual_light_count(stage) == initial_light_count, "Mode %d replay adds no accumulated light nodes" % mode)
		_check(bool(landscape.call("audit").static) and is_equal_approx(float(landscape.call("audit").elapsed), frozen_elapsed), "Mode %d replay cannot resume or advance frozen scenery" % mode)
	# Repeat one trial under the original environmental lighting. Its exact
	# settings must be restored after the temporary combat-light contribution.
	unchanged = _authoritative_context()
	await _click("LightingModeButton")
	_check(_authoritative_context() == unchanged and not bool(stage.call("lighting_audit").enhanced), "The original environmental-lighting button remains independent of combat mode")
	_check_mode(2)
	await _replay(2, "04-original-profile-replay.png", false)
	unchanged = _authoritative_context()
	await _click("LightingModeButton")
	_check(_authoritative_context() == unchanged and bool(stage.call("lighting_audit").enhanced), "The enhanced environmental profile can be restored after the original-profile replay")
	_check_mode(2)
	# Real actions continue to use the same authoritative barricade encounter.
	var host_before: Dictionary = app.get("_session").snapshot().duplicate(true)
	var lighting_before: Dictionary = stage.call("lighting_audit")
	await _click("Skill_push")
	await _hover_tile([4, 3])
	var preview: Dictionary = _view().audit_snapshot().preview
	_check(preview.get("push_to", []) == [5, 3] and int(preview.get("damage", -1)) == 5 and str(preview.get("collision_barricade_id", "")) == "north_gate", "Skill-lighting mode retains the actual five-damage stop-before-barricade preview")
	var action_camera_before: Dictionary = _camera_state(stage)
	await _mouse(_view().audit_tile_center([4, 3]), true)
	await _observe_action("real_player_push", true, action_camera_before)
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "The real illuminated shove still stops at the fence and destroys it with exact damage")
	_check(bool(_unit("player").acted) and not bool(_unit("player").moved) and int(_barricade("south_gate").hp) == 6, "The real shove consumes only its existing action and preserves the other route")
	_check(app.get("_session").snapshot() == host_before and stage.call("lighting_audit") == lighting_before, "Real shove lighting restores its exact profile without host settlement")
	_check_effect_idle()
	await _capture("05-real-push-barricade.png")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	action_camera_before = _camera_state(stage)
	await _mouse(_view().audit_tile_center([5, 4]), true)
	await _observe_action("real_tinglan_interrupt", true, action_camera_before)
	_check(bool(_plan("blade").get("interrupted", false)) and int(_unit("blade").hp) == 8, "The real illuminated interrupt keeps exact damage and cancels the existing plan")
	_check(app.get("_session").snapshot() == host_before and stage.call("lighting_audit") == lighting_before, "Interrupt lighting adds no host action or lasting environment change")
	_check_effect_idle()
	await _capture("06-real-interrupt.png")
	var end_button: Button = _view().ui_control("EndRoundButton") as Button
	action_camera_before = _camera_state(stage)
	await _mouse(end_button.get_global_transform_with_canvas() * (end_button.size * 0.5), true)
	await _observe_action("enemy_round", false, action_camera_before)
	_check(int(_battle().round) == 2 and int(_battle().objective.hp) == 15, "Enemy playback resolves the original advertised miss, interrupt and arrow damage")
	_check(app.get("_session").snapshot() == host_before, "The enemy round and lighting add no premature host settlement")
	_check_effect_idle()
	_check(bool(landscape.call("audit").static) and is_equal_approx(float(landscape.call("audit").elapsed), frozen_elapsed), "Real combat and enemy playback leave frozen scenery exactly frozen")
	await _capture("07-enemy-round.png")
	# Leave a nondefault mode before restarting to prove the new default.
	await _cycle_mode(0)
	var old_viewport: WeakRef = weakref(stage.get("viewport"))
	var old_helper: WeakRef = weakref(stage.get("_combat_light"))
	var sequence_before: int = int(app.get("_session").snapshot().sequence)
	await _click("RestartButton")
	_check(old_viewport.get_ref() == null and old_helper.get_ref() == null, "Restart releases the previous combat-light helper and viewport")
	_check(int(app.get("_session").snapshot().sequence) == sequence_before + 1, "Restart retains exactly one abandoned-attempt settlement")
	_check_mode(2)
	_check_effect_idle()
	stage = _view().get("_stage")
	_check(bool(stage.call("lighting_audit").enhanced) and not bool(stage.get("_landscape").call("audit").static), "A new encounter restores its existing enhanced and dynamic scene defaults")
	_check(int(_battle().round) == 1 and int(_battle().objective.hp) == 18 and int(_barricade("north_gate").hp) == 6, "Restart restores the same original battle defaults and intact barricade")
	_check_layout()
	_check_light_row_layout()
	await _capture("08-restart-default-mode.png")
	old_viewport = weakref(stage.get("viewport"))
	old_helper = weakref(stage.get("_combat_light"))
	sequence_before = int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_viewport.get_ref() == null and old_helper.get_ref() == null, "Returning releases the combat-light helper and its viewport")
	_check(app.get("_session").snapshot().scene == "shanxia_town" and app.get("_session").snapshot().phase == "result" and int(app.get("_session").snapshot().sequence) == sequence_before + 1, "Return preserves the original town and single withdrawal settlement")
	await _capture("09-combat-light-return.png")
	_finish()


func _replay(mode: int, filename: String, exercise_gates: bool) -> void:
	var stage: Control = _view().get("_stage")
	var button: Button = _view().ui_control("CombatLightReplayButton") as Button
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "Mode %d replay uses the actual available UI button" % mode)
	if button == null or button.disabled:
		return
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	await _mouse(point, false)
	var before: Dictionary = _authoritative_context()
	var actor_before: Dictionary = _actor_state(stage)
	var camera_before: Dictionary = _camera_state(stage)
	var camera_peak: Dictionary = {}
	var lighting_before: Dictionary = stage.call("lighting_audit")
	var idle_effect_before: Dictionary = _light().duplicate(true)
	await _mouse(point, true)
	_check(bool(_view().audit_snapshot().busy) and bool(_view().audit_snapshot().replaying), "Mode %d real replay immediately owns the busy/replaying gate" % mode)
	_check(str(stage.call("audit").presentation_phase) == "light_preview", "The stage explicitly marks the presentation-only replay")
	_check(_authoritative_context() == before, "Mode %d replay start preserves exact host, battle and tactical context" % mode)
	if exercise_gates:
		await _exercise_busy_gates(mode, before)
	var peak: Dictionary = await _wait_replay_peak()
	_check(not peak.is_empty() and bool(peak.get("active", false)) and int(peak.get("mode", -1)) == mode, "Mode %d replay reaches its own actual helper impact phase" % mode)
	if not peak.is_empty():
		camera_peak = _camera_state(stage)
		_check(absf(float(camera_peak.get("size", -1.0)) - float(camera_before.get("size", -1.0)) * 0.78) <= maxf(0.0001, float(camera_before.get("size", -1.0)) * 0.001), "Mode %d preview peak uses the same 0.78 orthographic zoom" % mode)
		_check(camera_peak.transform == camera_before.transform and camera_peak.near == camera_before.near and camera_peak.far == camera_before.far and camera_peak.projection == camera_before.projection, "Mode %d preview zoom preserves actual camera transform, projection and clip planes" % mode)
		_check_peak(peak, mode)
		_check(str(stage.call("audit").presentation_phase) == "light_preview" and bool(_view().audit_snapshot().replaying), "The peak remains a presentation-only replay")
		if mode == 2 and bool(lighting_before.enhanced):
			for previous: Dictionary in _replays:
				if int(previous.mode) == 1 and str(previous.lighting_profile) == "enhanced":
					var same_envelope := true
					for property: String in ["energy", "sun_energy", "fill_energy", "glow_enabled", "glow_intensity", "exposure", "light_position", "light_color", "light_range", "arc_alpha", "arc_mesh_count"]:
						same_envelope = same_envelope and peak.get(property) == previous.peak.get(property)
					_check(same_envelope, "Modes one and two use the same actual light, arc and exposure envelope apart from local shadows")
		await _capture(filename)
	await _idle()
	_check(not bool(_view().audit_snapshot().replaying), "Mode %d replay clears its replay gate on completion" % mode)
	_check(_authoritative_context() == before, "Mode %d complete replay preserves exact host, HP, barricades, moves, actions and tactical context" % mode)
	_check(_actor_state(stage) == actor_before, "Mode %d replay restores every actor's exact root transform, visibility and processing state" % mode)
	_check(_camera_state(stage) == camera_before, "Mode %d replay restores exact camera transform, size, projection, near and far" % mode)
	_check(stage.call("lighting_audit") == lighting_before, "Mode %d replay restores the selected environmental profile exactly" % mode)
	_check(bool(_light().get("glow_enabled", true)) == bool(idle_effect_before.get("glow_enabled", false)) and is_equal_approx(float(_light().get("sun_energy", -1.0)), float(idle_effect_before.get("sun_energy", -2.0))), "Mode %d replay restores actual glow state and sun energy exactly" % mode)
	_check_effect_idle()
	_check_mode(mode)
	_check(not (_view().ui_control("CombatLightReplayButton") as Button).disabled and not (_view().ui_control("CombatLightModeButton") as Button).disabled, "Mode %d replay restores its comparison controls" % mode)
	_replays.append({"mode": mode, "lighting_profile": lighting_before.profile, "peak": peak, "before": before, "after": _authoritative_context(), "actor_restore_exact": _actor_state(stage) == actor_before, "camera_before": camera_before, "camera_peak": camera_peak, "camera_after": _camera_state(stage), "camera_restore_exact": _camera_state(stage) == camera_before})


func _exercise_busy_gates(mode: int, before: Dictionary) -> void:
	for id: String in ["CombatLightReplayButton", "CombatLightModeButton", "LightingModeButton", "RestartButton", "ReturnButton", "EndRoundButton", "InspectCharactersButton", "Skill_push", "Skill_strike", "Skill_interrupt", "Skill_guard", "Unit_player", "Unit_tinglan", "MoveButton", "Skill_pierce", "Skill_sweep", "SoundToggleButton", "SkillPreviewChoice", "PalmVfxReplayButton", "PalmStyleChoice"]:
		var button: BaseButton = _view().ui_control(id) as BaseButton
		_check(button != null and button.disabled, "Replay mode %d disables %s" % [mode, id])
	# Queue real root input while the gate is known busy. Sending these in one
	# frame avoids allowing slow test machines to finish the short replay first.
	for id: String in ["CombatLightReplayButton", "CombatLightModeButton", "LightingModeButton", "RestartButton", "InspectCharactersButton", "EndRoundButton"]:
		_raw_click_now(id)
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = pressed
		root.push_input(key)
	await process_frame
	_check(_authoritative_context() == before and int(_view().audit_snapshot().combat_light_mode) == mode, "Mode %d replay rejects repeated playback, mode changes, Space, restart, inspection and hidden turns" % mode)
	_check(not is_instance_valid(_view().get("_character_inspector")), "Replay busy input cannot open a hidden character-inspection viewport")


func _raw_click_now(id: String) -> void:
	var button: Control = _view().ui_control(id)
	if button == null:
		return
	var point: Vector2 = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)


func _wait_replay_peak() -> Dictionary:
	var deadline := Time.get_ticks_msec() + 4000
	while is_instance_valid(_view()) and Time.get_ticks_msec() < deadline:
		var light: Dictionary = _light()
		if bool(light.get("active", false)) and str(light.get("phase", "")) == "impact":
			return light
		if not bool(_view().audit_snapshot().replaying):
			break
		await process_frame
	_check(false, "The actual replay impact phase is observed before its deadline")
	return {}


func _observe_action(label: String, should_activate: bool, camera_before: Dictionary) -> void:
	var samples: Array[Dictionary] = []
	var activated := false
	var stage: Control = _view().get("_stage")
	var actor_id := "player" if label == "real_player_push" else "tinglan"
	var skill_id := "push" if label == "real_player_push" else "interrupt"
	var plateau: Dictionary = {}
	var camera_peak: Dictionary = camera_before.duplicate()
	var max_camera_blend := 0.0
	var enemy_camera_unchanged := true
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(_view()) and bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		var audit: Dictionary = stage.call("audit")
		var camera_now: Dictionary = _camera_state(stage)
		var blend: float = float(audit.get("camera_action_blend", -1.0))
		if blend > max_camera_blend:
			max_camera_blend = blend
			camera_peak = camera_now
		enemy_camera_unchanged = enemy_camera_unchanged and is_zero_approx(blend) and camera_now == camera_before
		var light: Dictionary = _light()
		if bool(light.get("active", false)):
			activated = true
			if samples.is_empty() or str(samples[-1].phase) != str(light.get("phase", "")):
				samples.append(light)
		if should_activate and plateau.is_empty():
			for hit: Dictionary in _hit_timing_samples:
				if str(hit.unit_id) != actor_id or str(hit.skill_id) != skill_id:
					continue
				var after_hit_ms: int = Time.get_ticks_msec() - int(hit.hit_at_ms)
				if after_hit_ms >= 40:
					var animation: Dictionary = (stage.get("actor_nodes")[actor_id] as Node3D).call("get_animation_audit")
					plateau = {"after_hit_ms": after_hit_ms, "actor_mode": animation.get("mode", ""), "actor_elapsed": animation.get("elapsed", -1.0), "attack_source_clock": animation.get("attack_source_clock", -1.0), "attack_real_elapsed": animation.get("attack_real_elapsed", -1.0), "attack_timing_enabled": animation.get("attack_timing_enabled", false), "busy": bool(_view().audit_snapshot().busy), "helper_phase": light.get("phase", ""), "presentation_phase": audit.get("presentation_phase", "")}
					break
		await process_frame
	_check(activated == should_activate, "Actual %s %s the player-only combat light" % [label, "activates" if should_activate else "does not activate"])
	await _idle()
	if should_activate:
		_check(max_camera_blend >= 0.999 and absf(float(camera_peak.size) - float(camera_before.size) * 0.88) <= float(camera_before.size) * 0.001, "Actual %s reaches the restrained friendly attack camera focus" % label)
		var before_transform: Transform3D = camera_before.transform
		var peak_transform: Transform3D = camera_peak.transform
		_check(peak_transform.basis == before_transform.basis and peak_transform.origin.distance_to(before_transform.origin) > 0.001 and peak_transform.origin.distance_to(before_transform.origin) <= 1.35 and camera_peak.near == camera_before.near and camera_peak.far == camera_before.far and camera_peak.projection == camera_before.projection, "Actual %s camera shifts within its bounded focus without rotating or changing clip planes" % label)
	else:
		_check(enemy_camera_unchanged, "Enemy playback never starts a friendly camera focus")
	_check(_camera_state(stage) == camera_before and is_zero_approx(float(stage.call("audit").get("camera_action_blend", -1.0))), "Actual %s restores the exact playable camera before accepting another action" % label)
	var timing: Dictionary = {}
	if should_activate:
		var matching: Array = _hit_timing_samples.filter(func(row: Dictionary) -> bool: return str(row.unit_id) == actor_id and str(row.skill_id) == skill_id)
		_check(matching.size() == 1, "Actual %s records exactly one synchronous source-pose hit" % label)
		if not matching.is_empty():
			timing = matching[0]
			_check(int(timing.attack_to_hit_ms) >= 310 and int(timing.attack_to_hit_ms) <= 430, "Actual %s reaches its authored 0.34 second hit within the 310–430 ms window" % label)
			_check(str(timing.actor_mode) == "attack" and bool(timing.attack_timing_enabled) and absf(float(timing.actor_elapsed) - 0.13) <= 0.02 and absf(float(timing.attack_source_clock) - 0.13) <= 0.02, "Actual %s nonlinear attack still hits at the authored 0.13 second source pose" % label)
			_check(bool(timing.busy) and bool(timing.helper_active) and str(timing.helper_phase) == "impact", "Actual %s keeps input busy and the skill light synchronized at the real hit" % label)
			_check(absf(float(timing.windup_wall_seconds) - 0.34) < 0.000001 and absf(float(timing.recovery_wall_seconds) - 0.30) < 0.000001 and absf(float(timing.impact_hold_seconds) - 0.21) < 0.000001, "Actual %s skill light follows preparation, impact hold and recovery in wall time" % label)
		_check(not plateau.is_empty() and int(plateau.get("after_hit_ms", -1)) >= 40 and int(plateau.get("after_hit_ms", 1000)) <= 75, "Actual %s observes the source-pose plateau about forty milliseconds after its hit" % label)
		_check(str(plateau.get("actor_mode", "")) == "attack" and bool(plateau.get("attack_timing_enabled", false)) and absf(float(plateau.get("actor_elapsed", -1.0)) - 0.13) <= 0.005 and absf(float(plateau.get("attack_source_clock", -1.0)) - 0.13) <= 0.005 and bool(plateau.get("busy", false)) and str(plateau.get("helper_phase", "")) == "impact", "Actual %s holds the same 0.13 second source pose during the 0.08 second hit-stop" % label)
	_action_traces.append({"action": label, "expected_active": should_activate, "observed_active": activated, "phase_samples": samples, "hit_timing": timing, "hit_stop_sample": plateau, "camera_before": camera_before, "camera_peak": camera_peak, "camera_after": _camera_state(stage), "camera_max_blend": max_camera_blend, "camera_restore_exact": _camera_state(stage) == camera_before, "enemy_camera_unchanged": enemy_camera_unchanged if not should_activate else null})


func _observe_hit_timing(_text: String, _tone: String) -> void:
	var stage: Control = _view().get("_stage")
	var audit: Dictionary = stage.call("audit")
	var history: Array = audit.feedback_history
	if history.is_empty() or str(history[-1].type) != "hit":
		return
	var event: Dictionary = audit.active_event
	var actor_id := str(event.get("unit_id", ""))
	if actor_id not in ["player", "tinglan"]:
		return
	var attack_at_ms := -1
	for index: int in range(history.size() - 2, -1, -1):
		if str(history[index].type) == "attack":
			attack_at_ms = int(history[index].at_ms)
			break
	var actor: Node3D = stage.get("actor_nodes")[actor_id]
	var animation: Dictionary = actor.call("get_animation_audit")
	var light: Dictionary = audit.combat_light
	# elapsed is the short action clock; source_seconds is a position inside
	# the original GLB clip and can have a different origin for Jiang's sword.
	_hit_timing_samples.append({"unit_id": actor_id, "skill_id": str(event.get("skill_id", "")),
		"attack_at_ms": attack_at_ms, "hit_at_ms": int(history[-1].at_ms),
		"attack_to_hit_ms": int(history[-1].at_ms) - attack_at_ms if attack_at_ms >= 0 else -1,
		"actor_mode": animation.get("mode", ""), "actor_elapsed": animation.get("elapsed", -1.0),
		"attack_timing_enabled": animation.get("attack_timing_enabled", false), "attack_real_elapsed": animation.get("attack_real_elapsed", -1.0), "attack_source_clock": animation.get("attack_source_clock", -1.0),
		"source_clip": animation.get("source_clip", ""), "source_seconds": animation.get("source_seconds", -1.0),
		"busy": bool(_view().audit_snapshot().busy), "helper_active": light.get("active", false), "helper_phase": light.get("phase", ""),
		"stage_rate": audit.get("action_playback_speed", -1.0), "actor_rate": actor.get("action_playback_speed"), "helper_rate": light.get("action_playback_speed", -1.0), "attack_timing": audit.get("attack_timing", {}),
		"windup_wall_seconds": light.get("windup_wall_seconds", -1.0), "recovery_wall_seconds": light.get("recovery_wall_seconds", -1.0), "impact_hold_seconds": light.get("impact_hold_seconds", -1.0)})


func _check_peak(light: Dictionary, mode: int) -> void:
	_check(bool(light.get("light_visible", mode == 0)) == (mode > 0), "Mode %d actual light visibility matches its selected effect" % mode)
	_check(bool(light.get("shadow_enabled", mode != 2)) == (mode == 2), "Mode %d actual local shadow flag matches the selected comparison" % mode)
	_check((float(light.get("energy", -1.0)) > 0.0) if mode > 0 else is_zero_approx(float(light.get("energy", -1.0))), "Mode %d actual light energy matches its selected comparison" % mode)
	if mode == 0:
		_check(int(light.get("light_count", -1)) == 0 and str(light.get("point_light_path", "missing")).is_empty(), "Original presentation creates no transient point-light node")
	else:
		_check(int(light.get("light_count", -1)) == 1 and not str(light.get("point_light_path", "")).is_empty(), "The illuminated comparison reports its single real point-light node")
		var point: OmniLight3D = root.get_node_or_null(NodePath(str(light.get("point_light_path", "")))) as OmniLight3D
		_check(point != null and point.visible and point.shadow_enabled == (mode == 2) and is_equal_approx(point.light_energy, float(light.get("energy", -1.0))), "The audit matches actual OmniLight3D visibility, shadow flag and energy")
	var position: Variant = light.get("light_position")
	_check(position is Vector3 and (position as Vector3).is_finite(), "The actual skill-light position is finite")
	if mode == 0:
		_check(not bool(light.get("glow_enabled", true)), "Original presentation adds no environment glow")
	# No assertion here treats a shadow_enabled flag as rendered shadow pixels.


func _check_effect_idle() -> void:
	var light: Dictionary = _light()
	_check(not bool(light.get("active", true)) and str(light.get("phase", "")) == "idle" and not bool(light.get("light_visible", true)) and is_zero_approx(float(light.get("energy", -1.0))), "Idle leaves no active or energy-emitting skill light")
	_check(not bool(_view().audit_snapshot().get("replaying", true)), "Idle leaves no active replay")
	_check(int(light.get("light_count", -1)) == 0 and str(light.get("point_light_path", "missing")).is_empty(), "Idle frees the transient point light after every trial and real action")
	_check(int(light.get("arc_mesh_count", -1)) == 0 and not bool(light.get("arc_visible", true)), "Idle frees every transient arc mesh and leaves no visible skill arc")


func _cycle_mode(expected: int) -> void:
	var button: Button = _view().ui_control("CombatLightModeButton") as Button
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "The actual combat-light mode button is usable")
	if button == null or button.disabled:
		return
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	await _mouse(point, false)
	var before: Dictionary = _authoritative_context()
	var stage: Control = _view().get("_stage")
	var profile: Dictionary = stage.call("lighting_audit")
	await _mouse(point, true)
	await _idle()
	_check_mode(expected)
	_check(_authoritative_context() == before and stage.call("lighting_audit") == profile, "Mode switching preserves exact host, battle, tactical context and environmental profile")


func _check_mode(expected: int) -> void:
	_check(int(_view().audit_snapshot().get("combat_light_mode", -1)) == expected and int(_light().get("mode", -1)) == expected, "View and actual helper agree on combat-light mode %d" % expected)
	var button: Button = _view().ui_control("CombatLightModeButton") as Button
	_check(button != null and button.focus_mode == Control.FOCUS_NONE, "The comparison button cannot steal the battle's Space focus")
	if button != null:
		_check(("原演出" in button.text) if expected == 0 else (("投影" in button.text) if expected == 2 else ("招式光" in button.text and not "投影" in button.text)), "The real button label describes combat-light mode %d" % expected)


func _check_light_row_layout() -> void:
	var mode: Control = _view().ui_control("CombatLightModeButton")
	var replay: Control = _view().ui_control("CombatLightReplayButton")
	_check(mode != null and replay != null, "Both combat-light controls belong to the actual view")
	if mode == null or replay == null:
		return
	var objective: Control = _view().get("_objective_panel")
	var header_control: Control = _view().ui_control("EnvironmentMotionButton")
	_check(not mode.get_global_rect().intersects(replay.get_global_rect()), "Combat-light mode and replay buttons do not overlap")
	_check(mode.get_global_rect().end.y <= objective.get_global_rect().position.y and replay.get_global_rect().end.y <= objective.get_global_rect().position.y, "The new comparison row stays above the objective panel")
	_check(header_control.get_global_rect().end.y <= mode.get_global_rect().position.y, "The comparison row stays below the original header controls")


func _authoritative_context() -> Dictionary:
	var audit: Dictionary = _view().audit_snapshot()
	return {"host": app.get("_session").snapshot().duplicate(true), "battle": _battle().duplicate(true), "selected": audit.selected, "action": audit.action, "preview": (audit.preview as Dictionary).duplicate(true)}


func _actor_state(stage: Control) -> Dictionary:
	var result: Dictionary = {}
	for id: String in stage.get("actor_nodes"):
		var actor: Node3D = stage.get("actor_nodes")[id]
		result[id] = {"transform": actor.transform, "processing": actor.is_processing(), "visible": actor.visible}
	return result


func _camera_state(stage: Control) -> Dictionary:
	var camera: Camera3D = stage.get("camera")
	return {"transform": camera.transform, "size": camera.size, "projection": camera.projection, "near": camera.near, "far": camera.far}


func _actual_light_count(stage: Control) -> int:
	return stage.get("world_root").find_children("*", "Light3D", true, false).size()


func _light() -> Dictionary:
	return _view().get("_stage").call("audit").get("combat_light", {})


func _finish() -> void:
	var report := {"test": "mountain_ambush_combat_light_ui", "checks": checks, "failures": failures, "captures": captures, "replays": _replays, "actual_action_traces": _action_traces, "hit_timing_samples": _hit_timing_samples, "timing_boundary": "Attack/hit feedback at_ms measures native wall-clock delay; actor_elapsed measures the short source action, not absolute GLB source_seconds", "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input events; not physical input or browser", "visual_boundary": "Light-node flags and screenshots do not by themselves prove shadow-pixel quality or user acceptance", "result": "PASS" if failures.is_empty() else "FAIL"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH COMBAT LIGHT UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
