extends "res://tests/cultivation_ambush_camera_ui_test.gd"
## Actual root pointer transport and live battle. No gameplay or clock fixture.
## Rig checks read completed native modifier solves after frame_post_draw.
var _staff_trials: Array[Dictionary] = []
var _staff_rig_samples: Array[Dictionary] = []
var _staff_transport: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/ambush-staff/ui"
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
	_check(DisplayServer.get_name() != "headless", "Staff review requires the actual native Compatibility renderer")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("staff-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
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
	_check_layout()
	_check_projection(true)
	await _capture("00-staff-battle-arrival.png")
	await _drag(_board_point(), Vector2(-42, 17), MOUSE_BUTTON_MIDDLE)
	await _staff_modal_review()
	await _click("CameraResetButton")
	await _staff_enemy_round()
	await _click("RestartButton")
	await _staff_real_palm()
	await _click("RestartButton")
	await _staff_real_interrupt()
	var stage_ref: WeakRef = weakref(_stage())
	var viewport_ref: WeakRef = weakref(_stage().get("viewport"))
	var actor_ref: WeakRef = weakref(_stage().get("actor_nodes").brute)
	var sequence := int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and stage_ref.get_ref() == null and viewport_ref.get_ref() == null and actor_ref.get_ref() == null, "Return releases the real staff actor, board and viewport")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Return uses the original host and settles only the current unfinished encounter once")
	await _capture("15-staff-return-town.png")
	_finish()


func _staff_inspector() -> Control:
	return _view().get("_staff_inspector") as Control if is_instance_valid(_view()) else null


func _sa() -> Dictionary:
	return _staff_inspector().call("audit_snapshot") if is_instance_valid(_staff_inspector()) else {}


func _staff_actor_audit(actor: Node3D) -> Dictionary:
	return actor.call("staff_motion_audit") if is_instance_valid(actor) else {}


func _staff_rig(data: Dictionary) -> Dictionary:
	return data.get("rig", data.get("rig_audit", data)) as Dictionary


func _staff_open() -> void:
	var button := _view().ui_control("StaffInspectorButton") as BaseButton
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "The real battle toolbar exposes the staff review")
	if button == null or button.disabled:
		return
	await _mouse(button.get_global_transform_with_canvas() * (button.size * 0.5), true)
	await _frames(3)
	_check(is_instance_valid(_staff_inspector()), "Actual pointer input opens the isolated staff inspector")


func _staff_click(id: String) -> void:
	var control: Control = _staff_inspector().call("ui_control", id) if is_instance_valid(_staff_inspector()) else null
	_check(control != null and control.is_visible_in_tree() and (not control is BaseButton or not (control as BaseButton).disabled), "Staff review control is actually available: " + id)
	if control == null or not control.is_visible_in_tree() or (control is BaseButton and (control as BaseButton).disabled):
		return
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	await _frames(2)


func _staff_raw_click(id: String) -> void:
	var control: Control = _staff_inspector().call("ui_control", id)
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	_raw_motion(point, Vector2.ZERO, 0)
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	_raw_button(point, MOUSE_BUTTON_LEFT, false)


func _staff_seek(seconds: float) -> void:
	var slider := _staff_inspector().call("ui_control", "StaffScrubSlider") as HSlider
	_check(slider != null and slider.is_visible_in_tree(), "The actual review scrub slider is available")
	if slider == null:
		return
	var grabber: Texture2D = slider.get_theme_icon("grabber")
	var margin := float(grabber.get_width()) * 0.5
	var fraction := clampf(seconds / float(_sa().duration), 0.0, 1.0)
	var local := Vector2(lerpf(margin, slider.size.x - margin, fraction), slider.size.y * 0.5)
	await _mouse(slider.get_global_transform_with_canvas() * local, true)
	await _frames(2)
	_check(not bool(_sa().playing) and absf(float(_sa().time) - seconds) < 0.025, "Real pointer scrubbing pauses at the requested absolute motion time")
	await _staff_wait_solved(_staff_inspector().get("actor"))


func _staff_wait_solved(actor: Node3D) -> Dictionary:
	var data: Dictionary = {}
	for frame: int in range(12):
		await RenderingServer.frame_post_draw
		data = _staff_actor_audit(actor)
		var rig := _staff_rig(data)
		if int(rig.get("sample_revision", -1)) > 0 and int(rig.get("solved_revision", -2)) == int(rig.get("sample_revision", -1)):
			return data
		await process_frame
	_check(false, "The native modifier solve catches the exact sampled revision before audit")
	return data


func _staff_check_rig(data: Dictionary, label: String) -> void:
	var rig := _staff_rig(data)
	_check(bool(rig.get("skeleton", false)) and int(rig.get("bone_count", 0)) >= 16, "The reviewed pose uses a real articulated skeleton: " + label)
	_check(int(rig.get("sample_revision", -1)) > 0 and int(rig.get("sample_revision", -1)) == int(rig.get("solved_revision", -2)), "IK audit reads the completed matching sample revision: " + label)
	for side: String in ["left", "right"]:
		var arm: Dictionary = rig.get("arms", {}).get(side, {})
		var foot: Dictionary = rig.get("feet", {}).get(side, {})
		_check(arm.has("world_grip_error") and is_finite(float(arm.get("world_grip_error", INF))) and float(arm.get("world_grip_error", INF)) <= 0.015, "The actual " + side + " hand reaches its staff grip within 1.5cm: " + label)
		_check(foot.has("contact_error") and is_finite(float(foot.get("contact_error", INF))) and float(foot.get("contact_error", INF)) <= 0.02, "The solved " + side + " sole reaches its authored support/swing target within 2cm: " + label)
	_staff_rig_samples.append({"label":label, "actor":data.duplicate(true), "observation":"completed native frame_post_draw, solved_revision equals sample_revision"})


func _staff_visible_meshes(actor: Node3D) -> Array[String]:
	var rows: Array[String] = []
	for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.mesh != null:
			rows.append(str(actor.get_path_to(mesh)) + "@" + str(mesh.mesh.get_instance_id()))
	rows.sort()
	return rows


func _staff_check_frame(data: Dictionary, label: String) -> void:
	var inspector := _staff_inspector()
	var camera := inspector.get("camera") as Camera3D
	var viewport := inspector.get("viewport") as SubViewport
	var actor := inspector.get("actor") as Node3D
	var rig := _staff_rig(data)
	var bounds := Rect2(Vector2(5, 5), Vector2(viewport.size) - Vector2(10, 10))
	var points: Dictionary = rig.get("anchors", {}).duplicate(true)
	points["head_clearance"] = actor.to_global(Vector3(0, 1.90, 0))
	var skeletons := actor.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for side: String in ["left", "right"]:
			var foot: Dictionary = rig.get("feet", {}).get(side, {})
			if foot.has("sole"):
				points[side+"_sole"] = skeleton.to_global(foot.sole)
	_check(points.has("base") and points.has("tip"), "Staff tip and base are measured from the actual held weapon: " + label)
	for key: String in points:
		var point: Vector3 = points[key]
		_check(not camera.is_position_behind(point) and bounds.has_point(camera.unproject_position(point)), "The review camera retains the actual head/feet/staff landmark " + key + ": " + label)


func _staff_modal_review() -> void:
	var authority := _authority()
	var camera := _camera(_stage())
	var user := _user_camera()
	var actors := _actors(_stage())
	var stage_detail: Dictionary = _stage().call("detail_audit")
	await _staff_open()
	if not is_instance_valid(_staff_inspector()):
		return
	var inspector := _staff_inspector()
	var actor := inspector.get("actor") as Node3D
	_check(str(_sa().clip) == "attack" and is_zero_approx(float(_sa().time)) and not bool(_sa().playing) and bool(_sa().enabled), "The modal opens paused at attack zero in the new motion mode")
	_check(not actor.is_processing(), "The preview actor has no independent process clock")
	_check(not bool(_ca().get("input_enabled", true)) and not bool((_stage().call("detail_audit") as Dictionary).get("input_enabled", true)), "Staff modal locks the covered battle camera and detail switch")
	var bounds := Rect2(Vector2.ZERO, app.size)
	for id: String in _sa().controls:
		var rect: Rect2 = _sa().controls[id]
		_check(bounds.encloses(rect) and rect.size.x > 0 and rect.size.y > 0, "Review control remains within the usable canvas: " + id)
	var area := inspector.call("ui_control", "StaffModelArea") as Control
	_check(area.size.y >= app.size.y * 0.56, "The staff review model retains at least 56 percent of canvas height")
	_raw_home()
	_raw_drag(_board_point(), Vector2(55, -20), MOUSE_BUTTON_RIGHT)
	_raw_wheel(_board_point(), MOUSE_BUTTON_WHEEL_UP, 3)
	_check(_camera(_stage()) == camera and _user_camera() == user and _authority() == authority, "Actual modal pointer/key input cannot steer or act through the covered battle")
	# The inspector may legitimately consume wheel input for its own zoom.
	# Undo that local probe with the opposite real input before framing review.
	_raw_wheel(_board_point(), MOUSE_BUTTON_WHEEL_DOWN, 3)
	var rejected: Variant = _stage().call("set_refined_details", false)
	_check(rejected is bool and not bool(rejected) and (_stage().call("detail_audit") as Dictionary).enabled == stage_detail.enabled, "Separately labelled direct Stage negative probe rejects detail edits beneath the modal")
	await _staff_click("StaffFrontButton")
	await _staff_seek(0.48)
	var loaded := await _staff_wait_solved(actor)
	_staff_check_rig(loaded, "attack load front")
	_staff_check_frame(loaded, "attack load front")
	await _capture("01-staff-load-new-front.png")
	var before := _sa().duplicate(true)
	var preview_camera := _camera(inspector)
	var actor_transform := actor.transform
	var new_meshes := _staff_visible_meshes(actor)
	await _staff_click("StaffMotionToggleButton")
	var old_meshes := _staff_visible_meshes(actor)
	_check(not bool(_sa().enabled) and _sa().time == before.time and _sa().yaw == before.yaw and _sa().playing == before.playing and _sa().rate == before.rate and _camera(inspector) == preview_camera and actor.transform == actor_transform, "Actual paused A/B preserves the same absolute time, actor root, camera, pause and rate")
	_check(not old_meshes.is_empty() and not new_meshes.is_empty() and old_meshes != new_meshes, "A/B displays retained old swing geometry and the distinct articulated clothing geometry")
	await _capture("02-staff-load-legacy-front.png")
	await _staff_click("StaffMotionToggleButton")
	_check(bool(_sa().enabled) and _sa().time == before.time and _staff_visible_meshes(actor) == new_meshes, "Returning to new motion restores its retained visible geometry without resetting time")
	await _staff_click("StaffRateButton")
	_check(is_equal_approx(float(_sa().rate), 0.5) and _sa().time == before.time, "Real half-speed control changes rate without resetting the paused sample")
	await _staff_click("StaffResetButton")
	_check(is_zero_approx(float(_sa().time)) and not bool(_sa().playing), "The visible reset control returns to the current clip's paused beginning")
	await _staff_transport_measure()
	await _staff_seek(0.85)
	var contact := await _staff_wait_solved(actor)
	_staff_check_rig(contact, "attack contact front")
	_staff_check_frame(contact, "attack contact front")
	await _capture("03-staff-contact-new-front.png")
	await _staff_click("StaffSideButton")
	await _staff_seek(1.17)
	var follow := await _staff_wait_solved(actor)
	_staff_check_rig(follow, "attack recover side")
	_staff_check_frame(follow, "attack recover side")
	await _capture("04-staff-recovery-side.png")
	await _staff_click("StaffThreeQuarterButton")
	await _staff_seek(1.72)
	var guard := await _staff_wait_solved(actor)
	_staff_check_rig(guard, "attack complete guard")
	_staff_check_frame(guard, "attack complete guard")
	await _capture("05-staff-standing-guard.png")
	var index := 6
	for row: Array in [["interrupt",0.22],["stagger",0.55],["recoil",0.18],["walk",0.36]]:
		await _staff_click("StaffClip_"+str(row[0]))
		_check(str(_sa().clip) == str(row[0]) and is_zero_approx(float(_sa().time)) and not bool(_sa().playing), "The real clip choice selects its paused first sample: " + str(row[0]))
		await _staff_seek(float(row[1]))
		var sampled := await _staff_wait_solved(actor)
		_staff_check_rig(sampled, str(row[0]))
		_staff_check_frame(sampled, str(row[0]))
		await _capture("%02d-staff-%s.png" % [index,str(row[0])])
		index += 1
	_check(_authority() == authority and _camera(_stage()) == camera and _actors(_stage()) == actors, "All isolated clips, transport and A/B preserve exact battle/host, actor root/process and battle camera")
	_staff_trials.append({"kind":"isolated_modal","same_time_toggle":before,"new_visible_meshes":new_meshes,"legacy_visible_meshes":old_meshes,"authority_exact":_authority()==authority,"comparison":"same absolute seconds, distinct authored motion and geometry; not same-pose art A/B"})
	var viewport_ref: WeakRef = weakref(inspector.get("viewport"))
	var actor_ref: WeakRef = weakref(actor)
	await _staff_click("CloseStaffButton")
	await _frames(3)
	_check(not is_instance_valid(_staff_inspector()) and viewport_ref.get_ref() == null and actor_ref.get_ref() == null, "The real close control releases the isolated actor and viewport")
	_check(_authority() == authority and _camera(_stage()) == camera and _user_camera() == user and bool(_ca().get("input_enabled", false)), "Closing returns exact battle authority and chosen user camera with input restored")
	_check((_stage().call("detail_audit") as Dictionary).enabled == stage_detail.enabled and bool((_stage().call("detail_audit") as Dictionary).get("input_enabled", false)), "Closing preserves battle art choice and restores the detail input gate")


func _staff_transport_measure() -> void:
	_staff_raw_click("StaffPlayButton")
	_check(bool(_sa().playing), "A real pointer press/release starts the isolated absolute clock")
	await RenderingServer.frame_post_draw
	var initial := _sa().duplicate(true)
	var process_start := Engine.get_process_frames()
	var simulation_seconds := 0.0
	var previous_time := float(initial.time)
	var observations: Array[Dictionary] = []
	while observations.size() < 8 and bool(_sa().playing):
		await process_frame
		await RenderingServer.frame_post_draw
		var current := _sa()
		var delta: float = _staff_inspector().get_process_delta_time()
		simulation_seconds += delta
		observations.append({"process_frame":Engine.get_process_frames(),"delta":delta,"elapsed":current.time})
		_check(float(current.time) >= previous_time, "Half-speed playback advances the actual preview monotonically")
		previous_time = float(current.time)
	var advanced := _sa().duplicate(true)
	_check(observations.size() >= 3 and float(advanced.time) > float(initial.time), "Half-speed review produces multiple genuine playback samples")
	_check(absf((float(advanced.time)-float(initial.time))-simulation_seconds*0.5) < 0.035, "The real preview clock advances at half its accumulated process time")
	var before := _sa().duplicate(true)
	_staff_raw_click("StaffMotionToggleButton")
	var toggled := _sa().duplicate(true)
	_check(not bool(toggled.enabled) and bool(toggled.playing) and toggled.time == before.time and toggled.yaw == before.yaw and toggled.rate == before.rate, "A real A/B click during playback preserves its exact current seconds, camera, playing state and speed synchronously")
	_staff_raw_click("StaffMotionToggleButton")
	_staff_raw_click("StaffPlayButton")
	var paused := _sa().duplicate(true)
	_check(not bool(paused.playing), "The same visible play/pause control pauses the live clock")
	await _frames(4)
	_check(_sa().time == paused.time, "Paused preview time stays exact across real rendered frames")
	_staff_transport.append({"kind":"half_speed_and_live_toggle","initial":initial,"advanced":advanced,"accumulated_process_seconds":simulation_seconds,"process_frames":Engine.get_process_frames()-process_start,"samples":observations,"live_toggle_before":before,"live_toggle_after":toggled,"paused":paused,"boundary":"process-clock ratio; not browser or wall-time performance certification"})


func _staff_battle_raw_button(id: String) -> void:
	var button := _view().ui_control(id) as BaseButton
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "Real battle input is available before monitoring: " + id)
	if button == null or button.disabled:
		return
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	_raw_motion(point, Vector2.ZERO, 0)
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	_raw_button(point, MOUSE_BUTTON_LEFT, false)


func _staff_busy_probe(committed: Dictionary, host: Dictionary) -> void:
	var user := _user_camera()
	var detail: Dictionary = _stage().call("detail_audit")
	_check(bool(_view().audit_snapshot().busy) and not bool(_ca().get("input_enabled", true)), "The real action locks battle camera input")
	for id: String in ["StaffInspectorButton", "DetailToggleButton"]:
		var control := _view().ui_control(id) as BaseButton
		_check(control != null and control.disabled, "The complete action visibly disables " + id)
		if control != null:
			var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
			_raw_motion(point, Vector2.ZERO, 0)
			_raw_button(point, MOUSE_BUTTON_LEFT, true)
			_raw_button(point, MOUSE_BUTTON_LEFT, false)
	_raw_drag(_board_point(), Vector2(55, -20), MOUSE_BUTTON_RIGHT)
	_raw_wheel(_board_point(), MOUSE_BUTTON_WHEEL_DOWN, 2)
	_raw_home()
	_check(_user_camera() == user and _battle() == committed and app.get("_session").snapshot() == host and not is_instance_valid(_staff_inspector()), "Real busy pointer/key probes cannot change user view, duplicate settlement or open the modal")
	var rejected: Variant = _stage().call("set_refined_details", not bool(detail.enabled))
	_check(rejected is bool and not bool(rejected) and (_stage().call("detail_audit") as Dictionary).enabled == detail.enabled, "Separately labelled direct Stage detail API also rejects a busy edit")


func _staff_enemy_round() -> void:
	var medicine_before := int(_battle().objective.hp)
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var camera := _camera(_stage())
	var brute := _stage().get("actor_nodes").brute as Node3D
	var intent_before := _staff_actor_audit(brute).duplicate(true)
	_staff_battle_raw_button("EndRoundButton")
	var committed := _battle().duplicate(true)
	_check(int(committed.round) == 2 and int(committed.objective.hp) == medicine_before - 8, "The ordinary enemy-round input commits the original brute and arrow damage exactly once")
	_staff_busy_probe(committed, host)
	var windup := false
	var impact := false
	var recovery := false
	var attack_entry: Dictionary = {}
	var authority_exact := true
	var rows: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 15000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var stage: Dictionary = _stage().call("audit")
		var presentation: Dictionary = stage.get("combat_presentation", {})
		var motion := _staff_actor_audit(brute)
		if str(presentation.get("actor_id", "")) == "brute" and bool(presentation.get("active", false)):
			var time := float(motion.get("time", motion.get("elapsed", -1.0)))
			var hp := int(stage.get("presented_hp", {}).get("objective", -1))
			if attack_entry.is_empty() and str(motion.get("clip", "")) == "attack":
				var entry_context: Dictionary = (brute.get("_staff_context") as Dictionary).duplicate(true)
				var entry_source: Dictionary = entry_context.get("source_pose", {})
				attack_entry = {"intent_before_pointer":intent_before, "first_rendered_attack":motion.duplicate(true), "passed_context":entry_context, "process_frame":Engine.get_process_frames(), "observation":"first actual rendered attack may already have advanced above zero"}
				_check(not entry_source.is_empty() and entry_source.has("staff_position"), "The real enemy attack retains its prior intent pose as entry context")
				if entry_source.has("staff_position") and intent_before.get("pose", {}).has("staff_position"):
					var source_position: Vector3 = entry_source.staff_position
					var prior_position: Vector3 = intent_before.pose.staff_position
					var observed_position: Vector3 = motion.get("pose", {}).get("staff_position", Vector3.INF)
					attack_entry["source_to_observed_distance"] = source_position.distance_to(observed_position)
					attack_entry["source_to_preclick_intent_distance"] = source_position.distance_to(prior_position)
					_check(str(intent_before.get("clip", "")) == "intent" and source_position.distance_to(prior_position) <= 0.015, "Attack entry carries the already held intent position, allowing its small real-time breath")
					if time <= 0.18:
						_check(source_position.distance_to(observed_position) <= 0.04 and observed_position.distance_to(Vector3(0,0.96,0.24)) >= 0.10, "The first near-zero attack pose continues the held staff instead of returning to the low rest position")
					else:
						attack_entry["continuity_assertion"] = "source retained; first draw later than0.18s, so near-zero distance is recorded without an unjustified threshold assertion"
			rows.append({"motion":motion.duplicate(true),"presentation":presentation.duplicate(true),"presented_medicine_hp":hp,"process_frame":Engine.get_process_frames()})
			if not windup and time >= 0.05 and time < 0.70 and hp == medicine_before:
				windup = true
				_staff_check_rig(motion, "real enemy windup")
				_staff_capture_current("10-staff-enemy-windup.png")
			if not impact and hp == medicine_before - 5 and float(presentation.get("impact_elapsed", -1.0)) >= 0.82:
				impact = true
				_staff_check_rig(motion, "real enemy contact")
				_check(float(presentation.get("timing", {}).get("impact", -1.0)) == 0.82, "The real brute presentation declares its authored 0.82-second contact")
				_staff_capture_current("11-staff-enemy-impact.png")
			if not recovery and time >= 1.10 and time <= 1.73 and hp == medicine_before - 5:
				recovery = true
				_staff_check_rig(motion, "real enemy recovery")
				_staff_capture_current("12-staff-enemy-recovery.png")
		authority_exact = authority_exact and _battle() == committed and app.get("_session").snapshot() == host
		await process_frame
	await _idle()
	_check(windup and impact and recovery, "The actual enemy round renders separate loaded, contact/medicine-damage and full recovery samples")
	_check(authority_exact and _battle() == committed and app.get("_session").snapshot() == host, "The longer brute motion never duplicates or delays the authoritative enemy-round commitment")
	_check(int((_stage().call("audit") as Dictionary).presented_hp.objective) == int(committed.objective.hp), "The visible medicine HP catches up to the once-resolved enemy round")
	_check(_camera(_stage()) == camera and bool(_ca().get("input_enabled", false)), "Complete enemy recovery restores the tactical view and camera control")
	_staff_overlays_clean()
	_staff_trials.append({"kind":"real_enemy_round","windup_seen":windup,"contact_seen":impact,"recovery_seen":recovery,"authority_exact":authority_exact,"entry_continuity":attack_entry,"samples":rows})


func _staff_real_palm() -> void:
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([3, 4])
	_check(_unit("tinglan").pos == [3, 4], "The normal movement input prepares the real palm route")
	await _click("Skill_palm")
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and forecast.get("push_to", []) == [5, 3] and str(forecast.get("collision_barricade_id", "")) == "north_gate", "The actual staff enemy still receives the authored palm/fence forecast")
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var camera := _camera(_stage())
	var point: Vector2 = _view().audit_tile_center([4, 3])
	_raw_motion(point, Vector2.ZERO, 0)
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	_raw_button(point, MOUSE_BUTTON_LEFT, false)
	var committed := _battle().duplicate(true)
	_check(int(_unit("brute").hp) == 9 and _unit("brute").pos == [5, 3] and int(_barricade("north_gate").hp) == 0, "One real palm commits five damage, the same landing and broken north gate")
	_staff_busy_probe(committed, host)
	var brute := _stage().get("actor_nodes").brute as Node3D
	var landing: Vector3 = _stage().call("_tile_world", [5, 3])
	var stagger_seen := false
	var external_clock_seen := false
	var single_owner_pairs := 0
	var single_owner_violations: Array[Dictionary] = []
	var previous_staff_frame: Dictionary = {}
	var last_recoil: Dictionary = {}
	var stagger_entry: Dictionary = {}
	var travel_seen := false
	var contact_seen := false
	var flash_seen := false
	var authority_exact := true
	var rows: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 12000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var motion := _staff_actor_audit(brute)
		var stage: Dictionary = _stage().call("audit")
		var clip := str(motion.get("clip", ""))
		external_clock_seen = external_clock_seen or bool(motion.get("external_clock", false))
		var rig := _staff_rig(motion)
		var frame := Engine.get_process_frames()
		var current_staff_frame := {"clip":clip, "external_clock":bool(motion.get("external_clock", false)), "sample_revision":int(rig.get("sample_revision", -1)), "solved_revision":int(rig.get("solved_revision", -2)), "process_frame":frame, "time":motion.get("time", -1.0), "recipe_active":bool(stage.get("move_player", {}).get("active", false))}
		# Compare only adjacent completed-render observations already within the
		# externally owned stagger. Enter/exit samples legitimately initialize
		# or restore a pose; recipe completion can restore the retained recoil
		# before Stage places its final guard. Skip that exit and skipped frames.
		if clip == "stagger" and str(previous_staff_frame.get("clip", "")) == "stagger" and bool(current_staff_frame.external_clock) and bool(previous_staff_frame.get("external_clock", false)) and bool(current_staff_frame.recipe_active) and bool(previous_staff_frame.get("recipe_active", false)) and frame == int(previous_staff_frame.get("process_frame", -2)) + 1:
			var revision_delta := int(current_staff_frame.sample_revision) - int(previous_staff_frame.sample_revision)
			single_owner_pairs += 1
			if revision_delta < 0 or revision_delta > 1:
				single_owner_violations.append({"previous":previous_staff_frame.duplicate(true), "current":current_staff_frame.duplicate(true), "revision_delta":revision_delta})
		previous_staff_frame = current_staff_frame
		if clip in ["stagger", "recoil"]:
			rows.append({"motion":motion.duplicate(true),"position":brute.position,"presentation":stage.get("combat_presentation",{}).duplicate(true),"gate_hp":stage.get("presented_barricade_hp",{}).get("north_gate",-1), "process_frame":frame, "actor_processing":brute.is_processing(), "recipe_active":current_staff_frame.recipe_active})
			if clip == "recoil":
				last_recoil = motion.duplicate(true)
			if not stagger_seen and clip == "stagger":
				stagger_seen = true
				var entry_context: Dictionary = (brute.get("_staff_context") as Dictionary).duplicate(true)
				var entry_source: Dictionary = entry_context.get("source_pose", {})
				stagger_entry = {"last_rendered_recoil":last_recoil.duplicate(true), "first_rendered_stagger":motion.duplicate(true), "passed_context":entry_context, "process_frame":frame, "observation":"absolute recipe advancement can make the first rendered stagger later than0; only near-zero samples receive a small-distance bound"}
				_check(entry_source.has("staff_position"), "The real palm stagger retains a fixed recoil source pose for its entry")
				if entry_source.has("staff_position"):
					var source_position: Vector3 = entry_source.staff_position
					var observed_position: Vector3 = motion.get("pose", {}).get("staff_position", Vector3.INF)
					stagger_entry["source_to_observed_distance"] = source_position.distance_to(observed_position)
					if not last_recoil.is_empty() and last_recoil.get("pose", {}).has("staff_position"):
						var recoil_position: Vector3 = last_recoil.pose.staff_position
						stagger_entry["source_to_last_recoil_distance"] = source_position.distance_to(recoil_position)
						_check(source_position.distance_to(recoil_position) <= 0.015, "The held recoil and the actual stagger's fixed entry source agree within 1.5cm")
					if float(motion.get("time", 1.0)) <= 0.04:
						_check(source_position.distance_to(observed_position) <= 0.06, "The first near-zero stagger continues its recoil source without a rest-pose snap")
					else:
						stagger_entry["continuity_assertion"] = "source retained; first draw advanced beyond0.04s, so entry displacement is recorded without an unjustified near-zero threshold"
				_staff_check_rig(motion, "real palm stagger")
			contact_seen = contact_seen or clip == "recoil"
		travel_seen = travel_seen or (brute.position.distance_to(landing) > 0.001 and brute.position.distance_to(_stage().call("_tile_world", [4, 3])) > 0.001)
		for node: Node in brute.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			flash_seen = flash_seen or (mesh.is_visible_in_tree() and mesh.material_overlay != null)
		authority_exact = authority_exact and _battle() == committed and app.get("_session").snapshot() == host
		await process_frame
	await _idle()
	_check(stagger_seen and travel_seen and flash_seen, "The actual palm shows the new stagger, real root travel and hit flash on visible geometry")
	_check(external_clock_seen, "The real palm temporarily gives the staff victim's clock to its absolute Stage sampler")
	_check(single_owner_pairs > 0 and single_owner_violations.is_empty(), "Adjacent externally owned stagger frames each request at most one new Actor sample; entry/exit and skipped frames excluded")
	var after_motion := _staff_actor_audit(brute)
	_check(not bool(after_motion.get("external_clock", true)) and brute.is_processing(), "Full palm recovery clears the external clock flag and restores ordinary Actor processing")
	_check(brute.position.distance_to(landing) < 0.00005 and int((_stage().call("audit") as Dictionary).presented_barricade_hp.north_gate) == 0, "The new stance settles at the real landing beside the visibly broken fence")
	_check(authority_exact and _battle() == committed and app.get("_session").snapshot() == host and _camera(_stage()) == camera, "Full staff stagger recovery preserves once-only palm authority and the original camera")
	_staff_overlays_clean()
	await _capture("13-staff-real-palm-landing.png")
	_staff_trials.append({"kind":"real_palm","forecast":forecast,"stagger_seen":stagger_seen,"recoil_seen":contact_seen,"travel_seen":travel_seen,"flash_seen":flash_seen,"authority_exact":authority_exact,"external_clock_seen":external_clock_seen,"single_owner_adjacent_pairs":single_owner_pairs,"single_owner_violations":single_owner_violations,"cleanup_motion":after_motion,"cleanup_processing":brute.is_processing(),"entry_continuity":stagger_entry,"samples":rows})


func _staff_real_interrupt() -> void:
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([3, 4])
	await _click("Skill_interrupt")
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and str(forecast.get("target_id", "")) == "brute", "Real pointer targeting previews an interrupt on the staff enemy")
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	var camera := _camera(_stage())
	var point: Vector2 = _view().audit_tile_center([4, 3])
	_raw_motion(point, Vector2.ZERO, 0)
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	_raw_button(point, MOUSE_BUTTON_LEFT, false)
	var committed := _battle().duplicate(true)
	_check(bool(_plan("brute").get("interrupted", false)) and int(_unit("brute").hp) == 12, "The real interrupt commits two damage and cancels only the original brute intent")
	var brute := _stage().get("actor_nodes").brute as Node3D
	var seen := false
	var pending_samples := 0
	var solved_samples := 0
	var rows: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 12000
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var motion := _staff_actor_audit(brute)
		if str(motion.get("clip", "")) == "interrupt":
			seen = true
			var rig := _staff_rig(motion)
			var solved := int(rig.get("sample_revision", -1)) > 0 and int(rig.get("sample_revision", -1)) == int(rig.get("solved_revision", -2))
			rows.append({"motion":motion.duplicate(true), "solve_completed":solved, "process_frame":Engine.get_process_frames(), "observation":"frame_post_draw; coroutine may have queued a new reaction after this draw's modifier pass"})
			if solved:
				solved_samples += 1
				_staff_check_rig(motion, "real interrupted charge completed frame %d" % solved_samples)
			else:
				# Retain the pending sample as timing evidence. Do not compare a
				# freshly queued pose with the previous deferred native solve.
				pending_samples += 1
		await process_frame
	await _idle()
	_check(seen and solved_samples >= 2, "The actual pointer-selected interrupt renders its distinct broken-charge motion in multiple completed native solve frames")
	_check(_battle() == committed and app.get("_session").snapshot() == host and _camera(_stage()) == camera, "Interrupt recovery leaves exact committed rules, host and camera")
	_staff_overlays_clean()
	await _capture("14-staff-real-interrupt.png")
	_staff_trials.append({"kind":"real_interrupt","forecast":forecast,"interrupt_seen":seen,"completed_solve_samples":solved_samples,"pending_solve_samples":pending_samples,"samples":rows,"authority_exact":_battle()==committed})


func _staff_overlays_clean() -> void:
	for id: String in _stage().get("actor_nodes"):
		var actor := _stage().get("actor_nodes")[id] as Node3D
		var dirty: Array[String] = []
		for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.material_overlay != null:
				dirty.append(str(actor.get_path_to(mesh)))
		_check(dirty.is_empty(), "Actual original and articulated hit overlays clear after recovery: " + id)


func _staff_capture_current(filename: String) -> void:
	# Caller is already at the completed draw being observed. Do not yield into
	# another phase before capturing a short real contact sample.
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(output.path_join(filename))
	_check(image.save_png(path) == OK, "Current completed native frame captured: " + filename)
	captures.append({"file":path,"size":[image.get_width(),image.get_height()],"sha256":FileAccess.get_sha256(path)})


func _finish() -> void:
	var report := {"test":"ambush_staff_ui","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"captures":captures,"window":[qa_size.x,qa_size.y],"display_server":DisplayServer.get_name(),"input":"Actual Godot root.push_input pointer clicks, drag, wheel and keys; actual slider pointer samples. Direct Stage busy/modal negative probes labelled separately.","trials":_staff_trials,"rig_samples":_staff_rig_samples,"transport":_staff_transport,"boundary":"Native Compatibility/PCK presentation, actual modifier solves, same-second original/new comparison and real enemy/palm/interrupt/retry/return. No mocked runtime, gameplay fixture, Mesh.get_faces scan, browser/physical input or artistic approval. Process clock ratio is not a performance benchmark."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t")+"\n")
	print("AMBUSH STAFF UI: %d checks, %d failures, %d captures" % [checks,failures.size(),captures.size()])
	quit(0 if failures.is_empty() else 1)
