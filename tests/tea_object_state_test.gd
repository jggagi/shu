extends SceneTree

const State = preload("res://scripts/demo_state.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	test_direct_views_and_auto_completion()
	test_direct_view_invalidates_legacy_read()
	test_whitelisted_actions_and_once_only_settlement()
	test_invalid_requests_are_atomic()
	test_reset_invalidates_direct_calls()
	test_rest_during_tea_preserves_progress()
	print("TEA_OBJECT_STATE_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(failures)

func test_direct_views_and_auto_completion() -> void:
	for order in [["tea.cup_first", "tea.cup_second"], ["tea.cup_second", "tea.cup_first"]]:
		var state = State.new()
		var initial_cultivation := cultivation_snapshot(state)
		var start := state.begin_tea()
		var session := int(start.session)
		check(start.ok and state.accept_tea(session).ok, "direct-view session opens and accepts the commission")

		var first_id := String(order[0])
		var first_view := state.view_tea(first_id, session)
		check(first_view.ok and first_view.new_clue and not first_view.new_completion, "first viewed cup creates one clue without completing the stage")
		check(state.tea_active and not state.tea_stage_complete, "tea remains active after the first direct view")
		check(cultivation_snapshot(state) == initial_cultivation, "direct viewing has no cultivation or time settlement")

		var second_id := String(order[1])
		var second_view := state.view_tea(second_id, session)
		check(second_view.ok and second_view.new_clue and second_view.new_completion, "second viewed cup automatically completes the stage")
		check(state.tea_stage_complete and state.tea_active, "automatic completion keeps the accepted tea session active")
		check(cultivation_snapshot(state) == initial_cultivation, "automatic completion has no cultivation or time settlement")

		var repeated_view := state.view_tea(second_id, session)
		check(repeated_view.ok and not repeated_view.new_clue and not repeated_view.new_completion, "repeated viewing reports no new clue or completion")
		var before_blocked_return := full_snapshot(state)
		check(state.tea_stage_complete and not state.tea_quest_complete and not state.can_return_from_tea(), "two-cup viewing completes only the current stage")
		check(not state.cancel_tea().ok and full_snapshot(state) == before_blocked_return, "two-cup stage completion alone cannot return")
		fixture_mark_full_quest_complete_after_both_cups(state)
		check(state.cancel_tea().ok, "test-only full-quest fixture permits return")
		var revisit := state.begin_tea()
		var revisit_session := int(revisit.session)
		check(revisit.ok and not state.accept_tea(revisit_session).ok, "completed progress can be revisited without accepting twice")
		for object_id in [first_id, second_id]:
			var replay := state.view_tea(object_id, revisit_session)
			check(replay.ok and not replay.new_clue and not replay.new_completion, "replay of %s has no new progression" % object_id)
		check(state.tea_stage_complete and state.tea_quest_complete and state.tea_active, "replay keeps stage and fixture quest completion")
		check(state.cancel_tea().ok, "fixture-completed replay can return")

func test_whitelisted_actions_and_once_only_settlement() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var session := int(start.session)
	state.accept_tea(session)
	var before := full_snapshot(state)
	var unseen_action := state.execute_tea_action("tea.cup_first", "repair", session)
	check(not unseen_action.ok and full_snapshot(state) == before, "an action on an unseen cup is rejected atomically")

	var first_view := state.view_tea("tea.cup_first", session)
	var before_numeric := non_energy_snapshot(state)
	var repair := state.execute_tea_action("tea.cup_first", "repair", session)
	var repair_cost := int(state.rules.training_cost)
	check(first_view.ok and repair.ok and repair.cost == repair_cost and repair.feedback_key == "repair", "first-cup repair returns the host cost and repair feedback key")
	check(state.energy == 100 - repair_cost and non_energy_snapshot(state) == before_numeric, "repair only deducts the existing training cost")
	check(bool(state.tea_action_done.get("tea.cup_first", {}).get("repair", false)), "successful repair records its object/action settlement")
	before = full_snapshot(state)
	check(not state.execute_tea_action("tea.cup_first", "repair", session).ok and full_snapshot(state) == before, "repair cannot settle twice for the same cup")

	var ask_first := state.execute_tea_action("tea.cup_first", "ask_mentor", session)
	var mentor_cost := int(state.rules.mentor_cost)
	check(ask_first.ok and ask_first.cost == mentor_cost and ask_first.feedback_key == "rumor", "first cup mentor action returns the host cost and rumor feedback key")
	check(state.energy == 100 - repair_cost - mentor_cost, "mentor action deducts only the existing mentor cost")
	before = full_snapshot(state)
	check(not state.execute_tea_action("tea.cup_first", "ask_mentor", session).ok and full_snapshot(state) == before, "mentor action cannot settle twice for one cup")

	var unknown_action := state.execute_tea_action("tea.cup_first", "invented", session)
	check(not unknown_action.ok and full_snapshot(state) == before, "unknown action is rejected atomically")
	var repair_second := state.view_tea("tea.cup_second", session)
	before = full_snapshot(state)
	check(repair_second.ok and not state.execute_tea_action("tea.cup_second", "repair", session).ok and full_snapshot(state) == before, "repair is limited to the first cup")
	var ask_second := state.execute_tea_action("tea.cup_second", "ask_mentor", session)
	check(ask_second.ok and ask_second.cost == mentor_cost and ask_second.feedback_key == "rumor", "mentor action is allowed on the second cup")

func test_invalid_requests_are_atomic() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var session := int(start.session)
	var before := full_snapshot(state)
	check(not state.view_tea("tea.unknown", session).ok and full_snapshot(state) == before, "unknown object view is rejected atomically")
	check(not state.view_tea("tea.cup_first", session).ok and full_snapshot(state) == before, "view before acceptance is rejected atomically")
	state.accept_tea(session)
	before = full_snapshot(state)
	check(not state.execute_tea_action("tea.unknown", "ask_mentor", session).ok and full_snapshot(state) == before, "unknown object action is rejected atomically")
	check(not state.execute_tea_action("tea.cup_first", "unknown", session).ok and full_snapshot(state) == before, "unknown action is rejected atomically")
	check(not state.execute_tea_action("tea.cup_second", "repair", session).ok and full_snapshot(state) == before, "restricted action on an unseen cup is rejected atomically")

	state.energy = int(state.rules.training_cost) - 1
	state.view_tea("tea.cup_first", session)
	before = full_snapshot(state)
	var insufficient := state.execute_tea_action("tea.cup_first", "repair", session)
	check(not insufficient.ok and full_snapshot(state) == before, "insufficient energy rejects repair without partial settlement")

	before = full_snapshot(state)
	check(not state.can_return_from_tea() and not state.cancel_tea().ok and full_snapshot(state) == before, "accepted partial progress cannot cancel")
	state.reset()
	before = full_snapshot(state)
	check(not state.view_tea("tea.cup_first", session).ok and full_snapshot(state) == before, "reset session cannot view an object")
	check(not state.execute_tea_action("tea.cup_first", "ask_mentor", session).ok and full_snapshot(state) == before, "reset session cannot settle an action")
	check(not state.rest_tea(session).ok and full_snapshot(state) == before, "reset session cannot rest through tea")

func test_reset_invalidates_direct_calls() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var old_session := int(start.session)
	state.accept_tea(old_session)
	state.view_tea("tea.cup_first", old_session)
	check(state.execute_tea_action("tea.cup_first", "ask_mentor", old_session).ok, "pre-reset action settles once")
	state.reset()
	check(not state.tea_active and not state.tea_accepted and state.tea_seen.is_empty() and not state.tea_stage_complete and not state.tea_quest_complete and state.tea_action_done.is_empty(), "reset clears tea progress and action receipts")
	var before := full_snapshot(state)
	check(not state.view_tea("tea.cup_first", old_session).ok and full_snapshot(state) == before, "reset invalidates the old view session")
	check(not state.execute_tea_action("tea.cup_first", "ask_mentor", old_session).ok and full_snapshot(state) == before, "reset invalidates the old action session")
	check(not state.rest_tea(old_session).ok and full_snapshot(state) == before, "reset invalidates the old rest session")

	var fresh := state.begin_tea()
	var fresh_session := int(fresh.session)
	state.accept_tea(fresh_session)
	before = full_snapshot(state)
	check(fresh_session > old_session and not state.view_tea("tea.cup_first", old_session).ok and full_snapshot(state) == before, "old view stays stale after a new session starts")
	check(not state.execute_tea_action("tea.cup_first", "ask_mentor", old_session).ok and full_snapshot(state) == before, "old action stays stale after a new session starts")
	check(not state.rest_tea(old_session).ok and full_snapshot(state) == before, "old tea rest stays stale after a new session starts")
	state.reset()

func test_rest_during_tea_preserves_progress() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var session := int(start.session)
	state.accept_tea(session)
	state.view_tea("tea.cup_first", session)
	var action := state.execute_tea_action("tea.cup_first", "ask_mentor", session)
	check(action.ok, "tea action is recorded before resting")
	state.energy = int(state.rules.energy_max) - 5
	state.day = 4
	state.time_index = state.rules.times.size() - 1
	var unchanged_fields := non_time_non_energy_snapshot(state)
	var result := state.rest_tea(session)
	check(result.ok and result.gain == 5 and state.energy == int(state.rules.energy_max), "tea rest reports the actual gain and clamps at the energy maximum")
	check(state.day == 5 and state.time_index == 0, "tea rest advances one time slot across the day boundary")
	check(state.tea_active and state.tea_accepted and state.tea_seen.has("tea.cup_first"), "tea rest keeps session and clue progress active")
	check(state.tea_action_done.get("tea.cup_first", {}).get("ask_mentor", false), "tea rest keeps action settlement flags")
	check(non_time_non_energy_snapshot(state) == unchanged_fields, "tea rest does not change cultivation, understanding, or lesson bonus")
	var day_after_first_rest: int = state.day
	for i in range(8):
		var repeated_rest := state.rest_tea(session)
		check(repeated_rest.ok and state.tea_active, "repeated branch rest stays inside the active tea scene")
	check(state.day > day_after_first_rest, "repeated branch rests advance through another day")
	check(state.tea_seen.has("tea.cup_first") and state.tea_action_done.get("tea.cup_first", {}).get("ask_mentor", false), "repeated branch rests retain clue and action progress")

	var before_blocked_actions := full_snapshot(state)
	check(not state.train().ok and not state.rest().ok and not state.begin_dialogue().ok, "ordinary cultivation actions remain blocked during an accepted sidequest")
	check(full_snapshot(state) == before_blocked_actions, "blocked ordinary actions leave branch state unchanged")
	var second_view := state.view_tea("tea.cup_second", session)
	check(second_view.ok and state.tea_stage_complete, "second direct view completes only the current stage")
	fixture_mark_full_quest_complete_after_both_cups(state)
	check(state.cancel_tea().ok, "test-only full-quest fixture permits leaving the branch")
	state.train()
	state.rest()
	var revisit := state.begin_tea()
	var revisit_session := int(revisit.session)
	state.accept_tea(revisit_session)
	var replay_view := state.view_tea("tea.cup_first", revisit_session)
	var before := full_snapshot(state)
	check(replay_view.ok and not replay_view.new_clue and not state.execute_tea_action("tea.cup_first", "ask_mentor", revisit_session).ok and full_snapshot(state) == before, "action settlement and clue persist across cancellation, cultivation, rest, and revisit")
	state.cancel_tea()

func cultivation_snapshot(state) -> Dictionary:
	return {
		"day": state.day,
		"time_index": state.time_index,
		"energy": state.energy,
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func non_energy_snapshot(state) -> Dictionary:
	return {
		"day": state.day,
		"time_index": state.time_index,
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func non_time_non_energy_snapshot(state) -> Dictionary:
	return {
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func full_snapshot(state) -> Dictionary:
	return {
		"cultivation_state": cultivation_snapshot(state),
		"dialogue_open": state.dialogue_open,
		"tea_accepted": state.tea_accepted,
		"tea_seen": state.tea_seen.duplicate(true),
		"tea_stage_complete": state.tea_stage_complete,
		"tea_quest_complete": state.tea_quest_complete,
		"tea_action_done": state.tea_action_done.duplicate(true),
		"tea_active": state.tea_active,
		"tea_session": state.tea_session,
		"tea_read_counter": state._tea_read_counter,
		"pending_object_id": state._tea_pending_object_id,
		"pending_read_token": state._tea_pending_read_token,
	}

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func fixture_mark_full_quest_complete_after_both_cups(state) -> void:
	var both_cups_inspected: bool = state.tea_seen.has("tea.cup_first") and state.tea_seen.has("tea.cup_second")
	check(both_cups_inspected and state.tea_stage_complete and state.tea_active, "test fixture requires both inspected cups and completed stage")
	if both_cups_inspected and state.tea_stage_complete and state.tea_active:
		state.tea_quest_complete = true
	check(state.tea_quest_complete, "TEST FIXTURE ONLY: full quest is synthetic; current C-I gameplay is not implemented")

func test_direct_view_invalidates_legacy_read() -> void:
	var state = State.new()
	var session: int = state.begin_tea().session
	state.accept_tea(session)
	var pending: Dictionary = state.inspect_tea("tea.cup_second",session)
	check(state.view_tea("tea.cup_first",session).ok,"direct view supersedes a legacy pending read")
	check(not state.confirm_tea("tea.cup_second",session,pending.read_token).ok and state.tea_seen.size() == 1,"old pending read cannot commit after direct view")
