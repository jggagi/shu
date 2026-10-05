extends SceneTree

const State = preload("res://scripts/demo_state.gd")
var failures := 0

func _initialize() -> void:
	test_unaccepted_and_activity_occupancy()
	test_both_cup_orders()
	test_pending_read_cancel_and_stale_tokens()
	test_progress_survives_day_and_reset_clears_it()
	print("TEA_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)

func test_unaccepted_and_activity_occupancy() -> void:
	var state = State.new()
	var before := state_snapshot(state)
	var rejected := state.inspect_tea("tea.cup_first", 0)
	check(not rejected.ok and not state.tea_accepted, "unaccepted tea cannot be inspected")
	check(state_snapshot(state) == before, "rejected unaccepted inspection changes no state")

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
	check(not state.rest().ok, "rest is blocked during tea")
	check(not state.begin_dialogue().ok, "mentor dialogue is blocked during tea")
	state.dialogue_open = true
	check(not state.choose("breathing").ok and state.dialogue_open, "mentor choice is blocked during tea without releasing dialogue")
	state.dialogue_open = false
	check(state_snapshot(state) == before, "blocked actions during tea change no cultivation state")

	var early_finish := state.finish_tea(session)
	check(not early_finish.ok and state.tea_active and not state.tea_stage_complete, "finish before both clues is denied while tea stays active")
	var unknown := state.inspect_tea("tea.unknown", session)
	check(not unknown.ok and state.tea_seen.is_empty(), "unknown tea object is rejected")
	state.cancel_tea()

func test_both_cup_orders() -> void:
	check_cup_order("tea.cup_first", "tea.cup_second")
	check_cup_order("tea.cup_second", "tea.cup_first")

func check_cup_order(first_id: String, second_id: String) -> void:
	var state = State.new()
	var before := state_snapshot(state)
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
	check(not state.finish_tea(session).ok and state.tea_active, "one clue is insufficient to finish")

	var revisit := state.inspect_tea(first_id, session)
	var revisit_confirm := state.confirm_tea(first_id, session, int(revisit.get("read_token", -1)))
	check(revisit_confirm.ok and not revisit_confirm.new_clue, "revisiting %s does not add the clue twice" % first_id)

	var second_open := state.inspect_tea(second_id, session)
	var second_confirm := state.confirm_tea(second_id, session, int(second_open.get("read_token", -1)))
	check(second_confirm.ok and second_confirm.new_clue, "confirming %s commits the other clue" % second_id)
	check(state.tea_seen.size() == 2, "both cup clues are recorded")
	var completion := state.finish_tea(session)
	check(completion.ok and completion.new_completion and state.tea_stage_complete and not state.tea_active, "both clues complete the stage once and exit")
	check(state_snapshot(state) == before, "tea investigation has no energy, time, or growth cost or gain")

	var duplicate_finish := state.finish_tea(session)
	check(not duplicate_finish.ok, "finished session cannot complete again")
	var replay := state.begin_tea()
	check(replay.ok, "completed tea can be revisited")
	var replay_session := int(replay.get("session", -1))
	check(state.accept_tea(replay_session).ok == false and state.tea_accepted, "revisit does not accept the commission a second time")
	for object_id in [first_id, second_id]:
		var opened := state.inspect_tea(object_id, replay_session)
		var confirmed := state.confirm_tea(object_id, replay_session, int(opened.get("read_token", -1)))
		check(confirmed.ok and not confirmed.new_clue, "revisiting %s never repeats clue progression" % object_id)
	var replay_finish := state.finish_tea(replay_session)
	check(replay_finish.ok and not replay_finish.new_completion, "revisiting a completed stage cannot complete it twice")

func test_pending_read_cancel_and_stale_tokens() -> void:
	var state = State.new()
	var first_start := state.begin_tea()
	var old_session := int(first_start.get("session", -1))
	check(state.accept_tea(old_session).ok, "acceptance is retained for cancellation test")
	var first_read := state.inspect_tea("tea.cup_first", old_session)
	var first_token := int(first_read.get("read_token", -1))
	var replacement_read := state.inspect_tea("tea.cup_second", old_session)
	var replacement_token := int(replacement_read.get("read_token", -1))
	check(not state.confirm_tea("tea.cup_first", old_session, first_token).ok and state.tea_seen.is_empty(), "superseded read callback is rejected")
	check(state.confirm_tea("tea.cup_second", old_session, replacement_token).new_clue, "current pending read can be confirmed")
	state.cancel_tea()
	check(not state.tea_active and state.tea_accepted and state.tea_seen.has("tea.cup_second"), "cancel releases tea and retains accepted progress")
	check(not state.confirm_tea("tea.cup_second", old_session, replacement_token).ok, "cancel invalidates an outstanding session callback")

	var reopened := state.begin_tea()
	var new_session := int(reopened.get("session", -1))
	check(new_session > old_session, "reopened tea receives a newer session token")
	check(not state.inspect_tea("tea.cup_first", old_session).ok, "old session cannot inspect after tea reopens")
	check(not state.confirm_tea("tea.cup_second", old_session, replacement_token).ok, "old read cannot commit after tea reopens")
	check(state.inspect_tea("tea.cup_second", new_session).ok, "confirmed clue remains available on revisit")
	state.cancel_tea()

func test_progress_survives_day_and_reset_clears_it() -> void:
	var state = State.new()
	var start := state.begin_tea()
	var session := int(start.get("session", -1))
	state.accept_tea(session)
	var opened := state.inspect_tea("tea.cup_first", session)
	var confirmed := state.confirm_tea("tea.cup_first", session, int(opened.get("read_token", -1)))
	check(confirmed.ok and state.tea_seen.has("tea.cup_first"), "first clue commits before day advances")
	state.cancel_tea()

	for i in range(4):
		check(state.train().ok, "training remains available after tea cancellation")
	check(state.day == 2 and state.time_index == 2, "training advances into the next day")
	check(state.rest().ok, "rest remains available after tea cancellation")
	check(state.tea_accepted and state.tea_seen.has("tea.cup_first"), "accepted tea and confirmed clue survive training, rest, and a day change")

	var reopened := state.begin_tea()
	var reopened_session := int(reopened.get("session", -1))
	var second_open := state.inspect_tea("tea.cup_second", reopened_session)
	var second_confirm := state.confirm_tea("tea.cup_second", reopened_session, int(second_open.get("read_token", -1)))
	check(second_confirm.ok and state.finish_tea(reopened_session).ok, "remaining clue finishes after the day change")
	var stale_session := reopened_session
	var stale_token := int(second_open.get("read_token", -1))

	state.reset()
	check(not state.tea_accepted and state.tea_seen.is_empty() and not state.tea_stage_complete and not state.tea_active, "reset clears all tea progress and occupancy")
	check(state.day == 1 and state.energy == 100 and state.cultivation == 0, "reset keeps existing cultivation reset behavior")
	check(not state.confirm_tea("tea.cup_second", stale_session, stale_token).ok, "reset invalidates a completed session token")
	var after_reset := state.begin_tea()
	var fresh_session := int(after_reset.get("session", -1))
	check(fresh_session > stale_session and not state.inspect_tea("tea.cup_second", fresh_session).ok, "post-reset tea requires fresh acceptance and a fresh session")
	state.accept_tea(fresh_session)
	check(not state.confirm_tea("tea.cup_second", stale_session, stale_token).ok, "pre-reset read cannot commit after a new run begins")
	state.cancel_tea()

func state_snapshot(state) -> Dictionary:
	return {
		"day": state.day,
		"time_index": state.time_index,
		"energy": state.energy,
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
