extends "res://tests/cultivation_martial_fullbody_ui_test.gd"
## Actual native/PCK root input in the shipped encounter, without board fixtures.
## The separate hidden release reference samples the same immutable motion asset;
## it never samples or mutates the live MovePlayer or authoritative battle.
const PalmActor := preload("res://addons/cultivation_mode/ambush_actor.gd")
var _palm_trials: Array[Dictionary] = []
var _order_trials: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/sword-palm/ui"
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
	_check(DisplayServer.get_name() != "headless", "Sword/palm integration uses the actual native Compatibility renderer")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var loaded := Catalog.load_catalog()
	_check(bool(loaded.get("ok", false)), "The unchanged original workshop catalog and enhanced motion assets load")
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
	_check(_unit("player").pos == [3, 3] and _unit("tinglan").pos == [5, 5] and _unit("blade").pos == [5, 4], "The new palm preserves the established authored opening")
	await _capture("00-sword-palm-opening.png")
	await _click("Unit_tinglan")
	await _click("Skill_palm")
	_check(str((_view().ui_control("Skill_palm") as Button).text).contains("劲风掌"), "The real combat toolbar exposes Tinglan's named palm skill")
	_check_palm_button_layout()
	await _illegal_palms()
	await _real_palm()
	await _workshop_palm_unchanged()
	await _click("RestartButton")
	_check(int(_unit("blade").hp) == 10 and _unit("blade").pos == [5, 4] and not bool(_unit("tinglan").acted), "Restart restores exact enemy position, HP and the new palm action")
	_check_battle_clean()
	await _order_comparison()
	await _lethal_palm()
	await _stationary_palm()
	var stage: Control = _view().get("_stage")
	var viewport_ref: WeakRef = weakref(stage.get("viewport"))
	var sequence := int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and viewport_ref.get_ref() == null, "Returning releases the live palm viewport and all combat presentation owners")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Returning settles only the current unfinished encounter through the original host")
	await _capture("09-sword-palm-return-town.png")
	_finish()


func _check_palm_button_layout() -> void:
	var button := _view().ui_control("Skill_palm") as Button
	var bounds := Rect2(Vector2.ZERO, app.size)
	var rect := button.get_global_rect()
	_check(bounds.encloses(rect) and rect.size.x > 0 and rect.size.y >= 38, "The real palm button has a usable on-screen hit area")
	for id: String in ["MoveButton", "Skill_strike", "Skill_interrupt", "Skill_guard"]:
		var other: Control = _view().ui_control(id)
		_check(other.is_visible_in_tree() and not rect.intersects(other.get_global_rect()), "The palm button does not cover Tinglan's existing control " + id)


func _illegal_palms() -> void:
	for tile: Array in [[7, 1], [6, 4], [6, 5], [4, 5]]:
		var before := _battle().duplicate(true)
		var host: Dictionary = app.get("_session").snapshot().duplicate(true)
		var stage: Control = _view().get("_stage")
		var begins := int(stage.call("workshop_audit").get("begin_count", 0))
		await _hover_tile(tile)
		_check(not bool(_view().audit_snapshot().preview.get("ok", true)), "The actual palm preview rejects out-of-range, rock, intact fence or empty cell " + str(tile))
		await _mouse(_view().audit_tile_center(tile), true)
		await _frames(2)
		_check(_battle() == before and app.get("_session").snapshot() == host and not bool(_view().audit_snapshot().busy), "Rejected palm target spends no HP, movement, action, revision or host time " + str(tile))
		_check(int(stage.call("workshop_audit").get("begin_count", 0)) == begins, "Rejected palm starts no hidden motion or effect " + str(tile))


func _real_palm() -> void:
	var stage: Control = _view().get("_stage")
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var camera_before := _camera(stage)
	var actor: Node3D = stage.get("actor_nodes").tinglan
	var target: Node3D = stage.get("actor_nodes").blade
	var actor_position := actor.position
	var target_position := target.position
	var actor_process := actor.is_processing()
	var target_process := target.is_processing()
	var player_before: Dictionary = stage.call("workshop_audit")
	var effect_before: Dictionary = stage.call("audit").palm_impact
	await _hover_tile([5, 4])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and str(forecast.get("target_id", "")) == "blade" and int(forecast.get("damage", -1)) == 3 and forecast.get("push_to", []) == [5, 2], "Opening palm honestly previews three damage and two free cells of displacement")
	await _capture("01-palm-real-forecast.png")
	await _mouse(_view().audit_tile_center([5, 4]), true)
	var committed := _battle().duplicate(true)
	_check(bool(_view().audit_snapshot().busy) and int(_unit("blade").hp) == 7 and _unit("blade").pos == [5, 2], "Rules commit one real palm with exact damage and displacement before presentation")
	_check(int(stage.call("audit").presented_hp.blade) == 10 and target.position == target_position, "Visible HP and the enemy root both wait at their original values during palm preparation")
	for id: String in ["Skill_palm", "MoveButton", "EndRoundButton", "RestartButton", "ReturnButton", "MartialWorkshopButton"]:
		_check((_view().ui_control(id) as BaseButton).disabled, "The full palm gates real control " + id)
	_raw_fullbody_click("Skill_palm")
	_raw_fullbody_click("EndRoundButton")
	_raw_fullbody_click("RestartButton")
	_check(_battle() == committed and app.get("_session").snapshot() == host, "Busy repeated root input cannot double-hit, restart or advance an enemy round")
	var enhanced := Catalog.find_move(_catalog, "palm_gale", "enhanced")
	var independent_origin := _independent_palm_release(actor, enhanced, stage)
	var expected_aim: Vector3 = target.global_position + Vector3.UP * 0.72
	var samples: Array[Dictionary] = []
	var holds: Array[Dictionary] = []
	var deferred: Array[Dictionary] = []
	var first_hit := -1.0
	var early_samples := 0
	var flight_seen := false
	var recovery_seen := false
	var intermediate_push_seen := false
	var captured_prepare := false
	var captured_hit := false
	var captured_recovery := false
	var deadline := Time.get_ticks_msec() + 8000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var audit: Dictionary = stage.call("audit")
		var player: Dictionary = stage.call("workshop_audit")
		var effect: Dictionary = audit.palm_impact
		var time := float(player.get("elapsed", 0.0))
		var row := {"elapsed": time, "source_seconds": player.get("source_seconds", 0.0), "phase": audit.presentation_phase, "presented_hp": audit.presented_hp.blade, "actor_position": actor.position, "target_position": target.position, "effect": effect.duplicate(true), "combat": audit.combat_presentation.duplicate(true), "process_frame": Engine.get_process_frames()}
		samples.append(row)
		if bool(player.get("active", false)):
			_check(str(player.get("move_id", "")) == "palm_gale" and str(player.get("variant_id", "")) == "enhanced" and str(player.get("animation_asset", "")) == str(enhanced.animation.asset), "Real palm uses the existing enhanced open-left-palm full-body source")
			_check(absf(float(player.get("total", 0.0)) - 1.92) < 0.00001 and absf(float(player.get("impact_hold_seconds", 0.0)) - 0.07) < 0.00001, "Real palm keeps its full recovery and combat-only seventy-millisecond contact plateau")
		if time < 0.78 and bool(player.get("active", false)):
			early_samples += 1
			_check(int(audit.presented_hp.blade) == 10 and target.position == target_position, "Every completed preparation/flight frame preserves pre-impact HP and enemy position")
		if time >= 0.56 and time < 0.78 and bool(effect.get("active", false)):
			flight_seen = true
			_check((effect.release_origin as Vector3).distance_to(independent_origin) < 0.00005 and (effect.target as Vector3).distance_to(expected_aim) < 0.00005, "The visible gust starts at independently sampled actual left-palm release and aims at the original enemy chest")
		if int(audit.presented_hp.blade) == 7 and first_hit < 0.0:
			first_hit = time
		if bool(player.get("impact_hold_active", false)):
			row["body_pose"] = _bone_pose(actor)
			row["target_body"] = (target.get("body") as Node3D).transform
			holds.append(row)
			_check(int(audit.presented_hp.blade) == 7 and target.position == target_position, "Contact shows the single real damage while the enemy root stays planted through hit-stop")
		if target.position != target_position and target.position != (stage.call("_tile_world", [5, 2]) as Vector3):
			intermediate_push_seen = true
			_check(time > 0.85, "Actual displacement only advances after the shared palm contact plateau")
		if str(audit.presentation_phase) == "recovery" and time > 1.20 and bool(player.get("active", false)):
			recovery_seen = true
		if not captured_prepare and time >= 0.28 and time < 0.55:
			captured_prepare = true
			_defer_current_capture(deferred, "02-palm-step-and-chamber.png", player)
		elif not captured_hit and holds.size() >= 2:
			captured_hit = true
			_defer_current_capture(deferred, "03-palm-synchronized-contact.png", player)
		elif not captured_recovery and recovery_seen:
			captured_recovery = true
			_defer_current_capture(deferred, "04-palm-full-recovery.png", player)
		await process_frame
	await _idle()
	_save_deferred_captures(deferred)
	var after: Dictionary = stage.call("workshop_audit")
	var final: Dictionary = stage.call("audit")
	_check(early_samples > 0 and flight_seen and first_hit >= 0.78 and first_hit < 0.90, "Rendered preparation, free-flight and authored palm impact are observed separately")
	_check(holds.size() >= 2, "At least two completed contact samples preserve readable synchronized palm impact")
	if holds.size() >= 2:
		_check(holds[0].body_pose == holds[-1].body_pose and holds[0].target_body == holds[-1].target_body and absf(float(holds[0].source_seconds) - 0.78) < 0.00001 and absf(float(holds[-1].source_seconds) - 0.78) < 0.00001, "Actual palm bones and target recoil share the exact held source impact pose")
	_check(intermediate_push_seen and recovery_seen, "The real enemy visibly traverses its knockback and the palm remains busy through full recovery")
	_check(int(final.combat_presentation.damage_events) == 1 and int(final.combat_presentation.push_events) == 1 and int(final.combat_presentation.push_completed) == 1 and str(final.combat_presentation.push_clock) == "recipe elapsed", "One palm presents exactly one damage and one completed shove under the same recipe clock")
	_check(int(after.begin_count) == int(player_before.begin_count) + 1 and int(after.impact_count) == int(player_before.impact_count) + 1 and int(after.finish_count) == int(player_before.finish_count) + 1, "A single target click starts, impacts and finishes the unified move exactly once")
	_check(int(final.palm_impact.release_count) == int(effect_before.release_count) + 1 and int(final.palm_impact.impact_count) == int(effect_before.impact_count) + 1, "Real palm releases and impacts its directional effect exactly once")
	_check(_battle() == committed and int(_battle().revision) == int(before.revision) + 1 and bool(_unit("tinglan").acted) and not bool(_unit("tinglan").moved), "Whole-body playback spends one palm action, leaves movement available and never mutates the settled rules again")
	_check(app.get("_session").snapshot() == host and _battle().objective == before.objective and _battle().barricades == before.barricades, "Palm presentation changes no host time, medicine HP or untouched fence")
	_check(actor.position == actor_position and target.position == (stage.call("_tile_world", [5, 2]) as Vector3) and actor.is_processing() == actor_process and target.is_processing() == target_process and _camera(stage) == camera_before, "Recovery restores both actor process owners and camera while preserving the actual new enemy tile")
	_check_battle_clean()
	await _capture("05-palm-real-result.png")
	_palm_trials.append({"kind": "opening_real_palm", "forecast": forecast, "before": before, "after": _battle().duplicate(true), "independent_release_origin": independent_origin, "aim_original_chest": expected_aim, "first_hit_elapsed": first_hit, "early_samples": early_samples, "hold_samples": holds.size(), "flight_seen": flight_seen, "intermediate_push_seen": intermediate_push_seen, "recovery_seen": recovery_seen, "samples": samples})


func _independent_palm_release(live_actor: Node3D, move: Dictionary, stage: Control) -> Vector3:
	var reference := PalmActor.new()
	reference.name = "IndependentPalmReleaseReference"
	(stage.get("world_root") as Node3D).add_child(reference)
	reference.call("setup", "tinglan", "support", true)
	reference.transform = live_actor.transform
	reference.visible = false
	reference.set_process(false)
	var binding := Binding.new()
	var result: Dictionary = binding.bind_move(reference, move, _catalog.profiles.tinglan22)
	_check(bool(result.get("ok", false)), "A separate hidden real skeleton binds the immutable enhanced palm asset for release-origin comparison")
	binding.sample(float(move.timing.release))
	var origin: Vector3 = reference.call("get_palm_origin")
	binding.finish()
	reference.free()
	return origin


func _workshop_palm_unchanged() -> void:
	_parent_before = _context()
	await _open_workshop()
	if not is_instance_valid(_workshop()):
		return
	await _wclick("WorkshopMove_palm_gale")
	await _choose("WorkshopVariantChoice", 1)
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.26)
	await _wclick("WorkshopPauseButton")
	var player := _player().duplicate(true)
	_check(absf(float(player.get("total", 0.0)) - 1.85) < 0.00001 and is_zero_approx(float(player.get("impact_hold_seconds", 0.0))), "The independent workshop retains its original palm total and no combat-only hold")
	await _capture("06-palm-workshop-independent.png")
	await _close_workshop()
	_check(_context() == _parent_before, "Workshop playback after a real palm preserves exact host, board and selection state")
	_check_battle_clean()


func _prepare_order_position() -> void:
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([3, 4])
	_check(_unit("tinglan").pos == [3, 4] and bool(_unit("tinglan").moved) and not bool(_unit("tinglan").acted), "Three ordinary steps put Tinglan at the authored palm opening without spending her attack")
	await _click("Unit_player")
	await _click("MoveButton")
	_check(not [4, 4] in _view().get("_battle").call("reachable", "player"), "Before the palm, Tinglan and the brute close both short routes to the sword's follow-up tile")
	var before := _battle().duplicate(true)
	await _tile([4, 4])
	_check(_battle() == before and not bool(_unit("player").moved), "Trying that blocked route through the actual map consumes no movement or action")


func _collision_palm() -> void:
	await _click("Unit_tinglan")
	await _click("Skill_palm")
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and int(forecast.get("damage", -1)) == 5 and forecast.get("push_to", []) == [5, 3] and str(forecast.get("collision_barricade_id", "")) == "north_gate", "The actual diagonal palm preview uses the existing main-axis shove and predicts the north-fence collision")
	await _capture("07-palm-opens-follow-up-preview.png")
	var stage: Control = _view().get("_stage")
	var target: Node3D = stage.get("actor_nodes").brute
	var original := target.position
	var landing: Vector3 = stage.call("_tile_world", [5, 3])
	var before := _battle().duplicate(true)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	await _mouse(_view().audit_tile_center([4, 3]), true)
	var committed := _battle().duplicate(true)
	_check(int(_unit("brute").hp) == 9 and _unit("brute").pos == [5, 3] and int(_barricade("north_gate").hp) == 0, "The one authoritative palm commits the exact enemy and fence outcome")
	var rows: Array[Dictionary] = []
	var hold_frames := 0
	var travel_frames := 0
	var broken_at_landing := false
	var deadline := Time.get_ticks_msec() + 8000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var audit: Dictionary = stage.call("audit")
		var player: Dictionary = stage.call("workshop_audit")
		var gate: Dictionary = (audit.barricades as Array).filter(func(row): return str(row.id) == "north_gate")[0]
		rows.append({"elapsed": player.get("elapsed", 0.0), "source_seconds": player.get("source_seconds", 0.0), "position": target.position, "gate": gate.duplicate(true), "combat": audit.combat_presentation.duplicate(true)})
		if bool(player.get("impact_hold_active", false)):
			hold_frames += 1
			_check(target.position == original and int(gate.hp) == 6 and bool(gate.standing_visible) and not bool(gate.broken_visible), "During palm contact the enemy is planted and the not-yet-collided fence remains visibly intact")
		if target.position != original and target.position.distance_to(landing) > 0.00005:
			travel_frames += 1
			_check(int(gate.hp) == 6 and bool(gate.standing_visible) and not bool(gate.broken_visible), "The actual fence cannot break while the knocked-back enemy is still travelling toward it")
		if int(gate.hp) == 0:
			broken_at_landing = true
			_check(target.position.distance_to(landing) < 0.00005, "Broken-fence HP and geometry appear only after the enemy reaches its advertised landing")
		await process_frame
	await _idle()
	var after: Dictionary = stage.call("audit")
	_check(hold_frames >= 2 and travel_frames > 0 and broken_at_landing, "The collision has separately observed contact, travel and actual landing-break frames")
	_check(int(after.combat_presentation.damage_events) == 1 and int(after.combat_presentation.push_events) == 1 and int(after.combat_presentation.push_completed) == 1 and int(after.presented_barricade_hp.north_gate) == 0, "The collision presents one damage, one shove and the one real destroyed fence")
	_check(_battle() == committed and int(committed.revision) == int(before.revision) + 1 and app.get("_session").snapshot() == host, "Collision animation never repeats a rule effect, revision, action cost or host settlement")
	_check(_plan("brute").cells == [[5, 2]] and bool(_plan("brute").displaced), "The real shove moves the brute's announced attack away from the medicine basket")
	_check_battle_clean()
	_palm_trials.append({"kind": "authored_collision_opening", "forecast": forecast, "hold_samples": hold_frames, "travel_samples": travel_frames, "break_observed_at_landing": broken_at_landing, "samples": rows})


func _order_comparison() -> void:
	await _prepare_order_position()
	await _collision_palm()
	await _click("Unit_player")
	await _click("MoveButton")
	_check([4, 4] in _view().get("_battle").call("reachable", "player"), "The palm opens the formerly blocked short route for the other character in the same round")
	await _tile([4, 4])
	_check(_unit("player").pos == [4, 4], "The sword user actually follows through the newly vacated cell using normal movement")
	await _click("Skill_strike")
	await _hover_tile([5, 4])
	_check(bool(_view().audit_snapshot().preview.get("ok", false)) and int(_view().audit_snapshot().preview.get("damage", -1)) == 6, "The opened route enables the original six-damage falling-sword follow-up on the blade enemy")
	await _tile([5, 4])
	_check(int(_unit("blade").hp) == 4 and int(_unit("brute").hp) == 9 and bool(_unit("player").acted) and bool(_unit("tinglan").acted), "Palm then falling sword damages two distinct enemies through ordinary independent actions")
	var palm_first := _battle().duplicate(true)
	await _capture("08-palm-then-sword-result.png")
	await _click("EndRoundButton")
	_check(_battle().phase == "player" and int(_battle().round) == 2 and int(_battle().objective.hp) > 0, "The palm-then-sword route resolves a real enemy round and remains playable")
	_order_trials.append({"order": "palm_then_falling_sword", "before_enemy_round": palm_first, "after_enemy_round": _battle().duplicate(true)})
	await _click("RestartButton")
	await _prepare_order_position()
	await _click("Skill_sweep")
	await _hover_tile([4, 3])
	var early: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(early.get("ok", false)) and early.get("targets", []) == ["brute"], "Before the route opens, the original sword sweep can reach only the brute")
	await _tile([4, 3])
	_check(int(_unit("brute").hp) == 11 and int(_unit("blade").hp) == 10, "Sword first consumes its action against only the original reachable enemy")
	await _click("Unit_tinglan")
	await _click("Skill_palm")
	await _tile([4, 3])
	await _click("Unit_player")
	await _click("MoveButton")
	await _tile([4, 4])
	_check(_unit("player").pos == [4, 4] and bool(_unit("player").acted) and (_view().ui_control("Skill_strike") as BaseButton).disabled and int(_unit("blade").hp) == 10, "Reversed order opens the same route after the sword action has been spent, so the blade enemy receives no follow-up this round")
	_check(int(palm_first.units[3].hp) == 4 and int(_unit("blade").hp) == 10, "The real order comparison changes reachable targets and enemy HP without any special combo bonus")
	await _capture("08b-sword-then-palm-result.png")
	var sword_first := _battle().duplicate(true)
	await _click("EndRoundButton")
	_check(_battle().phase == "player" and int(_battle().round) == 2 and int(_battle().objective.hp) > 0, "The reversed legal order also resolves a real enemy round and remains playable")
	_order_trials.append({"order": "sword_then_palm", "forecast_before_palm": early, "before_enemy_round": sword_first, "after_enemy_round": _battle().duplicate(true)})


func _lethal_palm() -> void:
	await _click("RestartButton")
	await _click("Skill_strike")
	await _tile([4, 3])
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([3, 4])
	await _click("Skill_interrupt")
	await _tile([5, 4])
	await _click("EndRoundButton")
	await _click("Unit_player")
	await _click("Skill_strike")
	await _tile([4, 3])
	_check(int(_unit("brute").hp) == 2 and _unit("brute").pos == [4, 3] and int(_barricade("north_gate").hp) == 6, "Two ordinary sword turns prepare a real low-HP target beside the intact north gate")
	await _click("Unit_tinglan")
	await _click("Skill_palm")
	await _hover_tile([4, 3])
	var preview: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(preview.get("ok", false)) and (preview.get("push_path", []) as Array).is_empty() and (preview.get("push_to", []) as Array).is_empty() and str(_view().audit_snapshot().feedback).contains("将击倒"), "Lethal palm preview announces defeat and draws no fictitious post-defeat landing or path")
	var stage: Control = _view().get("_stage")
	var target: Node3D = stage.get("actor_nodes").brute
	var position := target.position
	await _mouse(_view().audit_tile_center([4, 3]), true)
	var committed := _battle().duplicate(true)
	var observed := 0
	var deadline := Time.get_ticks_msec() + 8000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var audit: Dictionary = stage.call("audit")
		observed += 1
		_check(target.position == position, "Every lethal-palm frame keeps the defeated body in its original cell")
		if float((stage.call("workshop_audit") as Dictionary).get("elapsed", 0.0)) < 0.78:
			_check(int(audit.presented_barricade_hp.north_gate) == 6, "Even a lethal collision keeps visible fence HP intact before the actual palm impact")
		await process_frame
	await _idle()
	var final: Dictionary = stage.call("audit")
	_check(observed > 0 and int(_unit("brute").hp) == 0 and _unit("brute").pos == [4, 3] and int(_barricade("north_gate").hp) == 0, "A lethal palm keeps the defeated body still while preserving the existing rule that a forecast collision destroys the fence")
	_check(_battle() == committed and int(final.combat_presentation.damage_events) == 1 and int(final.combat_presentation.push_events) == 0 and int(final.combat_presentation.push_completed) == 0, "Lethal playback presents one authoritative damage/defeat and schedules no phantom shove")
	_check((final.feedback_history as Array).filter(func(row): return str(row.type) == "barricade_hit").size() == 1 and (final.feedback_history as Array).filter(func(row): return str(row.type) == "barricade_destroyed").size() == 1, "The original lethal-collision contract presents the one fence damage and one destruction event exactly once")
	_check_battle_clean()
	await _capture("08c-lethal-palm-no-phantom-push.png")
	_palm_trials.append({"kind": "authored_lethal_palm", "preview": preview, "after": _battle().duplicate(true), "combat": final.combat_presentation.duplicate(true), "rendered_samples": observed})


func _stationary_palm() -> void:
	await _click("RestartButton")
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([4, 4])
	await _click("Skill_palm")
	await _hover_tile([4, 3])
	var preview: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(preview.get("ok", false)) and preview.get("push_to", []) == [4, 3] and int(preview.get("damage", -1)) == 5 and bool(preview.get("collision", false)), "Medicine blocks this legal palm's push immediately, with the original collision bonus and no movement")
	var stage: Control = _view().get("_stage")
	var target: Node3D = stage.get("actor_nodes").brute
	var position := target.position
	var objective: Dictionary = _battle().objective.duplicate(true)
	await _tile([4, 3])
	var final: Dictionary = stage.call("audit")
	_check(int(_unit("brute").hp) == 9 and _unit("brute").pos == [4, 3] and target.position == position and _battle().objective == objective, "Zero-distance collision completes at the original enemy tile without damaging the protected medicine")
	_check(int(final.combat_presentation.damage_events) == 1 and int(final.combat_presentation.push_events) == 1 and int(final.combat_presentation.push_completed) == 1, "A real zero-distance shove finishes exactly once and cannot hold input busy forever")
	_check_battle_clean()
	_palm_trials.append({"kind": "authored_zero_distance_collision", "preview": preview, "after": _battle().duplicate(true), "combat": final.combat_presentation.duplicate(true)})


func _finish() -> void:
	var report := {"test": "sword_palm_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input pointer events in shipped encounter; independent hidden skeleton only for motion-source comparison; no rule fixtures or direct UI signals", "catalog_sha256": _catalog.get("catalog_sha256", ""), "palm_trials": _palm_trials, "order_trials": _order_trials, "boundary": "Native/PCK Compatibility settlement, source/target clock and input proof. Browser, physical input, audio device listening, Windows and artistic user acceptance remain separate."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("SWORD PALM UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
