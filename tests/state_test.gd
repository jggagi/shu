extends SceneTree

const State = preload("res://scripts/demo_state.gd")
var failures := 0

func _initialize() -> void:
	var state = State.new()
	check(state.train().ok and state.energy == 78 and state.cultivation == 12, "training settles once")
	check(state.rest().gain == 22 and state.energy == 100, "rest clamps energy")
	state.reset()
	check(state.begin_dialogue().ok, "dialogue opens")
	check(not state.train().ok and state.energy == 100, "dialogue blocks other actions")
	state.cancel_dialogue()
	check(state.energy == 100 and state.time_index == 0, "cancel has no cost")
	state.begin_dialogue()
	check(not state.choose("invalid").ok and state.dialogue_open, "invalid choice cannot settle")
	check(state.choose("breathing").ok and state.energy == 92 and state.lesson_bonus == 6, "mentor grants one bonus")
	check(not state.choose("breathing").ok and state.energy == 92 and state.understanding == 1, "duplicate choice cannot settle")
	check(state.train().gain == 18 and state.lesson_bonus == 0, "bonus consumed once")
	check(state.train().gain == 12, "following training gets base gain")
	state.reset()
	for i in range(4):
		state.train()
	var old_time: int = state.time_index
	var old_progress: int = state.cultivation
	check(not state.train().ok and state.energy == 12 and state.time_index == old_time and state.cultivation == old_progress, "low energy failure is atomic")
	check(state.day == 2 and state.time_index == 2, "time rolls into next day")
	state.rest()
	state.train()
	check(state.complete(), "first lesson is reachable")
	state.reset()
	check(state.day == 1 and state.energy == 100 and state.cultivation == 0 and state.understanding == 0 and not state.dialogue_open, "reset returns known initial state")
	print("STATE_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
