extends SceneTree

const State = preload("res://scripts/demo_state.gd")
const STAGE_IDS := ["late_dates", "medical", "letter", "memory", "records", "last_day", "official_notice", "cups_return"]

var failures := 0
var checks := 0

func _initialize() -> void:
	test_stage_c_gate_rest_and_reset()
	await test_full_story_and_ending()
	print("TEA_FULL_STATE_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(failures)

func test_stage_c_gate_rest_and_reset() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	check(state.story_stage().get("id", "") == "late_dates", "the full-chain source exposes C as stage zero")
	check(not state.read_tea_story("tea.household", session).ok, "the paginated reader is unavailable during C")
	state.view_tea("tea.cup_first", session)
	state.view_tea("tea.cup_second", session)
	var entered: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(entered.session)
	check(not state.advance_tea_story(session).ok, "A/B completion alone cannot advance beyond C")
	check(state.view_tea_c("tea.household", session).ok, "C household clue is recorded")
	var c_seen_before_rest: Dictionary = state.tea_c_seen.duplicate(true)
	var rest: Dictionary = state.rest_tea(session)
	check(rest.ok and state.tea_active and state.tea_scene_id == State.TEA_COURTYARD_ID, "rest retains the branch and C scene")
	check(state.tea_c_seen == c_seen_before_rest and not state.tea_c_complete, "rest preserves partial C progress")
	check(not state.advance_tea_story(session).ok, "partial C cannot advance")
	check(state.view_tea_c("tea.ledger", session).ok and state.tea_c_complete, "the existing C API completes C from household plus ledger")
	var wrong_scene: Dictionary = state.switch_tea_scene(State.TEA_TERRACE_ID, session)
	var wrong_scene_session := int(wrong_scene.session)
	var wrong_scene_before := state_snapshot(state)
	check(not state.advance_tea_story(wrong_scene_session).ok and state_snapshot(state) == wrong_scene_before, "a completed stage cannot advance from the wrong scene")
	var return_to_courtyard: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, wrong_scene_session)
	session = int(return_to_courtyard.session)
	var c_advance: Dictionary = state.advance_tea_story(session)
	session = int(c_advance.session)
	check(c_advance.ok and state.story_stage().get("id", "") == "medical", "completed C advances into D")
	check(state.tea_scene_id == State.TEA_COURTYARD_ID and not state.tea_quest_complete, "C to D remains in the courtyard and does not finish the quest")

	var scene_read: Dictionary = state.read_tea_story("tea.medical_early", session)
	var terrace: Dictionary = state.switch_tea_scene(State.TEA_TERRACE_ID, session)
	check(terrace.ok and state.tea_story_object == "", "changing scenes closes a live story read")
	check(not state.turn_tea_story("tea.medical_early", session, int(scene_read.read_token)).ok, "a page callback from before a scene switch is stale")
	var courtyard: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, int(terrace.session))
	session = int(courtyard.session)
	check(courtyard.ok and state.story_stage().get("id", "") == "medical", "returning to the courtyard retains the current story stage")

	var first_read: Dictionary = state.read_tea_story("tea.medical_early", session)
	check(first_read.ok and first_read.page_index == 0 and first_read.page_count == 2, "D opens its first authored page")
	var stale_token := int(first_read.read_token)
	var before_rest := state_snapshot(state)
	var story_rest: Dictionary = state.rest_tea(session)
	check(story_rest.ok and state.tea_story_object == "" and state.tea_story_page == 0, "rest closes a live paginated read")
	check(not state.turn_tea_story("tea.medical_early", session, stale_token).ok, "rest invalidates the previous page-turn token")
	check(not state.tea_story_seen.has("tea.medical_early") and state.tea_story_stage == 1, "rest does not commit a partially read document or change its stage")
	check(before_rest["seen"] == state.tea_story_seen, "rest preserves previously committed story clues")

	var reread: Dictionary = state.read_tea_story("tea.medical_early", session)
	check(reread.ok and int(reread.read_token) > stale_token, "reopening an item gets a new monotonically increasing token")
	var reset_token := int(reread.read_token)
	var reset_session := session
	state.reset()
	check(state.tea_story_stage == 0 and state.tea_story_seen.is_empty(), "reset clears full-chain stage and seen items")
	check(state.tea_story_page == 0 and state.tea_story_object == "" and state.tea_ending_step == 0, "reset clears active reading and ending state")
	check(state.tea_story_token > reset_token, "reset invalidates the live story token without resetting its counter")
	var post_reset := state_snapshot(state)
	check(not state.turn_tea_story("tea.medical_early", reset_session, reset_token).ok and state_snapshot(state) == post_reset, "a pre-reset page callback cannot progress the new run")

func test_full_story_and_ending() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	state.view_tea("tea.cup_first", session)
	state.view_tea("tea.cup_second", session)
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(enter.session)
	state.view_tea_c("tea.household", session)
	state.view_tea_c("tea.ledger", session)
	var advance_c: Dictionary = state.advance_tea_story(session)
	check(advance_c.ok, "C completion opens the full-chain sequence")
	session = int(advance_c.session)
	var numeric_before_story := numeric_snapshot(state)
	var prereq_items := {
		"medical": "tea.medical_habits",
		"letter": "tea.letter",
		"records": "tea.record_last",
		"official_notice": "tea.notice_cups",
	}
	for stage_index in range(1, 7):
		var stage: Dictionary = state.story_stage()
		var stage_id := str(stage.get("id", ""))
		check(stage_id == STAGE_IDS[stage_index], "source stage order is %s" % STAGE_IDS[stage_index])
		if prereq_items.has(stage_id):
			var locked_before := state_snapshot(state)
			var locked: Dictionary = state.read_tea_story(str(prereq_items[stage_id]), session)
			check(not locked.ok and state_snapshot(state) == locked_before, "%s prerequisites reject out-of-order reading atomically" % stage_id)
		var items: Array = stage.get("items", [])
		for item_value in items:
			var object_id := str(item_value)
			var opened: Dictionary = state.read_tea_story(object_id, session)
			check(opened.ok and int(opened.page_index) == 0 and int(opened.page_count) > 0, "%s opens page zero for %s" % [stage_id, object_id])
			var current := opened
			while int(current.page_index) < int(current.page_count) - 1:
				current = state.turn_tea_story(object_id, session, int(current.read_token))
				check(current.ok, "%s advances an authored page for %s" % [stage_id, object_id])
			check(bool(state.tea_story_seen.get(object_id, false)), "%s commits %s only after the final page" % [stage_id, object_id])
			if object_id == "tea.medical_early":
				var duplicate_before := state_snapshot(state)
				var last_page: Dictionary = state.turn_tea_story(object_id, session, int(current.read_token))
				check(not last_page.ok and state_snapshot(state) == duplicate_before, "turning beyond a document's last page is rejected without changes")
		check(numeric_snapshot(state) == numeric_before_story, "%s reading does not change cultivation numbers or time" % stage_id)
		check(state.story_stage_complete(), "%s completes when every required item is read" % stage_id)
		var advanced: Dictionary = state.advance_tea_story(session)
		check(advanced.ok, "%s advances exactly one stage" % stage_id)
		session = int(advanced.session)
		check(state.tea_story_stage == stage_index + 1, "%s advances to the next source index" % stage_id)
		check(not state.tea_quest_complete, "%s remains nonterminal" % stage_id)
		if stage_index < 6:
			check(state.tea_scene_id == State.TEA_COURTYARD_ID, "%s keeps the courtyard scene" % stage_id)
		else:
			check(state.tea_scene_id == State.TEA_TERRACE_ID, "official notice returns the story to the ending terrace")
	check(state.story_stage().get("id", "") == STAGE_IDS[7], "the last source stage is cups_return")
	check(state.tea_story_stage == 7 and not state.story_stage_complete(), "the ending starts with neither returned cup inspected")
	check(numeric_snapshot(state) == numeric_before_story, "all D-I story progress preserves core cultivation state")
	var blocked_train_before := numeric_snapshot(state)
	check(not state.train().ok and not state.begin_dialogue().ok, "cultivation and mentor actions remain blocked before terminal return")
	check(numeric_snapshot(state) == blocked_train_before and state.tea_active, "blocked core actions leave the active story untouched")
	var old_action_before := state_snapshot(state)
	check(not state.execute_tea_action("tea.cup_first", "repair", session).ok and state_snapshot(state) == old_action_before, "legacy A/B actions are rejected during the ending")

	var no_read_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_first", session, state.tea_story_token).ok and state_snapshot(state) == no_read_before, "ending cannot fill a cup without its active read")
	var first_cup: Dictionary = state.read_tea_story("tea.cup_first", session)
	check(first_cup.ok and state.tea_story_seen.has("tea.cup_first"), "the one-page first cup completes on open")
	var uninspected_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_first", session, int(first_cup.read_token)).ok and state_snapshot(state) == uninspected_before, "first fill waits until both ending cups have been inspected")
	var second_cup: Dictionary = state.read_tea_story("tea.cup_second", session)
	check(second_cup.ok and not state.tea_story_seen.has("tea.cup_second"), "the second ending cup remains unseen until its final page")
	var second_last: Dictionary = state.turn_tea_story("tea.cup_second", session, int(second_cup.read_token))
	check(second_last.ok and second_last.page_index == 1 and state.tea_story_seen.has("tea.cup_second"), "turning to the second cup's last page commits its inspection")
	check(state.story_stage_complete(), "both ending cups complete the terminal story stage")
	var out_of_order_second_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_second", session, int(second_last.read_token)).ok and state_snapshot(state) == out_of_order_second_before, "the second fill cannot happen before the first")
	var wrong_cup_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_first", session, int(second_last.read_token)).ok and state_snapshot(state) == wrong_cup_before, "a read token cannot be used for the other cup")
	var reopen_first: Dictionary = state.read_tea_story("tea.cup_first", session)
	check(reopen_first.ok and int(reopen_first.read_token) > int(second_last.read_token), "reopening the first cup gets a fresh read token")
	var first_fill: Dictionary = state.fill_tea_cup("tea.cup_first", session, int(reopen_first.read_token))
	check(first_fill.ok and int(first_fill.ending_step) == 1, "the first ending action fills only the first cup")
	check(state.tea_ending_step == 1 and not state.tea_quest_complete, "first fill is nonterminal and does not return to cultivation")
	var stale_fill_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_first", session, int(reopen_first.read_token)).ok and state_snapshot(state) == stale_fill_before, "first fill invalidates its read and cannot be repeated")
	var reopened_first: Dictionary = state.read_tea_story("tea.cup_first", session)
	var out_of_order_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_first", session, int(reopened_first.read_token)).ok and state_snapshot(state) == out_of_order_before, "reopening the terminal stage does not reset or replay first fill")
	state.close_tea_story()
	check(not state.turn_tea_story("tea.cup_first", session, int(reopened_first.read_token)).ok, "closing a story view invalidates its page callback")

	var final_read: Dictionary = state.read_tea_story("tea.cup_second", session)
	var final_page: Dictionary = state.turn_tea_story("tea.cup_second", session, int(final_read.read_token))
	check(final_page.ok, "the second cup can be reopened for the delayed ending action")
	var early_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_second", session, int(final_page.read_token)).ok and state_snapshot(state) == early_before, "the second fill is rejected before the pause elapses")
	# SceneTreeTimer is scaled game time; the host gate uses monotonic wall time.
	var pause_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - pause_started < State.TEA_STORY_ENDING_DELAY_MSEC + 50:
		await create_timer(0.02).timeout
	var second_fill: Dictionary = state.fill_tea_cup("tea.cup_second", session, int(final_page.read_token))
	check(second_fill.ok and int(second_fill.ending_step) == 2, "the second cup fills after the required monotonic pause")
	check(state.tea_ending_step == 2 and state.tea_quest_complete and state.can_return_from_tea(), "the second fill alone completes the whole quest")
	var terminal_reopen: Dictionary = state.read_tea_story("tea.cup_second", session)
	check(terminal_reopen.ok and state.tea_ending_step == 2, "reopening the terminal cup does not replay or reset the ending")
	var duplicate_ending_before := state_snapshot(state)
	check(not state.fill_tea_cup("tea.cup_second", session, int(terminal_reopen.read_token)).ok and state_snapshot(state) == duplicate_ending_before, "terminal fill cannot be repeated")
	check(not state.advance_tea_story(session).ok and state.tea_story_stage == 7, "terminal stage cannot advance past the ending")
	check(state.cancel_tea().ok and not state.tea_active, "only the completed quest returns from the branch")
	check(state.train().ok and state.begin_dialogue().ok, "training and mentor interaction resume after terminal return")
	check(state.choose("breathing").ok, "mentor behavior remains available after return")

func begin_accepted_ab(state) -> int:
	var started: Dictionary = state.begin_tea()
	var session := int(started.session)
	state.accept_tea(session)
	return session

func numeric_snapshot(state) -> Dictionary:
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
		"numeric": numeric_snapshot(state),
		"session": state.tea_session,
		"active": state.tea_active,
		"accepted": state.tea_accepted,
		"scene": state.tea_scene_id,
		"stage": state.tea_story_stage,
		"seen": state.tea_story_seen.duplicate(true),
		"c_seen": state.tea_c_seen.duplicate(true),
		"c_complete": state.tea_c_complete,
		"quest_complete": state.tea_quest_complete,
		"page": state.tea_story_page,
		"object": state.tea_story_object,
		"token": state.tea_story_token,
		"ending_step": state.tea_ending_step,
	}

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
