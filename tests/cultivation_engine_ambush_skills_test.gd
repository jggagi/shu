extends SceneTree
## Public rule API tests. Rearranged positions and guard/dead flags are isolated QA fixtures.
const Rules = preload("res://addons/cultivation_mode/ambush_rules.gd")
var checks := 0
var failures := 0
var base: Dictionary = {}

func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_mountain_ambush/encounter.json"))
	_test_authored()
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		_test_direction(direction)
	_test_immunity()
	_test_blockers()
	_test_boundaries()
	_test_damage_and_victory()
	_test_invalid()
	print("AMBUSH SKILLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fresh(data: Dictionary = {}):
	var model = Rules.new()
	_check(model.configure(base if data.is_empty() else data).ok, "Skill fixture configures")
	return model

func _fixture() -> Dictionary:
	var data := base.duplicate(true)
	data.obstacles = []
	data.barricades = []
	data.objective.pos = [0, 0]
	data.units[0].pos = [3, 3]
	data.units[1].pos = [0, 6]
	data.units[2].pos = [4, 3]
	data.units[3].pos = [5, 3]
	data.units[4].pos = [8, 6]
	return data

func _cell(v: Vector2i) -> Array:
	return [v.x, v.y]

func _same_set(a: Array, b: Array) -> bool:
	return a.size() == b.size() and a.all(func(value): return value in b) and b.all(func(value): return value in a)

func _events(result: Dictionary, kind: String) -> Array:
	return result.get("events", []).filter(func(event): return str(event.type) == kind)

func _reject(model, actor: String, skill: String, target: Array, label: String) -> void:
	var before: Dictionary = model.snapshot()
	_check(not model.preview(actor, skill, target).ok and model.snapshot() == before, label + " preview is an atomic rejection")
	_check(not model.use_skill(actor, skill, target).ok and model.snapshot() == before, label + " execution is an atomic rejection")

func _check_attack(model, skill: String, target: Array, cells: Array, ids: Array, power: int) -> Dictionary:
	var before: Dictionary = model.snapshot()
	var forecast: Dictionary = model.preview("player", skill, target)
	_check(forecast.ok and model.snapshot() == before, skill + " preview is valid and read only")
	if not forecast.ok:
		return {}
	_check(_same_set(forecast.affected_cells, cells) and forecast.cells == forecast.affected_cells, skill + " exposes the exact unobstructed shape through both cell fields")
	_check(_same_set(forecast.targets, ids) and forecast.damage_by_target.size() == ids.size(), skill + " identifies every enemy exactly once")
	_check(int(forecast.damage) == power and int(forecast.total_damage) == ids.size() * power, skill + " separates per-enemy power and total applied damage")
	var result: Dictionary = model.use_skill("player", skill, target)
	var damage: Array = _events(result, "damage")
	_check(result.ok and _events(result, "attack").size() == 1 and damage.size() == ids.size(), skill + " emits one source attack and one damage event per target")
	_check(_same_set(damage.map(func(event): return event.target_id), ids) and damage.all(func(event): return int(event.amount) == int(forecast.damage_by_target[event.target_id])), skill + " damage events match the preview target ledger")
	_check(ids.all(func(id): return int(model.unit(id).hp) == int(_find(before.units, id).hp) - int(forecast.damage_by_target[id])), skill + " every final HP matches the preview")
	_check(model.unit("player").acted and not model.unit("player").moved and int(model.snapshot().revision) == int(before.revision) + 1, skill + " consumes one action, no movement, and one revision")
	_check(model.snapshot().objective == before.objective and model.unit("tinglan") == _find(before.units, "tinglan") and model.snapshot().barricades == before.barricades, skill + " never damages allies, medicine or fences")
	_check(model.snapshot().plans == before.plans and _events(result, "push").is_empty() and _events(result, "interrupt").is_empty(), skill + " adds no displacement, interrupt or hidden enemy replan")
	_reject(model, "player", skill, target, skill + " duplicate action")
	return result

func _find(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.id) == id:
			return row
	return {}

func _test_authored() -> void:
	var model = _fresh()
	_check(_same_set(model.unit("player").skills, ["strike", "push", "guard", "pierce", "sweep"]), "Jiang retains all original skills and learns only the two approved additions")
	_check(model.unit("tinglan").skills == ["strike", "interrupt", "guard", "palm"], "Tinglan retains her three original skills and the approved real-combat palm")
	var p: Dictionary = model.preview("player", "pierce", [4, 3])
	_check(p.ok and p.targets == ["brute"] and p.total_damage == 4 and model.snapshot().objective.hp == 18, "Unmodified authored opening honestly previews one pierced enemy")
	p = model.preview("player", "sweep", [4, 3])
	_check(p.ok and p.targets == ["brute"] and p.total_damage == 3, "Unmodified authored opening honestly previews one swept enemy")

func _test_direction(direction: Vector2i) -> void:
	var data := _fixture()
	var front := Vector2i(3, 3) + direction
	var far := front + direction
	data.units[2].pos = _cell(front)
	data.units[3].pos = _cell(far)
	var model = _fresh(data)
	var before: Dictionary = model.snapshot()
	var near_preview: Dictionary = model.preview("player", "pierce", _cell(front))
	var far_preview: Dictionary = model.preview("player", "pierce", _cell(far))
	_check(near_preview == far_preview and model.snapshot() == before, "Either legal orthogonal aim cell selects the same full two-cell thrust " + str(direction))
	_check_attack(model, "pierce", _cell(far), [_cell(front), _cell(far)], ["brute", "blade"], 4)
	_check(model.move_unit("player", [3, 2] if direction != Vector2i.UP else [2, 3]).ok and model.unit("player").moved, "Attack leaves the independent movement available")
	var side := Vector2i(-direction.y, direction.x)
	data.units[2].pos = _cell(front)
	data.units[3].pos = _cell(front + side)
	data.units[4].pos = _cell(front - side)
	model = _fresh(data)
	_check_attack(model, "sweep", _cell(front), [_cell(front), _cell(front + side), _cell(front - side)], ["brute", "blade", "archer"], 3)

func _test_immunity() -> void:
	for protect in ["ally", "objective"]:
		var data := _fixture()
		data.units[2].pos = [7, 6]
		if protect == "ally": data.units[1].pos = [4, 3]
		else: data.objective.pos = [4, 3]
		var model = _fresh(data)
		_check_attack(model, "pierce", [5, 3], [[4, 3], [5, 3]], ["blade"], 4)
		data = _fixture()
		data.units[2].pos = [4, 2]
		data.units[3].pos = [4, 4]
		if protect == "ally": data.units[1].pos = [4, 3]
		else: data.objective.pos = [4, 3]
		model = _fresh(data)
		_check_attack(model, "sweep", [4, 3], [[4, 3], [4, 2], [4, 4]], ["brute", "blade"], 3)

func _test_blockers() -> void:
	for kind in ["rock", "barricade"]:
		var data := _fixture()
		data.units[3].pos = [7, 5]
		if kind == "rock": data.obstacles = [[5, 3]]
		else: data.barricades = [{"id":"gate","name":"测试木栅","pos":[5,3],"hp":6,"max_hp":6}]
		var model = _fresh(data)
		_reject(model, "player", "pierce", [5, 3], kind + " cannot be aimed through")
		_check_attack(model, "pierce", [4, 3], [[4, 3]], ["brute"], 4)
		data = _fixture()
		data.units[2].pos = [7, 5]
		if kind == "rock": data.obstacles = [[4, 3]]
		else: data.barricades = [{"id":"gate","name":"测试木栅","pos":[4,3],"hp":6,"max_hp":6}]
		model = _fresh(data)
		_reject(model, "player", "pierce", [5, 3], kind + " hides the distant enemy")
		_reject(model, "player", "sweep", [4, 3], kind + " blocks the sweep front")
	var data := _fixture()
	data.units[3].pos = [4, 4]
	data.obstacles = [[3, 4]]
	var model = _fresh(data)
	_check_attack(model, "sweep", [4, 3], [[4, 3], [4, 2]], ["brute"], 3)
	_check(model.unit("blade").hp == 10, "A diagonal flank cannot cut through a touching rock corner")

func _test_boundaries() -> void:
	var data := _fixture()
	data.objective.pos = [8, 6]
	data.units[0].pos = [0, 0]
	data.units[2].pos = [1, 0]
	data.units[3].pos = [1, 1]
	data.units[4].pos = [8, 5]
	var model = _fresh(data)
	_check_attack(model, "sweep", [1, 0], [[1, 0], [1, 1]], ["brute", "blade"], 3)
	model = _fresh(data)
	_reject(model, "player", "sweep", [-1, 0], "Off-board direction")
	_reject(model, "player", "pierce", [0, -1], "Off-board thrust")
	data = _fixture()
	data.units[2].pos = [7, 5]
	model = _fresh(data)
	_check_attack(model, "pierce", [4, 3], [[4, 3], [5, 3]], ["blade"], 4)

func _test_damage_and_victory() -> void:
	var data := _fixture()
	data.units[2].hp = 1
	var model = _fresh(data)
	model.state.units[3].guarded = true
	var before: Dictionary = model.snapshot()
	var p: Dictionary = model.preview("player", "pierce", [5, 3])
	_check(p.ok and p.damage == 4 and p.total_damage == 2 and p.damage_by_target == {"brute":1,"blade":1}, "Preview clips overkill and applies guard separately for every target")
	var result: Dictionary = model.use_skill("player", "pierce", [5, 3])
	_check(model.unit("brute").hp == 0 and model.unit("blade").hp == 9 and _events(result,"damage").map(func(event): return event.amount) == [1,1], "Actual multi-hit damage matches the guarded and residual-HP forecast")
	_check(model.snapshot().phase == "player" and model.unit("archer").hp == before.units[4].hp, "A living off-shape enemy prevents premature victory")
	data = _fixture()
	data.units[3].pos = [4,4]
	model = _fresh(data)
	model.state.units[2].guarded = true
	model.state.units[3].guarded = true
	before = model.snapshot()
	p = model.preview("player","sweep",[4,3])
	_check(p.ok and p.total_damage == 0 and p.damage_by_target == {"brute":0,"blade":0}, "Living guarded targets remain valid even when sweep damage is fully absorbed")
	result = model.use_skill("player","sweep",[4,3])
	_check(result.ok and model.unit("player").acted and model.unit("brute").hp == before.units[2].hp and model.unit("blade").hp == before.units[3].hp and _events(result,"damage").all(func(event):return event.amount == 0), "A blocked multi-hit consumes exactly its one action without invented damage")
	data = _fixture()
	data.units = data.units.slice(0, 4)
	data.units[2].hp = 3
	data.units[3].hp = 4
	model = _fresh(data)
	result = model.use_skill("player", "pierce", [5, 3])
	_check(model.snapshot().phase == "won" and model.snapshot().outcome == "victory" and _events(result,"damage").size() == 2 and _events(result,"defeat").size() == 2 and _events(result,"victory").size() == 1, "All targets settle before a single terminal victory event")
	_reject(model,"player","sweep",[4,3],"Terminal encounter")
	data = _fixture()
	model = _fresh(data)
	model.state.units[2].hp = 0
	p = model.preview("player", "pierce", [4,3])
	_check(p.ok and p.targets == ["blade"] and p.total_damage == 4, "A defeated body is not a fresh target and does not block the far enemy")

func _test_invalid() -> void:
	var model = _fresh(_fixture())
	for skill in ["pierce", "sweep"]:
		for target in [[], [3,3], [4,4], [6,3], [3.5,3], [true,3], ["4",3], [9,3], [4], [4,3,0]]:
			_reject(model,"player",skill,target,skill+" invalid aim "+str(target))
		_reject(model,"missing",skill,[4,3],"Unknown actor")
		_reject(model,"tinglan",skill,[4,3],"Unlearned skill")
		_reject(model,"player",skill,[3,2],"Empty shape")
	for skill in ["pierce", "sweep"]:
		var invalid := base.duplicate(true)
		for row: Dictionary in invalid.skills:
			if row.id == skill: row.range = 3
		var before: Dictionary = model.snapshot()
		_check(not model.configure(invalid).ok and model.snapshot() == before, skill+" invalid authored shape range cannot overwrite an active game")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
