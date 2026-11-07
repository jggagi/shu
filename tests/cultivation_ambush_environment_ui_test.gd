extends "res://tests/cultivation_engine_ambush_render.gd"
## Render the actual scene and send Godot UI input. This is not browser or
## physical-input evidence; screenshots still require visual review.

var _environment_report: Dictionary = {}
var _occlusion: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/songfeng-environment/render"
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
	_check(DisplayServer.get_name() != "headless", "Environment review uses a real rendered window")
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
	_check(is_instance_valid(_view()), "The actual two-versus-three encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	var stage: Control = _view().get("_stage")
	var landscape: Node3D = stage.get("_landscape") as Node3D
	_check(is_instance_valid(landscape), "The actual stage owns its dedicated environment module")
	if not is_instance_valid(landscape):
		_finish()
		return
	var session: RefCounted = app.get("_session")
	var host_before: Dictionary = session.snapshot().duplicate(true)
	var battle_before: Dictionary = _battle().duplicate(true)
	_check_layout()
	_check_environment(landscape)
	_check_projections(stage)
	_check_clear_sightlines(stage, landscape)
	_check_threats(stage)
	_environment_report["initial"] = landscape.call("audit")
	await _capture("00-songfeng-arrival.png")
	var initial_elapsed: float = float(landscape.call("audit").elapsed)
	var initial_visual: Dictionary = _visual_state(landscape)
	await create_timer(0.35).timeout
	_check(float(landscape.call("audit").elapsed) > initial_elapsed + 0.10, "Stage processing advances the controlled scenery clock")
	_check(_visual_state(landscape) != initial_visual, "Dynamic scenery changes actual transforms or material uniforms")
	await _capture("01-songfeng-dynamic.png")
	await _click("EnvironmentMotionButton")
	_check(bool(landscape.call("audit").static), "The real scenery button freezes the environment")
	var frozen_elapsed: float = float(landscape.call("audit").elapsed)
	var frozen_visual: Dictionary = _visual_state(landscape)
	await _capture("02-songfeng-static-a.png")
	await create_timer(0.35).timeout
	_check(is_equal_approx(float(landscape.call("audit").elapsed), frozen_elapsed), "Static keeps the exact controlled environment time")
	_check(_visual_state(landscape) == frozen_visual, "Static freezes actual mesh transforms and material uniforms")
	await _capture("03-songfeng-static-b.png")
	await _click("EnvironmentMotionButton")
	_check(not bool(landscape.call("audit").static), "The real scenery button resumes the same populated environment")
	var resumed_elapsed: float = float(landscape.call("audit").elapsed)
	_check(resumed_elapsed >= frozen_elapsed and resumed_elapsed - frozen_elapsed < 0.30, "Resume continues from the frozen phase without a clock jump")
	await create_timer(0.20).timeout
	_check(float(landscape.call("audit").elapsed) > resumed_elapsed, "Resumed scenery continues advancing")
	_check(session.snapshot() == host_before and _battle() == battle_before, "Environment motion and its real UI toggle change no session or battle state")
	# Stop only the owner's clock while checking exact deterministic reset.
	stage.set_process(false)
	stage.call("set_environment_static", false)
	stage.call("reset_environment")
	_check(is_zero_approx(float(landscape.call("audit").elapsed)), "Environment reset returns its presentation clock to zero")
	var reset_visual: Dictionary = _visual_state(landscape)
	var reset_nodes: int = _subtree_count(landscape)
	for cycle: int in range(3):
		landscape.call("step", 2.25)
		stage.call("reset_environment")
		_check(is_zero_approx(float(landscape.call("audit").elapsed)) and _visual_state(landscape) == reset_visual, "Reset %d restores the actual authored initial phase" % cycle)
		_check(_subtree_count(landscape) == reset_nodes, "Reset %d creates no accumulated nodes" % cycle)
	stage.set_process(true)
	_check(session.snapshot() == host_before and _battle() == battle_before, "Resetting decorative presentation preserves exact authoritative state")
	await _capture("04-songfeng-reset.png")
	await _click("EnvironmentMotionButton")
	_check(bool(landscape.call("audit").static), "Scenery can be frozen while the encounter remains interactive")
	var action_frozen_elapsed: float = float(landscape.call("audit").elapsed)
	var action_frozen_visual: Dictionary = _visual_state(landscape)
	await _click("Skill_push")
	await _hover_tile([4, 3])
	await _capture("05-songfeng-push-preview.png")
	await _tile([4, 3])
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "Scenery preserves the actual mouse-selected barricade-collision knockback")
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	await _capture("06-songfeng-interrupt-preview.png")
	await _tile([5, 4])
	_check(bool(_plan("blade").get("interrupted", false)), "Scenery preserves the actual mouse-selected interrupt target")
	_check(is_equal_approx(float(landscape.call("audit").elapsed), action_frozen_elapsed) and _visual_state(landscape) == action_frozen_visual, "Real combat actions animate and settle while the scenery remains exactly frozen")
	_check(int(session.snapshot().sequence) == int(host_before.sequence), "Scenery mode adds no receipt while normal combat actions resolve")
	_check_threats(stage)
	_check_clear_sightlines(stage, landscape)
	await _capture("07-songfeng-control-result.png")
	await _click("EnvironmentMotionButton")
	_check(not bool(landscape.call("audit").static), "The populated scenery resumes after real combat actions")
	var old_environment: WeakRef = weakref(landscape)
	var old_viewport: WeakRef = weakref(stage.get("viewport"))
	var sequence_before: int = int(session.snapshot().sequence)
	await _click("RestartButton")
	_check(old_environment.get_ref() == null and old_viewport.get_ref() == null, "Restart releases the previous environment and render viewport")
	stage = _view().get("_stage")
	landscape = stage.get("_landscape") as Node3D
	_check(is_instance_valid(landscape) and _subtree_count(landscape) == reset_nodes, "Restart creates exactly one complete replacement scenery subtree")
	_check(int(session.snapshot().sequence) == sequence_before + 1, "Restart settles only its original abandoned-attempt receipt")
	_check(int(_battle().round) == 1 and int(_battle().objective.hp) == 18, "Restart retains the original fresh battle rules")
	_environment_report["restarted"] = landscape.call("audit")
	await _capture("08-songfeng-restart.png")
	old_environment = weakref(landscape)
	old_viewport = weakref(stage.get("viewport"))
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_environment.get_ref() == null and old_viewport.get_ref() == null, "Leaving combat releases scenery and its viewport")
	_check(session.snapshot().scene == "shanxia_town" and session.snapshot().phase == "result", "The same host returns to its correct town result")
	await _capture("09-songfeng-return.png")
	_finish()


func _check_environment(landscape: Node3D) -> void:
	var audit: Dictionary = landscape.call("audit")
	_check(bool(audit.get("ready", false)), "Environment setup has completed")
	_check(not landscape.is_processing(), "The environment uses its stage owner's clock, without an independent process loop")
	_check(not str(audit.get("layout_path", "")).is_empty(), "Scenery reports its separate authored layout resource")
	var mesh_count := 0
	var triangles := 0
	var missing_materials: Array[String] = []
	var nonfinite: Array[String] = []
	var independent_time: Array[String] = []
	for node: Node in landscape.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			missing_materials.append(str(landscape.get_path_to(instance)) + ":no mesh")
			continue
		mesh_count += 1
		triangles += instance.mesh.get_faces().size() / 3
		if not instance.get_aabb().position.is_finite() or not instance.get_aabb().size.is_finite() or not instance.global_transform.origin.is_finite():
			nonfinite.append(str(landscape.get_path_to(instance)))
		for surface: int in range(instance.mesh.get_surface_count()):
			var material: Material = instance.get_active_material(surface)
			if material == null:
				missing_materials.append("%s:%d" % [landscape.get_path_to(instance), surface])
			elif material is ShaderMaterial:
				var shader: Shader = (material as ShaderMaterial).shader
				var uncontrolled_time := RegEx.new()
				uncontrolled_time.compile("\\bTIME\\b")
				if shader == null or uncontrolled_time.search(shader.code) != null:
					independent_time.append(str(landscape.get_path_to(instance)))
	_check(mesh_count > 0 and triangles > 0, "The populated environment contains real renderable geometry")
	_check(missing_materials.is_empty(), "Every environment surface has an actual active material")
	_check(nonfinite.is_empty(), "All scenery bounds and transforms are finite")
	_check(independent_time.is_empty(), "Scenery shaders have no uncontrolled TIME clock")
	_check(landscape.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decorative scenery introduces no undeclared physics blockers")
	_environment_report["geometry"] = {"mesh_count": mesh_count, "triangles": triangles, "node_count": _subtree_count(landscape), "missing_materials": missing_materials, "nonfinite": nonfinite, "uncontrolled_shader_time": independent_time}


func _check_projections(stage: Control) -> void:
	var definition: Dictionary = _view().get("_definition")
	for y: int in range(int(definition.height)):
		for x: int in range(int(definition.width)):
			var tile := [x, y]
			var point: Vector2 = stage.call("tile_to_screen", tile)
			_check(stage.call("screen_to_tile", point) == tile, "Environment preserves real camera projection for tile %d,%d" % [x, y])
			_check(Rect2(Vector2.ZERO, stage.size).has_point(point), "Tile %d,%d stays within the visible playfield" % [x, y])


func _check_clear_sightlines(stage: Control, landscape: Node3D) -> void:
	var camera: Camera3D = stage.get("camera")
	var definition: Dictionary = _view().get("_definition")
	var geometry: Array[Dictionary] = _scenery_geometry(landscape)
	var mist_geometry: Array[Dictionary] = _scenery_geometry(landscape, true)
	var points: Array[Dictionary] = []
	for y: int in range(int(definition.height)):
		for x: int in range(int(definition.width)):
			var tile := [x, y]
			if tile in definition.get("obstacles", []):
				continue
			# Read the actual tile overlay height, with only a 2 mm tolerance.
			# A higher ray could miss a stone that hides a real threat marker.
			var fill: MeshInstance3D = stage.get("_tile_meshes").get(stage.call("_key", tile))
			points.append({"id": "tile:%d,%d" % [x, y], "at": fill.global_position + Vector3.UP * 0.002})
	for id: String in stage.get("actor_nodes"):
		var figure: Node3D = stage.get("actor_nodes")[id]
		if figure.visible:
			points.append({"id": "actor:" + id, "at": figure.global_position + Vector3.UP * 1.10})
	var objective: Node3D = stage.get("_objective")
	points.append({"id": "objective", "at": objective.global_position + Vector3.UP * 0.40})
	for group: Array in [["opaque", geometry], ["mist", mist_geometry]]:
		var blockers: Array[Dictionary] = []
		for point: Dictionary in points:
			var target: Vector3 = point.at
			var projected: Vector2 = camera.unproject_position(target)
			var start: Vector3 = camera.project_ray_origin(projected)
			for mesh_entry: Dictionary in group[1]:
				var bounds: AABB = mesh_entry.bounds
				if bounds.intersects_segment(start, target) == null:
					continue
				var vertices: PackedVector3Array = mesh_entry.triangles
				for index: int in range(0, vertices.size(), 3):
					if Geometry3D.segment_intersects_triangle(start, target, vertices[index], vertices[index + 1], vertices[index + 2]) != null:
						blockers.append({"target": point.id, "mesh": mesh_entry.path})
						break
		_check(blockers.is_empty(), "Actual %s scenery triangles stay out of sightlines to playable tile centers, actor chests and the objective" % group[0])
		_occlusion.append({"kind": group[0], "tested_targets": points.size(), "meshes": group[1].size(), "blockers": blockers, "method": "Actual transformed triangles; aesthetic readability is additionally reviewed in captures"})


func _scenery_geometry(landscape: Node3D, mist_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in landscape.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		if mist_only and str(instance.get_meta("environment_kind", "")) != "mist":
			continue
		var triangles := PackedVector3Array()
		var bounds := AABB()
		var initialized := false
		for surface: int in range(instance.mesh.get_surface_count()):
			var material: Material = instance.get_active_material(surface)
			if not mist_only and material is BaseMaterial3D:
				var standard := material as BaseMaterial3D
				if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and standard.albedo_color.a < 0.80:
					continue
			elif not mist_only and material is ShaderMaterial:
				var shader: Shader = (material as ShaderMaterial).shader
				if shader != null and "ALPHA" in shader.code:
					continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index: int in range(vertices.size()):
					indices.append(index)
			for index: int in indices:
				var point: Vector3 = instance.global_transform * vertices[index]
				triangles.append(point)
				if not initialized:
					bounds = AABB(point, Vector3.ZERO)
					initialized = true
				else:
					bounds = bounds.expand(point)
		if triangles.size() >= 3:
			result.append({"path": str(landscape.get_path_to(instance)), "triangles": triangles, "bounds": bounds})
	return result


func _visual_state(landscape: Node3D) -> Dictionary:
	var state: Dictionary = {}
	for node: Node in landscape.find_children("*", "Node3D", true, false):
		var object := node as Node3D
		var entry := {"transform": var_to_str(object.transform), "visible": object.visible}
		if object is MeshInstance3D:
			var instance := object as MeshInstance3D
			var materials: Array = []
			if instance.mesh == null:
				entry["materials"] = ["missing mesh"]
				state[str(landscape.get_path_to(object))] = entry
				continue
			for surface: int in range(instance.mesh.get_surface_count()):
				var material: Material = instance.get_active_material(surface)
				if material is ShaderMaterial:
					var shader_mat := material as ShaderMaterial
					var parameters: Dictionary = {}
					for uniform: Dictionary in shader_mat.shader.get_shader_uniform_list():
						var id: String = str(uniform.name)
						parameters[id] = var_to_str(shader_mat.get_shader_parameter(id))
					materials.append(parameters)
				elif material is BaseMaterial3D:
					materials.append(var_to_str((material as BaseMaterial3D).albedo_color))
			entry["materials"] = materials
		state[str(landscape.get_path_to(object))] = entry
	return state


func _subtree_count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _subtree_count(child)
	return total


func _check_threats(stage: Control) -> void:
	var expected: Array = []
	for plan: Dictionary in _battle().plans:
		if bool(plan.interrupted) or int(_unit(str(plan.unit_id)).hp) <= 0:
			continue
		for tile: Array in plan.cells:
			if not expected.has(tile):
				expected.append(tile)
	var actual: Array = stage.call("audit").danger_cells
	_check(actual.size() == expected.size() and expected.all(func(tile: Array) -> bool: return actual.has(tile)), "Environmental styling preserves the exact real enemy-threat cells")
	var visible := 0
	for tile: Array in actual:
		var key: String = stage.call("_key", tile)
		var fill: MeshInstance3D = stage.get("_tile_meshes").get(key)
		if fill != null and fill.is_visible_in_tree():
			visible += 1
	_check(visible == actual.size(), "Every current threat cell retains its visible board overlay")


func _finish() -> void:
	var report := {"test": "mountain_ambush_songfeng_environment", "checks": checks, "failures": failures,
		"captures": captures, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(),
		"environment": _environment_report, "occlusion": _occlusion,
		"input": "Godot root.push_input mouse events, not physical input or browser",
		"visual_acceptance": "Captures require visual review and user playtest; geometry and input checks do not establish aesthetic approval",
		"result": "PASS" if failures.is_empty() else "FAIL"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("SONGFENG ENVIRONMENT: %d checks, %d failures, %d captures" % [checks, failures.size(), captures.size()])
	quit(0 if failures.is_empty() else 1)
