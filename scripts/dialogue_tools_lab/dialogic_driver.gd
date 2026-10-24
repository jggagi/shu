extends Node

signal line_ready(speaker: String, text: String, choices: Array)
signal ended()
signal failed(message: String)

const TIMELINE_PATH := "res://scripts/dialogue_tools_lab/mentor_dialogic.txt"
const TIMELINE_SCRIPT_PATH := "res://addons/dialogic/Resources/timeline.gd"
const FONT_PATH := "res://assets/fonts/ShuDialogueLabSerif.ttf"

const TAKE_LESSON_LABEL := "坐下来，随师父调息（精力8 · 1时辰）"
const RETURN_LABEL := "先回去自己试试"
const TAKE_LESSON_ID := "take_lesson"
const RETURN_ID := "return_to_practice"
const PAPER := Color("#f3ead8")
const PAPER_LIGHT := Color("#fbf5e9")
const INK := Color("#302d28")
const MUTED_INK := Color("#766d60")
const GOLD := Color("#b89b69")

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

static var _ending_timeline: Resource

var _generation := 0
var _active := false
var _failed_once := false
var _waiting_question := false
var _choice_settled := false
var _used_real_timeline := false
var _last_event_index := -1
var _last_choice_id := ""
var _last_layout_path := ""

var _host: Node
var _dialogic: Node
var _text_subsystem: Object
var _choices_subsystem: Object
var _inputs_subsystem: Object
var _timeline: Resource
var _layout: Node
var _font: Font
var _pending_question_line: Dictionary = {}
var _current_choices: Array[Dictionary] = []
var _signal_bindings: Array[Dictionary] = []


func begin(host: Node) -> void:
	if _active:
		await stop()
	else:
		_generation += 1

	var token := _generation
	_active = true
	_failed_once = false
	_waiting_question = false
	_choice_settled = false
	_used_real_timeline = false
	_last_event_index = -1
	_last_choice_id = ""
	_last_layout_path = ""
	_host = host
	_pending_question_line.clear()
	_current_choices.clear()

	if not is_instance_valid(host):
		_fail(token, "Dialogic lab host is not a live Node.")
		return
	if not host.has_method("can_take_lesson") or not host.has_method("apply_choice"):
		_fail(token, "Dialogic lab host must implement can_take_lesson() and apply_choice(option_id).")
		return

	_dialogic = get_tree().root.get_node_or_null("Dialogic")
	if not is_instance_valid(_dialogic):
		_fail(token, "Dialogic autoload is unavailable; stage the addon and register its Dialogic autoload before starting the lab.")
		return
	if not _dialogic.has_method("has_subsystem") or not bool(_dialogic.call("has_subsystem", "Text")) or not bool(_dialogic.call("has_subsystem", "Choices")) or not bool(_dialogic.call("has_subsystem", "Inputs")) or not bool(_dialogic.call("has_subsystem", "Styles")):
		_fail(token, "Dialogic Text, Choices, Inputs, or Styles subsystem is unavailable.")
		return

	_text_subsystem = _dialogic.get("Text") as Object
	_choices_subsystem = _dialogic.get("Choices") as Object
	_inputs_subsystem = _dialogic.get("Inputs") as Object
	if not is_instance_valid(_text_subsystem) or not is_instance_valid(_choices_subsystem) or not is_instance_valid(_inputs_subsystem):
		_fail(token, "Dialogic public subsystems could not be resolved.")
		return
	if not _dialogic.has_signal("timeline_started") or not _dialogic.has_signal("timeline_ended") or not _text_subsystem.has_signal("text_started") or not _choices_subsystem.has_signal("question_shown") or not _choices_subsystem.has_signal("choice_selected") or not _choices_subsystem.has_signal("invalid_question_reached"):
		_fail(token, "Dialogic public timeline, text, or choice signals are unavailable.")
		return
	if not _inputs_subsystem.has_method("handle_input") or not _choices_subsystem.has_method("select_choice"):
		_fail(token, "Dialogic public input or choice-forwarding API is unavailable.")
		return

	var font_resource := ResourceLoader.load(FONT_PATH)
	if not font_resource is Font:
		_fail(token, "Dialogic lab font is missing or invalid: %s" % FONT_PATH)
		return
	_font = font_resource as Font

	if not FileAccess.file_exists(TIMELINE_PATH):
		_fail(token, "Dialogic lab timeline is missing: %s" % TIMELINE_PATH)
		return
	var source := FileAccess.get_file_as_string(TIMELINE_PATH)
	if source.is_empty():
		_fail(token, "Dialogic lab timeline is empty or could not be read: %s" % TIMELINE_PATH)
		return
	var source_error := _validate_literal_timeline(source)
	if not source_error.is_empty():
		_fail(token, source_error)
		return

	var timeline_script := ResourceLoader.load(TIMELINE_SCRIPT_PATH) as Script
	if not is_instance_valid(timeline_script):
		_fail(token, "DialogicTimeline script is unavailable: %s" % TIMELINE_SCRIPT_PATH)
		return
	var timeline_object: Variant = timeline_script.new()
	if not timeline_object is Resource or not timeline_object.has_method("from_text"):
		_fail(token, "DialogicTimeline could not be instantiated from the pinned addon.")
		return
	_timeline = timeline_object as Resource
	_timeline.call("from_text", source)
	var parsed_error := _validate_parsed_timeline(_timeline)
	if not parsed_error.is_empty():
		_fail(token, parsed_error)
		return

	var current_timeline: Variant = _dialogic.get("current_timeline")
	if is_instance_valid(current_timeline):
		if _ending_timeline == current_timeline:
			await Signal(_dialogic, &"timeline_ended")
			if token != _generation or not _active:
				return
			_ending_timeline = null
		else:
			_fail(token, "Another Dialogic timeline is already active; the lab will not replace it.")
			return

	_connect_dialogic_signals(token)
	var styles: Object = _dialogic.get("Styles") as Object
	if is_instance_valid(styles) and styles.has_method("get_layout_node"):
		var existing_layout: Variant = styles.call("get_layout_node")
		if is_instance_valid(existing_layout):
			_layout = existing_layout as Node
			_configure_layout(_layout)

	var started_layout: Variant = _dialogic.call("start", _timeline)
	if not is_instance_valid(started_layout):
		_fail(token, "Dialogic.start() did not return its native layout node.")
		return
	_layout = started_layout as Node
	_configure_layout(_layout)
	_last_layout_path = _get_layout_resource_path(_layout)


func advance() -> void:
	if not _active or _waiting_question or not is_instance_valid(_dialogic) or not is_instance_valid(_inputs_subsystem):
		return
	if _dialogic.get("current_timeline") != _timeline:
		return
	_inputs_subsystem.call("handle_input")


func advance_choice(id: String) -> void:
	if not _active or not _waiting_question or _choice_settled or not is_instance_valid(_choices_subsystem):
		return
	var index := _choice_index_for_id(id)
	if index < 1 or index > _current_choices.size():
		_fail(_generation, "Dialogic lab rejected unknown choice id: %s" % id)
		return
	var choice: Dictionary = _current_choices[index - 1]
	if not bool(choice.get("enabled", false)):
		return
	_choices_subsystem.call("select_choice", index)


func stop() -> void:
	var token := _generation
	var dialogic := _dialogic
	var timeline := _timeline
	var layout := _layout
	var should_end := _owns_dialogic_run(dialogic, timeline, layout)

	_generation += 1
	_active = false
	_waiting_question = false
	_disconnect_dialogic_signals()
	_cancel_pending_start(dialogic, timeline, layout)
	_host = null
	_pending_question_line.clear()
	_current_choices.clear()

	if should_end:
		_ending_timeline = timeline
		if is_instance_valid(layout) and not layout.is_inside_tree():
			layout.queue_free()
		await dialogic.call("end_timeline", true)
		if _ending_timeline == timeline:
			_ending_timeline = null
	if token + 1 == _generation:
		_clear_runtime_refs()


func audit() -> Dictionary:
	return {
		"used_real_timeline": _used_real_timeline,
		"current_event_index": _get_current_event_index(),
		"layout_path": _get_layout_resource_path(_layout) if is_instance_valid(_layout) else _last_layout_path,
		"timeline_source_path": TIMELINE_PATH,
		"choice_id": _last_choice_id,
		"active": _active,
	}


func _connect_dialogic_signals(token: int) -> void:
	_connect_signal(_dialogic, "timeline_started", Callable(self, "_on_timeline_started").bind(token))
	_connect_signal(_dialogic, "timeline_ended", Callable(self, "_on_timeline_ended").bind(token))
	_connect_signal(_text_subsystem, "text_started", Callable(self, "_on_text_started").bind(token))
	_connect_signal(_choices_subsystem, "question_shown", Callable(self, "_on_question_shown").bind(token))
	_connect_signal(_choices_subsystem, "choice_selected", Callable(self, "_on_choice_selected").bind(token))
	_connect_signal(_choices_subsystem, "invalid_question_reached", Callable(self, "_on_invalid_question").bind(token))


func _connect_signal(source: Object, signal_name: StringName, callback: Callable) -> void:
	if not is_instance_valid(source) or not source.has_signal(signal_name):
		return
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)
	_signal_bindings.append({"source": source, "signal": signal_name, "callback": callback})


func _disconnect_dialogic_signals() -> void:
	for binding in _signal_bindings:
		var source: Variant = binding.get("source")
		var signal_name: StringName = binding.get("signal", &"")
		var callback: Callable = binding.get("callback", Callable())
		if is_instance_valid(source) and source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)
	_signal_bindings.clear()


func _on_timeline_started(token: int) -> void:
	if not _is_current(token):
		return
	if _dialogic.get("current_timeline") != _timeline:
		return
	_used_real_timeline = true
	_last_event_index = int(_dialogic.get("current_event_idx"))


func _on_timeline_ended(token: int) -> void:
	if not _is_current(token) or not _used_real_timeline:
		return
	_active = false
	_waiting_question = false
	_disconnect_dialogic_signals()
	_host = null
	_pending_question_line.clear()
	_current_choices.clear()
	ended.emit()


func _on_text_started(info: Dictionary, token: int) -> void:
	if not _is_current(token) or _dialogic.get("current_timeline") != _timeline:
		return
	_last_event_index = int(_dialogic.get("current_event_idx"))
	var speaker := _speaker_name(info.get("character"))
	var text := str(info.get("text", ""))
	var choices: Object = _choices_subsystem
	if is_instance_valid(choices) and bool(choices.call("is_question", _last_event_index)):
		_pending_question_line = {"speaker": speaker, "text": text}
		_waiting_question = true
		_choice_settled = false
		return
	line_ready.emit(speaker, text, [])


func _on_question_shown(info: Dictionary, token: int) -> void:
	if not _is_current(token) or _dialogic.get("current_timeline") != _timeline:
		return
	_last_event_index = int(_dialogic.get("current_event_idx"))
	if _pending_question_line.is_empty():
		_fail(token, "Dialogic showed a native question without its preceding mentor text.")
		return
	if not is_instance_valid(_host) or not _host.has_method("can_take_lesson"):
		_fail(token, "Dialogic lab host is no longer available to validate the lesson choice.")
		return
	var native_choices: Variant = info.get("choices", [])
	if not native_choices is Array or native_choices.size() != 2:
		_fail(token, "Dialogic mentor question must expose exactly two native choices.")
		return

	var expected_labels: Array[String] = [TAKE_LESSON_LABEL, RETURN_LABEL]
	var option_ids: Array[String] = [TAKE_LESSON_ID, RETURN_ID]
	var available := bool(_host.call("can_take_lesson"))
	_current_choices.clear()
	for index in range(2):
		var native_choice: Variant = native_choices[index]
		if not native_choice is Dictionary:
			_fail(token, "Dialogic returned a malformed native choice entry.")
			return
		var choice_info: Dictionary = native_choice
		if int(choice_info.get("button_index", -1)) != index + 1 or str(choice_info.get("text", "")) != expected_labels[index]:
			_fail(token, "Dialogic native choice order or label no longer matches the Session whitelist.")
			return
		if bool(choice_info.get("disabled", false)) or not bool(choice_info.get("visible", false)):
			_fail(token, "Dialogic mentor choices must remain unconditional and visible.")
			return
		var enabled := available if index == 0 else true
		var button: Variant = _choices_subsystem.call("get_choice_button", index + 1)
		if not is_instance_valid(button) or not button is Button:
			_fail(token, "Dialogic native choice button %d is missing from the active layout." % (index + 1))
			return
		button.disabled = not enabled
		_style_native_choice_button(button as Button, enabled)
		_current_choices.append({"id": option_ids[index], "label": expected_labels[index], "enabled": enabled})

	_waiting_question = true
	var question_line := _pending_question_line.duplicate()
	line_ready.emit(str(question_line.get("speaker", "")), str(question_line.get("text", "")), _current_choices.duplicate(true))


func _on_choice_selected(info: Dictionary, token: int) -> void:
	if not _is_current(token) or _dialogic.get("current_timeline") != _timeline:
		return
	_last_event_index = int(_dialogic.get("current_event_idx"))
	if not _waiting_question or _choice_settled:
		_fail(token, "Dialogic emitted a native choice outside the active mentor question.")
		return
	var index := int(info.get("button_index", -1))
	if index < 1 or index > _current_choices.size():
		_fail(token, "Dialogic native choice index is outside the Session whitelist.")
		return
	var choice: Dictionary = _current_choices[index - 1]
	var option_id := str(choice.get("id", ""))
	if str(info.get("text", "")) != str(choice.get("label", "")) or not bool(choice.get("enabled", false)):
		_fail(token, "Dialogic native choice text or enabled state no longer matches the Session whitelist.")
		return
	if not is_instance_valid(_host) or not _host.has_method("apply_choice"):
		_fail(token, "Dialogic lab host is no longer available to settle the native choice.")
		return

	_choice_settled = true
	var accepted: Variant = _host.call("apply_choice", option_id)
	if not _is_current(token):
		return
	if not bool(accepted):
		_fail(token, "Session rejected Dialogic native choice: %s" % option_id)
		return
	_last_choice_id = option_id
	_waiting_question = false
	_pending_question_line.clear()
	_current_choices.clear()


func _on_invalid_question(token: int) -> void:
	if _is_current(token):
		_fail(token, "Dialogic reached an invalid native question with no usable choice.")


func _fail(token: int, message: String) -> void:
	if not _is_current(token) or _failed_once:
		return
	_failed_once = true
	_active = false
	_waiting_question = false
	_disconnect_dialogic_signals()
	var dialogic := _dialogic
	var timeline := _timeline
	var layout := _layout
	var should_end := _owns_dialogic_run(dialogic, timeline, layout)
	if should_end:
		_cancel_pending_start(dialogic, timeline, layout)
	_host = null
	_pending_question_line.clear()
	_current_choices.clear()
	if should_end:
		_ending_timeline = timeline
		if is_instance_valid(layout) and not layout.is_inside_tree():
			layout.queue_free()
		await dialogic.call("end_timeline", true)
		if _ending_timeline == timeline:
			_ending_timeline = null
	if token == _generation and _failed_once:
		failed.emit(message)


func _cancel_pending_start(dialogic: Node, timeline: Resource, layout: Node) -> void:
	if not is_instance_valid(dialogic) or not is_instance_valid(layout) or layout.is_node_ready():
		return
	var start_callback := Callable(dialogic, "start_timeline").bind(timeline, "")
	if layout.ready.is_connected(start_callback):
		layout.ready.disconnect(start_callback)
	var clear_callback := Callable(dialogic, "clear").bind(1) # ClearFlags.KEEP_VARIABLES
	if layout.ready.is_connected(clear_callback):
		layout.ready.disconnect(clear_callback)


func _owns_dialogic_run(dialogic: Node, timeline: Resource, layout: Node) -> bool:
	if not is_instance_valid(dialogic) or not is_instance_valid(timeline):
		return false
	if _ending_timeline == timeline:
		return false
	if dialogic.get("current_timeline") == timeline:
		return true
	if _used_real_timeline or not is_instance_valid(layout) or layout.is_queued_for_deletion():
		return false
	var styles: Variant = dialogic.get("Styles")
	if not is_instance_valid(styles) or not styles.has_method("get_layout_node"):
		return false
	return styles.call("get_layout_node") == layout


func _configure_layout(layout: Node) -> void:
	if not is_instance_valid(layout):
		return
	_set_if_present(layout, &"global_font", FONT_PATH)
	_set_if_present(layout, &"global_font_size", 21)
	_set_if_present(layout, &"global_font_color", INK)
	_set_if_present(layout, &"global_bg_color", PAPER)
	if layout.has_method("get_layers"):
		for layer_value in layout.call("get_layers"):
			if not is_instance_valid(layer_value):
				continue
			var layer := layer_value as Node
			var script := layer.get_script() as Script
			if not is_instance_valid(script):
				continue
			match script.resource_path.get_file():
				"vn_textbox_layer.gd":
					_set_if_present(layer, &"text_use_global_font", true)
					_set_if_present(layer, &"text_use_global_size", true)
					_set_if_present(layer, &"text_size", 21)
					_set_if_present(layer, &"text_use_global_color", true)
					_set_if_present(layer, &"box_size", Vector2(1180, 170))
					_set_if_present(layer, &"box_margin_bottom", 28)
					_set_if_present(layer, &"box_color_use_global", true)
					_set_if_present(layer, &"name_label_use_global_font", true)
					_set_if_present(layer, &"name_label_use_global_font_size", true)
					_set_if_present(layer, &"name_label_custom_font_size", 20)
				"vn_choice_layer.gd":
					_set_if_present(layer, &"font_use_global", true)
					_set_if_present(layer, &"font_size_use_global", true)
					_set_if_present(layer, &"font_size_custom", 20)
					_set_if_present(layer, &"text_color_use_global", true)
					_set_if_present(layer, &"boxes_v_separation", 12)
					_set_if_present(layer, &"boxes_min_size", Vector2(720, 58))
					_set_if_present(layer, &"boxes_offset", Vector2(0, 105))
		if layout.has_method("apply_export_overrides"):
			layout.call("apply_export_overrides")
	_last_layout_path = _get_layout_resource_path(layout)


func _style_native_choice_button(button: Button, enabled: bool) -> void:
	if not is_instance_valid(button):
		return
	button.add_theme_font_override(&"font", _font)
	button.add_theme_font_size_override(&"font_size", 20)
	button.add_theme_color_override(&"font_color", INK)
	button.add_theme_color_override(&"font_hover_color", INK)
	button.add_theme_color_override(&"font_pressed_color", INK)
	button.add_theme_color_override(&"font_focus_color", INK)
	button.add_theme_color_override(&"font_disabled_color", MUTED_INK)
	button.custom_minimum_size = Vector2(720, 58)
	var normal := _make_choice_panel(PAPER_LIGHT, GOLD, 1)
	var hover := _make_choice_panel(Color("#efe1c7"), GOLD, 2)
	var pressed := _make_choice_panel(Color("#e8d6b6"), GOLD, 2)
	var disabled := _make_choice_panel(Color("#e5dccb"), Color("#c5b99f"), 1)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"focus", hover)
	button.add_theme_stylebox_override(&"disabled", disabled)
	if not enabled:
		button.disabled = true


func _make_choice_panel(color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = color
	panel.border_color = border_color
	panel.set_border_width_all(border_width)
	panel.set_corner_radius_all(7)
	panel.content_margin_left = 18
	panel.content_margin_top = 9
	panel.content_margin_right = 18
	panel.content_margin_bottom = 9
	return panel


func _set_if_present(target: Object, property: StringName, value: Variant) -> void:
	if is_instance_valid(target) and property in target:
		target.set(property, value)


func _speaker_name(character: Variant) -> String:
	if is_instance_valid(character) and character.has_method("get_display_name_translated"):
		return str(character.call("get_display_name_translated"))
	return ""


func _choice_index_for_id(id: String) -> int:
	for index in range(_current_choices.size()):
		if str(_current_choices[index].get("id", "")) == id:
			return index + 1
	return -1


func _validate_literal_timeline(source: String) -> String:
	var expected_lines := _expected_timeline_source_lines()
	var lines := source.replace("\r\n", "\n").strip_edges().split("\n")
	if lines.size() != expected_lines.size():
		return "Dialogic lab timeline must contain exactly nine authored records and two choices."
	for index in range(expected_lines.size()):
		if lines[index] != expected_lines[index]:
			return "Dialogic lab timeline text, choice order, or structure no longer matches the authored whitelist (line %d)." % (index + 1)
	return ""


func _expected_timeline_source_lines() -> Array[String]:
	var expected: Array[String] = []
	for index in range(5):
		var line: Dictionary = EXPECTED_LINES[index]
		expected.append("%s: %s" % [str(line.get("speaker", "")), str(line.get("text", ""))])
	for branch_index in range(2):
		expected.append("- " + (TAKE_LESSON_LABEL if branch_index == 0 else RETURN_LABEL))
		for branch_line_index in range(2):
			var line: Dictionary = EXPECTED_LINES[5 + branch_index * 2 + branch_line_index]
			expected.append("\t%s: %s" % [str(line.get("speaker", "")), str(line.get("text", ""))])
	return expected


func _validate_parsed_timeline(timeline: Resource) -> String:
	if not timeline.has_method("process"):
		return "Dialogic parsed timeline does not expose the pinned process() parser."
	timeline.call("process")
	if not bool(timeline.get("events_processed")):
		return "Dialogic did not produce parsed events for the authored timeline."
	var events: Variant = timeline.get("events")
	if not (events is Array):
		return "Dialogic parser returned an invalid event list."
	var expected_events: Array[Dictionary] = []
	for index in range(5):
		var line: Dictionary = EXPECTED_LINES[index]
		expected_events.append({"kind": "Text", "speaker": str(line.get("speaker", "")), "text": str(line.get("text", ""))})
	for branch_index in range(2):
		expected_events.append({"kind": "Choice", "text": TAKE_LESSON_LABEL if branch_index == 0 else RETURN_LABEL})
		for branch_line_index in range(2):
			var line: Dictionary = EXPECTED_LINES[5 + branch_index * 2 + branch_line_index]
			expected_events.append({"kind": "Text", "speaker": str(line.get("speaker", "")), "text": str(line.get("text", ""))})
		expected_events.append({"kind": "End Branch"})
	if events.size() != expected_events.size():
		return "Dialogic parsed timeline must contain exactly the authored nine records, two choices, and two branch ends."
	for index in range(expected_events.size()):
		var parsed_event: Variant = events[index]
		if typeof(parsed_event) != TYPE_OBJECT or not is_instance_valid(parsed_event):
			return "Dialogic parser returned a missing or invalid event at index %d." % index
		var expected: Dictionary = expected_events[index]
		var event_name := str(parsed_event.get("event_name"))
		if event_name != str(expected.get("kind", "")):
			return "Dialogic parsed event structure no longer matches the exact authored whitelist at index %d." % index
		match event_name:
			"Text":
				if str(parsed_event.get("character_identifier")) != str(expected.get("speaker", "")) or str(parsed_event.get("text")) != str(expected.get("text", "")):
					return "Dialogic parsed text or speaker no longer matches the nine-record authored whitelist."
			"Choice":
				var extra_data: Variant = parsed_event.get("extra_data")
				if str(parsed_event.get("text")) != str(expected.get("text", "")) or not str(parsed_event.get("condition")).is_empty() or not str(parsed_event.get("disabled_text")).is_empty() or not (extra_data is Dictionary) or not extra_data.is_empty():
					return "Dialogic choices must match the exact labels and remain free of conditions or extra actions."
	return ""


func _is_current(token: int) -> bool:
	return _active and token == _generation


func _get_current_event_index() -> int:
	if _active and is_instance_valid(_dialogic) and _dialogic.get("current_timeline") == _timeline:
		return int(_dialogic.get("current_event_idx"))
	return _last_event_index


func _get_layout_resource_path(layout: Node) -> String:
	if is_instance_valid(layout):
		var style: Variant = layout.get_meta("style", null)
		if style is Resource and not style.resource_path.is_empty():
			return style.resource_path
		if not layout.scene_file_path.is_empty():
			return layout.scene_file_path
	return _last_layout_path


func _clear_runtime_refs() -> void:
	_dialogic = null
	_text_subsystem = null
	_choices_subsystem = null
	_inputs_subsystem = null
	_timeline = null
	_layout = null
	_font = null

