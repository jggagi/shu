extends RefCounted
## Shu's small, deterministic encounter. No UI, Session, clock or disk access.
## Selected references: jggagi/chengping a4a6c1c, src/combat/grid.gd
## (four-neighbour BFS) and combat_controller.gd (discrete rules/presentation events).
## Adapted under the user's two-project authorization; no GameState or assets copied.

var definition: Dictionary = {}
var state: Dictionary = {}
var _skills: Dictionary = {}
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


func configure(data: Dictionary) -> Dictionary:
	var checked := _validate_definition(data)
	if not checked.ok:
		return checked
	definition = data.duplicate(true)
	definition.width = int(definition.width)
	definition.height = int(definition.height)
	definition.obstacles = definition.obstacles.map(func(cell): return [int(cell[0]), int(cell[1])])
	definition.barricades = definition.get("barricades", []).duplicate(true)
	for barricade in definition.barricades:
		barricade.max_hp = int(barricade.get("max_hp", barricade.hp))
		barricade.hp = int(barricade.hp)
		barricade.pos = _a(_v(barricade.pos))
	_skills.clear()
	for skill in definition.skills:
		_skills[str(skill.id)] = skill.duplicate(true)
	var units: Array = []
	for source in definition.units:
		var member: Dictionary = source.duplicate(true)
		member.max_hp = int(member.get("max_hp", member.hp))
		member.hp = int(member.hp)
		member.pos = _a(_v(member.pos))
		member.moved = false
		member.acted = false
		member.guarded = false
		member.move_range = int(member.get("move_range", 3))
		units.append(member)
	var objective: Dictionary = definition.objective.duplicate(true)
	objective.max_hp = int(objective.get("max_hp", objective.hp))
	objective.hp = int(objective.hp)
	objective.pos = _a(_v(objective.pos))
	state = {"round": 1, "phase": "player", "outcome": "", "units": units,
		"objective": objective, "barricades": definition.barricades.duplicate(true),
		"plans": [], "log": [], "revision": 0}
	_log("山道遇袭：护住药篓四轮，或击退全部敌人。")
	_create_plans()
	return {"ok": true, "reason": ""}


func snapshot() -> Dictionary:
	return state.duplicate(true)


func unit(id: String) -> Dictionary:
	return _member(id).duplicate(true)


func reachable(unit_id: String) -> Array:
	var member := _member(unit_id)
	if not _player_ready(member) or bool(member.moved):
		return []
	var routes := _routes(member.pos, int(member.move_range), state.units, unit_id)
	var result: Array = []
	for cell in routes:
		if cell != _v(member.pos):
			result.append(_a(cell))
	return result


func preview(unit_id: String, skill_id: String, target: Array) -> Dictionary:
	var member := _member(unit_id)
	if not _player_ready(member):
		return _failure("当前角色不能行动。")
	if bool(member.acted):
		return _failure("这名队员本轮已经出招。")
	if not _skills.has(skill_id) or not skill_id in member.skills:
		return _failure("这名队员没有这门武学。")
	var skill: Dictionary = _skills[skill_id]
	var result := {"ok": true, "reason": "", "unit_id": unit_id, "skill_id": skill_id,
		"target_id": "", "cells": [], "damage": 0, "push_to": [], "push_path": [],
		"will_interrupt": false, "target_kind": "unit", "barricade_id": "",
		"barricade_damage": 0, "destroys_barricade": false,
		"collision_barricade_id": "", "collision_barricade_pos": []}
	if str(skill.effect) == "guard":
		if not target.is_empty() and (not _valid_cell(target) or target != member.pos):
			return _failure("防守只能作用于自己。")
		result.cells = [member.pos.duplicate()]
		result.target_id = unit_id
		return result
	if not _valid_cell(target):
		return _failure("目标格子无效。")
	if str(skill.effect) in ["pierce", "sweep"]:
		return _area_preview(member, skill, target, result)
	var barricade := _barricade_at(target)
	if not barricade.is_empty() and str(skill.effect) != "strike":
		return _failure("只能用普通剑式直接拆除木栅。")
	if _distance(member.pos, target) > int(skill.range) or not _line_clear(member.pos, target, not barricade.is_empty()):
		return _failure("目标超出距离，或被山石木栅挡住。")
	if not barricade.is_empty():
		result.target_kind = "barricade"
		result.target_id = str(barricade.id)
		result.barricade_id = str(barricade.id)
		result.cells = [target.duplicate()]
		result.damage = int(skill.damage)
		result.barricade_damage = mini(int(barricade.hp), int(skill.damage))
		result.destroys_barricade = int(skill.damage) >= int(barricade.hp)
		return result
	var victim := _at(target, state.units)
	if victim.is_empty() or victim.team != "enemy":
		return _failure("请选择仍在战场上的敌人。")
	result.target_id = str(victim.id)
	result.cells = [target.duplicate()]
	result.damage = int(skill.damage)
	if str(skill.effect) == "push":
		var pushed := _push_destination(member.pos, victim, int(skill.get("push_distance", 2)))
		result.push_to = pushed.to
		result.push_path = pushed.path
		result["collision"] = pushed.collision
		result.damage += int(skill.get("collision_bonus", 0)) if pushed.collision else 0
		result.collision_barricade_id = pushed.barricade_id
		result.collision_barricade_pos = pushed.barricade_pos
		if not str(pushed.barricade_id).is_empty():
			result.barricade_damage = int(_barricade_at(pushed.barricade_pos).hp)
			result.destroys_barricade = true
	elif str(skill.effect) == "interrupt":
		result.will_interrupt = true
	return result


func _area_preview(member: Dictionary, skill: Dictionary, target: Array, result: Dictionary) -> Dictionary:
	# Directional attacks share the exact same footprint for preview and damage.
	# Friends and the medicine cart are immune; rocks and living gates occlude it.
	var offset := _v(target) - _v(member.pos)
	if offset == Vector2i.ZERO or (offset.x != 0 and offset.y != 0) or _distance(member.pos, target) > int(skill.range):
		return _failure("请选择正前方的方向格。")
	var direction := Vector2i(signi(offset.x), signi(offset.y))
	var cells: Array = []
	if str(skill.effect) == "pierce":
		for step: int in range(1, int(skill.range) + 1):
			var cell := _a(_v(member.pos) + direction * step)
			if not _valid_cell(cell) or _blocked(cell):
				break
			cells.append(cell)
		if not target in cells:
			return _failure("剑气被山石木栅挡住。")
	else:
		var front := _a(_v(member.pos) + direction)
		if _blocked(front):
			return _failure("正前方被山石木栅挡住。")
		var side := Vector2i(-direction.y, direction.x)
		for wing: int in [0, -1, 1]:
			var cell := _a(_v(front) + side * wing)
			if _valid_cell(cell) and not _blocked(cell) and _line_clear(member.pos, cell):
				cells.append(cell)
	var targets: Array[String] = []
	var damage_by_target: Dictionary = {}
	var total_damage := 0
	for victim: Dictionary in state.units:
		if str(victim.team) != "enemy" or int(victim.hp) <= 0 or not victim.pos in cells:
			continue
		var id := str(victim.id)
		var applied := mini(int(victim.hp), maxi(0, int(skill.damage) - (3 if victim.get("guarded", false) else 0)))
		targets.append(id)
		damage_by_target[id] = applied
		total_damage += applied
	if targets.is_empty():
		return _failure("这片范围内没有敌人。")
	result.target_id = targets[0]
	result.cells = cells
	result["affected_cells"] = cells.duplicate(true)
	result["targets"] = targets
	result["damage_by_target"] = damage_by_target
	result["total_damage"] = total_damage
	result["shape"] = str(skill.effect)
	result["direction"] = _a(direction)
	result.damage = int(skill.damage)
	return result


func move_unit(unit_id: String, target: Array) -> Dictionary:
	var member := _member(unit_id)
	if not _player_ready(member) or bool(member.get("moved", true)):
		return _failure("这名队员当前不能移动。")
	if not _valid_cell(target) or target == member.pos:
		return _failure("请选择可达的其他格子。")
	var routes := _routes(member.pos, int(member.move_range), state.units, unit_id)
	var key := _v(target)
	if not routes.has(key):
		return _failure("这格无法到达。")
	var before: Array = member.pos.duplicate()
	member.pos = target.duplicate()
	member.moved = true
	_refresh_plans()
	state.revision += 1
	_log(str(member.name) + "移步。")
	return {"ok": true, "reason": "", "events": [{"type": "move", "unit_id": unit_id,
		"from": before, "to": target.duplicate(), "path": routes[key].duplicate(true)}]}


func use_skill(unit_id: String, skill_id: String, target: Array) -> Dictionary:
	var forecast := preview(unit_id, skill_id, target)
	if not forecast.ok:
		return forecast
	var member := _member(unit_id)
	var skill: Dictionary = _skills[skill_id]
	var events: Array = []
	member.acted = true
	if str(skill.effect) == "guard":
		member.guarded = true
		events.append({"type": "guard", "unit_id": unit_id, "target_id": unit_id, "amount": 3})
		_log(str(member.name) + "凝神守势，本轮受伤减少三点。")
	elif str(skill.effect) in ["pierce", "sweep"]:
		var direction := _v(forecast.direction)
		var aim := _a(_v(member.pos) + direction)
		var effect_to: Array = forecast.cells[-1] if str(skill.effect) == "pierce" else aim
		events.append({"type": "attack", "unit_id": unit_id, "target_id": str(forecast.target_id),
			"target_kind": "area", "skill_id": skill_id, "from": member.pos.duplicate(),
			"to": aim, "effect_to": effect_to.duplicate(), "direction": forecast.direction.duplicate(),
			"cells": forecast.cells.duplicate(true), "targets": forecast.targets.duplicate(),
			"amount": int(skill.damage), "total_damage": int(forecast.total_damage)})
		_log(str(member.name) + "使出" + str(skill.label) + "，击中" + str(forecast.targets.size()) + "名来敌。")
		for id: String in forecast.targets:
			_damage(_member(id), int(skill.damage), unit_id, events)
	elif str(forecast.target_kind) == "barricade":
		var barricade := _barricade_at(target)
		events.append({"type": "attack", "unit_id": unit_id, "target_id": str(barricade.id),
			"target_kind": "barricade", "skill_id": skill_id, "from": member.pos.duplicate(),
			"to": barricade.pos.duplicate(), "cells": forecast.cells.duplicate(true), "amount": int(forecast.damage)})
		_log(str(member.name) + "使出" + str(skill.label) + "拆栅。")
		_damage_barricade(barricade, int(forecast.barricade_damage), unit_id, events)
	else:
		var victim := _member(str(forecast.target_id))
		events.append({"type": "attack", "unit_id": unit_id, "target_id": str(victim.id),
			"target_kind": "unit", "skill_id": skill_id, "from": member.pos.duplicate(), "to": victim.pos.duplicate(),
			"cells": forecast.cells.duplicate(true), "amount": int(forecast.damage)})
		_log(str(member.name) + "使出" + str(skill.label) + "。")
		_damage(victim, int(forecast.damage), unit_id, events)
		if int(victim.hp) > 0 and str(skill.effect) == "push":
			var before: Array = victim.pos.duplicate()
			victim.pos = forecast.push_to.duplicate()
			for plan in state.plans:
				if plan.unit_id == victim.id:
					plan.displaced = true
			events.append({"type": "push", "unit_id": unit_id, "target_id": str(victim.id),
				"from": before, "to": victim.pos.duplicate(), "amount": _distance(before, victim.pos)})
			_log(str(victim.name) + ("撞上障碍，攻势被破。" if forecast.get("collision", false) else "被击退，攻击位置改变。"))
		elif int(victim.hp) > 0 and str(skill.effect) == "interrupt":
			for plan in state.plans:
				if plan.unit_id == victim.id:
					plan.interrupted = true
			events.append({"type": "interrupt", "unit_id": unit_id, "target_id": str(victim.id)})
			_log(str(victim.name) + "被封住来势，本轮行动取消。")
		# A lethal hit still breaks the forecast collision obstacle. Its defeated
		# victim stays at its last living position instead of moving a dead body.
		if str(skill.effect) == "push" and not str(forecast.collision_barricade_id).is_empty():
			_damage_barricade(_barricade_at(forecast.collision_barricade_pos), int(forecast.barricade_damage), unit_id, events)
	_refresh_plans()
	_resolve_terminal(events)
	state.revision += 1
	return {"ok": true, "reason": "", "events": events}


func end_round() -> Dictionary:
	if state.is_empty() or str(state.phase) != "player":
		return _failure("当前不能结束这一轮。")
	_refresh_plans()
	var events: Array = []
	# Resolve the displayed movement first, then the displayed attack cells.
	# No hidden retargeting: moving away, pushing or interrupting changes the outcome.
	for plan in state.plans:
		var enemy := _member(str(plan.unit_id))
		if int(enemy.hp) <= 0 or bool(plan.interrupted):
			continue
		if enemy.pos != plan.move_to:
			var before: Array = enemy.pos.duplicate()
			enemy.pos = plan.move_to.duplicate()
			events.append({"type": "move", "unit_id": str(enemy.id), "from": before,
				"to": enemy.pos.duplicate(), "path": plan.path.duplicate(true)})
	for plan in state.plans:
		var enemy := _member(str(plan.unit_id))
		if int(enemy.hp) <= 0 or bool(plan.interrupted):
			continue
		events.append({"type": "attack", "unit_id": str(enemy.id), "from": enemy.pos.duplicate(),
			"to": (plan.cells[-1] if not plan.cells.is_empty() else plan.target).duplicate(),
			"cells": plan.cells.duplicate(true), "amount": int(plan.damage)})
		var hit := false
		for member in state.units:
			if member.team == "player" and int(member.hp) > 0 and member.pos in plan.cells:
				_damage(member, int(plan.damage), str(enemy.id), events)
				hit = true
		if state.objective.pos in plan.cells and int(state.objective.hp) > 0:
			var amount := mini(int(state.objective.hp), int(plan.damage))
			state.objective.hp -= amount
			events.append({"type": "damage", "unit_id": str(enemy.id), "target_id": "objective", "amount": amount})
			_log(str(state.objective.name) + "受损 " + str(amount) + "。")
			hit = true
		if not hit:
			_log(str(enemy.name) + "的攻势落空。")
	_resolve_terminal(events)
	if str(state.phase) == "player" and int(state.round) >= int(definition.survive_rounds):
		state.phase = "won"
		state.outcome = "victory"
		_log("援手赶到，药篓保住了。")
		events.append({"type": "victory", "unit_id": "", "reason": "survived"})
	if str(state.phase) == "player":
		state.round += 1
		for member in state.units:
			member.moved = false
			member.acted = false
			member.guarded = false
		_create_plans()
	state.revision += 1
	return {"ok": true, "reason": "", "events": events}


func abandon() -> Dictionary:
	if state.is_empty() or str(state.phase) != "player":
		return _failure("这一战已经结束。")
	state.phase = "lost"
	state.outcome = "abandoned"
	state.revision += 1
	_log("你带着同伴撤离了山道。")
	return {"ok": true, "reason": "", "events": [{"type": "defeat", "unit_id": "", "reason": "abandoned"}]}


func surrender() -> Dictionary:
	return abandon()


func _create_plans() -> void:
	state.plans = []
	for member in state.units:
		if member.team != "enemy" or int(member.hp) <= 0:
			continue
		var attack: Dictionary = member.attack
		var target: Array = state.objective.pos.duplicate()
		if str(attack.get("target", "objective")) == "nearest_player":
			var best := 100000
			for friend in state.units:
				if friend.team == "player" and int(friend.hp) > 0:
					var distance := _distance(member.pos, friend.pos)
					if distance < best:
						best = distance
						target = friend.pos.duplicate()
		var routes := _routes(member.pos, int(attack.get("move_range", 2)), state.units, str(member.id))
		var chosen := _v(member.pos)
		var best_score := 100000
		for cell in routes:
			var distance := _distance(_a(cell), target)
			var aligned: bool = cell.x == int(target[0]) or cell.y == int(target[1])
			var can_hit: bool = distance <= int(attack.range) and (str(attack.effect) != "line" or aligned) and _line_clear(_a(cell), target)
			var score: int = routes[cell].size() if can_hit else 100 + distance * 10 + routes[cell].size()
			if score < best_score:
				best_score = score
				chosen = cell
		var offsets: Array = []
		for cell in routes[chosen]:
			offsets.append(_a(_v(cell) - _v(member.pos)))
		var direction := _direction(_a(chosen), target)
		state.plans.append({"unit_id": str(member.id), "label": str(attack.label),
			"kind": str(attack.effect), "damage": int(attack.damage), "range": int(attack.range),
			"target": target, "direction": _a(direction), "offsets": offsets,
			"interrupted": false, "displaced": false, "origin": member.pos.duplicate(),
			"move_to": member.pos.duplicate(), "path": [], "cells": []})
	_refresh_plans()


func _refresh_plans() -> void:
	var simulated: Array = state.units.duplicate(true)
	for plan in state.plans:
		var enemy := _at_id(str(plan.unit_id), simulated)
		plan.origin = enemy.pos.duplicate()
		plan.path = [enemy.pos.duplicate()]
		if int(enemy.hp) > 0 and not bool(plan.interrupted) and not bool(plan.displaced):
			var origin := _v(enemy.pos)
			for offset in plan.offsets:
				var next := _a(origin + _v(offset))
				if next == enemy.pos:
					continue
				if not _walkable(next, simulated, str(enemy.id)):
					break
				enemy.pos = next
				plan.path.append(next.duplicate())
		plan.move_to = enemy.pos.duplicate()
		plan.cells = [] if int(enemy.hp) <= 0 or bool(plan.interrupted) else _plan_cells(plan, enemy.pos)


func _plan_cells(plan: Dictionary, from: Array) -> Array:
	if str(plan.kind) == "shot":
		return [plan.target.duplicate()] if _distance(from, plan.target) <= int(plan.range) and _line_clear(from, plan.target) else []
	var result: Array = []
	for step in range(1, int(plan.range) + 1):
		var cell := _a(_v(from) + _v(plan.direction) * step)
		if not _valid_cell(cell) or _blocked(cell):
			break
		result.append(cell)
	return result


func _push_destination(from: Array, victim: Dictionary, amount: int) -> Dictionary:
	var direction := _direction(from, victim.pos)
	var target: Array = victim.pos.duplicate()
	var path: Array = [target.duplicate()]
	var collision := false
	var barricade_id := ""
	var barricade_pos: Array = []
	for step in amount:
		var next := _a(_v(target) + direction)
		if not _walkable(next, state.units, str(victim.id)):
			collision = true
			var barricade := _barricade_at(next)
			if not barricade.is_empty():
				barricade_id = str(barricade.id)
				barricade_pos = next.duplicate()
			break
		target = next
		path.append(next.duplicate())
	return {"to": target, "path": path, "collision": collision,
		"barricade_id": barricade_id, "barricade_pos": barricade_pos}


func _damage_barricade(barricade: Dictionary, amount: int, actor: String, events: Array) -> void:
	var applied := mini(int(barricade.hp), maxi(0, amount))
	barricade.hp -= applied
	events.append({"type": "barricade_damage", "unit_id": actor, "target_id": str(barricade.id),
		"amount": applied, "to": barricade.pos.duplicate(), "hp_after": int(barricade.hp)})
	_log(str(barricade.name) + "受损 " + str(applied) + "。")
	if int(barricade.hp) == 0:
		events.append({"type": "barricade_destroyed", "unit_id": actor,
			"target_id": str(barricade.id), "to": barricade.pos.duplicate()})
		_log(str(barricade.name) + "倒下，通路打开。")


func _damage(victim: Dictionary, amount: int, actor: String, events: Array) -> void:
	var applied := mini(int(victim.hp), maxi(0, amount - (3 if victim.get("guarded", false) else 0)))
	victim.hp -= applied
	events.append({"type": "damage", "unit_id": actor, "target_id": str(victim.id), "amount": applied})
	_log(str(victim.name) + "受伤 " + str(applied) + "。")
	if int(victim.hp) <= 0:
		events.append({"type": "defeat", "unit_id": str(victim.id), "target_id": str(victim.id), "amount": 0})
		_log(str(victim.name) + "退出战场。")


func _resolve_terminal(events: Array) -> void:
	var friends := 0
	var enemies := 0
	for member in state.units:
		if int(member.hp) > 0:
			if member.team == "player": friends += 1
			else: enemies += 1
	if int(state.objective.hp) <= 0 or friends == 0:
		state.phase = "lost"
		state.outcome = "defeat"
		_log("药篓失守。" if int(state.objective.hp) <= 0 else "两人力竭，只得退开。")
		events.append({"type": "defeat", "unit_id": "", "reason": "objective" if int(state.objective.hp) <= 0 else "party"})
	elif enemies == 0:
		state.phase = "won"
		state.outcome = "victory"
		_log("来敌尽退，山道重归平静。")
		events.append({"type": "victory", "unit_id": "", "reason": "defeated_all"})


func _routes(from: Array, limit: int, units: Array, excluding: String) -> Dictionary:
	var start := _v(from)
	var paths: Dictionary = {start: [from.duplicate()]}
	var queue: Array = [start]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		if paths[here].size() - 1 >= limit:
			continue
		for direction in DIRECTIONS:
			var next: Vector2i = here + direction
			if paths.has(next) or not _walkable(_a(next), units, excluding):
				continue
			var path: Array = paths[here].duplicate(true)
			path.append(_a(next))
			paths[next] = path
			queue.append(next)
	return paths


func _walkable(cell: Array, units: Array, excluding: String) -> bool:
	if not _valid_cell(cell) or _blocked(cell) or cell == state.objective.pos:
		return false
	for member in units:
		if member.id != excluding and int(member.hp) > 0 and member.pos == cell:
			return false
	return true


func _line_clear(from: Array, to: Array, allow_target_barricade: bool = false) -> bool:
	# Exact grid supercover; a diagonal cannot slip between two touching rocks.
	var cursor := _v(from)
	var target := _v(to)
	var delta := target - cursor
	var step_x := signi(delta.x)
	var step_y := signi(delta.y)
	var increment_x := 1.0 / float(absi(delta.x)) if delta.x != 0 else INF
	var increment_y := 1.0 / float(absi(delta.y)) if delta.y != 0 else INF
	var next_x := increment_x * 0.5
	var next_y := increment_y * 0.5
	while cursor != target:
		if absf(next_x - next_y) < 0.00000001:
			if _blocked([cursor.x + step_x, cursor.y]) or _blocked([cursor.x, cursor.y + step_y]):
				return false
			cursor += Vector2i(step_x, step_y)
			next_x += increment_x
			next_y += increment_y
		elif next_x < next_y:
			cursor.x += step_x
			next_x += increment_x
		else:
			cursor.y += step_y
			next_y += increment_y
		if _a(cursor) in definition.obstacles or (not (allow_target_barricade and cursor == target) and not _barricade_at(_a(cursor)).is_empty()):
			return false
	return true


func _barricade_at(cell: Array) -> Dictionary:
	for barricade in state.get("barricades", []):
		if int(barricade.hp) > 0 and barricade.pos == cell:
			return barricade
	return {}


func _blocked(cell: Array) -> bool:
	return cell in definition.obstacles or not _barricade_at(cell).is_empty()


func _player_ready(member: Dictionary) -> bool:
	return not state.is_empty() and str(state.phase) == "player" and not member.is_empty() and member.team == "player" and int(member.hp) > 0


func _member(id: String) -> Dictionary:
	return _at_id(id, state.get("units", []))


func _at_id(id: String, units: Array) -> Dictionary:
	for member in units:
		if str(member.id) == id: return member
	return {}


func _at(cell: Array, units: Array) -> Dictionary:
	for member in units:
		if int(member.hp) > 0 and member.pos == cell: return member
	return {}


func _direction(from: Array, to: Array) -> Vector2i:
	var delta := _v(to) - _v(from)
	return Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))


func _distance(from: Array, to: Array) -> int:
	return absi(int(from[0]) - int(to[0])) + absi(int(from[1]) - int(to[1]))


func _v(cell: Array) -> Vector2i:
	return Vector2i(int(cell[0]), int(cell[1]))


func _a(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


func _valid_cell(value: Variant, source: Dictionary = {}) -> bool:
	var data: Dictionary = definition if source.is_empty() else source
	return value is Array and value.size() == 2 and _integer(value[0], 0, int(data.get("width", 0)) - 1) and _integer(value[1], 0, int(data.get("height", 0)) - 1)


func _validate_definition(data: Dictionary) -> Dictionary:
	if not _integer(data.get("width"), 4, 32) or not _integer(data.get("height"), 4, 32) or not _integer(data.get("survive_rounds"), 1, 20):
		return _failure("战场尺寸或轮数无效。")
	if not data.get("obstacles") is Array or not data.get("units") is Array or not data.get("skills") is Array or not data.get("objective") is Dictionary:
		return _failure("战场数据缺失。")
	var occupied: Array = []
	for cell in data.obstacles:
		if not _valid_cell(cell, data) or _v(cell) in occupied: return _failure("障碍格子无效或重复。")
		occupied.append(_v(cell))
	var objective: Dictionary = data.objective
	if not _valid_cell(objective.get("pos"), data) or _v(objective.pos) in occupied or not _positive_hp(objective) or not objective.get("name") is String:
		return _failure("保护目标无效。")
	occupied.append(_v(objective.pos))
	var skills: Dictionary = {}
	for skill in data.skills:
		if not skill is Dictionary or not skill.get("id") is String or str(skill.id).is_empty() or skills.has(skill.id): return _failure("武学标识无效或重复。")
		if not skill.get("label") is String or not skill.get("description") is String or not str(skill.get("effect", "")) in ["strike", "push", "interrupt", "guard", "pierce", "sweep"]: return _failure("武学效果无效。")
		if not _integer(skill.get("range"), 0 if skill.effect == "guard" else 1, 32) or not _integer(skill.get("damage"), 0, 1000): return _failure("武学距离或伤害无效。")
		if (skill.effect == "pierce" and int(skill.range) != 2) or (skill.effect == "sweep" and int(skill.range) != 1): return _failure("方向武学的范围无效。")
		if skill.effect == "push" and (not _integer(skill.get("push_distance", 2), 1, 8) or not _integer(skill.get("collision_bonus", 0), 0, 1000)): return _failure("击退参数无效。")
		skills[skill.id] = true
	var ids: Dictionary = {}
	var friends := 0
	var enemies := 0
	for member in data.units:
		if not member is Dictionary or not member.get("id") is String or str(member.id).is_empty() or ids.has(member.id) or member.id == "objective": return _failure("人物标识无效或重复。")
		if not member.get("name") is String or not member.get("role") is String or not str(member.get("team", "")) in ["player", "enemy"] or not _positive_hp(member): return _failure("人物资料无效。")
		if not _valid_cell(member.get("pos"), data) or _v(member.pos) in occupied or not _integer(member.get("move_range", 3), 1, 10): return _failure("人物位置或移动距离无效。")
		if not member.get("skills") is Array: return _failure("人物武学资料无效。")
		var known: Array = []
		for id in member.skills:
			if not id is String or not skills.has(id) or id in known: return _failure("人物引用未知或重复武学。")
			known.append(id)
		if member.team == "enemy":
			var attack: Variant = member.get("attack")
			if not attack is Dictionary or not str(attack.get("effect", "")) in ["melee", "line", "shot"] or not attack.get("label") is String: return _failure("敌人预告资料无效。")
			if not _integer(attack.get("damage"), 1, 1000) or not _integer(attack.get("range"), 1, 32) or not _integer(attack.get("move_range", 2), 0, 10) or not str(attack.get("target", "objective")) in ["objective", "nearest_player"]: return _failure("敌人攻击参数无效。")
			enemies += 1
		else: friends += 1
		ids[member.id] = true
		occupied.append(_v(member.pos))
	if friends == 0 or enemies == 0: return _failure("战场需要双方人物。")
	if not data.get("barricades", []) is Array:
		return _failure("木栅资料必须是列表。")
	for barricade in data.get("barricades", []):
		if not barricade is Dictionary or not barricade.get("id") is String or str(barricade.id).strip_edges().is_empty() or barricade.id == "objective" or ids.has(barricade.id):
			return _failure("木栅标识无效、重复或与人物冲突。")
		if not barricade.get("name") is String or str(barricade.name).strip_edges().is_empty() or not _positive_hp(barricade):
			return _failure("木栅名称或耐久无效。")
		if not _valid_cell(barricade.get("pos"), data) or _v(barricade.pos) in occupied:
			return _failure("木栅位置无效或与战场物件重叠。")
		ids[barricade.id] = true
		occupied.append(_v(barricade.pos))
	return {"ok": true, "reason": ""}


func _positive_hp(value: Dictionary) -> bool:
	return _integer(value.get("hp"), 1, 10000) and _integer(value.get("max_hp", value.get("hp")), int(value.get("hp", 1)), 10000)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": [], "cells": []}


func _log(message: String) -> void:
	state.log.append(message)
	if state.log.size() > 18: state.log.pop_front()
