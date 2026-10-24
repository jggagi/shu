extends RefCounted
## Data-only branch policy. Only apply() mutates the supplied staged state.

func validate(pack: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not pack.get("quests", {}) is Dictionary: return ["quests: 需要对象"]
	var quests: Dictionary = _dict(pack.get("quests"))
	var scenes: Dictionary = _dict(pack.get("scenes"))
	var actions: Dictionary = _dict(pack.get("actions"))
	var owned_flags: Dictionary = {}
	var scene_owners: Dictionary = {}
	var action_owners: Dictionary = {}
	for qid: Variant in quests:
		var where: String = "quests." + str(qid)
		var q: Dictionary = _dict(quests[qid])
		if not _id(qid) or q.is_empty(): errors.append(where + ": 标识或对象无效")
		for key: String in ["title", "boundary_text"]:
			if not q.get(key) is String or str(q.get(key, "")).is_empty(): errors.append(where + "." + key + ": 需要文字")
		for key: String in ["active_flag", "complete_flag"]:
			var flag: String = str(q.get(key, ""))
			if not _id(q.get(key)) or owned_flags.has(flag): errors.append(where + "." + key + ": 旗标无效或重复")
			else: owned_flags[flag] = true
			if bool(_dict(pack.get("initial_flags")).get(flag, false)): errors.append(where + "." + key + ": 不得预先开始或完成")
		var locations: Array = _array(q.get("scenes"))
		if locations.is_empty() or not q.get("scenes") is Array: errors.append(where + ".scenes: 需要场景")
		for sid: Variant in locations:
			if not sid is String or not scenes.has(sid): errors.append(where + ".scenes: 场景未注册")
			elif scene_owners.has(sid): errors.append(where + ".scenes: 不能与另一支线共用占用场景")
			else: scene_owners[sid] = qid
		if not scenes.has(q.get("return_scene", "")): errors.append(where + ".return_scene: 场景未注册")
		if locations.has(pack.get("initial_scene", "")) or locations.has(q.get("return_scene", "")): errors.append(where + ": 支线场景与起点及返回地点必须分开")
		var registered: Array = _array(q.get("actions"))
		if registered.is_empty() or not q.get("actions") is Array: errors.append(where + ".actions: 需要行动列表")
		var seen_actions: Dictionary = {}
		for aid: Variant in registered:
			if not aid is String or not actions.has(aid) or seen_actions.has(aid): errors.append(where + ".actions: 行动无效或重复")
			else: seen_actions[aid] = true
			if action_owners.has(aid): errors.append(where + ".actions: 支线行动须有独立计数标识")
			else: action_owners[aid] = qid
		for key: String in ["rest_action", "return_action"]:
			if not q.get(key) is String or not registered.has(q.get(key)): errors.append(where + "." + key + ": 行动未登记")
		var returning: Dictionary = _dict(actions.get(q.get("return_action", "")))
		if returning.get("return_quest", "") != qid or returning.get("target_scene", "") != q.get("return_scene", ""): errors.append(where + ".return_action: 返回规则不匹配")
		if returning.get("menu", false) != true or _dict(actions.get(q.get("rest_action", ""))).get("menu", false) != true: errors.append(where + ": 歇息与返回须为菜单行动")
		var entrances: int = 0
		for aid: Variant in registered:
			if _dict(actions.get(aid)).get("enter_quest", "") == qid: entrances += 1
		if entrances == 0: errors.append(where + ": 未登记接受行动")
		var stages: Array = _array(q.get("stages"))
		if stages.is_empty() or stages.size() > 32 or not q.get("stages") is Array: errors.append(where + ".stages: 需要1至32个阶段")
		var stage_ids: Dictionary = {}
		for i: int in range(stages.size()):
			var s: Dictionary = _dict(stages[i])
			var stage_id: String = str(s.get("id", ""))
			if not _id(s.get("id")) or stage_ids.has(stage_id): errors.append(where + ".stages: 阶段标识无效或重复")
			else: stage_ids[stage_id] = true
			if not s.get("label") is String or str(s.get("label", "")).is_empty(): errors.append(where + ".stages: 缺少阶段名称")
			var flag: String = str(s.get("complete_flag", ""))
			if not _id(s.get("complete_flag")) or owned_flags.has(flag): errors.append(where + ".stages: 完成旗标无效或重复")
			else: owned_flags[flag] = true
			var req: Dictionary = _dict(s.get("requires"))
			var flags: Dictionary = _dict(req.get("flags"))
			if req.size() != 1 or not req.has("flags") or flags.is_empty(): errors.append(where + ".stages: 需要非空旗标条件")
			for f: Variant in flags:
				if not _id(f) or not flags[f] is bool or flags[f] != true: errors.append(where + ".stages: 只接受正向布尔旗标条件")
			if not s.get("terminal") is bool or (s.get("terminal", false) == true and i != stages.size() - 1): errors.append(where + ".stages: 只有最后阶段可为整条终点")
			if bool(_dict(pack.get("initial_flags")).get(flag, false)): errors.append(where + ".stages: 不得预先完成")
	for aid: Variant in actions:
		var a: Dictionary = _dict(actions[aid])
		var enter: Variant = a.get("enter_quest", "")
		var leave: Variant = a.get("return_quest", "")
		if not enter is String or not leave is String:
			errors.append("actions." + str(aid) + ": 支线引用必须为文字")
			continue
		if enter != "" and leave != "": errors.append("actions." + str(aid) + ": 不能同时进入和返回")
		for qid: String in [enter, leave]:
			if qid.is_empty(): continue
			var q: Dictionary = _dict(quests.get(qid))
			if q.is_empty() or not _array(q.get("actions")).has(aid): errors.append("actions." + str(aid) + ": 支线或其行动未注册")
			if a.has("presentation") or a.get("event", "") != "": errors.append("actions." + str(aid) + ": 支线进出不能重入对话或动作")
		if enter != "":
			var q: Dictionary = _dict(quests.get(enter))
			if a.get("menu", true) != false or not _array(q.get("scenes")).has(a.get("target_scene", "")): errors.append("actions." + str(aid) + ": 接受必须从选择进入支线场景")
	for qid: Variant in quests:
		var q: Dictionary = _dict(quests[qid])
		for aid: Variant in _array(q.get("actions")):
			var a: Dictionary = _dict(actions.get(aid))
			if a.get("event", "") != "" or a.has("presentation"): errors.append("quests." + str(qid) + ": 本版支线行动不能开启对话或演出")
			var target: String = str(a.get("target_scene", ""))
			if target != "" and a.get("return_quest", "") != qid and not _array(q.get("scenes")).has(target): errors.append("quests." + str(qid) + ": 非返回行动不能离开支线")
	var object_ids: Dictionary = {}
	var object_actions: Dictionary = {}
	var inspected_writers: Dictionary = {}
	var once_owners: Dictionary = {}
	for sid: Variant in scenes:
		var scene: Dictionary = _dict(scenes[sid])
		if scene.has("objects") and not scene.objects is Array: errors.append("scenes." + str(sid) + ".objects: 需要数组")
		for raw: Variant in _array(scene.get("objects")):
			var o: Dictionary = _dict(raw)
			var where: String = "scenes." + str(sid) + ".objects." + str(o.get("id", ""))
			var oid: String = str(o.get("id", ""))
			if not _qualified_id(o.get("id")) or object_ids.has(oid): errors.append(where + ": 物件标识无效或重复")
			else: object_ids[oid] = true
			for key: String in ["label", "description"]:
				if not o.get(key) is String or str(o.get(key, "")).is_empty(): errors.append(where + "." + key + ": 需要文字")
			var q: Dictionary = _dict(quests.get(o.get("quest", "")))
			if q.is_empty() or not _array(q.get("scenes")).has(sid): errors.append(where + ": 物件不属于此支线场景")
			if _stage(q, str(o.get("stage", ""))).is_empty(): errors.append(where + ": 阶段未注册")
			var inspected_flag: String = str(o.get("inspected_flag", ""))
			if not _id(o.get("inspected_flag")) or owned_flags.has(inspected_flag) or inspected_writers.has(inspected_flag): errors.append(where + ": 调查旗标无效或重复")
			else: inspected_writers[inspected_flag] = str(o.get("inspect_action", ""))
			if bool(_dict(pack.get("initial_flags")).get(inspected_flag, false)): errors.append(where + ": 不得预先调查物件")
			if not _normalized(o.get("rect"), 4, true) or not _normalized(o.get("anchor"), 2, false): errors.append(where + ": 热点位置无效")
			var texture: Variant = o.get("texture")
			var region: Array = _array(o.get("region"))
			if not texture is String: errors.append(where + ".texture: 需要资源路径")
			elif texture != "":
				if not texture.begins_with("res://assets/") or ".." in texture or not ResourceLoader.exists(texture, "Texture2D"): errors.append(where + ".texture: 图像不存在")
				elif region.size() == 4 and region.all(func(n: Variant) -> bool: return _integer(n)):
					var tex: Texture2D = load(texture) as Texture2D
					if tex == null or region[0] < 0 or region[1] < 0 or region[2] <= 0 or region[3] <= 0 or region[0]+region[2] > tex.get_width() or region[1]+region[3] > tex.get_height(): errors.append(where + ".region: 区域越界")
				else: errors.append(where + ".region: 需要四个整数")
			elif not region.is_empty(): errors.append(where + ".region: 无图像不能裁切")
			if not o.get("actions") is Array: errors.append(where + ".actions: 需要列表")
			var ids: Array = [o.get("inspect_action", "")]
			ids.append_array(_array(o.get("actions")))
			for aid: Variant in ids:
				var a: Dictionary = _dict(actions.get(aid))
				if not aid is String or a.is_empty() or object_actions.has(aid): errors.append(where + ": 每个物件须使用独立的已登记行动")
				else: object_actions[aid] = true
				if not _array(q.get("actions")).has(aid) or not _array(a.get("scenes")).has(sid): errors.append(where + ": 物件行动位置不匹配")
				if a.get("menu", true) != false or a.get("event", "") != "" or a.get("target_scene", "") != "" or a.has("presentation") or a.has("enter_quest") or a.has("return_quest"): errors.append(where + ": 物件行动只能从当前物件直接执行")
				var once: String = str(a.get("once_key", ""))
				if not once.is_empty():
					if once_owners.has(once): errors.append(where + ": 每个一次行为须有独立记录")
					else: once_owners[once] = str(aid)
			var inspect: Dictionary = _dict(actions.get(o.get("inspect_action", "")))
			if inspect.get("once_key", "") != o.get("inspected_flag", "") or inspect.get("duration", -1) != 0 or not _dict(inspect.get("costs")).is_empty() or not _dict(inspect.get("gains")).is_empty(): errors.append(where + ": 直接查看必须免费且只记录一次")
	for aid: Variant in actions:
		var a: Dictionary = _dict(actions[aid])
		var once: String = str(a.get("once_key", ""))
		if owned_flags.has(once) or (inspected_writers.has(once) and inspected_writers[once] != aid): errors.append("actions." + str(aid) + ": 不能写入支线保留旗标")
		for flag: Variant in _dict(a.get("set_flags")):
			if owned_flags.has(flag) or inspected_writers.has(flag): errors.append("actions." + str(aid) + ": 不能改写支线或调查旗标")
		for raw: Variant in _array(a.get("bonuses")):
			var bonus: Dictionary = _dict(raw)
			if bonus.get("consume", false) == true and (owned_flags.has(bonus.get("flag", "")) or inspected_writers.has(bonus.get("flag", ""))): errors.append("actions." + str(aid) + ": 不能消费支线或调查旗标")
	return errors

func known_flags(pack: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in _dict(pack.get("quests")).values():
		var q: Dictionary = _dict(raw)
		for key: String in ["active_flag", "complete_flag"]: result[str(q.get(key, ""))] = true
		for raw_stage: Variant in _array(q.get("stages")):
			var s: Dictionary = _dict(raw_stage)
			result[str(s.get("complete_flag", ""))] = true
			for flag: Variant in _dict(_dict(s.get("requires")).get("flags")): result[str(flag)] = true
	for scene: Variant in _dict(pack.get("scenes")).values():
		for o: Variant in _array(_dict(scene).get("objects")): result[str(_dict(o).get("inspected_flag", ""))] = true
	result.erase("")
	return result

func active(pack: Dictionary, state: Dictionary) -> Dictionary:
	var flags: Dictionary = _dict(state.get("flags"))
	for qid: Variant in _dict(pack.get("quests")):
		var q: Dictionary = _dict(_dict(pack.get("quests"))[qid])
		if not bool(flags.get(q.get("active_flag", ""), false)): continue
		var stages: Array = _array(q.get("stages"))
		var current: Dictionary = {}
		var completed: Array[String] = []
		for raw: Variant in stages:
			var s: Dictionary = _dict(raw)
			if bool(flags.get(s.get("complete_flag", ""), false)): completed.append(str(s.get("id", "")))
			elif current.is_empty(): current = s
		if current.is_empty() and not stages.is_empty(): current = _dict(stages.back())
		var seen: int = 0
		var total: int = 0
		for scene: Variant in _dict(pack.get("scenes")).values():
			for raw: Variant in _array(_dict(scene).get("objects")):
				var o: Dictionary = _dict(raw)
				if o.get("quest", "") == qid and o.get("stage", "") == current.get("id", ""):
					total += 1
					if bool(flags.get(o.get("inspected_flag", ""), false)): seen += 1
		return {"id":str(qid),"title":str(q.get("title", "")),"stage_id":str(current.get("id", "")),"stage_label":str(current.get("label", "")),"stage_complete":bool(flags.get(current.get("complete_flag", ""),false)),"complete":bool(flags.get(q.get("complete_flag", ""),false)),"seen":seen,"total":total,"rest_action":str(q.get("rest_action", "")),"return_action":str(q.get("return_action", "")),"boundary_text":str(q.get("boundary_text", "")),"completed_stages":completed,"scenes":_array(q.get("scenes")).duplicate()}
	return {}

func check_action(pack: Dictionary, state: Dictionary, action_id: String) -> String:
	var a: Dictionary = _dict(_dict(pack.get("actions")).get(action_id))
	var context: Dictionary = active(pack, state)
	var enter: String = str(a.get("enter_quest", ""))
	var leave: String = str(a.get("return_quest", ""))
	if not enter.is_empty():
		if not context.is_empty(): return "请先完成当前支线"
		var q: Dictionary = _dict(_dict(pack.get("quests")).get(enter))
		if q.is_empty(): return "支线未注册"
		if bool(_dict(state.get("flags")).get(q.get("complete_flag", ""),false)): return "此支线已经完成"
	if context.is_empty():
		if not leave.is_empty(): return "当前不在这段支线中"
		return ""
	var q: Dictionary = _dict(_dict(pack.get("quests")).get(context.id))
	if not _array(q.get("actions")).has(action_id): return "支线尚未结束，请留在当前场景"
	if not leave.is_empty():
		if leave != context.id or action_id != q.get("return_action", ""): return "返回入口不匹配"
		if not context.complete: return "整条支线尚未完成，暂不能返回养成"
	else:
		var target: String = str(a.get("target_scene", ""))
		if not target.is_empty() and not _array(q.get("scenes")).has(target): return "支线尚未结束，暂不能离开"
	return ""

func apply(pack: Dictionary, next_state: Dictionary, action: Dictionary) -> void:
	var flags: Dictionary = _dict(next_state.get("flags"))
	var quests: Dictionary = _dict(pack.get("quests"))
	var enter: String = str(action.get("enter_quest", ""))
	if not enter.is_empty(): flags[str(_dict(quests.get(enter)).get("active_flag", ""))] = true
	for qid: Variant in quests:
		var q: Dictionary = _dict(quests[qid])
		if not bool(flags.get(q.get("active_flag", ""), false)): continue
		for raw: Variant in _array(q.get("stages")):
			var s: Dictionary = _dict(raw)
			if not _matches(flags, _dict(_dict(s.get("requires")).get("flags"))): break
			flags[str(s.get("complete_flag", ""))] = true
			if bool(s.get("terminal",false)): flags[str(q.get("complete_flag", ""))] = true
	var leave: String = str(action.get("return_quest", ""))
	if not leave.is_empty(): flags[str(_dict(quests.get(leave)).get("active_flag", ""))] = false
	next_state["flags"] = flags

func registered_object(pack: Dictionary, object_id: String) -> Dictionary:
	for sid: Variant in _dict(pack.get("scenes")):
		for raw: Variant in _array(_dict(_dict(pack.get("scenes"))[sid]).get("objects")):
			var o: Dictionary = _dict(raw)
			if o.get("id", "") == object_id:
				var result: Dictionary = o.duplicate(true)
				result["scene_id"] = str(sid)
				return result
	return {}

func object_for(pack: Dictionary, state: Dictionary, object_id: String) -> Dictionary:
	var o: Dictionary = registered_object(pack, object_id)
	var q: Dictionary = active(pack, state)
	if o.is_empty() or q.is_empty() or o.get("quest", "") != q.get("id", "") or o.get("scene_id", "") != state.get("scene", ""): return {}
	if o.get("stage", "") != q.get("stage_id", "") and not _array(q.get("completed_stages")).has(o.get("stage", "")): return {}
	return o

func object_action_error(pack: Dictionary, state: Dictionary, object_id: String, action_id: String) -> String:
	var o: Dictionary = object_for(pack, state, object_id)
	if o.is_empty(): return "当前场景没有这件可调查物品"
	if action_id != o.get("inspect_action", "") and not _array(o.get("actions")).has(action_id): return "这件物品没有该行动"
	return check_action(pack, state, action_id)

func object_views(pack: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in _array(_dict(_dict(pack.get("scenes")).get(state.get("scene", ""))).get("objects")):
		var o: Dictionary = object_for(pack, state, str(_dict(raw).get("id", "")))
		if o.is_empty(): continue
		o["inspected"] = bool(_dict(state.get("flags")).get(o.get("inspected_flag", ""), false))
		result.append(o)
	return result

func snapshot_error(pack: Dictionary, state: Dictionary) -> String:
	var flags: Dictionary = _dict(state.get("flags"))
	var counts: Dictionary = _dict(state.get("counts"))
	var active_count: int = 0
	for qid: Variant in _dict(pack.get("quests")):
		var q: Dictionary = _dict(_dict(pack.get("quests"))[qid])
		var running: bool = bool(flags.get(q.get("active_flag", ""),false))
		var complete: bool = bool(flags.get(q.get("complete_flag", ""),false))
		var entries: int = 0
		var transactions: int = 0
		for aid: Variant in _array(q.get("actions")):
			transactions += int(counts.get(aid, 0))
			if _dict(_dict(pack.get("actions")).get(aid)).get("enter_quest", "") == qid: entries += int(counts.get(aid, 0))
		var returns: int = int(counts.get(q.get("return_action", ""), 0))
		if entries > 1 or returns > 1 or (entries == 0 and transactions != 0) or (running and (entries != 1 or returns != 0)) or (not running and entries > 0 and (not complete or returns != 1)): return "存档支线进出回执不一致"
		if running: active_count += 1
		if running and not _array(q.get("scenes")).has(state.get("scene", "")): return "存档支线与地点不一致"
		if not running and _array(q.get("scenes")).has(state.get("scene", "")): return "存档支线占用丢失"
		var all_prior: bool = true
		var terminal_complete: bool = false
		for raw: Variant in _array(q.get("stages")):
			var s: Dictionary = _dict(raw)
			var done: bool = bool(flags.get(s.get("complete_flag", ""),false))
			if done and entries == 0: return "存档支线阶段缺少接受记录"
			if done and not all_prior: return "存档支线阶段顺序无效"
			if done and running and not _matches(flags,_dict(_dict(s.get("requires")).get("flags"))): return "存档支线阶段条件无效"
			if running and not done and all_prior and _matches(flags,_dict(_dict(s.get("requires")).get("flags"))): return "存档遗漏已完成的支线阶段"
			if bool(s.get("terminal",false)) and done: terminal_complete = true
			all_prior = all_prior and done
		if complete != terminal_complete: return "存档整条支线完成状态无效"
	for scene: Variant in _dict(pack.get("scenes")).values():
		for raw: Variant in _array(_dict(scene).get("objects")):
			var o: Dictionary = _dict(raw)
			var count: int = int(counts.get(o.get("inspect_action", ""),0))
			if count > 1 or bool(flags.get(o.get("inspected_flag", ""),false)) != (count == 1): return "存档物件调查记录不一致"
			for aid: Variant in _array(o.get("actions")):
				var action: Dictionary = _dict(_dict(pack.get("actions")).get(aid))
				var once: String = str(action.get("once_key", ""))
				var times: int = int(counts.get(aid, 0))
				if not once.is_empty() and (times > 1 or bool(flags.get(once, false)) != (times == 1)): return "存档物件一次行为记录不一致"
	if active_count > 1: return "存档不能同时占用多条支线"
	return ""

func _matches(flags: Dictionary, required: Dictionary) -> bool:
	for key: Variant in required:
		if bool(flags.get(key,false)) != bool(required[key]): return false
	return true

func _stage(q: Dictionary, stage_id: String) -> Dictionary:
	for raw: Variant in _array(q.get("stages")):
		if _dict(raw).get("id", "") == stage_id: return _dict(raw)
	return {}

func _normalized(value: Variant, count: int, rect: bool) -> bool:
	if not value is Array or value.size() != count: return false
	for n: Variant in value:
		if not (n is float or n is int) or not is_finite(float(n)) or n < 0 or n > 1: return false
	return not rect or (value[2] > 0 and value[3] > 0 and value[0]+value[2] <= 1.000001 and value[1]+value[3] <= 1.000001)

func _id(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$").search(value) != null

func _qualified_id(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$").search(value) != null and value.length() <= 96

func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floor(value) == value)

func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []
