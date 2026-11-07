extends SceneTree
## Approved palm combat uses the existing push rule. Exercises only public rules.
const Rules := preload("res://addons/cultivation_mode/ambush_rules.gd")
const ENCOUNTER := "res://games/shu_mountain_ambush/encounter.json"
const ORIGINAL_RULES_SHA := "0253ca749018ed2bb38f1730616c9dc26aee86c644a6a02e55cb2589dee73d6e"
var base: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}
var output_dir := "res://.local/qa/sword-palm/rules"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			output_dir = arg.trim_prefix("--output-dir=")
	base = JSON.parse_string(FileAccess.get_file_as_string(ENCOUNTER))
	_test_authored()
	_test_opening_order()
	_test_targets_and_sight()
	_test_displacement_boundaries()
	_test_lethal_and_legacy()
	_finish()


func _fresh(data: Dictionary = {}):
	var model = Rules.new()
	_check(model.configure(base if data.is_empty() else data).ok, "Rule fixture configures")
	return model


func _test_authored() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_mountain_ambush/game.json"))
	_check(manifest.version == "0.5.1" and manifest.ambush.encounter_sha256 == FileAccess.get_sha256(ENCOUNTER), "New content version pins the actual encounter bytes")
	_check(FileAccess.get_sha256("res://addons/cultivation_mode/ambush_rules.gd") == ORIGINAL_RULES_SHA, "Palm reuses the unchanged authoritative rules")
	var model = _fresh()
	var authored: Dictionary = model.snapshot()
	_check(authored.units.size() == 5 and int(base.survive_rounds) == 4 and authored.objective.pos == [4, 2] and authored.objective.hp == 18, "Two allies, three enemies and four-round medicine protection remain")
	var positions := [[3, 3], [5, 5], [4, 3], [5, 4], [7, 1]]
	var health := [22, 18, 14, 10, 8]
	for index: int in range(5):
		_check(authored.units[index].pos == positions[index] and authored.units[index].hp == health[index], "Original opening position and HP retained for " + str(base.units[index].id))
	_check(authored.barricades[0].pos == [6, 3] and authored.barricades[1].pos == [6, 5] and authored.barricades.all(func(row): return int(row.hp) == 6), "Both original six-HP gates remain")
	_check(model.unit("tinglan").skills == ["strike", "interrupt", "guard", "palm"], "Tinglan retains her original three skills and learns palm")
	_check(model.unit("player").skills == ["strike", "push", "pierce", "sweep", "guard"], "Jiang's original five skills remain")
	var skill: Dictionary = base.skills.filter(func(row): return row.id == "palm")[0]
	_check(skill.effect == "push" and skill.range == 2 and skill.damage == 3 and skill.push_distance == 2 and skill.collision_bonus == 2, "Palm has approved range, power and existing displacement parameters")
	var before: Dictionary = model.snapshot()
	var p: Dictionary = model.preview("tinglan", "palm", [5, 4])
	_check(p.ok and p.target_id == "blade" and p.push_to == [5, 2] and p.push_path == [[5, 4], [5, 3], [5, 2]] and p.damage == 3 and not p.collision, "Opening palm preview offers a real two-cell retreat with no invented collision")
	_check(model.snapshot() == before, "Opening palm preview is read only")
	_check(_plan(model, "brute").cells.has([4, 2]) and _plan(model, "blade").cells.has([5, 5]), "Original medicine and ally threats remain visible at the opening")


func _test_opening_order() -> void:
	var palm_first = _fresh()
	var approach: Dictionary = palm_first.move_unit("tinglan", [3, 4])
	_check(approach.ok and approach.events[0].path.size() == 4 and approach.events[0].path[0] == [5, 5] and approach.events[0].path[-1] == [3, 4], "Tinglan reaches the setup cell by exactly three legal steps")
	_check(not [4, 4] in palm_first.reachable("player"), "Before palm, ally and brute block Jiang's two entrances to the follow-up cell")
	_reject(palm_first, "player", "strike", [5, 4], "Blade is outside Jiang's initial sword reach")
	var before: Dictionary = palm_first.snapshot()
	var p: Dictionary = palm_first.preview("tinglan", "palm", [4, 3])
	_check(p.ok and p.target_id == "brute" and p.damage == 5 and p.push_to == [5, 3] and p.push_path == [[4, 3], [5, 3]], "Diagonal two-cell palm predicts the existing horizontal main-axis displacement")
	_check(p.collision and p.collision_barricade_id == "north_gate" and p.collision_barricade_pos == [6, 3] and p.destroys_barricade and p.barricade_damage == 6, "Palm identifies the precise collision gate and break result")
	_check(not p.will_interrupt and palm_first.snapshot() == before and palm_first.preview("tinglan", "palm", [4, 3]) == p, "Repeated palm preview is deterministic, read only and distinct from interrupt")
	var cast: Dictionary = palm_first.use_skill("tinglan", "palm", [4, 3])
	_check(cast.ok and cast.events.map(func(event): return event.type) == ["attack", "damage", "push", "barricade_damage", "barricade_destroyed"], "One palm emits the normal ordered attack, damage, displacement and gate events")
	_check(cast.events[0].skill_id == "palm" and cast.events[0].from == [3, 4] and cast.events[0].to == [4, 3] and cast.events[1].amount == 5, "Attack remains palm-labelled with exact source, victim cell and actual damage")
	_check(palm_first.unit("brute").hp == 9 and palm_first.unit("brute").pos == p.push_to and _bar(palm_first, "north_gate").hp == 0, "Actual HP, displacement and gate break match palm preview")
	_check(palm_first.unit("tinglan").moved and palm_first.unit("tinglan").acted and int(palm_first.snapshot().revision) == int(before.revision) + 1, "Palm spends exactly one action after the independent movement")
	_check(_plan(palm_first, "brute").displaced and _plan(palm_first, "brute").cells == [[5, 2]] and not [4, 2] in _plan(palm_first, "brute").cells, "Palm shifts the frozen brute threat away from medicine without secretly retargeting")
	_check([4, 4] in palm_first.reachable("player"), "Vacating the brute cell really unlocks Jiang's follow-up route")
	_reject(palm_first, "tinglan", "palm", [5, 3], "Duplicate palm cannot consume another action or damage")
	var advance: Dictionary = palm_first.move_unit("player", [4, 4])
	_check(advance.ok and advance.events[0].path == [[3, 3], [4, 3], [4, 4]], "Jiang follows through the exact cell opened by palm")
	var sword: Dictionary = palm_first.preview("player", "strike", [5, 4])
	_check(sword.ok and sword.damage == 6 and sword.target_id == "blade", "The newly accessible follow-up cell enables the original six-damage sword on blade")
	var sweep: Dictionary = palm_first.preview("player", "sweep", [5, 4])
	_check(sweep.ok and sweep.targets == ["brute", "blade"] and sweep.total_damage == 6, "The same follow-up cell offers a genuine two-enemy sweep")
	_check(palm_first.use_skill("player", "sweep", [5, 4]).ok and palm_first.unit("brute").hp == 6 and palm_first.unit("blade").hp == 7, "Palm then sweep deals exactly the two normal independent skill results")
	_check(palm_first.end_round().ok and palm_first.snapshot().objective.hp == 15 and palm_first.unit("player").hp == 22 and palm_first.unit("tinglan").hp == 18, "The actual end turn uses changed positions: only the bow damages medicine")
	var sword_first = _fresh()
	_check(sword_first.move_unit("tinglan", [3, 4]).ok, "Reverse-order fixture uses the identical three-step setup")
	var reverse_before: Dictionary = sword_first.snapshot()
	_check(not sword_first.move_unit("player", [4, 4]).ok and sword_first.snapshot() == reverse_before, "Reverse order cannot invent the still-blocked follow-up move")
	var reverse: Dictionary = sword_first.preview("player", "sweep", [4, 3])
	_check(reverse.ok and reverse.targets == ["brute"] and reverse.total_damage == 3, "Sword before palm can sweep only one enemy from the original cell")
	_check(sword_first.use_skill("player", "sweep", [4, 3]).ok and sword_first.use_skill("tinglan", "palm", [4, 3]).ok, "Both original-order actions execute through public APIs")
	_check(sword_first.unit("brute").hp == 6 and sword_first.unit("blade").hp == 10 and sword_first.unit("player").pos == [3, 3], "Reversing the same two skills leaves blade unharmed and Jiang behind the opening")
	evidence["opening_order"] = {"setup_path": approach.events[0].path, "palm_forecast": p, "palm_events": cast.events, "follow_path": advance.events[0].path, "palm_then_sword": palm_first.snapshot(), "sword_then_palm": sword_first.snapshot()}


func _test_targets_and_sight() -> void:
	var model = _fresh()
	_reject(model, "player", "palm", [4, 3], "Jiang has not learned palm")
	for target: Array in [[5, 5], [3, 3], [4, 2], [6, 5], [6, 4], [5, 3], [7, 1], [-1, 4], [5.5, 4]]:
		_reject(model, "tinglan", "palm", target, "Invalid palm target " + str(target))
	for blocker in ["rock", "gate"]:
		var data := _fixture()
		data.units[1].pos = [3, 3]
		data.units[2].pos = [5, 3]
		if blocker == "rock": data.obstacles = [[4, 3]]
		else: data.barricades = [{"id": "sight_gate", "name": "测试木栅", "pos": [4, 3], "hp": 6, "max_hp": 6}]
		model = _fresh(data)
		_reject(model, "tinglan", "palm", [5, 3], "Living " + blocker + " blocks palm sight before the target")
	var data := _fixture()
	data.units[1].pos = [3, 3]
	data.units[2].pos = [4, 4]
	data.obstacles = [[4, 3]]
	model = _fresh(data)
	_reject(model, "tinglan", "palm", [4, 4], "Supercover prevents palm slipping through a blocked diagonal corner")
	data.obstacles = []
	model = _fresh(data)
	_check(model.preview("tinglan", "palm", [4, 4]).ok, "The same diagonal is legal when the actual corner is clear")


func _test_displacement_boundaries() -> void:
	for blocker in ["rock", "ally", "objective", "gate", "edge"]:
		var data := _fixture()
		data.units[1].pos = [3, 3]
		data.units[2].pos = [4, 3]
		match blocker:
			"rock": data.obstacles = [[5, 3]]
			"ally": data.units[0].pos = [5, 3]
			"objective": data.objective.pos = [5, 3]
			"gate": data.barricades = [{"id": "collision_gate", "name": "测试木栅", "pos": [5, 3], "hp": 6, "max_hp": 6}]
			"edge":
				data.units[1].pos = [7, 3]
				data.units[2].pos = [8, 3]
		var model = _fresh(data)
		var protected_ally: Dictionary = model.unit("player")
		var protected_objective: Dictionary = model.snapshot().objective
		var target: Array = model.unit("brute").pos
		var p: Dictionary = model.preview("tinglan", "palm", target)
		_check(p.ok and p.collision and p.damage == 5 and p.push_to == target and p.push_path == [target], "Palm stops at the actual immediate " + blocker + " collision")
		var outcome: Dictionary = model.use_skill("tinglan", "palm", target)
		_check(outcome.ok and model.unit("brute").hp == 9 and model.unit("brute").pos == target and _events(outcome, "damage").size() == 1, "Collision with " + blocker + " applies one predicted hit without passing through it")
		_check(model.unit("player") == protected_ally and model.snapshot().objective == protected_objective, "Collision with " + blocker + " does not damage an ally or medicine")
		_check(_events(outcome, "barricade_destroyed").size() == (1 if blocker == "gate" else 0), "Only an actual gate collision destroys one gate: " + blocker)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var data := _fixture()
		data.units[1].pos = [4, 3]
		data.units[2].pos = [4 + direction.x, 3 + direction.y]
		var model = _fresh(data)
		var p: Dictionary = model.preview("tinglan", "palm", data.units[2].pos)
		var expected := [4 + direction.x * 3, 3 + direction.y * 3]
		_check(p.ok and p.push_to == expected and p.damage == 3 and not p.collision, "Unobstructed palm forecasts two real cells " + str(direction))
		_check(model.use_skill("tinglan", "palm", data.units[2].pos).ok and model.unit("brute").pos == expected and model.unit("brute").hp == 11, "Unobstructed palm execution matches each direction " + str(direction))


func _test_lethal_and_legacy() -> void:
	var data := _fixture()
	data.units[1].pos = [3, 3]
	data.units[2].pos = [4, 3]
	data.units[2].hp = 3
	var model = _fresh(data)
	var outcome: Dictionary = model.use_skill("tinglan", "palm", [4, 3])
	_check(outcome.ok and model.unit("brute").hp == 0 and model.unit("brute").pos == [4, 3] and _events(outcome, "push").is_empty() and _events(outcome, "defeat").size() == 1, "Lethal palm emits one defeat and never moves a defeated body")
	_reject(model, "tinglan", "palm", [4, 3], "Already acted palm cannot hit a defeated target again")
	model = _fresh()
	_check(model.use_skill("player", "push", [4, 3]).ok and model.unit("brute").pos == [5, 3] and model.unit("brute").hp == 9, "Jiang's original push keeps the original opening collision behavior")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok and _plan(model, "blade").interrupted, "Tinglan's original interrupt still cancels the enemy plan")
	_check(model.end_round().ok and model.snapshot().objective.hp == 15 and model.unit("tinglan").hp == 18, "The original control opening still protects medicine and Tinglan")
	model.configure(base)
	_check(model.unit("tinglan").pos == [5, 5] and not model.unit("tinglan").acted and _bar(model, "north_gate").hp == 6 and model.snapshot().objective.hp == 18, "Explicit reset restores the complete new encounter without leftover palm state")


func _fixture() -> Dictionary:
	var data := base.duplicate(true)
	data.obstacles = []
	data.barricades = []
	data.objective.pos = [0, 0]
	data.units[0].pos = [0, 6]
	data.units[3].pos = [8, 6]
	data.units[4].pos = [8, 0]
	return data


func _plan(model, id: String) -> Dictionary:
	for row: Dictionary in model.snapshot().plans:
		if row.unit_id == id: return row
	return {}


func _bar(model, id: String) -> Dictionary:
	for row: Dictionary in model.snapshot().barricades:
		if row.id == id: return row
	return {}


func _events(result: Dictionary, kind: String) -> Array:
	return result.get("events", []).filter(func(row): return row.type == kind)


func _reject(model, actor: String, skill: String, target: Array, label: String) -> void:
	var before: Dictionary = model.snapshot()
	_check(not model.preview(actor, skill, target).ok and model.snapshot() == before, label + " preview rejects atomically")
	_check(not model.use_skill(actor, skill, target).ok and model.snapshot() == before, label + " execution rejects atomically")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var file := FileAccess.open(output_dir.path_join("sword-palm-rules.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "evidence": evidence, "encounter_sha256": FileAccess.get_sha256(ENCOUNTER), "rules_sha256": FileAccess.get_sha256("res://addons/cultivation_mode/ambush_rules.gd")}, "\t") + "\n")
	print("SWORD PALM RULES: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
