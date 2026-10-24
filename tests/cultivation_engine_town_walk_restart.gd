extends SceneTree

const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript = preload("res://addons/cultivation_mode/session.gd")
const StoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const MANIFEST := "res://games/shu_town_walk/game.json"
var checks: int = 0
var failures: Array[String] = []
var config: Dictionary = {}
var mode: String = ""
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected MODE CONFIG_PATH")
		quit(2)
		return
	mode = args[0]
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not loaded is Dictionary:
		push_error("Invalid restart QA config")
		quit(2)
		return
	config = loaded
	if not check(ProjectSettings.globalize_path("res://").trim_suffix("/") == str(config.stage), "all resource reads use the selected frozen stage"):
		_finish()
		return
	var complete: bool = _write_process() if mode == "write" else _read_process() if mode == "read" else false
	if not complete and failures.is_empty():
		check(false, "the selected restart QA mode completes")
	_finish()


func _session(manifest: String = MANIFEST) -> Variant:
	var loader: Variant = LoaderScript.new()
	var loaded: Dictionary = loader.load_pack(manifest)
	if not ok(loaded, "load the registered content manifest " + manifest):
		return null
	var session: Variant = SessionScript.new()
	if not ok(session.configure(loaded.pack), "configure a fresh session for " + str(loaded.pack.id)):
		return null
	return session


func _store() -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = str(config.base_dir)
	return store


func _continue_nodes(session: Variant, ids: Array) -> bool:
	for node: String in ids:
		if not check(str(session.event_view().get("node_id", "")) == node, "reach original mentor node " + node):
			return false
		if not ok(session.continue_event(), "continue original mentor node " + node):
			return false
	return true


func _position(session: Variant, point: Array) -> bool:
	var state: Dictionary = session.snapshot()
	return ok(session.commit_walk_position("shanxia_town", point, str(state.run_id), int(state.revision)), "commit a legal test position " + str(point))


func _interaction(session: Variant, target: String, operation: String) -> bool:
	var state: Dictionary = session.snapshot()
	return ok(session.execute_walk_interaction(target, operation, str(state.run_id), int(state.revision)), "execute the registered close-range target " + target)


func _free_reading_done(session: Variant) -> bool:
	for _step: int in range(16):
		var phase: String = str(session.snapshot().phase)
		if phase == "ready":
			return true
		if phase == "result":
			return ok(session.acknowledge_result(), "acknowledge the free town reading")
		if phase == "event":
			if not ok(session.continue_event(), "continue the short town reading"):
				return false
		else:
			return check(false, "town reading uses a supported safe completion phase")
	return check(false, "town reading reaches its short authored end")


func _write_process() -> bool:
	var store: Variant = _store()
	var town: Variant = _session()
	if town == null:
		return false
	if not ok(town.select_action("talk_mentor", "p1b-restart-lesson-open"), "open original mentor dialogue"):
		return false
	if not _continue_nodes(town, ["opening", "sit", "hurry", "advice"]):
		return false
	if not ok(town.choose("take_lesson", "p1b-restart-lesson-choice"), "settle the original eight-energy lesson"):
		return false
	if not _continue_nodes(town, ["lesson_taken", "lesson_reply", "end"]):
		return false
	if not ok(town.acknowledge_result(), "acknowledge the completed lesson") or not ok(town.select_action("go_to_town", "p1b-restart-outbound"), "settle one-slot outbound travel"):
		return false
	if not ok(town.acknowledge_result(), "acknowledge town arrival before walking"):
		return false
	var before_walk: Dictionary = town.snapshot()
	if not _position(town, [1010, 560]) or not _position(town, [1010, 390]):
		return false
	if not _interaction(town, "tea_seller", "p1b-restart-tea") or not _free_reading_done(town):
		return false
	var checkpoint: Dictionary = town.snapshot()
	if not check(checkpoint.scene == "shanxia_town" and checkpoint.phase == "ready" and checkpoint.day == 1 and checkpoint.slot == 2, "writer reaches a safe first-day town position after lesson and travel"):
		return false
	if not check(checkpoint.stats == before_walk.stats and checkpoint.slot == before_walk.slot and checkpoint.day == before_walk.day, "test position commits and town reading are free of game-time or attribute charges"):
		return false
	if not check(checkpoint.exploration.schema_version == 1 and checkpoint.exploration.positions.shanxia_town == [1010, 390], "writer records the new schema's exact town position"):
		return false
	if not _lesson_preserved(checkpoint) or not ok(store.save_session(town), "save the safe town position through SaveStore"):
		return false
	var town_path: String = str(config.base_dir).path_join("shu_town_walk/checkpoint_0.json")
	var town_digest: String = FileAccess.get_sha256(town_path)
	var stream: Variant = _session("res://games/stream_study/game.json")
	if stream == null or not ok(stream.select_action("walk_to_river", "p1b-stream-walk"), "settle the independent Stream journey") or not ok(stream.acknowledge_result(), "acknowledge the separate Stream arrival") or not ok(stream.select_action("read_by_river", "p1b-stream-read"), "settle the separate Stream reading"):
		return false
	var stream_checkpoint: Dictionary = stream.snapshot()
	if not check(not stream_checkpoint.has("exploration") and stream_checkpoint.size() == 14, "the retained Stream state remains the original fourteen-field contract"):
		return false
	if not ok(store.save_session(stream), "save Stream in its own pack directory") or not check(FileAccess.get_sha256(town_path) == town_digest, "saving Stream preserves town checkpoint bytes"):
		return false
	var expected: Dictionary = {"writer_pid": OS.get_process_id(), "town": checkpoint, "stream": stream_checkpoint, "checkpoint_sha256": {"town": town_digest, "stream": FileAccess.get_sha256(str(config.base_dir).path_join("stream_study/checkpoint_0.json"))}}
	if not _write_expected(expected):
		return false
	evidence = expected
	return true


func _read_process() -> bool:
	var typed_file := FileAccess.open(str(config.expected_path) + ".bin", FileAccess.READ)
	if typed_file == null:
		return check(false, "read the writer's typed expected snapshots")
	var expected: Dictionary = typed_file.get_var(false)
	typed_file.close()
	if not check(int(expected.writer_pid) != OS.get_process_id(), "reader is a distinct operating-system process"):
		return false
	var store: Variant = _store()
	var town: Variant = _session()
	if town == null or not ok(store.load_session(town), "restore the town checkpoint after writer exit"):
		return false
	var restored: Dictionary = town.snapshot()
	if not check(restored == expected.town, "the full typed snapshot including position, date, stats, flags, counts and receipts survives process exit") or not _lesson_preserved(restored):
		return false
	var duplicate: Dictionary = town.execute_walk_interaction("tea_seller", "p1b-restart-tea", str(restored.run_id), int(restored.revision))
	if not check(bool(duplicate.get("duplicate", false)) and town.snapshot() == restored, "a repeated persisted interaction operation has no duplicate settlement"):
		return false
	if not _interaction(town, "tea_seller", "p1b-restart-tea-revisit"):
		return false
	var revisited: Dictionary = town.snapshot()
	if not check(str(revisited.last_result.action_id) == "greet_tea_seller_again" and revisited.stats == restored.stats and revisited.day == restored.day and revisited.slot == restored.slot, "the saved greeting flag selects the remembered free NPC response after restart") or not _free_reading_done(town):
		return false
	var invalid_state: Dictionary = town.snapshot()
	var invalid: Dictionary = town.commit_walk_position("shanxia_town", [600, 400], str(invalid_state.run_id), int(invalid_state.revision))
	if not check(not bool(invalid.get("ok", true)) and town.snapshot() == invalid_state, "an obstacle position is rejected without modifying the restored state"):
		return false
	# Deliberate legal test commits; native input verifies actual route traversal.
	for point: Array in [[1010, 560], [160, 560], [160, 310]]:
		if not _position(town, point):
			return false
	if not _interaction(town, "mountain_exit", "p1b-restart-homeward"):
		return false
	var returned: Dictionary = town.snapshot()
	if not check(returned.scene == "tingyu_corridor" and returned.phase == "result" and returned.day == 1 and returned.slot == 3, "the approached exit spends one slot and restores the original corridor context"):
		return false
	if not _lesson_preserved(returned) or not check(bool(returned.flags.town_returned) and int(returned.counts.get("return_from_town", 0)) == 1, "the host records exactly one return with its persistent flag"):
		return false
	if not ok(store.save_session(town), "save the returned corridor result"):
		return false
	var returned_reload: Variant = _session()
	if returned_reload == null or not ok(store.load_session(returned_reload), "read back the returned corridor result") or not check(returned_reload.snapshot() == returned, "the returned snapshot reads back exactly without repeated travel"):
		return false
	if not ok(town.acknowledge_result(), "acknowledge the return") or not ok(town.select_action("go_to_mountain", "p1b-restart-mountain"), "resume the retained mountain route") or not ok(town.acknowledge_result(), "acknowledge the zero-slot mountain route") or not ok(town.select_action("pine_wind", "p1b-restart-sword"), "preflight and settle the retained Songfeng action"):
		return false
	var pending: Dictionary = town.pending_presentation()
	if not check(town.snapshot().phase == "performing" and not town.can_save(), "the original motion phase still blocks saving") or not ok(town.finish_presentation(str(pending.run_id), str(pending.operation_id)), "simulate only the matching original presenter completion callback"):
		return false
	var sword: Dictionary = town.snapshot()
	if not check(sword.scene == "back_mountain" and sword.day == 1 and sword.slot == 4 and sword.stats.energy == 70 and sword.stats.cultivation == 6 and sword.stats.sword == 10, "the retained sword consumes twenty-two energy and the original lesson bonus once"):
		return false
	if not check(not bool(sword.flags.breathing_hint) and bool(sword.flags.mentor_practice_finished) and bool(sword.flags.town_returned), "original practice and town consequences remain continuous") or not ok(store.save_session(town), "save the completed original sword result"):
		return false
	var sword_reload: Variant = _session()
	if sword_reload == null or not ok(store.load_session(sword_reload), "read back the completed sword result") or not check(sword_reload.snapshot() == sword and sword_reload.pending_presentation().is_empty(), "saved sword results restore without replay or repeat reward"):
		return false
	var stream: Variant = _session("res://games/stream_study/game.json")
	if stream == null or not ok(store.load_session(stream), "restore the independent Stream checkpoint") or not check(stream.snapshot() == expected.stream, "the full Stream snapshot remains unchanged by town, return and sword saves"):
		return false
	if not check(FileAccess.get_sha256(str(config.base_dir).path_join("stream_study/checkpoint_0.json")) == str(expected.checkpoint_sha256.stream), "the retained Stream checkpoint bytes stay unchanged"):
		return false
	evidence = {"writer_pid": expected.writer_pid, "reader_pid": OS.get_process_id(), "restored_town": restored, "returned_saved_and_restored": returned, "sword_saved_and_restored": sword, "stream_restored": stream.snapshot()}
	return true


func _lesson_preserved(state: Dictionary) -> bool:
	return check(state.stats.energy == 92 and state.stats.understanding == 1 and state.stats.cultivation == 0 and state.stats.sword == 0 and bool(state.flags.breathing_hint), "travel and restoration preserve the original paid lesson and unspent bonus")


func _write_expected(expected: Dictionary) -> bool:
	if not _write_json(str(config.expected_path), expected):
		return false
	var file := FileAccess.open(str(config.expected_path) + ".bin", FileAccess.WRITE)
	if file == null:
		return check(false, "open typed cross-process expected snapshot file")
	file.store_var(expected)
	file.flush()
	var success: bool = file.get_error() == OK
	file.close()
	return check(success, "write typed snapshots for strict cross-process equality")


func check(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)
	return condition


func ok(result: Dictionary, message: String) -> bool:
	return check(bool(result.get("ok", false)), message + ("" if bool(result.get("ok", false)) else ": " + str(result)))


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return check(false, "open QA report file " + path)
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.flush()
	var success: bool = file.get_error() == OK
	file.close()
	return check(success, "write QA report " + path)


func _finish() -> void:
	var report: Dictionary = {"mode": mode, "pid": OS.get_process_id(), "stage": config.get("stage", ""), "checks": checks + 1, "failures": failures, "result": "PASS" if failures.is_empty() else "FAIL", "scope": "P1b cross-process EngineSession/SaveStore integration; position commits and presenter completion simulated; no UI/browser input evidence", "evidence": evidence}
	_write_json(str(config.report_dir).path_join(mode + "-report.json"), report)
	print("P1B_CROSS_PROCESS_%s: %d checks, %d failures" % [mode.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
