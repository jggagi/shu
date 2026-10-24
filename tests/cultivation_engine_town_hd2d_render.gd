extends "res://tests/cultivation_engine_town_walk_render.gd"

const TownHD2DScene := preload("res://scenes/demos/cultivation_engine_v05_town_hd2d.tscn")
var legacy_fixture_path: String = ""
var legacy_evidence: Dictionary = {}
var projection_samples: Array[Dictionary] = []


func _run() -> void:
	output_dir = "res://.local/qa/cultivation-engine-town-hd2d/render"
	_parse_user_args()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--legacy-fixture" and index + 1 < args.size():
			legacy_fixture_path = args[index + 1]
		elif args[index].begins_with("--legacy-fixture="):
			legacy_fixture_path = args[index].trim_prefix("--legacy-fixture=")
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	check(DirAccess.make_dir_recursive_absolute(_absolute_output_dir()) == OK, "HD2D capture directory is available")
	check(DisplayServer.get_name() != "headless", "HD2D verification uses an actual native display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	test_store_dir = "user://town_hd2d_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(test_store_dir)), "HD2D allocates an independent random QA Store")
	app = TownHD2DScene.instantiate() as Control
	# Set the exported Store location before _ready so catalog availability never
	# even scans the native preview's player checkpoint directory.
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	check(str(app.get("_store").get("base_dir")) == test_store_dir, "the UI uses its QA Store from its first catalog scan")
	if await _legacy_continuation():
		if await _click_sequence(["SwitchPackButton", "PackSelectButton_0", "PackStartButton_0", "ConfirmAcceptButton"]):
			await _run_walk_flow()
	_finish()


func _legacy_continuation() -> bool:
	if legacy_fixture_path.is_empty() or not FileAccess.file_exists(legacy_fixture_path):
		check(false, "HD2D receives an actual old-stage QA checkpoint fixture")
		return false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_fixture_path))
	var source_base: String = str(config.get("base_dir", ""))
	if not _expect(FileAccess.get_file_as_string(source_base.path_join(".qa-owner")) == str(config.get("token", "")) and not str(config.get("token", "")).is_empty(), "old-stage fixture carries its matching QA ownership token"):
		return false
	var copied: Dictionary = {}
	for relative: String in config.get("checkpoint_sha256", {}):
		if not _expect(not relative.is_absolute_path() and not relative.contains("..") and relative.ends_with(".json"), "fixture checkpoint uses a safe relative path"):
			return false
		var source: String = source_base.path_join(relative)
		var destination: String = ProjectSettings.globalize_path(test_store_dir).path_join(relative)
		if not _expect(FileAccess.get_sha256(source) == str(config.checkpoint_sha256[relative]), "old-stage checkpoint bytes match the retained fixture receipt"):
			return false
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if not _expect(DirAccess.copy_absolute(source, destination) == OK and FileAccess.get_sha256(destination) == FileAccess.get_sha256(source), "native UI gets an exact checkpoint copy in its own QA Store"):
			return false
		copied[relative] = FileAccess.get_sha256(destination)
	var expected_file := FileAccess.open(str(config.expected_path) + ".bin", FileAccess.READ)
	if expected_file == null:
		check(false, "the old writer's complete typed snapshot is available")
		return false
	var expected: Dictionary = expected_file.get_var(false)
	expected_file.close()
	app.call("_render")
	await process_frame
	if not await _click_sequence(["PackSelectButton_0", "PackContinueButton_0"]):
		return false
	check(await _wait_for_snapshot(expected.town, 90), "new HD2D UI restores the exact old-stage town position, date, stats, flags, counts and receipts")
	check(_position().distance_to(Vector2(1010, 390)) < 2.0 and (_town().get("route", []) as Array).is_empty(), "continuing the old save places feet at the saved anchor without replaying a route")
	await _check_hd2d_projection("old-save continuation")
	await _capture("legacy_00_continued.png", "HD2D continues an unchanged checkpoint written by the prior P1b stage")
	var count: int = int(_town().get("interaction_count", 0))
	if not await _ground_click(Vector2(1010, 350)) or not await _wait_for_interaction(count):
		return false
	check(str(_state().get("last_result", {}).get("action_id", "")) == "greet_tea_seller_again", "HD2D keeps the old save's remembered NPC response")
	check(_state().get("stats", {}) == expected.town.stats and _state().get("day", -1) == expected.town.day and _state().get("slot", -1) == expected.town.slot, "continuing old progress and reading in HD2D charges no extra travel or growth")
	var busy: Dictionary = _state()
	if not await _ground_click(Vector2(160, 260)):
		return false
	check(_state() == busy, "HD2D busy reading keeps old progress unchanged after an exit click")
	if not await _click("SaveButton"):
		return false
	legacy_evidence = {"source_stage": config.source_stage, "fixture_sha256": copied, "restored": expected.town, "continued": _state()}
	await _capture("legacy_01_remembered.png", "new HD2D reading and save after continuing the prior-stage town checkpoint")
	return true


func _expect(condition: bool, message: String) -> bool:
	check(condition, message)
	return condition


func _ground_click(point: Vector2) -> bool:
	# All targets use their actual logical ground anchor. The adapter projects
	# target hit areas; a former 2D portrait offset must not enter this mapping.
	return await super._ground_click(point)


func _check_hd2d_projection(label: String) -> void:
	var before: Dictionary = _state()
	var walker: Control = _walker()
	check(walker != null and walker.has_method("local_to_logical"), label + " exposes reversible projected ground input")
	if walker == null:
		return
	var hd2d: Dictionary = _audit().get("hd2d", {})
	check(not hd2d.is_empty(), label + " reports the actual HD2D presentation")
	var camera: Variant = hd2d.get("camera_position")
	check(camera is Vector3 and (camera as Vector3).y > 0.0, label + " uses a three-dimensional camera above the walk plane")
	check(int(hd2d.get("actor_count", 0)) >= 2 and int(hd2d.get("building_count", 0)) >= 2, label + " populates 3D buildings and separate player/NPC actors")
	var viewport_size: Variant = hd2d.get("viewport_size")
	check(viewport_size is Vector2i and (viewport_size as Vector2i).x > 0 and (viewport_size as Vector2i).y > 0, label + " has a rendered SubViewport with a measured size")
	check(str(hd2d.get("projection", "")) in ["orthographic", "perspective"], label + " declares the camera projection used for input")
	for point: Vector2 in [Vector2(150, 560), Vector2(930, 300), Vector2(1010, 350), Vector2(710, 560), Vector2(160, 260), Vector2(900, 600)]:
		var local: Vector2 = walker.call("logical_to_local", point)
		var roundtrip: Vector2 = walker.call("local_to_logical", local)
		check(local.is_finite() and roundtrip.distance_to(point) <= 1.0, label + " preserves a projected ground anchor through screen-to-world input")
		check(Rect2(Vector2.ZERO, walker.size).has_point(local), label + " keeps its usable ground/target anchor inside the visible scene surface")
		projection_samples.append({"label": label, "logical": [point.x, point.y], "local": [local.x, local.y], "restored": [roundtrip.x, roundtrip.y], "viewport_size": viewport_size})
	check(_state() == before, label + " projection inspection does not mutate persistent game state")


func _capture(filename: String, description: String) -> void:
	if _state().get("scene", "") == "shanxia_town" and filename in ["01_town_arrival.png", "06_position_restored.png"]:
		await _check_hd2d_projection(filename)
	await super._capture(filename, description)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report: Dictionary = {"test": "cultivation_engine_town_hd2d_render", "checks": checks, "failures": failures, "failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "captures": captures, "facings_seen": facings_seen, "projection_samples": projection_samples, "legacy_continuation": legacy_evidence, "result": "PASS" if failures == 0 else "FAIL", "input_method": "Godot root.push_input into projected HD2D scene; not OS physical input or browser"}
	var file := FileAccess.open(_absolute_output_dir().path_join("cultivation-engine-town-hd2d-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CULTIVATION_ENGINE_TOWN_HD2D_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
