extends SceneTree

const LoaderScript := preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript := preload("res://addons/cultivation_mode/session.gd")
const StoreScript := preload("res://addons/cultivation_mode/save_store.gd")
const SHU_MANIFEST := "res://games/shu_entry/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"
const REPORT_PATH := "res://.local/qa/cultivation-engine-v02-tea/quest-state-report.json"

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
	check(bool(shu_result.get("ok", false)), "the authored Shu pack with the optional quest registry loads")
	check(bool(stream_result.get("ok", false)), "the unchanged Stream pack without a quest registry loads")
	if not bool(shu_result.get("ok", false)) or not bool(stream_result.get("ok", false)):
		_finish()
		return
	shu_pack = shu_result.get("pack", {})
	stream_pack = stream_result.get("pack", {})
	test_base = "user://cultivation_engine_quest_test_%d" % Time.get_ticks_usec()

	_check_decline_and_pre_accept_cancel()
	_check_acceptance_and_either_inspection_order()
	_check_object_costs_and_replay()
	_check_context_and_return_gates()
	_check_rest_crosses_day_inside_quest()
	_check_checkpoint_roundtrips_and_pack_isolation()
	_check_invalid_quest_and_object_data()
	_check_reserved_flags_and_forged_snapshots()
	_check_renamed_content_fixture()
	_check_synthetic_terminal_return_fixture()
	_finish()


func _check_decline_and_pre_accept_cancel() -> void:
	var cancelled: Variant = _new_session(shu_pack)
	var invite: Dictionary = _invitation_spec(shu_pack)
	check(not invite.is_empty(), "authored commission data exposes an invitation and accepted choice")
	if invite.is_empty():
		return
	var opened: Dictionary = cancelled.select_action(str(invite.action_id), "cancel-before-accept-invitation")
	check(bool(opened.get("ok", false)) and str(cancelled.snapshot().get("phase", "")) == "event", "commission invitation opens as ordinary dialogue before acceptance")
	var before_cancel: Dictionary = cancelled.snapshot()
	var cancel_result: Dictionary = cancelled.cancel_event()
	check(bool(cancel_result.get("ok", false)) and str(cancelled.snapshot().get("phase", "")) == "ready", "the pre-accept commission dialogue can be cancelled")
	check(not bool(cancelled.snapshot().get("flags", {}).get(_quest_flag(shu_pack, "active_flag"), false)) and str(cancelled.snapshot().get("scene", "")) == str(shu_pack.get("initial_scene", "")), "cancelling before acceptance does not enter or activate the quest")
	check(cancelled.snapshot().get("sequence", -1) == before_cancel.get("sequence", -2), "cancelling before acceptance does not add a gameplay settlement")

	var declined: Variant = _new_session(shu_pack)
	declined.select_action(str(invite.action_id), "decline-before-accept-invitation")
	declined.continue_event()
	var choice: Dictionary = declined.event_view()
	var decline_option: String = _option_id_for_action(choice, "")
	check(not decline_option.is_empty(), "the authored commission choice has a decline-without-action option")
	if decline_option.is_empty():
		return
	var declined_result: Dictionary = declined.choose(decline_option, "decline-before-accept-choice")
	check(bool(declined_result.get("ok", false)) and str(declined.snapshot().get("phase", "")) == "event", "declining keeps the authored dialogue flow without activating the quest")
	declined.continue_event()
	declined.acknowledge_result()
	check(str(declined.snapshot().get("scene", "")) == str(shu_pack.get("initial_scene", "")) and str(declined.quest_view().get("id", "")).is_empty(), "a declined commission leaves the player at the normal initial location")


func _check_acceptance_and_either_inspection_order() -> void:
	var first_then_second: Variant = _new_session(shu_pack)
	var accepted: Dictionary = _start_quest(first_then_second, shu_pack, "accept-first-order")
	check(bool(accepted.get("ok", false)), "accepting the commission enters the authored branch")
	if not bool(accepted.get("ok", false)):
		return
	var quest: Dictionary = first_then_second.quest_view()
	var q: Dictionary = _quest_data(shu_pack)
	var stages: Array = q.get("stages", [])
	check(str(first_then_second.snapshot().get("phase", "")) == "ready" and first_then_second.snapshot().get("event", {}).is_empty(), "acceptance goes directly to a safe ready state with no extra acknowledgement")
	check(str(first_then_second.snapshot().get("scene", "")) == _quest_scene(shu_pack), "acceptance lands in the authored quest scene")
	check(bool(first_then_second.snapshot().get("flags", {}).get(str(stages[0].get("complete_flag", "")), false)) and str(quest.get("stage_id", "")) == str(stages[1].get("id", "")), "the entry stage completes on acceptance and the cup stage becomes current")
	check(bool(quest.get("stage_complete", false)) == false and bool(quest.get("complete", false)) == false and not bool(stages[1].get("terminal", false)), "the A/B cup stage is a nonterminal stage, not a completed quest")
	check(int(quest.get("seen", -1)) == 0 and int(quest.get("total", -1)) == 2, "the authored two-cup stage begins at 0 / 2 inspected objects")
	check(first_then_second.can_save(), "the accepted branch is an ordinary save boundary")
	var objects: Array = _objects_for_quest(shu_pack)
	if objects.size() != 2:
		check(false, "the authored A/B stage has exactly two inspectable cups")
		return
	var first_id := str(objects[0].get("id", ""))
	var second_id := str(objects[1].get("id", ""))
	var before_first: Dictionary = first_then_second.snapshot()
	var first: Dictionary = first_then_second.inspect_object(first_id, "first-order-inspect-first")
	check(bool(first.get("ok", false)) and first.get("delta", {}).get("stats", {}) == {} and int(first.get("delta", {}).get("slots", -1)) == 0, "direct cup inspection is free and has zero duration")
	check(first.get("before", {}).get("day", -1) == before_first.get("day", -2) and first.get("before", {}).get("slot", -1) == before_first.get("slot", -2) and first.get("after", {}).get("day", -1) == before_first.get("day", -2) and first.get("after", {}).get("slot", -1) == before_first.get("slot", -2), "inspection leaves the authored day and time slot unchanged")
	check(bool(first_then_second.snapshot().get("flags", {}).get(str(objects[0].get("inspected_flag", "")), false)) and not bool(first_then_second.snapshot().get("flags", {}).get(str(objects[1].get("inspected_flag", "")), false)) and int(first_then_second.quest_view().get("seen", -1)) == 1 and not bool(first_then_second.quest_view().get("stage_complete", true)), "one cup moves the stage to 1 / 2 with only its own seen flag set")
	var first_state: Dictionary = first_then_second.snapshot()
	var replay: Dictionary = first_then_second.inspect_object(first_id, "first-order-inspect-first")
	check(bool(replay.get("ok", false)) and bool(replay.get("duplicate", false)) and first_then_second.snapshot() == first_state, "same-operation inspection returns its receipt without another settlement")
	var reread: Dictionary = first_then_second.inspect_object(first_id, "first-order-inspect-first-again")
	check(bool(reread.get("ok", false)) and bool(reread.get("repeat", false)) and first_then_second.snapshot() == first_state, "a new read of an inspected cup is informational and does not alter counters or receipts")
	var second: Dictionary = first_then_second.inspect_object(second_id, "first-order-inspect-second")
	check(bool(second.get("ok", false)) and int(first_then_second.quest_view().get("seen", -1)) == 2 and bool(first_then_second.quest_view().get("stage_complete", false)), "inspecting the other cup moves the stage to 2 / 2 and completes B in first-then-second order")
	_check_ab_boundary(first_then_second, shu_pack, "first-then-second")

	var second_then_first: Variant = _new_session(shu_pack)
	_start_quest(second_then_first, shu_pack, "accept-reverse-order")
	var reverse_objects: Array = _objects_for_quest(shu_pack)
	second_then_first.inspect_object(str(reverse_objects[1].get("id", "")), "reverse-inspect-second")
	check(not bool(second_then_first.quest_view().get("stage_complete", true)), "inspecting the second cup alone does not complete the two-cup stage")
	second_then_first.inspect_object(str(reverse_objects[0].get("id", "")), "reverse-inspect-first")
	check(bool(second_then_first.quest_view().get("stage_complete", false)), "the same stage completes in the reverse inspection order")
	_check_ab_boundary(second_then_first, shu_pack, "second-then-first")


func _check_object_costs_and_replay() -> void:
	var session: Variant = _new_session(shu_pack)
	_start_quest(session, shu_pack, "costs-accept")
	var objects := _objects_for_quest(shu_pack)
	var first_object: Dictionary = objects[0]
	var second_object: Dictionary = objects[1]
	var first_id := str(first_object.get("id", ""))
	var second_id := str(second_object.get("id", ""))
	var inspect_first := str(first_object.get("inspect_action", ""))
	var inspect_second := str(second_object.get("inspect_action", ""))
	session.inspect_object(first_id, "costs-inspect-first")
	var actions: Dictionary = shu_pack.get("actions", {})
	var repair_id := _object_action_with_cost(first_object, actions, 22)
	var ask_first_id := _object_action_with_cost(first_object, actions, 8)
	var ask_second_id := _object_action_with_cost(second_object, actions, 8)
	check(not repair_id.is_empty() and not ask_first_id.is_empty() and not ask_second_id.is_empty(), "authored objects expose their own repair and mentor actions with 22/8 energy costs")
	if repair_id.is_empty() or ask_first_id.is_empty() or ask_second_id.is_empty():
		return
	var baseline: Dictionary = session.snapshot()
	var repair: Dictionary = session.execute_object_action(first_id, repair_id, "once-repair-first")
	check(bool(repair.get("ok", false)) and int(repair.get("delta", {}).get("stats", {}).get("energy", 0)) == -22 and int(repair.get("delta", {}).get("slots", -1)) == 0, "repair settles its authored 22 energy cost and no time")
	var repaired_state: Dictionary = session.snapshot()
	check(int(repaired_state.get("stats", {}).get("energy", -1)) == int(baseline.get("stats", {}).get("energy", -2)) - 22, "repair applies exactly one 22-point deduction")
	var repair_replay: Dictionary = session.execute_object_action(first_id, repair_id, "once-repair-first")
	check(bool(repair_replay.get("duplicate", false)) and session.snapshot() == repaired_state, "same-operation repair replay returns the original receipt without recharging")
	var repair_again: Dictionary = session.execute_object_action(first_id, repair_id, "repair-first-new-request")
	check(not bool(repair_again.get("ok", false)) and repair_again.get("code", "") == "already_used" and session.snapshot() == repaired_state, "a new repair request for the same cup is rejected without state change")

	var ask_first: Dictionary = session.execute_object_action(first_id, ask_first_id, "once-ask-first")
	check(bool(ask_first.get("ok", false)) and int(ask_first.get("delta", {}).get("stats", {}).get("energy", 0)) == -8 and int(ask_first.get("delta", {}).get("slots", -1)) == 0, "asking about the first cup spends 8 energy and no time")
	var asked_first_state: Dictionary = session.snapshot()
	var ask_first_replay: Dictionary = session.execute_object_action(first_id, ask_first_id, "once-ask-first")
	check(bool(ask_first_replay.get("duplicate", false)) and session.snapshot() == asked_first_state, "same-operation first-cup question replay does not spend energy twice")
	var ask_first_again: Dictionary = session.execute_object_action(first_id, ask_first_id, "ask-first-new-request")
	check(not bool(ask_first_again.get("ok", false)) and ask_first_again.get("code", "") == "already_used" and session.snapshot() == asked_first_state, "a new first-cup question is rejected after its once-only settlement")

	session.inspect_object(second_id, "costs-inspect-second")
	var before_second_ask: Dictionary = session.snapshot()
	var ask_second: Dictionary = session.execute_object_action(second_id, ask_second_id, "once-ask-second")
	check(bool(ask_second.get("ok", false)) and int(ask_second.get("delta", {}).get("stats", {}).get("energy", 0)) == -8 and int(ask_second.get("delta", {}).get("slots", -1)) == 0, "asking about the second cup independently spends 8 energy and no time")
	var asked_second_state: Dictionary = session.snapshot()
	var ask_second_replay: Dictionary = session.execute_object_action(second_id, ask_second_id, "once-ask-second")
	check(bool(ask_second_replay.get("duplicate", false)) and session.snapshot() == asked_second_state, "same-operation second-cup question replay does not spend energy twice")
	var ask_second_again: Dictionary = session.execute_object_action(second_id, ask_second_id, "ask-second-new-request")
	check(not bool(ask_second_again.get("ok", false)) and ask_second_again.get("code", "") == "already_used" and session.snapshot() == asked_second_state, "a new second-cup question is rejected after its once-only settlement")
	var final_stats: Dictionary = session.snapshot().get("stats", {})
	for stat: Variant in shu_pack.get("rules", {}).get("stats", []):
		if not stat is Dictionary or str(stat.get("id", "")) == "energy":
			continue
		check(int(baseline.get("stats", {}).get(str(stat.id), -1)) == int(final_stats.get(str(stat.id), -2)), "cup actions do not alter unrelated growth stat " + str(stat.id))
	check(int(before_second_ask.get("day", -1)) == int(session.snapshot().get("day", -2)) and int(before_second_ask.get("slot", -1)) == int(session.snapshot().get("slot", -2)), "the second-cup question does not advance time")
	check(inspect_first != inspect_second, "each cup has a distinct zero-cost inspection action")

	var floor_session: Variant = _new_session(shu_pack)
	_start_quest(floor_session, shu_pack, "resource-floor-accept")
	floor_session.inspect_object(first_id, "resource-floor-inspect")
	var floor_fixture: Dictionary = floor_session.snapshot()
	floor_fixture["stats"]["energy"] = 7
	check(bool(floor_session.restore(floor_fixture).get("ok", false)), "limited test-only restore fixture sets energy below the 8-point question cost")
	var floor_before: Dictionary = floor_session.snapshot()
	var denied_ask: Dictionary = floor_session.execute_object_action(first_id, ask_first_id, "resource-floor-question")
	check(not bool(denied_ask.get("ok", false)) and denied_ask.get("code", "") == "insufficient_resource" and floor_session.snapshot() == floor_before, "insufficient object-action energy rejects atomically")
	var denied_repair: Dictionary = floor_session.execute_object_action(first_id, repair_id, "resource-floor-repair")
	check(not bool(denied_repair.get("ok", false)) and denied_repair.get("code", "") == "insufficient_resource" and floor_session.snapshot() == floor_before, "the 22-point repair floor also rejects atomically")


func _check_context_and_return_gates() -> void:
	var outside: Variant = _new_session(shu_pack)
	var objects := _objects_for_quest(shu_pack)
	var cup_id := str(objects[0].get("id", ""))
	var cup_action := str(objects[0].get("actions", [])[0])
	var before_outside: Dictionary = outside.snapshot()
	var outside_inspect: Dictionary = outside.inspect_object(cup_id, "forged-outside-inspect")
	check(not bool(outside_inspect.get("ok", false)) and outside.snapshot() == before_outside, "a registered object cannot be inspected outside its active scene and quest")
	var started: Variant = _new_session(shu_pack)
	_start_quest(started, shu_pack, "forged-context-accept")
	var run_id := str(started.snapshot().get("run_id", ""))
	var revision := int(started.snapshot().get("revision", -1))
	var before: Dictionary = started.snapshot()
	var stale_run: Dictionary = started.inspect_object(cup_id, "stale-run-object", "retired-run", revision)
	check(not bool(stale_run.get("ok", false)) and stale_run.get("code", "") == "stale_run" and started.snapshot() == before, "retired object UI run context is rejected atomically")
	var stale_revision: Dictionary = started.inspect_object(cup_id, "stale-revision-object", run_id, revision - 1)
	check(not bool(stale_revision.get("ok", false)) and stale_revision.get("code", "") == "stale_revision" and started.snapshot() == before, "stale object revision is rejected atomically")
	var stale_action_run: Dictionary = started.execute_object_action(cup_id, cup_action, "stale-run-object-action", "retired-run", revision)
	check(not bool(stale_action_run.get("ok", false)) and stale_action_run.get("code", "") == "stale_run" and started.snapshot() == before, "retired UI context cannot execute an object action through the action API")
	var stale_action_revision: Dictionary = started.execute_object_action(cup_id, cup_action, "stale-revision-object-action", run_id, revision - 1)
	check(not bool(stale_action_revision.get("ok", false)) and stale_action_revision.get("code", "") == "stale_revision" and started.snapshot() == before, "stale object-action revision is rejected atomically")
	var unknown: Dictionary = started.inspect_object("fixture.unknown_object", "unknown-object")
	check(not bool(unknown.get("ok", false)) and unknown.get("code", "") == "unknown_object" and started.snapshot() == before, "unknown object IDs are rejected without transaction changes")
	var wrong_object: Dictionary = started.execute_object_action(str(objects[1].get("id", "")), cup_action, "forged-object-action")
	check(not bool(wrong_object.get("ok", false)) and started.snapshot() == before, "an action registered to one cup cannot be forged against the other cup")
	var generic_menu: Dictionary = started.select_action("train_mountain", "generic-action-inside-quest")
	check(not bool(generic_menu.get("ok", false)) and started.snapshot() == before, "normal cultivation menu APIs cannot execute an outside action in the quest")
	var q: Dictionary = _quest_data(shu_pack)
	var return_id := str(q.get("return_action", ""))
	var attempted_return: Dictionary = started.select_action(return_id, "unfinished-api-return")
	check(not bool(attempted_return.get("ok", false)) and started.snapshot() == before, "the return action API cannot leave an unfinished A/B quest")
	var escaped: Dictionary = started.cancel_event()
	check(not bool(escaped.get("ok", false)) and started.snapshot() == before, "cancel_event cannot release an active branch even when called directly")

	var escape_pack: Dictionary = shu_pack.duplicate(true)
	var escape_id := "fixture_branch_escape"
	var qid := _quest_id(shu_pack)
	var branch_scene := _quest_scene(shu_pack)
	var return_scene := str(q.get("return_scene", ""))
	escape_pack["actions"][escape_id] = {
		"label": "TEST FIXTURE ONLY: forged branch escape",
		"description": "Adversarial API-gate fixture; not shipped content.",
		"scenes": [branch_scene], "menu": true, "duration": 0, "costs": {}, "gains": {},
		"conditions": {"stats_gte": {}, "flags": {}}, "set_flags": {}, "once_key": "",
		"bonuses": [], "event": "", "target_scene": return_scene,
		"result": "Synthetic adversarial test action.", "character": ""
	}
	check(loader.validate(escape_pack).is_empty(), "the explicitly synthetic adversarial action is valid authored content outside the quest registration")
	var escaped_session: Variant = _new_session(escape_pack)
	_start_quest(escaped_session, escape_pack, "escape-fixture-accept")
	var before_escape: Dictionary = escaped_session.snapshot()
	var escape_result: Dictionary = escaped_session.select_action(escape_id, "forged-unregistered-escape")
	check(not bool(escape_result.get("ok", false)) and escaped_session.snapshot() == before_escape and str(escaped_session.snapshot().get("scene", "")) == branch_scene, "an unregistered target-scene action cannot leave the active branch through select_action")
	check(not qid.is_empty(), "the branch escape check resolves the registered quest from the pack")

	var completed: Variant = _new_session(shu_pack)
	_start_quest(completed, shu_pack, "boundary-accept")
	var complete_objects := _objects_for_quest(shu_pack)
	completed.inspect_object(str(complete_objects[0].get("id", "")), "boundary-inspect-one")
	completed.inspect_object(str(complete_objects[1].get("id", "")), "boundary-inspect-two")
	var before_boundary: Dictionary = completed.snapshot()
	var return_after_b: Dictionary = completed.select_action(return_id, "ab-boundary-return")
	check(not bool(return_after_b.get("ok", false)) and completed.snapshot() == before_boundary and bool(completed.quest_view().get("stage_complete", false)) and not bool(completed.quest_view().get("complete", true)), "B completion remains inside the active quest and cannot return through the API")
	var cancel_after_b: Dictionary = completed.cancel_event()
	check(not bool(cancel_after_b.get("ok", false)) and completed.snapshot() == before_boundary, "B completion cannot be escaped through cancel_event")
	check(str(completed.snapshot().get("scene", "")) == branch_scene, "the player remains in the authored A/B scene after stage completion")


func _check_rest_crosses_day_inside_quest() -> void:
	var session: Variant = _new_session(shu_pack)
	_start_quest(session, shu_pack, "crossday-accept")
	var fixture: Dictionary = session.snapshot()
	fixture["stats"]["energy"] = 50
	fixture["slot"] = shu_pack.get("rules", {}).get("clock", {}).get("slots", []).size() - 1
	fixture["day"] = int(fixture.get("day", 1))
	check(bool(session.restore(fixture).get("ok", false)), "limited active-quest boundary fixture starts at the last authored time slot")
	var before: Dictionary = session.snapshot()
	var rest_id := str(_quest_data(shu_pack).get("rest_action", ""))
	var rest: Dictionary = session.select_action(rest_id, "crossday-quest-rest")
	check(bool(rest.get("ok", false)) and session.can_save(), "resting is allowed during the quest and remains a save-safe ready action")
	check(int(session.snapshot().get("stats", {}).get("energy", -1)) == 84 and int(rest.get("delta", {}).get("stats", {}).get("energy", 0)) == 34, "quest rest applies the authored +34 recovery")
	check(int(session.snapshot().get("day", -1)) == int(before.get("day", 0)) + 1 and int(session.snapshot().get("slot", -1)) == 0 and int(rest.get("delta", {}).get("slots", -1)) == 1, "quest rest advances one slot and crosses the pack-defined day boundary")
	check(str(session.snapshot().get("scene", "")) == _quest_scene(shu_pack) and str(session.quest_view().get("stage_id", "")) == _stage_id(shu_pack, 1), "cross-day rest preserves quest location and current stage")
	check(bool(session.snapshot().get("flags", {}).get(_quest_flag(shu_pack, "active_flag"), false)) and not bool(session.quest_view().get("complete", true)), "cross-day rest preserves branch occupancy without marking the whole quest complete")


func _check_checkpoint_roundtrips_and_pack_isolation() -> void:
	var first: Variant = _new_session(shu_pack)
	_start_quest(first, shu_pack, "save-accept")
	var objects := _objects_for_quest(shu_pack)
	var first_object: Dictionary = objects[0]
	var second_object: Dictionary = objects[1]
	var first_id := str(first_object.get("id", ""))
	var second_id := str(second_object.get("id", ""))
	var repair_id := _object_action_with_cost(first_object, shu_pack.get("actions", {}), 22)
	var ask_first_id := _object_action_with_cost(first_object, shu_pack.get("actions", {}), 8)
	first.inspect_object(first_id, "save-one-cup-inspect")
	first.execute_object_action(first_id, repair_id, "save-one-cup-repair")
	var store: Variant = _new_store(test_base.path_join("save_isolation"))
	var one_cup_checkpoint: Dictionary = first.snapshot()
	check(bool(store.save_session(first).get("ok", false)), "the one-cup A/B checkpoint is saved through SaveStore")
	first.execute_object_action(first_id, ask_first_id, "mutate-after-one-cup-save")
	check(first.snapshot() != one_cup_checkpoint, "a legal action mutates live state after the one-cup checkpoint")
	check(bool(store.load_session(first).get("ok", false)) and first.snapshot() == one_cup_checkpoint, "one-cup load restores the exact state, receipt, flags, resources and clock")
	var repair_replay: Dictionary = first.execute_object_action(first_id, repair_id, "save-one-cup-repair")
	check(bool(repair_replay.get("duplicate", false)) and first.snapshot() == one_cup_checkpoint, "restored one-cup repair receipt cannot charge again")
	var repair_new: Dictionary = first.execute_object_action(first_id, repair_id, "save-one-cup-repair-again")
	check(not bool(repair_new.get("ok", false)) and first.snapshot() == one_cup_checkpoint, "restored once flag rejects a new repair without recharging")
	first.inspect_object(second_id, "save-two-cup-inspect")
	var two_cup_checkpoint: Dictionary = first.snapshot()
	check(bool(first.quest_view().get("stage_complete", false)) and not bool(first.quest_view().get("complete", true)), "two-cup checkpoint captures completed B while the whole A/B branch remains incomplete")
	check(bool(store.save_session(first).get("ok", false)), "the two-cup stage-boundary checkpoint is saved")
	var rest_id := str(_quest_data(shu_pack).get("rest_action", ""))
	first.select_action(rest_id, "mutate-after-two-cup-save")
	check(first.snapshot() != two_cup_checkpoint, "a quest rest mutates live state after the two-cup checkpoint")
	check(bool(store.load_session(first).get("ok", false)) and first.snapshot() == two_cup_checkpoint, "two-cup load restores the exact stage-complete, branch-active checkpoint")
	check(bool(first.quest_view().get("stage_complete", false)) and not bool(first.quest_view().get("complete", true)) and first.can_save(), "restored B checkpoint keeps its boundary and is still saveable")

	var stream: Variant = _new_session(stream_pack)
	var stream_checkpoint: Dictionary = stream.snapshot()
	check(stream.pack.get("quests", {}).is_empty(), "Stream remains an independent pack without Tea quest data")
	check(bool(store.save_session(stream).get("ok", false)), "the same SaveStore writes a separate Stream pack checkpoint")
	var stream_action := "walk_to_river"
	var stream_change: Dictionary = stream.select_action(stream_action, "stream-isolation-mutate")
	check(bool(stream_change.get("ok", false)) and stream.snapshot() != stream_checkpoint, "Stream's own action changes only its independent session")
	check(bool(store.load_session(first).get("ok", false)) and first.snapshot() == two_cup_checkpoint, "loading the Tea pack does not select Stream's checkpoint")
	check(bool(store.load_session(stream).get("ok", false)) and stream.snapshot() == stream_checkpoint, "loading Stream restores its own exact checkpoint after Tea use")
	check(first.snapshot() == two_cup_checkpoint, "restoring Stream leaves the Tea stage-complete session untouched")


func _check_invalid_quest_and_object_data() -> void:
	var bad_quest: Dictionary = shu_pack.duplicate(true)
	var qid := _quest_id(bad_quest)
	var bad_requirements: Dictionary = bad_quest["quests"][qid]["stages"][1]["requires"]["flags"]
	bad_requirements[bad_requirements.keys()[0]] = false
	check(not loader.validate(bad_quest).is_empty(), "loader rejects a quest stage requiring a negative rather than positive flag")
	var bad_object: Dictionary = shu_pack.duplicate(true)
	var scene_id := _quest_scene(bad_object)
	bad_object["scenes"][scene_id]["objects"][0]["rect"] = [0.95, 0.95, 0.2, 0.2]
	check(not loader.validate(bad_object).is_empty(), "loader rejects an object hotspot extending beyond its authored scene")
	var missing_object_action: Dictionary = shu_pack.duplicate(true)
	missing_object_action["scenes"][scene_id]["objects"][0]["inspect_action"] = "missing_fixture_inspection"
	check(not loader.validate(missing_object_action).is_empty(), "loader rejects an object that references an unregistered inspection action")
	var duplicate_inspected_flag: Dictionary = shu_pack.duplicate(true)
	var duplicate_scene := _quest_scene(duplicate_inspected_flag)
	var first_inspected := str(duplicate_inspected_flag["scenes"][duplicate_scene]["objects"][0].get("inspected_flag", ""))
	duplicate_inspected_flag["scenes"][duplicate_scene]["objects"][1]["inspected_flag"] = first_inspected
	check(not loader.validate(duplicate_inspected_flag).is_empty(), "loader rejects duplicate inspected flags across authored objects")
	var preinspected_object: Dictionary = shu_pack.duplicate(true)
	var preinspected_id := str(preinspected_object["scenes"][scene_id]["objects"][0].get("inspected_flag", ""))
	preinspected_object["initial_flags"][preinspected_id] = true
	check(not loader.validate(preinspected_object).is_empty(), "loader rejects an object whose inspected flag starts true")
	var foreign_inspection_writer: Dictionary = shu_pack.duplicate(true)
	var normal_writer := _clone_normal_action(foreign_inspection_writer, "fixture_foreign_inspection_writer")
	normal_writer["once_key"] = first_inspected
	check(not loader.validate(foreign_inspection_writer).is_empty(), "loader permits only the object's own inspect action to write its inspected flag")


func _check_reserved_flags_and_forged_snapshots() -> void:
	var q: Dictionary = _quest_data(shu_pack)
	var reserved_flags: Array[String] = [str(q.get("active_flag", "")), str(q.get("complete_flag", ""))]
	for raw_stage: Variant in q.get("stages", []):
		reserved_flags.append(str(_dict(raw_stage).get("complete_flag", "")))
	var writer_modes: Array[String] = ["once_key", "set_flags", "consume_bonus"]
	for reserved_flag: String in reserved_flags:
		for mode: String in writer_modes:
			var bad_pack: Dictionary = shu_pack.duplicate(true)
			var action: Dictionary = _clone_normal_action(bad_pack, "fixture_reserved_%s_%s" % [mode, reserved_flag])
			match mode:
				"once_key":
					action["once_key"] = reserved_flag
				"set_flags":
					action["set_flags"] = {reserved_flag: false}
				"consume_bonus":
					action["bonuses"] = [{"flag": reserved_flag, "gains": {"cultivation": 1}, "consume": true}]
			check(not loader.validate(bad_pack).is_empty(), "loader rejects a normal action %s writer for reserved quest flag %s" % [mode, reserved_flag])

	var active_session: Variant = _new_session(shu_pack)
	var forged_active: Dictionary = active_session.snapshot()
	var quest_stages: Array = q.get("stages", [])
	var first_stage: Dictionary = _dict(quest_stages[0]) if not quest_stages.is_empty() else {}
	forged_active["flags"][str(q.get("active_flag", ""))] = true
	forged_active["flags"][str(first_stage.get("complete_flag", ""))] = true
	forged_active["scene"] = _quest_scene(shu_pack)
	var unchanged_before_active_restore: Dictionary = active_session.snapshot()
	var active_restore: Dictionary = active_session.restore(forged_active)
	check(not bool(active_restore.get("ok", false)) and active_session.snapshot() == unchanged_before_active_restore, "restore rejects a forged active branch without an authored enter-action count and receipt, atomically")

	var phantom_session: Variant = _new_session(shu_pack)
	var invitation_id: String = str(_invitation_spec(shu_pack).get("action_id", ""))
	phantom_session.select_action(invitation_id, "phantom-return-fixture")
	phantom_session.cancel_event()
	var phantom: Dictionary = phantom_session.snapshot()
	var return_id: String = str(q.get("return_action", ""))
	var wrapper: Dictionary = phantom["receipts"]["phantom-return-fixture"]
	wrapper["action_id"] = return_id
	wrapper["result"]["action_id"] = return_id
	wrapper["result"]["action_label"] = str(shu_pack["actions"][return_id]["label"])
	phantom["counts"] = {return_id: 1}
	phantom["last_result"] = wrapper["result"].duplicate(true)
	phantom["journal"] = [wrapper["result"].duplicate(true)]
	var before_phantom: Dictionary = phantom_session.snapshot()
	var phantom_result: Dictionary = phantom_session.restore(phantom)
	check(not bool(phantom_result.get("ok", false)) and phantom_session.snapshot() == before_phantom, "a count-and-receipt-consistent phantom return without acceptance is rejected atomically")

	var accepted_session: Variant = _new_session(shu_pack)
	_start_quest(accepted_session, shu_pack, "receipt-backed-accept")
	var missing_entry_count: Dictionary = accepted_session.snapshot()
	var entry_id := str(_invitation_spec(shu_pack).get("entry_action", ""))
	missing_entry_count["counts"][entry_id] = 0
	var accepted_before_bad_restore: Dictionary = accepted_session.snapshot()
	var missing_count_restore: Dictionary = accepted_session.restore(missing_entry_count)
	check(not bool(missing_count_restore.get("ok", false)) and accepted_session.snapshot() == accepted_before_bad_restore, "restore rejects an active flag with an enter receipt but no matching action count, atomically")

	var terminal_pack: Dictionary = _make_terminal_fixture()
	if not loader.validate(terminal_pack).is_empty():
		check(false, "terminal snapshot checks use a valid synthetic-only authored fixture")
		return
	var qid := _quest_id(terminal_pack)
	var terminal_q: Dictionary = _dict(terminal_pack["quests"].get(qid))
	var terminal_session: Variant = _new_session(terminal_pack)
	_start_quest(terminal_session, terminal_pack, "forged-return-accept")
	var objects := _objects_for_quest(terminal_pack)
	terminal_session.inspect_object(str(objects[0].get("id", "")), "forged-return-inspect-one")
	terminal_session.inspect_object(str(objects[1].get("id", "")), "forged-return-inspect-two")
	var forged_return: Dictionary = terminal_session.snapshot()
	forged_return["scene"] = str(terminal_q.get("return_scene", ""))
	forged_return["flags"][str(terminal_q.get("active_flag", ""))] = false
	var active_before_bad_return_restore: Dictionary = terminal_session.snapshot()
	var return_restore: Dictionary = terminal_session.restore(forged_return)
	check(not bool(return_restore.get("ok", false)) and terminal_session.snapshot() == active_before_bad_return_restore, "restore rejects leaving even a synthetic complete quest without its authored return-action count and receipt, atomically")


func _make_terminal_fixture() -> Dictionary:
	# In-memory test data only; the shipped Tea A/B registry remains nonterminal.
	var terminal_pack: Dictionary = shu_pack.duplicate(true)
	var qid := _quest_id(terminal_pack)
	var q: Dictionary = terminal_pack["quests"][qid]
	var stages: Array = q.get("stages", []).duplicate(true)
	var predecessor_flag := str(_dict(stages.back()).get("complete_flag", ""))
	var terminal_flag := "fixture_terminal_stage_complete"
	terminal_pack["initial_flags"][terminal_flag] = false
	stages.append({
		"id": "fixture_terminal_stage",
		"label": "TEST FIXTURE ONLY · authored terminal stage",
		"complete_flag": terminal_flag,
		"requires": {"flags": {predecessor_flag: true}},
		"terminal": true
	})
	q["stages"] = stages
	terminal_pack["quests"][qid] = q
	return terminal_pack


func _clone_normal_action(pack: Dictionary, new_id: String) -> Dictionary:
	var source: Dictionary = _dict(pack.get("actions", {}).get("train_mountain"))
	var fixture_action: Dictionary = source.duplicate(true)
	fixture_action.erase("presentation")
	fixture_action["scenes"] = ["back_mountain"]
	fixture_action["menu"] = true
	fixture_action["event"] = ""
	fixture_action["target_scene"] = ""
	fixture_action["once_key"] = ""
	fixture_action["set_flags"] = {}
	fixture_action["bonuses"] = []
	pack["actions"][new_id] = fixture_action
	return fixture_action


func _check_renamed_content_fixture() -> void:
	var remap: Dictionary = {
		"tea": "journey_alpha",
		"tea.sword_terrace": "scene_alpha",
		"tea_active": "branch_alpha_active",
		"tea_quest_complete": "branch_alpha_complete",
		"tea_return_sword_complete": "stage_alpha_arrived",
		"tea_cups_first_complete": "stage_alpha_pair_complete",
		"tea_cup_first_seen": "prop_alpha_one_seen",
		"tea_cup_second_seen": "prop_alpha_two_seen",
		"tea_first_repair_done": "prop_alpha_one_repaired",
		"tea_first_ask_done": "prop_alpha_one_questioned",
		"tea_second_ask_done": "prop_alpha_two_questioned",
		"return_sword": "arrival_alpha",
		"cups_first": "pair_alpha",
		"tea_invitation": "invite_alpha",
		"tea_accept": "enter_alpha",
		"tea_rest": "rest_alpha",
		"tea_return_to_corridor": "return_alpha",
		"tea_inspect_cup_first": "inspect_alpha_one",
		"tea_repair_cup_first": "repair_alpha_one",
		"tea_ask_first_cup": "ask_alpha_one",
		"tea_inspect_cup_second": "inspect_alpha_two",
		"tea_ask_second_cup": "ask_alpha_two",
		"tea.cup_first": "prop.alpha_one",
		"tea.cup_second": "prop.alpha_two",
		"tea_commission": "commission_alpha"
	}
	var renamed: Dictionary = _rename_tree(shu_pack, remap)
	check(loader.validate(renamed).is_empty(), "the in-memory renamed quest, scene, object, flag, stage, event and action IDs remain valid data")
	var session: Variant = _new_session(renamed)
	var entered: Dictionary = _start_quest(session, renamed, "renamed-entry")
	check(bool(entered.get("ok", false)) and str(session.quest_view().get("id", "")) == "journey_alpha" and str(session.snapshot().get("scene", "")) == "scene_alpha", "the shared quest runtime enters a renamed authored branch without Tea identity checks")
	var objects := _objects_for_quest(renamed)
	var object_id := str(objects[0].get("id", ""))
	var inspected: Dictionary = session.inspect_object(object_id, "renamed-inspection")
	check(bool(inspected.get("ok", false)) and str(inspected.get("object_id", "")) == object_id, "renamed object IDs use the generic object inspection API")
	var action_id := str(objects[0].get("actions", [])[0])
	var settled: Dictionary = session.execute_object_action(object_id, action_id, "renamed-object-action")
	check(bool(settled.get("ok", false)) and str(settled.get("object_id", "")) == object_id, "renamed object/action IDs settle via generic authored data")


func _check_synthetic_terminal_return_fixture() -> void:
	# This is an in-memory, clearly synthetic authored-data fixture. It does not
	# alter or claim that the shipped A/B story has a terminal ending.
	var terminal_pack: Dictionary = _make_terminal_fixture()
	var qid := _quest_id(terminal_pack)
	var q: Dictionary = terminal_pack["quests"][qid]
	check(loader.validate(terminal_pack).is_empty(), "synthetic terminal-path fixture validates as a separate authored-data pack")
	var session: Variant = _new_session(terminal_pack)
	_start_quest(session, terminal_pack, "synthetic-terminal-entry")
	var objects := _objects_for_quest(terminal_pack)
	session.inspect_object(str(objects[0].get("id", "")), "synthetic-terminal-cup-one")
	var before_terminal: Dictionary = session.snapshot()
	check(not bool(session.quest_view().get("complete", true)) and session.snapshot() == before_terminal, "synthetic terminal fixture remains incomplete until its authored stage requirements are met")
	session.inspect_object(str(objects[1].get("id", "")), "synthetic-terminal-cup-two")
	var terminal_view: Dictionary = session.quest_view()
	check(bool(terminal_view.get("stage_complete", false)) and bool(terminal_view.get("complete", false)) and str(terminal_view.get("stage_id", "")) == "fixture_terminal_stage", "clearly labeled synthetic authored terminal data can complete a terminal stage")
	var return_id := str(q.get("return_action", ""))
	var returned: Dictionary = session.select_action(return_id, "synthetic-terminal-return")
	check(bool(returned.get("ok", false)) and str(session.snapshot().get("scene", "")) == str(q.get("return_scene", "")) and str(session.quest_view().get("id", "")).is_empty(), "only the synthetic terminal fixture exercises the actual authored return path")


func _check_ab_boundary(session: Variant, pack: Dictionary, label: String) -> void:
	var q: Dictionary = _quest_data(pack)
	var flags: Dictionary = session.snapshot().get("flags", {})
	check(bool(session.quest_view().get("stage_complete", false)) and not bool(session.quest_view().get("complete", true)), "%s reaches the stage boundary while the entire quest remains incomplete" % label)
	check(not bool(flags.get(str(q.get("complete_flag", "")), false)), "%s does not set the whole-quest completion flag" % label)
	check(str(session.snapshot().get("scene", "")) == _quest_scene(pack), "%s keeps the active player in the quest scene" % label)
	check(session.can_save(), "%s remains a saveable ready checkpoint" % label)


func _start_quest(session: Variant, pack: Dictionary, prefix: String) -> Dictionary:
	var invite: Dictionary = _invitation_spec(pack)
	if invite.is_empty():
		check(false, "quest fixture has an authored invitation choice")
		return {"ok": false}
	var opened: Dictionary = session.select_action(str(invite.get("action_id", "")), prefix + "-invitation")
	if not bool(opened.get("ok", false)):
		check(false, "quest invitation opens for " + prefix)
		return opened
	var continued: Dictionary = session.continue_event()
	if not bool(continued.get("ok", false)):
		check(false, "quest invitation reaches its authored acceptance choice for " + prefix)
		return continued
	var accepted: Dictionary = session.choose(str(invite.get("option_id", "")), prefix + "-accept")
	check(bool(accepted.get("ok", false)), "authored acceptance action settles for " + prefix)
	return accepted


func _invitation_spec(pack: Dictionary) -> Dictionary:
	var quest: Dictionary = _quest_data(pack)
	if quest.is_empty():
		return {}
	var quest_id := _quest_id(pack)
	var entry_action := ""
	for action_key: Variant in _dict(pack.get("actions")):
		var action: Dictionary = _dict(pack.get("actions", {})[action_key])
		if str(action.get("enter_quest", "")) == quest_id:
			entry_action = str(action_key)
			break
	if entry_action.is_empty():
		return {}
	for action_key: Variant in _dict(pack.get("actions")):
		var action: Dictionary = _dict(pack.get("actions", {})[action_key])
		var event_id := str(action.get("event", ""))
		if event_id.is_empty():
			continue
		var event: Dictionary = _dict(pack.get("events", {}).get(event_id))
		for node_value: Variant in _dict(event.get("nodes", {})).values():
			for option_value: Variant in _dict(node_value).get("options", []):
				var option: Dictionary = _dict(option_value)
				if str(option.get("action", "")) == entry_action:
					return {"action_id": str(action_key), "event_id": event_id, "option_id": str(option.get("id", "")), "entry_action": entry_action}
	return {}


func _option_id_for_action(event_view: Dictionary, action_id: String) -> String:
	for raw: Variant in event_view.get("options", []):
		var option: Dictionary = _dict(raw)
		if str(option.get("action", "")) == action_id:
			return str(option.get("id", ""))
		if action_id.is_empty() and str(option.get("action", "")).is_empty():
			return str(option.get("id", ""))
	return ""


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(data)
	check(bool(configured.get("ok", false)), "EngineSession configures pack %s" % str(data.get("id", "?")))
	return session


func _new_store(folder: String) -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = folder
	return store


func _quest_id(pack: Dictionary) -> String:
	var quests: Dictionary = _dict(pack.get("quests"))
	return str(quests.keys()[0]) if not quests.is_empty() else ""


func _quest_data(pack: Dictionary) -> Dictionary:
	var quests: Dictionary = _dict(pack.get("quests"))
	return _dict(quests.get(_quest_id(pack)))


func _quest_flag(pack: Dictionary, key: String) -> String:
	return str(_quest_data(pack).get(key, ""))


func _quest_scene(pack: Dictionary) -> String:
	var scenes: Array = _quest_data(pack).get("scenes", [])
	return str(scenes[0]) if not scenes.is_empty() else ""


func _stage_id(pack: Dictionary, index: int) -> String:
	var stages: Array = _quest_data(pack).get("stages", [])
	return str(stages[index].get("id", "")) if index >= 0 and index < stages.size() else ""


func _objects_for_quest(pack: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var qid := _quest_id(pack)
	var q: Dictionary = _quest_data(pack)
	for scene_id: Variant in q.get("scenes", []):
		var scene: Dictionary = _dict(pack.get("scenes", {}).get(scene_id))
		for raw: Variant in scene.get("objects", []):
			var object: Dictionary = _dict(raw)
			if str(object.get("quest", "")) == qid:
				result.append(object.duplicate(true))
	return result


func _object_action_with_cost(object: Dictionary, actions: Dictionary, energy_cost: int) -> String:
	for raw: Variant in object.get("actions", []):
		var action_id := str(raw)
		var action: Dictionary = _dict(actions.get(action_id))
		if int(_dict(action.get("costs", {})).get("energy", -1)) == energy_cost:
			return action_id
	return ""


func _rename_tree(value: Variant, remap: Dictionary) -> Variant:
	if value is String:
		return str(remap.get(value, value))
	if value is Array:
		var renamed: Array = []
		for item: Variant in value:
			renamed.append(_rename_tree(item, remap))
		return renamed
	if value is Dictionary:
		var renamed: Dictionary = {}
		for key: Variant in value:
			var new_key: Variant = remap.get(key, key)
			renamed[new_key] = _rename_tree(value[key], remap)
		return renamed
	return value


func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


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
	var report: Dictionary = {
		"test": "cultivation_engine_quest_test",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"captures": [],
		"limited_state_fixtures": ["resource_floor_energy_7", "crossday_slot_boundary", "forged_snapshot_rejections"],
		"terminal_return_source": "clearly_labeled_synthetic_authored_data_fixture_only",
		"result": ("PASS" if failures == 0 else "FAIL")
	}
	var report_parent: String = REPORT_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_parent))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write quest state report: " + REPORT_PATH)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Quest state report write failed: " + REPORT_PATH)
		file.close()
	print("CULTIVATION_ENGINE_QUEST_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)
