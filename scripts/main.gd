extends Control

const State = preload("res://scripts/demo_state.gd")
const Weather = preload("res://scripts/weather.gd")
const SceneObject = preload("res://scripts/interactive_scene_object.gd")
const ObjectPopover = preload("res://scripts/scene_object_popover.gd")
const TeaMemory = preload("res://scripts/tea_memory_scene.gd")
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
var failure_notice := false
var cultivation_scene: Control
var tea_scene: Control
var sword_card: Control
var tea_entry: Button
var tea_accept: Button
var tea_cancel: Button
var tea_return: Button
var tea_backdrop: TextureRect
var tea_title: Label
var tea_paths: Dictionary = {}
var tea_status: Label
var shortcut_label: Label
var tea_hotspots: Dictionary = {}
var selected_object_id := ""
var object_popover: Control
var tea_memory: Control
var tea_journal: Control
var tea_journal_text: Label
var tea_journal_entries: Array[String] = []
var tea_rest: Button
var dialogue_panel: Control
var actions_panel: Control
var cultivation_frame: Control
var tea_data: Dictionary
var tea_full: Dictionary
var tea_fill_views: Array[Polygon2D] = []
var tea_layout: Dictionary
var tea_session := 0
var tea_pour_waiting := false
var tea_recollection_waiting := false
var tea_ending_waiting := false
var tea_pacing: Dictionary
var _tea_pacing_generation := 0
var next_weather: Button
var weather_paper: Control

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
	tea_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea.json"))
	tea_full = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea-full-source.json"))
	tea_layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea-layout.json"))
	tea_pacing = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea-pacing.json"))
	_build_ui()
	_build_tea_ui()
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
	if callback.is_valid():
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
	cultivation_scene = scene_root
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
	cultivation_frame = _paper(_rect("scene"), null, true)
	cultivation_frame.z_index = 3
	weather_paper = _paper(Rect2(886, 182, 204, 32), null, false, true)
	weather_paper.z_index = 3
	weather_label = _label("", Rect2(886, 182, 204, 32), 17, INK)
	weather_label.z_index = 3
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_weather = _button("切换天气", Rect2(1103, 182, 136, 32), _next_weather)
	next_weather.z_index = 3
	next_weather.tooltip_text = "薄云、微风、小雨、雨歇依次预览；快捷键 5。"
	weather_button = _button("静态对比", Rect2(1252, 182, 142, 32), _toggle_weather)
	weather_button.z_index = 3
	weather_button.tooltip_text = "关闭／开启环境动态，养成状态保持；快捷键 4。"
	weather.changed.connect(_weather_ui)
	_weather_ui()
	dialogue_panel = _paper(_rect("dialogue"))
	speaker = _label("", Rect2(45, 709, 632, 34), 24, JADE)
	shortcut_label = _label("1 修炼 · 2 请教 · 3 休息", Rect2(738, 712, 283, 27), 17, MUTED)
	dialogue_text = _label("", Rect2(45, 754, 969, 73), 24)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_text = _label("", Rect2(45, 830, 788, 32), 17, MUTED)
	choices.append(_button("请教吐纳口诀", Rect2(45, 831, 293, 43), _choose.bind("breathing")))
	choices.append(_button("问问蜀山日常", Rect2(353, 831, 293, 43), _choose.bind("mountain")))
	choices.append(_button("改日再问", Rect2(661, 831, 208, 43), _cancel))
	continue_button = _button("继续", Rect2(859, 831, 164, 43), _continue, true)
	actions_panel = _paper(_rect("actions"))
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
	var locked: bool = busy or state.dialogue_open or awaiting_continue or state.tea_active
	train_button.disabled = locked
	mentor_button.disabled = locked
	rest_button.disabled = locked
	mentor_hotspot.disabled = locked
	for button in choices:
		button.visible = state.dialogue_open
	continue_button.visible = awaiting_continue
	result_text.visible = not state.dialogue_open
	_refresh_tea()
	goal_title.text = "初课已成" if state.complete() else "今日功课"
	goal_title.add_theme_color_override("font_color", JADE if state.complete() else INK)

func _show_text(title: String, text: String, result: String = "") -> void:
	speaker.text = title
	dialogue_text.text = text
	result_text.text = result

func _train() -> void:
	if busy or awaiting_continue or state.dialogue_open or state.tea_active:
		return
	var result: Dictionary = state.train()
	if not result.ok:
		_show_failure(result.reason)
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
	if busy or awaiting_continue or state.dialogue_open or state.tea_active:
		return
	var result: Dictionary = state.rest()
	_show_text("%s · 廊下休息" % dialogue.player_name, dialogue.rest, "精力 +%d · 时间 +一时辰" % result.gain)
	_refresh()

func _ask() -> void:
	if busy or awaiting_continue or state.dialogue_open or state.tea_active:
		return
	var result: Dictionary = state.begin_dialogue()
	if not result.ok:
		_show_failure(result.reason)
		return
	_show_text("%s · 师傅" % dialogue.mentor_name, dialogue.opening)
	_refresh()

func _choose(topic: String) -> void:
	if busy or awaiting_continue or state.tea_active or not state.dialogue_open:
		return
	var result: Dictionary = state.choose(topic)
	if not result.ok:
		return
	awaiting_continue = true
	_show_text("%s · 师傅" % dialogue.mentor_name, dialogue[topic], "领悟 +1 · 精力 -8 · 下一次修炼 +6" if topic == "breathing" else "领悟 +1 · 精力 -8 · 时间 +一时辰")
	_refresh()

func _cancel() -> void:
	if not state.dialogue_open or state.tea_active:
		return
	state.cancel_dialogue()
	_show_text("听雨廊 · 师徒同修", "你向师傅行了一礼，准备先练一遍。", "未消耗精力与时间。")
	_refresh()

func _continue() -> void:
	if not awaiting_continue or state.tea_active:
		return
	awaiting_continue = false
	if failure_notice:
		failure_notice = false
		_show_text("听雨廊 · 师徒同修", dialogue.idle, "继续安排今日的功课。")
		_refresh()
		return
	_show_text("听雨廊 · 师徒同修", "将师傅的话记在心里，再试试今天的修炼。", "点拨的加成会在下一次修炼中生效。" if state.lesson_bonus else "继续安排今日的功课。")
	_refresh()

func _reset() -> void:
	if busy:
		return
	state.reset()
	_tea_pacing_generation += 1
	tea_recollection_waiting = false
	tea_ending_waiting = false
	tea_pour_waiting = false
	awaiting_continue = false
	completion_announced = false
	failure_notice = false
	_close_object_popover()
	tea_journal_entries.clear()
	_show_text("听雨廊 · 师徒同修", dialogue.idle, "今日功课：修为达到 60。")
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if tea_memory != null and tea_memory.visible and event.keycode != KEY_ESCAPE:
		return
	match event.keycode:
		KEY_1: _train()
		KEY_2: _ask()
		KEY_3:
			if state.tea_active and state.tea_accepted: _tea_rest()
			else: _rest()
		KEY_4: _toggle_weather()
		KEY_5: _next_weather()
		KEY_6: _open_tea()
		KEY_ESCAPE:
			if state.tea_active:
				if tea_memory != null and tea_memory.visible: _close_object_popover()
				elif not selected_object_id.is_empty(): _close_object_popover()
				else: _tea_cancel()
			elif state.dialogue_open:
				_cancel()
			elif awaiting_continue:
				_continue()


func _tea_rect(key: String) -> Rect2:
	var r: Array = tea_layout[key]
	return Rect2(r[0], r[1], r[2], r[3])

func _build_tea_ui() -> void:
	tea_entry = _button("归剑问天 · 旧剑委托", Rect2(308, 187, 326, 40), _open_tea)
	tea_entry.z_index = 4
	tea_entry.tooltip_text = "接受后进入支线，整条完成前留在其中；快捷键 6。查看不消耗精力或时辰。"
	tea_scene = Control.new()
	tea_scene.clip_contents = true
	tea_scene.mouse_filter = Control.MOUSE_FILTER_STOP
	tea_scene.z_index = 2
	_place(tea_scene, _tea_rect("scene"))
	tea_backdrop = _art("res://assets/art/tea/tea-terrace-v1.png", Rect2(Vector2.ZERO, tea_scene.size), tea_scene)
	tea_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_paper(_tea_rect("title_panel"), tea_scene, false, true)
	tea_title = _label("归剑问天 · 旧剑坪", _tea_rect("title"), 27, INK, tea_scene)
	tea_status = _label("", _tea_rect("subtitle"), 18, MUTED, tea_scene)
	tea_return = _button("返回听雨廊", Rect2(1243,24,146,32), _tea_cancel, false, tea_scene)
	tea_return.tooltip_text = "整条支线完成后返回养成主界面。"
	var pair: Texture2D = load("res://assets/art/tea/tea-cups-v1.png")
	for object_id: String in state.TEA_OBJECT_IDS:
		var atlas := AtlasTexture.new()
		atlas.atlas = pair
		var r: Array = tea_layout[object_id + ".atlas"]
		atlas.region = Rect2(r[0], r[1], r[2], r[3])
		var object_view := SceneObject.new()
		object_view.configure(object_id, tea_data.objects[object_id].label, atlas)
		object_view.object_selected.connect(_tea_inspect)
		_place(object_view, _tea_rect(object_id), tea_scene)
		tea_hotspots[object_id] = object_view
	for object_id: String in tea_data.courtyard.objects:
		var object_view := SceneObject.new()
		object_view.configure(object_id, tea_data.courtyard.objects[object_id].label, null)
		object_view.object_selected.connect(_tea_inspect)
		_place(object_view, _tea_rect(object_id), tea_scene)
		tea_hotspots[object_id] = object_view
	for object_id: String in tea_full.objects:
		if tea_hotspots.has(object_id): continue
		var object_view := SceneObject.new()
		object_view.configure(object_id, tea_full.objects[object_id].label, null)
		object_view.object_selected.connect(_tea_inspect)
		_place(object_view, _tea_rect(object_id), tea_scene)
		tea_hotspots[object_id] = object_view
	for object_id: String in state.TEA_OBJECT_IDS:
		var fill := Polygon2D.new()
		var tea_surface := PackedVector2Array()
		for point in 32:
			var angle := TAU * point / 32.0
			tea_surface.append(Vector2(cos(angle)*65.0,sin(angle)*29.0))
		fill.polygon = tea_surface
		fill.color = Color(0.43,0.32,0.12,0.86)
		fill.position = _tea_rect(object_id).position + Vector2(83,53)
		fill.z_index = 2
		tea_scene.add_child(fill)
		tea_fill_views.append(fill)
	for path_id: String in ["tea.path_old_courtyard", "tea.path_sword_terrace", "tea.story_next"]:
		var path_view := SceneObject.new()
		path_view.configure(path_id, "", null)
		path_view.persistent_hint = true
		path_view.hint.text = "前往旧院 →" if path_id == "tea.path_old_courtyard" else "← 重访剑坪"
		path_view.object_selected.connect(_tea_path)
		_place(path_view, _tea_rect(path_id), tea_scene)
		path_view.set_state(false,false)
		path_view.hint.position = Vector2(8,25)
		path_view.hint.size = Vector2(path_view.size.x-16,28)
		path_view.hint.add_theme_constant_override("shadow_outline_size",0)
		path_view.hint.add_theme_stylebox_override("normal",_style(Color(0.96,0.93,0.87,0.88),GOLD))
		tea_paths[path_id] = path_view
	object_popover = ObjectPopover.new()
	object_popover.z_index = 5
	tea_scene.add_child(object_popover)
	object_popover.action_requested.connect(_tea_action)
	object_popover.hide()
	tea_memory = TeaMemory.new()
	tea_memory.z_index = 20
	_place(tea_memory, Rect2(0, 0, 1440, 900))
	tea_memory.action_requested.connect(_tea_action)
	tea_memory.close_requested.connect(_tea_memory_close)
	tea_memory.close_view()
	tea_journal = Control.new()
	_place(tea_journal, _tea_rect("journal"))
	_paper(Rect2(Vector2.ZERO,tea_journal.size),tea_journal,false,true)
	_label("札记",Rect2(24,19,66,38),26,INK,tea_journal)
	tea_journal_text = _label("",Rect2(111,11,963,60),20,INK,tea_journal)
	tea_journal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tea_rest = _button("廊下歇息",_tea_rect("rest"),_tea_rest)
	tea_rest.tooltip_text = "恢复精力，推进一时辰；查看进度保留。快捷键 3。"
	sword_card = Control.new()
	sword_card.z_index = 2
	sword_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(sword_card, _rect("scene"))
	_paper(Rect2(508,156,466,220),sword_card)
	_label("一柄旧剑",Rect2(540,174,388,36),25,INK,sword_card)
	_art("res://assets/art/tea/tea-sword-v1.png",Rect2(540,223,388,126),sword_card)
	tea_accept = _button("接受委托 · 去剑坪",Rect2(45,831,293,43),_tea_accept)
	tea_cancel = _button("暂且返回",Rect2(661,831,208,43),_tea_cancel)

func _refresh_tea() -> void:
	var active: bool = state.tea_active
	var terrace: bool = active and state.tea_accepted
	var memory_active: bool = _uses_memory_view()
	if not memory_active and tea_memory != null:
		tea_memory.close_view()
	shortcut_label.text = ("Esc 返回" if state.can_return_from_tea() else "Esc 收起物品 · 3 歇息") if active else "1 修炼 · 2 请教 · 3 休息"
	cultivation_scene.visible = not terrace
	cultivation_frame.visible = not terrace
	tea_scene.visible = terrace
	sword_card.visible = active and not state.tea_accepted
	tea_entry.visible = not active
	tea_entry.disabled = busy or awaiting_continue or state.dialogue_open
	tea_entry.text = "两盏茶 · 重访剑坪" if state.tea_quest_complete else "归剑问天 · 重访剑坪" if state.tea_accepted else "归剑问天 · 旧剑委托"
	tea_accept.visible = active and not state.tea_accepted
	tea_cancel.visible = active and not state.tea_accepted
	tea_return.visible = terrace and state.can_return_from_tea() and not tea_ending_waiting
	for chrome in [dialogue_panel,actions_panel,speaker,dialogue_text,result_text,shortcut_label,train_button,mentor_button,rest_button]:
		chrome.visible = not terrace
	tea_journal.visible = terrace
	tea_rest.visible = terrace
	var courtyard: bool = state.tea_scene_id == state.TEA_COURTYARD_ID
	var stage: Dictionary = state.story_stage()
	var later: bool = state.tea_story_stage > 0
	tea_title.text = "两盏茶" if state.tea_quest_complete else "归剑问天 · " + (str(stage.title) if courtyard or state.tea_story_stage == 7 else "旧剑坪")
	tea_backdrop.texture = load("res://assets/art/tea-c/tea-courtyard-reference-v1.png" if courtyard else "res://assets/art/tea/tea-terrace-v1.png")
	tea_backdrop.modulate = Color.WHITE
	tea_status.text = "" if state.tea_ending_step > 0 or tea_recollection_waiting else _tea_investigation_prompt(courtyard, stage)
	tea_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tea_rest.text = "院中歇息" if courtyard else "廊下歇息"
	tea_journal.visible = terrace and state.tea_ending_step == 0 and not memory_active
	tea_rest.visible = terrace and state.tea_ending_step == 0 and not memory_active
	tea_paths["tea.path_old_courtyard"].visible = terrace and not memory_active and not courtyard and state.tea_stage_complete and state.tea_story_stage < 7
	tea_paths["tea.path_sword_terrace"].visible = terrace and not memory_active and courtyard
	var next_view: Control = tea_paths["tea.story_next"]
	next_view.visible = terrace and not memory_active and not tea_recollection_waiting and courtyard and state.story_stage_complete() and state.tea_story_stage < 7 and selected_object_id.is_empty()
	var next_labels := ["翻看药匣诊录 →", "打开柜中旧物 →", "翻到旧记中的一日 →", "翻阅几册旧记 →", "翻到最后一日 →", "查看后事公文 →", "归剑 · 回到剑坪 →"]
	if state.tea_story_stage < 7:
		next_view.hint.text = next_labels[state.tea_story_stage]
		var next_anchors := [Vector2(96,397),Vector2(1172,294),Vector2(1126,403),Vector2(1126,403),Vector2(1126,403),Vector2(1126,403),Vector2(380,326)]
		next_view.position = next_anchors[state.tea_story_stage]
	for object_id: String in tea_hotspots:
		var in_courtyard: bool = tea_data.courtyard.objects.has(object_id)
		var seen: Dictionary = state.tea_c_seen if in_courtyard else state.tea_seen
		var shown: bool = terrace and courtyard == in_courtyard and (in_courtyard or object_id in state.TEA_OBJECT_IDS)
		if later and courtyard:
			shown = terrace and object_id in stage.items
			seen = state.tea_story_seen
		elif state.tea_story_stage == 7:
			shown = terrace and object_id in state.TEA_OBJECT_IDS
			seen = state.tea_story_seen
		tea_hotspots[object_id].visible = shown and not memory_active
		tea_hotspots[object_id].set_state(object_id == selected_object_id, seen.has(object_id))
	for i in tea_fill_views.size(): tea_fill_views[i].visible = terrace and not memory_active and state.tea_story_stage == 7 and state.tea_ending_step > i
	if terrace and not selected_object_id.is_empty():
		_present_object_popover()
	weather_label.visible = not terrace
	weather_paper.visible = not terrace
	weather_button.visible = not terrace
	next_weather.visible = not terrace

func _open_tea() -> void:
	if busy or awaiting_continue or state.dialogue_open or state.tea_active:
		return
	var result: Dictionary = state.begin_tea()
	if not result.ok: return
	tea_session = int(result.session)
	_close_object_popover()
	if state.tea_accepted:
		_tea_overview()
	else:
		_show_text("归剑问天 · 山下老人",tea_data.commission,"接受后进入支线，完成前留在其中；也可暂且返回。")
	_refresh()

func _tea_accept() -> void:
	var result: Dictionary = state.accept_tea(tea_session)
	if not result.ok: return
	_tea_overview()
	_refresh()

func _tea_overview() -> void:
	_append_tea_narrative(tea_data.rumor)

func _tea_path(path_id: String) -> void:
	if tea_memory != null and tea_memory.visible: return
	if path_id == "tea.story_next":
		if not tea_paths[path_id].visible: return
		_advance_tea_story()
		return
	if not tea_paths.has(path_id) or not tea_paths[path_id].visible: return
	var target: String = state.TEA_COURTYARD_ID if path_id == "tea.path_old_courtyard" else state.TEA_TERRACE_ID
	var result: Dictionary = state.switch_tea_scene(target, tea_session)
	if not result.ok: return
	tea_session = int(result.session)
	_tea_pacing_generation += 1
	tea_recollection_waiting = false
	_close_object_popover()
	var text: String = tea_data.courtyard.intro if target == state.TEA_COURTYARD_ID else "剑坪仍在，两只旧杯还放在原处。"
	if state.tea_c_complete and state.tea_story_stage == 0: text = tea_data.courtyard.impression + "  " + tea_data.courtyard.stage_complete_notice
	_append_tea_narrative(text)
	_refresh()

func _tea_inspect(object_id: String) -> void:
	if tea_memory != null and tea_memory.visible: return
	if state.tea_story_stage > 0 and (state.tea_scene_id == state.TEA_COURTYARD_ID or state.tea_story_stage == 7):
		_close_object_popover()
		var read: Dictionary = state.read_tea_story(object_id, tea_session)
		if read.ok:
			selected_object_id = object_id
			if state.tea_ending_step == 0 and not _uses_memory_view(): _append_tea_narrative(str(read.page.text))
		else: _append_tea_narrative(read.reason)
		_refresh()
		return
	var courtyard: bool = state.tea_scene_id == state.TEA_COURTYARD_ID
	var result: Dictionary = state.view_tea_c(object_id,tea_session) if courtyard else state.view_tea(object_id,tea_session)
	if not result.ok:
		_close_object_popover()
		_append_tea_narrative(result.reason)
		_refresh()
		return
	selected_object_id = object_id
	var objects: Dictionary = tea_data.courtyard.objects if courtyard else tea_data.objects
	_append_tea_narrative(objects[object_id].text)
	if result.new_completion:
		_append_tea_narrative(tea_data.courtyard.impression + "  " + tea_data.courtyard.stage_complete_notice if courtyard else objects[object_id].text + "  " + tea_data.impression + "  " + tea_data.stage_complete_notice)
	_refresh()

func _present_object_popover() -> void:
	if state.tea_story_stage > 0 and (state.tea_scene_id == state.TEA_COURTYARD_ID or state.tea_story_stage == 7):
		_present_story_popover()
		return
	var objects: Dictionary = tea_data.courtyard.objects if state.tea_scene_id == state.TEA_COURTYARD_ID else tea_data.objects
	var object_data: Dictionary = objects[selected_object_id].duplicate(true)
	object_data["id"] = selected_object_id
	var actions: Array = []
	for definition: Dictionary in object_data.get("actions",[]):
		var cost := int(state.rules[definition.cost_rule])
		var done: bool = bool(state.tea_action_done.get(selected_object_id, {}).get(str(definition.id), false))
		var action_label: String = definition.label
		if definition.has("character_id"):
			action_label = action_label.replace("{mentor}",dialogue.mentor_name)
		actions.append({"id":definition.id,"label":action_label,"cost":cost,"done":done,"enabled":not done and state.energy >= cost,"reason":"已完成，重访不会重复消耗。" if done else ("精力不足，可先廊下歇息。" if state.energy < cost else "")})
	object_popover.present(object_data,actions,_tea_rect(selected_object_id),tea_scene.size,tea_session)

func _tea_action(object_id: String, action_id: String, session: int) -> void:
	# A replaced/closed popover cannot spend resources through an old callback.
	if object_id != selected_object_id or session != tea_session: return
	var memory_active: bool = tea_memory != null and tea_memory.visible
	if memory_active and not action_id.begins_with("page:") and action_id != "memory_close": return
	if not object_popover.visible and not memory_active: return
	if action_id == "memory_close":
		if tea_memory == null or not tea_memory.visible: return
		if tea_memory.remaining_hold_seconds() > 0.0: return
		_tea_memory_close()
		return
	if action_id.begins_with("page:"):
		if memory_active and tea_memory.remaining_hold_seconds() > 0.0: return
		var result: Dictionary = state.turn_tea_story(object_id,session,int(action_id.get_slice(":",1)))
		if result.ok:
			if not _uses_memory_view(): _append_tea_narrative(str(result.page.text))
		else: _append_tea_narrative(result.reason)
		_refresh()
		return
	if action_id == "story_next":
		if tea_recollection_waiting: return
		_advance_tea_story()
		return
	if action_id.begins_with("fill:"):
		if tea_pour_waiting or tea_ending_waiting: return
		var result: Dictionary = state.fill_tea_cup(object_id,session,int(action_id.get_slice(":",1)))
		if result.ok:
			tea_pour_waiting = int(result.ending_step) == 1
			tea_ending_waiting = int(result.ending_step) == 2
			_close_object_popover()
		else: _append_tea_narrative(result.reason)
		_refresh()
		if result.ok:
			var ending_step: int = int(result.ending_step)
			var generation := _tea_pacing_generation
			var duration := float(tea_pacing.first_cup_pause_ms if ending_step == 1 else tea_pacing.filled_cups_hold_ms) / 1000.0
			await get_tree().create_timer(duration).timeout
			if generation == _tea_pacing_generation and state.tea_active and tea_session == session and state.tea_ending_step == ending_step:
				tea_pour_waiting = false
				tea_ending_waiting = false
				_refresh()
		return
	var result: Dictionary = state.execute_tea_action(object_id,action_id,session)
	if result.ok:
		_append_tea_narrative(tea_data.feedback[result.feedback_key] if tea_data.feedback.has(result.feedback_key) else tea_data[result.feedback_key])
	else:
		_append_tea_narrative(result.reason)
	_refresh()

func _tea_rest() -> void:
	if tea_memory != null and tea_memory.visible: return
	var result: Dictionary = state.rest_tea(tea_session)
	if not result.ok: return
	_close_object_popover()
	_append_tea_narrative(("在旧院坐了一会儿。" if state.tea_scene_id == state.TEA_COURTYARD_ID else dialogue.rest) + "  精力 +%d。" % result.gain)
	_refresh()

func _append_tea_narrative(text: String) -> void:
	tea_journal_entries.append(text)
	if tea_journal_entries.size() > 20: tea_journal_entries.pop_front()
	tea_journal_text.text = text.replace("\n"," ")
	tea_journal_text.tooltip_text = text

func _close_object_popover() -> void:
	state.close_tea_story()
	selected_object_id = ""
	if object_popover != null: object_popover.hide()
	if tea_memory != null: tea_memory.close_view()
	for object_id: String in tea_hotspots:
		tea_hotspots[object_id].set_state(false,state.tea_seen.has(object_id) or state.tea_c_seen.has(object_id))
	if tea_paths.has("tea.story_next"): _refresh_tea()

func _input(event: InputEvent) -> void:
	if tea_memory != null and tea_memory.visible: return
	if not state.tea_active or selected_object_id.is_empty(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		if object_popover.get_global_rect().has_point(point): return
		for object_view: Control in tea_hotspots.values() + tea_paths.values():
			if object_view.visible and object_view.get_global_rect().has_point(point): return
		_close_object_popover()

func _tea_cancel() -> void:
	if not state.tea_active or tea_ending_waiting: return
	var result: Dictionary = state.cancel_tea()
	if not result.ok:
		_append_tea_narrative(result.reason)
		return
	_tea_pacing_generation += 1
	tea_recollection_waiting = false
	_close_object_popover()
	_show_text("听雨廊 · 师徒同修",dialogue.idle,"所见已保留 · 可继续养成或重访剑坪。")
	_refresh()

func _show_failure(reason: String) -> void:
	awaiting_continue = true
	failure_notice = true
	_show_text("先歇一歇", reason, "关闭提示后继续安排功课。")
	_refresh()

func _advance_tea_story() -> void:
	if tea_recollection_waiting: return
	var result: Dictionary = state.advance_tea_story(tea_session)
	if not result.ok:
		_append_tea_narrative(result.reason)
		return
	tea_session = int(result.session)
	_close_object_popover()
	_append_tea_narrative(str(state.story_stage().intro))
	_refresh()

func _story_action(id: String, label: String) -> Dictionary:
	return {"id":id,"label":label,"cost":0,"show_cost":false,"done":false,"enabled":true,"reason":""}

func _present_story_popover() -> void:
	var source: Dictionary = tea_full.objects[selected_object_id]
	if _uses_memory_view():
		object_popover.hide()
		tea_memory.present(selected_object_id, source, state.tea_story_page, state.tea_story_token, tea_session)
		return
	tea_memory.close_view()
	var page: Dictionary = source.pages[state.tea_story_page]
	var data: Dictionary = {"id":selected_object_id,"label":str(page.speaker) + " · %d / %d" % [state.tea_story_page+1,source.pages.size()],"text":page.text,"popover_width":430,"description_height":190}
	var actions: Array = []
	if state.tea_story_stage == 7 and state.tea_ending_step > 0:
		data.label = source.label
		data.text = ""
		data.description_height = 0
		if state.tea_ending_step == 1 and selected_object_id == "tea.cup_second":
			var pour := _story_action("fill:%d" % state.tea_story_token,"添茶")
			pour.enabled = not tea_pour_waiting
			pour.reason = "静静等一会儿。" if tea_pour_waiting else ""
			actions.append(pour)
		object_popover.present(data,actions,_tea_rect(selected_object_id),tea_scene.size,tea_session)
		return
	if state.tea_story_page < source.pages.size()-1:
		var label := "翻到下一页"
		if state.story_stage().profile == "memory": label = "坐下 · 等一会儿" if state.tea_story_page == 9 else "继续读这段对话"
		actions.append(_story_action("page:%d" % state.tea_story_token,label))
	elif state.tea_story_stage < 7 and state.story_stage_complete():
		var labels := ["翻看药匣诊录", "打开柜中旧物", "翻到旧记中的一日", "翻阅几册旧记", "翻到最后一日", "查看后事公文", "归剑 · 回到剑坪"]
		actions.append(_story_action("story_next",labels[state.tea_story_stage]))
	elif state.tea_story_stage == 7 and state.story_stage_complete():
		if (state.tea_ending_step == 0 and selected_object_id == "tea.cup_first") or (state.tea_ending_step == 1 and selected_object_id == "tea.cup_second"):
			actions.append(_story_action("fill:%d" % state.tea_story_token,"添茶"))
	object_popover.present(data,actions,_tea_rect(selected_object_id),tea_scene.size,tea_session)

func _uses_memory_view() -> bool:
	if selected_object_id.is_empty() or state.tea_story_object != selected_object_id or state.tea_story_stage <= 0 or state.tea_scene_id != state.TEA_COURTYARD_ID:
		return false
	if selected_object_id in ["tea.memory", "tea.record_early", "tea.record_late", "tea.record_last", "tea.last_day", "tea.letter", "tea.notice_cups"]:
		return true
	if selected_object_id in ["tea.cabinet", "tea.medical_early", "tea.notice_death"]:
		return state.tea_story_page >= 1
	return selected_object_id == "tea.medical_habits" and state.tea_story_page == 0

func _tea_memory_close() -> void:
	if tea_memory == null or not tea_memory.visible or selected_object_id.is_empty():
		return
	_tea_pacing_generation += 1
	var generation := _tea_pacing_generation
	var session := tea_session
	tea_recollection_waiting = true
	_close_object_popover()
	_refresh()
	await get_tree().create_timer(float(tea_pacing.memory_return_ms) / 1000.0).timeout
	if generation == _tea_pacing_generation and state.tea_active and session == tea_session:
		tea_recollection_waiting = false
		_refresh()

func _tea_investigation_prompt(courtyard: bool, stage: Dictionary) -> String:
	if not courtyard and state.tea_story_stage > 0 and state.tea_story_stage < 7:
		return "沿石阶前往旧院。"
	if state.tea_story_stage == 0:
		if not courtyard:
			return "昔日高台之上，仍两只旧杯。   旧杯 %d / 2" % state.tea_seen.size()
		if state.tea_c_complete: return "账册已阅 · 药匣中尚有旧页"
		var item := "tea.ledger" if state.tea_c_seen.has("tea.household") else "tea.household"
		return str(tea_pacing.investigation_hints[item]) + " · 查看"
	if state.story_stage_complete():
		return "第一只旧杯 · 添茶" if state.tea_story_stage == 7 else "旧页已阅 · 继续调查"
	for item_variant in stage.get("items", []):
		var item := str(item_variant)
		if state.tea_story_seen.has(item): continue
		var available := true
		for required in tea_full.objects[item].get("requires", []):
			if not state.tea_story_seen.has(str(required)): available = false
		if available:
			return str(tea_pacing.investigation_hints.get(item, "旧页")) + " · 查看"
	return "依次翻阅留下的旧页。"
