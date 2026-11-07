extends "res://tests/cultivation_ambush_camera_ui_test.gd"
## Real pointer controls in native and the exported PCK. The explicitly labelled
## same-pose visual fixtures pause presentation only; gameplay is never edited.
var _detail_trials: Array[Dictionary] = []
var _detail_budget: Dictionary = {}
var _base_hero_materials: Dictionary = {}


func _run() -> void:
	output = "res://.local/qa/ambush-detail/ui"
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
	_check(DisplayServer.get_name() != "headless", "Refinement review uses the actual native Compatibility renderer")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("detail-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The existing two-versus-three encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	_check(bool(_detail().get("enabled", false)), "The playable candidate starts with refined details enabled")
	_check_detail_contract(true)
	_base_hero_materials = _hero_materials()
	_check_projection(true)
	await _same_pose_battle_pair("00-default")
	await _drag(_board_point(), Vector2(-58, 20), MOUSE_BUTTON_MIDDLE)
	await _wheel(_board_point(), MOUSE_BUTTON_WHEEL_UP, 2)
	_check(not bool(_ca().get("is_default", true)), "Actual mouse input still changes the refined scene's tactical view")
	_check_projection(false)
	await _same_pose_battle_pair("02-near-angle")
	await _inspect_same_pose_enemies()
	await _click("CameraResetButton")
	await _real_palm_and_busy_gate()
	await _click("RestartButton")
	_check(int(_unit("brute").hp) == 14 and _unit("brute").pos == [4, 3] and int(_barricade("north_gate").hp) == 6, "Restart restores the real enemy and intact fence")
	_check(bool(_detail().get("enabled", false)), "A restarted encounter constructs the default refined presentation")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	_check(bool(_view().audit_snapshot().preview.get("ok", false)), "The new costume and terrain preserve actual interrupt targeting")
	await _tile([5, 4])
	_check(bool(_plan("blade").get("interrupted", false)), "A real pointer-selected interrupt still cancels the blade enemy's intent")
	_check_actor_overlays_clean()
	await _capture("12-detail-interrupt-and-retry.png")
	var old_stage: WeakRef = weakref(_stage())
	var old_viewport: WeakRef = weakref(_stage().get("viewport"))
	var sequence := int(app.get("_session").snapshot().sequence)
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_stage.get_ref() == null and old_viewport.get_ref() == null, "Returning releases the complete refined battle and its viewport")
	_check(str(app.get("_session").snapshot().scene) == "shanxia_town" and int(app.get("_session").snapshot().sequence) == sequence + 1, "Returning settles only this encounter once through the original host")
	await _capture("13-detail-return-town.png")
	_finish()


func _detail() -> Dictionary:
	return (_stage().call("detail_audit") as Dictionary).duplicate(true)


func _same_pose_battle_pair(label: String) -> void:
	# Visual fixture only: stop the five actors at their current exact poses and
	# use the player's existing scenery-static control for a clean comparison.
	var environment_was_static: bool = (_stage().call("audit") as Dictionary).environment.get("static", false)
	if not environment_was_static:
		await _click("EnvironmentMotionButton")
	var owners: Dictionary = {}
	for id: String in _stage().get("actor_nodes"):
		var actor: Node3D = _stage().get("actor_nodes")[id]
		owners[id] = actor.is_processing()
		actor.set_process(false)
	var context := _authority()
	var pose := _battle_pose()
	var camera := _camera(_stage())
	await _toggle_battle(false)
	await _capture(label + "-original.png")
	var original := _detail_geometry(_stage().get("world_root"))
	await _toggle_battle(true)
	await _capture(label + "-refined.png")
	var refined := _detail_geometry(_stage().get("world_root"))
	_check(_authority() == context and _battle_pose() == pose and _camera(_stage()) == camera, "The whole same-pose A/B fixture preserves battle, host, exact bones/pivots and the chosen camera: " + label)
	_check(int(refined.nodes) == int(original.nodes), "Switching details uses retained nodes rather than rebuilding the scene: " + label)
	_check(int(refined.visible_triangles) != int(original.visible_triangles) or int(refined.visible_meshes) != int(original.visible_meshes), "Actual visible refinement geometry changes in the renderer: " + label)
	_check(int(refined.visible_triangles) - int(original.visible_triangles) <= 200000 and int(refined.visible_meshes) - int(original.visible_meshes) <= 250, "Additional visible geometry remains within the explicit prototype ceiling: " + label)
	_check(_hero_materials() == _base_hero_materials, "Detail A/B leaves both existing hero material resources exact: " + label)
	_detail_budget[label] = {"original": original, "refined": refined, "audit": _detail(), "fixture": "five existing actor process owners paused; existing scenery-static control; identical gameplay, poses and camera"}
	for id: String in owners:
		(_stage().get("actor_nodes")[id] as Node3D).set_process(bool(owners[id]))
	if not environment_was_static:
		await _click("EnvironmentMotionButton")


func _toggle_battle(enabled: bool) -> void:
	if bool(_detail().get("enabled", false)) == enabled:
		return
	var button := _view().ui_control("DetailToggleButton") as Button
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "The actual battle detail control is available")
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	await _motion(point, Vector2.ZERO, 0)
	await RenderingServer.frame_post_draw
	var authority := _authority()
	var pose := _battle_pose()
	var camera := _camera(_stage())
	var view: Dictionary = _view().audit_snapshot().duplicate(true)
	var environment: Dictionary = (_stage().call("audit") as Dictionary).environment.duplicate(true)
	_raw_button(point, MOUSE_BUTTON_LEFT, true)
	_raw_button(point, MOUSE_BUTTON_LEFT, false)
	_check(bool(_detail().get("enabled", not enabled)) == enabled and bool(_view().audit_snapshot().get("refined_details", not enabled)) == enabled, "Real pointer input changes the visible battle detail mode")
	_check(_authority() == authority and _battle_pose() == pose and _camera(_stage()) == camera, "The synchronous detail click changes no battle/host state, actor pose, motion clock or camera")
	var after: Dictionary = _view().audit_snapshot()
	_check(after.selected == view.selected and after.action == view.action and after.preview == view.preview, "Detail A/B keeps the exact selected fighter, action and preview")
	_check((_stage().call("audit") as Dictionary).environment == environment, "Detail A/B does not reset or advance the environment's presentation clock/state")
	_check_detail_contract(enabled)
	_detail_trials.append({"kind": "actual_battle_button", "enabled": enabled, "authority_unchanged": _authority() == authority, "pose_unchanged": _battle_pose() == pose, "camera_unchanged": _camera(_stage()) == camera, "detail": _detail()})
	await _frames(2)


func _check_detail_contract(enabled: bool) -> void:
	var data := _detail()
	var environment: Dictionary = data.get("environment", {})
	_check(bool(environment.get("ready", false)) and bool(environment.get("enabled", not enabled)) == enabled and bool(environment.get("root_visible", not enabled)) == enabled, "The retained environment finish root follows the actual detail mode")
	_check(int(environment.get("mesh_batches", -1)) > 0 and int(environment.get("mesh_batches", 999)) <= 20 and int(environment.get("triangles", 999999)) <= 20000, "Environment refinement stays within twenty mesh batches and twenty thousand triangles")
	_check(not bool(environment.get("owns_processing", true)) and int(environment.get("decorative_blockers", -1)) == 0 and bool(environment.get("gameplay_clearance_met", false)), "New scenery has no independent clock or gameplay blocker and satisfies its measured clearance")
	_check(float(environment.get("ground_max_height", 1.0)) < 0.023 and float(environment.get("outside_props_min_grid_margin", 0.0)) >= 0.35, "Measured floor decoration stays below tile overlays and tall scenery outside the grid")
	if not enabled:
		_check(bool(environment.get("original_materials_restored", false)), "Original-mode scenery restores every cached original material slot")
	for id: String in ["brute", "blade", "archer"]:
		var actor: Dictionary = data.get("actors", {}).get(id, {})
		_check(bool(actor.get("applicable", false)) and bool(actor.get("enabled", not enabled)) == enabled, "The actual enemy finish follows detail A/B: " + id)
		_check(int(actor.get("mesh_count", 999)) <= 12 and int(actor.get("triangles", 999999)) <= 30000, "The moving enemy finish remains batched under its explicit geometry budget: " + id)
		_check(int(actor.get("visible_mesh_count", -1)) == (int(actor.get("mesh_count", -2)) if enabled else 0), "Only the selected new enemy layer is visible: " + id)
		_check(int(actor.get("original_visible_mesh_count", -1)) == (0 if enabled else int(actor.get("original_mesh_count", -2))), "Original and refined enemy geometry remain mutually exclusive: " + id)
	for id: String in ["player", "tinglan"]:
		_check(not bool(data.get("actors", {}).get(id, {}).get("applicable", true)), "The existing hero is explicitly outside the new enemy finish: " + id)


func _inspect_same_pose_enemies() -> void:
	var context := _authority()
	var camera := _camera(_stage())
	await _click("InspectCharactersButton")
	var inspector: Control = _view().get("_character_inspector")
	_check(is_instance_valid(inspector), "The real character-inspection modal opens")
	if not is_instance_valid(inspector):
		return
	_check(bool((inspector.call("detail_audit") as Dictionary).get("enabled", false)), "Character inspection inherits the battle's refined mode on opening")
	for id: String in ["brute", "blade", "archer"]:
		await _detail_inspector_click(inspector, "Character_" + id)
		await _detail_inspector_click(inspector, "FrontButton")
		var actor: Node3D = inspector.get("actor")
		var process_owner := actor.is_processing()
		actor.set_process(false)
		var pose := _actor_pose(actor)
		var view_camera := _camera(inspector)
		for mode: String in ["original", "refined"]:
			var enabled := mode == "refined"
			if bool((inspector.call("detail_audit") as Dictionary).get("enabled", not enabled)) != enabled:
				await _detail_inspector_click(inspector, "DetailToggleButton")
			_check(bool((inspector.call("detail_audit") as Dictionary).get("enabled", not enabled)) == enabled, "The real inspector A/B button selects " + id + " " + mode)
			_check(_actor_pose(actor) == pose and _camera(inspector) == view_camera, "Close-up A/B preserves the same actual enemy pose and camera: " + id + " " + mode)
			_check(_authority() == context and _camera(_stage()) == camera and bool(_detail().enabled), "Inspector A/B cannot change battle authority, its camera or its independent detail choice")
			await _capture("%s-%s.png" % [id, mode])
		_detail_trials.append({"kind": "same_pose_inspector", "actor": id, "detail": inspector.call("detail_audit"), "geometry": _detail_geometry(actor), "fixture": "only this portrait actor's process owner paused; same front pose and camera"})
		actor.set_process(process_owner)
	# Leave the local modal in original mode to prove its choice is independent.
	await _detail_inspector_click(inspector, "DetailToggleButton")
	_check(not bool((inspector.call("detail_audit") as Dictionary).get("enabled", true)), "The inspector can retain a local original-detail comparison")
	await _detail_inspector_click(inspector, "CloseCharactersButton")
	await _frames(3)
	_check(bool(_detail().enabled) and _authority() == context and _camera(_stage()) == camera, "Closing local inspector A/B preserves the battle's refined mode and its exact authority/view")
	await _click("InspectCharactersButton")
	inspector = _view().get("_character_inspector")
	_check(bool((inspector.call("detail_audit") as Dictionary).get("enabled", false)), "Reopening inherits the battle mode rather than a stale previous local inspector mode")
	await _detail_inspector_click(inspector, "CloseCharactersButton")
	await _frames(3)


func _detail_inspector_click(inspector: Control, id: String) -> void:
	var button: Control = inspector.call("ui_control", id)
	_check(button != null and button.is_visible_in_tree(), "Actual character-inspection control is available: " + id)
	if button != null and button.is_visible_in_tree():
		await _mouse(button.get_global_transform_with_canvas() * (button.size * 0.5), true)
		await _frames(2)


func _real_palm_and_busy_gate() -> void:
	await _click("Unit_tinglan")
	await _click("MoveButton")
	await _tile([3, 4])
	_check(_unit("tinglan").pos == [3, 4], "The refined path still accepts the actual three-step palm setup")
	await _drag(_board_point(), Vector2(40, -16), MOUSE_BUTTON_RIGHT)
	await _click("Skill_palm")
	await _hover_tile([4, 3])
	var forecast: Dictionary = _view().audit_snapshot().preview.duplicate(true)
	_check(bool(forecast.get("ok", false)) and forecast.get("push_to", []) == [5, 3] and str(forecast.get("collision_barricade_id", "")) == "north_gate", "Rotated refined scenery still picks the real palm target and predicts its fence collision")
	var chosen_camera := _camera(_stage())
	var host: Dictionary = app.get("_session").snapshot().duplicate(true)
	await _mouse(_view().audit_tile_center([4, 3]), true)
	var committed := _battle().duplicate(true)
	_check(bool(_view().audit_snapshot().busy) and int(_unit("brute").hp) == 9 and _unit("brute").pos == [5, 3] and int(_barricade("north_gate").hp) == 0, "The one real palm commits the original five-damage collision and destroyed fence")
	var toggle := _view().ui_control("DetailToggleButton") as Button
	_check(toggle != null and toggle.disabled, "The detail button is visibly disabled for the complete real action")
	if toggle != null:
		var point := toggle.get_global_transform_with_canvas() * (toggle.size * 0.5)
		_raw_motion(point, Vector2.ZERO, 0)
		_raw_button(point, MOUSE_BUTTON_LEFT, true)
		_raw_button(point, MOUSE_BUTTON_LEFT, false)
	_check(bool(_detail().enabled) and _battle() == committed and app.get("_session").snapshot() == host, "Repeated real detail-button input while busy cannot alter visuals or duplicate the committed action")
	var rejected: Variant = _stage().call("set_refined_details", false)
	_check(rejected is bool and not bool(rejected) and bool(_detail().enabled), "Separately labelled direct Stage API negative probe also rejects a detail change while busy")
	var flash_seen := false
	var travel_seen := false
	var deadline := Time.get_ticks_msec() + 10000
	var actor: Node3D = _stage().get("actor_nodes").brute
	var landing: Vector3 = _stage().call("_tile_world", [5, 3])
	while bool(_view().audit_snapshot().busy) and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		for item: Node in actor.find_children("*", "MeshInstance3D", true, false):
			var mesh := item as MeshInstance3D
			flash_seen = flash_seen or (mesh.is_visible_in_tree() and mesh.material_overlay != null)
		travel_seen = travel_seen or (actor.position != (_stage().call("_tile_world", [4, 3]) as Vector3) and actor.position.distance_to(landing) > 0.00005)
		await process_frame
	await _idle()
	_check(flash_seen and travel_seen, "The refined enemy visibly receives the existing hit flash and traverses its real shove")
	_check(_battle() == committed and app.get("_session").snapshot() == host and _camera(_stage()) == chosen_camera and actor.position.distance_to(landing) < 0.00005, "Palm recovery keeps exactly one settlement and restores the chosen camera at the real landing")
	_check_actor_overlays_clean()
	_check(_hero_materials() == _base_hero_materials, "Real action and recoil keep the existing hero materials exact")
	_check(not bool((_stage().call("audit") as Dictionary).barricades[0].standing_visible), "The actual broken fence cannot be covered by a new standing decorative copy")
	await _toggle_battle(false)
	await _toggle_battle(true)
	_check_actor_overlays_clean()
	await _capture("11-detail-after-real-palm.png")
	_detail_trials.append({"kind": "actual_palm_collision", "forecast": forecast, "flash_seen": flash_seen, "travel_seen": travel_seen, "detail": _detail(), "direct_negative_probe": "Stage.set_refined_details(false) while action busy"})


func _battle_pose() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _stage().get("actor_nodes"):
		result[id] = _actor_pose(_stage().get("actor_nodes")[id])
	return result


func _actor_pose(actor: Node3D) -> Dictionary:
	var result := {"transform": actor.transform, "processing": actor.is_processing(), "mode": actor.get("_mode"), "pose_time": actor.get("_pose_time"), "attack_real_elapsed": actor.get("_attack_real_elapsed"), "attack_source_clock": actor.get("_attack_source_clock"), "pivots": {}, "skeletons": []}
	for key: String in ["body", "right_arm", "left_arm", "left_leg", "right_leg", "weapon", "head"]:
		var node: Node3D = actor.get(key) as Node3D
		if is_instance_valid(node):
			result.pivots[key] = node.transform
	for node: Node in actor.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		var bones: Array[Transform3D] = []
		for index: int in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_pose(index))
		result.skeletons.append({"path": str(actor.get_path_to(skeleton)), "transform": skeleton.transform, "bones": bones})
	return result


func _hero_materials() -> Dictionary:
	var result: Dictionary = {}
	for id: String in ["player", "tinglan"]:
		var actor: Node3D = _stage().get("actor_nodes")[id]
		var rows: Array[Dictionary] = []
		for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var surfaces: Array = []
			if mesh.mesh != null:
				for index: int in range(mesh.mesh.get_surface_count()):
					surfaces.append(_material_signature(mesh.get_active_material(index)))
			rows.append({"path": str(actor.get_path_to(mesh)), "mesh": mesh.mesh, "override": _material_signature(mesh.material_override), "surfaces": surfaces})
		result[id] = rows
	return result


func _material_signature(material: Material) -> Dictionary:
	if material == null:
		return {}
	var result := {"identity": material.get_instance_id(), "class": material.get_class(), "path": material.resource_path}
	if material is StandardMaterial3D:
		var source := material as StandardMaterial3D
		result.merge({"albedo": source.albedo_color, "roughness": source.roughness, "metallic": source.metallic, "specular": source.metallic_specular, "vertex_color": source.vertex_color_use_as_albedo, "vertex_srgb": source.vertex_color_is_srgb, "transparency": source.transparency, "shading": source.shading_mode, "cull": source.cull_mode, "texture": source.albedo_texture.get_instance_id() if source.albedo_texture != null else 0})
	return result


func _detail_geometry(parent: Node) -> Dictionary:
	var nodes := parent.find_children("*", "Node", true, false)
	var count := 0
	var triangles := 0
	var visible_count := 0
	var visible_triangles := 0
	var collision_count := 0
	for node: Node in nodes:
		if node is CollisionObject3D:
			collision_count += 1
		if not node is MeshInstance3D:
			continue
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		count += 1
		var local_triangles: int = mesh.mesh.get_faces().size() / 3
		triangles += local_triangles
		if mesh.is_visible_in_tree():
			visible_count += 1
			visible_triangles += local_triangles
	return {"nodes": nodes.size(), "meshes": count, "triangles": triangles, "visible_meshes": visible_count, "visible_triangles": visible_triangles, "collision_objects": collision_count}


func _check_actor_overlays_clean() -> void:
	for id: String in _stage().get("actor_nodes"):
		var actor: Node3D = _stage().get("actor_nodes")[id]
		var dirty: Array[String] = []
		for item: Node in actor.find_children("*", "MeshInstance3D", true, false):
			var mesh := item as MeshInstance3D
			if mesh.material_overlay != null:
				dirty.append(str(actor.get_path_to(mesh)))
		_check(dirty.is_empty(), "All original and added actor hit overlays clear after recovery: " + id + " " + str(dirty))


func _finish() -> void:
	var report := {"test": "ambush_detail_ui", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual root.push_input pointer clicks/drags/wheel against battle and character inspector; separately labelled presentation-only same-pose fixtures and direct Stage busy API negative probe", "trials": _detail_trials, "geometry_budget": _detail_budget, "boundary": "Native Compatibility/PCK A/B presentation, authority isolation, actual palm collision/interrupt/retry/return. Visible geometry and budgets do not constitute artistic approval, browser/physical-input validation or long-run performance."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH DETAIL UI: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
