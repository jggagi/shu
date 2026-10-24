extends SceneTree

const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript = preload("res://addons/cultivation_mode/session.gd")
const StoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const TOWN_MANIFEST := "res://games/shu_town_return/game.json"
const MENTOR_MANIFEST := "res://games/shu_mentor_loop/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"
const REPORT_PATH := "res://.local/qa/cultivation-engine-town-return/state-report.json"

var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var town_pack: Dictionary = {}
var mentor_pack: Dictionary = {}
var stream_pack: Dictionary = {}
var test_base: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader: Variant = LoaderScript.new()
	var town_result: Dictionary = loader.load_pack(TOWN_MANIFEST)
	var mentor_result: Dictionary = loader.load_pack(MENTOR_MANIFEST)
	var stream_result: Dictionary = loader.load_pack(STREAM_MANIFEST)
	check(bool(town_result.get("ok", false)), "the independent town-return pack loads through the shared PackLoader" + ("; " + str(town_result.get("errors", [])) if not bool(town_result.get("ok", false)) else ""))
	check(bool(mentor_result.get("ok", false)), "the retained mentor-loop pack still loads")
	check(bool(stream_result.get("ok", false)), "the unmodified Stream pack still loads")
	if not bool(town_result.get("ok", false)) or not bool(mentor_result.get("ok", false)) or not bool(stream_result.get("ok", false)):
		_finish()
		return
	town_pack = town_result.pack
	mentor_pack = mentor_result.pack
	stream_pack = stream_result.pack
	test_base = _allocate_store_base()
	check(not test_base.is_empty(), "a new isolated town-return save directory is available")
	if test_base.is_empty():
		_finish()
		return
	_check_round_trip_and_free_observation()
	_check_zero_energy_and_day_rollover()
	_check_mentor_and_motion_continuity()
	_check_pack_save_isolation()
	_finish()


func _check_round_trip_and_free_observation() -> void:
	var session: Variant = _new_session(town_pack)
	var initial: Dictionary = session.snapshot()
	check(initial.scene == "tingyu_corridor" and initial.phase == "ready", "the new town pack retains the corridor opening")
	check(not bool(initial.flags.get("town_visited", true)) and not bool(initial.flags.get("town_returned", true)) and not bool(initial.flags.get("town_observed", true)), "a new run has no fabricated town visit, observation or return")
	_reject_action(session, "return_from_town", "wrong-place-return", "returning from town is unavailable in the corridor")
	_reject_action(session, "look_town", "wrong-place-look", "town observation cannot be triggered from the corridor")
	var outbound: Dictionary = session.select_action("go_to_town", "town-first-outbound")
	check(bool(outbound.get("ok", false)), "the registered outbound action is available without a lesson prerequisite")
	var in_town: Dictionary = session.snapshot()
	check(in_town.scene == "shanxia_town" and in_town.phase == "result", "outbound travel settles into the town result phase")
	check(in_town.day == 1 and in_town.slot == 1 and in_town.stats == initial.stats, "outbound travel costs exactly one slot and no growth or energy")
	check(bool(in_town.flags.town_visited) and not bool(in_town.flags.town_returned), "arriving records the visit without completing the return")
	check(int(in_town.counts.get("go_to_town", 0)) == 1 and int(outbound.get("delta", {}).get("slots", -1)) == 1, "outbound travel produces one counted receipt with its actual time cost")
	check(outbound.get("before", {}).get("scene", "") == "tingyu_corridor" and outbound.get("after", {}).get("scene", "") == "shanxia_town", "the travel receipt records the real source and destination")
	var duplicate: Dictionary = session.select_action("go_to_town", "town-first-outbound")
	check(bool(duplicate.get("ok", false)) and bool(duplicate.get("duplicate", false)) and session.snapshot() == in_town, "replaying the outbound operation returns its receipt without charging again")
	_reject_action(session, "return_from_town", "town-first-outbound", "an operation ID cannot be reused for a different travel action")
	_reject_action(session, "return_from_town", "result-phase-return", "a second trip cannot start before acknowledging the arrival result")
	var cancelled: Dictionary = session.cancel_event()
	check(not bool(cancelled.get("ok", false)) and session.snapshot() == in_town, "cancelling a nonexistent travel dialogue does not refund or erase the settled trip")
	var store: Variant = _new_store("round_trip")
	check(session.can_save() and bool(store.save_session(session).get("ok", false)), "the arrival result is a safe saved checkpoint")
	var restored: Variant = _new_session(town_pack)
	check(bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == in_town, "arrival restore preserves the entire result snapshot including travel receipts")
	check(restored.pending_presentation().is_empty(), "loading town arrival creates no presentation or repeated settlement")
	check(bool(session.acknowledge_result().get("ok", false)), "acknowledging arrival releases the next town action")
	var town_ready: Dictionary = session.snapshot()
	check(session.can_save() and bool(store.save_session(session).get("ok", false)), "the ready town scene is also a safe checkpoint")
	check(bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == town_ready, "the latest ready town snapshot restores exactly")
	_reject_action(session, "go_to_town", "town-already-there", "outbound travel cannot be restarted from the town")
	_reject_action(session, "rest_practice", "town-no-mountain-rest", "mountain-only rest is not silently exposed in the town")
	for index: int in range(2):
		var before_look: Dictionary = session.snapshot()
		var observation: Dictionary = session.select_action("look_town", "town-look-%d" % index)
		check(bool(observation.get("ok", false)), "town observation %d is independently repeatable" % (index + 1))
		var after_look: Dictionary = session.snapshot()
		check(after_look.stats == before_look.stats and after_look.day == before_look.day and after_look.slot == before_look.slot, "observation %d grants no reward and consumes no time or energy" % (index + 1))
		check(bool(after_look.flags.town_observed) and not bool(after_look.flags.town_returned), "observation records only its persistent observation flag")
		check(int(after_look.counts.get("look_town", 0)) == index + 1 and int(observation.get("delta", {}).get("slots", -1)) == 0 and observation.get("delta", {}).get("stats", {}) == {}, "each new observation has one free action receipt")
		var repeated_look: Dictionary = session.select_action("look_town", "town-look-%d" % index)
		check(bool(repeated_look.get("duplicate", false)) and session.snapshot() == after_look, "a duplicate observation callback does not add another visit or receipt")
		check(bool(session.acknowledge_result().get("ok", false)), "observation result returns to the town action panel")
	var homeward: Dictionary = session.select_action("return_from_town", "town-first-homeward")
	check(bool(homeward.get("ok", false)), "the registered homeward action returns from town")
	var returned: Dictionary = session.snapshot()
	check(returned.scene == "tingyu_corridor" and returned.day == 1 and returned.slot == 2 and returned.stats == initial.stats, "the round trip returns to the corridor after exactly two slots without changing growth")
	check(bool(returned.flags.town_visited) and bool(returned.flags.town_observed) and bool(returned.flags.town_returned), "return preserves the visit and observation and records the completed return")
	check(int(returned.counts.get("go_to_town", 0)) == 1 and int(returned.counts.get("return_from_town", 0)) == 1, "a round trip contains exactly one outbound and one homeward action")
	check(bool(store.save_session(session).get("ok", false)) and bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == returned, "a returned result checkpoint preserves the complete clock, stats, flags, counts, journal and receipts")
	var old_outbound: Dictionary = restored.select_action("go_to_town", "town-first-outbound")
	check(bool(old_outbound.get("duplicate", false)) and restored.snapshot() == returned, "replaying an old outbound receipt after returning cannot teleport or recharge the run")
	var old_homeward: Dictionary = restored.select_action("return_from_town", "town-first-homeward")
	check(bool(old_homeward.get("duplicate", false)) and restored.snapshot() == returned, "replaying the restored homeward receipt changes no saved state")
	check(bool(restored.acknowledge_result().get("ok", false)), "the restored returned result can be acknowledged")
	_reject_action(restored, "return_from_town", "already-home-return", "a fresh homeward operation cannot be charged when already home")


func _check_zero_energy_and_day_rollover() -> void:
	var session: Variant = _new_session(town_pack)
	# Explicit boundary fixture, validated through restore instead of writing live state.
	var boundary: Dictionary = session.snapshot()
	boundary["slot"] = 5
	boundary["stats"]["energy"] = 0
	check(bool(session.restore(boundary).get("ok", false)), "the validated boundary fixture starts at last slot with zero energy")
	var outbound: Dictionary = session.select_action("go_to_town", "boundary-outbound")
	check(bool(outbound.get("ok", false)), "a time-only outbound trip remains available at zero energy")
	check(session.snapshot().day == 2 and session.snapshot().slot == 0 and session.snapshot().stats.energy == 0, "outbound travel naturally crosses the six-slot day boundary once")
	check(bool(session.acknowledge_result().get("ok", false)), "the day-two arrival result can be acknowledged")
	var homeward: Dictionary = session.select_action("return_from_town", "boundary-homeward")
	check(bool(homeward.get("ok", false)), "zero energy never strands the player in town")
	var returned: Dictionary = session.snapshot()
	check(returned.day == 2 and returned.slot == 1 and returned.scene == "tingyu_corridor" and returned.stats == boundary.stats, "two one-slot trips cross the day without clamping energy or resetting other stats")
	check(int(outbound.get("delta", {}).get("slots", -1)) + int(homeward.get("delta", {}).get("slots", -1)) == 2, "the two travel receipts account for exactly two charged slots")
	var store: Variant = _new_store("day_boundary")
	check(bool(store.save_session(session).get("ok", false)), "the zero-energy day-two result can be saved")
	var restored: Variant = _new_session(town_pack)
	check(bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == returned, "day rollover, zero energy and return completion survive a full checkpoint restore")


func _check_mentor_and_motion_continuity() -> void:
	var session: Variant = _new_session(town_pack)
	check(bool(session.select_action("talk_mentor", "continuity-lesson-open").get("ok", false)), "the retained voiced lesson can open in the town pack")
	_reject_action(session, "go_to_town", "lesson-busy-trip", "the open lesson blocks travel without changing lesson progress or resources")
	check(bool(session.cancel_event().get("ok", false)), "the unchanged ordinary lesson cancellation returns to the corridor")
	check(not bool(session.snapshot().flags.mentor_lesson_heard) and session.snapshot().stats.energy == 100 and session.snapshot().slot == 0, "cancelling before a lesson choice does not invent progress or travel costs")
	check(bool(session.select_action("talk_mentor", "continuity-lesson-reopen").get("ok", false)), "the lesson can be reopened after cancellation")
	_continue_nodes(session, ["opening", "sit", "hurry", "advice"])
	check(str(session.event_view().get("node_id", "")) == "choice", "the original lesson reaches its existing choice")
	check(bool(session.choose("take_lesson", "continuity-lesson-choice").get("ok", false)), "the original paid lesson choice retains its settlement")
	_reject_action(session, "go_to_town", "paid-lesson-busy-trip", "an accepted but unfinished lesson still blocks travel")
	_continue_nodes(session, ["lesson_taken", "lesson_reply", "end"])
	check(bool(session.acknowledge_result().get("ok", false)), "the completed lesson releases the action panel")
	var before_trip: Dictionary = session.snapshot()
	check(before_trip.stats.energy == 92 and before_trip.stats.understanding == 1 and bool(before_trip.flags.breathing_hint), "the real lesson prepares its original one-use training hint")
	check(bool(session.select_action("go_to_town", "continuity-outbound").get("ok", false)), "the prepared student can visit town")
	check(bool(session.acknowledge_result().get("ok", false)), "town arrival is acknowledged before returning")
	check(bool(session.select_action("return_from_town", "continuity-homeward").get("ok", false)), "the prepared student can return to the corridor")
	check(bool(session.acknowledge_result().get("ok", false)), "homeward result releases training access")
	var after_trip: Dictionary = session.snapshot()
	check(after_trip.stats == before_trip.stats and bool(after_trip.flags.breathing_hint) and bool(after_trip.flags.mentor_lesson_heard) and bool(after_trip.flags.mentor_lesson_accepted), "travel preserves all lesson stats, completion and the unspent hint")
	check(bool(session.select_action("go_to_mountain", "continuity-mountain").get("ok", false)) and bool(session.acknowledge_result().get("ok", false)), "the original mountain action still works after returning from town")
	check(bool(session.select_action("pine_wind", "continuity-sword").get("ok", false)), "the existing sword activity still preflights and settles")
	var performing: Dictionary = session.snapshot()
	var pending: Dictionary = session.pending_presentation()
	check(performing.phase == "performing" and performing.stats.energy == 70 and performing.stats.cultivation == 6 and performing.stats.sword == 10, "post-travel sword training retains the real cost and consumes the hint once")
	_reject_action(session, "go_to_town", "motion-busy-outbound", "performing blocks outbound travel")
	_reject_action(session, "return_from_town", "motion-busy-homeward", "performing blocks return travel")
	check(not session.can_save() and session.pending_presentation() == pending, "travel rejection leaves the pending sword and save gate intact")
	check(bool(session.finish_presentation(str(pending.run_id), str(pending.operation_id)).get("ok", false)), "the matching presenter completion releases the original sword result")
	check(bool(session.acknowledge_result().get("ok", false)), "the completed sword result can be acknowledged")
	check(bool(session.select_action("return_to_corridor", "continuity-from-mountain").get("ok", false)) and bool(session.acknowledge_result().get("ok", false)), "the original return-from-mountain action remains available")
	check(bool(session.select_action("report_practice", "continuity-report-open").get("ok", false)), "the old practice report still opens after the town visit")
	check(bool(session.choose("with_lesson", "continuity-report-choice").get("ok", false)), "the original report branch follows the retained lesson choice")
	_continue_nodes(session, ["report_calm", "report_calm_reply", "end"])
	var reported: Dictionary = session.snapshot()
	check(bool(reported.flags.mentor_reported) and int(reported.counts.get("pine_wind", 0)) == 1 and not bool(reported.flags.breathing_hint), "the unchanged mentor goal completes with one sword and the once-only hint consumed")
	var store: Variant = _new_store("mentor_continuity")
	check(bool(store.save_session(session).get("ok", false)), "the complete lesson, town, sword and report history is saveable")
	var restored: Variant = _new_session(town_pack)
	check(bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == reported, "all mentor and travel progress restores as one complete snapshot")
	var duplicate_sword: Dictionary = restored.select_action("pine_wind", "continuity-sword")
	check(bool(duplicate_sword.get("duplicate", false)) and restored.snapshot() == reported and restored.pending_presentation().is_empty(), "a restored old sword callback cannot replay, recharge or grant the hint again")
	check(not bool(restored.finish_presentation(str(pending.run_id), str(pending.operation_id)).get("ok", false)) and restored.snapshot() == reported, "a stale presenter completion cannot change restored travel or mentor progress")


func _check_pack_save_isolation() -> void:
	check(str(town_pack.id) != str(mentor_pack.id) and str(town_pack.id) != str(stream_pack.id), "the new journey has a distinct save identity")
	check(town_pack.rules.get("goals", []) == mentor_pack.rules.get("goals", []), "the journey retains the mentor goal without adding numeric town progress")
	for action_id: String in mentor_pack.actions:
		check(town_pack.actions.has(action_id), "the journey retains the existing mentor activity ID: " + action_id)
	check(not mentor_pack.actions.has("go_to_town") and not mentor_pack.scenes.has("shanxia_town") and not mentor_pack.initial_flags.has("town_visited"), "the retained mentor pack contains no town extension")
	check(not stream_pack.actions.has("go_to_town") and not stream_pack.scenes.has("shanxia_town") and not stream_pack.initial_flags.has("town_visited"), "the independent Stream schema contains no town extension")
	var mentor: Variant = _new_session(mentor_pack)
	var stream: Variant = _new_session(stream_pack)
	var town: Variant = _new_session(town_pack)
	check(bool(mentor.select_action("rest_practice", "isolation-mentor-rest").get("ok", false)), "the retained mentor rest still follows its original rules")
	check(bool(stream.select_action("walk_to_river", "isolation-stream-walk").get("ok", false)) and bool(stream.acknowledge_result().get("ok", false)), "Stream can still move using its independent clock")
	check(bool(stream.select_action("read_by_river", "isolation-stream-read").get("ok", false)), "Stream reading remains a separate registered activity")
	var mentor_expected: Dictionary = mentor.snapshot()
	var stream_expected: Dictionary = stream.snapshot()
	check(mentor_expected.slot == 1 and mentor_expected.stats.energy == 100 and not mentor_expected.flags.has("town_visited"), "retained mentor rules and flags remain unchanged")
	check(stream_expected.scene == "riverbank" and stream_expected.slot == 2 and stream_expected.stats.stamina == 65 and stream_expected.stats.insight == 8, "Stream retains its four-slot clock and original reading reward")
	var store: Variant = _new_store("pack_isolation")
	check(bool(store.save_session(mentor).get("ok", false)) and bool(store.save_session(stream).get("ok", false)), "old mentor and Stream checkpoints save under their own identities")
	var mentor_path: String = str(store.base_dir).path_join(str(mentor_pack.id)).path_join("checkpoint_0.json")
	var stream_path: String = str(store.base_dir).path_join(str(stream_pack.id)).path_join("checkpoint_0.json")
	var mentor_hash: String = FileAccess.get_sha256(mentor_path)
	var stream_hash: String = FileAccess.get_sha256(stream_path)
	check(bool(town.select_action("go_to_town", "isolation-town-outbound").get("ok", false)), "the independent journey can settle while the old sessions remain resident")
	var town_expected: Dictionary = town.snapshot()
	check(mentor.snapshot() == mentor_expected and stream.snapshot() == stream_expected, "the town action cannot mutate either retained session")
	check(bool(store.save_session(town).get("ok", false)), "the new pack writes its own checkpoint in the shared test base")
	check(FileAccess.get_sha256(mentor_path) == mentor_hash and FileAccess.get_sha256(stream_path) == stream_hash, "saving the new journey leaves both old checkpoint files byte-for-byte unchanged")
	for data: Dictionary in [mentor_pack, stream_pack, town_pack]:
		var restored: Variant = _new_session(data)
		var expected: Dictionary = mentor_expected if data.id == mentor_pack.id else (stream_expected if data.id == stream_pack.id else town_expected)
		check(bool(store.load_session(restored).get("ok", false)) and restored.snapshot() == expected, "each pack restores its own complete checkpoint: " + str(data.id))
	var reloaded_old: Dictionary = LoaderScript.new().load_pack(MENTOR_MANIFEST)
	var reloaded_stream: Dictionary = LoaderScript.new().load_pack(STREAM_MANIFEST)
	check(bool(reloaded_old.get("ok", false)) and str(reloaded_old.get("pack", {}).get("_fingerprint", "")) == str(mentor_pack._fingerprint), "town operations leave the retained mentor content fingerprint unchanged")
	check(bool(reloaded_stream.get("ok", false)) and str(reloaded_stream.get("pack", {}).get("_fingerprint", "")) == str(stream_pack._fingerprint), "town operations leave the Stream content fingerprint unchanged")


func _continue_nodes(session: Variant, node_ids: Array) -> void:
	for node_id: String in node_ids:
		check(str(session.event_view().get("node_id", "")) == node_id, "the retained mentor event reaches authored node " + node_id)
		check(bool(session.continue_event().get("ok", false)), "the retained mentor event continues node " + node_id)


func _reject_action(session: Variant, action_id: String, operation_id: String, message: String) -> void:
	var before: Dictionary = session.snapshot()
	var result: Dictionary = session.select_action(action_id, operation_id)
	check(not bool(result.get("ok", false)), message)
	check(session.snapshot() == before, "rejected action preserves the entire snapshot: " + action_id)


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	check(bool(session.configure(data).get("ok", false)), "configure an independent session for " + str(data.get("id", "?")))
	return session


func _new_store(folder: String) -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = test_base.path_join(folder)
	return store


func _allocate_store_base() -> String:
	for attempt: int in range(20):
		var candidate: String = "user://cultivation_engine_town_return_test_%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), attempt]
		var absolute: String = ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)


func _cleanup_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname: String in directory.get_directories():
		_cleanup_tree(path.path_join(dirname))
		DirAccess.remove_absolute(path.path_join(dirname))


func _finish() -> void:
	if not test_base.is_empty():
		var absolute: String = ProjectSettings.globalize_path(test_base)
		_cleanup_tree(absolute)
		DirAccess.remove_absolute(absolute)
	var report: Dictionary = {"test": "cultivation_engine_town_return_test", "checks": checks, "failures": failures, "failure_messages": failure_messages, "result": "PASS" if failures == 0 else "FAIL", "boundary_fixture": "zero energy and last-slot state enter through validated Session.restore", "presentation_completion": "matching callback simulated; no GUI or browser claim"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write town-return state report")
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Town-return state report write failed")
		file.close()
	print("CULTIVATION_ENGINE_TOWN_RETURN_TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
