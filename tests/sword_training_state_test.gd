extends SceneTree

const State := preload("res://scripts/demo_state.gd")
const Catalog := preload("res://scripts/sword_manual_catalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	var state = State.new()
	_check_rule_contract(state)
	_check_repeated_training(state)
	_check_energy_boundary(state)
	_check_below_cost_is_atomic(state)
	_check_dialogue_and_tea_gates(state)
	_check_lesson_bonus_is_independent(state)
	_check_all_time_slots()
	_check_reset(state)
	print("SWORD_TRAINING_STATE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)

func _check_rule_contract(state) -> void:
	check(state.swordsmanship == 0, "swordsmanship starts at zero")
	check(state.rules.sword_training_cost == 22, "sword training costs the authored 22 energy")
	check(state.rules.sword_training_gain == 10, "sword training grants the authored 10 swordsmanship")
	check(state.rules.sword_training_duration == 1, "sword training advances one time slot")

func _check_repeated_training(state) -> void:
	var first: Dictionary = state.train_sword()
	var second: Dictionary = state.train_sword()
	check(first.ok and first.gain == 10, "the first valid sword training settles")
	check(second.ok and second.gain == 10, "a repeated valid sword training remains a separate action")
	check(state.energy == 56 and state.swordsmanship == 20, "two sword actions spend 44 energy and grant 20 swordsmanship")
	check(state.cultivation == 0 and state.understanding == 0 and state.lesson_bonus == 0, "sword training leaves cultivation and mentor progression alone")
	check(state.time_index == 2 and state.day == 1, "two sword actions advance two time slots")
	check(first == _receipt(1, 0, 0, 1, 10, 22, 0) and second == _receipt(1, 1, 10, 1, 20, 22, 1), "each accepted action returns its complete before-and-after receipt")

func _check_energy_boundary(state) -> void:
	state.reset()
	state.energy = int(state.rules.sword_training_cost)
	state.day = 2
	state.time_index = 4
	state.swordsmanship = 3
	var result: Dictionary = state.train_sword()
	check(result.ok and result.energy_cost == 22 and state.energy == 0, "exactly the required energy is sufficient")
	check(state.swordsmanship == 13 and result.gain == 10, "the exact-cost action grants the full swordsmanship gain")
	check(state.day == 2 and state.time_index == 5, "the exact-cost action advances one slot")
	check(result == _receipt(2, 4, 3, 2, 13, 22, 0), "the exact-cost action returns all receipt fields")

func _check_below_cost_is_atomic(state) -> void:
	state.reset()
	state.day = 5
	state.time_index = state.rules.times.size() - 1
	state.energy = int(state.rules.sword_training_cost) - 1
	state.cultivation = 31
	state.swordsmanship = 7
	state.understanding = 3
	state.lesson_bonus = 6
	state.tea_accepted = true
	state.tea_seen = {"tea.cup_first": true}
	state.tea_action_done = {"tea.cup_first": {"repair": true}}
	state.tea_story_seen = {"tea.memory": true}
	state._tea_read_counter = 8
	state._tea_pending_object_id = "tea.cup_first"
	state._tea_pending_read_token = 8
	var before := _script_variable_snapshot(state)
	check(before.has("rules") and before.has("swordsmanship") and before.has("_tea_read_counter") and before.has("_tea_pending_read_token") and before.has("_tea_story_source"), "the atomicity snapshot covers every script variable, including private Tea state")
	check(before.tea_action_done["tea.cup_first"].repair and before.tea_seen["tea.cup_first"], "the atomicity snapshot deep-copies nested Tea dictionaries")
	var result: Dictionary = state.train_sword()
	check(not result.ok and result.reason == "精力不足，暂时无法练剑。", "one energy below cost is rejected")
	check(_script_variable_snapshot(state) == before, "below-cost rejection preserves every script variable and nested value")

func _check_dialogue_and_tea_gates(state) -> void:
	state.reset()
	check(state.begin_dialogue().ok, "the dialogue guard fixture opens through DemoState")
	var dialogue_before := _script_variable_snapshot(state)
	var dialogue_result: Dictionary = state.train_sword()
	check(not dialogue_result.ok and dialogue_result.reason == "请先结束与师傅的对话。", "sword training is refused during mentor dialogue")
	check(_script_variable_snapshot(state) == dialogue_before, "dialogue rejection preserves every script variable")
	state.cancel_dialogue()

	var tea_start: Dictionary = state.begin_tea()
	check(tea_start.ok, "the Tea guard fixture starts through DemoState")
	var tea_before := _script_variable_snapshot(state)
	var tea_result: Dictionary = state.train_sword()
	check(not tea_result.ok and tea_result.reason == "请先结束茶事调查。", "sword training is refused during an active Tea branch")
	check(_script_variable_snapshot(state) == tea_before, "Tea rejection preserves every script variable")
	check(state.cancel_tea().ok, "the unaccepted Tea fixture can be closed")

func _check_lesson_bonus_is_independent(state) -> void:
	state.reset()
	state.lesson_bonus = int(state.rules.lesson_bonus)
	var sword_result: Dictionary = state.train_sword()
	check(sword_result.ok and state.energy == 78 and state.swordsmanship == 10, "sword training settles its own energy and skill result")
	check(state.cultivation == 0 and state.lesson_bonus == 6, "sword training retains the pending breathing bonus without adding cultivation")
	var breathing_result: Dictionary = state.train()
	check(breathing_result.ok and breathing_result.gain == 18, "the next breathing action consumes the retained bonus normally")
	check(state.swordsmanship == 10 and state.cultivation == 18 and state.lesson_bonus == 0, "breathing progression remains distinct from swordsmanship")
	var base_result: Dictionary = state.train()
	check(base_result.ok and base_result.gain == 12 and state.cultivation == 30, "later breathing training returns to its authored base gain")
	check(state.swordsmanship == 10 and state.lesson_bonus == 0, "subsequent breathing training does not change swordsmanship or recreate the bonus")

func _check_all_time_slots() -> void:
	var slot_count: int = int(State.new().rules.times.size())
	for slot in range(slot_count):
		var state = State.new()
		state.day = 3
		state.time_index = slot
		state.energy = 100
		state.swordsmanship = 20 + slot
		state.cultivation = 11
		state.understanding = 2
		state.lesson_bonus = 6
		state.tea_accepted = true
		state.tea_seen = {"tea.cup_second": true}
		state.tea_action_done = {"tea.cup_first": {"repair": true}}
		var before := _script_variable_snapshot(state)
		var expected_day_after: int = 3 + (1 if slot == slot_count - 1 else 0)
		var expected_time_after: int = (slot + 1) % slot_count
		var result: Dictionary = state.train_sword()
		check(result.ok, "sword training is available from cultivation time slot %d" % slot)
		check(state.day == expected_day_after and state.time_index == expected_time_after, "time slot %d advances exactly one slot with the expected day rollover" % slot)
		check(result.day_before == 3 and result.time_index_before == slot and result.day_after == expected_day_after and result.time_index_after == expected_time_after, "time slot %d receipt records its exact clock transition" % slot)
		check(state.swordsmanship == 30 + slot and result.swordsmanship_before == 20 + slot and result.swordsmanship_after == 30 + slot, "time slot %d grants only the authored swordsmanship gain" % slot)
		check(state.energy == 78 and result.energy_cost == 22 and result.duration == 1, "time slot %d uses the authored cost and duration" % slot)
		var before_unrelated := _snapshot_without(before, ["day", "time_index", "energy", "swordsmanship", "sword_manual_practice_counts"])
		var after_unrelated := _snapshot_without(_script_variable_snapshot(state), ["day", "time_index", "energy", "swordsmanship", "sword_manual_practice_counts"])
		check(after_unrelated == before_unrelated, "time slot %d leaves every unrelated cultivation and Tea field unchanged" % slot)
		check(state.sword_manual_practice_counts.get(state.selected_sword_manual_id, 0) == 1, "time slot %d increments the selected manual count once" % slot)

func _check_reset(state) -> void:
	state.swordsmanship = 40
	state.cultivation = 50
	state.energy = 4
	state.reset()
	check(state.swordsmanship == 0, "reset clears swordsmanship")
	check(state.selected_sword_manual_id == Catalog.DEFAULT_ID, "reset restores the default sword manual")
	for entry: Dictionary in Catalog.manuals():
		check(state.sword_manual_practice_counts.get(str(entry.id), -1) == 0, "reset clears practice count for %s" % str(entry.id))
	check(state.energy == 100 and state.cultivation == 0 and state.day == 1 and state.time_index == 0, "reset preserves the existing cultivation reset behavior")

func _receipt(day_before: int, time_index_before: int, swordsmanship_before: int, day_after: int, swordsmanship_after: int, energy_cost: int, practice_count_before: int) -> Dictionary:
	var manual: Dictionary = Catalog.manual(Catalog.DEFAULT_ID)
	var technique: Dictionary = Catalog.technique(Catalog.DEFAULT_ID, practice_count_before)
	return {
		"ok": true,
		"gain": 10,
		"energy_cost": energy_cost,
		"duration": 1,
		"day_before": day_before,
		"time_index_before": time_index_before,
		"day_after": day_after,
		"time_index_after": (time_index_before + 1) % 6,
		"swordsmanship_before": swordsmanship_before,
		"swordsmanship_after": swordsmanship_after,
		"manual_id": Catalog.DEFAULT_ID,
		"manual_title": str(manual.get("title", "")),
		"technique_id": str(technique.get("id", "")),
		"technique_title": str(technique.get("title", "")),
		"result_text": str(technique.get("result_text", "")),
		"practice_count_before": practice_count_before,
		"practice_count_after": practice_count_before + 1,
	}

func _script_variable_snapshot(state) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_info in state.get_property_list():
		if (int(property_info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property_info.name)
		var value: Variant = state.get(name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		snapshot[name] = value
	return snapshot

func _snapshot_without(snapshot: Dictionary, excluded: Array) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for key in excluded:
		result.erase(str(key))
	return result

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
