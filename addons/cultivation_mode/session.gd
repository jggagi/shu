extends RefCounted

const PHASE_READY: String = "ready"
const PHASE_EVENT: String = "event"
const PHASE_RESULT: String = "result"
const PHASE_PERFORMING: String = "performing"

const MotionAssetsScript = preload("res://addons/cultivation_mode/motion_assets.gd")
const QuestRuntimeScript = preload("res://addons/cultivation_mode/quest_runtime.gd")

const STATE_FIELDS: Array[String] = [
	"run_id", "sequence", "revision", "day", "slot", "scene", "stats",
	"flags", "counts", "receipts", "phase", "event", "last_result", "journal"
]

var pack: Dictionary = {}
var state: Dictionary = {}
var last_error: String = ""
var _pending_presentation: Dictionary = {}


func configure(data: Dictionary) -> Dictionary:
	var reason: String = _minimal_pack_error(data)
	if not reason.is_empty():
		return _failure(reason, "invalid_pack")
	pack = data.duplicate(true)
	state.clear()
	_pending_presentation.clear()
	return start_new()


func start_new() -> Dictionary:
	if pack.is_empty():
		return _failure("尚未载入内容包", "not_configured")
	var rules: Dictionary = _dict_or_empty(pack.get("rules", {}))
	var clock: Dictionary = _dict_or_empty(rules.get("clock", {}))
	var stats_rules: Array = _array_or_empty(rules.get("stats", []))
	var stats: Dictionary = {}
	for stat_value in stats_rules:
		if not (stat_value is Dictionary):
			return _failure("属性规则无效", "invalid_pack")
		var stat: Dictionary = stat_value
		stats[str(stat.get("id", ""))] = int(stat.get("initial", 0))
	var flags: Dictionary = _dict_or_empty(pack.get("initial_flags", {})).duplicate(true)
	var run_id: String = _new_run_id()
	_pending_presentation.clear()
	state = {
		"run_id": run_id,
		"sequence": 0,
		"revision": 0,
		"day": int(clock.get("start_day", 1)),
		"slot": int(clock.get("start_slot", 0)),
		"scene": str(pack.get("initial_scene", "")),
		"stats": stats,
		"flags": flags,
		"counts": {},
		"receipts": {},
		"phase": PHASE_READY,
		"event": {},
		"last_result": {},
		"journal": []
	}
	last_error = ""
	return {"ok": true}


func snapshot() -> Dictionary:
	return state.duplicate(true)


func available_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	for action_key in actions.keys():
		var action_id: String = str(action_key)
		var action_value: Variant = actions.get(action_key)
		if not (action_value is Dictionary):
			continue
		var action: Dictionary = action_value
		if not bool(action.get("menu", false)):
			continue
		var scenes: Variant = action.get("scenes", [])
		if not (scenes is Array) or not scenes.has(state.get("scene", "")):
			continue
		var availability: Dictionary = _check_action(action_id, action, true, PHASE_READY)
		result.append({
			"id": action_id,
			"label": str(action.get("label", action_id)),
			"description": str(action.get("description", "")),
			"enabled": bool(availability.get("ok", false)),
			"reason": str(availability.get("reason", "")),
			"costs": _dict_or_empty(action.get("costs", {})).duplicate(true),
			"gains": _dict_or_empty(action.get("gains", {})).duplicate(true),
			"duration": int(action.get("duration", 0)),
			"show_count": bool(action.get("show_count", false)),
			"count": int(_dict_or_empty(state.get("counts", {})).get(action_id, 0))
		})
	return result


func quest_view() -> Dictionary:
	return QuestRuntimeScript.new().active(pack, state)


func available_objects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest_runtime = QuestRuntimeScript.new()
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	var object_values: Array[Dictionary] = quest_runtime.object_views(pack, state)
	for object_value in object_values:
		var object: Dictionary = object_value.duplicate(true)
		var object_id: String = str(object.get("id", ""))
		if object_id.is_empty():
			continue
		var inspected: bool = bool(object.get("inspected", false))
		var inspect_action: String = str(object.get("inspect_action", ""))
		var inspect_data: Variant = actions.get(inspect_action, {})
		var inspect_availability: Dictionary = {"ok": false, "reason": "找不到该物件的查看行动", "code": "invalid_action"}
		if inspect_data is Dictionary:
			inspect_availability = _check_action(inspect_action, inspect_data, false, PHASE_READY)
		if inspected and state.get("phase", "") == PHASE_READY:
			inspect_availability = {"ok": true, "reason": "", "code": ""}
		object["enabled"] = bool(inspect_availability.get("ok", false))
		object["reason"] = str(inspect_availability.get("reason", ""))
		var action_views: Array[Dictionary] = []
		var object_actions_value: Variant = object.get("actions", [])
		if object_actions_value is Array:
			for action_value in object_actions_value:
				if not (action_value is String):
					continue
				var action_id: String = str(action_value)
				var action_data_value: Variant = actions.get(action_id, {})
				var availability: Dictionary = {"ok": false, "reason": "找不到该行动", "code": "unknown_action"}
				if action_data_value is Dictionary:
					var context_reason: String = quest_runtime.object_action_error(pack, state, object_id, action_id)
					if not context_reason.is_empty():
						availability = {"ok": false, "reason": context_reason, "code": "not_available"}
					else:
						availability = _check_action(action_id, action_data_value, false, PHASE_READY)
				var action_data: Dictionary = _dict_or_empty(action_data_value)
				action_views.append({
					"id": action_id,
					"label": str(action_data.get("label", action_id)),
					"description": str(action_data.get("description", "")),
					"enabled": bool(availability.get("ok", false)),
					"reason": str(availability.get("reason", "")),
					"costs": _dict_or_empty(action_data.get("costs", {})).duplicate(true),
					"gains": _dict_or_empty(action_data.get("gains", {})).duplicate(true),
					"duration": int(action_data.get("duration", 0)),
					"show_count": bool(action_data.get("show_count", false)),
					"count": int(_dict_or_empty(state.get("counts", {})).get(action_id, 0))
				})
		object["actions"] = action_views
		result.append(object)
	return result


func inspect_object(object_id: String, operation_id: String = "", expected_run_id: String = "", expected_revision: int = -1) -> Dictionary:
	if not expected_run_id.is_empty() and str(state.get("run_id", "")) != expected_run_id:
		return _failure("物件界面已过期，请重新查看当前场景", "stale_run")
	var operation: String = operation_id
	if operation.is_empty():
		operation = _next_operation_id()
	var quest_runtime = QuestRuntimeScript.new()
	var registered_object: Dictionary = quest_runtime.registered_object(pack, object_id)
	var receipts: Dictionary = _dict_or_empty(state.get("receipts", {}))
	if receipts.has(operation):
		var prior: Dictionary = _dict_or_empty(receipts.get(operation, {}))
		if not registered_object.is_empty() and str(prior.get("kind", "")) == "object" and str(prior.get("object_id", "")) == object_id and str(prior.get("action_id", "")) == str(registered_object.get("inspect_action", "")):
			var duplicate: Dictionary = _duplicate_result(prior)
			duplicate["description"] = str(registered_object.get("description", ""))
			duplicate["repeat"] = false
			return duplicate
		return _failure("操作编号已用于其他请求", "operation_mismatch")
	if registered_object.is_empty():
		return _failure("找不到当前可用的物件", "unknown_object")
	var inspect_action: String = str(registered_object.get("inspect_action", ""))
	if expected_revision >= 0 and int(state.get("revision", -1)) != expected_revision:
		return _failure("物件界面已更新，请重新查看当前场景", "stale_revision")
	var current_object: Dictionary = quest_runtime.object_for(pack, state, object_id)
	if current_object.is_empty():
		return _failure("该物件当前不可使用", "unknown_object")
	var description: String = str(current_object.get("description", ""))
	var inspected_flag: String = str(current_object.get("inspected_flag", ""))
	if bool(_dict_or_empty(state.get("flags", {})).get(inspected_flag, false)):
		if state.get("phase", "") != PHASE_READY:
			return _failure("当前不能查看物件", "wrong_phase")
		last_error = ""
		return {"ok": true, "object_id": object_id, "description": description, "repeat": true}
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	var action_value: Variant = actions.get(inspect_action)
	if not (action_value is Dictionary):
		return _failure("找不到该物件的查看行动", "invalid_action")
	var availability: Dictionary = _check_action(inspect_action, action_value, false, PHASE_READY)
	if not bool(availability.get("ok", false)):
		return _failure(str(availability.get("reason", "物件暂不可查看")), str(availability.get("code", "not_available")))
	var prepared: Dictionary = _prepare_action(inspect_action, action_value, operation, "object", {"object_id": object_id})
	if not bool(prepared.get("ok", false)):
		return _failure(str(prepared.get("reason", "查看未完成")), str(prepared.get("code", "action_failed")))
	state = _dict_or_empty(prepared.get("state", {})).duplicate(true)
	last_error = ""
	var result: Dictionary = _dict_or_empty(prepared.get("result", {})).duplicate(true)
	result["description"] = description
	result["repeat"] = false
	return result


func execute_object_action(object_id: String, action_id: String, operation_id: String = "", expected_run_id: String = "", expected_revision: int = -1) -> Dictionary:
	if not expected_run_id.is_empty() and str(state.get("run_id", "")) != expected_run_id:
		return _failure("物件界面已过期，请重新查看当前场景", "stale_run")
	var operation: String = operation_id
	if operation.is_empty():
		operation = _next_operation_id()
	var receipts: Dictionary = _dict_or_empty(state.get("receipts", {}))
	if receipts.has(operation):
		var prior: Dictionary = _dict_or_empty(receipts.get(operation, {}))
		if str(prior.get("kind", "")) == "object" and str(prior.get("object_id", "")) == object_id and str(prior.get("action_id", "")) == action_id:
			return _duplicate_result(prior)
		return _failure("操作编号已用于其他请求", "operation_mismatch")
	if expected_revision >= 0 and int(state.get("revision", -1)) != expected_revision:
		return _failure("物件界面已更新，请重新查看当前场景", "stale_revision")
	var quest_runtime = QuestRuntimeScript.new()
	if quest_runtime.object_for(pack, state, object_id).is_empty():
		return _failure("该物件当前不可使用", "unknown_object")
	var context_reason: String = quest_runtime.object_action_error(pack, state, object_id, action_id)
	if not context_reason.is_empty():
		return _failure(context_reason, "not_available")
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	var action_value: Variant = actions.get(action_id)
	if not (action_value is Dictionary):
		return _failure("找不到该行动", "unknown_action")
	var availability: Dictionary = _check_action(action_id, action_value, false, PHASE_READY)
	if not bool(availability.get("ok", false)):
		return _failure(str(availability.get("reason", "行动暂不可用")), str(availability.get("code", "not_available")))
	var prepared: Dictionary = _prepare_action(action_id, action_value, operation, "object", {"object_id": object_id})
	if not bool(prepared.get("ok", false)):
		return _failure(str(prepared.get("reason", "行动未完成")), str(prepared.get("code", "action_failed")))
	state = _dict_or_empty(prepared.get("state", {})).duplicate(true)
	last_error = ""
	return _dict_or_empty(prepared.get("result", {})).duplicate(true)


func select_action(action_id: String, operation_id: String = "") -> Dictionary:
	var op_id: String = operation_id
	if op_id.is_empty():
		op_id = _next_operation_id()
	var receipts: Dictionary = _dict_or_empty(state.get("receipts", {}))
	if receipts.has(op_id):
		var prior: Dictionary = _dict_or_empty(receipts.get(op_id, {}))
		if str(prior.get("kind", "")) == "action" and str(prior.get("action_id", "")) == action_id:
			return _duplicate_result(prior)
		return _failure("操作编号已用于其他请求", "operation_mismatch")
	if state.get("phase", "") != PHASE_READY:
		return _failure("当前不能选择行动", "wrong_phase")
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	var action_value: Variant = actions.get(action_id)
	if not (action_value is Dictionary):
		return _failure("找不到该行动", "unknown_action")
	var action: Dictionary = action_value
	var availability: Dictionary = _check_action(action_id, action, true, PHASE_READY)
	if not bool(availability.get("ok", false)):
		return _failure(str(availability.get("reason", "行动暂不可用")), str(availability.get("code", "not_available")))
	var presentation_assets: Dictionary = {}
	var presentation_motion_id: String = ""
	var presentation_clip_id: String = ""
	if action.has("presentation"):
		var presentation_value: Variant = action.get("presentation")
		if not (presentation_value is Dictionary):
			return _failure("行动演出规则无效", "invalid_action")
		var presentation: Dictionary = presentation_value
		var motion_value: Variant = presentation.get("motion", null)
		var clip_value: Variant = presentation.get("clip", null)
		if not (motion_value is String) or str(motion_value).is_empty() or not (clip_value is String) or str(clip_value).is_empty():
			return _failure("行动演出规则无效", "invalid_action")
		presentation_motion_id = str(motion_value)
		presentation_clip_id = str(clip_value)
		if not str(action.get("event", "")).is_empty() or not str(action.get("target_scene", "")).is_empty():
			return _failure("演出行动不能开启剧情或切换场景", "invalid_action")
		var preflight: Dictionary = MotionAssetsScript.new().prepare(pack, presentation_motion_id, presentation_clip_id)
		if not bool(preflight.get("ok", false)):
			var preflight_reason: String = str(preflight.get("reason", "演出资源不可用"))
			if preflight_reason.is_empty():
				preflight_reason = "演出资源不可用"
			return _failure(preflight_reason, "presentation_unavailable")
		var assets_value: Variant = preflight.get("assets", {})
		if not (assets_value is Dictionary):
			return _failure("演出资源无效", "presentation_unavailable")
		presentation_assets = assets_value
	var prepared: Dictionary = _prepare_action(action_id, action, op_id, "action", {})
	if not bool(prepared.get("ok", false)):
		return _failure(str(prepared.get("reason", "行动未完成")), str(prepared.get("code", "action_failed")))
	var prepared_state: Dictionary = _dict_or_empty(prepared.get("state", {})).duplicate(true)
	if action.has("presentation"):
		prepared_state["phase"] = PHASE_PERFORMING
		prepared_state["event"] = {}
		_pending_presentation = {
			"run_id": str(prepared_state.get("run_id", "")),
			"operation_id": op_id,
			"action_id": action_id,
			"motion_id": presentation_motion_id,
			"clip_id": presentation_clip_id,
			"assets": presentation_assets.duplicate(true),
			"receipt": _dict_or_empty(prepared.get("result", {})).duplicate(true)
		}
	state = prepared_state
	last_error = ""
	return _dict_or_empty(prepared.get("result", {})).duplicate(true)


func pending_presentation() -> Dictionary:
	return _pending_presentation.duplicate(true)


func finish_presentation(run_id: String, operation_id: String) -> Dictionary:
	if state.get("phase", "") != PHASE_PERFORMING or _pending_presentation.is_empty():
		return _failure("当前没有待完成的行动演出", "wrong_phase")
	if str(state.get("run_id", "")) != run_id or str(_pending_presentation.get("run_id", "")) != run_id or str(_pending_presentation.get("operation_id", "")) != operation_id:
		return _failure("行动演出回调已过期", "stale_presentation")
	var next_state: Dictionary = state.duplicate(true)
	next_state["phase"] = PHASE_RESULT
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	var receipt: Dictionary = _dict_or_empty(_pending_presentation.get("receipt", {})).duplicate(true)
	state = next_state
	_pending_presentation.clear()
	last_error = ""
	return {"ok": true, "phase": PHASE_RESULT, "result": receipt}


func event_view() -> Dictionary:
	if state.get("phase", "") != PHASE_EVENT:
		return {}
	var pointer: Dictionary = _dict_or_empty(state.get("event", {}))
	var event_id: String = str(pointer.get("id", ""))
	var node_id: String = str(pointer.get("node", ""))
	var events: Dictionary = _dict_or_empty(pack.get("events", {}))
	var event_value: Variant = events.get(event_id)
	if not (event_value is Dictionary):
		return {}
	var event_data: Dictionary = event_value
	var nodes: Dictionary = _dict_or_empty(event_data.get("nodes", {}))
	var node_value: Variant = nodes.get(node_id)
	if not (node_value is Dictionary):
		return {}
	var view: Dictionary = (node_value as Dictionary).duplicate(true)
	var speaker_id: String = str(view.get("speaker", ""))
	var characters: Dictionary = _dict_or_empty(pack.get("characters", {}))
	var character_value: Variant = characters.get(speaker_id, {})
	var character: Dictionary = _dict_or_empty(character_value)
	view["event_id"] = event_id
	view["node_id"] = node_id
	view["title"] = str(event_data.get("title", ""))
	view["speaker_name"] = str(character.get("name", ""))
	view["portrait"] = str(character.get("portrait", ""))
	if str(view.get("type", "")) == "choice":
		var options_value: Variant = view.get("options", [])
		var display_options: Array = []
		if options_value is Array:
			for option_value in options_value:
				if not (option_value is Dictionary):
					continue
				var option: Dictionary = (option_value as Dictionary).duplicate(true)
				var availability: Dictionary = _check_option(option)
				option["enabled"] = bool(availability.get("ok", false))
				option["reason"] = str(availability.get("reason", ""))
				display_options.append(option)
		view["options"] = display_options
	return view


func continue_event(expected_run_id: String = "", expected_revision: int = -1) -> Dictionary:
	if (not expected_run_id.is_empty() and str(state.get("run_id", "")) != expected_run_id) or (expected_revision >= 0 and int(state.get("revision", -1)) != expected_revision):
		return _failure("这段交谈已经更新，请使用当前继续按钮", "stale_event")
	if state.get("phase", "") != PHASE_EVENT:
		return _failure("当前没有待继续的对话", "wrong_phase")
	var pointer: Dictionary = _dict_or_empty(state.get("event", {}))
	var event_id: String = str(pointer.get("id", ""))
	var node_id: String = str(pointer.get("node", ""))
	var node: Dictionary = _event_node(event_id, node_id)
	if node.is_empty():
		return _failure("当前剧情节点无效", "invalid_event")
	var node_type: String = str(node.get("type", ""))
	if node_type == "choice":
		return _failure("请先选择一个选项", "choice_required")
	if node_type == "say":
		var next_node: String = str(node.get("next", ""))
		if _event_node(event_id, next_node).is_empty():
			return _failure("对话后续节点无效", "invalid_event")
		var say_state: Dictionary = state.duplicate(true)
		say_state["event"] = {"id": event_id, "node": next_node}
		say_state["revision"] = int(say_state.get("revision", 0)) + 1
		state = say_state
		last_error = ""
		return {"ok": true, "phase": PHASE_EVENT, "event": event_view()}
	if node_type == "end":
		var end_flags_value: Variant = node.get("set_flags", {})
		if not _valid_flag_map(end_flags_value):
			return _failure("剧情结束旗标无效", "invalid_event")
		var end_flags: Dictionary = end_flags_value
		var quest_flags: Dictionary = QuestRuntimeScript.new().known_flags(pack)
		for flag_key in end_flags.keys():
			if quest_flags.has(flag_key):
				return _failure("剧情结束不能改写支线或调查旗标", "invalid_event")
		var end_state: Dictionary = state.duplicate(true)
		var current_flags: Dictionary = _dict_or_empty(end_state.get("flags", {})).duplicate(true)
		for flag_key in end_flags.keys():
			current_flags[flag_key] = end_flags.get(flag_key)
		end_state["flags"] = current_flags
		var ending: String = str(node.get("text", ""))
		var last_result: Dictionary = _dict_or_empty(end_state.get("last_result", {})).duplicate(true)
		if not ending.is_empty():
			var old_message: String = str(last_result.get("message", ""))
			if old_message.is_empty():
				last_result["message"] = ending
			elif not old_message.ends_with(ending):
				last_result["message"] = old_message + "\n" + ending
			end_state["last_result"] = last_result
			_update_receipt_result(end_state, last_result)
			end_state["journal"] = _journal_with_result(end_state.get("journal", []), last_result)
		end_state["phase"] = PHASE_RESULT
		end_state["event"] = {}
		end_state["revision"] = int(end_state.get("revision", 0)) + 1
		state = end_state
		last_error = ""
		return {"ok": true, "phase": PHASE_RESULT, "result": last_result.duplicate(true)}
	return _failure("当前剧情节点类型无效", "invalid_event")


func choose(option_id: String, operation_id: String = "") -> Dictionary:
	var op_id: String = operation_id
	if op_id.is_empty():
		op_id = _next_operation_id()
	var pointer: Dictionary = _dict_or_empty(state.get("event", {}))
	var current_event_id: String = str(pointer.get("id", ""))
	var current_node_id: String = str(pointer.get("node", ""))
	var receipts: Dictionary = _dict_or_empty(state.get("receipts", {}))
	if receipts.has(op_id):
		var prior: Dictionary = _dict_or_empty(receipts.get(op_id, {}))
		var same_choice: bool = str(prior.get("kind", "")) == "choice" and str(prior.get("option_id", "")) == option_id
		if same_choice:
			return _duplicate_result(prior)
		return _failure("操作编号已用于其他请求", "operation_mismatch")
	if state.get("phase", "") != PHASE_EVENT:
		return _failure("当前没有可选择的对话", "wrong_phase")
	var node: Dictionary = _event_node(current_event_id, current_node_id)
	if node.is_empty() or str(node.get("type", "")) != "choice":
		return _failure("当前节点不接受选项", "choice_required")
	var option: Dictionary = _find_option(node, option_id)
	if option.is_empty():
		return _failure("找不到该选项", "unknown_choice")
	var next_node_id: String = str(option.get("next", ""))
	if _event_node(current_event_id, next_node_id).is_empty():
		return _failure("选项后续节点无效", "invalid_event")
	var availability: Dictionary = _check_option(option)
	if not bool(availability.get("ok", false)):
		return _failure(str(availability.get("reason", "选项暂不可用")), str(availability.get("code", "not_available")))
	var action_id: String = str(option.get("action", ""))
	if not action_id.is_empty():
		var action_value: Variant = _dict_or_empty(pack.get("actions", {})).get(action_id)
		if not (action_value is Dictionary):
			return _failure("选项行动不存在", "unknown_action")
		var source: Dictionary = {
			"event_id": current_event_id,
			"node_id": current_node_id,
			"option_id": option_id,
			"next_node": str(option.get("next", ""))
		}
		var prepared: Dictionary = _prepare_action(action_id, action_value, op_id, "choice", source)
		if not bool(prepared.get("ok", false)):
			return _failure(str(prepared.get("reason", "选项未完成")), str(prepared.get("code", "action_failed")))
		state = _dict_or_empty(prepared.get("state", {})).duplicate(true)
		last_error = ""
		return _dict_or_empty(prepared.get("result", {})).duplicate(true)
	var before: Dictionary = _position_snapshot(state)
	var next_state: Dictionary = state.duplicate(true)
	var sequence: int = int(next_state.get("sequence", 0)) + 1
	var after: Dictionary = _position_snapshot(next_state)
	var result: Dictionary = {
		"ok": true,
		"operation_id": op_id,
		"event_id": current_event_id,
		"node_id": current_node_id,
		"option_id": option_id,
		"action_id": "",
		"action_label": "",
		"delta": {"stats": {}, "slots": 0},
		"before": before,
		"after": after,
		"message": str(option.get("label", ""))
	}
	var wrapper: Dictionary = {
		"operation_id": op_id,
		"kind": "choice",
		"action_id": "",
		"event_id": current_event_id,
		"node_id": current_node_id,
		"option_id": option_id,
		"sequence": sequence,
		"result": result.duplicate(true)
	}
	next_state["sequence"] = sequence
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	next_state["event"] = {"id": current_event_id, "node": next_node_id}
	next_state["receipts"][op_id] = wrapper
	next_state["last_result"] = result.duplicate(true)
	var journal: Array = _array_or_empty(next_state.get("journal", [])).duplicate(true)
	journal.append(result.duplicate(true))
	next_state["journal"] = journal
	state = next_state
	last_error = ""
	return result.duplicate(true)


func cancel_event() -> Dictionary:
	if not QuestRuntimeScript.new().active(pack, state).is_empty():
		return _failure("支线进行中，不能通过取消对话离开", "quest_active")
	if state.get("phase", "") != PHASE_EVENT:
		return _failure("当前没有可取消的对话", "wrong_phase")
	var next_state: Dictionary = state.duplicate(true)
	next_state["phase"] = PHASE_READY
	next_state["event"] = {}
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	state = next_state
	last_error = ""
	return {"ok": true, "phase": PHASE_READY}


func acknowledge_result() -> Dictionary:
	if state.get("phase", "") != PHASE_RESULT:
		return _failure("当前没有待确认的结果", "wrong_phase")
	var next_state: Dictionary = state.duplicate(true)
	next_state["phase"] = PHASE_READY
	next_state["event"] = {}
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	state = next_state
	last_error = ""
	return {"ok": true, "phase": PHASE_READY}


func can_save() -> bool:
	var phase: String = str(state.get("phase", ""))
	return phase != PHASE_PERFORMING and (phase == PHASE_READY or phase == PHASE_RESULT) and _dict_or_empty(state.get("event", {})).is_empty()


func restore(candidate: Dictionary) -> Dictionary:
	if state.get("phase", "") == PHASE_PERFORMING:
		return _failure("行动演出期间不能恢复存档", "busy")
	var normalized_value: Variant = _canonicalize_restore_value(candidate)
	if not (normalized_value is Dictionary):
		return _failure("存档格式无效", "invalid_snapshot")
	var normalized_candidate: Dictionary = normalized_value
	var reason: String = _snapshot_error(normalized_candidate)
	if not reason.is_empty():
		return _failure(reason, "invalid_snapshot")
	var safe_state: Dictionary = normalized_candidate.duplicate(true)
	state = safe_state
	_pending_presentation.clear()
	last_error = ""
	return {"ok": true}


func _prepare_action(action_id: String, action: Dictionary, operation_id: String, kind: String, source: Dictionary) -> Dictionary:
	var required_phase: String = PHASE_EVENT if kind == "choice" else PHASE_READY
	var expected_menu: bool = kind == "action"
	var availability: Dictionary = _check_action(action_id, action, expected_menu, required_phase)
	if not bool(availability.get("ok", false)):
		return availability
	var next_state: Dictionary = state.duplicate(true)
	var before: Dictionary = _position_snapshot(state)
	var initial_stats: Dictionary = _dict_or_empty(state.get("stats", {})).duplicate(true)
	var old_stats: Dictionary = _dict_or_empty(state.get("stats", {}))
	var changed_stats: Dictionary = {}
	var stat_ranges: Dictionary = _stat_ranges()
	var costs_value: Variant = action.get("costs", {})
	if not _valid_cost_map(costs_value, stat_ranges):
		return {"ok": false, "reason": "行动消耗规则无效", "code": "invalid_action"}
	var costs: Dictionary = costs_value
	for stat_key in costs.keys():
		var cost_stat_id: String = str(stat_key)
		var amount: int = int(costs.get(stat_key, 0))
		var current: int = int(initial_stats.get(cost_stat_id, 0))
		initial_stats[cost_stat_id] = current - amount
		changed_stats[cost_stat_id] = true
	var gains: Dictionary = _dict_or_empty(action.get("gains", {}))
	for stat_key in gains.keys():
		var gain_stat_id: String = str(stat_key)
		_apply_gain(initial_stats, stat_ranges, gain_stat_id, int(gains.get(stat_key, 0)))
		changed_stats[gain_stat_id] = true
	var flags: Dictionary = _dict_or_empty(next_state.get("flags", {})).duplicate(true)
	var set_flags: Dictionary = _dict_or_empty(action.get("set_flags", {}))
	for flag_key in set_flags.keys():
		flags[str(flag_key)] = bool(set_flags.get(flag_key, false))
	var bonuses_value: Variant = action.get("bonuses", [])
	if bonuses_value is Array:
		for bonus_value in bonuses_value:
			if not (bonus_value is Dictionary):
				continue
			var bonus: Dictionary = bonus_value
			var bonus_flag: String = str(bonus.get("flag", ""))
			if bonus_flag.is_empty() or not bool(flags.get(bonus_flag, false)):
				continue
			var bonus_gains: Dictionary = _dict_or_empty(bonus.get("gains", {}))
			for stat_key in bonus_gains.keys():
				var bonus_stat_id: String = str(stat_key)
				_apply_gain(initial_stats, stat_ranges, bonus_stat_id, int(bonus_gains.get(stat_key, 0)))
				changed_stats[bonus_stat_id] = true
			if bool(bonus.get("consume", false)):
				flags[bonus_flag] = false
	var once_key: String = str(action.get("once_key", ""))
	if not once_key.is_empty():
		flags[once_key] = true
	var duration: int = int(action.get("duration", 0))
	var time: Dictionary = _advance_time(int(next_state.get("day", 1)), int(next_state.get("slot", 0)), duration)
	next_state["day"] = int(time.get("day", next_state.get("day", 1)))
	next_state["slot"] = int(time.get("slot", next_state.get("slot", 0)))
	var target_scene: String = str(action.get("target_scene", ""))
	if not target_scene.is_empty():
		next_state["scene"] = target_scene
	next_state["stats"] = initial_stats
	next_state["flags"] = flags
	var was_quest_active: bool = not QuestRuntimeScript.new().active(pack, state).is_empty()
	QuestRuntimeScript.new().apply(pack, next_state, action)
	var counts: Dictionary = _dict_or_empty(next_state.get("counts", {})).duplicate(true)
	counts[action_id] = int(counts.get(action_id, 0)) + 1
	next_state["counts"] = counts
	var sequence: int = int(next_state.get("sequence", 0)) + 1
	var after: Dictionary = _position_snapshot(next_state)
	var actual_deltas: Dictionary = {}
	for stat_key in changed_stats.keys():
		var delta_stat_id: String = str(stat_key)
		actual_deltas[delta_stat_id] = int(initial_stats.get(delta_stat_id, 0)) - int(old_stats.get(delta_stat_id, 0))
	var action_label: String = str(action.get("label", action_id))
	var message: String = str(action.get("result", ""))
	if message.is_empty():
		message = action_label
	var result: Dictionary
	var wrapper: Dictionary
	if kind == "choice":
		var choice_event_id: String = str(source.get("event_id", ""))
		var choice_node_id: String = str(source.get("node_id", ""))
		var choice_option_id: String = str(source.get("option_id", ""))
		result = {
			"ok": true,
			"operation_id": operation_id,
			"event_id": choice_event_id,
			"node_id": choice_node_id,
			"option_id": choice_option_id,
			"action_id": action_id,
			"action_label": action_label,
			"delta": {"stats": actual_deltas, "slots": duration},
			"before": before,
			"after": after,
			"message": message
		}
		wrapper = {
			"operation_id": operation_id,
			"kind": "choice",
			"action_id": action_id,
			"event_id": choice_event_id,
			"node_id": choice_node_id,
			"option_id": choice_option_id,
			"sequence": sequence,
			"result": result.duplicate(true)
		}
		var next_node_id: String = str(source.get("next_node", ""))
		next_state["phase"] = PHASE_EVENT
		next_state["event"] = {"id": choice_event_id, "node": next_node_id}
	else:
		result = {
			"ok": true,
			"operation_id": operation_id,
			"action_id": action_id,
			"action_label": action_label,
			"delta": {"stats": actual_deltas, "slots": duration},
			"before": before,
			"after": after,
			"message": message
		}
		wrapper = {
			"operation_id": operation_id,
			"kind": kind,
			"action_id": action_id,
			"event_id": "",
			"node_id": "",
			"option_id": "",
			"sequence": sequence,
			"result": result.duplicate(true)
		}
		if kind == "object":
			var object_id: String = str(source.get("object_id", ""))
			result["object_id"] = object_id
			wrapper["object_id"] = object_id
			wrapper["result"] = result.duplicate(true)
		var action_event_id: String = str(action.get("event", ""))
		if action_event_id.is_empty():
			next_state["phase"] = PHASE_RESULT
			next_state["event"] = {}
		else:
			var event_data: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("events", {})).get(action_event_id, {}))
			next_state["phase"] = PHASE_EVENT
			next_state["event"] = {"id": action_event_id, "node": str(event_data.get("start", ""))}
	var entered_quest: bool = action.has("enter_quest") and not str(action.get("enter_quest", "")).is_empty()
	var quest_non_event_action: bool = was_quest_active and kind != "choice" and str(action.get("event", "")).is_empty() and not action.has("presentation")
	if entered_quest or quest_non_event_action:
		next_state["phase"] = PHASE_READY
		next_state["event"] = {}
	next_state["sequence"] = sequence
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	var receipts: Dictionary = _dict_or_empty(next_state.get("receipts", {})).duplicate(true)
	receipts[operation_id] = wrapper
	next_state["receipts"] = receipts
	next_state["last_result"] = result.duplicate(true)
	var journal: Array = _array_or_empty(next_state.get("journal", [])).duplicate(true)
	journal.append(result.duplicate(true))
	next_state["journal"] = journal
	return {"ok": true, "state": next_state, "result": result}


func _check_action(action_id: String, action: Dictionary, expected_menu: bool, required_phase: String) -> Dictionary:
	if state.get("phase", "") != required_phase:
		return {"ok": false, "reason": "当前阶段不能执行行动", "code": "wrong_phase"}
	if bool(action.get("menu", false)) != expected_menu:
		return {"ok": false, "reason": "行动入口不匹配", "code": "not_available"}
	if expected_menu and required_phase != PHASE_READY:
		return {"ok": false, "reason": "当前不能选择行动", "code": "wrong_phase"}
	var menu_value: Variant = action.get("menu", null)
	if not (menu_value is bool):
		return {"ok": false, "reason": "行动入口规则无效", "code": "invalid_action"}
	var event_value: Variant = action.get("event", "")
	if not (event_value is String):
		return {"ok": false, "reason": "行动剧情规则无效", "code": "invalid_action"}
	if not expected_menu and not str(event_value).is_empty():
		return {"ok": false, "reason": "对话选项行动不能再开启剧情", "code": "not_available"}
	var scenes_value: Variant = action.get("scenes", [])
	if not (scenes_value is Array) or not scenes_value.has(state.get("scene", "")):
		return {"ok": false, "reason": "该行动不适用于当前场景", "code": "not_available"}
	var condition_reason: String = _condition_failure(action.get("conditions", {}))
	if not condition_reason.is_empty():
		return {"ok": false, "reason": condition_reason, "code": "conditions_failed"}
	var once_key_value: Variant = action.get("once_key", "")
	if not (once_key_value is String):
		return {"ok": false, "reason": "行动次数规则无效", "code": "invalid_action"}
	var once_key: String = str(once_key_value)
	if not once_key.is_empty() and bool(_dict_or_empty(state.get("flags", {})).get(once_key, false)):
		return {"ok": false, "reason": "此行动已经完成", "code": "already_used"}
	var stat_ranges: Dictionary = _stat_ranges()
	var stats: Dictionary = _dict_or_empty(state.get("stats", {}))
	var costs_value: Variant = action.get("costs", {})
	if not _valid_cost_map(costs_value, stat_ranges):
		return {"ok": false, "reason": "行动消耗规则无效", "code": "invalid_action"}
	var costs: Dictionary = costs_value
	for stat_key in costs.keys():
		var stat_id: String = str(stat_key)
		var amount_value: Variant = costs.get(stat_key)
		var range: Dictionary = _dict_or_empty(stat_ranges.get(stat_id, {}))
		if range.is_empty() or not _is_integer(amount_value) or int(amount_value) < 0:
			return {"ok": false, "reason": "行动资源规则无效", "code": "invalid_action"}
		var current_value: Variant = stats.get(stat_id)
		if not _is_integer(current_value):
			return {"ok": false, "reason": "当前资源状态无效", "code": "invalid_state"}
		var cost: int = int(amount_value)
		var minimum: int = int(range.get("min", 0))
		if int(current_value) - cost < minimum:
			return {"ok": false, "reason": "资源不足：" + _stat_label(stat_id), "code": "insufficient_resource"}
	var duration: Variant = action.get("duration", 0)
	if not _is_integer(duration) or int(duration) < 0:
		return {"ok": false, "reason": "行动时长规则无效", "code": "invalid_action"}
	if not _valid_gain_map(action.get("gains", {}), stat_ranges):
		return {"ok": false, "reason": "行动收益规则无效", "code": "invalid_action"}
	if not _valid_bonus_list(action.get("bonuses", []), stat_ranges):
		return {"ok": false, "reason": "行动加成规则无效", "code": "invalid_action"}
	if not _valid_flag_map(action.get("set_flags", {})):
		return {"ok": false, "reason": "行动旗标规则无效", "code": "invalid_action"}
	var event_id: String = str(event_value)
	if expected_menu and not event_id.is_empty():
		var event_data: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("events", {})).get(event_id, {}))
		if event_data.is_empty() or _event_node(event_id, str(event_data.get("start", ""))).is_empty():
			return {"ok": false, "reason": "行动剧情入口无效", "code": "invalid_action"}
	var target_scene_value: Variant = action.get("target_scene", "")
	if not (target_scene_value is String):
		return {"ok": false, "reason": "行动目标场景规则无效", "code": "invalid_action"}
	var target_scene: String = str(target_scene_value)
	if not target_scene.is_empty() and not _dict_or_empty(pack.get("scenes", {})).has(target_scene):
		return {"ok": false, "reason": "行动目标场景无效", "code": "invalid_action"}
	var quest_reason: String = QuestRuntimeScript.new().check_action(pack, state, action_id)
	if not quest_reason.is_empty():
		return {"ok": false, "reason": quest_reason, "code": "not_available"}
	return {"ok": true, "reason": "", "code": ""}


func _check_option(option: Dictionary) -> Dictionary:
	if state.get("phase", "") != PHASE_EVENT:
		return {"ok": false, "reason": "当前没有可选择的对话", "code": "wrong_phase"}
	var condition_reason: String = _condition_failure(option.get("conditions", {}))
	if not condition_reason.is_empty():
		return {"ok": false, "reason": condition_reason, "code": "conditions_failed"}
	var action_id: String = str(option.get("action", ""))
	if action_id.is_empty():
		return {"ok": true, "reason": "", "code": ""}
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	var action_value: Variant = actions.get(action_id)
	if not (action_value is Dictionary):
		return {"ok": false, "reason": "选项行动不存在", "code": "unknown_action"}
	return _check_action(action_id, action_value, false, PHASE_EVENT)


func _condition_failure(condition_value: Variant) -> String:
	if not (condition_value is Dictionary):
		return "行动条件无效"
	var conditions: Dictionary = condition_value
	for condition_key in conditions.keys():
		var key: String = str(condition_key)
		if key != "stats_gte" and key != "flags":
			return "行动条件无效"
	var stats_gte_value: Variant = conditions.get("stats_gte", {})
	if not (stats_gte_value is Dictionary):
		return "行动条件无效"
	var stats_gte: Dictionary = stats_gte_value
	var stats: Dictionary = _dict_or_empty(state.get("stats", {}))
	for stat_key in stats_gte.keys():
		var threshold_value: Variant = stats_gte.get(stat_key)
		var stat_value: Variant = stats.get(str(stat_key))
		if not _is_integer(threshold_value) or not _is_integer(stat_value):
			return "行动条件尚未满足"
		if int(stat_value) < int(threshold_value):
			return "行动条件尚未满足"
	var flags_value: Variant = conditions.get("flags", {})
	if not (flags_value is Dictionary):
		return "行动条件无效"
	var flags: Dictionary = _dict_or_empty(state.get("flags", {}))
	var required_flags: Dictionary = flags_value
	for flag_key in required_flags.keys():
		var expected_value: Variant = required_flags.get(flag_key)
		if not (expected_value is bool):
			return "行动条件无效"
		if bool(flags.get(str(flag_key), false)) != bool(expected_value):
			return "行动条件尚未满足"
	return ""


func _find_option(node: Dictionary, option_id: String) -> Dictionary:
	var options_value: Variant = node.get("options", [])
	if not (options_value is Array):
		return {}
	for option_value in options_value:
		if not (option_value is Dictionary):
			continue
		var option: Dictionary = option_value
		if str(option.get("id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _event_node(event_id: String, node_id: String) -> Dictionary:
	var events: Dictionary = _dict_or_empty(pack.get("events", {}))
	var event_data: Dictionary = _dict_or_empty(events.get(event_id, {}))
	var nodes: Dictionary = _dict_or_empty(event_data.get("nodes", {}))
	return _dict_or_empty(nodes.get(node_id, {})).duplicate(true)


func _position_snapshot(source: Dictionary) -> Dictionary:
	return {
		"day": int(source.get("day", 0)),
		"slot": int(source.get("slot", 0)),
		"scene": str(source.get("scene", ""))
	}


func _advance_time(day: int, slot: int, duration: int) -> Dictionary:
	var rules: Dictionary = _dict_or_empty(pack.get("rules", {}))
	var clock: Dictionary = _dict_or_empty(rules.get("clock", {}))
	var slots: Array = _array_or_empty(clock.get("slots", []))
	if slots.is_empty():
		return {"day": day, "slot": slot}
	var total: int = slot + duration
	return {"day": day + int(total / slots.size()), "slot": total % slots.size()}


func _apply_gain(stats: Dictionary, ranges: Dictionary, stat_id: String, amount: int) -> void:
	var range: Dictionary = _dict_or_empty(ranges.get(stat_id, {}))
	if range.is_empty():
		return
	var current: int = int(stats.get(stat_id, 0))
	var maximum: int = int(range.get("max", current))
	stats[stat_id] = mini(current + amount, maximum)


func _stat_ranges() -> Dictionary:
	var result: Dictionary = {}
	var rules: Dictionary = _dict_or_empty(pack.get("rules", {}))
	var stats_value: Variant = rules.get("stats", [])
	if not (stats_value is Array):
		return result
	for stat_value in stats_value:
		if not (stat_value is Dictionary):
			continue
		var stat: Dictionary = stat_value
		var stat_id: String = str(stat.get("id", ""))
		if stat_id.is_empty():
			continue
		result[stat_id] = {"min": int(stat.get("min", 0)), "max": int(stat.get("max", 0))}
	return result


func _valid_gain_map(value: Variant, ranges: Dictionary) -> bool:
	if not (value is Dictionary):
		return false
	var gains: Dictionary = value
	for stat_key in gains.keys():
		var stat_id: String = str(stat_key)
		var amount: Variant = gains.get(stat_key)
		if not ranges.has(stat_id) or not _is_integer(amount) or int(amount) < 0:
			return false
	return true


func _valid_cost_map(value: Variant, ranges: Dictionary) -> bool:
	if not (value is Dictionary):
		return false
	var costs: Dictionary = value
	for stat_key in costs.keys():
		var stat_id: String = str(stat_key)
		var amount: Variant = costs.get(stat_key)
		if not ranges.has(stat_id) or not _is_integer(amount) or int(amount) < 0:
			return false
	return true


func _valid_bonus_list(value: Variant, ranges: Dictionary) -> bool:
	if not (value is Array):
		return false
	for bonus_value in value:
		if not (bonus_value is Dictionary):
			return false
		var bonus: Dictionary = bonus_value
		if not (bonus.get("flag", null) is String) or str(bonus.get("flag", "")).is_empty():
			return false
		if not (bonus.get("consume", null) is bool) or not _valid_gain_map(bonus.get("gains", {}), ranges):
			return false
	return true


func _valid_flag_map(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var flags: Dictionary = value
	for key in flags.keys():
		var flag_value: Variant = flags.get(key)
		if not (key is String) or not (flag_value is bool):
			return false
	return true


func _stat_label(stat_id: String) -> String:
	var rules: Dictionary = _dict_or_empty(pack.get("rules", {}))
	var stats_value: Variant = rules.get("stats", [])
	if stats_value is Array:
		for stat_value in stats_value:
			if stat_value is Dictionary and str(stat_value.get("id", "")) == stat_id:
				return str(stat_value.get("label", stat_id))
	return stat_id


func _next_operation_id() -> String:
	return str(state.get("run_id", "run")) + ":" + str(int(state.get("sequence", 0)) + 1)


func _new_run_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if not bytes.is_empty():
		return bytes.hex_encode()
	return str(Time.get_ticks_usec()) + "-" + str(randi())


func _duplicate_result(receipt: Dictionary) -> Dictionary:
	var result: Dictionary = _dict_or_empty(receipt.get("result", {})).duplicate(true)
	result["duplicate"] = true
	last_error = ""
	return result


func _failure(reason: String, code: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason, "code": code}


func _dict_or_empty(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array_or_empty(value: Variant) -> Array:
	return value if value is Array else []


func _is_integer(value: Variant) -> bool:
	if value is bool:
		return false
	if value is int:
		return true
	if value is float:
		var number: float = float(value)
		return is_finite(number) and floor(number) == number
	return false


func _canonicalize_restore_value(value: Variant, depth: int = 0) -> Variant:
	if depth > 64:
		return value
	if value == null or value is bool or value is String or value is int:
		return value
	if value is float:
		var number: float = float(value)
		if is_finite(number) and floor(number) == number:
			return int(number)
		return value
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_canonicalize_restore_value(item, depth + 1))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key in value.keys():
			normalized_dictionary[key] = _canonicalize_restore_value(value.get(key), depth + 1)
		return normalized_dictionary
	return value


func _is_json_compatible(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(float(value))
	if value is Array:
		for item in value:
			if not _is_json_compatible(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key in dictionary.keys():
			if not (key is String) or not _is_json_compatible(dictionary.get(key), depth + 1):
				return false
		return true
	return false


func _minimal_pack_error(data: Dictionary) -> String:
	if not _is_json_compatible(data):
		return "内容包包含不支持的数据"
	for required_key in ["id", "version", "initial_scene", "initial_flags", "rules", "characters", "scenes", "actions", "events"]:
		if not data.has(required_key):
			return "内容包缺少必要字段"
	if not (data.get("id", "") is String) or str(data.get("id", "")).is_empty():
		return "内容包标识无效"
	if not (data.get("version", "") is String) or str(data.get("version", "")).is_empty():
		return "内容包版本无效"
	if not (data.get("initial_scene", "") is String) or str(data.get("initial_scene", "")).is_empty():
		return "起始场景无效"
	var scenes: Dictionary = _dict_or_empty(data.get("scenes", {}))
	if scenes.is_empty() or not scenes.has(data.get("initial_scene", "")):
		return "起始场景未注册"
	if not (data.get("characters", {}) is Dictionary):
		return "人物表无效"
	if not (data.get("actions", {}) is Dictionary) or not (data.get("events", {}) is Dictionary):
		return "行动或剧情表无效"
	var initial_flags_value: Variant = data.get("initial_flags", {})
	if not (initial_flags_value is Dictionary):
		return "初始旗标无效"
	var initial_flags: Dictionary = initial_flags_value
	for key in initial_flags.keys():
		if not (key is String) or not (initial_flags.get(key) is bool):
			return "初始旗标无效"
	var rules_value: Variant = data.get("rules", {})
	if not (rules_value is Dictionary):
		return "养成规则无效"
	var rules: Dictionary = rules_value
	var clock_value: Variant = rules.get("clock", {})
	if not (clock_value is Dictionary):
		return "时间规则无效"
	var clock: Dictionary = clock_value
	var slots_value: Variant = clock.get("slots", [])
	if not (slots_value is Array) or (slots_value as Array).is_empty():
		return "时间段列表无效"
	for slot_name in slots_value:
		if not (slot_name is String) or str(slot_name).is_empty():
			return "时间段列表无效"
	var start_day: Variant = clock.get("start_day", null)
	var start_slot: Variant = clock.get("start_slot", null)
	if not _is_integer(start_day) or int(start_day) < 1:
		return "起始日期无效"
	if not _is_integer(start_slot) or int(start_slot) < 0 or int(start_slot) >= (slots_value as Array).size():
		return "起始时辰无效"
	var stats_value: Variant = rules.get("stats", [])
	if not (stats_value is Array) or (stats_value as Array).is_empty():
		return "属性规则无效"
	var seen_stats: Dictionary = {}
	for stat_value in stats_value:
		if not (stat_value is Dictionary):
			return "属性规则无效"
		var stat: Dictionary = stat_value
		var stat_id: String = str(stat.get("id", ""))
		var minimum: Variant = stat.get("min", null)
		var initial: Variant = stat.get("initial", null)
		var maximum: Variant = stat.get("max", null)
		if stat_id.is_empty() or seen_stats.has(stat_id):
			return "属性标识无效"
		if not _is_integer(minimum) or not _is_integer(initial) or not _is_integer(maximum):
			return "属性数值无效"
		if int(minimum) > int(initial) or int(initial) > int(maximum):
			return "属性初始范围无效"
		seen_stats[stat_id] = true
	var quest_errors: Array[String] = QuestRuntimeScript.new().validate(data)
	if not quest_errors.is_empty():
		return str(quest_errors[0])
	return ""


func _snapshot_error(candidate: Dictionary) -> String:
	if pack.is_empty():
		return "尚未载入内容包"
	if not _is_json_compatible(candidate):
		return "存档包含不支持的数据"
	if candidate.size() != STATE_FIELDS.size():
		return "存档字段不匹配"
	for key in STATE_FIELDS:
		if not candidate.has(key):
			return "存档字段不匹配"
	var run_id: Variant = candidate.get("run_id")
	if not (run_id is String) or str(run_id).is_empty():
		return "存档运行标识无效"
	var sequence_value: Variant = candidate.get("sequence")
	var revision_value: Variant = candidate.get("revision")
	var day_value: Variant = candidate.get("day")
	var slot_value: Variant = candidate.get("slot")
	if not _is_integer(sequence_value) or int(sequence_value) < 0:
		return "存档操作序号无效"
	if not _is_integer(revision_value) or int(revision_value) < int(sequence_value):
		return "存档修订号无效"
	if not _is_integer(day_value) or int(day_value) < int(_dict_or_empty(_dict_or_empty(pack.get("rules", {})).get("clock", {})).get("start_day", 1)):
		return "存档日期无效"
	var clock: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("rules", {})).get("clock", {}))
	var slots: Array = _array_or_empty(clock.get("slots", []))
	if not _is_integer(slot_value) or int(slot_value) < 0 or int(slot_value) >= slots.size():
		return "存档时辰无效"
	var scene_value: Variant = candidate.get("scene")
	var scenes: Dictionary = _dict_or_empty(pack.get("scenes", {}))
	if not (scene_value is String) or not scenes.has(scene_value):
		return "存档场景无效"
	var phase: Variant = candidate.get("phase")
	if not (phase is String) or (str(phase) != PHASE_READY and str(phase) != PHASE_RESULT):
		return "存档阶段无效"
	var event_value: Variant = candidate.get("event")
	if not (event_value is Dictionary) or not (event_value as Dictionary).is_empty():
		return "不能恢复未完成的剧情"
	if not _validate_stats(candidate.get("stats")):
		return "存档属性无效"
	if not _validate_flags(candidate.get("flags")):
		return "存档旗标无效"
	if not _validate_counts(candidate.get("counts")):
		return "存档行动次数无效"
	var receipts_value: Variant = candidate.get("receipts")
	if not (receipts_value is Dictionary):
		return "存档回执无效"
	var receipt_error: String = _validate_receipts(receipts_value, int(sequence_value), _dict_or_empty(candidate.get("counts", {})))
	if not receipt_error.is_empty():
		return receipt_error
	var journal_value: Variant = candidate.get("journal")
	if not (journal_value is Array):
		return "存档记录无效"
	var journal: Array = journal_value
	if journal.size() != int(sequence_value):
		return "存档记录与序号不一致"
	for index in range(journal.size()):
		var entry_value: Variant = journal[index]
		if not (entry_value is Dictionary):
			return "存档记录无效"
		var entry: Dictionary = entry_value
		var op_id: String = str(entry.get("operation_id", ""))
		var wrapper: Dictionary = _dict_or_empty(_dict_or_empty(receipts_value).get(op_id, {}))
		if wrapper.is_empty() or int(wrapper.get("sequence", 0)) != index + 1 or entry != _dict_or_empty(wrapper.get("result", {})):
			return "存档记录与回执不一致"
	var last_result_value: Variant = candidate.get("last_result")
	if not (last_result_value is Dictionary):
		return "存档结果无效"
	var last_result: Dictionary = last_result_value
	if journal.is_empty():
		if not last_result.is_empty():
			return "存档结果与记录不一致"
	else:
		if last_result != _dict_or_empty(journal[journal.size() - 1]):
			return "存档结果与记录不一致"
	return QuestRuntimeScript.new().snapshot_error(pack, candidate)


func _validate_stats(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var stats: Dictionary = value
	var ranges: Dictionary = _stat_ranges()
	if stats.size() != ranges.size():
		return false
	for stat_id in ranges.keys():
		if not stats.has(stat_id) or not _is_integer(stats.get(stat_id)):
			return false
		var amount: int = int(stats.get(stat_id))
		var range: Dictionary = _dict_or_empty(ranges.get(stat_id, {}))
		if amount < int(range.get("min", 0)) or amount > int(range.get("max", 0)):
			return false
	return true


func _validate_flags(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var flags: Dictionary = value
	var known: Dictionary = _known_flag_ids()
	var initial_flags: Dictionary = _dict_or_empty(pack.get("initial_flags", {}))
	for initial_key in initial_flags.keys():
		if not flags.has(initial_key):
			return false
	for flag_key in flags.keys():
		if not (flag_key is String) or not known.has(flag_key) or not (flags.get(flag_key) is bool):
			return false
	return true


func _validate_counts(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var counts: Dictionary = value
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	for action_key in counts.keys():
		if not (action_key is String) or not actions.has(action_key) or not _is_integer(counts.get(action_key)) or int(counts.get(action_key)) < 0:
			return false
	return true


func _validate_receipts(value: Dictionary, sequence: int, candidate_counts: Dictionary) -> String:
	if value.size() != sequence:
		return "存档回执与序号不一致"
	var seen_sequences: Dictionary = {}
	var actual_counts: Dictionary = {}
	for op_key in value.keys():
		if not (op_key is String) or str(op_key).is_empty():
			return "存档操作编号无效"
		var wrapper_value: Variant = value.get(op_key)
		if not (wrapper_value is Dictionary):
			return "存档回执无效"
		var wrapper: Dictionary = wrapper_value
		if str(wrapper.get("operation_id", "")) != str(op_key):
			return "存档回执编号不一致"
		var kind: String = str(wrapper.get("kind", ""))
		if kind != "action" and kind != "choice":
			if kind != "object":
				return "存档回执类型无效"
		var wrapper_fields: Array[String] = ["operation_id", "kind", "action_id", "event_id", "node_id", "option_id", "sequence", "result"]
		if kind == "object":
			wrapper_fields.append("object_id")
		if not _has_only_keys(wrapper, wrapper_fields):
			return "存档回执字段无效"
		var receipt_sequence: Variant = wrapper.get("sequence")
		if not _is_integer(receipt_sequence) or int(receipt_sequence) < 1 or int(receipt_sequence) > sequence or seen_sequences.has(int(receipt_sequence)):
			return "存档回执序号无效"
		seen_sequences[int(receipt_sequence)] = true
		var action_id: String = str(wrapper.get("action_id", ""))
		if not action_id.is_empty():
			if not _dict_or_empty(pack.get("actions", {})).has(action_id):
				return "存档回执引用未知行动"
			actual_counts[action_id] = int(actual_counts.get(action_id, 0)) + 1
		if kind == "action":
			if action_id.is_empty() or not str(wrapper.get("event_id", "")).is_empty() or not str(wrapper.get("node_id", "")).is_empty() or not str(wrapper.get("option_id", "")).is_empty():
				return "存档行动回执无效"
			var action_data: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("actions", {})).get(action_id, {}))
			if not bool(action_data.get("menu", false)):
				return "存档行动回执引用非菜单行动"
		elif kind == "choice" and not _valid_choice_source(wrapper):
			return "存档选项回执无效"
		elif kind == "object":
			var object_id_value: Variant = wrapper.get("object_id", null)
			if not (wrapper.get("action_id", null) is String) or not (object_id_value is String) or str(object_id_value).is_empty() or not str(wrapper.get("event_id", "")).is_empty() or not str(wrapper.get("node_id", "")).is_empty() or not str(wrapper.get("option_id", "")).is_empty() or not _valid_object_receipt(action_id, str(object_id_value)):
				return "存档物件回执无效"
		var result_value: Variant = wrapper.get("result")
		if not (result_value is Dictionary) or not _validate_result(result_value, str(op_key), kind, action_id, wrapper):
			return "存档结果回执无效"
	if seen_sequences.size() != sequence or candidate_counts != actual_counts:
		return "存档回执与计数不一致"
	return ""


func _valid_choice_source(wrapper: Dictionary) -> bool:
	var event_id: String = str(wrapper.get("event_id", ""))
	var node_id: String = str(wrapper.get("node_id", ""))
	var option_id: String = str(wrapper.get("option_id", ""))
	if event_id.is_empty() or node_id.is_empty() or option_id.is_empty():
		return false
	var node: Dictionary = _event_node(event_id, node_id)
	if node.is_empty() or str(node.get("type", "")) != "choice":
		return false
	var option: Dictionary = _find_option(node, option_id)
	if option.is_empty() or str(option.get("action", "")) != str(wrapper.get("action_id", "")):
		return false
	var action_id: String = str(wrapper.get("action_id", ""))
	if action_id.is_empty():
		return true
	var action: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("actions", {})).get(action_id, {}))
	return not bool(action.get("menu", true)) and str(action.get("event", "")).is_empty()


func _valid_object_receipt(action_id: String, object_id: String) -> bool:
	if action_id.is_empty() or object_id.is_empty():
		return false
	var object: Dictionary = QuestRuntimeScript.new().registered_object(pack, object_id)
	if object.is_empty():
		return false
	var registered_actions: Array = _array_or_empty(object.get("actions", []))
	var inspect_action: String = str(object.get("inspect_action", ""))
	if action_id != inspect_action and not registered_actions.has(action_id):
		return false
	var action: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("actions", {})).get(action_id, {}))
	return not action.is_empty() and action.get("menu", null) is bool and not bool(action.get("menu", true))


func _validate_result(value: Dictionary, operation_id: String, kind: String, action_id: String, wrapper: Dictionary) -> bool:
	var expected_fields: Array[String] = ["ok", "operation_id", "event_id", "node_id", "option_id", "action_id", "action_label", "delta", "before", "after", "message"]
	if kind == "action" or kind == "object":
		expected_fields = ["ok", "operation_id", "action_id", "action_label", "delta", "before", "after", "message"]
	if kind == "object":
		expected_fields.append("object_id")
	if not _has_only_keys(value, expected_fields):
		return false
	if value.get("ok", false) != true or str(value.get("operation_id", "")) != operation_id:
		return false
	if str(value.get("action_id", "")) != action_id:
		return false
	if not (value.get("message", null) is String):
		return false
	var before_value: Variant = value.get("before")
	var after_value: Variant = value.get("after")
	if not _valid_position(before_value) or not _valid_position(after_value):
		return false
	var before: Dictionary = before_value
	var after: Dictionary = after_value
	if not _valid_position_for_pack(before) or not _valid_position_for_pack(after):
		return false
	var delta_value: Variant = value.get("delta")
	if not (delta_value is Dictionary):
		return false
	var delta: Dictionary = delta_value
	if not _has_only_keys(delta, ["stats", "slots"]):
		return false
	var stat_delta_value: Variant = delta.get("stats")
	if not (stat_delta_value is Dictionary):
		return false
	var ranges: Dictionary = _stat_ranges()
	for stat_key in (stat_delta_value as Dictionary).keys():
		if not ranges.has(stat_key) or not _is_integer((stat_delta_value as Dictionary).get(stat_key)):
			return false
	if not _is_integer(delta.get("slots")) or int(delta.get("slots")) < 0:
		return false
	if kind == "action" or kind == "object":
		if not (value.get("action_label", null) is String) or not _dict_or_empty(pack.get("actions", {})).has(action_id):
			return false
		if kind == "object":
			var object_id: String = str(wrapper.get("object_id", ""))
			if not (wrapper.get("action_id", null) is String) or not (value.get("action_id", null) is String) or not (wrapper.get("object_id", null) is String) or not (value.get("object_id", null) is String) or str(value.get("object_id", "")) != object_id or not _valid_object_receipt(action_id, object_id):
				return false
			var object: Dictionary = QuestRuntimeScript.new().registered_object(pack, object_id)
			var scene_id: String = str(object.get("scene_id", ""))
			if scene_id.is_empty() or str(before.get("scene", "")) != scene_id or str(after.get("scene", "")) != scene_id:
				return false
	else:
		if str(value.get("event_id", "")) != str(wrapper.get("event_id", "")) or str(value.get("node_id", "")) != str(wrapper.get("node_id", "")) or str(value.get("option_id", "")) != str(wrapper.get("option_id", "")):
			return false
	return true


func _valid_position(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var position: Dictionary = value
	if not _has_only_keys(position, ["day", "slot", "scene"]):
		return false
	return _is_integer(position.get("day")) and int(position.get("day")) >= 1 and _is_integer(position.get("slot")) and position.get("scene") is String


func _valid_position_for_pack(position: Dictionary) -> bool:
	var clock: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("rules", {})).get("clock", {}))
	var slots: Array = _array_or_empty(clock.get("slots", []))
	var scenes: Dictionary = _dict_or_empty(pack.get("scenes", {}))
	var start_day: int = int(clock.get("start_day", 1))
	return int(position.get("day", 0)) >= start_day and int(position.get("slot", -1)) >= 0 and int(position.get("slot", -1)) < slots.size() and scenes.has(position.get("scene", ""))


func _known_flag_ids() -> Dictionary:
	var known: Dictionary = {}
	var initial_flags: Dictionary = _dict_or_empty(pack.get("initial_flags", {}))
	for flag_key in initial_flags.keys():
		known[str(flag_key)] = true
	var rules: Dictionary = _dict_or_empty(pack.get("rules", {}))
	var goals_value: Variant = rules.get("goals", [])
	if goals_value is Array:
		for goal_value in goals_value:
			if goal_value is Dictionary:
				var completion_flag: String = str(goal_value.get("completion_flag", ""))
				if not completion_flag.is_empty():
					known[completion_flag] = true
	var actions: Dictionary = _dict_or_empty(pack.get("actions", {}))
	for action_value in actions.values():
		if not (action_value is Dictionary):
			continue
		var action: Dictionary = action_value
		var once_key: String = str(action.get("once_key", ""))
		if not once_key.is_empty():
			known[once_key] = true
		_add_flag_keys(known, action.get("set_flags", {}))
		_add_condition_flag_keys(known, action.get("conditions", {}))
		var bonuses_value: Variant = action.get("bonuses", [])
		if bonuses_value is Array:
			for bonus_value in bonuses_value:
				if bonus_value is Dictionary:
					var bonus_flag: String = str(bonus_value.get("flag", ""))
					if not bonus_flag.is_empty():
						known[bonus_flag] = true
	var events: Dictionary = _dict_or_empty(pack.get("events", {}))
	for event_value in events.values():
		if not (event_value is Dictionary):
			continue
		var nodes: Dictionary = _dict_or_empty(event_value.get("nodes", {}))
		for node_value in nodes.values():
			if not (node_value is Dictionary):
				continue
			var node: Dictionary = node_value
			if str(node.get("type", "")) == "end":
				_add_flag_keys(known, node.get("set_flags", {}))
			var options_value: Variant = node.get("options", [])
			if options_value is Array:
				for option_value in options_value:
					if option_value is Dictionary:
						_add_condition_flag_keys(known, option_value.get("conditions", {}))
	var quest_flags: Dictionary = QuestRuntimeScript.new().known_flags(pack)
	for flag_key in quest_flags.keys():
		known[str(flag_key)] = true
	return known


func _add_flag_keys(target: Dictionary, value: Variant) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			target[str(key)] = true


func _add_condition_flag_keys(target: Dictionary, value: Variant) -> void:
	if not (value is Dictionary):
		return
	var conditions: Dictionary = value
	var flags_value: Variant = conditions.get("flags", {})
	if flags_value is Dictionary:
		_add_flag_keys(target, flags_value)


func _has_only_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in value.keys():
		if not expected.has(key):
			return false
	return true


func _update_receipt_result(target_state: Dictionary, result: Dictionary) -> void:
	var operation_id: String = str(result.get("operation_id", ""))
	var receipts: Dictionary = _dict_or_empty(target_state.get("receipts", {})).duplicate(true)
	if receipts.has(operation_id):
		var wrapper: Dictionary = _dict_or_empty(receipts.get(operation_id, {})).duplicate(true)
		wrapper["result"] = result.duplicate(true)
		receipts[operation_id] = wrapper
		target_state["receipts"] = receipts


func _journal_with_result(journal_value: Variant, result: Dictionary) -> Array:
	var journal: Array = _array_or_empty(journal_value).duplicate(true)
	var operation_id: String = str(result.get("operation_id", ""))
	for index in range(journal.size()):
		if str(_dict_or_empty(journal[index]).get("operation_id", "")) == operation_id:
			journal[index] = result.duplicate(true)
	return journal
