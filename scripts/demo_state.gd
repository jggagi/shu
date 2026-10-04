extends RefCounted

var rules: Dictionary
var day := 1
var time_index := 0
var energy := 100
var cultivation := 0
var understanding := 0
var lesson_bonus := 0
var dialogue_open := false

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

func train() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "请先结束与师傅的对话。"}
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
	var previous := energy
	energy = mini(int(rules.energy_max), energy + int(rules.rest_gain))
	_advance(int(rules.rest_duration))
	return {"ok": true, "gain": energy - previous}

func begin_dialogue() -> Dictionary:
	if dialogue_open:
		return {"ok": false, "reason": "正在与师傅交谈。"}
	if energy < int(rules.mentor_cost):
		return {"ok": false, "reason": "精力不足，歇一歇再向师傅请教。"}
	dialogue_open = true
	return {"ok": true}

func choose(topic: String) -> Dictionary:
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

func complete() -> bool:
	return cultivation >= int(rules.goal)

func time_text() -> String:
	return "第 %d 日 · %s" % [day, rules.times[time_index]]

func _advance(amount: int) -> void:
	var next := time_index + amount
	day += floori(float(next) / float(rules.times.size()))
	time_index = next % rules.times.size()
