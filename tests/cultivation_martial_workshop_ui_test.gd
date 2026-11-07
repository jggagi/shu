extends "res://tests/cultivation_engine_ambush_render.gd"
## Actual root.push_input UI; source/fixture probes are identified separately.
const Catalog := preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const Binding := preload("res://addons/cultivation_mode/martial_actor_binding.gd")
const IDS := ["pierce", "sweep", "palm_gale", "sword_cleave", "palm_cloud", "palm_brace"]
const REVIEW_PATH := "user://martial_workshop/reviews.json"
var _catalog: Dictionary = {}
var _trials: Array[Dictionary] = []
var _parent_before: Dictionary = {}
var _review_backup := PackedByteArray()
var _review_existed := false
var _review_owned := false
var _binding_cases: Array[Dictionary] = []
var _transport_observations: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/martial-workshop/ui"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			output = arg.trim_prefix("--output-dir=")
		elif arg.begins_with("--qa-size="):
			var parts := arg.trim_prefix("--qa-size=").split("x")
			qa_size = Vector2i(int(parts[0]), int(parts[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(DisplayServer.get_name() != "headless", "Workshop UI uses an actual Compatibility render window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var loaded := Catalog.load_catalog()
	_check(bool(loaded.ok), "The real compiled workshop catalog loads")
	if not bool(loaded.ok):
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
	_check(is_instance_valid(_view()), "The original two-versus-three battle opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_parent_before = _context()
	var battle_stage: Control = _view().get("_stage")
	var actors_before := _actors(battle_stage)
	var camera_before := _camera(battle_stage)
	var battle_viewport: SubViewport = battle_stage.get("viewport")
	var render_mode := battle_viewport.render_target_update_mode
	await _open_workshop()
	if not is_instance_valid(_workshop()):
		_finish()
		return
	_check(battle_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The hidden battle viewport stops rendering while the independent review stage is open")
	_check(_wa().visible_move_ids == IDS and bool(_wa().stage_ready), "All six authored moves are available in the actual overlay")
	_check(str(_wa().selected_id) == "sword_cleave" and str(_wa().variant_id) == "enhanced" and str(_wa().camera) == "close" and str(_player().camera_mode) == "close" and (_workshop().call("ui_control", "WorkshopCameraChoice") as OptionButton).selected == 3, "First opening shows the enhanced sword cleave in the real close camera")
	_check_workshop_layout()
	await _capture("00-workshop-six-moves.png")
	await _filters()
	await _binding_rejections()
	for id: String in IDS:
		await _play_move(id, id in ["sword_cleave", "palm_cloud", "palm_brace"])
	await _transport_and_seek()
	await _switch_compare_cancel()
	await _review_flow()
	var workshop_stage := _wstage()
	var viewport_ref: WeakRef = weakref(workshop_stage.get("viewport"))
	var blade_ref: WeakRef = weakref(workshop_stage.get("_skill_fx"))
	var palm_ref: WeakRef = weakref(workshop_stage.get("_palm_impact"))
	await _wclick("WorkshopMove_palm_cloud")
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.25)
	await _close_workshop()
	_check(viewport_ref.get_ref() == null and blade_ref.get_ref() == null and palm_ref.get_ref() == null, "Closing during playback frees the real review viewport and both effect helpers")
	_check(_context() == _parent_before and _actors(battle_stage) == actors_before and _camera(battle_stage) == camera_before, "Opening, every preview, scrubbing, review and close preserve exact host, battle, actor transforms/process and playable camera")
	_check(battle_viewport.render_target_update_mode == render_mode and not bool(_view().audit_snapshot().busy), "Closing restores the original render scheduling and battle input gate")
	await _capture("08-workshop-closed-battle-restored.png")
	await _review_reload_and_revision()
	await _muted_workshop()
	await _combat_migration("pierce")
	await _click("RestartButton")
	await _combat_migration("sweep")
	_finish()


func _workshop() -> Control:
	return _view().get("_martial_workshop") as Control if is_instance_valid(_view()) else null


func _wa() -> Dictionary:
	return _workshop().call("audit_snapshot") if is_instance_valid(_workshop()) else {}


func _wstage() -> Control:
	return _workshop().call("ui_control", "WorkshopStage") as Control if is_instance_valid(_workshop()) else null


func _player() -> Dictionary:
	return _wstage().call("workshop_audit") if is_instance_valid(_wstage()) else {}


func _effect(move: Dictionary) -> Dictionary:
	var data: Dictionary = _wstage().call("audit")
	return data.skill_fx if str(move.category) == "sword" else data.palm_impact


func _move(id: String) -> Dictionary:
	return Catalog.find_move(_catalog, id)


func _open_workshop() -> void:
	var button := _view().ui_control("MartialWorkshopButton") as BaseButton
	_check(button != null and not button.disabled and button.is_visible_in_tree(), "The real battle toolbar exposes the available workshop entry")
	if button == null or button.disabled:
		return
	await _mouse(button.get_global_transform_with_canvas() * (button.size * 0.5), true)
	await _frames(4)
	_check(is_instance_valid(_workshop()) and bool(_view().audit_snapshot().busy), "Pointer input opens the modal independent workshop and gates battle controls")


func _close_workshop() -> void:
	await _wclick("WorkshopCloseButton")
	await _frames(4)
	_check(not is_instance_valid(_workshop()) and not bool(_view().audit_snapshot().busy), "The real close button returns control to the same battle")


func _wclick(id: String) -> void:
	var control: Control = _workshop().call("ui_control", id) if is_instance_valid(_workshop()) else null
	_check(control != null and control.is_visible_in_tree() and (not control is BaseButton or not (control as BaseButton).disabled), "Workshop control is actually available: " + id)
	if control == null or not control.is_visible_in_tree() or (control is BaseButton and (control as BaseButton).disabled):
		return
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	await _frames(2)


func _choose(id: String, index: int) -> void:
	await _wclick(id)
	var choice := _workshop().call("ui_control", id) as OptionButton
	var popup := choice.get_popup()
	_check(popup.visible and popup.is_embedded(), id + " opens its real embedded popup")
	var panel: StyleBox = popup.get_theme_stylebox("panel")
	var top: float = panel.get_margin(SIDE_TOP) * popup.content_scale_factor
	var bottom: float = panel.get_margin(SIDE_BOTTOM) * popup.content_scale_factor
	var local := Vector2(float(popup.size.x) * 0.5, top + (float(popup.size.y) - top - bottom) * (float(index) + 0.5) / float(popup.item_count))
	await _mouse(Vector2(popup.position) + local, true)
	await _frames(2)
	_check(choice.selected == index and not popup.visible, id + " selects the actual popup row through pointer input")


func _filters() -> void:
	await _choose("WorkshopCategoryChoice", 1)
	_check(_wa().visible_move_ids == ["pierce", "sweep", "sword_cleave"], "Sword filter shows the three real sword moves")
	await _choose("WorkshopCategoryChoice", 2)
	_check(_wa().visible_move_ids == ["palm_gale", "palm_cloud", "palm_brace"], "Palm filter shows the three real palm moves")
	await _choose("WorkshopStyleChoice", 1)
	var expected: Array = []
	for move: Dictionary in _catalog.moves:
		if move.category == "palm" and move.style == "light":
			expected.append(move.id)
	_check(_wa().visible_move_ids == expected, "Combined category and style filters use the authored move metadata")
	await _choose("WorkshopCategoryChoice", 0)
	await _choose("WorkshopStyleChoice", 0)
	_check(_wa().visible_move_ids == IDS and _context() == _parent_before, "Resetting filters restores all six without changing battle or host state")


func _play_move(id: String, full: bool) -> void:
	await _wclick("WorkshopMove_" + id)
	if id in ["sword_cleave", "palm_gale"]:
		await _choose("WorkshopVariantChoice", 0)
	var move := _move(id)
	var before := _player()
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(float(move.timing.impact) + 0.06 if full else 0.10)
	var data := _player()
	var fx := _effect(move)
	_check(bool(data.get("active", false)) and str(data.get("move_id", "")) == id, id + " plays through the unified move player")
	var actor: Node3D = _wstage().get("actor_nodes")[str(move.actor)]
	var adapter: Node3D = actor.call("workshop_adapter")
	var animation_player := adapter.get("animation_player") as AnimationPlayer
	var clip := str(data.get("binding", {}).get("clip", ""))
	var animation: Animation = animation_player.get_animation(clip) if animation_player.has_animation(clip) else null
	_check(animation != null and animation.get_track_count() > 0 and absf(animation.length - float(move.animation.source_seconds)) < 0.025, id + " samples a real populated and correctly timed imported clip")
	_check(int(data.get("begin_count", 0)) == int(before.get("begin_count", 0)) + 1, id + " has one unified begin per pointer activation")
	_check(_context() == _parent_before, id + " leaves authoritative session and battle dictionaries exactly unchanged")
	if full:
		_check(absf(float(fx.get("elapsed", -1.0)) - float(data.elapsed)) < 0.00001, id + " actual effect helper and player share one clock")
		_check(absf(float(data.source_seconds) - _source_at(move, float(data.elapsed))) < 0.0001, id + " body follows its declared source-time mapping")
		_check(int(fx.get("visible_mesh_vertices", 0)) > 0, id + " visible phase contains actual native mesh geometry")
		var pose_before := _bone_pose(actor)
		var source_before := float(data.source_seconds)
		await _frames(4)
		var continued := _player()
		_check(float(continued.source_seconds) > source_before and _bone_pose(actor) != pose_before, id + " body continues through follow-through instead of freezing behind the effect")
		await _capture("01-" + id + "-impact.png")
		await _wait_finished()
		_check_cleanup()
	else:
		await _wclick("WorkshopStopButton")
		_check_cleanup()
		_check_stopped_timeline()
	_trials.append({"id": id, "full_follow_through": full, "player": data, "actual_effect": fx, "context_exact": _context() == _parent_before})


func _transport_and_seek() -> void:
	await _wclick("WorkshopMove_palm_cloud")
	await _choose("WorkshopSpeedChoice", 1)
	if not await _pause_on_live_release():
		return
	var frozen := _player()
	var frozen_effect := _effect(_move("palm_cloud"))
	_transport_observations.append({"sample": "paused_release", "player": frozen, "effect": frozen_effect, "audio_nodes": _actual_palm_audio(), "engine_fps": Engine.get_frames_per_second()})
	var actor: Node3D = _wstage().get("actor_nodes").tinglan
	var pose := _bone_pose(actor)
	var geometry := _geometry(_wstage().get("_palm_impact"))
	await create_timer(0.16).timeout
	_check(bool(_player().paused) and _player().elapsed == frozen.elapsed and _effect(_move("palm_cloud")).elapsed == frozen_effect.elapsed and _bone_pose(actor) == pose and _geometry(_wstage().get("_palm_impact")) == geometry, "Pause freezes the actual skeleton, helper geometry and unified clock")
	_check(int(frozen_effect.audio_player_count) > 0 and int(frozen_effect.audio_paused_count) == int(frozen_effect.audio_player_count), "Pause also pauses the actual live release AudioStreamPlayer")
	await _capture("04-paused-half-speed.png")
	await _wclick("WorkshopPauseButton")
	# Both measurements refer to the same completed-render boundary. A short
	# SceneTreeTimer sampled mid-frame could include a whole simulation step
	# while its monotonic wall interval excluded part of that step.
	await RenderingServer.frame_post_draw
	var start := _player()
	var rate_window := 0.8
	_check(bool(start.active) and float(start.total) - float(start.elapsed) > rate_window * 0.5 + 0.15, "Half-speed measurement starts with enough unplayed motion to avoid the endpoint")
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
	var observed_rate := (float(advanced.elapsed) - float(start.elapsed)) / real_seconds
	_transport_observations.append({"sample": "half_speed", "start": start, "advanced": advanced, "monotonic_wall_seconds": real_seconds, "stage_process_seconds": process_seconds, "elapsed_delta": float(advanced.elapsed) - float(start.elapsed), "observed_rate": observed_rate, "frames": rate_frames, "sampling": "frame_post_draw at both ends; monotonic window at least 0.8 seconds"})
	_check(real_seconds >= rate_window and bool(advanced.active), "Half-speed measurement observes the complete wall window while playback remains active")
	_check(absf((float(advanced.elapsed) - float(start.elapsed)) / real_seconds - 0.5) < 0.16, "Half speed advances the shared timeline by half real time within one-frame tolerance")
	await _wclick("WorkshopPauseButton")
	var audio_before := int(_player().audio_play_count)
	var endpoint_pose: Array = []
	for fraction: float in [0.15, 1.0, 0.48, 0.23, 0.72]:
		await _seek_pointer(fraction)
		_check(bool(_player().paused) and int(_player().audio_play_count) == audio_before, "Paused pointer scrubbing across cue events never schedules sound")
		if is_equal_approx(fraction, 1.0):
			endpoint_pose = _bone_pose(actor)
		if is_equal_approx(fraction, 0.48):
			_check(int(_effect(_move("palm_cloud")).get("visible_mesh_vertices", 0)) > 0 and int(_effect(_move("palm_cloud")).get("visible_nodes", 0)) > 0, "Seeking from the endpoint back into impact restores actual live effect geometry without restarting or sound")
			_check(actor.visible and not endpoint_pose.is_empty() and _bone_pose(actor) != endpoint_pose, "Seeking from endpoint back to impact also restores the actual authored body pose")
	await _wclick("WorkshopPauseButton")
	await create_timer(0.10).timeout
	_check(int(_player().audio_play_count) == audio_before, "Resuming beyond impact does not backfill consumed release or impact cues")
	await _wclick("WorkshopStopButton")
	_check_cleanup()
	_check_stopped_timeline()
	await _choose("WorkshopSpeedChoice", 0)
	for index: int in [1, 2, 0]:
		await _choose("WorkshopCameraChoice", index)
		_check(str(_player().camera_mode) == ["tactical", "front", "side"][index], "Actual camera choice selects the requested inspection view")
		if index == 2:
			await _capture("05-side-inspection.png")


func _pause_on_live_release() -> bool:
	var play := _workshop().call("ui_control", "WorkshopPlayButton") as BaseButton
	var button := _workshop().call("ui_control", "WorkshopPauseButton") as BaseButton
	_check(play != null and not play.disabled and play.is_visible_in_tree() and button != null and button.is_visible_in_tree(), "Real play and pause controls exist before arming the release monitor")
	if play == null or play.disabled or button == null:
		return false
	# Finish all hover/layout waits before playback starts. The generic
	# _wclick waits five frames and can outlast a short real release cue.
	var play_point := play.get_global_transform_with_canvas() * (play.size * 0.5)
	await _mouse(play_point, false)
	await RenderingServer.frame_post_draw
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var started_wall := Time.get_ticks_usec()
	var actual_play: Vector2 = root.get_final_transform() * play_point
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = actual_play
		event.global_position = actual_play
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.window_id = root.get_window_id()
		root.push_input(event)
	# Arm the pause pointer synchronously, without yielding even one playback
	# frame. Observe from elapsed zero; click only when the real sound is live.
	var actual_pause: Vector2 = root.get_final_transform() * point
	var motion := InputEventMouseMotion.new()
	motion.position = actual_pause
	motion.global_position = actual_pause
	motion.window_id = root.get_window_id()
	root.push_input(motion)
	_transport_observations.append({"sample": "release_monitor_armed_at_pointer_play", "player": _player(), "audio_nodes": _actual_palm_audio(), "start_to_armed_wall_seconds": float(Time.get_ticks_usec() - started_wall) / 1000000.0,
		"input": "Play root.push_input press/release and pause hover synchronously, with no await between startup and the first live-audio observation"})
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline and bool(_player().active):
		# Observe after Stage has created this frame's actual audio but before
		# GPU drawing can consume the entire short sound between observations.
		await RenderingServer.frame_pre_draw
		var audio := _actual_palm_audio()
		var player_state := _player()
		var effect_state := _effect(_move("palm_cloud"))
		_transport_observations.append({"sample": "release_monitor_frame_pre_draw", "observation_phase": "frame_pre_draw after Stage update, before GPU draw",
			"process_frame": Engine.get_process_frames(), "observation_usec": Time.get_ticks_usec(),
			"player_elapsed": player_state.get("elapsed", 0.0), "player_source_seconds": player_state.get("source_seconds", 0.0), "player_phase": player_state.get("phase", ""),
			"effect_elapsed": effect_state.get("elapsed", 0.0), "effect_phase": effect_state.get("phase", ""), "effect_release_count": effect_state.get("release_count", 0),
			"effect_audio_play_count": effect_state.get("audio_play_count", 0), "effect_audio_player_count": effect_state.get("audio_player_count", 0), "muted": effect_state.get("muted", false), "audio_nodes": audio})
		var live_release := false
		for row: Dictionary in audio:
			if str(row.name) == "PalmReleaseAudio" and bool(row.playing) and not bool(row.paused):
				live_release = true
		if live_release:
			_check(not button.disabled and button.is_visible_in_tree(), "The real pause button is enabled while the release AudioStreamPlayer is live")
			_transport_observations.append({"sample": "live_release_before_pointer_pause", "observation_phase": "frame_pre_draw after Stage update, before GPU draw", "player": _player(), "effect": _effect(_move("palm_cloud")), "audio_nodes": audio, "engine_fps": Engine.get_frames_per_second()})
			_check(int(_effect(_move("palm_cloud")).audio_player_count) > 0, "A genuine release AudioStreamPlayer is playing immediately before the real pause click")
			var actual: Vector2 = root.get_final_transform() * point
			for pressed: bool in [true, false]:
				var event := InputEventMouseButton.new()
				event.position = actual
				event.global_position = actual
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				root.push_input(event)
			await _frames(2)
			return true
	_check(false, "The real release sound becomes live before the pointer-pause deadline")
	return false


func _actual_palm_audio() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_wstage()):
		return result
	var helper: Node = _wstage().get("_palm_impact")
	for player: AudioStreamPlayer in helper.find_children("*", "AudioStreamPlayer", true, false):
		result.append({"name": str(player.name), "instance_id": player.get_instance_id(), "playing": player.playing, "paused": player.stream_paused, "playback_seconds": player.get_playback_position(), "stream_seconds": player.stream.get_length() if player.stream != null else 0.0})
	return result


func _switch_compare_cancel() -> void:
	await _wclick("WorkshopMove_palm_cloud")
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.30)
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	_check(str(_wa().selected_id) == "sword_cleave" and str(_wa().previous_id) == "palm_cloud", "Selecting another move remembers the true previous candidate")
	_check_cleanup()
	_check_stopped_timeline()
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.25)
	await _wclick("WorkshopCompareButton")
	_check(str(_wa().selected_id) == "palm_cloud" and str(_wa().previous_id) == "sword_cleave", "A/B exchanges current and previous moves and cancels the prior live presentation")
	_check_cleanup()
	_check_stopped_timeline()
	await _wclick("WorkshopCompareButton")
	await _choose("WorkshopVariantChoice", 0)
	_check(str(_wa().selected_id) == "sword_cleave" and str(_wa().previous_id) == "palm_cloud", "A/B safely exchanges back without an automatic overlapping replay")
	_check_cleanup()
	_check_stopped_timeline()


func _review_flow() -> void:
	await _wclick("WorkshopMove_palm_brace")
	var existing := FileAccess.get_file_as_bytes(REVIEW_PATH) if FileAccess.file_exists(REVIEW_PATH) else PackedByteArray()
	await _wclick("WorkshopReturnButton")
	_check(str(_wa().review_status) == "pending" and not str(_wa().feedback).is_empty(), "Returning a move requires a meaningful reason")
	_check((FileAccess.get_file_as_bytes(REVIEW_PATH) if FileAccess.file_exists(REVIEW_PATH) else PackedByteArray()) == existing, "Rejected blank reason cannot overwrite saved review bytes")
	await _type_reason("   ")
	await _wclick("WorkshopReturnButton")
	_check(str(_wa().review_status) == "pending", "Whitespace-only return reason is also rejected")
	await _type_reason("Palm recovery needs clearer weight transfer")
	await _wclick("WorkshopReturnButton")
	_check(str(_wa().review_status) == "needs_revision" and str(_wa().reason) == "Palm recovery needs clearer weight transfer", "Actual text input and return control persist the explicit critique")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REVIEW_PATH))
	_check(str(saved.catalog_hash) == str(_catalog.catalog_sha256) and str(saved.reviews.palm_brace.status) == "needs_revision", "The review file binds the actual catalog revision and selected move status")
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	await _wclick("WorkshopAcceptButton")
	_check(str(_wa().review_status) == "accepted", "A second candidate can be accepted independently")
	await _capture("06-review-accepted-and-returned.png")
	_check(_context() == _parent_before, "Review persistence creates no game progress, action cost or host save mutation")


func _review_reload_and_revision() -> void:
	await _open_workshop()
	await _wclick("WorkshopMove_palm_brace")
	_check(str(_wa().review_status) == "needs_revision" and str(_wa().reason) == "Palm recovery needs clearer weight transfer", "Reopening reloads the actual saved return reason")
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	_check(str(_wa().review_status) == "accepted", "Reopening reloads the separately accepted candidate")
	await _close_workshop()
	# Labelled review-file fixtures exercise revision invalidation and corrupt
	# persistence boundaries. They never replace the authored resource catalog.
	var valid_bytes := FileAccess.get_file_as_bytes(REVIEW_PATH)
	var stale: Dictionary = JSON.parse_string(valid_bytes.get_string_from_utf8())
	stale.catalog_hash = "qa-previous-catalog-revision"
	_write_review(JSON.stringify(stale).to_utf8_buffer())
	await _open_workshop()
	await _wclick("WorkshopMove_sword_cleave")
	await _choose("WorkshopVariantChoice", 0)
	_check(bool(_wa().review_invalidated) and str(_wa().review_status) == "pending", "A prior asset/recipe catalog revision cannot approve the current batch")
	await _wclick("WorkshopAcceptButton")
	var revised: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REVIEW_PATH))
	_check(str(revised.catalog_hash) == str(_catalog.catalog_sha256) and (revised.previous_catalogs as Array).size() > 0, "Saving the new batch retains the previous catalog's review history")
	await _close_workshop()
	var corrupt := "{ labelled malformed QA review fixture".to_utf8_buffer()
	_write_review(corrupt)
	await _open_workshop()
	_check(bool(_wa().review_read_blocked) and not str(_wa().review_error).is_empty(), "A corrupt review is reported instead of silently accepted")
	await _wclick("WorkshopAcceptButton")
	_check(FileAccess.get_file_as_bytes(REVIEW_PATH) == corrupt, "Attempted review cannot overwrite an unreadable original file")
	await _close_workshop()
	_write_review(valid_bytes)
	_check(_context() == _parent_before, "Reopen and persistence error paths still preserve exact host and battle state")


func _combat_migration(id: String) -> void:
	var stage: Control = _view().get("_stage")
	var unified_before: Dictionary = stage.call("workshop_audit")
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var before := _battle().duplicate(true)
	await _click("Skill_" + id)
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)), id + " still uses the existing legal rule preview")
	await _mouse(_view().audit_tile_center([4, 3]), true)
	var committed := _battle().duplicate(true)
	_check((_view().ui_control("MartialWorkshopButton") as BaseButton).disabled, "A real attack visually disables entry to the workshop")
	await _idle()
	var after: Dictionary = stage.call("workshop_audit")
	_check(int(after.get("unified_combat_count", 0)) == int(unified_before.get("unified_combat_count", 0)) + 1 and int(after.get("begin_count", 0)) == int(unified_before.get("begin_count", 0)) + 1, id + " real combat is routed through one unified player invocation")
	for target: String in forecast.get("targets", []):
		_check(int(_unit(target).hp) == int(_find_unit(before.units, target).hp) - int(forecast.damage_by_target[target]), id + " damages each original rule target exactly once")
	_check(_battle() == committed and int(_battle().revision) == int(before.revision) + 1 and app.get("_session").snapshot() == host, id + " presentation cannot duplicate authoritative damage, action revision or host settlement")
	_check(int(after.get("live_audio", -1)) == 0 and int(after.get("live_fx", -1)) == 0, id + " unified combat also clears presentation resources")
	await _capture("09-combat-" + id + "-unified.png")


func _muted_workshop() -> void:
	await _click("SoundToggleButton")
	_check(bool(_view().audit_snapshot().sound_muted), "The original battle sound preference can be muted before opening the workshop")
	await _open_workshop()
	await _wclick("WorkshopMove_palm_gale")
	await _choose("WorkshopVariantChoice", 0)
	var before := int(_player().get("audio_play_count", 0))
	await _wclick("WorkshopPlayButton")
	await _wait_elapsed(0.88)
	_check(int(_player().audio_play_count) == before, "The independent workshop inherits the muted player preference and schedules no hidden cues")
	await _wclick("WorkshopStopButton")
	_check_cleanup()
	await _close_workshop()
	_check(bool(_view().audit_snapshot().sound_muted) and _context() == _parent_before, "Closing the workshop preserves mute and the exact underlying battle state")
	await _click("SoundToggleButton")
	_check(not bool(_view().audit_snapshot().sound_muted), "The original sound control still restores enabled playback normally")


func _binding_rejections() -> void:
	var actor: Node3D = _wstage().get("actor_nodes").player
	var before := _actors(_wstage())
	var bad := _move("pierce")
	bad.animation.clip = "QA_missing_clip"
	var binding := Binding.new()
	var rejected: Dictionary = binding.bind_move(actor, bad, _catalog.profiles.jiang22)
	_check(not bool(rejected.ok) and not str(rejected.reason).is_empty() and _actors(_wstage()) == before, "Actual ActorBinding atomically rejects a missing animation clip")
	_binding_cases.append({"fixture": "existing GLB with nonexistent raw clip", "result": rejected})
	# A real temporary PackedScene carries the matching names/parents but a
	# deliberately wrong rest matrix; no mocked binder or altered project asset.
	var adapter: Node3D = actor.call("workshop_adapter")
	var target := adapter.get("skeleton") as Skeleton3D
	var source := Node3D.new()
	var rig := Skeleton3D.new()
	source.add_child(rig)
	rig.owner = source
	for index: int in range(target.get_bone_count()):
		rig.add_bone(target.get_bone_name(index))
		rig.set_bone_parent(index, target.get_bone_parent(index))
		var rest := target.get_bone_rest(index)
		if index == 0:
			rest.origin += Vector3(0.10, 0.0, 0.0)
		rig.set_bone_rest(index, rest)
	var animations := AnimationPlayer.new()
	source.add_child(animations)
	animations.owner = source
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = float(bad.animation.source_seconds)
	library.add_animation("QA_bad_rest", clip)
	animations.add_animation_library("", library)
	var packed := PackedScene.new()
	_check(packed.pack(source) == OK, "The deliberately incompatible rig fixture packs as a real scene")
	var path := "user://workshop-bad-rig-%d-%d.tscn" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(ResourceSaver.save(packed, path) == OK, "The isolated bad-rest scene is available to the real resource loader")
	source.free()
	bad.animation.asset = path
	bad.animation.clip = "QA_bad_rest"
	var second := Binding.new()
	rejected = second.bind_move(actor, bad, _catalog.profiles.jiang22)
	_check(not bool(rejected.ok) and not str(rejected.reason).is_empty() and _actors(_wstage()) == before, "Actual ActorBinding atomically rejects a matching-name rig with incompatible rest pose")
	_binding_cases.append({"fixture": "temporary scene; original 22 names/parents with pelvis rest shifted 0.10m", "result": rejected})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _source_at(move: Dictionary, elapsed: float) -> float:
	var mapping: Array = move.timing.source_map
	var time := clampf(elapsed, 0.0, float(move.timing.duration))
	for index: int in range(1, mapping.size()):
		if time <= float(mapping[index][0]):
			return lerpf(float(mapping[index - 1][1]), float(mapping[index][1]), (time - float(mapping[index - 1][0])) / (float(mapping[index][0]) - float(mapping[index - 1][0])))
	return float(mapping[-1][1])


func _bone_pose(actor: Node3D) -> Array:
	var adapter: Node3D = actor.call("workshop_adapter")
	var skeleton := adapter.get("skeleton") as Skeleton3D
	var result: Array = []
	for index: int in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_pose(index))
	return result


func _geometry(helper: Node3D) -> Array:
	var result: Array = []
	for node: Node in helper.find_children("*", "Node3D", true, false):
		if not node is MeshInstance3D and not node is Sprite3D:
			continue
		var row := {"transform": (node as Node3D).transform, "visible": (node as Node3D).visible}
		if node is Sprite3D:
			row["modulate"] = (node as Sprite3D).modulate
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh is ArrayMesh:
			var surfaces: Array = []
			for index: int in range(mesh.mesh.get_surface_count()):
				surfaces.append(mesh.mesh.surface_get_arrays(index))
			row["surfaces"] = surfaces
		result.append(row)
	return result


func _wait_elapsed(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while bool(_player().get("active", false)) and float(_player().get("elapsed", 0.0)) < seconds and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(bool(_player().get("active", false)) and float(_player().get("elapsed", 0.0)) >= seconds, "The real player reaches the requested authored sample")


func _wait_finished() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while bool(_player().get("active", false)) and Time.get_ticks_msec() < deadline:
		await process_frame
	await _frames(3)
	_check(not bool(_player().get("active", true)), "The unified presentation ends within its real-time deadline")


func _check_cleanup() -> void:
	var data := _player()
	_check(not bool(data.get("active", true)) and int(data.get("live_audio", -1)) == 0 and int(data.get("live_fx", -1)) == 0, "Stopped/completed/switch presentation owns no live mesh, light or audio children")
	var actual: Dictionary = _wstage().call("audit")
	_check(int(actual.skill_fx.mesh_count) == 0 and int(actual.palm_impact.live_nodes) == 0 and int(actual.combat_light.light_count) == 0, "The actual independent helper audits also confirm all effect roots cleared")


func _check_stopped_timeline() -> void:
	var slider := _workshop().call("ui_control", "WorkshopTimelineSlider") as HSlider
	_check(is_zero_approx(float(_wa().elapsed)) and is_zero_approx(slider.value), "Manual stop or move switch resets the actual displayed timeline to zero rather than the previous player's clock")


func _seek_pointer(fraction: float) -> void:
	var slider := _workshop().call("ui_control", "WorkshopTimelineSlider") as HSlider
	var grabber: Texture2D = slider.get_theme_icon("grabber")
	var margin := float(grabber.get_width()) * 0.5
	var local := Vector2(lerpf(margin, slider.size.x - margin, fraction), slider.size.y * 0.5)
	await _mouse(slider.get_global_transform_with_canvas() * local, true)
	await _frames(2)
	_check(absf(float(_player().elapsed) / float(_wa().duration) - fraction) < 0.06, "A real slider pointer seek changes the requested time instead of emitting a synthetic signal")


func _type_reason(text: String) -> void:
	await _wclick("WorkshopReasonEdit")
	for pressed: bool in [true, false]:
		var select_all := InputEventKey.new()
		select_all.keycode = KEY_A
		select_all.ctrl_pressed = true
		select_all.pressed = pressed
		root.push_input(select_all)
		await process_frame
	for character: String in text:
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.pressed = true
		root.push_input(event)
		await process_frame
	await _frames(2)
	_check(str(_wa().reason) == text, "The actual TextEdit receives the typed review reason")


func _check_workshop_layout() -> void:
	var bounds := Rect2(Vector2.ZERO, app.size)
	var rects: Dictionary = _wa().controls
	for id: String in rects:
		_check(bounds.encloses(rects[id]) and (rects[id] as Rect2).size.x > 0.0 and (rects[id] as Rect2).size.y > 0.0, "Workshop control stays in the complete usable canvas: " + id)
	for id: String in ["WorkshopPlayButton", "WorkshopStopButton", "WorkshopPauseButton", "WorkshopCameraChoice", "WorkshopSpeedChoice", "WorkshopCompareButton", "WorkshopTimelineSlider", "WorkshopReasonEdit", "WorkshopCloseButton"]:
		for other: String in ["WorkshopAcceptButton", "WorkshopReturnButton", "WorkshopPendingButton"]:
			_check(not (rects[id] as Rect2).intersects(rects[other]), "Transport/review controls retain separate actual hit areas: " + id + "/" + other)
	_check((_wa().viewport_size as Vector2i).x > 300 and (_wa().viewport_size as Vector2i).y > 160, "The actual independent 3D review viewport remains usable")


func _context() -> Dictionary:
	var data: Dictionary = _view().audit_snapshot()
	return {"host": app.get("_session").snapshot().duplicate(true), "battle": _battle().duplicate(true), "selected": data.selected, "action": data.action, "preview": data.preview.duplicate(true), "preview_skill": data.preview_skill}


func _actors(stage: Control) -> Dictionary:
	var result := {}
	for id: String in stage.get("actor_nodes"):
		var actor: Node3D = stage.get("actor_nodes")[id]
		result[id] = {"transform": actor.transform, "processing": actor.is_processing(), "visible": actor.visible}
	return result


func _camera(stage: Control) -> Dictionary:
	var camera: Camera3D = stage.get("camera")
	return {"transform": camera.transform, "size": camera.size, "near": camera.near, "far": camera.far, "projection": camera.projection}


func _find_unit(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.id) == id:
			return row
	return {}


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame


func _backup_reviews() -> void:
	_review_existed = FileAccess.file_exists(REVIEW_PATH)
	if _review_existed:
		_review_backup = FileAccess.get_file_as_bytes(REVIEW_PATH)
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_PATH)) == OK, "The original review bytes are safely isolated for the persistence test")
	_review_owned = true


func _write_review(bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_PATH.get_base_dir()))
	var file := FileAccess.open(REVIEW_PATH, FileAccess.WRITE)
	_check(file != null, "The explicitly labelled review-file fixture is writable")
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _finish() -> void:
	if _review_owned:
		if _review_existed:
			_write_review(_review_backup)
			_check(FileAccess.get_file_as_bytes(REVIEW_PATH) == _review_backup, "The test restores the exact original review bytes")
		elif FileAccess.file_exists(REVIEW_PATH):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_PATH)) == OK, "The test removes only its own newly created review file")
	var report := {"test": "martial_workshop_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input pointer/keyboard events; negative ActorBinding and review-file fixtures labelled separately; not browser or physical input", "scope": "Six-move independent presentation/review desk, unified real-combat migration, no new combat rules", "catalog_sha256": _catalog.get("catalog_sha256", ""), "trials": _trials, "binding_rejections": _binding_cases, "transport_observations": _transport_observations, "audio_boundary": "Dummy scheduling and mute/seek/pause state only; actual device listening remains unverified"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("MARTIAL WORKSHOP UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
