extends Control

const State = preload("res://scripts/demo_state.gd")
const INK := Color("354137")
const JADE := Color("32695c")
const GOLD := Color("ad8959")
const PAPER := Color("f4eddf")
const MUTED := Color("817968")

var state = State.new()
var layout: Dictionary
var dialogue: Dictionary
var energy_text: Label
var progress_text: Label
var relation_text: Label
var date_text: Label
var bonus_text: Label
var energy_bar: ProgressBar
var progress_bar: ProgressBar
var goal_title: Label
var goal_note: Label
var speaker: Label
var dialogue_text: Label
var result_text: Label
var train_button: Button
var mentor_button: Button
var rest_button: Button
var mentor_hotspot: Button
var choices: Array[Button] = []
var continue_button: Button
var player_art: TextureRect
var mentor_art: TextureRect
var busy := false
var awaiting_continue := false
var completion_announced := false

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/layout.json"))
	dialogue = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dialogue.json"))
	var game_theme := Theme.new()
	game_theme.default_font = load("res://assets/fonts/ShuDemoSans.ttf")
	game_theme.default_font_size = 21
	theme = game_theme
	_build_ui()
	_refresh()
	_show_text("问心院 · 初晴", dialogue.idle, "今日功课：修为达到 60。")

func _rect(key: String) -> Rect2:
	var value: Array = layout[key]
	return Rect2(value[0], value[1], value[2], value[3])

func _place(node: Control, rect: Rect2, parent: Node = null) -> void:
	if parent == null:
		parent = self
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size

func _style(color: Color, border: Color = GOLD, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(5)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box

func _panel(key: String) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _style(PAPER))
	_place(panel, _rect(key))
	return panel

func _label(text: String, rect: Rect2, font_size: int = 21, color: Color = INK, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(label, rect, parent)
	return label

func _button(text: String, rect: Rect2, callback: Callable, primary: bool = false, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", PAPER if primary else INK)
	button.add_theme_color_override("font_hover_color", PAPER if primary else JADE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("9b988c"))
	button.add_theme_stylebox_override("normal", _style(JADE if primary else Color("eae1d0")))
	button.add_theme_stylebox_override("hover", _style(Color("477e6e") if primary else Color("f8f2e7"), JADE, 2))
	button.add_theme_stylebox_override("pressed", _style(Color("245345")))
	button.add_theme_stylebox_override("disabled", _style(Color("e4dfd3"), Color("bcb5a5")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 3))
	button.pressed.connect(callback)
	_place(button, rect, parent)
	return button

func _art(path: String, rect: Rect2, parent: Node = null) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load(path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(image, rect, parent)
	return image

func _bar(rect: Rect2, maximum: int, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("dfd6c4"), Color("dfd6c4"), 0))
	bar.add_theme_stylebox_override("fill", _style(color, color, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(bar, rect)
	return bar

func _build_ui() -> void:
	_art("res://assets/art/paper.svg", Rect2(0, 0, 1440, 900))
	_panel("header")
	_label("蜀", Rect2(52, 32, 60, 70), 48, JADE)
	_label("问 心 院", Rect2(124, 35, 300, 54), 36)
	_label("山静日长，修行从一息开始。", Rect2(126, 87, 610, 25), 17, MUTED)
	_label("日常养成 · 第一课", Rect2(1080, 50, 290, 35), 24, JADE)
	_panel("profile")
	_label("弟 子", Rect2(50, 158, 160, 36), 18, MUTED)
	_label(dialogue.player_name, Rect2(49, 205, 164, 42), 29)
	_label("蜀山门下 · 初学", Rect2(50, 252, 160, 30), 16, MUTED)
	date_text = _label("", Rect2(50, 308, 170, 30), 20, JADE)
	energy_text = _label("", Rect2(50, 368, 164, 32), 21)
	energy_bar = _bar(Rect2(50, 410, 164, 10), 100, JADE)
	progress_text = _label("", Rect2(50, 450, 170, 32), 20)
	progress_bar = _bar(Rect2(50, 492, 164, 10), 60, GOLD)
	relation_text = _label("", Rect2(50, 533, 170, 32), 19)
	bonus_text = _label("", Rect2(50, 578, 170, 42), 17, JADE)
	bonus_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel("scene")
	_art("res://assets/art/courtyard.svg", Rect2(266, 150, 912, 486))
	_label("问心院", Rect2(285, 161, 170, 40), 25, INK)
	_label("竹影清风 · 师徒同修", Rect2(810, 164, 338, 32), 18, MUTED)
	player_art = _art("res://assets/art/qinglan.svg", _rect("player"))
	mentor_art = _art("res://assets/art/songfeng.svg", _rect("mentor"))
	_label(dialogue.player_name, Rect2(393, 600, 180, 32), 22, INK)
	_label(dialogue.mentor_name, Rect2(924, 600, 180, 32), 22, INK)
	mentor_hotspot = Button.new()
	mentor_hotspot.flat = true
	mentor_hotspot.tooltip_text = "向陆松风请教"
	mentor_hotspot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mentor_hotspot.pressed.connect(_ask)
	_place(mentor_hotspot, _rect("mentor"))
	_panel("actions")
	_label("今日安排", Rect2(1228, 162, 170, 36), 24)
	train_button = _button("修炼吐纳\n精力 -22 · 两时辰", Rect2(1224, 222, 172, 101), _train, true)
	mentor_button = _button("请教师傅\n精力 -8 · 一时辰", Rect2(1224, 346, 172, 101), _ask)
	rest_button = _button("廊下休息\n恢复精力 · 一时辰", Rect2(1224, 470, 172, 101), _rest)
	train_button.tooltip_text = "每次修为 +12；师傅点拨可额外增加 +6。"
	_panel("dialogue")
	speaker = _label("", Rect2(282, 680, 840, 38), 24, JADE)
	dialogue_text = _label("", Rect2(282, 727, 850, 74), 23)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_text = _label("", Rect2(282, 824, 702, 28), 18, MUTED)
	choices.append(_button("请教吐纳口诀", Rect2(282, 814, 302, 44), _choose.bind("breathing")))
	choices.append(_button("问问蜀山日常", Rect2(602, 814, 302, 44), _choose.bind("mountain")))
	choices.append(_button("改日再问", Rect2(922, 814, 232, 44), _cancel))
	continue_button = _button("继续", Rect2(1022, 814, 132, 44), _continue, true)
	_panel("notes")
	_label("试玩小记", Rect2(49, 684, 170, 32), 22)
	var help := _label("先修炼，再请教。\n留意点拨的加成。\n精力不足时休息。", Rect2(49, 731, 169, 101), 18, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("1 修炼  2 请教  3 休息", Rect2(49, 839, 180, 25), 13, MUTED)
	_panel("goal")
	goal_title = _label("今日功课", Rect2(1224, 684, 175, 34), 22)
	goal_note = _label("修为达到 60\n完成第一课", Rect2(1224, 729, 175, 65), 20, MUTED)
	_button("重新开始", Rect2(1224, 816, 172, 42), _reset)

func _refresh() -> void:
	date_text.text = state.time_text()
	energy_text.text = "精力  %d / 100" % state.energy
	progress_text.text = "修为  %d / 60" % state.cultivation
	relation_text.text = "师徒领悟  %d" % state.understanding
	bonus_text.text = "点拨在心\n下次修炼 +6" if state.lesson_bonus > 0 else "循序渐进，气息自稳。"
	energy_bar.value = state.energy
	progress_bar.value = state.cultivation
	var locked: bool = busy or state.dialogue_open or awaiting_continue
	train_button.disabled = locked
	mentor_button.disabled = locked
	rest_button.disabled = locked
	mentor_hotspot.disabled = locked
	for button in choices:
		button.visible = state.dialogue_open
	continue_button.visible = awaiting_continue
	result_text.visible = not state.dialogue_open
	goal_title.text = "初课已成" if state.complete() else "今日功课"
	goal_title.add_theme_color_override("font_color", JADE if state.complete() else INK)
	goal_note.text = "修为达到目标\n可继续试练" if state.complete() else "修为达到 60\n完成第一课"

func _show_text(title: String, text: String, result: String = "") -> void:
	speaker.text = title
	dialogue_text.text = text
	result_text.text = result

func _train() -> void:
	if busy or awaiting_continue or state.dialogue_open:
		return
	var result: Dictionary = state.train()
	if not result.ok:
		_show_text("先歇一歇", result.reason)
		return
	busy = true
	_show_text("顾青岚 · 修炼吐纳", dialogue.training, "修为 +%d · 精力 -22 · 时间 +两时辰" % result.gain)
	_refresh()
	var original := player_art.position
	var motion := create_tween()
	motion.tween_property(player_art, "position:y", original.y - 8, 0.22)
	motion.tween_property(player_art, "position:y", original.y, 0.25)
	await motion.finished
	busy = false
	if state.complete() and not completion_announced:
		completion_announced = true
		_show_text("陆松风 · 第一课已成", dialogue.complete, "你已完成本轮功课。")
	_refresh()

func _rest() -> void:
	if busy or awaiting_continue or state.dialogue_open:
		return
	var result: Dictionary = state.rest()
	_show_text("顾青岚 · 廊下休息", dialogue.rest, "精力 +%d · 时间 +一时辰" % result.gain)
	_refresh()

func _ask() -> void:
	if busy or awaiting_continue:
		return
	var result: Dictionary = state.begin_dialogue()
	if not result.ok:
		_show_text("先歇一歇", result.reason)
		return
	_show_text("陆松风 · 师傅", dialogue.opening)
	_refresh()

func _choose(topic: String) -> void:
	var result: Dictionary = state.choose(topic)
	if not result.ok:
		return
	awaiting_continue = true
	_show_text("陆松风 · 师傅", dialogue[topic], "领悟 +1 · 精力 -8 · 下一次修炼 +6" if topic == "breathing" else "领悟 +1 · 精力 -8 · 时间 +一时辰")
	_refresh()

func _cancel() -> void:
	state.cancel_dialogue()
	_show_text("问心院 · 初晴", "你向师傅行了一礼，准备先练一遍。", "未消耗精力与时间。")
	_refresh()

func _continue() -> void:
	awaiting_continue = false
	_show_text("问心院 · 初晴", "将师傅的话记在心里，再试试今天的修炼。", "点拨的加成会在下一次修炼中生效。" if state.lesson_bonus else "继续安排今日的功课。")
	_refresh()

func _reset() -> void:
	if busy:
		return
	state.reset()
	awaiting_continue = false
	completion_announced = false
	_show_text("问心院 · 初晴", dialogue.idle, "今日功课：修为达到 60。")
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _train()
		KEY_2: _ask()
		KEY_3: _rest()
		KEY_ESCAPE:
			if state.dialogue_open:
				_cancel()
