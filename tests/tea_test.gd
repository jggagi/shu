extends SceneTree

const State = preload("res://scripts/demo_state.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	test_unaccepted_and_activity_occupancy()
	test_both_cup_orders()
	test_return_gate_fixtures()
	test_pending_read_cancel_and_stale_tokens()
	test_progress_survives_day_and_reset_clears_it()
	print("TEA_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(failures)

func test_unaccepted_and_activity_occupancy() -> void:
	var state = State.new()
	var before := state_snapshot(state)
	var rejected := state.inspect_tea("tea.cup_first", 0)
	check(not rejected.ok and not state.tea_accepted, "unaccepted tea cannot be inspected")
	check(state_snapshot(state) == before, "rejected unaccepted inspection changes no state")
	check(state.can_return_from_tea(), "an unaccepted commission may return")
	check(not state.cancel_tea().ok and state_snapshot(state) == before, "inactive cancellation is rejected atomically")

	check(state.begin_dialogue().ok, "mentor dialogue opens before tea")
	var dialogue_session := state.begin_tea()
	check(not dialogue_session.ok and state.dialogue_open and not state.tea_active, "tea cannot begin during mentor dialogue")
	state.cancel_dialogue()

	var start := state.begin_tea()
	check(start.ok and state.tea_active, "tea session opens")
	var session := int(start.get("session", -1))
	check(not state.begin_tea().ok and state.tea_active, "second tea session cannot replace an active one")
	check(state.accept_tea(session).ok and state.tea_accepted, "tea can be accepted once")
	check(not state.confirm_tea("", session, 0).ok and state.tea_seen.is_empty(), "confirmation without an inspected read is rejected")
	check(not state.accept_tea(session).ok and state.tea_accepted, "duplicate acceptance does not unset or repeat acceptance")

	before = state_snapshot(state)
	check(not state.train().ok, "training is blocked during tea")
	check(not state.rest().ok, "ordinary rest is blocked during tea")
	check(not state.begin_dialogue().ok, "mentor dialogue is blocked during tea")
	state.dialogue_open = true
	check(not state.choose("breathing").ok and state.dialogue_open, "mentor choice is blocked during tea without releasing dialogue")
	state.dialogue_open = false
	check(state_snapshot(state) == before, "blocked actions during tea change no cultivation state")

	var early_finish := state.finish_tea(session)
	check(not early_finish.ok and state.tea_active and not state.tea_stage_complete, "finish before both clues is denied while tea stays active")
	var unknown := state.inspect_tea("tea.unknown", session)
	check(not unknown.ok and state.tea_seen.is_empty(), "unknown tea object is rejected")
	before = state_snapshot(state)
	check(not state.can_return_from_tea() and not state.cancel_tea().ok and state_snapshot(state) == before, "accepted incomplete quest cannot return or mutate state")

func test_both_cup_orders() -> void:
	check_cup_order("tea.cup_first", "tea.cup_second")
	check_cup_order("tea.cup_second", "tea.cup_first")

func check_cup_order(first_id: String, second_id: String) -> void:
	var state = State.new()
	var before_cultivation := cultivation_snapshot(state)
	var start := state.begin_tea()
	check(start.ok, "tea session opens for order %s then %s" % [first_id, second_id])
	var session := int(start.get("session", -1))
	check(state.accept_tea(session).ok, "acceptance opens clue access")

	var first_open := state.inspect_tea(first_id, session)
	check(first_open.ok and not state.tea_seen.has(first_id), "opening %s does not commit its clue" % first_id)
	var first_token := int(first_open.get("read_token", -1))
	var first_confirm := state.confirm_tea(first_id, session, first_token)
	check(first_confirm.ok and first_confirm.new_clue and state.tea_seen.has(first_id), "confirming %s commits one new clue" % first_id)
	check(not state.confirm_tea(first_id, session, first_token).ok, "the same read token cannot confirm twice")
	check(not state.finish_tea(session).ok and state.tea_active, "one clue is insufficient to finish the stage")

	var revisit := state.inspect_tea(first_id, session)
	var revisit_confirm := state.confirm_tea(first_id, session, int(revisit.get("read_token", -1)))
	check(revisit_confirm.ok and not revisit_confirm.new_clue, "revisiting %s does not add the clue twice" % first_id)

	var second_open := state.inspect_tea(second_id, session)
	var second_confirm := state.confirm_tea(second_id, session, int(second_open.get("read_token", -1)))
	check(second_confirm.ok and second_confirm.new_clue, "confirming %s commits the other clue" % second_id)
	check(state.tea_seen.size() == 2 and not state.tea_stage_complete, "legacy confirmation records both clues without finishing the stage")
	var completion := state.finish_tea(session)
	check(completion.ok and completion.new_completion and state.tea_stage_complete and not state.tea_quest_complete and state.tea_active, "legacy finish marks the stage only and keeps tea active")
	check(state.tea_session == session, "stage finish retains its active session")
	check(cultivation_snapshot(state) == before_cultivation, "tea investigation has no energy, time, or growth cost or gain")

	var duplicate_finish := state.finish_tea(session)
	check(duplicate_finish.ok and not duplicate_finish.new_completion and state.tea_active and not state.tea_quest_complete, "repeated stage finish is idempotent and does not complete the quest")
	var before_blocked_return := state_snapshot(state)
	check(not state.can_return_from_tea() and not state.cancel_tea().ok and state_snapshot(state) == before_blocked_return, "two-cup stage completion alone cannot return to cultivation")

	fixture_mark_full_quest_complete_after_both_cups(state)
	check(state.can_return_from_tea(), "test-only full-quest fixture unlocks the return gate")
	var pending := state.inspect_tea(first_id, session)
	var pending_token := int(pending.get("read_token", -1))
	check(state.cancel_tea().ok and not state.tea_active, "fixture-completed tea can return and releases occupancy")
	check(not state.confirm_tea(first_id, session, pending_token).ok, "permitted terminal return invalidates a pending legacy read")

	var replay := state.begin_tea()
	check(replay.ok, "completed test fixture can be revisited")
	var replay_session := int(replay.get("session", -1))
	check(not state.accept_tea(replay_session).ok and state.tea_accepted, "revisit does not accept the commission a second time")
	for object_id in [first_id, second_id]:
		var opened := state.inspect_tea(object_id, replay_session)
		var confirmed := state.confirm_tea(object_id, replay_session, int(opened.get("read_token", -1)))
		check(confirmed.ok and not confirmed.new_clue, "revisiting %s never repeats clue progression" % object_id)
	var replay_finish := state.finish_tea(replay_session)
	check(replay_finish.ok and not replay_finish.new_completion and state.tea_active, "revisited stage does not complete again or exit")
	check(state.cancel_tea().ok, "test fixture permits return after replay")

func test_return_gate_fixtures() -> void:
	var unaccepted := State.new()
	var unaccepted_start := unaccepted.begin_tea()
	var unaccepted_session := int(unaccepted_start.get("session", -1))
	var pending_before_acceptance := unaccepted.inspect_tea("tea.cup_first", unaccepted_session)
	check(not pending_before_acceptance.ok, "unaccepted commission cannot create a pending read")
	check(unaccepted.cancel_tea().ok and not unaccepted.tea_active, "unaccepted commission cancellation remains permitted")
	var after_unaccepted_return := state_snapshot(unaccepted)
	check(not unaccepted.cancel_tea().ok and state_snapshot(unaccepted) == after_unaccepted_return, "inactive cancellation rejects without changing state")

	var malformed := State.new()
	var malformed_session := int(malformed.begin_tea().get("session", -1))
	malformed.accept_tea(malformed_session)
	for object_id in ["tea.cup_first", "tea.cup_second"]:
		var opened := malformed.inspect_tea(object_id, malformed_session)
		malformed.confirm_tea(object_id, malformed_session, int(opened.get("read_token", -1)))
	check(malformed.tea_seen.size() == 2 and not malformed.tea_stage_complete, "malformed-state fixture has both inspected cups but no completed stage")
	malformed.tea_quest_complete = true
	var malformed_before := state_snapshot(malformed)
	check(not malformed.can_return_from_tea() and not malformed.cancel_tea().ok and state_snapshot(malformed) == malformed_before, "quest flag without stage completion fails closed")
	malformed.reset()
	check(not malformed.tea_quest_complete and not malformed.tea_active, "reset clears malformed quest flag and invalidates the session")

func test_pending_read_cancel_and_stale_tokens() -> void:
	var state = State.new()
	var first_start := state.begin_tea()
	var old_session := int(first_start.get("session", -1))
	check(state.accept_tea(old_session).ok, "acceptance is retained for callback test")
	var first_read := state.inspect_tea("tea.cup_first", old_session)
	var first_token := int(first_read.get("read_token", -1))
	var replacement_read := state.inspect_tea("tea.cup_second", old_session)
	var replacement_token := int(replacement_read.get("read_token", -1))
	check(not state.confirm_tea("tea.cup_first", old_session, first_token).ok and state.tea_seen.is_empty(), "superseded read callback is rejected")
	check(state.confirm_tea("tea.cup_second", old_session, replacement_token).new_clue, "current pending read can be confirmed")
	var direct_first := state.view_tea("tea.cup_first", old_session)
	var direct_second := state.view_tea("tea.cup_second", old_session)
	check(direct_first.ok and direct_second.ok and state.tea_stage_complete, "direct views complete only the current investigation stage")
	fixture_mark_full_quest_complete_after_both_cups(state)
	var terminal_read := state.inspect_tea("tea.cup_second", old_session)
	var terminal_token := int(terminal_read.get("read_token", -1))
	check(state.cancel_tea().ok, "full-quest test fixture permits terminal return")
	check(not state.confirm_tea("tea.cup_second", old_session, terminal_token).ok, "terminal return rejects its pending callback")

	var reopened := state.begin_tea()
	var new_session := int(reopened.get("session", -1))
	check(new_session > old_session, "reopened tea receives a newer session token")
	check(not state.inspect_tea("tea.cup_first", old_session).ok, "old session cannot inspect after tea reopens")
	check(not state.confirm_tea("tea.cup_second", old_session, terminal_token).ok, "old pending read cannot commit after tea reopens")
	check(state.inspect_tea("tea.cup_second", new_session).ok, "confirmed clue remains available on revisit")
	check(state.cancel_tea().ok, "revisited completed test fixture can return")

func test_progress_survives_day_and_reset_clears_it() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var session := int(start.get("session", -1))
	state.accept_tea(session)
	var first_view := state.view_tea("tea.cup_first", session)
	var second_view := state.view_tea("tea.cup_second", session)
	check(first_view.ok and second_view.ok and state.tea_stage_complete, "both direct views complete the local stage")
	fixture_mark_full_quest_complete_after_both_cups(state)
	check(state.cancel_tea().ok, "test-only full-quest fixture permits leaving the sidequest")

	for i in range(4):
		check(state.train().ok, "training is available after fixture-completed tea returns")
	check(state.day == 2 and state.time_index == 2, "training advances into the next day after permitted return")
	check(state.rest().ok, "ordinary rest is available after permitted return")
	check(state.tea_accepted and state.tea_seen.has("tea.cup_first") and state.tea_stage_complete and state.tea_quest_complete, "completed quest and clues survive cultivation and a day change")

	var reopened := state.begin_tea()
	var reopened_session := int(reopened.get("session", -1))
	var replay := state.view_tea("tea.cup_second", reopened_session)
	check(replay.ok and not replay.new_clue and not replay.new_completion, "revisited clue and stage do not repeat progression")
	var stale_read := state.inspect_tea("tea.cup_second", reopened_session)
	var stale_session := reopened_session
	var stale_token := int(stale_read.get("read_token", -1))

	state.reset()
	check(not state.tea_accepted and state.tea_seen.is_empty() and not state.tea_stage_complete and not state.tea_quest_complete and state.tea_action_done.is_empty() and not state.tea_active, "reset clears all tea progress and occupancy")
	check(state.day == 1 and state.energy == 100 and state.cultivation == 0, "reset keeps existing cultivation reset behavior")
	check(not state.confirm_tea("tea.cup_second", stale_session, stale_token).ok, "reset invalidates pending read from the old session")
	var after_reset := state.begin_tea()
	var fresh_session := int(after_reset.get("session", -1))
	check(fresh_session > stale_session and not state.inspect_tea("tea.cup_second", fresh_session).ok, "post-reset tea requires fresh acceptance and a fresh session")
	check(not state.confirm_tea("tea.cup_second", stale_session, stale_token).ok, "pre-reset read cannot commit after a new run begins")
	check(state.cancel_tea().ok, "unaccepted cancellation after reset remains permitted")

func fixture_mark_full_quest_complete_after_both_cups(state) -> void:
	var both_cups_inspected: bool = state.tea_seen.has("tea.cup_first") and state.tea_seen.has("tea.cup_second")
	check(both_cups_inspected and state.tea_stage_complete and state.tea_active, "test fixture requires both inspected cups and completed stage")
	if both_cups_inspected and state.tea_stage_complete and state.tea_active:
		state.tea_quest_complete = true
	check(state.tea_quest_complete, "TEST FIXTURE ONLY: full quest flag is set after both cups; live C-I gameplay is not implemented")

func cultivation_snapshot(state) -> Dictionary:
	return {
		"day": state.day,
		"time_index": state.time_index,
		"energy": state.energy,
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func state_snapshot(state) -> Dictionary:
	return {
		"cultivation": cultivation_snapshot(state),
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
