extends Node

signal line_ready(speaker: String, text: String, choices: Array)
signal ended()
signal failed(message: String)

const DIALOGUE_PATH := "res://scripts/dialogue_tools_lab/mentor_dm.txt"
const TAKE_LESSON_LABEL := "坐下来，随师父调息（精力8 · 1时辰）"
const RETURN_LABEL := "先回去自己试试"
const EXPECTED_LINES := [
	{"speaker": "江砚秋", "text": "师父，刚才那一剑，我明明已经快了，怎么还是收不住？"},
	{"speaker": "叶知闲", "text": "过来坐。你这口气，还留在剑坪上呢。"},
	{"speaker": "江砚秋", "text": "我就是想早些练好，免得总让您等。"},
	{"speaker": "叶知闲", "text": "剑快一点不难。难的是出剑时，心里不抢那一步。"},
	{"speaker": "叶知闲", "text": "先陪我听一会儿雨。等肩膀松了，再想刚才那一剑。"},
	{"speaker": "江砚秋", "text": "好，我不抢。先把这一口气放稳。"},
	{"speaker": "叶知闲", "text": "这就对了。待会儿再出剑，记住此刻肩上的轻松。"},
	{"speaker": "江砚秋", "text": "那我先去试试。要是还不对，我再来找您。"},
	{"speaker": "叶知闲", "text": "去吧。慢半步，也无妨。"},
]

var _generation := 0
var _active := false
var _busy := false
var _host: Node
var _dialogue_manager: Object
var _resource: Resource
var _current_line: Variant
var _responses_by_option: Dictionary = {}
var _last_response_id := ""
var _used_real_parser := false


func begin(host: Node) -> void:
	stop()
	var token := _generation
	_used_real_parser = false
	_last_response_id = ""
	_active = true
	_host = host
	if not is_instance_valid(host):
		_fail(token, "Dialogue Manager lab host is not a live Node.")
		return
	if not host.has_method("can_take_lesson") or not host.has_method("apply_choice"):
		_fail(token, "Dialogue Manager lab host must implement can_take_lesson() and apply_choice(option_id).")
		return
	_dialogue_manager = get_tree().root.get_node_or_null("DialogueManager")
	if not is_instance_valid(_dialogue_manager):
		_fail(token, "DialogueManager autoload node is unavailable; enable the pinned plugin runtime before starting the lab.")
		return
	if not Engine.has_singleton("DialogueManager") or Engine.get_singleton("DialogueManager") != _dialogue_manager:
		_fail(token, "Pinned DialogueManager runtime has not registered its required engine singleton yet.")
		return
	if not FileAccess.file_exists(DIALOGUE_PATH):
		_fail(token, "Dialogue Manager lab dialogue is missing: %s" % DIALOGUE_PATH)
		return

	var source := FileAccess.get_file_as_string(DIALOGUE_PATH)
	if source.is_empty():
		_fail(token, "Dialogue Manager lab dialogue is empty or could not be read: %s" % DIALOGUE_PATH)
		return
	var source_error := _validate_literal_dialogue_source(source)
	if not source_error.is_empty():
		_fail(token, source_error)
		return

	_busy = true
	var parsed: Variant = _dialogue_manager.call("create_resource_from_text", source)
	if not (parsed is Resource):
		_fail(token, "DialogueManager.create_resource_from_text did not return a Resource.")
		return
	_resource = parsed as Resource
	var resource_error := _validate_parsed_resource(_resource)
	if not resource_error.is_empty():
		_fail(token, resource_error)
		return
	_used_real_parser = true
	_load_line(token, "")


func advance() -> void:
	if not _active or _busy or not is_instance_valid(_current_line):
		return
	if not _responses_by_option.is_empty():
		return
	var next_id := str(_current_line.get("next_id"))
	if next_id.is_empty():
		_fail(_generation, "Dialogue Manager returned a line without a next_id.")
		return
	_busy = true
	_load_line(_generation, next_id)


func advance_choice(option_id: String) -> void:
	if not _active or _busy:
		return
	if _responses_by_option.is_empty():
		return
	if not _responses_by_option.has(option_id):
		_fail(_generation, "Dialogue Manager lab rejected unknown choice id: %s" % option_id)
		return

	var choice: Dictionary = _responses_by_option[option_id]
	if not bool(choice.get("enabled", false)):
		_fail(_generation, "Dialogue Manager lab rejected disabled choice id: %s" % option_id)
		return
	if not is_instance_valid(_host) or not _host.has_method("apply_choice"):
		_fail(_generation, "Dialogue Manager lab host is no longer available to settle the choice.")
		return

	_busy = true
	var token := _generation
	var response: Variant = choice.get("response")
	var response_id := str(response.get("id"))
	var branch_id := str(response.get("next_id"))
	if response_id.is_empty() or branch_id.is_empty():
		_fail(token, "Dialogue Manager returned a choice without a response id or next_id.")
		return

	var accepted: Variant = _host.call("apply_choice", option_id)
	if not _is_current(token):
		return
	if not bool(accepted):
		_fail(token, "Session rejected Dialogue Manager choice: %s" % option_id)
		return

	_last_response_id = response_id
	_load_line(token, branch_id)


func stop() -> void:
	_generation += 1
	_active = false
	_busy = false
	_host = null
	_dialogue_manager = null
	_resource = null
	_current_line = null
	_responses_by_option.clear()


func audit() -> Dictionary:
	var response_ids: Array[String] = []
	for choice in _responses_by_option.values():
		var response: Variant = choice.get("response")
		if is_instance_valid(response):
			response_ids.append(str(response.get("id")))
	return {
		"line_id": str(_current_line.get("id")) if is_instance_valid(_current_line) else "",
		"response_id": _last_response_id,
		"response_ids": response_ids,
		"used_real_parser": _used_real_parser,
	}


func _load_line(token: int, cue: String) -> void:
	if not _is_current(token):
		return
	var resource := _resource
	var dialogue_line: Variant = await resource.call("get_next_dialogue_line", cue)
	if not _is_current(token):
		return
	if dialogue_line == null:
		_finish(token)
		return
	if str(dialogue_line.get("type")) != "dialogue":
		_fail(token, "Dialogue Manager returned a non-dialogue line at runtime.")
		return
	if not _prepare_choices(token, dialogue_line):
		return

	_current_line = dialogue_line
	_busy = false
	line_ready.emit(
		str(dialogue_line.get("character")),
		str(dialogue_line.get("text")),
		_build_choices()
	)


func _prepare_choices(token: int, dialogue_line: Variant) -> bool:
	_responses_by_option.clear()
	var responses: Variant = dialogue_line.get("responses")
	if not (responses is Array):
		_fail(token, "Dialogue Manager returned a line with an invalid responses value.")
		return false
	if responses.is_empty():
		return true
	if responses.size() != 2:
		_fail(token, "mentor_tip must have exactly two whitelisted Dialogue Manager responses.")
		return false

	var expected_labels: Array[String] = [TAKE_LESSON_LABEL, RETURN_LABEL]
	var option_ids: Array[String] = ["take_lesson", "return_to_practice"]
	for index in range(responses.size()):
		var response: Variant = responses[index]
		var label := str(response.get("text"))
		if label != expected_labels[index]:
			_fail(token, "Dialogue Manager response order or text no longer matches the mentor_tip whitelist.")
			return false
		if not bool(response.get("is_allowed")) or not str(response.get("condition_as_text")).is_empty():
			_fail(token, "Dialogue Manager responses must be unconditional; Session owns choice availability.")
			return false
		if str(response.get("id")).is_empty() or str(response.get("next_id")).is_empty():
			_fail(token, "Dialogue Manager returned a response without an id or branch next_id.")
			return false

		var option_id := option_ids[index]
		var enabled := true
		if option_id == "take_lesson":
			if not is_instance_valid(_host) or not _host.has_method("can_take_lesson"):
				_fail(token, "Dialogue Manager lab host cannot report whether the lesson is affordable.")
				return false
			enabled = bool(_host.call("can_take_lesson"))
		_responses_by_option[option_id] = {
			"response": response,
			"label": label,
			"enabled": enabled,
		}
	return true


func _build_choices() -> Array:
	var choices: Array = []
	for option_id in ["take_lesson", "return_to_practice"]:
		if not _responses_by_option.has(option_id):
			continue
		var response: Dictionary = _responses_by_option[option_id]
		choices.append({
			"id": option_id,
			"label": str(response.get("label", "")),
			"enabled": bool(response.get("enabled", false)),
		})
	return choices


func _validate_literal_dialogue_source(source: String) -> String:
	var expected_labels: Array[String] = [TAKE_LESSON_LABEL, RETURN_LABEL]
	var option_ids: Array[String] = ["take_lesson", "return_to_practice"]
	var branch_line_counts := {"take_lesson": 0, "return_to_practice": 0}
	var branch_has_end := {"take_lesson": false, "return_to_practice": false}
	var next_option_index := 0
	var next_dialogue_index := 0
	var active_option := ""
	var saw_start_cue := false
	var saw_dialogue_before_cue := false
	var source_lines := source.split("\n")
	for line_number in range(source_lines.size()):
		var raw_line: String = source_lines[line_number]
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var indent_level := _dialogue_indent_level(raw_line)
		if indent_level < 0 or indent_level > 1:
			return "Dialogue Manager lab source uses unsupported indentation at line %d." % (line_number + 1)
		for forbidden in ["{{", "}}", "[", "]", "==>", "~>", "#", "`", "$", "\\"]:
			if forbidden in line:
				return "Dialogue Manager lab source must contain literal text only (forbidden syntax at line %d)." % (line_number + 1)
		if line.begins_with("~"):
			if line != "~ start" or indent_level != 0 or saw_start_cue or saw_dialogue_before_cue:
				return "Dialogue Manager lab source may contain only one leading `~ start` cue."
			saw_start_cue = true
			continue
		if line.begins_with("=>"):
			if line != "=> END" or indent_level != 1 or active_option.is_empty() or branch_line_counts[active_option] != 2 or branch_has_end[active_option]:
				return "Dialogue Manager lab source may use only a fixed `=> END` after each two-line literal branch."
			branch_has_end[active_option] = true
			continue
		if line.begins_with("-"):
			if indent_level != 0 or not line.begins_with("- ") or line.length() <= 2:
				return "Dialogue Manager lab source has an unsupported response syntax at line %d." % (line_number + 1)
			if next_dialogue_index != 5 + next_option_index * 2:
				return "Dialogue Manager lab choices must follow the five-line opening and each complete two-line branch."
			if not active_option.is_empty():
				if branch_line_counts[active_option] != 2 or not branch_has_end[active_option]:
					return "Dialogue Manager lab response branch is missing its two literal lines or END at line %d." % (line_number + 1)
				active_option = ""
			var label := line.substr(2).strip_edges()
			if next_option_index >= expected_labels.size() or label != expected_labels[next_option_index]:
				return "Dialogue Manager lab source contains a response outside the mentor_tip whitelist."
			active_option = option_ids[next_option_index]
			next_option_index += 1
			continue

		# The experiment accepts only plain dialogue records and fixed two-line branches.
		if line.begins_with("do ") or line.begins_with("do! ") or line.begins_with("set ") or line.begins_with("$> ") or line.begins_with("$>> ") or line.begins_with("if ") or line.begins_with("elif") or line.begins_with("else") or line.begins_with("when ") or line.begins_with("match ") or line.begins_with("while ") or line.begins_with("using ") or line.begins_with("import "):
			return "Dialogue Manager lab source contains a non-dialogue instruction at line %d." % (line_number + 1)
		if indent_level == 1:
			if active_option.is_empty() or branch_line_counts[active_option] >= 2 or branch_has_end[active_option]:
				return "Dialogue Manager lab source has an unsupported branch line at line %d." % (line_number + 1)
			branch_line_counts[active_option] += 1
		else:
			if next_option_index > 0 or next_dialogue_index >= 5:
				return "Dialogue Manager lab source may not place dialogue outside the opening or a choice branch."
			if not active_option.is_empty():
				if branch_line_counts[active_option] != 2 or not branch_has_end[active_option]:
					return "Dialogue Manager lab response branch is missing its two literal lines or END at line %d." % (line_number + 1)
				active_option = ""
			saw_dialogue_before_cue = true
		var separator := line.find(": ")
		if separator <= 0 or separator + 2 >= line.length():
			return "Dialogue Manager lab accepts only the nine literal mentor_tip dialogue records (line %d)." % (line_number + 1)
		var speaker := line.substr(0, separator)
		var dialogue_text := line.substr(separator + 2)
		if next_dialogue_index >= EXPECTED_LINES.size():
			return "Dialogue Manager lab source contains extra mentor_tip text."
		var expected_line: Dictionary = EXPECTED_LINES[next_dialogue_index]
		if speaker != str(expected_line.get("speaker")) or dialogue_text != str(expected_line.get("text")):
			return "Dialogue Manager lab text or speaker no longer matches the authored mentor_tip order."
		next_dialogue_index += 1
	if not saw_start_cue or next_option_index != 2:
		return "Dialogue Manager lab source must start at `~ start` and contain both mentor_tip responses in order."
	if next_dialogue_index != EXPECTED_LINES.size():
		return "Dialogue Manager lab source must contain the nine authored mentor_tip dialogue records in order."
	if not active_option.is_empty() and (branch_line_counts[active_option] != 2 or not branch_has_end[active_option]):
		return "Dialogue Manager lab response branch is missing its two literal lines or END."
	return ""


func _dialogue_indent_level(raw_line: String) -> int:
	var remaining := raw_line
	var level := 0
	while remaining.begins_with("\t"):
		remaining = remaining.substr(1)
		level += 1
	if remaining.begins_with(" ") or remaining.begins_with("\\t"):
		return -1
	return level


func _validate_parsed_resource(resource: Resource) -> String:
	var using_states: Variant = resource.get("using_states")
	var lines: Variant = resource.get("lines")
	var cues: Variant = resource.get("cues")
	if not (using_states is PackedStringArray) or not using_states.is_empty():
		return "Dialogue Manager lab source must not declare external game states."
	if not (lines is Dictionary) or lines.is_empty():
		return "Dialogue Manager parser returned an empty or invalid dialogue resource."
	if lines.size() != 16:
		return "Dialogue Manager parsed fixture must contain nine dialogue records, two responses, one cue, three fixed END jumps, and its compiler trailing record."
	if not (cues is Dictionary) or cues.size() != 1 or not cues.has("start"):
		return "Dialogue Manager parser did not preserve the fixed start cue."
	var dialogue_ids: Array[String] = []
	var response_ids: Array[String] = []
	var cue_ids: Array[String] = []
	var end_jump_ids: Array[String] = []
	var trailing_record_ids: Array[String] = []
	for line_number in range(16):
		var line_id := str(line_number)
		if not lines.has(line_id):
			return "Dialogue Manager parser returned a missing numeric line id: %s" % line_id
		var entry: Variant = lines[line_id]
		if not (entry is Dictionary):
			return "Dialogue Manager parser returned an invalid line record."
		var line_type := str(entry.get("type", ""))
		if line_type not in ["dialogue", "response", "cue", "goto", ""]:
			return "Dialogue Manager lab source contains unsupported parsed line type: %s" % line_type
		if str(entry.get("id", "")) != str(line_id):
			return "Dialogue Manager parser returned a line whose id does not match its resource key."
		match line_type:
			"dialogue":
				dialogue_ids.append(str(line_id))
			"response":
				response_ids.append(str(line_id))
			"cue":
				cue_ids.append(str(line_id))
			"goto":
				end_jump_ids.append(str(line_id))
			"":
				trailing_record_ids.append(str(line_id))
		for property in ["expression", "condition", "mutation", "next_id_expression"]:
			var value: Variant = entry.get(property)
			if value is Dictionary or value is Array or value is PackedStringArray:
				if not value.is_empty():
					return "Dialogue Manager lab source contains a condition, expression, or mutation."
			elif value is String and not value.is_empty():
				return "Dialogue Manager lab source contains a condition, expression, or mutation."
		for property in ["text_replacements", "character_replacements", "inline_mutations", "siblings", "concurrent_lines", "tags"]:
			var values: Variant = entry.get(property)
			if (values is Array or values is PackedStringArray) and not values.is_empty():
				return "Dialogue Manager lab source contains dynamic replacements, conditions, or inline mutations."
		if not str(entry.get("condition_as_text", "")).is_empty():
			return "Dialogue Manager lab source contains a conditional response."
	if dialogue_ids.size() != EXPECTED_LINES.size() or response_ids.size() != 2 or cue_ids.size() != 1 or end_jump_ids.size() != 3 or trailing_record_ids != ["14"]:
		return "Dialogue Manager parsed fixture must contain nine authored records, two responses, one cue, three fixed END jumps, and one trailing compiler record."
	var trailing_record: Dictionary = lines["14"]
	if trailing_record.size() != 3 or not trailing_record.has("id") or not trailing_record.has("type") or not trailing_record.has("next_id") or trailing_record.has("text"):
		return "Dialogue Manager parser trailing record must be the fixed empty line before its compiler END jump."
	if str(trailing_record.get("next_id", "")) != "15":
		return "Dialogue Manager parser trailing record must be the fixed empty line before its compiler END jump."
	var trailing_end_jump: Dictionary = lines["15"]
	if str(trailing_end_jump.get("type", "")) != "goto" or str(trailing_end_jump.get("next_id", "")) != "end" or trailing_end_jump.has("text"):
		return "Dialogue Manager parser trailing compiler record must lead only to END."
	var cue_id := str(resource.get("first_cue"))
	var start_id := str(cues.get("start", ""))
	if cue_id.is_empty() or not lines.has(cue_id) or str(lines[cue_id].get("type", "")) != "cue" or start_id.is_empty() or str(lines[cue_id].get("next_id", "")) != start_id:
		return "Dialogue Manager parsed start cue no longer points to the first authored line."
	if cue_id != "0" or start_id != "1":
		return "Dialogue Manager parsed start cue no longer begins with the first authored line."
	for index in range(5):
		var dialogue_id := str(index + 1)
		if not lines.has(dialogue_id) or str(lines[dialogue_id].get("type", "")) != "dialogue":
			return "Dialogue Manager parsed opening no longer contains its five authored dialogue lines."
		var dialogue: Dictionary = lines[dialogue_id]
		var expected: Dictionary = EXPECTED_LINES[index]
		if str(dialogue.get("character", "")) != str(expected.get("speaker", "")) or str(dialogue.get("text", "")) != str(expected.get("text", "")):
			return "Dialogue Manager parsed dialogue no longer matches the nine-record authored whitelist."
		var expected_next_id := str(index + 2) if index < 4 else "6"
		if str(dialogue.get("next_id", "")) != expected_next_id:
			return "Dialogue Manager parsed opening path no longer matches the authored sequence."
	var question: Dictionary = lines["5"]
	var first_response_id := str(question.get("next_id", ""))
	if first_response_id != "6" or not lines.has(first_response_id) or str(lines[first_response_id].get("type", "")) != "response":
		return "Dialogue Manager parsed question is missing its whitelisted response group."
	var parsed_response_ids: Variant = lines[first_response_id].get("responses", [])
	if not (parsed_response_ids is Array or parsed_response_ids is PackedStringArray) or parsed_response_ids.size() != 2 or str(parsed_response_ids[0]) != "6" or str(parsed_response_ids[1]) != "10":
		return "Dialogue Manager parsed question must expose exactly the two authored responses."
	var expected_response_ids: Array[String] = ["6", "10"]
	var expected_branch_dialogue_ids: Array[String] = ["7", "11"]
	var expected_branch_goto_ids: Array[String] = ["9", "13"]
	for branch_index in range(2):
		var response_id := str(parsed_response_ids[branch_index])
		if not lines.has(response_id) or str(lines[response_id].get("type", "")) != "response":
			return "Dialogue Manager parsed choice group contains a missing or invalid response."
		var response: Dictionary = lines[response_id]
		var expected_label := TAKE_LESSON_LABEL if branch_index == 0 else RETURN_LABEL
		if response_id != expected_response_ids[branch_index] or str(response.get("text", "")) != expected_label:
			return "Dialogue Manager parsed response label or order no longer matches the exact whitelist."
		var branch_start_index := 5 + branch_index * 2
		var branch_start_id := expected_branch_dialogue_ids[branch_index]
		if str(response.get("next_id", "")) != branch_start_id:
			return "Dialogue Manager parsed choice no longer enters its authored two-line branch."
		var end_jump_id := expected_branch_goto_ids[branch_index]
		if str(lines[end_jump_id].get("next_id", "")) != "end":
			return "Dialogue Manager parsed branch contains a jump outside the fixed END target."
		for branch_line_index in range(2):
			var dialogue_index := branch_start_index + branch_line_index
			var dialogue_id := str(int(branch_start_id) + branch_line_index)
			if not lines.has(dialogue_id) or str(lines[dialogue_id].get("type", "")) != "dialogue":
				return "Dialogue Manager parsed branch no longer contains exactly two authored dialogue lines."
			var dialogue: Dictionary = lines[dialogue_id]
			var expected: Dictionary = EXPECTED_LINES[dialogue_index]
			if str(dialogue.get("character", "")) != str(expected.get("speaker", "")) or str(dialogue.get("text", "")) != str(expected.get("text", "")):
				return "Dialogue Manager parsed branch no longer matches the nine-record authored whitelist."
			var expected_next := str(int(dialogue_id) + 1) if branch_line_index == 0 else end_jump_id
			if str(dialogue.get("next_id", "")) != expected_next:
				return "Dialogue Manager parsed branch must contain exactly two authored lines and then END."
	if response_ids != expected_response_ids or end_jump_ids != ["9", "13", "15"] or dialogue_ids != ["1", "2", "3", "4", "5", "7", "8", "11", "12"] or cue_ids != ["0"]:
		return "Dialogue Manager parsed records no longer match the exact authored graph and compiler suffix."
	return ""


func _is_current(token: int) -> bool:
	if not _active or token != _generation:
		return false
	if not is_instance_valid(_host):
		_fail(token, "Dialogue Manager lab host was destroyed while the dialogue was active.")
		return false
	if not is_instance_valid(_resource):
		_fail(token, "Dialogue Manager parsed resource was released while the dialogue was active.")
		return false
	return true


func _finish(token: int) -> void:
	if not _is_current(token):
		return
	_generation += 1
	_active = false
	_busy = false
	_host = null
	_dialogue_manager = null
	_resource = null
	_current_line = null
	_responses_by_option.clear()
	ended.emit()


func _fail(token: int, message: String) -> void:
	if token != _generation:
		return
	_generation += 1
	_active = false
	_busy = false
	_host = null
	_dialogue_manager = null
	_resource = null
	_current_line = null
	_responses_by_option.clear()
	failed.emit(message)
