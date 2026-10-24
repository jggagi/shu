extends SceneTree

const LoaderScript := preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript := preload("res://addons/cultivation_mode/session.gd")
const StoreScript := preload("res://addons/cultivation_mode/save_store.gd")
const SHU_MANIFEST := "res://games/shu_entry/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"
const REPORT_PATH := "res://.local/qa/engine-v01/state-report.json"

var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var loader: Variant
var shu_pack: Dictionary = {}
var stream_pack: Dictionary = {}
var test_base: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	loader = LoaderScript.new()
	var shu_result: Dictionary = loader.load_pack(SHU_MANIFEST)
	var stream_result: Dictionary = loader.load_pack(STREAM_MANIFEST)
	check(bool(shu_result.get("ok", false)), "the authored shu_entry pack loads through PackLoader")
	check(bool(stream_result.get("ok", false)), "the authored stream_study pack loads through PackLoader")
	if not bool(shu_result.get("ok", false)) or not bool(stream_result.get("ok", false)):
		_finish()
		return
	shu_pack = shu_result.get("pack", {})
	stream_pack = stream_result.get("pack", {})
	test_base = "user://engine_test_%d" % Time.get_ticks_usec()

	_check_loader_rejections()
	_check_one_session_uses_both_packs()
	_check_shu_actions_and_atomicity()
	_check_shu_dialogue_bonus_and_goal()
	_check_stale_continue()
	_check_stream_actions_and_dialogue()
	_check_stream_goal()
	_check_restore_rejection_is_atomic()
	_check_ready_and_result_save_roundtrips()
	_check_cross_pack_version_and_checksum_rejection()
	_check_corrupt_latest_fallback()
	_check_injected_write_failure_preserves_previous_save()
	var test_base_absolute: String = ProjectSettings.globalize_path(test_base)
	_cleanup_tree(test_base_absolute)
	DirAccess.remove_absolute(test_base_absolute)
	_finish()


func _check_loader_rejections() -> void:
	var bad: Dictionary = shu_pack.duplicate(true)
	bad["actions"]["train_mountain"]["scenes"] = ["missing_scene"]
	_expect_invalid_pack(bad, "loader rejects an action that references an unknown scene")

	bad = shu_pack.duplicate(true)
	bad["rules"]["stats"][0]["initial"] = "100"
	_expect_invalid_pack(bad, "loader rejects a numeric stat encoded as a string")

	bad = shu_pack.duplicate(true)
	bad["actions"]["train_mountain"]["gains"]["cultivation"] = -1
	_expect_invalid_pack(bad, "loader rejects a negative authored gain")

	bad = shu_pack.duplicate(true)
	bad["actions"]["train_mountain"]["conditions"] = {"day_equals": 1}
	_expect_invalid_pack(bad, "loader rejects an unsupported condition type")

	bad = shu_pack.duplicate(true)
	bad["events"]["mentor_tip"]["nodes"]["opening"]["next"] = "opening"
	_expect_invalid_pack(bad, "loader rejects a small cyclic event graph without hanging")

	bad = shu_pack.duplicate(true)
	bad["events"]["mentor_tip"]["nodes"]["opening"]["next"] = "missing_node"
	_expect_invalid_pack(bad, "loader rejects a dangling event edge")

	bad = shu_pack.duplicate(true)
	bad["scenes"]["back_mountain"]["actors"][0]["region"] = [0, 0, 9999, 9999]
	_expect_invalid_pack(bad, "loader rejects a static actor atlas region outside the source texture")

	bad = shu_pack.duplicate(true)
	bad["scenes"]["tingyu_corridor"]["foreground"]["width"] = 0
	_expect_invalid_pack(bad, "loader rejects a zero-width foreground instead of hiding the composition error")

	bad = shu_pack.duplicate(true)
	bad["events"]["mentor_tip"]["nodes"]["choice"]["options"][0]["conditions"] = {"flags": 7}
	_expect_invalid_pack(bad, "loader rejects malformed nested choice conditions without runtime errors")

	bad = shu_pack.duplicate(true)
	bad["characters"] = []
	_expect_invalid_pack(bad, "loader rejects a non-object cast without invoking untrusted data")


func _expect_invalid_pack(candidate: Dictionary, label: String) -> void:
	var issues: Array[String] = loader.validate(candidate)
	check(not issues.is_empty(), label)


func _check_one_session_uses_both_packs() -> void:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(shu_pack)
	check(bool(configured.get("ok", false)), "one EngineSession configures the first authored pack")
	check(session.pack.get("id", "") == "shu_entry" and session.state.stats.get("energy", -1) == 100, "the configured session starts with shu_entry rules and resources")
	configured = session.configure(stream_pack)
	check(bool(configured.get("ok", false)), "the same EngineSession reconfigures for the second authored pack")
	check(session.pack.get("id", "") == "stream_study", "the same runtime now identifies the second pack")
	check(session.state.stats == {"stamina": 80, "insight": 0}, "the second pack uses only its own resource IDs and starting values")
	check(session.state.scene == "tea_pavilion" and session.state.sequence == 0, "reconfiguration starts a clean run in the second pack's start scene")


func _check_shu_actions_and_atomicity() -> void:
	var session: Variant = _new_session(shu_pack)
	var start: Dictionary = session.snapshot()
	var travel: Dictionary = session.select_action("go_to_mountain", "shu-travel")
	check(bool(travel.get("ok", false)), "shu travel settles through a normal action request")
	check(travel.get("before", {}).get("scene", "") == "tingyu_corridor" and travel.get("after", {}).get("scene", "") == "back_mountain", "travel receipt records the actual scene transition")
	check(travel.get("delta", {}).get("slots", -1) == 0 and session.state.slot == start.slot, "zero-duration shu travel does not advance the clock")
	check(session.state.phase == "result" and session.state.receipts.has("shu-travel"), "travel creates a replayable receipt and enters result phase")
	check(bool(session.acknowledge_result().get("ok", false)) and session.state.phase == "ready", "acknowledging travel returns the session to ready")

	for index in range(4):
		var rest: Dictionary = session.select_action("rest_practice", "shu-pretrain-rest-%d" % index)
		check(bool(rest.get("ok", false)), "shu rest action %d settles" % (index + 1))
		check(session.state.stats.energy == 100, "rest clamps energy at its authored maximum")
		check(bool(session.acknowledge_result().get("ok", false)), "shu rest result %d returns to ready" % (index + 1))
	check(session.state.day == 1 and session.state.slot == 4, "four rests advance to the final pre-rollover shu slot")

	var train: Dictionary = session.select_action("train_mountain", "shu-train-cycle")
	check(bool(train.get("ok", false)), "shu training settles with sufficient energy")
	check(train.get("delta", {}).get("stats", {}).get("energy", 0) == -22 and train.get("delta", {}).get("stats", {}).get("cultivation", 0) == 12, "shu training receipt reports actual -22/+12 changes")
	check(train.get("delta", {}).get("slots", -1) == 2, "shu training receipt reports its two-slot duration")
	check(session.state.stats.energy == 78 and session.state.stats.cultivation == 12, "shu training applies its authored resource change")
	check(session.state.day == 2 and session.state.slot == 0, "shu training rolls the clock over at the correct boundary")
	var result_actions_disabled: bool = true
	for action: Dictionary in session.available_actions():
		if bool(action.get("enabled", false)):
			result_actions_disabled = false
	check(session.state.phase == "result" and result_actions_disabled, "result phase disables further menu actions until acknowledged")
	var result_state: Dictionary = session.snapshot()
	var duplicate: Dictionary = session.select_action("train_mountain", "shu-train-cycle")
	check(bool(duplicate.get("ok", false)) and bool(duplicate.get("duplicate", false)), "replaying the same operation ID returns its original result")
	check(session.snapshot() == result_state, "duplicate action replay cannot settle or advance twice")
	var mismatch: Dictionary = session.select_action("rest_practice", "shu-train-cycle")
	check(not bool(mismatch.get("ok", false)) and mismatch.get("code", "") == "operation_mismatch", "an operation ID bound to another action is rejected")
	check(session.snapshot() == result_state, "mismatched operation replay preserves the full session state")
	check(bool(session.acknowledge_result().get("ok", false)) and session.state.phase == "ready", "acknowledging training returns to ready")
	var capped_rest: Dictionary = session.select_action("rest_practice", "shu-rest-to-cap")
	check(bool(capped_rest.get("ok", false)) and session.state.stats.energy == 100, "shu rest restores energy without exceeding its maximum")
	check(capped_rest.get("delta", {}).get("stats", {}).get("energy", 0) == 22, "shu rest receipt reports only the actual twenty-two-point recovery")

	var capped: Variant = _new_session(shu_pack)
	var cap_fixture: Dictionary = capped.snapshot()
	cap_fixture["scene"] = "back_mountain"
	cap_fixture["stats"]["cultivation"] = 95
	check(bool(capped.restore(cap_fixture).get("ok", false)), "valid shu boundary fixture restores before any action")
	var cap_result: Dictionary = capped.select_action("train_mountain", "shu-cap-train")
	check(bool(cap_result.get("ok", false)), "training remains valid near the growth cap")
	check(capped.state.stats.cultivation == 100 and cap_result.get("delta", {}).get("stats", {}).get("cultivation", 0) == 5, "training clamps growth and receipt to the actual five-point gain")

	var poor: Variant = _new_session(shu_pack)
	var poor_fixture: Dictionary = poor.snapshot()
	poor_fixture["scene"] = "back_mountain"
	poor_fixture["stats"]["energy"] = 21
	check(bool(poor.restore(poor_fixture).get("ok", false)), "valid shu low-energy fixture restores")
	var before: Dictionary = poor.snapshot()
	var denied: Dictionary = poor.select_action("train_mountain")
	check(not bool(denied.get("ok", false)) and denied.get("code", "") == "insufficient_resource", "training one energy below cost is refused")
	check(poor.snapshot() == before, "insufficient energy leaves resources, clock, sequence, flags, counts and receipts unchanged")


func _check_shu_dialogue_bonus_and_goal() -> void:
	var session: Variant = _new_session(shu_pack)
	var talk: Dictionary = session.select_action("talk_mentor", "shu-talk-cancel")
	check(bool(talk.get("ok", false)) and session.state.phase == "event", "mentor action opens a data-driven event")
	check(not session.can_save(), "an in-progress mentor event cannot be saved")
	var store: Variant = _new_store(test_base.path_join("dialogue_save_guard"))
	var dialogue_snapshot: Dictionary = session.snapshot()
	check(not bool(store.save_session(session).get("ok", false)), "SaveStore refuses a mid-dialogue save")
	check(session.snapshot() == dialogue_snapshot, "refused dialogue save does not alter the active event")
	check(bool(session.continue_event().get("ok", false)) and session.event_view().get("type", "") == "choice", "mentor opening continues to its authored choice node")
	var before_cancel: Dictionary = session.snapshot()
	check(bool(session.cancel_event().get("ok", false)), "ordinary mentor dialogue can be cancelled")
	check(session.state.phase == "ready" and session.state.event.is_empty(), "cancelling clears only the active event pointer")
	check(session.state.stats == before_cancel.stats and session.state.day == before_cancel.day and session.state.slot == before_cancel.slot, "cancelling preserves already committed action resources and time")

	session.select_action("talk_mentor", "shu-talk-lesson")
	session.continue_event()
	var choice: Dictionary = session.event_view()
	check(choice.get("type", "") == "choice" and choice.get("options", []).size() == 2, "mentor choices come from the selected pack data")
	var selected: Dictionary = session.choose("take_lesson", "shu-lesson-choice")
	check(bool(selected.get("ok", false)) and selected.get("action_id", "") == "claim_mentor_lesson", "the selected private action settles through the choice transaction")
	check(session.state.stats.energy == 92 and session.state.stats.understanding == 1, "claiming the mentor hint spends eight energy and grants one understanding")
	check(session.state.slot == 1 and session.state.flags.breathing_hint, "claiming the hint advances one slot and arms its one-use bonus")
	var after_choice: Dictionary = session.snapshot()
	var repeated_choice: Dictionary = session.choose("take_lesson", "shu-lesson-choice")
	check(bool(repeated_choice.get("duplicate", false)), "replaying a committed event choice returns its receipt")
	check(session.snapshot() == after_choice, "stale duplicate choice does not advance the event pointer twice")
	var different_stale_choice: Dictionary = session.choose("return_to_practice", "shu-lesson-choice")
	check(not bool(different_stale_choice.get("ok", false)) and different_stale_choice.get("code", "") == "operation_mismatch", "the same choice operation ID cannot be reused for another branch")
	check(session.snapshot() == after_choice, "a mismatched stale choice leaves the current event untouched")
	check(bool(session.continue_event().get("ok", false)) and session.event_view().get("node_id", "") == "end", "the selected lesson branch reaches its authored ending")
	check(bool(session.continue_event().get("ok", false)) and session.state.phase == "result", "continuing the event ending returns to result phase")
	session.acknowledge_result()
	session.select_action("go_to_mountain", "shu-lesson-travel")
	session.acknowledge_result()
	var bonus_train: Dictionary = session.select_action("train_mountain", "shu-bonus-train")
	check(bool(bonus_train.get("ok", false)) and bonus_train.get("delta", {}).get("stats", {}).get("cultivation", 0) == 18, "the next training consumes the mentor hint for twelve plus six growth")
	check(session.state.stats.energy == 70 and not session.state.flags.breathing_hint, "the one-use mentor bonus is consumed atomically with training")
	session.acknowledge_result()
	var base_train: Dictionary = session.select_action("train_mountain", "shu-base-train")
	check(bool(base_train.get("ok", false)) and base_train.get("delta", {}).get("stats", {}).get("cultivation", 0) == 12, "later training returns to its authored base gain")
	check(not session.state.flags.breathing_hint, "the consumed mentor bonus is not recreated")

	var goal_session: Variant = _new_session(shu_pack)
	var goal_fixture: Dictionary = goal_session.snapshot()
	goal_fixture["stats"]["cultivation"] = 60
	check(bool(goal_session.restore(goal_fixture).get("ok", false)), "valid shu goal boundary fixture restores")
	var report: Dictionary = goal_session.select_action("report_practice", "shu-goal-report")
	check(bool(report.get("ok", false)) and goal_session.state.phase == "event", "a qualified shu goal opens its report event")
	goal_session.continue_event()
	goal_session.continue_event()
	check(goal_session.state.phase == "result" and goal_session.state.flags.cultivation_goal_reported, "finishing the report returns to results and marks its once-only goal")
	goal_session.acknowledge_result()
	var completed: Dictionary = goal_session.snapshot()
	var repeated_report: Dictionary = goal_session.select_action("report_practice", "shu-goal-repeat")
	check(not bool(repeated_report.get("ok", false)) and goal_session.snapshot() == completed, "the completed shu report cannot be claimed twice")
	check(bool(goal_session.select_action("rest_practice", "shu-after-goal-rest").get("ok", false)), "sandbox actions remain available after reporting the goal")


func _check_stream_actions_and_dialogue() -> void:
	var session: Variant = _new_session(stream_pack)
	var travel: Dictionary = session.select_action("walk_to_river", "stream-walk")
	check(bool(travel.get("ok", false)) and session.state.scene == "riverbank", "stream_study uses the same action flow to travel between its scenes")
	check(travel.get("delta", {}).get("slots", -1) == 1 and session.state.slot == 1, "stream travel uses its authored one-slot duration")
	session.acknowledge_result()
	var reading: Dictionary = session.select_action("read_by_river", "stream-reading")
	check(bool(reading.get("ok", false)), "stream reading settles from its own pack")
	check(reading.get("delta", {}).get("stats", {}).get("stamina", 0) == -15 and reading.get("delta", {}).get("stats", {}).get("insight", 0) == 8, "stream reading receipt reports authored -15/+8 changes")
	check(session.state.stats.stamina == 65 and session.state.stats.insight == 8 and session.state.slot == 2, "stream reading updates resources and its four-slot clock")
	session.acknowledge_result()

	var rest_session: Variant = _new_session(stream_pack)
	var rest_fixture: Dictionary = rest_session.snapshot()
	rest_fixture["stats"]["stamina"] = 70
	check(bool(rest_session.restore(rest_fixture).get("ok", false)), "valid stream rest-cap fixture restores")
	var rest: Dictionary = rest_session.select_action("pause_by_stream", "stream-rest-cap")
	check(bool(rest.get("ok", false)) and rest_session.state.stats.stamina == 80, "stream rest clamps stamina to the pack maximum")
	check(rest.get("delta", {}).get("stats", {}).get("stamina", 0) == 10, "stream rest receipt reports the actual capped ten-point recovery")

	var cancel_session: Variant = _new_session(stream_pack)
	var talk: Dictionary = cancel_session.select_action("talk_to_keeper", "stream-talk-cancel")
	check(bool(talk.get("ok", false)) and cancel_session.state.stats.stamina == 77 and cancel_session.state.slot == 1, "stream conversation entry commits its authored cost and time")
	cancel_session.continue_event()
	var before_cancel: Dictionary = cancel_session.snapshot()
	cancel_session.cancel_event()
	check(cancel_session.state.phase == "ready" and cancel_session.state.stats == before_cancel.stats and cancel_session.state.slot == before_cancel.slot, "cancelling a stream event preserves its already committed entry cost")

	var study: Variant = _new_session(stream_pack)
	study.select_action("talk_to_keeper", "stream-talk-choice")
	study.continue_event()
	var study_choice: Dictionary = study.event_view()
	check(study_choice.get("type", "") == "choice" and study_choice.get("options", []).size() == 2, "stream dialogue exposes its data-authored choice")
	var accepted: Dictionary = study.choose("keep_tip", "stream-tip-choice")
	check(bool(accepted.get("ok", false)) and study.state.flags.study_tip_claimed and study.state.flags.study_hint, "accepting the stream tip sets its claimed and pending flags")
	var choice_state: Dictionary = study.snapshot()
	var stale: Dictionary = study.choose("keep_tip", "stream-tip-choice")
	check(bool(stale.get("duplicate", false)) and study.snapshot() == choice_state, "duplicate stream choice replay does not move the event twice")
	study.continue_event()
	study.continue_event()
	study.acknowledge_result()
	var river: Dictionary = study.select_action("walk_to_river", "stream-tip-walk")
	check(bool(river.get("ok", false)), "accepted study tip can continue into the reading scene")
	study.acknowledge_result()
	var hinted_read: Dictionary = study.select_action("read_by_river", "stream-hinted-reading")
	check(bool(hinted_read.get("ok", false)) and hinted_read.get("delta", {}).get("stats", {}).get("insight", 0) == 12, "the next stream reading consumes its one-use four-point tip")
	check(not study.state.flags.study_hint and study.state.stats.insight == 12, "the stream hint is consumed with the actual reading result")
	study.acknowledge_result()
	var ordinary_read: Dictionary = study.select_action("read_by_river", "stream-ordinary-reading")
	check(bool(ordinary_read.get("ok", false)) and ordinary_read.get("delta", {}).get("stats", {}).get("insight", 0) == 8, "later stream reading returns to its authored base gain")


func _check_stream_goal() -> void:
	var session: Variant = _new_session(stream_pack)
	var fixture: Dictionary = session.snapshot()
	fixture["stats"]["insight"] = 30
	check(bool(session.restore(fixture).get("ok", false)), "valid stream goal boundary fixture restores")
	var submission: Dictionary = session.select_action("submit_reading_note", "stream-goal-submit")
	check(bool(submission.get("ok", false)) and session.state.phase == "event", "qualified stream goal opens its authored submission event")
	session.continue_event()
	session.continue_event()
	check(session.state.phase == "result" and session.state.flags.study_goal_complete, "finishing the stream report returns to results and marks the goal")
	session.acknowledge_result()
	var completed: Dictionary = session.snapshot()
	var repeated: Dictionary = session.select_action("submit_reading_note", "stream-goal-repeat")
	check(not bool(repeated.get("ok", false)) and session.snapshot() == completed, "the stream goal report is once-only")
	check(bool(session.select_action("pause_by_stream", "stream-after-goal-rest").get("ok", false)), "stream sandbox actions remain available after goal completion")


func _check_stale_continue() -> void:
	var fixture: Dictionary = shu_pack.duplicate(true)
	var nodes: Dictionary = fixture.events.mentor_tip.nodes
	nodes.opening.next = "extra_line"
	nodes["extra_line"] = {"type": "say", "speaker": "mentor_zhixian", "text": "第二句必须单独继续。", "next": "choice"}
	check(loader.validate(fixture).is_empty(), "the stale-continue fixture is a valid two-line event")
	var session: Variant = _new_session(fixture)
	session.select_action("talk_mentor", "continue-open")
	var before: Dictionary = session.snapshot()
	check(bool(session.continue_event(str(before.run_id), int(before.revision)).get("ok", false)), "the current line's captured continue request advances once")
	check(session.state.event.node == "extra_line", "captured continue shows the second line")
	var after: Dictionary = session.snapshot()
	check(not bool(session.continue_event(str(before.run_id), int(before.revision)).get("ok", false)), "a delayed duplicate continue cannot skip the next line")
	check(session.snapshot() == after, "stale continue leaves all progress and receipts unchanged")
	session.start_new()
	session.select_action("talk_mentor", "continue-new-run")
	var reset_state: Dictionary = session.snapshot()
	check(not bool(session.continue_event(str(before.run_id), int(before.revision)).get("ok", false)), "a previous run's continue cannot advance a new event at the same node")
	check(session.snapshot() == reset_state, "reset invalidates the old line callback atomically")


func _check_restore_rejection_is_atomic() -> void:
	var session: Variant = _new_session(shu_pack)
	var before: Dictionary = session.snapshot()
	var malformed: Dictionary = before.duplicate(true)
	malformed["stats"]["energy"] = 101
	check(not bool(session.restore(malformed).get("ok", false)), "restore rejects a stat outside the authored bounds")
	check(session.snapshot() == before, "out-of-range snapshot rejection preserves every live field")

	malformed = before.duplicate(true)
	malformed["unexpected_runtime_directive"] = true
	check(not bool(session.restore(malformed).get("ok", false)), "restore rejects unknown snapshot fields")
	check(session.snapshot() == before, "unknown-field rejection is atomic")

	malformed = before.duplicate(true)
	malformed["phase"] = "event"
	malformed["event"] = {"id": "mentor_tip", "node": "choice"}
	check(not bool(session.restore(malformed).get("ok", false)), "restore rejects an unfinished dialogue snapshot")
	check(session.snapshot() == before, "unfinished-dialogue rejection leaves the current state untouched")

	malformed = before.duplicate(true)
	malformed["stats"]["energy"] = 20
	malformed["last_result"] = {"ok": true}
	check(not bool(session.restore(malformed).get("ok", false)), "restore rejects inconsistent last-result data")
	check(session.snapshot() == before, "inconsistent-result rejection is atomic")


func _check_ready_and_result_save_roundtrips() -> void:
	var ready_store: Variant = _new_store(test_base.path_join("ready_roundtrip"))
	var ready_session: Variant = _new_session(shu_pack)
	var ready_fixture: Dictionary = ready_session.snapshot()
	ready_fixture["scene"] = "back_mountain"
	ready_fixture["stats"]["cultivation"] = 7
	check(bool(ready_session.restore(ready_fixture).get("ok", false)), "valid ready-save fixture restores")
	var ready_saved: Dictionary = ready_session.snapshot()
	check(bool(ready_store.save_session(ready_session).get("ok", false)), "SaveStore saves a ready-phase state")
	var save_stream: Variant = _new_session(stream_pack)
	var stream_saved: Dictionary = save_stream.snapshot()
	check(bool(ready_store.save_session(save_stream).get("ok", false)), "the same SaveStore keeps an independent save for the second pack")
	check(ready_store.has_save(shu_pack) and ready_store.has_save(stream_pack), "both packs have separately discoverable saves")
	save_stream.select_action("walk_to_river", "stream-ready-roundtrip-walk")
	save_stream.acknowledge_result()
	check(bool(ready_store.load_session(save_stream).get("ok", false)), "the second pack also loads through the shared SaveStore")
	check(save_stream.snapshot() == stream_saved, "stream load restores its own exact state without shu resource IDs")
	ready_session.select_action("train_mountain", "ready-roundtrip-train")
	ready_session.acknowledge_result()
	ready_session.select_action("rest_practice", "ready-roundtrip-rest")
	check(bool(ready_store.load_session(ready_session).get("ok", false)), "loading restores a ready-phase checkpoint")
	check(ready_session.snapshot() == ready_saved, "ready load restores exact resources, time, progress, receipt and run metadata")

	var result_store: Variant = _new_store(test_base.path_join("result_roundtrip"))
	var result_session: Variant = _new_session(shu_pack)
	var result_fixture: Dictionary = result_session.snapshot()
	result_fixture["scene"] = "back_mountain"
	check(bool(result_session.restore(result_fixture).get("ok", false)), "valid result-save fixture restores")
	var train: Dictionary = result_session.select_action("train_mountain", "result-roundtrip-train")
	check(bool(train.get("ok", false)) and result_session.can_save(), "completed action result is an allowed save boundary")
	var result_saved: Dictionary = result_session.snapshot()
	check(bool(result_store.save_session(result_session).get("ok", false)), "SaveStore saves a result-phase state")
	result_session.acknowledge_result()
	result_session.select_action("rest_practice", "result-roundtrip-rest")
	check(bool(result_store.load_session(result_session).get("ok", false)), "loading restores a result-phase checkpoint")
	check(result_session.snapshot() == result_saved, "result load restores exact resources, time, progress and receipts")
	var before_replay: Dictionary = result_session.snapshot()
	var replay: Dictionary = result_session.select_action("train_mountain", "result-roundtrip-train")
	check(bool(replay.get("duplicate", false)) and result_session.snapshot() == before_replay, "a receipt remains replayable after save and restore")
	var prior_run_id: String = str(result_session.state.run_id)
	check(bool(result_session.start_new().get("ok", false)), "a saved session can start a new run")
	check(result_session.state.run_id != prior_run_id and result_session.state.sequence == 0, "new run replaces the run ID and clears its operation sequence")
	check(result_session.state.stats.energy == 100 and result_session.state.stats.cultivation == 0 and result_session.state.scene == "tingyu_corridor", "new run returns to pack-defined initial values and location")


func _check_cross_pack_version_and_checksum_rejection() -> void:
	var store: Variant = _new_store(test_base.path_join("identity_checks"))
	var shu_session: Variant = _new_session(shu_pack)
	check(bool(store.save_session(shu_session).get("ok", false)), "identity fixture creates a valid shu checkpoint")
	var source_path: String = _checkpoint_path(store.base_dir, "shu_entry", 0)
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	check(not original_bytes.is_empty(), "identity fixture has readable checkpoint bytes")

	var study_dir: String = store.base_dir.path_join("stream_study")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(study_dir))
	var cross_path: String = _checkpoint_path(store.base_dir, "stream_study", 0)
	check(_write_bytes(cross_path, original_bytes), "cross-pack mismatch fixture is copied into the other pack's slot")
	var study_session: Variant = _new_session(stream_pack)
	var before_study: Dictionary = study_session.snapshot()
	var cross_result: Dictionary = store.load_session(study_session)
	check(not bool(cross_result.get("ok", false)), "a different pack ID cannot load the copied checkpoint")
	check(study_session.snapshot() == before_study, "cross-pack rejection does not partially restore state")

	var changed_version: Dictionary = shu_pack.duplicate(true)
	changed_version["version"] = "9.9.9"
	var version_session: Variant = _new_session(changed_version)
	var before_version: Dictionary = version_session.snapshot()
	var version_result: Dictionary = store.load_session(version_session)
	check(not bool(version_result.get("ok", false)), "a checkpoint from another content version is rejected")
	check(version_session.snapshot() == before_version, "content-version rejection preserves the configured session")

	var changed_fingerprint: Dictionary = shu_pack.duplicate(true)
	changed_fingerprint["_fingerprint"] = "changed-fingerprint"
	var fingerprint_session: Variant = _new_session(changed_fingerprint)
	var before_fingerprint: Dictionary = fingerprint_session.snapshot()
	check(not bool(store.load_session(fingerprint_session).get("ok", false)), "a checkpoint from different content bytes is rejected")
	check(fingerprint_session.snapshot() == before_fingerprint, "content-fingerprint rejection is atomic")

	var parsed: JSON = JSON.new()
	check(parsed.parse(original_bytes.get_string_from_utf8()) == OK and parsed.data is Dictionary, "checksum fixture parses its envelope")
	if parsed.data is Dictionary:
		var envelope: Dictionary = parsed.data
		envelope["checksum"] = "0000000000000000000000000000000000000000000000000000000000000000"
		check(_write_text(source_path, JSON.stringify(envelope)), "checksum fixture changes only the stored checksum")
	var before_checksum: Dictionary = shu_session.snapshot()
	var checksum_result: Dictionary = store.load_session(shu_session)
	check(not bool(checksum_result.get("ok", false)), "checksum mismatch is rejected instead of restoring state")
	check(shu_session.snapshot() == before_checksum, "checksum rejection leaves live state unchanged")


func _check_corrupt_latest_fallback() -> void:
	var store: Variant = _new_store(test_base.path_join("corrupt_fallback"))
	var session: Variant = _new_session(shu_pack)
	var fixture: Dictionary = session.snapshot()
	fixture["scene"] = "back_mountain"
	check(bool(session.restore(fixture).get("ok", false)), "valid fallback fixture restores")
	var older_state: Dictionary = session.snapshot()
	check(bool(store.save_session(session).get("ok", false)), "first fallback checkpoint saves")
	session.select_action("train_mountain", "fallback-newer-train")
	var newer_state: Dictionary = session.snapshot()
	check(bool(store.save_session(session).get("ok", false)), "second fallback checkpoint saves as the newer generation")
	var newest: Dictionary = _newest_checkpoint(store.base_dir, "shu_entry")
	check(not newest.is_empty() and int(newest.get("generation", 0)) == 2, "fallback fixture locates the latest generation")
	if newest.is_empty():
		return
	check(_write_text(str(newest.path), "{corrupt"), "latest checkpoint is corrupted for recovery testing")
	session.acknowledge_result()
	var recovered: Dictionary = store.load_session(session)
	check(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)), "load falls back to the older valid checkpoint with an explicit recovery notice")
	check(session.snapshot() == older_state and session.snapshot() != newer_state, "fallback restores the older exact state, not the damaged latest state")


func _check_injected_write_failure_preserves_previous_save() -> void:
	var store: Variant = _new_store(test_base.path_join("write_failure"))
	var session: Variant = _new_session(shu_pack)
	var fixture: Dictionary = session.snapshot()
	fixture["scene"] = "back_mountain"
	check(bool(session.restore(fixture).get("ok", false)), "valid write-failure fixture restores")
	check(bool(store.save_session(session).get("ok", false)), "baseline checkpoint saves before injecting a path failure")
	var valid_path: String = _checkpoint_path(store.base_dir, "shu_entry", 0)
	var valid_bytes: PackedByteArray = FileAccess.get_file_as_bytes(valid_path)
	session.select_action("train_mountain", "failed-write-train")
	var pending_directory: String = _checkpoint_path(store.base_dir, "shu_entry", 1) + ".pending"
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pending_directory))
	check(mkdir_error == OK, "injected path failure blocks the older slot's pending-file path")
	var failed_save: Dictionary = store.save_session(session)
	check(not bool(failed_save.get("ok", false)), "SaveStore reports the injected pending-file write failure")
	check(FileAccess.get_file_as_bytes(valid_path) == valid_bytes, "failed save leaves the previous valid checkpoint bytes unchanged")
	var after_failed_save: Dictionary = session.snapshot()
	var reloaded: Dictionary = store.load_session(session)
	check(bool(reloaded.get("ok", false)) and int(reloaded.get("generation", 0)) == 1, "the previous checkpoint remains loadable after write failure")
	check(session.snapshot() != after_failed_save, "loading after failed write restores the last valid state")


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(data)
	check(bool(configured.get("ok", false)), "EngineSession configures pack %s" % str(data.get("id", "?")))
	return session


func _new_store(folder: String) -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = folder
	return store


func _checkpoint_path(base: String, pack_id: String, index: int) -> String:
	return base.path_join(pack_id).path_join("checkpoint_%d.json" % index)


func _newest_checkpoint(base: String, pack_id: String) -> Dictionary:
	var newest: Dictionary = {}
	for index in range(2):
		var path: String = _checkpoint_path(base, pack_id, index)
		var parsed: JSON = JSON.new()
		if not FileAccess.file_exists(path):
			continue
		var raw: String = FileAccess.get_file_as_string(path)
		if parsed.parse(raw) != OK or not parsed.data is Dictionary:
			continue
		var value: Dictionary = parsed.data
		var generation: int = int(value.get("generation", 0))
		if generation > int(newest.get("generation", 0)):
			newest = {"path": path, "generation": generation}
	return newest


func _write_text(path: String, value: String) -> bool:
	var parent: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	var written: bool = file.get_error() == OK
	file.close()
	return written


func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var parent: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.flush()
	var written: bool = file.get_error() == OK and file.get_position() == value.size()
	file.close()
	return written


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


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	failure_messages.append(message)
	push_error("FAIL: " + message)


func _finish() -> void:
	var report: Dictionary = {
		"test": "cultivation_engine_test",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"result": ("PASS" if failures == 0 else "FAIL")
	}
	var report_parent: String = REPORT_PATH.get_base_dir()
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_parent))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write test report: " + REPORT_PATH + " (" + str(mkdir_error) + ")")
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Test report write failed: " + REPORT_PATH)
		file.close()
	print("CULTIVATION_ENGINE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)
