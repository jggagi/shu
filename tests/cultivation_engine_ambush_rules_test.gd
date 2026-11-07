extends SceneTree

const Rules = preload("res://addons/cultivation_mode/ambush_rules.gd")
var checks := 0
var failures := 0
var base: Dictionary = {}


func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_mountain_ambush/encounter.json"))
	# Preserve all pre-barricade assertions as the optional-data legacy fixture.
	# The shipped barricade encounter has its own state/API regression suite.
	base.erase("barricades")
	var model = _fresh()
	_check(model.snapshot().units.size() == 5 and model.snapshot().objective.name == "药篓", "Exactly two allies, three enemies and a separate static objective")
	var copy: Dictionary = model.snapshot()
	copy.units[0].hp = 0
	var copied_unit: Dictionary = model.unit("player")
	copied_unit.pos[0] = 0
	_check(model.unit("player").hp == 22 and model.unit("player").pos == [3, 3], "Public reads cannot mutate rules")
	var before: Dictionary = model.snapshot()
	_check(not model.move_unit("player", [4, 3]).ok and model.snapshot() == before, "Occupied movement fails atomically")
	_check(not model.move_unit("player", [3.5, 3]).ok and model.snapshot() == before, "Fractional movement fails atomically")
	_check(not model.move_unit("enemy_missing", [3, 2]).ok and model.snapshot() == before, "Unknown actor fails atomically")
	_check(not model.use_skill("player", "interrupt", [4, 3]).ok and model.snapshot() == before, "Unknown learned skill fails atomically")
	_check(not model.use_skill("player", "push", [7, 1]).ok and model.snapshot() == before, "Distant attack fails atomically")
	_check(not [4, 2] in model.reachable("player") and not [2, 2] in model.reachable("player"), "Goal and rocks block movement")
	var forecast: Dictionary = model.preview("player", "push", [4, 3])
	_check(forecast.ok and forecast.push_to == [6, 3] and forecast.damage == 3 and model.snapshot() == before, "Push preview is read only and predicts two real cells")
	var brute_plan := _plan(model, "brute")
	_check([4, 2] in brute_plan.cells, "Brute immediately threatens medicine")
	_check(model.use_skill("player", "push", [4, 3]).ok and model.unit("brute").pos == forecast.push_to and model.unit("brute").hp == int(base.units[2].hp) - forecast.damage, "Push execution matches preview")
	_check(not [4, 2] in _plan(model, "brute").cells and [6, 2] in _plan(model, "brute").cells, "Pushing changes actual advertised attack space")
	before = model.snapshot()
	_check(not model.use_skill("player", "push", [6, 3]).ok and model.snapshot() == before, "One action per ally per round")
	_check(model.move_unit("player", [4, 3]).ok and model.unit("player").moved, "Can move after attacking into vacated tile")
	before = model.snapshot()
	_check(not model.move_unit("player", [3, 3]).ok and model.snapshot() == before, "One move per ally per round")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok and _plan(model, "blade").interrupted and _plan(model, "blade").cells.is_empty(), "Interrupt cancels advertised blade action")
	var hp: int = model.unit("tinglan").hp
	var ended: Dictionary = model.end_round()
	_check(ended.ok and model.unit("tinglan").hp == hp and model.snapshot().objective.hp == 15, "Interrupted blade and displaced brute do not secretly retarget; only bow hits goal")
	_check(model.snapshot().round == 2 and not model.unit("player").acted and not model.unit("player").moved, "Next round restores one move and action")
	model = _fresh()
	model.end_round()
	_check(model.snapshot().objective.hp == 10 and model.unit("tinglan").hp == 13, "Ignoring initial threats has real HP consequences")
	model.end_round()
	model.end_round()
	_check(model.snapshot().phase == "lost" and model.snapshot().outcome == "defeat", "Unopposed attackers can destroy the objective")
	before = model.snapshot()
	_check(not model.end_round().ok and not model.move_unit("player", [3, 2]).ok and model.snapshot() == before, "Terminal state rejects every further action")
	model = _fresh()
	_check(model.abandon().ok and model.snapshot().phase == "lost" and model.snapshot().outcome == "abandoned", "Withdrawal creates a genuine terminal state")
	before = model.snapshot()
	_check(not model.surrender().ok and model.snapshot() == before, "Repeated withdrawal fails without state changes")
	var invalid: Dictionary = base.duplicate(true)
	invalid.units[0].pos = invalid.objective.pos.duplicate()
	_check(not model.configure(invalid).ok and model.snapshot() == before, "Invalid encounter cannot overwrite active or terminal state")
	invalid = base.duplicate(true)
	invalid.units[0].skills.append("missing")
	_check(not model.configure(invalid).ok and model.snapshot() == before, "Unknown skill references rejected before mutation")
	invalid = base.duplicate(true)
	invalid.width = 9.5
	_check(not model.configure(invalid).ok and model.snapshot() == before, "Fractional dimensions rejected")
	_test_guard()
	_test_blocked_push()
	_test_survival()
	_test_victory()
	_test_authored_victory()
	print("AMBUSH RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_guard() -> void:
	var model = _fresh()
	model.use_skill("tinglan", "guard", [])
	model.end_round()
	_check(model.unit("tinglan").hp == 16 and not model.unit("tinglan").guarded, "Guard reduces damage and expires at next round")


func _test_blocked_push() -> void:
	var data: Dictionary = base.duplicate(true)
	data.obstacles.append([6, 3])
	var model = Rules.new()
	_check(model.configure(data).ok, "Collision fixture valid")
	var forecast: Dictionary = model.preview("player", "push", [4, 3])
	model.use_skill("player", "push", [4, 3])
	_check(forecast.push_to == [5, 3] and forecast.collision and model.unit("brute").pos == [5, 3] and model.unit("brute").hp == int(base.units[2].hp) - forecast.damage, "Blocked push stops before obstacle and preview includes collision damage")


func _test_survival() -> void:
	var data: Dictionary = base.duplicate(true)
	# Rules-level boundary fixture: isolate the deadline from authored difficulty.
	data.objective.hp = 100
	data.objective.max_hp = 100
	for member in data.units:
		if member.team == "player": member.hp = 100; member.max_hp = 100
	var model = Rules.new()
	model.configure(data)
	for index in 3: model.end_round()
	_check(model.snapshot().phase == "player" and model.snapshot().round == 4, "Survival does not win one round early")
	model.end_round()
	_check(model.snapshot().phase == "won" and model.snapshot().outcome == "victory" and model.snapshot().round == 4, "Victory occurs after the fourth resolved enemy round")


func _test_victory() -> void:
	var data: Dictionary = base.duplicate(true)
	data.units = [data.units[0], data.units[2]]
	data.units[1].hp = 6
	data.units[1].max_hp = 6
	var model = Rules.new()
	model.configure(data)
	model.use_skill("player", "strike", [4, 3])
	_check(model.snapshot().phase == "won" and model.snapshot().objective.hp == 18, "Defeating every enemy wins immediately without a bonus enemy phase")


func _test_authored_victory() -> void:
	# A real winning line against the shipped data, with no injected HP or state.
	var model = _fresh()
	_check(model.use_skill("player", "push", [4, 3]).ok, "Authored win R1 push")
	_check(model.move_unit("player", [5, 3]).ok, "Authored win R1 reposition")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok, "Authored win R1 interrupt")
	_check(model.end_round().ok, "Authored win R1 end")
	_check(model.use_skill("player", "push", [6, 3]).ok, "Authored win R2 push")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok, "Authored win R2 interrupt")
	_check(model.end_round().ok, "Authored win R2 end")
	_check(model.move_unit("player", [7, 3]).ok, "Authored win R3 advance")
	_check(model.use_skill("player", "push", [8, 3]).ok, "Authored win R3 collision")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok, "Authored win R3 interrupt")
	_check(model.end_round().ok, "Authored win R3 end")
	_check(model.use_skill("player", "strike", [8, 3]).ok, "Authored win R4 finish brute")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok, "Authored win R4 finish blade")
	_check(model.end_round().ok, "Authored win R4 end")
	_check(model.snapshot().phase == "won" and model.snapshot().objective.hp == 6 and model.unit("player").hp == 17 and model.unit("tinglan").hp == 18, "Authored public API route wins with medicine and both allies surviving")


func _fresh():
	var result = Rules.new()
	_check(result.configure(base).ok, "Authored encounter configures")
	return result


func _plan(model, id: String) -> Dictionary:
	for row in model.snapshot().plans:
		if row.unit_id == id: return row
	return {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
