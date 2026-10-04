extends Control

const State = preload("res://scripts/demo_state.gd")
const Weather = preload("res://scripts/weather.gd")
const INK := Color("354137")
const JADE := Color("32695c")
const GOLD := Color("ad8959")
const PAPER := Color("f4eddf")
const MUTED := Color("6d6658")

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
var weather: Node
var weather_label: Label
var weather_button: Button
var busy := false
var awaiting_continue := false
var completion_announced := false

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/layout.json"))
	dialogue = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dialogue.json"))
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/characters.json"))
	for character: Dictionary in roster.characters:
		if character.id == dialogue.player_id:
			dialogue["player_name"] = character.name
		if character.id == dialogue.mentor_id:
			dialogue["mentor_name"] = character.name
	var game_theme := Theme.new()
	game_theme.default_font = load("res://assets/fonts/ShuDemoSerif.ttf")
	game_theme.default_font_size = 21
	theme = game_theme
	_build_ui()
	_refresh()
	_show_text("听雨廊 · 师徒同修", dialogue.idle, "今日功课：修为达到 60。")

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
	button.add_theme_font_size_override("font_size", 17 if rect.size.y < 35 else 21)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", JADE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("9b988c"))
	button.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.02), GOLD, 0))
	button.add_theme_stylebox_override("hover", _style(Color(0.85, 0.73, 0.50, 0.26), GOLD, 2))
	button.add_theme_stylebox_override("pressed", _style(Color("245345")))
	button.add_theme_stylebox_override("disabled", _style(Color(0.35, 0.38, 0.35, 0.18), GOLD, 0))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 3))
	button.pressed.connect(callback)
	_place(button, rect, parent)
	var backing := _paper(Rect2(Vector2.ZERO, rect.size), button, false, true)
	backing.show_behind_parent = true
	backing.modulate = Color("efce8f") if primary else Color.WHITE
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

func _paper(rect: Rect2, parent: Node = null, frame_only: bool = false, small: bool = false) -> NinePatchRect:
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/art/v2/paper-frame-v2.png")
	panel.patch_margin_left = 100
	panel.patch_margin_top = 100
	panel.patch_margin_right = 100
	panel.patch_margin_bottom = 100
	panel.draw_center = not frame_only
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var factor := 0.07 if small else 0.24
	_place(panel, Rect2(rect.position, rect.size / factor), parent)
	panel.scale = Vector2(factor, factor)
	return panel

func _build_ui() -> void:
	var ground := ColorRect.new()
	ground.color = Color("282b27")
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(ground, Rect2(0, 0, 1440, 900))
	_paper(_rect("header"))
	_label("蜀山行记", Rect2(32, 40, 174, 51), 36, INK)
	_label("问道长生", Rect2(70, 98, 110, 27), 18, MUTED)
	_art("res://assets/art/v2/jiang-yanqiu-v2.png", Rect2(215, 23, 90, 116))
	_label(dialogue.player_name, Rect2(326, 31, 182, 40), 29)
	_label("初入蜀山 · 听雨静心", Rect2(326, 80, 204, 28), 18, MUTED)
	date_text = _label("", Rect2(563, 30, 314, 34), 24, INK)
	energy_text = _label("", Rect2(563, 74, 312, 28), 22, INK)
	energy_bar = _bar(Rect2(564, 115, 300, 10), 100, Color("548d9a"))
	goal_title = _label("今日功课", Rect2(934, 31, 205, 29), 19, MUTED)
	progress_text = _label("", Rect2(934, 69, 205, 34), 25, INK)
	progress_bar = _bar(Rect2(935, 115, 183, 10), 60, Color("a28251"))
	relation_text = _label("", Rect2(1162, 30, 231, 31), 20, INK)
	bonus_text = _label("", Rect2(1162, 68, 231, 27), 17, JADE)
	_button("重新开始", Rect2(1230, 101, 164, 32), _reset)
	var scene_root := Control.new()
	# Keep background, weather, and foreground independently ordered.
	scene_root.clip_contents = true
	scene_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(scene_root, _rect("scene"))
	var background_root := Control.new()
	background_root.clip_contents = true
	background_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(background_root, Rect2(0, 0, 1416, 526), scene_root)
	var backdrop := _art("res://assets/art/weather3/tingyu-clean-v3.png", Rect2(0, 0, 1416, 526), background_root)
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	weather = Weather.new()
	scene_root.add_child(weather)
	weather.setup(scene_root, backdrop)
	var foreground_root := Control.new()
	foreground_root.clip_contents = true
	foreground_root.z_index = 2
	foreground_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(foreground_root, Rect2(0, 0, 1416, 526), scene_root)
	_paper(Rect2(55, 30, 208, 54), foreground_root, false, true)
	_label("听 雨 廊", Rect2(75, 40, 168, 35), 29, INK, foreground_root)
	_label("云\n山\n有\n路", Rect2(99, 140, 40, 220), 32, INK, foreground_root)
	_label("修\n心\n为\n先", Rect2(55, 172, 40, 220), 30, INK, foreground_root)
	player_art = _art("res://assets/art/v2/jiang-yanqiu-v2.png", _rect("player"), foreground_root)
	mentor_art = _art("res://assets/art/v2/ye-zhixian-v2.png", _rect("mentor"), foreground_root)
	weather.add_lit_art(player_art)
	weather.add_lit_art(mentor_art)
	mentor_hotspot = Button.new()
	mentor_hotspot.flat = true
	mentor_hotspot.tooltip_text = "向%s请教" % dialogue.mentor_name
	mentor_hotspot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mentor_hotspot.pressed.connect(_ask)
	_place(mentor_hotspot, _rect("mentor"), foreground_root)
	var desk := _art("res://assets/art/v2/desk-v2.png", _rect("desk"), foreground_root)
	desk.stretch_mode = TextureRect.STRETCH_SCALE
	weather.add_lit_art(desk)
	_paper(Rect2(347, 477, 176, 37), foreground_root, false, true)
	_label(dialogue.player_name, Rect2(358, 476, 154, 32), 19, INK, foreground_root).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paper(Rect2(913, 477, 176, 37), foreground_root, false, true)
	_label(dialogue.mentor_name, Rect2(924, 476, 154, 32), 19, INK, foreground_root).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scene_frame := _paper(_rect("scene"), null, true)
	scene_frame.z_index = 3
	var weather_paper := _paper(Rect2(886, 182, 204, 32), null, false, true)
	weather_paper.z_index = 3
	weather_label = _label("", Rect2(886, 182, 204, 32), 17, INK)
	weather_label.z_index = 3
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next_weather := _button("切换天气", Rect2(1103, 182, 136, 32), _next_weather)
	next_weather.z_index = 3
	next_weather.tooltip_text = "薄云、微风、小雨、雨歇依次预览；快捷键 5。"
	weather_button = _button("静态对比", Rect2(1252, 182, 142, 32), _toggle_weather)
	weather_button.z_index = 3
	weather_button.tooltip_text = "关闭／开启环境动态，养成状态保持；快捷键 4。"
	weather.changed.connect(_weather_ui)
	_weather_ui()
	_paper(_rect("dialogue"))
	speaker = _label("", Rect2(45, 709, 632, 34), 24, JADE)
	_label("1 修炼 · 2 请教 · 3 休息", Rect2(738, 712, 283, 27), 17, MUTED)
	dialogue_text = _label("", Rect2(45, 754, 969, 73), 24)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_text = _label("", Rect2(45, 830, 788, 32), 17, MUTED)
	choices.append(_button("请教吐纳口诀", Rect2(45, 831, 293, 43), _choose.bind("breathing")))
	choices.append(_button("问问蜀山日常", Rect2(353, 831, 293, 43), _choose.bind("mountain")))
	choices.append(_button("改日再问", Rect2(661, 831, 208, 43), _cancel))
	continue_button = _button("继续", Rect2(859, 831, 164, 43), _continue, true)
	_paper(_rect("actions"))
	train_button = _button("修炼吐纳   精力 -22", Rect2(1086, 710, 314, 45), _train, true)
	mentor_button = _button("请教%s   精力 -8" % dialogue.mentor_name, Rect2(1086, 769, 314, 45), _ask)
	rest_button = _button("廊下休息   恢复精力", Rect2(1086, 828, 314, 45), _rest)
	train_button.tooltip_text = "修为 +12 · 两时辰；师傅点拨可额外增加 +6。"
	mentor_button.tooltip_text = "点击师傅也能请教。选择话题后推进一时辰。"
	rest_button.tooltip_text = "精力最多恢复 34 · 一时辰。"

func _weather_ui() -> void:
	weather_label.text = weather.phase
	weather_button.text = "静态对比" if weather.enabled else "开启动态"

func _toggle_weather() -> void:
	weather.toggle()

func _next_weather() -> void:
	weather.next_phase()

func _refresh() -> void:
	date_text.text = state.time_text()
	energy_text.text = "精力  %d / 100" % state.energy
	progress_text.text = "修为  %d / 60" % state.cultivation
	relation_text.text = "师徒领悟  %d" % state.understanding
	bonus_text.text = "点拨在心 · 下次修炼 +6" if state.lesson_bonus > 0 else "循序渐进，气息自稳。"
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
	_show_text("%s · 修炼吐纳" % dialogue.player_name, dialogue.training, "修为 +%d · 精力 -22 · 时间 +两时辰" % result.gain)
	_refresh()
	var original := player_art.position
	var motion := create_tween()
	motion.tween_property(player_art, "position:y", original.y - 8, 0.22)
	motion.tween_property(player_art, "position:y", original.y, 0.25)
	await motion.finished
	busy = false
	if state.complete() and not completion_announced:
		completion_announced = true
		_show_text("%s · 第一课已成" % dialogue.mentor_name, dialogue.complete, "你已完成本轮功课。")
	_refresh()

func _rest() -> void:
	if busy or awaiting_continue or state.dialogue_open:
		return
	var result: Dictionary = state.rest()
	_show_text("%s · 廊下休息" % dialogue.player_name, dialogue.rest, "精力 +%d · 时间 +一时辰" % result.gain)
	_refresh()

func _ask() -> void:
	if busy or awaiting_continue:
		return
	var result: Dictionary = state.begin_dialogue()
	if not result.ok:
		_show_text("先歇一歇", result.reason)
		return
	_show_text("%s · 师傅" % dialogue.mentor_name, dialogue.opening)
	_refresh()

func _choose(topic: String) -> void:
	var result: Dictionary = state.choose(topic)
	if not result.ok:
		return
	awaiting_continue = true
	_show_text("%s · 师傅" % dialogue.mentor_name, dialogue[topic], "领悟 +1 · 精力 -8 · 下一次修炼 +6" if topic == "breathing" else "领悟 +1 · 精力 -8 · 时间 +一时辰")
	_refresh()

func _cancel() -> void:
	state.cancel_dialogue()
	_show_text("听雨廊 · 师徒同修", "你向师傅行了一礼，准备先练一遍。", "未消耗精力与时间。")
	_refresh()

func _continue() -> void:
	awaiting_continue = false
	_show_text("听雨廊 · 师徒同修", "将师傅的话记在心里，再试试今天的修炼。", "点拨的加成会在下一次修炼中生效。" if state.lesson_bonus else "继续安排今日的功课。")
	_refresh()

func _reset() -> void:
	if busy:
		return
	state.reset()
	awaiting_continue = false
	completion_announced = false
	_show_text("听雨廊 · 师徒同修", dialogue.idle, "今日功课：修为达到 60。")
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _train()
		KEY_2: _ask()
		KEY_3: _rest()
		KEY_4: _toggle_weather()
		KEY_5: _next_weather()
		KEY_ESCAPE:
			if state.dialogue_open:
				_cancel()
