extends SceneTree

const State = preload("res://scripts/demo_state.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	test_scene_and_progress_gates()
	test_c_prerequisite_and_completion()
	test_scene_switch_invalidates_old_callbacks()
	test_rest_preserves_flags_in_both_scenes()
	test_reset_clears_c_and_rejects_old_session()
	test_nonterminal_c_cannot_return()
	print("TEA_C_STATE_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(failures)

func test_scene_and_progress_gates() -> void:
	var state = State.new()
	check(state.tea_scene_id == State.TEA_TERRACE_ID, "new state starts on the sword terrace")
	check(state.tea_c_seen.is_empty() and not state.tea_c_complete, "new state has no C clues or completion")
	var start: Dictionary = state.begin_tea()
	var session := int(start.session)
	var before := full_snapshot(state)
	check(not state.switch_tea_scene(State.TEA_COURTYARD_ID, session).ok and full_snapshot(state) == before, "courtyard is unavailable before accepting and completing A/B")
	check(state.accept_tea(session).ok, "the active tea session accepts its commission")
	var accepted_snapshot := full_snapshot(state)
	check(not state.switch_tea_scene(State.TEA_COURTYARD_ID, session).ok and full_snapshot(state) == accepted_snapshot, "courtyard stays unavailable until A/B is complete")
	var invalid_destination: Dictionary = state.switch_tea_scene("tea.unknown_scene", session)
	check(not invalid_destination.ok and full_snapshot(state) == accepted_snapshot, "unknown scene is rejected without state changes")
	var same_scene: Dictionary = state.switch_tea_scene(State.TEA_TERRACE_ID, session)
	check(same_scene.ok and int(same_scene.session) == session and same_scene.new_scene == State.TEA_TERRACE_ID, "switching to the current scene keeps its session")
	var numbers := numeric_snapshot(state)
	complete_ab(state, session)
	check(state.tea_stage_complete and not state.tea_quest_complete, "A/B completion remains separate from whole-quest completion")
	check(numeric_snapshot(state) == numbers, "A/B direct views do not change cultivation values or time")
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	check(enter.ok and enter.new_scene == State.TEA_COURTYARD_ID and int(enter.session) > session, "completed A/B permits entry and advances the scene session")
	check(state.tea_active and state.tea_accepted, "scene transition keeps the accepted tea branch active")
	check(numeric_snapshot(state) == numbers, "scene transition does not change cultivation values or time")

func test_c_prerequisite_and_completion() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	var before := full_snapshot(state)
	check(not state.view_tea_c("tea.household", session).ok and full_snapshot(state) == before, "C objects cannot be viewed on the terrace")
	complete_ab(state, session)
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(enter.session)
	var numbers := numeric_snapshot(state)
	before = full_snapshot(state)
	check(not state.view_tea_c("tea.unknown", session).ok and full_snapshot(state) == before, "unknown C object is rejected atomically")
	check(not state.view_tea_c("tea.ledger", session).ok and full_snapshot(state) == before, "ledger is locked until the household clue is seen")
	var household: Dictionary = state.view_tea_c("tea.household", session)
	check(household.ok and household.new_clue and not household.new_completion, "household clue is recorded without completing C")
	check(not state.tea_c_complete and state.tea_stage_complete, "household clue leaves C incomplete and preserves A/B completion")
	check(numeric_snapshot(state) == numbers, "C inspection does not change cultivation values or time")
	var repeated_household: Dictionary = state.view_tea_c("tea.household", session)
	check(repeated_household.ok and not repeated_household.new_clue and not repeated_household.new_completion, "rereading the household clue does not repeat progress")
	for object_id in ["tea.coats", "tea.medicine_pot", "tea.window"]:
		var minor: Dictionary = state.view_tea_c(object_id, session)
		check(minor.ok and minor.new_clue and not minor.new_completion, "%s is an optional C clue" % object_id)
	var ledger: Dictionary = state.view_tea_c("tea.ledger", session)
	check(ledger.ok and ledger.new_clue and ledger.new_completion, "ledger completes C after the household clue")
	check(state.tea_c_complete and state.tea_stage_complete and not state.tea_quest_complete, "C completion does not complete the quest")
	var repeated_ledger: Dictionary = state.view_tea_c("tea.ledger", session)
	check(repeated_ledger.ok and not repeated_ledger.new_clue and not repeated_ledger.new_completion, "rereading the ledger cannot complete C twice")
	check(numeric_snapshot(state) == numbers, "all C clue reads leave resources and time unchanged")
	var back: Dictionary = state.switch_tea_scene(State.TEA_TERRACE_ID, session)
	session = int(back.session)
	check(back.ok and state.tea_c_complete and state.tea_c_seen.has("tea.household") and state.tea_c_seen.has("tea.ledger"), "switching back to the terrace retains C progress")
	var forward: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(forward.session)
	var replay_household: Dictionary = state.view_tea_c("tea.household", session)
	var replay_ledger: Dictionary = state.view_tea_c("tea.ledger", session)
	check(forward.ok and replay_household.ok and replay_ledger.ok and not replay_household.new_clue and not replay_ledger.new_completion, "returning to the courtyard does not replay C progress")

func test_scene_switch_invalidates_old_callbacks() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	complete_ab(state, session)
	var pending: Dictionary = state.inspect_tea("tea.cup_first", session)
	check(pending.ok, "legacy inspection can be pending before a scene switch")
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	var courtyard_session := int(enter.session)
	check(enter.ok and courtyard_session != session, "actual scene change issues a replacement session")
	check(not state.confirm_tea("tea.cup_first", session, int(pending.read_token)).ok, "confirmation from the previous scene session is stale")
	var before := full_snapshot(state)
	check(not state.view_tea("tea.cup_first", session).ok and full_snapshot(state) == before, "stale A/B view is rejected atomically")
	check(not state.inspect_tea("tea.cup_first", courtyard_session).ok and full_snapshot(state) == before, "A/B inspect rejects terrace props in the courtyard")
	check(not state.view_tea("tea.cup_first", courtyard_session).ok and full_snapshot(state) == before, "A/B direct view rejects terrace props in the courtyard")
	check(not state.execute_tea_action("tea.cup_first", "ask_mentor", courtyard_session).ok and full_snapshot(state) == before, "A/B action rejects terrace props in the courtyard")
	check(not state.confirm_tea("tea.cup_first", courtyard_session, int(pending.read_token)).ok and full_snapshot(state) == before, "old read token cannot confirm in the courtyard")
	check(not state.switch_tea_scene(State.TEA_TERRACE_ID, session).ok and full_snapshot(state) == before, "stale callback cannot switch scenes")
	var back: Dictionary = state.switch_tea_scene(State.TEA_TERRACE_ID, courtyard_session)
	check(back.ok and back.new_scene == State.TEA_TERRACE_ID and int(back.session) > courtyard_session, "switching back to the terrace creates a fresh session")
	check(state.tea_active and state.tea_accepted and state.tea_stage_complete, "switching back retains the accepted A/B progress")
	var forward: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, int(back.session))
	check(forward.ok and int(forward.session) > int(back.session), "switching forward again creates another fresh session")

func test_rest_preserves_flags_in_both_scenes() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	state.view_tea("tea.cup_first", session)
	state.day = 4
	state.time_index = state.rules.times.size() - 1
	state.energy = int(state.rules.energy_max) - 5
	var terrace_rest: Dictionary = state.rest_tea(session)
	check(terrace_rest.ok and terrace_rest.gain == 5, "rest works on the terrace and reports actual energy gain")
	check(state.day == 5 and state.time_index == 0, "terrace rest advances across the day boundary")
	check(state.tea_seen.has("tea.cup_first") and not state.tea_stage_complete, "terrace rest retains partial A/B clues")
	state.view_tea("tea.cup_second", session)
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(enter.session)
	state.view_tea_c("tea.household", session)
	state.energy = int(state.rules.energy_max) - 5
	state.day = 8
	state.time_index = state.rules.times.size() - 1
	var courtyard_rest: Dictionary = state.rest_tea(session)
	check(courtyard_rest.ok and courtyard_rest.gain == 5, "rest works in the courtyard and reports actual energy gain")
	check(state.day == 9 and state.time_index == 0, "courtyard rest advances across the day boundary")
	check(state.tea_active and state.tea_accepted and state.tea_stage_complete, "courtyard rest keeps the active branch and A/B flags")
	check(state.tea_c_seen.has("tea.household") and not state.tea_c_complete, "courtyard rest retains C clues and completion state")

func test_reset_clears_c_and_rejects_old_session() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	complete_ab(state, session)
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	var old_session := int(enter.session)
	state.view_tea_c("tea.household", old_session)
	state.view_tea_c("tea.ledger", old_session)
	check(state.tea_c_complete, "fixture reaches C completion before reset")
	state.reset()
	check(state.tea_scene_id == State.TEA_TERRACE_ID, "reset returns the active scene to the terrace")
	check(state.tea_c_seen.is_empty() and not state.tea_c_complete, "reset clears C clues and completion")
	check(not state.tea_active and not state.tea_accepted and state.tea_seen.is_empty() and not state.tea_stage_complete and not state.tea_quest_complete, "reset clears A/B and whole-quest flags")
	var before := full_snapshot(state)
	check(not state.view_tea_c("tea.household", old_session).ok and full_snapshot(state) == before, "reset rejects old C view callbacks")
	check(not state.switch_tea_scene(State.TEA_COURTYARD_ID, old_session).ok and full_snapshot(state) == before, "reset rejects old scene-switch callbacks")
	check(not state.rest_tea(old_session).ok and full_snapshot(state) == before, "reset rejects old rest callbacks")
	var fresh: Dictionary = state.begin_tea()
	check(int(fresh.session) > old_session, "reset invalidates the old generation before a new session")
	before = full_snapshot(state)
	check(not state.view_tea("tea.cup_first", old_session).ok and full_snapshot(state) == before, "old terrace view stays stale in the new run")

func test_nonterminal_c_cannot_return() -> void:
	var state = State.new()
	var session := begin_accepted_ab(state)
	complete_ab(state, session)
	var enter: Dictionary = state.switch_tea_scene(State.TEA_COURTYARD_ID, session)
	session = int(enter.session)
	state.view_tea_c("tea.household", session)
	state.view_tea_c("tea.ledger", session)
	check(state.tea_c_complete and not state.tea_quest_complete, "C is complete while the whole quest remains unfinished")
	var before := full_snapshot(state)
	check(not state.can_return_from_tea() and not state.cancel_tea().ok and full_snapshot(state) == before, "completed nonterminal C cannot return to cultivation")

func begin_accepted_ab(state) -> int:
	var start: Dictionary = state.begin_tea()
	var session := int(start.session)
	state.accept_tea(session)
	return session

func complete_ab(state, session: int) -> void:
	state.view_tea("tea.cup_first", session)
	state.view_tea("tea.cup_second", session)

func numeric_snapshot(state) -> Dictionary:
	return {
		"day": state.day,
		"time_index": state.time_index,
		"energy": state.energy,
		"cultivation": state.cultivation,
		"understanding": state.understanding,
		"lesson_bonus": state.lesson_bonus,
	}

func full_snapshot(state) -> Dictionary:
	return {
		"numeric": numeric_snapshot(state),
		"tea_accepted": state.tea_accepted,
		"tea_seen": state.tea_seen.duplicate(true),
		"tea_stage_complete": state.tea_stage_complete,
		"tea_quest_complete": state.tea_quest_complete,
		"tea_scene_id": state.tea_scene_id,
		"tea_c_seen": state.tea_c_seen.duplicate(true),
		"tea_c_complete": state.tea_c_complete,
		"tea_action_done": state.tea_action_done.duplicate(true),
		"tea_active": state.tea_active,
		"tea_session": state.tea_session,
		"read_counter": state._tea_read_counter,
		"pending_object_id": state._tea_pending_object_id,
		"pending_read_token": state._tea_pending_read_token,
	}

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
