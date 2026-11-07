extends SceneTree
## Destructible blockers are encounter-local state; host settlement stays unique.
const Rules = preload("res://addons/cultivation_mode/ambush_rules.gd")
const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const AmbushSession = preload("res://addons/cultivation_mode/ambush_session.gd")
const Store = preload("res://addons/cultivation_mode/save_store.gd")
var checks := 0
var failures := 0
var base: Dictionary = {}

func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_mountain_ambush/encounter.json"))
	_test_authored_and_isolation()
	_test_direct_opening()
	_test_collision()
	_test_partial_and_lethal()
	_test_lines_and_frozen_intents()
	_test_validation()
	_test_host_boundary()
	print("AMBUSH BARRICADE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fresh(data: Dictionary = {}):
	var model = Rules.new()
	_check(model.configure(base if data.is_empty() else data).ok, "Fixture configures")
	return model

func _bar(model, id: String) -> Dictionary:
	for row in model.snapshot().barricades:
		if row.id == id: return row
	return {}

func _plan(model, id: String) -> Dictionary:
	for row in model.snapshot().plans:
		if row.unit_id == id: return row
	return {}

func _events(events: Array, kind: String, id: String = "") -> Array:
	return events.filter(func(event): return event.type == kind and (id.is_empty() or event.get("target_id", "") == id))

func _test_authored_and_isolation() -> void:
	var model = _fresh()
	_check(model.snapshot().barricades == [{"id":"north_gate","name":"路口木栅","pos":[6,3],"hp":6,"max_hp":6},{"id":"south_gate","name":"侧路木栅","pos":[6,5],"hp":6,"max_hp":6}], "Authored independent six-HP gates occupy the two route cells")
	_check(model.snapshot().units.size() == 5 and model.unit("brute").hp == 14 and model.snapshot().objective.hp == 18 and int(base.survive_rounds) == 4, "Original party enemy goal and survival parameters remain")
	var before: Dictionary = model.snapshot()
	var copied: Dictionary = model.snapshot()
	copied.barricades[0].hp = 0
	copied.barricades[1].pos[0] = 0
	_check(model.snapshot() == before, "Returned barricade state cannot mutate live rules")
	var input: Dictionary = base.duplicate(true)
	model = _fresh(input)
	input.barricades[0].hp = 1
	_check(_bar(model, "north_gate").hp == 6 and model.definition.barricades[0].hp == 6, "Configure isolates caller data and pristine reset definition")
	var legacy: Dictionary = base.duplicate(true)
	legacy.erase("barricades")
	model = _fresh(legacy)
	_check(model.snapshot().barricades.is_empty() and [6, 5] in model.reachable("tinglan"), "Absent optional barricades retains the legacy open road")
	var forecast: Dictionary = model.preview("player", "push", [4, 3])
	_check(forecast.push_to == [6, 3] and forecast.damage == 3 and forecast.target_kind == "unit" and not forecast.destroys_barricade, "Legacy push keeps original destination damage and unit target")

func _test_direct_opening() -> void:
	var model = _fresh()
	var before: Dictionary = model.snapshot()
	_check(not [6, 5] in model.reachable("tinglan") and not [7, 5] in model.reachable("tinglan"), "Live side gate blocks itself and makes the shortcut exceed three movement points")
	_check(not model.move_unit("tinglan", [6, 5]).ok and not model.move_unit("tinglan", [7, 5]).ok and model.snapshot() == before, "Blocked movement does not consume movement or mutate state")
	_check(not model.preview("tinglan", "interrupt", [6, 5]).ok and not model.use_skill("tinglan", "interrupt", [6, 5]).ok and model.snapshot() == before, "Interrupt cannot directly select an empty gate")
	_check(not model.preview("player", "push", [6, 3]).ok and not model.use_skill("player", "push", [6, 3]).ok and model.snapshot() == before, "Push cannot directly select a gate")
	var forecast: Dictionary = model.preview("tinglan", "strike", [6, 5])
	_check(forecast.ok and forecast.target_kind == "barricade" and forecast.target_id == "south_gate" and forecast.barricade_id == "south_gate" and forecast.cells == [[6, 5]], "Sword preview identifies the precise gate target")
	_check(forecast.damage == 6 and forecast.barricade_damage == 6 and forecast.destroys_barricade and forecast.collision_barricade_id == "" and forecast.collision_barricade_pos.is_empty(), "Direct sword forecast distinguishes gate damage from push collision")
	_check(model.snapshot() == before and model.preview("tinglan", "strike", [6, 5]) == forecast, "Repeated gate preview is deterministic and side-effect free")
	var outcome: Dictionary = model.use_skill("tinglan", "strike", [6, 5])
	_check(outcome.ok and _bar(model, "south_gate").hp == 0 and _bar(model, "north_gate").hp == 6 and model.unit("tinglan").acted and not model.unit("tinglan").moved, "Direct destruction spends one action and preserves the independent gate and movement")
	_check(outcome.events.map(func(event): return event.type) == ["attack", "barricade_damage", "barricade_destroyed"], "Direct gate hit has ordered attack damage destruction events without a fake unit hit")
	_check(outcome.events[0].target_kind == "barricade" and outcome.events[0].target_id == "south_gate" and outcome.events[1].amount == 6 and outcome.events[1].hp_after == 0 and outcome.events[2].to == [6, 5], "Destruction events carry exact target cell and actual HP result")
	_check([6, 5] in model.reachable("tinglan") and [7, 5] in model.reachable("tinglan"), "Destruction immediately opens a shorter real route")
	before = model.snapshot()
	_check(not model.use_skill("tinglan", "strike", [6, 5]).ok and model.snapshot() == before, "Repeated same-round destruction is rejected atomically")
	outcome = model.move_unit("tinglan", [7, 5])
	_check(outcome.ok and outcome.events[0].path == [[5, 5], [6, 5], [7, 5]], "Player walks through destroyed gate by the advertised two-step shortcut")
	model.configure(base)
	_check(_bar(model, "south_gate").hp == 6 and _bar(model, "north_gate").hp == 6 and model.unit("tinglan").pos == [5, 5] and not model.unit("tinglan").acted, "Explicit reset restores intact gates and original action state")
	var adjacent: Dictionary = base.duplicate(true)
	adjacent.units[0].pos = [6, 2]
	model = _fresh(adjacent)
	before = model.snapshot()
	_check(not model.use_skill("player", "push", [6, 3]).ok and not model.use_skill("player", "guard", [6, 3]).ok and model.snapshot() == before, "Even in range push and guard cannot directly select wood or spend an action")

func _test_collision() -> void:
	var model = _fresh()
	var before: Dictionary = model.snapshot()
	var forecast: Dictionary = model.preview("player", "push", [4, 3])
	_check(forecast.ok and forecast.target_kind == "unit" and forecast.target_id == "brute" and forecast.barricade_id == "", "Collision preview remains a unit-targeted skill")
	_check(forecast.push_to == [5, 3] and forecast.push_path == [[4, 3], [5, 3]] and forecast.collision and forecast.damage == 5, "Gate collision stops one square before the gate and adds the existing two damage")
	_check(forecast.collision_barricade_id == "north_gate" and forecast.collision_barricade_pos == [6, 3] and forecast.barricade_damage == 6 and forecast.destroys_barricade and model.snapshot() == before, "Collision forecast includes guaranteed gate destruction without mutation")
	var outcome: Dictionary = model.use_skill("player", "push", [4, 3])
	_check(outcome.ok and model.unit("brute").pos == [5, 3] and model.unit("brute").hp == 9 and _bar(model, "north_gate").hp == 0, "Actual push damage position and destroyed gate match preview without passing through it")
	_check(_bar(model, "south_gate").hp == 6 and model.definition.barricades[0].hp == 6, "A collision changes only that live gate and not pristine definition")
	_check(outcome.events.map(func(event): return event.type) == ["attack", "damage", "push", "barricade_damage", "barricade_destroyed"], "Collision destroys the gate only after presentation of the push")
	_check(outcome.events[2].from == [4, 3] and outcome.events[2].to == [5, 3] and outcome.events[3].to == [6, 3] and outcome.events[3].amount == 6 and outcome.events[3].hp_after == 0, "Push and wood-hit events identify their different destinations")
	var plan: Dictionary = _plan(model, "brute")
	_check(plan.displaced and plan.move_to == [5, 3] and plan.target == [4, 2] and plan.cells == [[5, 2]], "Collision changes frozen melee cells without secretly redirecting onto the medicine")
	_check(model.use_skill("tinglan", "interrupt", [5, 4]).ok and model.end_round().ok and model.snapshot().objective.hp == 15 and model.unit("tinglan").hp == 18, "First collision control turn protects the goal from brute and blade while bow still hits")
	# A nearer hard obstacle or unit is the actual collision, not a gate behind it.
	for kind in ["rock", "unit"]:
		var data: Dictionary = base.duplicate(true)
		if kind == "rock": data.obstacles.append([5, 3])
		else: data.units[1].pos = [5, 3]
		model = _fresh(data)
		forecast = model.preview("player", "push", [4, 3])
		outcome = model.use_skill("player", "push", [4, 3])
		_check(forecast.collision and forecast.damage == 5 and forecast.collision_barricade_id == "" and not forecast.destroys_barricade and _bar(model, "north_gate").hp == 6 and _events(outcome.events, "barricade_destroyed").is_empty(), "A nearer " + kind + " prevents a false behind-obstacle gate break")
	var data: Dictionary = base.duplicate(true)
	data.barricades[0].pos = [5, 3]
	model = _fresh(data)
	forecast = model.preview("player", "push", [4, 3])
	outcome = model.use_skill("player", "push", [4, 3])
	_check(forecast.push_to == [4, 3] and forecast.push_path == [[4, 3]] and model.unit("brute").pos == [4, 3] and _bar(model, "north_gate").hp == 0, "Immediate collision can break a gate without moving through its original cell")

func _test_partial_and_lethal() -> void:
	var data: Dictionary = base.duplicate(true)
	data.barricades[1].hp = 10
	data.barricades[1].max_hp = 10
	data.units[0].pos = [7, 5]
	var model = _fresh(data)
	var forecast: Dictionary = model.preview("tinglan", "strike", [6, 5])
	_check(forecast.damage == 6 and forecast.barricade_damage == 6 and not forecast.destroys_barricade, "Stronger gate previews a real partial hit")
	var outcome: Dictionary = model.use_skill("tinglan", "strike", [6, 5])
	_check(_bar(model, "south_gate").hp == 4 and _events(outcome.events, "barricade_destroyed").is_empty() and not [6, 5] in model.reachable("player"), "Partially damaged gate still blocks the road")
	forecast = model.preview("player", "strike", [6, 5])
	_check(forecast.damage == 6 and forecast.barricade_damage == 4 and forecast.destroys_barricade, "Overkill forecast separates skill power from actual remaining wood damage")
	outcome = model.use_skill("player", "strike", [6, 5])
	_check(_events(outcome.events, "barricade_damage")[0].amount == 4 and _bar(model, "south_gate").hp == 0, "Second attacker destroys only remaining HP without negative durability")
	model.end_round()
	var before: Dictionary = model.snapshot()
	_check(not model.use_skill("player", "strike", [6, 5]).ok and model.snapshot() == before, "Destroyed gate cannot consume a new-round attack")
	data = base.duplicate(true)
	data.units[2].hp = 5
	data.barricades[0].hp = 10000
	data.barricades[0].max_hp = 10000
	model = _fresh(data)
	forecast = model.preview("player", "push", [4, 3])
	_check(forecast.damage == 5 and forecast.barricade_damage == 10000 and forecast.destroys_barricade, "Collision guarantees destruction at the valid durability boundary even on lethal unit damage")
	outcome = model.use_skill("player", "push", [4, 3])
	_check(model.unit("brute").hp == 0 and model.unit("brute").pos == [4, 3] and _bar(model, "north_gate").hp == 0, "Lethal push still fulfills promised gate destruction without moving the defeated unit")
	_check(_events(outcome.events, "push").is_empty() and _events(outcome.events, "defeat", "brute").size() == 1 and _events(outcome.events, "barricade_destroyed", "north_gate").size() == 1 and _plan(model, "brute").cells.is_empty(), "Lethal collision emits one defeat and one destruction and clears dead enemy threats")
	data.units = [data.units[0], data.units[2]]
	model = _fresh(data)
	outcome = model.use_skill("player", "push", [4, 3])
	_check(model.snapshot().phase == "won" and _bar(model, "north_gate").hp == 0 and outcome.events[-1].type == "victory" and outcome.events[-2].type == "barricade_destroyed", "Last-enemy lethal collision finishes wood destruction before terminal victory")

func _line_fixture() -> Dictionary:
	var data: Dictionary = base.duplicate(true)
	data.units[3].pos = [7, 5]
	data.units[3].attack.move_range = 0
	data.units[4].pos = [8, 5]
	data.units[4].attack.target = "nearest_player"
	data.units[4].attack.move_range = 0
	return data

func _test_lines_and_frozen_intents() -> void:
	var data := _line_fixture()
	var model = _fresh(data)
	_check(not model.preview("tinglan", "interrupt", [7, 5]).ok and _plan(model, "blade").cells.is_empty() and _plan(model, "archer").cells.is_empty(), "Live gate blocks player sight and frozen enemy line and shot cells")
	var blade: Dictionary = _plan(model, "blade")
	var bow: Dictionary = _plan(model, "archer")
	model.use_skill("tinglan", "strike", [6, 5])
	_check(_plan(model, "blade").cells == [[6, 5], [5, 5]] and _plan(model, "archer").cells == [[5, 5]], "Breaking gate immediately exposes the actual line and shot threat cells")
	for id in ["blade", "archer"]:
		var old: Dictionary = blade if id == "blade" else bow
		var current: Dictionary = _plan(model, id)
		_check(current.target == old.target and current.direction == old.direction and current.offsets == old.offsets and current.move_to == old.move_to, "Destruction refreshes " + id + " cells without retargeting or inventing a new route")
	var shown: Array = _plan(model, "blade").cells
	var outcome: Dictionary = model.end_round()
	var actual: Array = outcome.events.filter(func(event): return event.type == "attack" and event.unit_id == "blade")
	_check(actual[0].cells == shown and model.unit("tinglan").hp == 10, "Enemy resolution uses exactly the exposed advertised cells and damage")
	model = _fresh(data)
	model.end_round()
	_check(_bar(model, "south_gate").hp == 6 and model.unit("tinglan").hp == 18, "Enemies keep their original targets and do not secretly attack the blocking gate")
	data = base.duplicate(true)
	data.units[3].pos = [6, 6]
	data.units[3].attack.move_range = 0
	model = _fresh(data)
	_check(not model.preview("tinglan", "interrupt", [6, 6]).ok, "Supercover sight cannot slip diagonally past an intact gate corner")
	model.use_skill("tinglan", "strike", [6, 5])
	model.end_round()
	_check(model.preview("tinglan", "interrupt", [6, 6]).ok, "Destroying that corner blocker restores diagonal sight")
	data = base.duplicate(true)
	data.units[2].pos = [7, 5]
	model = _fresh(data)
	var frozen: Dictionary = _plan(model, "brute")
	_check(not [6, 5] in frozen.path and not [6, 3] in frozen.cells, "Enemy planned movement and melee cells respect both live gates")
	model.use_skill("tinglan", "strike", [6, 5])
	_check(_plan(model, "brute").target == frozen.target and _plan(model, "brute").offsets == frozen.offsets and _plan(model, "brute").path == frozen.path, "Opening a shorter path does not change the already frozen enemy route")

func _test_validation() -> void:
	var model = _fresh()
	var before: Dictionary = model.snapshot()
	var original_definition: Dictionary = model.definition.duplicate(true)
	var cases: Array = []
	for bad in [null, {}, "wrong"]:
		var data: Dictionary = base.duplicate(true)
		data.barricades = bad
		cases.append(["array type " + str(bad), data])
	for field in ["id", "name", "pos", "hp", "max_hp"]:
		var values: Array
		match field:
			"id": values = [null, "", "  ", "objective", "player", "south_gate", 4]
			"name": values = [null, "", " ", 4]
			"pos": values = [null, [-1, 3], [9, 3], [6, 7], [6.5, 3], [true, 3], [6], [6, 3, 0], [2, 2], [4, 2], [3, 3], [6, 5]]
			"hp": values = [null, 0, -1, 6.5, 10001, true, INF, NAN]
			_: values = [null, 5, 6.5, 10001, true, INF, NAN]
		for bad in values:
			var data: Dictionary = base.duplicate(true)
			data.barricades[0][field] = bad
			cases.append([field + "=" + str(bad), data])
	for malformed in [null, 4, {}, []]:
		var data: Dictionary = base.duplicate(true)
		data.barricades[0] = malformed
		cases.append(["malformed member=" + str(malformed), data])
	for row in cases:
		_check(not model.configure(row[1]).ok and model.snapshot() == before and model.definition == original_definition, "Invalid barricade rejects atomically: " + str(row[0]))
	var data: Dictionary = base.duplicate(true)
	data.barricades[0].erase("max_hp")
	data.barricades[0].pos = [6.0, 3.0]
	data.barricades[0].hp = 6.0
	model = _fresh(data)
	_check(_bar(model, "north_gate").hp is int and _bar(model, "north_gate").max_hp == 6 and _bar(model, "north_gate").pos[0] is int, "Valid JSON integer-valued numbers normalize and omitted max HP defaults safely")

func _test_host_boundary() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_mountain_ambush/game.json")
	_check(loaded.ok, "Actual authored content pack loads")
	if not loaded.ok: return
	var session = AmbushSession.new()
	var configured: Dictionary = session.configure(loaded.pack)
	_check(configured.ok, "Actual encounter hash pin configures host Session")
	if not configured.ok: return
	var before: Dictionary = session.snapshot()
	_check(before.size() == 15 and not before.has("barricades") and session.can_save(), "Safe host checkpoint retains the existing fifteen-field contract")
	_check(session.begin_ambush(before.run_id, "wood-test", before.revision).ok, "Host enters new wood-gate encounter")
	var battle = session.battle()
	var busy: Dictionary = session.snapshot()
	_check(battle.snapshot().barricades.size() == 2 and not session.can_save(), "Live wood durability remains transient and cannot be saved")
	battle.use_skill("tinglan", "strike", [6, 5])
	_check(session.snapshot() == busy and not session.finish_ambush(before.run_id, "wood-test").ok and session.snapshot() == busy, "Breaking wood changes no host time resources flags or result and cannot forge settlement")
	var store = Store.new()
	store.base_dir = "user://test_runs/ambush-barricade-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(not store.save_session(session).ok, "SaveStore refuses a live battle after wood destruction")
	_check(session.abandon_ambush(before.run_id, "wood-test").ok, "Withdrawing after destruction settles through the original host")
	var settled: Dictionary = session.snapshot()
	_check(settled.size() == 15 and settled.slot == before.slot + 1 and settled.counts.get("ambush_loss", 0) == 1 and not settled.has("barricades"), "One terminal settlement charges once without persisting temporary wood state")
	_check(session.finish_ambush(before.run_id, "wood-test").get("duplicate", false) and session.snapshot() == settled and store.save_session(session).ok, "Duplicate terminal callback stays idempotent and result is saveable")
	var restored = AmbushSession.new()
	restored.configure(loaded.pack)
	_check(store.load_session(restored).ok and restored.snapshot() == settled and restored.battle() == null, "Saved terminal result restores exact original checkpoint without replaying destroyed gates")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
