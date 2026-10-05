extends RefCounted

const TEA_OBJECT_IDS := ["tea.cup_first", "tea.cup_second"]

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
var tea_active := false
var tea_session: int = 0
var _tea_read_counter: int = 0
var _tea_pending_object_id := ""
var _tea_pending_read_token: int = 0

func _init() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/rules.json"))
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

func inspect_tea(object_id: String, session: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
	if not tea_accepted:
		return {"ok": false, "reason": "请先接受归剑委托。"}
	if object_id not in TEA_OBJECT_IDS:
		return {"ok": false, "reason": "未知的调查物件。"}
	_tea_read_counter += 1
	_tea_pending_object_id = object_id
	_tea_pending_read_token = _tea_read_counter
	return {"ok": true, "read_token": _tea_pending_read_token}

func confirm_tea(object_id: String, session: int, read_token: int) -> Dictionary:
	if not _is_active_tea_session(session):
		return {"ok": false, "reason": "调查会话已经结束。"}
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
	_invalidate_tea_session()
	return {"ok": true, "new_completion": new_completion}

func cancel_tea() -> void:
	_invalidate_tea_session()

func complete() -> bool:
	return cultivation >= int(rules.goal)

func time_text() -> String:
	return "第 %d 日 · %s" % [day, rules.times[time_index]]

func _is_active_tea_session(session: int) -> bool:
	return tea_active and session == tea_session

func _clear_pending_tea_read() -> void:
	_tea_pending_object_id = ""
	_tea_pending_read_token = 0

func _invalidate_tea_session() -> void:
	tea_session += 1
	tea_active = false
	_clear_pending_tea_read()

func _advance(amount: int) -> void:
	var next := time_index + amount
	day += floori(float(next) / float(rules.times.size()))
	time_index = next % rules.times.size()
