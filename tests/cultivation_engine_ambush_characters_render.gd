extends "res://tests/cultivation_engine_ambush_render.gd"
## Visual review of the actual battle actors, plus modal input/state isolation.

var _inspector: Control
var _geometry: Dictionary = {}


func _run() -> void:
	output = "res://.local/qa/ambush-characters/render"
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
	_check(DisplayServer.get_name() != "headless", "Character review uses an actual native Compatibility window")
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
	_check(is_instance_valid(_view()), "The encounter opens with the revised character presentation")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	var before: Dictionary = _battle().duplicate(true)
	var host_before: Dictionary = app.get("_session").snapshot()
	await _capture("00-battle.png")
	await _click("InspectCharactersButton")
	_inspector = _view().get("_character_inspector") as Control
	_check(is_instance_valid(_inspector), "The real character-inspection button opens its modal")
	if not is_instance_valid(_inspector):
		_finish()
		return
	for id: String in _inspector.audit_snapshot().controls:
		var rect: Rect2 = _inspector.audit_snapshot().controls[id]
		_check(Rect2(Vector2.ZERO, app.size).grow(1.0).encloses(rect), "Inspection control %s fits the current window" % id)
	for id: String in ["player", "tinglan", "brute", "blade", "archer"]:
		await _inspector_click("Character_" + id)
		var figure: Node3D = _inspector.get("actor") as Node3D
		figure.set_process(false)
		figure.call("set_motion", "idle")
		figure.call("_process", 0.0)
		_check(_inspector.audit_snapshot().character == id, "The %s figure is the selected actual battle actor" % id)
		_measure_geometry(id, figure)
		for angle: Array in [["front", "FrontButton"], ["side", "SideButton"], ["back", "BackButton"]]:
			await _inspector_click(str(angle[1]))
			await _capture("%s-%s.png" % [id, str(angle[0])])
		if id == "player":
			_check(figure.has_method("approved_model_active") and bool(figure.call("approved_model_active")), "Jiang uses the derivative of his approved original model")
			var skeletons: Array[Node] = figure.find_children("*", "Skeleton3D", true, false)
			_check(skeletons.size() == 1 and (skeletons[0] as Skeleton3D).get_bone_count() == 22, "Jiang retains his actual original 22-bone skeleton")
			_check(_uses_source_colors(figure), "Jiang's real active materials consume the original warm vertex colors in the renderer color space")
		if id == "tinglan":
			await _check_tinglan_source(figure)
		var neutral: Transform3D = _observed_arm_pose(figure)
		figure.call("set_motion", "attack")
		figure.call("_process", 0.13)
		_check(_pose_angle(_observed_arm_pose(figure), neutral) > 0.05, "%s has a visible armed attack pose" % id)
		figure.call("set_motion", "idle")
		figure.call("_process", 0.0)
		_check(_pose_angle(_observed_arm_pose(figure), neutral) < 0.035, "%s explicitly returns to its neutral arm after early attack cancellation" % id)
		figure.set_process(true)
		_check(_battle() == before and app.get("_session").snapshot() == host_before, "Reviewing %s and its poses changes no battle or persistent state" % id)
	await _inspector_click("Character_player")
	await _inspector_click("FrontButton")
	await _inspector_click("CharacterAttackButton")
	await create_timer(0.12).timeout
	await _capture("player-action.png")
	await create_timer(0.4).timeout
	_check(str(_inspector.get("actor").get("_mode")) == "idle", "A preview attack naturally finishes in idle")
	await _inspector_click("CharacterWalkButton")
	await create_timer(0.14).timeout
	await _capture("player-walk.png")
	await create_timer(1.6).timeout
	_check(str(_inspector.get("actor").get("_mode")) == "idle", "The walk preview naturally stops and returns to idle")
	var yaw_before: float = float(_inspector.audit_snapshot().yaw)
	await _inspector_click("AutoTurnButton")
	await create_timer(0.2).timeout
	_check(absf(float(_inspector.audit_snapshot().yaw) - yaw_before) > 0.03, "Automatic turning visibly changes the same model's viewing angle")
	await _inspector_click("AutoTurnButton")
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = pressed
		root.push_input(key)
		await process_frame
	_check(_battle() == before, "Space in character inspection cannot end a hidden battle round")
	var old_inspector: WeakRef = weakref(_inspector)
	var old_viewport: WeakRef = weakref(_inspector.get("viewport"))
	await _inspector_click("CloseCharactersButton")
	_check(not is_instance_valid(_view().get("_character_inspector")), "Returning closes the inspection modal")
	_check(old_inspector.get_ref() == null and old_viewport.get_ref() == null, "Closing inspection releases its modal and render viewport")
	_check(_battle() == before and app.get("_session").snapshot() == host_before, "Returning from inspection retains the exact original encounter and host")
	await _capture("01-battle-return.png")
	await _click("Skill_push")
	await _tile([4, 3])
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "The revised bodies still allow the real barricade-collision knockback target click")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _tile([5, 4])
	_check(_plan("blade").get("interrupted", false), "The revised figures retain the real interrupt target click")
	await _capture("02-control-actions.png")
	var file := FileAccess.open(output.path_join("geometry.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_geometry, "\t") + "\n")
	_finish()


func _check_tinglan_source(figure: Node3D) -> void:
	_check(figure.has_method("candidate_model_active") and bool(figure.call("candidate_model_active")) and not bool(figure.call("approved_model_active")), "Tinglan loads the separate derivative candidate without claiming Jiang's approval")
	var audit: Dictionary = figure.call("get_animation_audit")
	_check(bool(audit.get("ready", false)) and str(audit.get("model", "")).ends_with("tinglan-candidate.glb"), "The real battle and inspector actor use Tinglan's separate model resource")
	_check(_uses_source_colors(figure), "Tinglan's material gains are active in Compatibility")
	var skeleton: Skeleton3D = figure.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_check(skeleton.get_bone_count() == 22, "Tinglan's candidate has the verified actual rig rather than proxy limb nodes")
	var neutral_left: Transform3D = skeleton.get_bone_pose(skeleton.find_bone("upper_arm.L"))
	var neutral_right: Transform3D = skeleton.get_bone_pose(skeleton.find_bone("upper_arm.R"))
	var foot_left: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("foot.L"))
	var foot_right: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("foot.R"))
	_check(audit.left_hand_variant == "relaxed" and int(audit.visible_relaxed_hands) == 1 and int(audit.visible_pointing_hands) == 0, "Idle shows exactly the relaxed left hand")
	figure.call("set_motion", "attack", 1.0, "interrupt")
	figure.call("_process", 0.13)
	audit = figure.call("get_animation_audit")
	_check(audit.source_clip == "TinglanInterrupt" and audit.skill_id == "interrupt" and absf(float(audit.source_seconds) - 0.13) < 0.001, "The pointing strike samples its own authored clip at the real battle impact time")
	_check(_pose_angle(skeleton.get_bone_pose(skeleton.find_bone("upper_arm.L")), neutral_left) > 0.25, "The actual left upper arm clearly extends for the pointing strike")
	_check(_pose_angle(skeleton.get_bone_pose(skeleton.find_bone("upper_arm.R")), neutral_right) < 0.04, "The sword arm retains its guard during the pointing strike")
	_check(audit.left_hand_variant == "pointing" and int(audit.visible_pointing_hands) == 1 and int(audit.visible_relaxed_hands) == 0 and audit.sword_visible and audit.right_grip_visible, "The strike displays one authored double-finger hand and one retained sword grip")
	var origin: Vector3 = figure.call("get_action_origin", "interrupt")
	var local_origin: Vector3 = figure.global_transform.affine_inverse() * origin
	_check(local_origin.y > 1.10 and local_origin.y < 1.55 and local_origin.z > 0.28, "The control trace starts at the raised, forward pointing hand rather than the waist")
	_check(skeleton.get_bone_global_pose(skeleton.find_bone("foot.L")).origin.distance_to(foot_left.origin) < 0.002 and skeleton.get_bone_global_pose(skeleton.find_bone("foot.R")).origin.distance_to(foot_right.origin) < 0.002, "The pointing strike keeps both real foot anchors planted")
	await _inspector_click("FrontButton")
	await _capture("tinglan-interrupt-front.png")
	await _inspector_click("SideButton")
	await _capture("tinglan-interrupt-side.png")
	figure.call("set_motion", "idle")
	figure.call("_process", 0.0)
	audit = figure.call("get_animation_audit")
	_check(audit.left_hand_variant == "relaxed" and int(audit.visible_pointing_hands) == 0 and _pose_angle(skeleton.get_bone_pose(skeleton.find_bone("upper_arm.L")), neutral_left) < 0.02, "Early cancellation fully restores the hand and neutral arm")
	figure.call("set_motion", "attack", 1.0, "interrupt")
	figure.call("_process", 0.41)
	_check(figure.call("get_animation_audit").mode == "idle" and figure.call("get_animation_audit").left_hand_variant == "relaxed", "The complete pointing strike recovers naturally without a stranded finger pose")
	await _inspector_click("FrontButton")
	figure.set_process(true)
	await _inspector_click("CharacterInterruptButton")
	_check(figure.call("get_animation_audit").source_clip == "TinglanInterrupt", "The real inspector pointing button selects the unique action")
	await create_timer(0.45).timeout
	_check(figure.call("get_animation_audit").mode == "idle", "The real preview button completes and returns to idle")
	var button: Control = _inspector.call("ui_control", "CharacterInterruptButton")
	_check(Rect2(Vector2.ZERO, app.size).encloses(button.get_global_rect()), "The new pointing preview control fits the current window")
	figure.set_process(false)
	figure.call("set_motion", "idle")
	figure.call("_process", 0.0)


func _inspector_click(id: String) -> void:
	var control: Control = _inspector.call("ui_control", id) if is_instance_valid(_inspector) else null
	_check(control != null and control.is_visible_in_tree(), "Inspection control %s is visible" % id)
	if control == null:
		return
	await _mouse(control.get_global_transform_with_canvas() * (control.size * 0.5), true)
	await process_frame
	await process_frame


func _measure_geometry(id: String, figure: Node3D) -> void:
	var bounds := AABB()
	var initialized := false
	var triangles := 0
	var mesh_count := 0
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		mesh_count += 1
		triangles += instance.mesh.get_faces().size() / 3
		var local := instance.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = figure.global_transform.affine_inverse() * (instance.global_transform * local.get_endpoint(corner))
			if not initialized:
				bounds = AABB(point, Vector3.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(point)
	_check(initialized and bounds.size.is_finite(), "%s has finite renderable three-dimensional geometry" % id)
	_check(bounds.position.y >= -0.10 and bounds.size.y > 1.45 and bounds.size.y < 2.35, "%s keeps the common foot anchor and a readable figure height" % id)
	_geometry[id] = {"mesh_count": mesh_count, "triangles": triangles, "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}


func _observed_arm_pose(figure: Node3D) -> Transform3D:
	# Observe the real imported skeleton, rather than a proxy limb node.
	for node: Node in figure.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		var index := skeleton.find_bone("upper_arm.R")
		if index >= 0:
			return skeleton.get_bone_pose(index)
	var arm: Node3D = figure.get("right_arm") as Node3D
	return arm.transform if arm != null else Transform3D.IDENTITY


func _pose_angle(a: Transform3D, b: Transform3D) -> float:
	return a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion())


func _uses_source_colors(figure: Node3D) -> bool:
	var enabled := 0
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] == null:
				continue
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.is_empty():
				continue
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo or not material.vertex_color_is_srgb:
				return false
			enabled += 1
	return enabled >= 2
