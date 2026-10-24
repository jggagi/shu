extends RefCounted
## Optional spatial content and save boundary. Persistent values belong to Session.

const NavigationScript = preload("res://addons/cultivation_mode/town_navigation.gd")

func maps(pack: Dictionary) -> Dictionary:
	return _dict(_dict(pack.get("walks")).get("scenes"))

func enabled(pack: Dictionary) -> bool:
	return not maps(pack).is_empty()

func validate(pack: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var value: Variant = pack.get("walks", {})
	if not value is Dictionary:
		return ["walks: 需要对象"]
	var walks: Dictionary = value
	if walks.is_empty():
		return errors
	if not _keys(walks, ["schema_version", "scenes"]) or not _integer(walks.get("schema_version")) or int(walks.get("schema_version", 0)) != 1:
		errors.append("walks: 仅支持 schema_version 1 与 scenes")
	var definitions: Dictionary = maps(pack)
	if not walks.get("scenes") is Dictionary or definitions.is_empty() or definitions.size() > 8:
		errors.append("walks.scenes: 需要1至8张地图")
	var registered_scenes: Dictionary = _dict(pack.get("scenes"))
	var actions: Dictionary = _dict(pack.get("actions"))
	var interaction_ids: Dictionary = {}
	var action_ids: Dictionary = {}
	for sid: Variant in definitions:
		var where: String = "walks.scenes." + str(sid)
		var definition: Dictionary = _dict(definitions[sid])
		if not sid is String or not registered_scenes.has(sid) or definition.is_empty():
			errors.append(where + ": 场景未注册或地图无效")
			continue
		if not _vector(definition.get("size")) or float(definition.get("size", [0, 0])[0]) <= 0 or float(definition.get("size", [0, 0])[1]) <= 0:
			errors.append(where + ".size: 需要正整数宽高")
		if not _rect(definition.get("floor")):
			errors.append(where + ".floor: 需要整数矩形")
		if not _vector(definition.get("spawn")):
			errors.append(where + ".spawn: 需要整数坐标")
		for key: String in ["actor_radius", "cell_size"]:
			if not _integer(definition.get(key)) or int(definition.get(key, 0)) < 1 or int(definition.get(key, 0)) > 100:
				errors.append(where + "." + key + ": 需要1至100的整数")
		if _integer(definition.get("cell_size")) and int(definition.get("cell_size", 0)) % 2 != 0:
			errors.append(where + ".cell_size: 整数脚点需要偶数格距")
		var obstacles: Variant = definition.get("obstacles")
		if not obstacles is Array or (obstacles is Array and obstacles.size() > 64):
			errors.append(where + ".obstacles: 需要至多64个矩形")
		else:
			for obstacle: Variant in obstacles:
				if not _rect(obstacle): errors.append(where + ".obstacles: 矩形无效")
		if not errors.is_empty():
			continue
		var size: Vector2 = _point(definition.size)
		var floor_rect: Rect2 = Rect2(_point(definition.floor.slice(0, 2)), _point(definition.floor.slice(2, 4)))
		if not Rect2(Vector2.ZERO, size).encloses(floor_rect):
			errors.append(where + ".floor: 超出地图")
		var nav = NavigationScript.new()
		nav.configure(definition, false)
		if nav.blocked(_point(definition.spawn)):
			errors.append(where + ".spawn: 不能位于障碍或边界外")
		var interactions: Dictionary = _dict(definition.get("interactions"))
		if not definition.get("interactions") is Dictionary or interactions.is_empty() or interactions.size() > 16:
			errors.append(where + ".interactions: 需要1至16个互动点")
		for iid: Variant in interactions:
			var here: String = where + ".interactions." + str(iid)
			var item: Dictionary = _dict(interactions[iid])
			if not _id(iid) or interaction_ids.has(iid): errors.append(here + ": 标识无效或重复")
			interaction_ids[iid] = true
			if not item.get("label") is String or str(item.get("label", "")).is_empty(): errors.append(here + ".label: 缺少名称")
			if not _vector(item.get("position")) or (_vector(item.get("position")) and not floor_rect.has_point(_point(item.position))): errors.append(here + ".position: 需要地图内整数坐标")
			elif nav.blocked(_point(item.position)): errors.append(here + ".position: 互动锚点必须位于可走空地")
			if not _integer(item.get("radius")) or int(item.get("radius", 0)) < 16 or int(item.get("radius", 0)) > 160: errors.append(here + ".radius: 需要16至160的整数")
			var owned: Array = [item.get("action", "")]
			if item.has("repeat_action"):
				owned.append(item.repeat_action)
				var seen: Variant = item.get("seen_flag")
				if not _id(seen) or not _dict(pack.get("initial_flags")).has(seen): errors.append(here + ".seen_flag: 旗标未登记")
			elif item.has("seen_flag"):
				errors.append(here + ".seen_flag: 需要重复回应行动")
			for aid: Variant in owned:
				var action: Dictionary = _dict(actions.get(aid))
				if not _id(aid) or action.is_empty() or action.get("menu", true) != false or _array(action.get("scenes")) != [sid] or action.get("event", "") != "" or action.has("presentation"):
					errors.append(here + ".action: 需要属于本场景的非菜单普通行动")
				if action_ids.has(aid): errors.append(here + ".action: 互动行动不能重复绑定")
				action_ids[aid] = true
			if item.has("repeat_action") and _dict(_dict(actions.get(item.get("action", ""))).get("set_flags")).get(item.get("seen_flag"), false) != true:
				errors.append(here + ".seen_flag: 初次互动必须登记重访旗标")
	# Contextual spatial actions cannot be called through an event choice.
	for event: Variant in _dict(pack.get("events")).values():
		for node: Variant in _dict(_dict(event).get("nodes")).values():
			for option: Variant in _array(_dict(node).get("options")):
				if action_ids.has(_dict(option).get("action", "")): errors.append("walks: 互动行动不能由对话选项绕过距离门禁")
	return errors

func initial_state(pack: Dictionary) -> Dictionary:
	var positions: Dictionary = {}
	for sid: Variant in maps(pack):
		var spawn: Array = _dict(maps(pack)[sid]).get("spawn", [])
		positions[sid] = [int(spawn[0]), int(spawn[1])]
	return {"schema_version": 1, "positions": positions}

func snapshot_error(pack: Dictionary, candidate: Dictionary) -> String:
	if not enabled(pack):
		return "存档包含未声明的探索状态" if candidate.has("exploration") else ""
	var value: Variant = candidate.get("exploration")
	if not value is Dictionary or not _keys(value, ["schema_version", "positions"]):
		return "存档探索字段无效"
	if not _integer(value.get("schema_version")) or int(value.get("schema_version", 0)) != 1:
		return "存档探索版本不兼容"
	var positions: Variant = value.get("positions")
	var definitions: Dictionary = maps(pack)
	if not positions is Dictionary or not _keys(positions, definitions.keys()):
		return "存档探索地点不匹配"
	for sid: Variant in definitions:
		if not _vector(positions.get(sid)):
			return "存档探索位置无效"
		var nav = NavigationScript.new()
		nav.configure(definitions[sid], false)
		if nav.blocked(_point(positions[sid])):
			return "存档探索位置位于障碍或边界外"
	return ""

func interaction(pack: Dictionary, interaction_id: String) -> Dictionary:
	for sid: Variant in maps(pack):
		var items: Dictionary = _dict(_dict(maps(pack)[sid]).get("interactions"))
		if items.has(interaction_id):
			var item: Dictionary = _dict(items[interaction_id]).duplicate(true)
			item["scene_id"] = sid
			return item
	return {}

func action_for(pack: Dictionary, snapshot: Dictionary, item: Dictionary) -> String:
	var seen: String = str(item.get("seen_flag", ""))
	if not seen.is_empty() and bool(_dict(snapshot.get("flags")).get(seen, false)):
		return str(item.get("repeat_action", ""))
	return str(item.get("action", ""))

func valid_receipt(pack: Dictionary, action_id: String, interaction_id: String) -> bool:
	var item: Dictionary = interaction(pack, interaction_id)
	return not item.is_empty() and action_id in [item.get("action", ""), item.get("repeat_action", "")] and not action_id.is_empty()

func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value)

func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and abs(float(value[0])) <= 16384 and abs(float(value[1])) <= 16384

func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _rect(value: Variant) -> bool:
	return value is Array and value.size() == 4 and _integer(value[0]) and _integer(value[1]) and _integer(value[2]) and _integer(value[3]) and float(value[2]) > 0 and float(value[3]) > 0 and value.all(func(n: Variant) -> bool: return abs(float(n)) <= 16384)

func _id(value: Variant) -> bool:
	return value is String and value.length() <= 48 and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value) != null

func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key: Variant in value:
		if not expected.has(key): return false
	return true
