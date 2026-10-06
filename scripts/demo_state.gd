extends RefCounted

const TEA_OBJECT_IDS := ["tea.cup_first", "tea.cup_second"]
const TEA_TERRACE_ID := "tea.sword_terrace"
const TEA_COURTYARD_ID := "tea.old_courtyard"
const TEA_C_OBJECT_IDS := ["tea.household", "tea.coats", "tea.medicine_pot", "tea.window", "tea.ledger"]
const TEA_STORY_ENDING_STAGE := 7
const TEA_STORY_ENDING_DELAY_MSEC := 1200

var rules: Dictionary
var day := 1
var time_index := 0
var energy := 100
var cultivation := 0
var understanding := 0
var lesson_bonus := 0
var dialogue_open := false

var tea_accepted := false
var tea_seen: Dictionary = {}
var tea_stage_complete := false
var tea_quest_complete := false
var tea_scene_id := TEA_TERRACE_ID
var tea_c_seen: Dictionary = {}
var tea_c_complete := false
var tea_action_done: Dictionary = {}
var tea_active := false
var tea_session: int = 0
var _tea_read_counter: int = 0
var _tea_pending_object_id := ""
var _tea_pending_read_token: int = 0
var tea_story_stage: int = 0
var tea_story_seen: Dictionary = {}
var tea_story_page: int = 0
var tea_story_object := ""
var tea_story_token: int = 0
var tea_ending_step: int = 0
var _tea_ending_first_fill_msec: int = 0
var _tea_story_source: Dictionary = {}

func _init() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/rules.json"))
	var parsed_story: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea-full-source.json"))
	if parsed_story is Dictionary:
		_tea_story_source = parsed_story
	reset()

func reset() -> void:
	day = 1
	time_index = 0
	energy = int(rules.energy_max)
	cultivation = 0
	understanding = 0
	lesson_bonus = 0
	dialogue_open = false
	_invalidate_tea_session()
	tea_accepted = false
	tea_seen.clear()
	tea_stage_complete = false
	tea_quest_complete = false
	tea_scene_id = TEA_TERRACE_ID
	tea_c_seen.clear()
	tea_c_complete = false
	tea_action_done.clear()
	tea_story_stage = 0
	tea_story_seen.clear()
	tea_story_page = 0
	tea_story_object = ""
	tea_ending_step = 0
	_tea_ending_first_fill_msec = 0

func train() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "请先结束与师傅的对话。"}
	if tea_active:
		return {"ok": false, "reason": "请先结束茶事调查。"}
	if energy < int(rules.training_cost):
		return {"ok": false, "reason": "精力不足，先休息一会儿再修炼。"}
	var gain := int(rules.training_gain) + lesson_bonus
	energy -= int(rules.training_cost)
	cultivation += gain
	lesson_bonus = 0
	_advance(int(rules.training_duration))
	return {"ok": true, "gain": gain}

func rest() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "请先结束与师傅的对话。"}
	if tea_active:
		return {"ok": false, "reason": "请先结束茶事调查。"}
	return _settle_rest()

func rest_tea(session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	close_tea_story()
	return _settle_rest()

func _settle_rest() -> Dictionary:
	var previous := energy
	energy = mini(int(rules.energy_max), energy + int(rules.rest_gain))
	_advance(int(rules.rest_duration))
	return {"ok": true, "gain": energy - previous}

func begin_dialogue() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "正在与师傅交谈。"}
	if tea_active:
		return {"ok": false, "reason": "请先结束茶事调查。"}
	if energy < int(rules.mentor_cost):
		return {"ok": false, "reason": "精力不足，歇一歇再向师傅请教。"}
	dialogue_open = true
	return {"ok": true}

func choose(topic: String) -> Dictionary:
	if tea_active:
		return {"ok": false, "reason": "请先结束茶事调查。"}
	if not dialogue_open:
		return {"ok": false, "reason": "对话已经结束。"}
	if topic not in ["breathing", "mountain"]:
		return {"ok": false, "reason": "未知的请教内容。"}
	dialogue_open = false
	energy -= int(rules.mentor_cost)
	understanding += 1
	if topic == "breathing":
		lesson_bonus = int(rules.lesson_bonus)
	_advance(int(rules.mentor_duration))
	return {"ok": true, "topic": topic}

func cancel_dialogue() -> void:
	dialogue_open = false

func begin_tea() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "请先结束与师傅的对话。"}
	if tea_active:
		return {"ok": false, "reason": "茶事调查已经开始。"}
	tea_session += 1
	tea_active = true
	_clear_pending_tea_read()
	return {"ok": true, "session": tea_session}

func accept_tea(session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "委托会话已经结束。"}
	if tea_accepted:
		return {"ok": false, "reason": "已经接受过这项委托。"}
	tea_accepted = true
	return {"ok": true}

func switch_tea_scene(destination: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if destination not in [TEA_TERRACE_ID, TEA_COURTYARD_ID]:
		return {"ok": false, "reason": "未知的茶事场景。"}
	if destination == TEA_COURTYARD_ID and not tea_stage_complete:
		return {"ok": false, "reason": "剑坪线索尚未收齐。"}
	if destination != tea_scene_id:
		tea_scene_id = destination
		tea_session += 1
		_clear_pending_tea_read()
		close_tea_story()
	return {"ok": true, "session": tea_session, "new_scene": tea_scene_id}

func inspect_tea(object_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if object_id not in TEA_OBJECT_IDS:
		return {"ok": false, "reason": "未知的调查物件。"}
	if tea_scene_id != TEA_TERRACE_ID:
		return {"ok": false, "reason": "这件物品不在当前场景。"}
	_tea_read_counter += 1
	_tea_pending_object_id = object_id
	_tea_pending_read_token = _tea_read_counter
	return {"ok": true, "read_token": _tea_pending_read_token}

func view_tea(object_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if object_id not in TEA_OBJECT_IDS:
		return {"ok": false, "reason": "未知的调查物件。"}
	if tea_scene_id != TEA_TERRACE_ID:
		return {"ok": false, "reason": "这件物品不在当前场景。"}
	_clear_pending_tea_read()
	var new_clue := not bool(tea_seen.get(object_id, false))
	tea_seen[object_id] = true
	var both_clues_seen := bool(tea_seen.get("tea.cup_first", false)) and bool(tea_seen.get("tea.cup_second", false))
	var new_completion := both_clues_seen and not tea_stage_complete
	if new_completion:
		tea_stage_complete = true
	return {"ok": true, "new_clue": new_clue, "new_completion": new_completion}

func view_tea_c(object_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if tea_scene_id != TEA_COURTYARD_ID:
		return {"ok": false, "reason": "请先进入问天峰旧院。"}
	if not tea_stage_complete:
		return {"ok": false, "reason": "剑坪线索尚未收齐。"}
	if object_id not in TEA_C_OBJECT_IDS:
		return {"ok": false, "reason": "未知的院中物件。"}
	if object_id == "tea.ledger" and not bool(tea_c_seen.get("tea.household", false)):
		return {"ok": false, "reason": "先看看院中两副碗筷。"}
	var new_clue := not bool(tea_c_seen.get(object_id, false))
	tea_c_seen[object_id] = true
	var household_and_ledger_seen := bool(tea_c_seen.get("tea.household", false)) and bool(tea_c_seen.get("tea.ledger", false))
	var new_completion := household_and_ledger_seen and not tea_c_complete
	if new_completion:
		tea_c_complete = true
	return {"ok": true, "new_clue": new_clue, "new_completion": new_completion}

func story_stage() -> Dictionary:
	var stages: Array = _tea_story_source.get("stages", [])
	if tea_story_stage < 0 or tea_story_stage >= stages.size():
		return {}
	return (stages[tea_story_stage] as Dictionary).duplicate(true)

func story_stage_complete() -> bool:
	if tea_story_stage == 0:
		return tea_c_complete
	if tea_story_stage < 0 or tea_story_stage > TEA_STORY_ENDING_STAGE:
		return false
	if tea_story_stage == TEA_STORY_ENDING_STAGE:
		return bool(tea_story_seen.get("tea.cup_first", false)) and bool(tea_story_seen.get("tea.cup_second", false))
	var stage := story_stage()
	var items: Array = stage.get("items", [])
	if items.is_empty():
		return false
	for object_id in items:
		if not bool(tea_story_seen.get(str(object_id), false)):
			return false
	return true

func advance_tea_story(session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if tea_story_stage >= TEA_STORY_ENDING_STAGE:
		return {"ok": false, "reason": "故事已经到达最后一幕。"}
	if tea_story_stage < 0 or tea_story_stage > TEA_STORY_ENDING_STAGE:
		return {"ok": false, "reason": "当前故事阶段无效。"}
	if tea_scene_id != TEA_COURTYARD_ID:
		return {"ok": false, "reason": "请先进入问天峰旧院。"}
	if not story_stage_complete():
		return {"ok": false, "reason": "当前故事阶段尚未读完。"}
	tea_story_stage += 1
	tea_scene_id = TEA_TERRACE_ID if tea_story_stage == TEA_STORY_ENDING_STAGE else TEA_COURTYARD_ID
	tea_session += 1
	_clear_pending_tea_read()
	close_tea_story()
	return {"ok": true, "session": tea_session, "stage": story_stage(), "scene": tea_scene_id}

func read_tea_story(object_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if tea_story_stage <= 0 or tea_story_stage > TEA_STORY_ENDING_STAGE:
		return {"ok": false, "reason": "当前阶段没有可分页阅读的故事。"}
	if not _is_story_scene_valid():
		return {"ok": false, "reason": "这件物品不在当前场景。"}
	var stage := story_stage()
	var items: Array = stage.get("items", [])
	if object_id not in items:
		return {"ok": false, "reason": "这件物品不属于当前故事阶段。"}
	var objects: Dictionary = _tea_story_source.get("objects", {})
	if not objects.has(object_id):
		return {"ok": false, "reason": "故事物件内容缺失。"}
	var source_object: Dictionary = objects[object_id]
	var pages: Array = source_object.get("pages", [])
	if pages.is_empty():
		return {"ok": false, "reason": "故事物件没有可读内容。"}
	var requirements: Array = source_object.get("requires", [])
	for required_id in requirements:
		if not bool(tea_story_seen.get(str(required_id), false)):
			return {"ok": false, "reason": "仍有前置线索尚未读完。"}
	tea_story_object = object_id
	tea_story_page = 0
	_advance_tea_story_token()
	if pages.size() == 1:
		_mark_tea_story_seen(object_id)
	return _tea_story_read_result(pages)

func turn_tea_story(object_id: String, session: int, read_token: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if not _is_story_scene_valid():
		return {"ok": false, "reason": "阅读场景已经改变。"}
	if tea_story_object == "" or object_id != tea_story_object or read_token != tea_story_token:
		return {"ok": false, "reason": "这次阅读已经失效。"}
	var objects: Dictionary = _tea_story_source.get("objects", {})
	if not objects.has(object_id):
		return {"ok": false, "reason": "故事物件内容缺失。"}
	var source_object: Dictionary = objects[object_id]
	var pages: Array = source_object.get("pages", [])
	if pages.is_empty() or tea_story_page < 0 or tea_story_page >= pages.size() - 1:
		return {"ok": false, "reason": "已经读到最后一页。"}
	tea_story_page += 1
	_advance_tea_story_token()
	if tea_story_page == pages.size() - 1:
		_mark_tea_story_seen(object_id)
	return _tea_story_read_result(pages)

func close_tea_story() -> void:
	tea_story_object = ""
	tea_story_page = 0
	_advance_tea_story_token()

func fill_tea_cup(object_id: String, session: int, read_token: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if tea_story_stage != TEA_STORY_ENDING_STAGE or tea_scene_id != TEA_TERRACE_ID:
		return {"ok": false, "reason": "还没有回到最后的剑坪。"}
	if not bool(tea_story_seen.get("tea.cup_first", false)) or not bool(tea_story_seen.get("tea.cup_second", false)):
		return {"ok": false, "reason": "请先重新看过剑坪上的两只旧杯。"}
	if tea_story_object == "" or object_id != tea_story_object or read_token != tea_story_token:
		return {"ok": false, "reason": "请先查看对应的旧杯。"}
	if tea_ending_step == 0 and object_id == "tea.cup_first":
		tea_ending_step = 1
		_tea_ending_first_fill_msec = Time.get_ticks_msec()
		close_tea_story()
		return {"ok": true, "ending_step": tea_ending_step}
	if tea_ending_step == 1 and object_id == "tea.cup_second":
		if Time.get_ticks_msec() - _tea_ending_first_fill_msec < TEA_STORY_ENDING_DELAY_MSEC:
			return {"ok": false, "reason": "静静等一会儿。"}
		tea_ending_step = 2
		tea_quest_complete = true
		close_tea_story()
		return {"ok": true, "ending_step": tea_ending_step}
	return {"ok": false, "reason": "现在还不能为这只杯子添茶。"}

func execute_tea_action(object_id: String, action_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if tea_story_stage == TEA_STORY_ENDING_STAGE:
		return {"ok": false, "reason": "最后一幕不再使用旧的茶事行动。"}
	if object_id not in TEA_OBJECT_IDS:
		return {"ok": false, "reason": "未知的调查物件。"}
	if tea_scene_id != TEA_TERRACE_ID:
		return {"ok": false, "reason": "这件物品不在当前场景。"}
	if action_id not in ["repair", "ask_mentor"]:
		return {"ok": false, "reason": "未知的茶事行动。"}
	if action_id == "repair" and object_id != "tea.cup_first":
		return {"ok": false, "reason": "这只茶杯目前无法修补。"}
	if not bool(tea_seen.get(object_id, false)):
		return {"ok": false, "reason": "请先查看这只茶杯。"}
	if _has_tea_action_done(object_id, action_id):
		return {"ok": false, "reason": "这项茶事行动已经完成。"}
	var cost := int(rules.training_cost) if action_id == "repair" else int(rules.mentor_cost)
	if energy < cost:
		return {"ok": false, "reason": "精力不足，暂时无法进行这项行动。"}
	energy -= cost
	_mark_tea_action_done(object_id, action_id)
	var feedback_key := "repair" if action_id == "repair" else "rumor"
	return {"ok": true, "cost": cost, "feedback_key": feedback_key}

func confirm_tea(object_id: String, session: int, read_token: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if tea_scene_id != TEA_TERRACE_ID:
		return {"ok": false, "reason": "这件物品不在当前场景。"}
	if _tea_pending_read_token == 0 or object_id not in TEA_OBJECT_IDS or read_token != _tea_pending_read_token or object_id != _tea_pending_object_id:
		return {"ok": false, "reason": "这次阅读已经失效。"}
	var new_clue := not bool(tea_seen.get(object_id, false))
	tea_seen[object_id] = true
	_clear_pending_tea_read()
	return {"ok": true, "new_clue": new_clue}

func finish_tea(session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not bool(tea_seen.get("tea.cup_first", false)) or not bool(tea_seen.get("tea.cup_second", false)):
		return {"ok": false, "reason": "还没有确认两只茶杯的线索。"}
	var new_completion := not tea_stage_complete
	tea_stage_complete = true
	return {"ok": true, "new_completion": new_completion}

func can_return_from_tea() -> bool:
	return not tea_accepted or (tea_stage_complete and tea_quest_complete)

func cancel_tea() -> Dictionary:
	if not tea_active:
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not can_return_from_tea():
		return {"ok": false, "reason": "茶事尚未完成，暂时不能离开。"}
	_invalidate_tea_session()
	return {"ok": true}

func complete() -> bool:
	return cultivation >= int(rules.goal)

func time_text() -> String:
	return "第 %d 日 · %s" % [day, rules.times[time_index]]

func _is_active_tea_session(session: int) -> bool:
	return tea_active and session == tea_session

func _clear_pending_tea_read() -> void:
	_tea_pending_object_id = ""
	_tea_pending_read_token = 0

func _has_tea_action_done(object_id: String, action_id: String) -> bool:
	var completed_actions: Dictionary = tea_action_done.get(object_id, {})
	return bool(completed_actions.get(action_id, false))

func _mark_tea_action_done(object_id: String, action_id: String) -> void:
	var completed_actions: Dictionary = tea_action_done.get(object_id, {})
	completed_actions[action_id] = true
	tea_action_done[object_id] = completed_actions

func _invalidate_tea_session() -> void:
	tea_session += 1
	tea_active = false
	_clear_pending_tea_read()
	close_tea_story()

func _is_story_scene_valid() -> bool:
	return tea_scene_id == (TEA_TERRACE_ID if tea_story_stage == TEA_STORY_ENDING_STAGE else TEA_COURTYARD_ID)

func _tea_story_read_result(pages: Array) -> Dictionary:
	return {
		"ok": true,
		"page": (pages[tea_story_page] as Dictionary).duplicate(true),
		"read_token": tea_story_token,
		"page_index": tea_story_page,
		"page_count": pages.size(),
	}

func _mark_tea_story_seen(object_id: String) -> void:
	tea_story_seen[object_id] = true

func _advance_tea_story_token() -> void:
	tea_story_token += 1

func _advance(amount: int) -> void:
	var next := time_index + amount
	day += floori(float(next) / float(rules.times.size()))
	time_index = next % rules.times.size()
