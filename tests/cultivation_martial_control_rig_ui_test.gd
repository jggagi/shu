extends "res://tests/cultivation_martial_workshop_ui_test.gd"
## Root pointer/keyboard input and real renderer; no synthetic pressed signals.
const VARIANT_IDS := ["sword_cleave", "palm_gale"]
var _control_trials: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/martial-control-rig/ui"
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
	_check(DisplayServer.get_name() != "headless", "Control-rig comparison uses an actual native Compatibility render window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var loaded := Catalog.load_catalog()
	_check(bool(loaded.get("ok", false)), "The real original/enhanced catalog loads")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_catalog = loaded.catalog
	_backup_reviews()
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The existing playable two-versus-three battle opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_parent_before = _context()
	var battle_stage: Control = _view().get("_stage")
	var battle_actors := _actors(battle_stage)
	var battle_camera := _camera(battle_stage)
	var battle_viewport: SubViewport = battle_stage.get("viewport")
	var render_mode := battle_viewport.render_target_update_mode
	await _open_workshop()
	if not is_instance_valid(_workshop()):
		_finish()
		return
	_check(_wa().visible_move_ids == IDS and bool(_wa().stage_ready), "The workshop keeps exactly the same six list entries")
	_check(str(_wa().selected_id) == "sword_cleave" and str(_wa().variant_id) == "enhanced" and str(_wa().camera) == "close" and str(_player().camera_mode) == "close" and (_workshop().call("ui_control", "WorkshopCameraChoice") as OptionButton).selected == 3, "First opening presents the enhanced sword cleave through the actual close camera")
	_check_workshop_layout()
	_check_variant_layout()
	await _capture("00-control-rig-workshop.png")
	await _default_variant_controls()
	for id: String in VARIANT_IDS:
		await _same_time_variants(id)
	await _separate_variant_reviews()
	await _close_workshop()
	await _open_workshop()
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	_check(str(_wa().variant_id) == "original" and str(_wa().review_status) == "accepted", "Reopening restores the original candidate's separately accepted review")
	await _choose("WorkshopVariantChoice", 1)
	_check(str(_wa().variant_id) == "enhanced" and str(_wa().review_status) == "needs_revision" and str(_wa().reason) == "Enhanced recovery needs a softer elbow", "Reopening restores the enhanced candidate's independent reason and status")
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.25)
	var stage := _wstage()
	var viewport_ref: WeakRef = weakref(stage.get("viewport"))
	var blade_ref: WeakRef = weakref(stage.get("_skill_fx"))
	var palm_ref: WeakRef = weakref(stage.get("_palm_impact"))
	await _close_workshop()
	_check(viewport_ref.get_ref() == null and blade_ref.get_ref() == null and palm_ref.get_ref() == null, "Closing an enhanced playback frees its real viewport, mesh/light helpers and audio owners")
	_check(_context() == _parent_before and _actors(battle_stage) == battle_actors and _camera(battle_stage) == battle_camera, "Variant selection, sampling, review and close preserve exact host/battle/actor/camera authority")
	_check(battle_viewport.render_target_update_mode == render_mode and not bool(_view().audit_snapshot().busy), "Close restores the original battle render mode and input availability")
	await _capture("09-control-rig-closed.png")
	_finish()


func _default_variant_controls() -> void:
	for id: String in IDS:
		await _wclick("WorkshopMove_" + id)
		var available: Array = _wa().available_variants
		var choice := _workshop().call("ui_control", "WorkshopVariantChoice") as OptionButton
		var compare := _workshop().call("ui_control", "WorkshopVariantCompareButton") as BaseButton
		var expected_variant := "enhanced" if id in VARIANT_IDS else "original"
		var expected_review_key := id + "@enhanced" if id in VARIANT_IDS else id
		_check(choice != null and compare != null and str(_wa().variant_id) == expected_variant and str(_wa().review_key) == expected_review_key, "Selecting " + id + " defaults to its intended available variant and separate review key")
		if id in VARIANT_IDS:
			_check(available == ["original", "enhanced"] and not choice.disabled and not compare.disabled and choice.item_count == 2 and choice.get_item_metadata(0) == "original" and choice.get_item_metadata(1) == "enhanced", id + " offers exactly the two true motion variants")
		else:
			_check(available == ["original"] and choice.disabled and compare.disabled and choice.item_count == 1, id + " accurately exposes original only")
		_check_cleanup()
		_check(_context() == _parent_before, id + " default/available variant inspection does not settle gameplay")


func _same_time_variants(id: String) -> void:
	await _wclick("WorkshopMove_" + id)
	await _choose("WorkshopVariantChoice", 0)
	await _choose("WorkshopCameraChoice", 2)
	await _choose("WorkshopSpeedChoice", 1)
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.10)
	await _wclick("WorkshopPauseButton")
	var actor: Node3D = _wstage().get("actor_nodes")[str(_move(id).actor)]
	var baseline_audio := int(_player().audio_play_count)
	var different_samples := 0
	for fraction: float in [0.23, 0.38, 0.50, 0.73, 1.0, 0.46]:
		await _seek_pointer(fraction)
		var original := _player().duplicate(true)
		var old_pose := _bone_pose(actor)
		var old_camera := _camera(_wstage())
		var old_effect := _effect(_move(id)).duplicate(true)
		_check(str(original.variant_id) == "original" and bool(original.paused), id + " original is the paused comparison source")
		if is_equal_approx(fraction, 0.50):
			await _capture("02-" + id + "-original.png")
		await _wclick("WorkshopVariantCompareButton")
		var enhanced := _player().duplicate(true)
		var new_pose := _bone_pose(actor)
		var new_effect := _effect(_move(id)).duplicate(true)
		_check(str(_wa().variant_id) == "enhanced" and str(enhanced.variant_id) == "enhanced" and str(enhanced.animation_asset) == str(Catalog.find_move(_catalog, id, "enhanced").animation.asset), id + " comparison samples the actual enhanced resource")
		_check(absf(float(enhanced.elapsed) - float(original.elapsed)) < 0.00001 and absf(float(enhanced.source_seconds) - float(original.source_seconds)) < 0.00001 and str(enhanced.phase) == str(original.phase), id + " A/B preserves both presentation/source seconds and phase at " + str(fraction))
		_check(bool(enhanced.paused) and is_equal_approx(float(enhanced.speed), 0.5) and str(enhanced.camera_mode) == "side" and _camera(_wstage()) == old_camera, id + " comparison keeps pause, half speed and exact view transform")
		_check(int(enhanced.audio_play_count) == baseline_audio and int(original.audio_play_count) == baseline_audio, id + " same-time exchange and seeking never backfill sound events")
		_check(absf(float(new_effect.elapsed) - float(old_effect.elapsed)) < 0.00001, id + " both actual effect helpers sample the exact same time")
		if old_pose != new_pose and fraction < 0.9:
			different_samples += 1
		if is_equal_approx(fraction, 0.50):
			_check(int(new_effect.get("visible_mesh_vertices", 0)) > 0, id + " enhanced body retains real effect geometry")
			await _capture("03-" + id + "-enhanced.png")
		if is_equal_approx(fraction, 0.46):
			_check(int(new_effect.get("visible_mesh_vertices", 0)) > 0 and actor.visible, id + " endpoint-to-impact rewind restores the actual body and effect")
		var frozen_geometry := _geometry(_wstage().get("_skill_fx") if str(_move(id).category) == "sword" else _wstage().get("_palm_impact"))
		await _frames(3)
		_check(_bone_pose(actor) == new_pose and _player().elapsed == enhanced.elapsed and _geometry(_wstage().get("_skill_fx") if str(_move(id).category) == "sword" else _wstage().get("_palm_impact")) == frozen_geometry, id + " enhancement pause freezes actual skeleton and mesh state")
		await _choose("WorkshopVariantChoice", 0)
		_check(str(_wa().variant_id) == "original" and absf(float(_player().elapsed) - float(original.elapsed)) < 0.00001 and _bone_pose(actor) == old_pose, id + " popup returns to the exact original pose at the same second")
		_control_trials.append({"id": id, "fraction": fraction, "original": original, "enhanced": enhanced, "actual_pose_differs": old_pose != new_pose, "same_camera": _camera(_wstage()) == old_camera, "audio_count": _player().audio_play_count})
	_check(different_samples >= 3, id + " enhanced choreography changes the real imported bone pose across multiple action phases")
	await _choose("WorkshopVariantChoice", 1)
	await _wclick("WorkshopPauseButton")
	# Use completed-frame boundaries and a monotonic observation window, as in
	# the workshop transport check, so a mid-frame timer cannot skew the rate.
	await RenderingServer.frame_post_draw
	var resumed := _player()
	var rate_window := 0.8
	_check(bool(resumed.active) and float(resumed.total) - float(resumed.elapsed) > rate_window * 0.5 + 0.15, id + " enhanced rate measurement starts far enough from the endpoint")
	var wall := Time.get_ticks_usec()
	var previous_wall := wall
	var process_seconds := 0.0
	var rate_frames: Array[Dictionary] = []
	while float(Time.get_ticks_usec() - wall) / 1000000.0 < rate_window and bool(_player().active):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var delta := _wstage().get_process_delta_time()
		process_seconds += delta
		rate_frames.append({"wall_delta": float(now - previous_wall) / 1000000.0, "stage_process_delta": delta, "elapsed": _player().elapsed, "engine_fps": Engine.get_frames_per_second()})
		previous_wall = now
	var advanced := _player()
	var real_seconds := float(Time.get_ticks_usec() - wall) / 1000000.0
	_control_trials.append({"id": id, "sample": "resumed_half_speed", "start": resumed, "advanced": advanced, "monotonic_wall_seconds": real_seconds, "stage_process_seconds": process_seconds, "elapsed_delta": float(advanced.elapsed) - float(resumed.elapsed), "observed_rate": (float(advanced.elapsed) - float(resumed.elapsed)) / real_seconds, "frames": rate_frames, "sampling": "frame_post_draw at both ends; monotonic window at least 0.8 seconds"})
	_check(real_seconds >= rate_window and bool(advanced.active), id + " enhanced rate measurement observes the complete wall window while active")
	_check(bool(_player().active) and not bool(_player().paused) and absf((float(_player().elapsed) - float(resumed.elapsed)) / real_seconds - 0.5) < 0.16, id + " enhanced playback resumes at genuine half speed")
	var compare := _workshop().call("ui_control", "WorkshopVariantCompareButton") as BaseButton
	_check(compare != null and compare.is_visible_in_tree() and not compare.disabled, id + " running same-time comparison button is actually available")
	if compare != null and compare.is_visible_in_tree() and not compare.disabled:
		# Hover and its frame happen before the measured boundary. The generic
		# _wclick helper intentionally waits five frames; measuring across those
		# frames would mistake ordinary low-fps playback for an exchange jump.
		var compare_at := compare.get_global_transform_with_canvas() * (compare.size * 0.5)
		await _mouse(compare_at, false)
		await RenderingServer.frame_post_draw
		var running := _player().duplicate(true)
		var dispatch_wall := Time.get_ticks_usec()
		var actual: Vector2 = root.get_final_transform() * compare_at
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = actual
			event.global_position = actual
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.window_id = root.get_window_id()
			root.push_input(event)
		var switched := _player().duplicate(true)
		var switched_wall := Time.get_ticks_usec()
		_check(str(switched.variant_id) == "original" and not bool(switched.paused) and float(switched.elapsed) >= float(running.elapsed) and float(switched.elapsed) - float(running.elapsed) < 0.14 and is_equal_approx(float(switched.speed), 0.5), id + " running same-time comparison continues without restarting at zero or losing speed")
		_check(int(switched.audio_play_count) == baseline_audio, id + " resuming/exchanging beyond impact does not replay consumed audio")
		await process_frame
		await RenderingServer.frame_post_draw
		var continued := _player().duplicate(true)
		var continued_wall := Time.get_ticks_usec()
		_check(bool(continued.active) and str(continued.variant_id) == "original" and not bool(continued.paused) and float(continued.elapsed) > float(switched.elapsed) and is_equal_approx(float(continued.speed), 0.5), id + " same-boundary real pointer exchange continues normal playback on the next completed frame")
		_check(int(continued.audio_play_count) == baseline_audio, id + " the following real playback frame still does not backfill consumed cues")
		_control_trials.append({"id": id, "sample": "running_same_boundary_pointer_exchange", "before": running, "after_dispatch": switched, "next_completed_frame": continued,
			"dispatch_wall_seconds": float(switched_wall - dispatch_wall) / 1000000.0,
			"next_frame_wall_seconds": float(continued_wall - switched_wall) / 1000000.0,
			"dispatch_elapsed_delta": float(switched.elapsed) - float(running.elapsed),
			"next_frame_elapsed_delta": float(continued.elapsed) - float(switched.elapsed),
			"sampling": "Hover first; frame_post_draw boundary; root.push_input press/release synchronously without awaits; immediate after sample. Next completed frame recorded separately."})
	await _wclick("WorkshopStopButton")
	_check_cleanup()
	_check_stopped_timeline()
	await _choose("WorkshopSpeedChoice", 0)
	await _choose("WorkshopCameraChoice", 0)
	_check(_context() == _parent_before, id + " all variant transport operations preserve exact host and battle dictionaries")


func _separate_variant_reviews() -> void:
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	await _wclick("WorkshopAcceptButton")
	_check(str(_wa().review_status) == "accepted" and str(_wa().review_key) == "sword_cleave", "The preserved original can be reviewed independently")
	await _choose("WorkshopVariantChoice", 1)
	_check(str(_wa().review_status) == "pending" and str(_wa().review_key) == "sword_cleave@enhanced", "Accepting the original cannot preapprove the enhanced choreography")
	var bytes := FileAccess.get_file_as_bytes(REVIEW_PATH)
	await _wclick("WorkshopReturnButton")
	_check(str(_wa().review_status) == "pending" and FileAccess.get_file_as_bytes(REVIEW_PATH) == bytes, "Returning the enhanced variant still requires an explicit meaningful reason")
	await _type_reason("Enhanced recovery needs a softer elbow")
	await _wclick("WorkshopReturnButton")
	_check(str(_wa().review_status) == "needs_revision" and str(_wa().reason) == "Enhanced recovery needs a softer elbow", "Real text input stores the enhanced candidate's critique")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REVIEW_PATH))
	_check(str(saved.catalog_hash) == str(_catalog.catalog_sha256) and str(saved.reviews.sword_cleave.status) == "accepted" and str(saved.reviews["sword_cleave@enhanced"].status) == "needs_revision", "The actual persistent review file binds distinct original/enhanced keys to the combined asset revision")
	await _choose("WorkshopVariantChoice", 0)
	_check(str(_wa().review_status) == "accepted" and str(_wa().reason).is_empty(), "Returning to original restores its own status and does not inherit the enhanced return reason")
	await _capture("07-original-review-separated.png")
	await _choose("WorkshopVariantChoice", 1)
	await _capture("08-enhanced-review-separated.png")


func _check_variant_layout() -> void:
	var rectangles: Dictionary = _wa().controls
	for id: String in ["WorkshopVariantChoice", "WorkshopVariantCompareButton"]:
		_check(rectangles.has(id) and Rect2(Vector2.ZERO, app.size).encloses(rectangles.get(id, Rect2())), "Variant control has a usable contained hit region: " + id)
		for other: String in ["WorkshopPlayButton", "WorkshopStopButton", "WorkshopPauseButton", "WorkshopCompareButton", "WorkshopTimelineSlider", "WorkshopAcceptButton", "WorkshopReturnButton"]:
			_check(not (rectangles.get(id, Rect2()) as Rect2).intersects(rectangles[other]), "Variant control keeps a distinct hit region from " + other)


func _finish() -> void:
	if _review_owned:
		if _review_existed:
			_write_review(_review_backup)
			_check(FileAccess.get_file_as_bytes(REVIEW_PATH) == _review_backup, "The enhanced comparison test restores the exact original review bytes")
		elif FileAccess.file_exists(REVIEW_PATH):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_PATH)) == OK, "The comparison test removes only its own temporary review file")
	var report := {"test": "martial_control_rig_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input pointer/keyboard events and real popup selections; no direct signal emissions", "catalog_sha256": _catalog.get("catalog_sha256", ""), "paired_samples": _control_trials, "boundary": "Native Compatibility render/input and scheduling proof. Rendered review establishes visible difference, not user approval. Browser, Windows, device audio and physical input remain unverified."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("MARTIAL CONTROL RIG UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
