extends SceneTree

const LoaderScript := preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript := preload("res://addons/cultivation_mode/session.gd")
const StoreScript := preload("res://addons/cultivation_mode/save_store.gd")
const MENTOR_MANIFEST := "res://games/shu_mentor_loop/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"
const SHU_MANIFEST := "res://games/shu_entry/game.json"

const INTRO_VOICE_IDS := [
	"opening", "sit", "hurry", "advice", "choice", "lesson_taken", "lesson_reply", "lesson_skipped", "skip_reply"
]
const REPORT_VOICE_IDS := ["report_question", "report_calm", "report_calm_reply", "report_try", "report_try_reply"]
const SWORD_CLIPS := {
	"pine_wind": "songfeng",
	"listening_rain": "chuanyun",
	"returning_tide": "huilan",
	"rising_peak": "tiaoyue",
	"swift_swallow": "xieying",
}

var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var loader: Variant
var mentor_pack: Dictionary = {}
var stream_pack: Dictionary = {}
var test_base: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	loader = LoaderScript.new()
	var mentor_result: Dictionary = loader.load_pack(MENTOR_MANIFEST)
	var stream_result: Dictionary = loader.load_pack(STREAM_MANIFEST)
	var shu_result: Dictionary = loader.load_pack(SHU_MANIFEST)
	check(bool(mentor_result.get("ok", false)), "the authored mentor-loop pack loads through PackLoader")
	check(bool(stream_result.get("ok", false)), "the existing unvoiced Stream pack still loads through PackLoader")
	check(bool(shu_result.get("ok", false)), "the existing Shu pack with quest reservations still loads through PackLoader")
	if not bool(mentor_result.get("ok", false)) or not bool(stream_result.get("ok", false)) or not bool(shu_result.get("ok", false)):
		_finish()
		return
	mentor_pack = mentor_result.get("pack", {})
	stream_pack = stream_result.get("pack", {})
	test_base = _allocate_store_base()
	check(not test_base.is_empty(), "a fresh isolated save directory is available for mentor-loop checkpoints")
	if test_base.is_empty():
		_finish()
		return

	_check_voice_registry_and_loader_guards(shu_result.get("pack", {}))
	_check_cancel_and_accepted_lesson_report_restore()
	_check_skipped_lesson_report_branch()
	_check_all_sword_preflights()
	_check_legacy_unvoiced_stream()
	_finish()


func _check_voice_registry_and_loader_guards(shu_pack: Dictionary) -> void:
	var voices: Dictionary = mentor_pack.get("voices", {})
	var expected_ids: Array[String] = []
	for voice_id: String in INTRO_VOICE_IDS + REPORT_VOICE_IDS:
		expected_ids.append(voice_id)
	var actual_ids: Array[String] = []
	for voice_key: Variant in voices.keys():
		actual_ids.append(str(voice_key))
	expected_ids.sort()
	actual_ids.sort()
	check(actual_ids == expected_ids, "the local voice catalog contains the nine lesson and five report clip IDs")
	check(loader.validate(mentor_pack).is_empty(), "the complete mentor-loop pack passes loader validation")
	var intro_nodes: Dictionary = mentor_pack.get("events", {}).get("mentor_tip", {}).get("nodes", {})
	for node_id: String in INTRO_VOICE_IDS:
		var node: Dictionary = intro_nodes.get(node_id, {})
		check(str(node.get("voice", "")) == node_id and voices.has(node_id), "mentor node %s binds its matching local voice clip" % node_id)
	var report_nodes: Dictionary = mentor_pack.get("events", {}).get("mentor_practice_report", {}).get("nodes", {})
	for node_id: String in REPORT_VOICE_IDS:
		var node: Dictionary = report_nodes.get(node_id, {})
		check(str(node.get("voice", "")) == node_id and voices.has(node_id), "report node %s binds its matching local voice clip" % node_id)
	check(not voices.has("end") and not voices.has("laterend"), "event endings remain unvoiced")

	var unsafe_path: Dictionary = mentor_pack.duplicate(true)
	unsafe_path["voices"]["opening"]["file"] = "res://assets/audio/mentor_pause/../outside.wav"
	_expect_loader_rejection(unsafe_path, "the loader rejects an unsafe local voice path")
	for path: String in ["res://assets/audio/./mentor_pause/opening.wav", "res://assets/audio//mentor_pause/opening.wav", "res://assets/audio/mentor_pause/opening.WAV"]:
		var noncanonical_voice: Dictionary = mentor_pack.duplicate(true)
		noncanonical_voice["voices"]["opening"]["file"] = path
		_expect_loader_rejection(noncanonical_voice, "the loader and voice player agree on canonical WAV paths: " + path)
	var speaker_mismatch: Dictionary = mentor_pack.duplicate(true)
	speaker_mismatch["voices"]["opening"]["speaker"] = "mentor_zhixian"
	_expect_loader_rejection(speaker_mismatch, "the loader rejects a voice clip with a mismatched speaker")
	var text_mismatch: Dictionary = mentor_pack.duplicate(true)
	text_mismatch["voices"]["opening"]["text"] = "Different spoken words."
	_expect_loader_rejection(text_mismatch, "the loader rejects a voice clip with text different from its line")
	var end_voice: Dictionary = mentor_pack.duplicate(true)
	end_voice["events"]["mentor_tip"]["nodes"]["end"]["voice"] = "opening"
	_expect_loader_rejection(end_voice, "the loader rejects a voice binding on an end node")
	var reserved_end_flag: Dictionary = shu_pack.duplicate(true)
	reserved_end_flag["events"]["mentor_tip"]["nodes"]["end"]["set_flags"] = {"tea_active": true, "tea_cup_first_seen": true}
	_expect_loader_rejection(reserved_end_flag, "the loader rejects end-node writes to quest and inspection flags")

	var stream_voices: Variant = stream_pack.get("voices", {})
	check(stream_voices is Dictionary and (stream_voices as Dictionary).is_empty(), "the old Stream pack remains valid without an optional voice registry")


func _expect_loader_rejection(candidate: Dictionary, message: String) -> void:
	var errors: Array[String] = loader.validate(candidate)
	check(not errors.is_empty(), message)


func _check_cancel_and_accepted_lesson_report_restore() -> void:
	var cancelled: Variant = _new_session(mentor_pack)
	var initial: Dictionary = cancelled.snapshot()
	var opened: Dictionary = cancelled.select_action("talk_mentor", "mentor-cancel-opening")
	check(bool(opened.get("ok", false)) and cancelled.event_view().get("node_id", "") == "opening", "the mentor dialogue opens in its first voiced line")
	check(cancelled.snapshot().get("stats", {}) == initial.get("stats", {}) and cancelled.snapshot().get("slot", -1) == initial.get("slot", -2), "opening the mentor dialogue is free and advances no time")
	var cancel_opening: Dictionary = cancelled.cancel_event()
	check(bool(cancel_opening.get("ok", false)) and not bool(cancelled.snapshot().get("flags", {}).get("mentor_lesson_heard", true)), "cancelling the opening dialogue leaves the completion flag unset")
	var before_reopen: Dictionary = cancelled.snapshot()
	var reopened: Dictionary = cancelled.select_action("talk_mentor", "mentor-cancel-reopen")
	check(bool(reopened.get("ok", false)) and cancelled.snapshot().get("event", {}).get("node", "") == "opening", "the opening can be resumed after cancellation")
	_advance_intro_to_choice(cancelled)
	var before_partial_cancel: Dictionary = cancelled.snapshot()
	check(bool(cancelled.cancel_event().get("ok", false)) and cancelled.snapshot().get("phase", "") == "ready", "the partial mentor event can be cancelled from its choice")
	check(not bool(cancelled.snapshot().get("flags", {}).get("mentor_lesson_heard", true)) and cancelled.snapshot().get("stats", {}) == before_partial_cancel.get("stats", {}) and cancelled.snapshot().get("slot", -1) == before_partial_cancel.get("slot", -2), "cancelling a partial event never commits its ending or changes resources/time")
	check(cancelled.snapshot().get("flags", {}).get("mentor_lesson_accepted", false) == before_reopen.get("flags", {}).get("mentor_lesson_accepted", false), "cancelling preserves the unchanged lesson-acceptance flag")

	var session: Variant = _new_session(mentor_pack)
	var before_locked: Dictionary = session.snapshot()
	var travel_locked: Dictionary = session.select_action("go_to_mountain", "mentor-locked-travel")
	check(not bool(travel_locked.get("ok", false)) and session.snapshot() == before_locked, "mountain travel remains locked until the mentor event ending is continued")
	var report_locked: Dictionary = session.select_action("report_practice", "mentor-locked-report")
	check(not bool(report_locked.get("ok", false)) and session.snapshot() == before_locked, "the practice report remains locked before a sword action")
	var opening: Dictionary = session.select_action("talk_mentor", "mentor-accepted-open")
	check(bool(opening.get("ok", false)) and session.snapshot().get("flags", {}).get("mentor_lesson_heard", true) == false, "a fresh mentor event starts with its completion flag false")
	var before_duplicate_open: Dictionary = session.snapshot()
	var duplicate_open: Dictionary = session.select_action("talk_mentor", "mentor-accepted-open")
	check(bool(duplicate_open.get("duplicate", false)), "replaying the opening action ID returns its original receipt")
	check(session.snapshot() == before_duplicate_open and int(before_duplicate_open.get("sequence", -1)) == 1, "opening replay does not re-settle the dialogue action")
	_advance_intro_to_choice(session)
	var choice_state: Dictionary = session.snapshot()
	var choice_revision: int = int(choice_state.get("revision", -1))
	var choice_run: String = str(choice_state.get("run_id", ""))
	var choice_view: Dictionary = session.event_view()
	check(choice_view.get("node_id", "") == "choice" and choice_view.get("voice", "") == "choice", "the lesson choice displays its authored question and matching voice ID")
	var take_result: Dictionary = session.choose("take_lesson", "mentor-lesson-choice")
	check(bool(take_result.get("ok", false)) and take_result.get("action_id", "") == "claim_mentor_lesson", "the accepted branch settles through its selected lesson action")
	var lesson_state: Dictionary = session.snapshot()
	check(int(lesson_state.get("stats", {}).get("energy", -1)) == 92 and int(lesson_state.get("stats", {}).get("understanding", -1)) == 1 and int(lesson_state.get("slot", -1)) == 1, "accepting the lesson applies the actual eight-energy, one-understanding, one-slot cost")
	check(bool(lesson_state.get("flags", {}).get("mentor_lesson_accepted", false)) and bool(lesson_state.get("flags", {}).get("breathing_hint", false)), "accepting the lesson arms the one-use breathing hint")
	var duplicate_choice: Dictionary = session.choose("take_lesson", "mentor-lesson-choice")
	check(bool(duplicate_choice.get("duplicate", false)) and session.snapshot() == lesson_state, "replaying the lesson choice cannot charge or grant twice")
	var mismatched_choice: Dictionary = session.choose("return_to_practice", "mentor-lesson-choice")
	check(not bool(mismatched_choice.get("ok", false)) and mismatched_choice.get("code", "") == "operation_mismatch" and session.snapshot() == lesson_state, "an operation ID cannot be replayed for the other choice")
	check(not bool(session.continue_event(choice_run, choice_revision).get("ok", false)) and session.snapshot() == lesson_state, "a stale continue callback cannot skip the paid lesson line")
	_advance_to_end(session, ["lesson_taken", "lesson_reply"])
	var before_lesson_end: Dictionary = session.snapshot()
	check(not bool(before_lesson_end.get("flags", {}).get("mentor_lesson_heard", true)), "the paid lesson still does not commit heard progress before its end node")
	var lesson_end: Dictionary = session.continue_event(str(before_lesson_end.get("run_id", "")), int(before_lesson_end.get("revision", -1)))
	check(bool(lesson_end.get("ok", false)) and bool(session.snapshot().get("flags", {}).get("mentor_lesson_heard", false)), "continuing the lesson end commits its heard flag")
	var ended_lesson: Dictionary = session.snapshot()
	check(not bool(session.continue_event(str(before_lesson_end.get("run_id", "")), int(before_lesson_end.get("revision", -1))).get("ok", false)) and session.snapshot() == ended_lesson, "the ended lesson rejects stale duplicate continuation atomically")
	check(not bool(session.continue_event().get("ok", false)) and session.snapshot() == ended_lesson, "repeated end continuation cannot recommit the lesson")
	var store: Variant = _new_store("mentor_lesson")
	check(bool(store.save_session(session).get("ok", false)), "a completed lesson result is a save boundary")
	check(bool(session.acknowledge_result().get("ok", false)), "the lesson result can be acknowledged before travel")
	check(bool(session.select_action("go_to_mountain", "mentor-enter-mountain").get("ok", false)), "hearing the lesson unlocks mountain travel")
	check(bool(session.acknowledge_result().get("ok", false)) and session.snapshot().get("scene", "") == "back_mountain", "travel reaches the mountain at the unchanged slot")
	var sword_operation: String = "mentor-loop-first-sword"
	var before_sword: Dictionary = session.snapshot()
	var sword_result: Dictionary = session.select_action("pine_wind", sword_operation)
	check(bool(sword_result.get("ok", false)) and session.snapshot().get("phase", "") == "performing", "the selected real sword action enters its preflighted performing phase")
	check(not bool(session.can_save()) and not bool(_new_store("busy_guard").save_session(session).get("ok", false)), "the performing sword transaction cannot be saved")
	var pending: Dictionary = session.pending_presentation()
	check(pending.get("receipt", {}) == sword_result and pending.get("assets", {}).get("clip_id", "") == "songfeng", "the pending presentation carries the real action receipt and content-selected clip")
	var before_duplicate_sword: Dictionary = session.snapshot()
	var leave_while_performing: Dictionary = session.select_action("return_to_corridor", "mentor-leave-during-motion")
	check(not bool(leave_while_performing.get("ok", false)) and session.snapshot() == before_duplicate_sword, "the player cannot leave the mountain before the sword presentation finishes")
	var duplicate_sword: Dictionary = session.select_action("pine_wind", sword_operation)
	check(bool(duplicate_sword.get("duplicate", false)) and session.snapshot() == before_duplicate_sword, "replaying the performing sword operation does not settle a second action")
	var finish_sword: Dictionary = session.finish_presentation(str(pending.get("run_id", "")), str(pending.get("operation_id", "")))
	check(bool(finish_sword.get("ok", false)) and session.snapshot().get("phase", "") == "result", "presentation completes with the exact pending run and operation IDs")
	var sword_state: Dictionary = session.snapshot()
	var sword_delta: Dictionary = sword_state.get("last_result", {}).get("delta", {})
	check(int(sword_state.get("stats", {}).get("energy", -1)) == 70 and int(sword_state.get("stats", {}).get("sword", -1)) == 10 and int(sword_state.get("stats", {}).get("cultivation", -1)) == 6, "the first sword spends 22 energy and grants sword 10 plus the one-use cultivation 6")
	check(int(sword_delta.get("stats", {}).get("cultivation", -1)) == 6 and int(sword_delta.get("slots", -1)) == 1 and not bool(sword_state.get("flags", {}).get("breathing_hint", true)), "the first sword receipt records and consumes the hint exactly once")
	check(bool(sword_state.get("flags", {}).get("mentor_practice_finished", false)) and int(sword_state.get("counts", {}).get("pine_wind", 0)) == 1, "the completed sword marks practice and counts one actual action")
	var duplicate_finished_sword: Dictionary = session.select_action("pine_wind", sword_operation)
	check(bool(duplicate_finished_sword.get("duplicate", false)) and session.snapshot() == sword_state, "replaying the saved motion ID after completion does not recharge or replay")
	check(bool(session.acknowledge_result().get("ok", false)), "the finished sword result can be acknowledged")
	check(bool(session.select_action("return_to_corridor", "mentor-return-to-corridor").get("ok", false)), "the player can return to the corridor after practice")
	check(bool(session.acknowledge_result().get("ok", false)) and session.snapshot().get("scene", "") == "tingyu_corridor", "the explicit return action settles before the report")
	var report_open: Dictionary = session.select_action("report_practice", "mentor-report-open-later")
	check(bool(report_open.get("ok", false)) and session.event_view().get("node_id", "") == "report_question", "completed practice unlocks the voiced report question")
	var report_options: Dictionary = _options_by_id(session.event_view())
	check(bool(report_options.get("with_lesson", {}).get("enabled", false)) and not bool(report_options.get("self_practice", {}).get("enabled", true)) and bool(report_options.get("later", {}).get("enabled", false)), "report choice availability follows whether the lesson was accepted")
	var wrong_report_before: Dictionary = session.snapshot()
	var wrong_report: Dictionary = session.choose("self_practice", "wrong-report-branch")
	check(not bool(wrong_report.get("ok", false)) and session.snapshot() == wrong_report_before, "the report rejects a branch whose lesson flag does not match")
	check(bool(session.choose("later", "mentor-report-later").get("ok", false)), "the report can be deferred without a progress action")
	check(session.event_view().get("node_id", "") == "laterend" and not bool(session.snapshot().get("flags", {}).get("mentor_reported", true)), "the deferred branch reaches its unvoiced end without marking report complete")
	check(bool(session.continue_event().get("ok", false)) and not bool(session.snapshot().get("flags", {}).get("mentor_reported", true)), "continuing the deferred ending leaves the report flag false")
	var deferred_state: Dictionary = session.snapshot()
	check(bool(session.acknowledge_result().get("ok", false)), "the deferred report result can be acknowledged")
	check(bool(session.select_action("report_practice", "mentor-report-cancel").get("ok", false)), "an unfinished report can be reopened")
	var report_cancel_before: Dictionary = session.snapshot()
	check(bool(session.cancel_event().get("ok", false)) and not bool(session.snapshot().get("flags", {}).get("mentor_reported", true)), "cancelling a reopened report does not mark it complete")
	check(session.snapshot().get("stats", {}) == report_cancel_before.get("stats", {}) and session.snapshot().get("slot", -1) == report_cancel_before.get("slot", -2), "cancelling the report preserves resources and time")
	check(bool(session.select_action("report_practice", "mentor-report-open-final").get("ok", false)), "the player can reopen the report after cancelling")
	check(bool(session.choose("with_lesson", "mentor-report-accepted-branch").get("ok", false)), "the accepted-lesson report branch is selectable")
	_advance_to_end(session, ["report_calm", "report_calm_reply"])
	var before_report_end: Dictionary = session.snapshot()
	check(not bool(before_report_end.get("flags", {}).get("mentor_reported", true)), "report completion remains false until its ending is continued")
	check(bool(session.continue_event().get("ok", false)) and bool(session.snapshot().get("flags", {}).get("mentor_reported", false)), "continuing the voiced report end completes the report")
	var saved_state: Dictionary = session.snapshot()
	check(bool(store.save_session(session).get("ok", false)), "the final report result checkpoint saves exact gameplay state")
	for rest_index in range(4):
		check(bool(session.acknowledge_result().get("ok", false)), "report result %d returns to the ready phase" % rest_index)
		var rest: Dictionary = session.select_action("rest_practice", "mentor-rest-cross-day-%d" % rest_index)
		check(bool(rest.get("ok", false)), "rest %d settles through the ordinary action API" % (rest_index + 1))
	check(session.snapshot().get("day", -1) == 2 and session.snapshot().get("slot", -1) == 0, "four ordinary rests cross the six-slot day boundary naturally")
	var day_two_state: Dictionary = session.snapshot()
	check(bool(store.load_session(session).get("ok", false)) and session.snapshot() == saved_state, "loading restores the exact pre-rest result checkpoint")
	check(session.snapshot().get("scene", "") == saved_state.get("scene", "") and session.snapshot().get("day", -1) == saved_state.get("day", -2) and session.snapshot().get("slot", -1) == saved_state.get("slot", -2) and session.snapshot().get("stats", {}) == saved_state.get("stats", {}) and session.snapshot().get("flags", {}) == saved_state.get("flags", {}) and session.snapshot().get("counts", {}) == saved_state.get("counts", {}) and session.snapshot().get("receipts", {}) == saved_state.get("receipts", {}), "checkpoint preserves scene, clock, stats, flags, counts and receipts")
	check(day_two_state.get("revision", -1) > saved_state.get("revision", -2), "the test really advanced the run after the saved checkpoint")
	var replay_after_restore: Dictionary = session.select_action("pine_wind", sword_operation)
	check(bool(replay_after_restore.get("duplicate", false)) and session.snapshot() == saved_state and session.pending_presentation().is_empty(), "a restored motion receipt cannot recharge, replay animation or create a pending presentation")
	check(deferred_state.get("phase", "") == "result", "the earlier deferred ending remained a normal result boundary")


func _check_skipped_lesson_report_branch() -> void:
	var session: Variant = _new_session(mentor_pack)
	session.select_action("talk_mentor", "mentor-skip-open")
	_advance_intro_to_choice(session)
	check(bool(session.choose("return_to_practice", "mentor-skip-choice").get("ok", false)), "the player can skip the paid lesson")
	check(not bool(session.snapshot().get("flags", {}).get("mentor_lesson_accepted", true)) and not bool(session.snapshot().get("flags", {}).get("mentor_lesson_heard", true)), "skipping leaves lesson acceptance false until the intro end")
	_advance_to_end(session, ["lesson_skipped", "skip_reply"])
	check(bool(session.continue_event().get("ok", false)) and bool(session.snapshot().get("flags", {}).get("mentor_lesson_heard", false)), "continuing the skipped intro ending records heard progress")
	check(not bool(session.snapshot().get("flags", {}).get("mentor_lesson_accepted", true)) and int(session.snapshot().get("stats", {}).get("energy", -1)) == 100 and int(session.snapshot().get("slot", -1)) == 0, "the skipped branch spends no lesson cost or time")
	session.acknowledge_result()
	session.select_action("go_to_mountain", "mentor-skip-to-mountain")
	session.acknowledge_result()
	var motion: Dictionary = session.select_action("swift_swallow", "mentor-skip-sword")
	var pending: Dictionary = session.pending_presentation()
	check(bool(motion.get("ok", false)) and pending.get("assets", {}).get("clip_id", "") == "xieying", "the skipped branch can still complete a real sword presentation")
	session.finish_presentation(str(pending.get("run_id", "")), str(pending.get("operation_id", "")))
	session.acknowledge_result()
	session.select_action("return_to_corridor", "mentor-skip-return")
	session.acknowledge_result()
	check(bool(session.select_action("report_practice", "mentor-skip-report").get("ok", false)), "the skipped-lesson run can report after practice")
	var options: Dictionary = _options_by_id(session.event_view())
	check(not bool(options.get("with_lesson", {}).get("enabled", true)) and bool(options.get("self_practice", {}).get("enabled", false)), "the report options switch to self-practice when the lesson was skipped")
	check(bool(session.choose("self_practice", "mentor-self-report").get("ok", false)), "the self-practice report branch is selectable")
	_advance_to_end(session, ["report_try", "report_try_reply"])
	check(not bool(session.snapshot().get("flags", {}).get("mentor_reported", true)), "self-practice report completion is deferred at its end node")
	check(bool(session.continue_event().get("ok", false)) and bool(session.snapshot().get("flags", {}).get("mentor_reported", false)), "continuing the self-practice ending completes the report")


func _check_all_sword_preflights() -> void:
	var session: Variant = _new_session(mentor_pack)
	session.select_action("talk_mentor", "mentor-five-preflight-open")
	_advance_intro_to_choice(session)
	session.choose("return_to_practice", "mentor-five-preflight-skip")
	_advance_to_end(session, ["lesson_skipped", "skip_reply"])
	session.continue_event()
	session.acknowledge_result()
	session.select_action("go_to_mountain", "mentor-five-preflight-travel")
	session.acknowledge_result()
	for action_id: String in SWORD_CLIPS:
		if session.snapshot().get("phase", "") != "ready":
			check(false, "%s preflight starts at a saveable ready boundary" % action_id)
			return
		if int(session.snapshot().get("stats", {}).get("energy", 0)) < 22:
			var refill: Dictionary = session.snapshot()
			var stats: Dictionary = refill.get("stats", {}).duplicate(true)
			stats["energy"] = 100
			refill["stats"] = stats
			check(bool(session.restore(refill).get("ok", false)), "a valid high-energy fixture enables the next motion preflight")
		var operation_id: String = "mentor-preflight-" + action_id
		var result: Dictionary = session.select_action(action_id, operation_id)
		check(bool(result.get("ok", false)) and session.snapshot().get("phase", "") == "performing", "%s passes real asset preflight and settles once" % action_id)
		if not bool(result.get("ok", false)):
			return
		var pending: Dictionary = session.pending_presentation()
		check(pending.get("assets", {}).get("clip_id", "") == str(SWORD_CLIPS[action_id]) and pending.get("receipt", {}) == result, "%s pending presentation selects the matching clip and actual receipt" % action_id)
		var finished: Dictionary = session.finish_presentation(str(pending.get("run_id", "")), str(pending.get("operation_id", "")))
		check(bool(finished.get("ok", false)) and session.snapshot().get("phase", "") == "result", "%s completes only through its pending run and operation identity" % action_id)
		check(int(session.snapshot().get("last_result", {}).get("delta", {}).get("stats", {}).get("sword", -1)) == 10, "%s reports the configured sword gain" % action_id)
		session.acknowledge_result()
	var all_motion_counts_once: bool = true
	for action_id: String in SWORD_CLIPS:
		all_motion_counts_once = all_motion_counts_once and int(session.snapshot().get("counts", {}).get(action_id, 0)) == 1
	check(all_motion_counts_once, "all five stable sword actions preflighted and settled exactly once")


func _check_legacy_unvoiced_stream() -> void:
	var session: Variant = _new_session(stream_pack)
	var talk: Dictionary = session.select_action("talk_to_keeper", "legacy-stream-talk")
	check(bool(talk.get("ok", false)) and session.event_view().get("voice", "").is_empty(), "an old unvoiced pack still opens a dialogue without a voice binding")
	check(bool(session.continue_event().get("ok", false)) and session.event_view().get("node_id", "") == "choice", "the legacy dialogue still advances normally")
	var result: Dictionary = session.select_action("read_by_river", "legacy-stream-read")
	check(not bool(result.get("ok", false)), "a menu action remains unavailable while the legacy dialogue is active")
	check(bool(session.cancel_event().get("ok", false)), "the legacy unvoiced event can still be cancelled")
	var read_result: Dictionary = session.select_action("walk_to_river", "legacy-stream-travel")
	check(bool(read_result.get("ok", false)), "the legacy Stream pack continues to execute its original scene actions")
	session.acknowledge_result()
	var river_read: Dictionary = session.select_action("read_by_river", "legacy-stream-read-after-travel")
	check(bool(river_read.get("ok", false)) and int(session.snapshot().get("stats", {}).get("insight", -1)) == 8, "the legacy Stream reading action still settles with its original gain")


func _advance_intro_to_choice(session: Variant) -> void:
	var expected: Array[String] = ["opening", "sit", "hurry", "advice", "choice"]
	for index in range(expected.size() - 1):
		var event: Dictionary = session.event_view()
		check(str(event.get("node_id", "")) == expected[index], "mentor intro reaches authored line %s" % expected[index])
		if index == 0:
			var run_id: String = str(session.snapshot().get("run_id", ""))
			var revision: int = int(session.snapshot().get("revision", -1))
			var advanced: Dictionary = session.continue_event(run_id, revision)
			check(bool(advanced.get("ok", false)), "the current opening-line continue advances once")
			var after_opening: Dictionary = session.snapshot()
			check(not bool(session.continue_event(run_id, revision).get("ok", false)) and session.snapshot() == after_opening, "a stale opening continue cannot skip the next line")
		else:
			check(bool(session.continue_event().get("ok", false)), "the player continues the voiced %s line" % expected[index])
	var choice: Dictionary = session.event_view()
	check(str(choice.get("node_id", "")) == "choice" and str(choice.get("voice", "")) == "choice", "mentor intro reaches its voiced choice node")


func _advance_to_end(session: Variant, say_nodes: Array[String]) -> void:
	for node_id: String in say_nodes:
		var event: Dictionary = session.event_view()
		check(str(event.get("node_id", "")) == node_id and str(event.get("voice", "")) == node_id, "the selected branch reaches voiced node %s" % node_id)
		check(bool(session.continue_event().get("ok", false)), "the player continues voiced node %s" % node_id)
	check(session.event_view().get("node_id", "") == "end", "the selected branch reaches its explicit end node")


func _options_by_id(event: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for option_value: Variant in event.get("options", []):
		if option_value is Dictionary:
			var option: Dictionary = option_value
			result[str(option.get("id", ""))] = option
	return result


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(data)
	check(bool(configured.get("ok", false)), "EngineSession configures pack %s" % str(data.get("id", "?")))
	return session


func _new_store(folder: String) -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = test_base.path_join(folder)
	return store


func _allocate_store_base() -> String:
	for attempt in range(20):
		var candidate: String = "user://mentor_loop_test_%d_%d" % [Time.get_ticks_usec(), attempt]
		var absolute_path: String = ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute_path) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if not test_base.is_empty():
		_cleanup_tree(ProjectSettings.globalize_path(test_base))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_base))
	if failures > 0:
		for message in failure_messages:
			push_error(message)
	print("cultivation_engine_mentor_loop_test: ", checks - failures, "/", checks, " checks passed")
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
