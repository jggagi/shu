extends SceneTree

const LoaderScript := preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript := preload("res://addons/cultivation_mode/session.gd")
const StoreScript := preload("res://addons/cultivation_mode/save_store.gd")
const SHU_MANIFEST := "res://games/shu_entry/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"

const COMPLETION_FLAG := "completion_test_done"
const END_ONLY_FLAG := "end_only_completion"

var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var test_store_dir: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader: Variant = LoaderScript.new()
	var stream_result: Dictionary = loader.load_pack(STREAM_MANIFEST)
	var shu_result: Dictionary = loader.load_pack(SHU_MANIFEST)
	check(bool(stream_result.get("ok", false)), "the unchanged Stream pack loads through PackLoader")
	check(bool(shu_result.get("ok", false)), "the authored Shu pack loads through PackLoader")
	if not bool(stream_result.get("ok", false)) or not bool(shu_result.get("ok", false)):
		_finish()
		return
	var stream_pack: Dictionary = stream_result.get("pack", {})
	var shu_pack: Dictionary = shu_result.get("pack", {})
	test_store_dir = "user://cultivation_engine_event_completion_%d" % Time.get_ticks_usec()

	_check_open_partial_and_cancel(stream_pack)
	_check_end_commit_stale_repeat_and_restore(stream_pack)
	_check_invalid_end_flags_are_atomic(stream_pack)
	_check_quest_flags_are_reserved(shu_pack)
	_finish()


func _check_open_partial_and_cancel(base_pack: Dictionary) -> void:
	var fixture: Dictionary = _completion_fixture(base_pack, {COMPLETION_FLAG: true, END_ONLY_FLAG: true})
	var loader: Variant = LoaderScript.new()
	check(loader.validate(fixture).is_empty(), "the in-memory completion event fixture is valid pack data")
	var session: Variant = _new_session(fixture)
	var initial: Dictionary = session.snapshot()
	var opened: Dictionary = session.select_action("completion_test", "completion-open-cancel")
	check(bool(opened.get("ok", false)) and str(session.snapshot().get("phase", "")) == "event", "the test event opens through an ordinary zero-cost menu action")
	check(not bool(session.snapshot().get("flags", {}).get(COMPLETION_FLAG, false)), "opening the event does not commit its end flag")
	check(session.snapshot().get("stats", {}) == initial.get("stats", {}) and session.snapshot().get("day", -1) == initial.get("day", -2) and session.snapshot().get("slot", -1) == initial.get("slot", -2), "opening the event does not change resources or time")
	var partial: Dictionary = session.continue_event()
	check(bool(partial.get("ok", false)) and str(session.event_view().get("node_id", "")) == "end", "continuing the opening line reaches the end node")
	var before_cancel: Dictionary = session.snapshot()
	check(not bool(before_cancel.get("flags", {}).get(COMPLETION_FLAG, false)), "a partial event still leaves its end flag false")
	var cancelled: Dictionary = session.cancel_event()
	check(bool(cancelled.get("ok", false)) and session.snapshot().get("phase", "") == "ready", "the ordinary event can be cancelled before its ending is continued")
	check(not bool(session.snapshot().get("flags", {}).get(COMPLETION_FLAG, false)) and session.snapshot().get("stats", {}) == before_cancel.get("stats", {}) and session.snapshot().get("day", -1) == before_cancel.get("day", -2) and session.snapshot().get("slot", -1) == before_cancel.get("slot", -2), "cancelling the partial event preserves progress, resources and time")


func _check_end_commit_stale_repeat_and_restore(base_pack: Dictionary) -> void:
	var fixture: Dictionary = _completion_fixture(base_pack, {COMPLETION_FLAG: true, END_ONLY_FLAG: true})
	var session: Variant = _new_session(fixture)
	session.select_action("completion_test", "completion-end-commit")
	session.continue_event()
	var at_end: Dictionary = session.snapshot()
	check(not bool(at_end.get("flags", {}).get(COMPLETION_FLAG, false)) and not bool(at_end.get("flags", {}).get(END_ONLY_FLAG, false)), "completion flags remain false until the end is continued")
	var run_id: String = str(at_end.get("run_id", ""))
	var revision: int = int(at_end.get("revision", -1))
	var completed: Dictionary = session.continue_event(run_id, revision)
	check(bool(completed.get("ok", false)) and str(session.snapshot().get("phase", "")) == "result", "continuing a valid end node commits it and enters result phase")
	var after_end: Dictionary = session.snapshot()
	var end_flags: Dictionary = after_end.get("flags", {})
	check(bool(end_flags.get(COMPLETION_FLAG, false)) and bool(end_flags.get(END_ONLY_FLAG, false)), "the end atomically sets both authored completion flags")
	check(after_end.get("stats", {}) == at_end.get("stats", {}) and after_end.get("day", -1) == at_end.get("day", -2) and after_end.get("slot", -1) == at_end.get("slot", -2) and after_end.get("sequence", -1) == at_end.get("sequence", -2) and after_end.get("counts", {}) == at_end.get("counts", {}), "end completion changes no costs, gains, time, sequence or action counts")
	var stale: Dictionary = session.continue_event(run_id, revision)
	check(not bool(stale.get("ok", false)) and stale.get("code", "") == "stale_event" and session.snapshot() == after_end, "a stale end continuation is rejected without changing the completed state")
	var repeated: Dictionary = session.continue_event()
	check(not bool(repeated.get("ok", false)) and session.snapshot() == after_end, "repeating end continuation cannot apply flags a second time")

	var store: Variant = StoreScript.new()
	store.base_dir = test_store_dir
	check(bool(store.save_session(session).get("ok", false)), "the end-completed result state saves through SaveStore")
	var restored: Variant = _new_session(fixture)
	var load_result: Dictionary = store.load_session(restored)
	check(bool(load_result.get("ok", false)) and restored.snapshot() == after_end, "SaveStore restores the exact completed event state")
	check(bool(restored.snapshot().get("flags", {}).get(END_ONLY_FLAG, false)), "restore accepts the flag declared only by the end node")


func _check_invalid_end_flags_are_atomic(base_pack: Dictionary) -> void:
	var malformed_maps: Array = [
		{COMPLETION_FLAG: "true"},
		[COMPLETION_FLAG, true]
	]
	for index in range(malformed_maps.size()):
		var fixture: Dictionary = _completion_fixture(base_pack, malformed_maps[index])
		var session: Variant = _new_session(fixture)
		session.select_action("completion_test", "invalid-end-flags-%d" % index)
		session.continue_event()
		var before: Dictionary = session.snapshot()
		var result: Dictionary = session.continue_event()
		check(not bool(result.get("ok", false)) and result.get("code", "") == "invalid_event", "malformed end flag map %d is rejected as invalid_event" % index)
		check(session.snapshot() == before, "malformed end flag map %d leaves the entire state unchanged" % index)


func _check_quest_flags_are_reserved(base_pack: Dictionary) -> void:
	var fixture: Dictionary = _completion_fixture(base_pack, {"tea_active": true, "tea_cup_first_seen": true})
	var session: Variant = _new_session(fixture)
	session.select_action("completion_test", "reserved-quest-end-flags")
	session.continue_event()
	var before: Dictionary = session.snapshot()
	var result: Dictionary = session.continue_event()
	check(not bool(result.get("ok", false)) and result.get("code", "") == "invalid_event", "end nodes cannot write quest or inspection flags")
	check(session.snapshot() == before, "reserved quest-flag rejection is atomic")


func _completion_fixture(base_pack: Dictionary, end_flags: Variant) -> Dictionary:
	var fixture: Dictionary = base_pack.duplicate(true)
	var character_ids: Array = fixture.get("characters", {}).keys()
	var speaker_id: String = str(character_ids[0]) if not character_ids.is_empty() else ""
	var initial_flags: Dictionary = fixture.get("initial_flags", {}).duplicate(true)
	initial_flags[COMPLETION_FLAG] = false
	fixture["initial_flags"] = initial_flags
	var events: Dictionary = fixture.get("events", {}).duplicate(true)
	events["completion_test_event"] = {
		"title": "Completion flag test",
		"start": "opening",
		"nodes": {
			"opening": {"type": "say", "speaker": speaker_id, "text": "Opening line.", "next": "end"},
			"end": {"type": "end", "text": "Event completed.", "set_flags": end_flags}
		}
	}
	fixture["events"] = events
	var actions: Dictionary = fixture.get("actions", {}).duplicate(true)
	actions["completion_test"] = {
		"label": "Open completion test",
		"description": "Zero-cost fixture action for event completion tests.",
		"scenes": [str(fixture.get("initial_scene", ""))],
		"menu": true,
		"duration": 0,
		"costs": {},
		"gains": {},
		"conditions": {"stats_gte": {}, "flags": {}},
		"set_flags": {},
		"once_key": "",
		"bonuses": [],
		"event": "completion_test_event",
		"target_scene": "",
		"result": "The test event opens.",
		"character": speaker_id
	}
	fixture["actions"] = actions
	return fixture


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(data)
	check(bool(configured.get("ok", false)), "EngineSession configures pack %s" % str(data.get("id", "?")))
	return session


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if not test_store_dir.is_empty():
		_cleanup_tree(ProjectSettings.globalize_path(test_store_dir))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_store_dir))
	if failures > 0:
		for message in failure_messages:
			push_error(message)
	print("cultivation_engine_event_completion_test: ", checks - failures, "/", checks, " checks passed")
	quit(0 if failures == 0 else 1)


func _cleanup_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname in directory.get_directories():
		_cleanup_tree(path.path_join(dirname))
		DirAccess.remove_absolute(path.path_join(dirname))
