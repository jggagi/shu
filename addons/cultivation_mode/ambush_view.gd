extends Control
## A view over the session-owned encounter. No persistent settlement lives here.

signal completed
signal return_requested
signal retry_requested

@export var review_tools_enabled: bool = true

const StageScript = preload("res://addons/cultivation_mode/ambush_stage.gd")
const StaffInspectorScript = preload("res://addons/cultivation_mode/ambush_staff_inspector.gd")
const CharacterInspectorScript = preload("res://addons/cultivation_mode/ambush_character_inspector.gd")
const WorkshopScript = preload("res://addons/cultivation_mode/martial_workshop_view.gd")
const MoveCatalog = preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const FONT_PATH := "res://assets/fonts/ShuAmbushSerif.ttf"
const INK := Color("#2e3d37")
const MUTED := Color("#77796c")
const PAPER := Color("#f0eadb")
const LIGHT := Color("#faf5e9")
const LINE := Color("#c7c4af")
const GREEN := Color("#426c5d")
const RED := Color("#a05440")
const GOLD := Color("#b18a48")

var _session: RefCounted
var _battle: RefCounted
var _context: Dictionary = {}
var _definition: Dictionary = {}
var _stage: Control
var _selected := "player"
var _action := "move"
var _hover: Array = []
var _busy := false
var _reported := false
var _controls: Dictionary = {}
var _round_label: Label
var _objective_label: Label
var _objective_bar: ProgressBar
var _objective_detail: Label
var _objective_panel: PanelContainer
var _objective_warning: Label
var _selected_label: Label
var _feedback: Label
var _plans_label: Label
var _plans_title: Label
var _barricade_label: Label
var _log_label: Label
var _hint: Label
var _end_button: Button
var _return_button: Button
var _retry_button: Button
var _restart_button: Button
var _camera_reset_button: Button
var _detail_button: Button
var _refined_details := true
var _inspect_button: Button
var _environment_button: Button
var _environment_static := false
var _lighting_button: Button
var _enhanced_lighting := true
var _combat_light_mode := 2
var _replaying := false
var _combat_light_button: Button
var _combat_replay_button: Button
var _preview_choice: OptionButton
var _preview_skill := "push"
var _sound_button: Button
var _sound_muted := false
var _settings_button: Button
var _settings_overlay: Control
var _settings_return_note: Label
var _finished_return_parent: Control
var _palm_button: Button
var _palm_style: OptionButton
var _palm_style_index := 0
var _staff_inspector: Control
var _staff_inspect_button: Button
var _character_inspector: Control
var _martial_workshop: Control
var _workshop_button: Button
var _battle_viewport_mode := SubViewport.UPDATE_ALWAYS
var _skills: Dictionary = {}
var _cards: Dictionary = {}
var _threats: Dictionary = {}
var _feedback_tone := "neutral"
var _hover_preview: Dictionary = {}


func setup(session: RefCounted, battle: RefCounted, context: Dictionary) -> void:
	_session = session
	_battle = battle
	_context = context.duplicate(true)
	_definition = (battle.get("definition") as Dictionary).duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_sync()
	_set_feedback("试试剑掌配合：先选沈听岚，绕到棍客左下侧出掌；江砚秋沿空出的路追击。" if review_tools_enabled else "")


func _build() -> void:
	var view_theme := Theme.new()
	view_theme.default_font = load(FONT_PATH) as Font
	view_theme.default_font_size = 16
	view_theme.set_color("font_color", "Label", INK)
	view_theme.set_color("font_color", "Button", INK)
	view_theme.set_color("font_hover_color", "Button", INK)
	view_theme.set_color("font_pressed_color", "Button", INK)
	view_theme.set_stylebox("normal", "Button", _style(LIGHT, LINE, 7, 8))
	view_theme.set_stylebox("hover", "Button", _style(Color("#e4ebdd"), GREEN, 7, 8))
	view_theme.set_stylebox("pressed", "Button", _style(Color("#d2e1d4"), GREEN, 7, 8))
	view_theme.set_stylebox("disabled", "Button", _style(Color("#e5e2d7"), Color("#d2d0c2"), 7, 8))
	view_theme.set_color("font_disabled_color", "Button", Color("#979b8d"))
	theme = view_theme
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	column.add_child(header)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	header.add_child(title_column)
	title_column.add_child(_label("蜀 · 山道遇袭", 26, INK))
	_round_label = _label("", 19, GREEN)
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_round_label)
	_environment_button = _button("景物：动态", "EnvironmentMotionButton", _toggle_environment)
	_environment_button.add_theme_font_size_override("font_size", 14)
	_environment_button.tooltip_text = "暂停或继续松梢与远处云气；思考与战斗照常进行。"
	header.add_child(_environment_button)
	_lighting_button = _button("光影：增强", "LightingModeButton", _toggle_lighting)
	_lighting_button.add_theme_font_size_override("font_size", 14)
	_lighting_button.tooltip_text = "对照古道原光影与增强光影。"
	header.add_child(_lighting_button)
	_inspect_button = _button("人物近看", "InspectCharactersButton", _open_characters)
	header.add_child(_inspect_button)
	_restart_button = _button("重开本战", "RestartButton", _request_retry)
	_restart_button.tooltip_text = "结束本场并重新挑战；本场按失败结算一时辰。"
	header.add_child(_restart_button)
	_return_button = _button("撤离", "ReturnButton", _request_return)
	_return_button.custom_minimum_size = Vector2(76, 36)
	header.add_child(_return_button)
	var experiment_row := HBoxContainer.new()
	experiment_row.add_theme_constant_override("separation", 9)
	column.add_child(experiment_row)
	experiment_row.add_child(_label("招式光影", 15, GREEN))
	_combat_light_button = _button("演出：光与投影", "CombatLightModeButton", _cycle_combat_light)
	_combat_light_button.add_theme_font_size_override("font_size", 15)
	_combat_light_button.tooltip_text = "依次对照原演出、招式光、招式光与真实投影；同一战局可反复试演。"
	experiment_row.add_child(_combat_light_button)
	_preview_choice = OptionButton.new()
	_preview_choice.name = "SkillPreviewChoice"
	_preview_choice.focus_mode = Control.FOCUS_NONE
	for label: String in ["回澜剑", "穿云刺", "回风扫"]:
		_preview_choice.add_item(label)
	_preview_choice.item_selected.connect(_select_preview_skill)
	_preview_choice.tooltip_text = "选择一招反复试演；不伤敌，也不扣行动。"
	_preview_choice.add_theme_font_size_override("font_size", 15)
	experiment_row.add_child(_preview_choice)
	_controls["SkillPreviewChoice"] = _preview_choice
	_combat_replay_button = _button("近看回澜", "CombatLightReplayButton", _replay_combat_light)
	_combat_replay_button.add_theme_font_size_override("font_size", 15)
	_combat_replay_button.tooltip_text = "拉近并停留在出剑瞬间比较光与影，不伤敌、不扣行动，也不推进时辰。"
	experiment_row.add_child(_combat_replay_button)
	_sound_button = _button("招式声：开", "SoundToggleButton", _toggle_sound)
	_sound_button.add_theme_font_size_override("font_size", 15)
	_sound_button.tooltip_text = "开启或静音剑招和劲风掌的出招与落点声音。"
	experiment_row.add_child(_sound_button)
	_palm_button = _button("试演掌法", "PalmVfxReplayButton", _replay_palm_vfx)
	_palm_button.add_theme_font_size_override("font_size", 15)
	_palm_button.tooltip_text = "在空地试演掌风与落尘，不伤敌、不扣行动。"
	experiment_row.add_child(_palm_button)
	_palm_style = OptionButton.new()
	_palm_style.name = "PalmStyleChoice"
	_palm_style.focus_mode = Control.FOCUS_NONE
	_palm_style.add_item("劲风掌 · 新版")
	_palm_style.add_item("气环 · 初稿")
	_palm_style.add_theme_font_size_override("font_size", 15)
	_palm_style.tooltip_text = "选择新版完整掌法演出或初稿气环，点击试演比较。"
	_palm_style.item_selected.connect(_select_palm_style)
	experiment_row.add_child(_palm_style)
	_controls["PalmStyleChoice"] = _palm_style
	_workshop_button = _button("武学工坊", "MartialWorkshopButton", _open_martial_workshop)
	_workshop_button.add_theme_font_size_override("font_size", 15)
	_workshop_button.tooltip_text = "查看六招配方、减速逐帧、对照动作并记录审阅。"
	experiment_row.add_child(_workshop_button)
	_detail_button = _button("细节：精细", "DetailToggleButton", _toggle_refined_details)
	_detail_button.add_theme_font_size_override("font_size", 15)
	_detail_button.tooltip_text = "在同一视角对照人物服饰、兵器和古道近景；不改变招式或行动。"
	experiment_row.add_child(_detail_button)
	_staff_inspect_button = _button("持棍动作", "StaffInspectorButton", _open_staff_inspector)
	_staff_inspect_button.add_theme_font_size_override("font_size", 15)
	_staff_inspect_button.tooltip_text = "近看持棍客：慢放、拖动时间并比较新旧动作。"
	experiment_row.add_child(_staff_inspect_button)
	if not review_tools_enabled:
		experiment_row.hide()
		_lighting_button.hide()
		_inspect_button.hide()
		_settings_button = _button("设置", "BattleSettingsButton", _open_battle_settings)
		header.add_child(_settings_button)
	_objective_panel = PanelContainer.new()
	_objective_panel.add_theme_stylebox_override("panel", _style(Color("#e2e7d9"), Color("#bac7b4"), 8, 8))
	column.add_child(_objective_panel)
	var goal_row := HBoxContainer.new()
	goal_row.add_theme_constant_override("separation", 18)
	_objective_panel.add_child(goal_row)
	_objective_label = _label("护住药篓", 19, INK)
	goal_row.add_child(_objective_label)
	var bar_column := VBoxContainer.new()
	bar_column.custom_minimum_size.x = 180
	bar_column.add_theme_constant_override("separation", 3)
	goal_row.add_child(bar_column)
	_objective_detail = _label("", 14, GREEN)
	bar_column.add_child(_objective_detail)
	_objective_bar = ProgressBar.new()
	_objective_bar.custom_minimum_size = Vector2(180, 6)
	_objective_bar.show_percentage = false
	_objective_bar.add_theme_stylebox_override("background", _style(Color("#c5ceba"), Color.TRANSPARENT, 4, 0))
	_objective_bar.add_theme_stylebox_override("fill", _style(GREEN, Color.TRANSPARENT, 4, 0))
	bar_column.add_child(_objective_bar)
	_objective_warning = _label("", 15, MUTED)
	_objective_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_row.add_child(_objective_warning)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	column.add_child(middle)
	var stage_frame := PanelContainer.new()
	stage_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_frame.add_theme_stylebox_override("panel", _style(Color("#cdd3bc"), Color("#aeb59c"), 9, 2))
	middle.add_child(stage_frame)
	_stage = StageScript.new() as Control
	_stage.name = "AmbushStage"
	_stage.custom_minimum_size = Vector2(600, 390)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_frame.add_child(_stage)
	_stage.call("setup", _definition, theme.default_font)
	_stage.connect("tile_clicked", _on_tile_clicked)
	_stage.connect("tile_hovered", _on_tile_hovered)
	_stage.connect("cancel_action_requested", _choose_action.bind("move"))
	_stage.tooltip_text = "按住右键或中键拖动视角；滚轮缩放。右键轻点取消招式，Home复位。"
	if _stage.has_signal("feedback_changed"):
		_stage.connect("feedback_changed", _set_feedback)
	_controls["AmbushStage"] = _stage
	var sidebar_outer := VBoxContainer.new()
	_finished_return_parent = sidebar_outer
	sidebar_outer.custom_minimum_size.x = 260
	sidebar_outer.add_theme_constant_override("separation", 6)
	middle.add_child(sidebar_outer)
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_outer.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 7)
	sidebar_scroll.add_child(sidebar)
	sidebar.add_child(_label("同行之人", 18, GREEN))
	for id: String in ["player", "tinglan"]:
		var card := _button("", "Unit_" + id, _select_unit.bind(id))
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size = Vector2(260, 46)
		sidebar.add_child(card)
		_cards[id] = card
	_barricade_label = _label("", 14, MUTED)
	_barricade_label.name = "BarricadeStatus"
	_barricade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_barricade_label.tooltip_text = "松风剑可拆栅；回澜剑或劲风掌把敌人撞向木栅时，造成碰撞加伤并破栅。"
	sidebar.add_child(_barricade_label)
	_controls["BarricadeStatus"] = _barricade_label
	var plans_panel := PanelContainer.new()
	plans_panel.add_theme_stylebox_override("panel", _style(Color("#eee2d2"), Color("#d2bda3"), 7, 8))
	sidebar.add_child(plans_panel)
	var plans_column := VBoxContainer.new()
	plans_column.add_theme_constant_override("separation", 5)
	plans_panel.add_child(plans_column)
	_plans_title = _label("敌方蓄势", 18, RED)
	plans_column.add_child(_plans_title)
	_plans_label = _label("", 14, INK)
	_plans_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plans_label.custom_minimum_size.x = 236
	plans_column.add_child(_plans_label)
	var log_title := _label("战况", 16, GREEN)
	sidebar.add_child(log_title)
	_log_label = _label("", 14, MUTED)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.max_lines_visible = 2
	_log_label.clip_text = true
	_log_label.custom_minimum_size.x = 240
	_log_label.custom_minimum_size.y = 32
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_log_label)
	_end_button = _button("结束我方回合   空格", "EndRoundButton", _end_round)
	if not review_tools_enabled:
		log_title.hide()
		_log_label.hide()
		_end_button.text = "结束回合"
		_end_button.tooltip_text = "结束我方行动，来敌按红格发动攻击（空格）。"
	_end_button.custom_minimum_size.y = 42
	_end_button.add_theme_stylebox_override("normal", _style(GREEN, GREEN, 7, 8))
	_end_button.add_theme_color_override("font_color", LIGHT)
	sidebar_outer.add_child(_end_button)
	_retry_button = _button("再试一次", "RetryButton", _request_retry)
	_retry_button.custom_minimum_size.y = 42
	sidebar_outer.add_child(_retry_button)
	var actions_panel := PanelContainer.new()
	actions_panel.add_theme_stylebox_override("panel", _style(LIGHT, LINE, 9, 8))
	column.add_child(actions_panel)
	var action_column := VBoxContainer.new()
	action_column.add_theme_constant_override("separation", 5)
	actions_panel.add_child(action_column)
	var info_row := HBoxContainer.new()
	action_column.add_child(info_row)
	_selected_label = _label("", 16, INK)
	_selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_selected_label)
	var camera_hint := _label("右键拖视角 · 滚轮缩放 · 轻点取消", 13, MUTED)
	info_row.add_child(camera_hint)
	camera_hint.visible = review_tools_enabled
	_camera_reset_button = _button("复位视角", "CameraResetButton", _reset_camera)
	_camera_reset_button.add_theme_font_size_override("font_size", 13)
	_camera_reset_button.tooltip_text = "恢复开场视角与缩放（Home）。右键或中键拖动仅改变观察角度。"
	info_row.add_child(_camera_reset_button)
	var skills_row := HBoxContainer.new()
	skills_row.add_theme_constant_override("separation", 10)
	action_column.add_child(skills_row)
	var move_button := _button("1  移动", "MoveButton", _choose_action.bind("move"))
	if not review_tools_enabled:
		move_button.text = "移动"
		move_button.tooltip_text = "每轮可移动一次；点选青色格子（1）。"
	move_button.custom_minimum_size.y = 38
	move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_row.add_child(move_button)
	_skills["move"] = move_button
	for id: String in ["strike", "push", "interrupt", "guard", "pierce", "sweep", "palm"]:
		var skill := _button("", "Skill_" + id, _choose_action.bind(id))
		skill.custom_minimum_size.y = 38
		skill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skills_row.add_child(skill)
		_skills[id] = skill
	_feedback = _label("", 15, GREEN)
	_feedback.clip_text = true
	_feedback.custom_minimum_size.y = 21
	action_column.add_child(_feedback)
	_hint = _label("青色可走 · 红格敌招 · 金色箭头为击退 · 先掌开路，再剑追击 · 每场一时辰", 13, MUTED)
	column.add_child(_hint)
	_hint.visible = review_tools_enabled
	if not review_tools_enabled:
		_build_battle_settings()


func _build_battle_settings() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.name = "BattleSettingsOverlay"
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_overlay)
	_controls["BattleSettingsOverlay"] = _settings_overlay
	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.14, 0.12, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(_on_settings_backdrop_input)
	_settings_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "BattleSettingsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -390
	panel.offset_top = 60
	panel.offset_right = -14
	panel.offset_bottom = 60
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(LIGHT, LINE, 9, 16))
	_settings_overlay.add_child(panel)
	_controls["BattleSettingsPanel"] = panel
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("设置", 20, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_button("收起", "CloseBattleSettingsButton", _close_battle_settings))
	_environment_button.reparent(column)
	_sound_button.reparent(column)
	_camera_reset_button.reparent(column)
	var camera_help := _label("右键拖视角 · 滚轮缩放\n轻点右键取消招式 · Esc 收起", 14, MUTED)
	camera_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(camera_help)
	var rules := _label("守住 %d 轮，或击退全部来敌。\n药篓被毁或两人倒下，护送失败。" % int(_definition.get("survive_rounds", 4)), 14, INK)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(rules)
	_settings_return_note = _label("撤离按未完成护送结算 1 时辰。", 14, RED)
	_settings_return_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_settings_return_note)
	_return_button.reparent(column)
	_settings_overlay.hide()


func _settings_open() -> bool:
	return is_instance_valid(_settings_overlay) and _settings_overlay.visible


func _open_battle_settings() -> void:
	if _busy or not is_instance_valid(_settings_overlay):
		return
	_settings_overlay.show()
	_hover = []
	_sync()


func _close_battle_settings() -> void:
	if not is_instance_valid(_settings_overlay):
		return
	_settings_overlay.hide()
	_sync()


func _on_settings_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_settings_overlay.accept_event()
		_close_battle_settings()


func _input(event: InputEvent) -> void:
	if not _settings_open() or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close_battle_settings()
	get_viewport().set_input_as_handled()


func _style(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, id: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	_controls[id] = button
	return button


func _state() -> Dictionary:
	return _battle.call("snapshot")


func _skill(id: String) -> Dictionary:
	var rows: Variant = _definition.get("skills", [])
	if rows is Dictionary:
		return _presented_skill((rows as Dictionary).get(id, {}))
	for row: Dictionary in rows:
		if str(row.get("id", "")) == id:
			return _presented_skill(row)
	return {}

func _presented_skill(skill: Dictionary) -> Dictionary:
	if str(skill.get("id", "")) != "strike" or _selected != "player":
		return skill
	var presented := skill.duplicate(true)
	presented.label = "松风剑·落雁斩"
	presented.description = "垫步沉身，举剑斜劈，再收势站稳。近身一格，伤害 %d；可破木栅。" % int(skill.get("damage", 0))
	return presented


func _sync() -> void:
	if not is_instance_valid(_stage):
		return
	var state := _state()
	var input_blocked := _busy or _settings_open()
	var barricade_lines: Array[String] = []
	for row: Dictionary in state.get("barricades", []):
		barricade_lines.append(str(row.name) + (" · 已破，可通行" if int(row.hp) <= 0 else "  %d/%d · 可破坏" % [int(row.hp), int(row.max_hp)]))
	_barricade_label.text = "\n".join(barricade_lines)
	_barricade_label.visible = review_tools_enabled and not barricade_lines.is_empty()
	var finished := str(state.get("phase", "")) in ["won", "lost"]
	var selected: Dictionary = _battle.call("unit", _selected)
	if int(selected.get("hp", 0)) <= 0 and not finished:
		for member: Dictionary in state.get("units", []):
			if member.get("team") == "player" and int(member.hp) > 0:
				_selected = str(member.id)
				selected = member
				break
	_round_label.text = ("护送成功" if state.phase == "won" else "护送未成") if finished else "第 %d / %d 回合 · 我方" % [int(state.round), int(_definition.get("survive_rounds", 4))]
	if not review_tools_enabled and not finished:
		_round_label.text = "第 %d / %d 回合" % [int(state.round), int(_definition.get("survive_rounds", 4))]
	_round_label.add_theme_color_override("font_color", RED if state.phase == "lost" else GREEN)
	var objective: Dictionary = state.get("objective", {})
	_threats = _threat_snapshot(state)
	var objective_threat: Dictionary = _threats.objective
	var threatened := int(objective_threat.count) > 0
	var objective_tone := RED if threatened or int(objective.get("hp", 0)) <= 0 else (GOLD if int(objective.get("hp", 0)) < int(objective.get("max_hp", 1)) else GREEN)
	var objective_status := " · 危急" if objective_threat.lethal else (" · 受威胁" if threatened else "")
	_objective_label.text = str(objective.get("name", "药篓")) + ("" if finished else objective_status)
	_objective_label.add_theme_color_override("font_color", objective_tone)
	_objective_detail.text = "完好程度  %d / %d" % [int(objective.get("hp", 0)), int(objective.get("max_hp", 1))]
	if not review_tools_enabled:
		_objective_detail.text = "%d / %d" % [int(objective.get("hp", 0)), int(objective.get("max_hp", 1))]
	_objective_bar.max_value = int(objective.get("max_hp", 1))
	_objective_bar.value = int(objective.get("hp", 0))
	_objective_bar.add_theme_stylebox_override("fill", _style(objective_tone, Color.TRANSPARENT, 4, 0))
	_objective_panel.add_theme_stylebox_override("panel", _style(Color("#efe0d3") if threatened else Color("#e2e7d9"), RED if threatened else Color("#bac7b4"), 8, 8))
	_objective_warning.add_theme_color_override("font_color", objective_tone)
	if finished:
		_objective_warning.text = "护送成功 · 药篓保住了。" if state.phase == "won" else "护送结束 · 可重新挑战。"
		if not review_tools_enabled:
			_objective_warning.text = "此役已结 · 返回集镇继续此行。"
	else:
		_objective_warning.text = "本轮预计损伤 %d · %d 人威胁" % [int(objective_threat.damage), int(objective_threat.count)]
		if not review_tools_enabled:
			_objective_warning.text = "本轮预计受损 %d%s · 每场 1 时辰" % [int(objective_threat.damage), " · 将被毁" if objective_threat.lethal else ""]
		_objective_warning.tooltip_text = ("若不应对，药篓将被毁！" if objective_threat.lethal else ("红格仍覆盖药篓，请击退或打断。" if threatened else "本轮无人攻及药篓 · 留意同伴。"))
	_objective_panel.tooltip_text = "守住 %d 轮，或击退全部来敌。药篓被毁或两人倒下，护送失败。\n按当前站位与红格计算；预计本轮后剩余 %d / %d。" % [int(_definition.get("survive_rounds", 4)), int(objective_threat.hp_after), int(objective.get("max_hp", 1))]
	for id: String in _cards:
		var member: Dictionary = _battle.call("unit", id)
		var card: Button = _cards[id]
		var status := "已倒下" if int(member.get("hp", 0)) <= 0 else ("可移动" if not member.get("moved", false) else "已移动") + " · " + ("可出招" if not member.get("acted", false) else "已出招")
		card.text = "%s   %d / %d\n%s" % [str(member.get("name", id)), int(member.get("hp", 0)), int(member.get("max_hp", 0)), status]
		card.disabled = input_blocked or int(member.get("hp", 0)) <= 0 or finished
		card.add_theme_stylebox_override("normal", _style(Color("#dce6d8") if id == _selected else LIGHT, GREEN if id == _selected else LINE, 7, 8))
	_selected_label.text = "%s   ·   %s" % [str(selected.get("name", "")), "战斗结束" if finished else ("选择落点" if _action == "move" else str(_skill(_action).get("label", "选择招式")))]
	for id: String in _skills:
		var button: Button = _skills[id]
		if id == "move":
			button.disabled = input_blocked or finished or bool(selected.get("moved", true))
		else:
			var skill := _skill(id)
			button.visible = (selected.get("skills", []) as Array).has(id)
			var number: String = {"strike": "2", "push": "3", "interrupt": "4", "guard": "5", "pierce": "6", "sweep": "7", "palm": "8"}[id]
			button.text = "%s  %s" % [number, str(skill.get("label", id))] if review_tools_enabled else str(skill.get("label", id))
			button.tooltip_text = _skill_short(skill) + "\n" + str(skill.get("description", "")) + ("" if review_tools_enabled else "（%s）" % number)
			button.disabled = input_blocked or finished or bool(selected.get("acted", true))
		button.add_theme_stylebox_override("normal", _style(Color("#dbe5d8") if id == _action else LIGHT, GREEN if id == _action else LINE, 7, 8))
	_end_button.visible = not finished
	_end_button.disabled = input_blocked
	_retry_button.visible = review_tools_enabled and finished
	_retry_button.disabled = _busy
	_return_button.text = "返回集镇" if finished else "撤离"
	_return_button.tooltip_text = "收起战斗，返回同一段行旅。" if finished else "放弃本场护送，按失败结算一时辰并返回集镇。"
	_return_button.disabled = _busy
	if not review_tools_enabled:
		_settings_button.disabled = _busy
		_settings_return_note.visible = not finished
		if finished and _return_button.get_parent() != _finished_return_parent:
			_return_button.reparent(_finished_return_parent)
	_restart_button.visible = review_tools_enabled and not finished
	_restart_button.disabled = _busy
	_camera_reset_button.disabled = _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop)
	_stage.call("set_camera_input_enabled", not _camera_reset_button.disabled and not _settings_open())
	_detail_button.disabled = _camera_reset_button.disabled
	_detail_button.text = "细节：精细" if _refined_details else "细节：原版"
	_stage.call("set_detail_input_enabled", not _detail_button.disabled and not _settings_open())
	_staff_inspect_button.disabled = _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop)
	_workshop_button.disabled = _busy or is_instance_valid(_character_inspector)
	_inspect_button.disabled = _busy
	_lighting_button.disabled = _busy
	_combat_light_button.disabled = _busy
	_combat_replay_button.disabled = _busy or int((_battle.call("unit", "player") as Dictionary).get("hp", 0)) <= 0
	_preview_choice.disabled = _busy
	_sound_button.disabled = _busy
	_palm_style.disabled = _busy
	_palm_button.disabled = _busy or int((_battle.call("unit", "tinglan") as Dictionary).get("hp", 0)) <= 0
	var plans: Array[String] = []
	var detailed_plans: Array[String] = []
	for threat: Dictionary in _threats.enemies:
		var text := str(threat.text)
		detailed_plans.append(text)
		if not review_tools_enabled:
			text = text.get_slice(" · ", 0) + (" · 已打断" if threat.interrupted else " " + text.get_slice("\n", 1))
		plans.append(text)
	_plans_label.text = "\n".join(plans) if not plans.is_empty() else "来敌已退。"
	_plans_label.tooltip_text = "\n".join(detailed_plans) if not detailed_plans.is_empty() else _plans_label.text
	_plans_title.text = "护送回报" if finished else ("敌方蓄势 · 药篓告急" if threatened else "敌方蓄势 · 真实红格")
	if not review_tools_enabled:
		_plans_title.text = "护送回报" if finished else "即将攻击"
	if finished:
		_plans_label.text = "药篓已脱险，可以继续上山。" if state.phase == "won" else "本场护送失败，先撤回安全处。"
	var lines: Array = state.get("log", [])
	var tail: Array[String] = []
	for index: int in range(maxi(0, lines.size() - 4), lines.size()):
		tail.append(str(lines[index]))
	_log_label.text = "\n".join(tail)
	var reachable: Array = _battle.call("reachable", _selected) if _action == "move" and not input_blocked and not finished else []
	var preview: Dictionary = {}
	if not _hover.is_empty() and _action != "move" and not finished:
		preview = _battle.call("preview", _selected, _action, _hover)
		if bool(preview.get("ok", false)) and str(_skill(_action).get("effect", "")) == "push":
			var target: Dictionary = _battle.call("unit", str(preview.get("target_id", "")))
			var applied := maxi(0, int(preview.get("damage", 0)) - (3 if bool(target.get("guarded", false)) else 0))
			if int(target.get("hp", 0)) > 0 and applied >= int(target.hp):
				# The authoritative action never moves a defeated body. Keep
				# collision damage/obstacle marks, but show no fictitious landing.
				preview["push_path"] = []
				preview["push_to"] = []
	if _action == "palm" and not _busy and not finished:
		var target_cells: Array = []
		for member: Dictionary in state.get("units", []):
			if str(member.get("team", "")) != "enemy" or int(member.get("hp", 0)) <= 0:
				continue
			var forecast: Dictionary = _battle.call("preview", _selected, _action, member.pos)
			if bool(forecast.get("ok", false)):
				target_cells.append(member.pos.duplicate())
		# Legal range and line of sight come from the same authoritative
		# preview used on click, including currently standing barricades.
		preview["target_cells"] = target_cells
	if _selected == "tinglan" and _action == "move" and not bool(selected.get("acted", true)) and int(state.get("round", 0)) == 1 and reachable.has([3, 4]):
		var brute: Dictionary = _battle.call("unit", "brute")
		if int(brute.get("hp", 0)) > 0 and brute.get("pos", []) == [4, 3]:
			preview["tactic_tile"] = [3, 4]
	_hover_preview = preview.duplicate(true)
	_stage.call("sync_state", state, _selected, reachable, preview)
	if finished:
		var ending_feedback := "药篓保住了。可以再试另一种走位，或返回集镇继续修行。" if state.phase == "won" else "护送未成。可重新挑战，试着优先打断重招、把来敌推离药篓。"
		_set_feedback(ending_feedback if review_tools_enabled else "返回集镇，继续此行。", "danger" if state.phase == "lost" else "control")


func _threat_snapshot(state: Dictionary) -> Dictionary:
	# Presentation only: consume the rule's advertised cells, never its authored target/label.
	var members: Dictionary = {}
	for member: Dictionary in state.get("units", []):
		members[str(member.get("id", ""))] = member
	var objective: Dictionary = state.get("objective", {})
	var hp := maxi(0, int(objective.get("hp", 0)))
	var count := 0
	var raw_damage := 0
	var enemies: Array[Dictionary] = []
	var active := str(state.get("phase", "")) == "player"
	for plan: Dictionary in state.get("plans", []):
		var id := str(plan.get("unit_id", ""))
		var enemy: Dictionary = members.get(id, {})
		if int(enemy.get("hp", 0)) <= 0:
			continue
		var interrupted := bool(plan.get("interrupted", false))
		var displaced := bool(plan.get("displaced", false))
		var cells: Array = plan.get("cells", [])
		var damage := maxi(0, int(plan.get("damage", 0)))
		var targets: Array[String] = []
		var names: Array[String] = []
		if active and not interrupted:
			if hp > 0 and objective.get("pos", []) in cells:
				targets.append("objective")
				names.append(str(objective.get("name", "药篓")))
				count += 1
				raw_damage += damage
			for member: Dictionary in state.get("units", []):
				if member.get("team") == "player" and int(member.get("hp", 0)) > 0 and member.get("pos", []) in cells:
					targets.append(str(member.get("id", "")))
					names.append(str(member.get("name", "同伴")))
		var title := str(enemy.get("name", "敌人")) + " · "
		var detail := ""
		if interrupted:
			title += "本轮已打断"
			detail = "移动与攻击均已取消"
		else:
			title += "击退后新范围" if displaced else str(plan.get("label", "蓄势"))
			detail = "→ " + ("落空 · 无人处于红格" if names.is_empty() else " / ".join(names) + " · 攻击 %d" % damage)
		enemies.append({"unit_id": id, "cells": cells.duplicate(true), "targets": targets,
			"interrupted": interrupted, "displaced": displaced, "damage": damage,
			"text": title + "\n" + detail})
	var expected := mini(hp, raw_damage)
	return {"enemies": enemies, "objective": {"count": count, "damage": expected,
		"raw_damage": raw_damage, "hp_after": hp - expected, "lethal": hp > 0 and expected >= hp}}


func _preview_feedback(preview: Dictionary) -> String:
	if str(preview.get("shape", "")) in ["pierce", "sweep"]:
		var names: Array[String] = []
		for id: String in preview.get("targets", []):
			names.append(str((_battle.call("unit", id) as Dictionary).get("name", id)))
		return "%s → %s · %d人 · 共 %d 伤害 · 同伴药篓免伤" % [str(_skill(_action).get("label", "出招")), " / ".join(names), names.size(), int(preview.get("total_damage", 0))]
	if str(preview.get("target_kind", "unit")) == "barricade":
		var gate: Dictionary = _barricade(str(preview.get("target_id", "")))
		return "%s → %s · 预计破坏 %d · %s" % [str(_skill("strike").get("label", "松风剑")), str(gate.get("name", "木栅")), int(preview.get("barricade_damage", preview.get("damage", 0))), "栅破后可通行" if bool(preview.get("destroys_barricade", false)) else "仍会阻路"]
	var target: Dictionary = _battle.call("unit", str(preview.get("target_id", "")))
	var skill := _skill(_action)
	var damage := mini(int(target.get("hp", 0)), maxi(0, int(preview.get("damage", 0)) - (3 if target.get("guarded", false) else 0)))
	var lethal_palm := _action == "palm" and damage >= int(target.get("hp", 1))
	var text := "%s → %s · 预计 %d 伤害" % [str(skill.get("label", "出招")), str(target.get("name", "目标")), damage]
	if bool(preview.get("destroys_barricade", false)):
		text += (" · 撞破%s" if lethal_palm else " · 撞破%s，停在栅前") % str(_barricade(str(preview.get("collision_barricade_id", ""))).get("name", "木栅"))
	if damage >= int(target.get("hp", 1)):
		return text + (" · 将击倒，不再位移，蓄势消失" if lethal_palm else " · 将击倒，蓄势消失")
	if str(skill.get("effect", "")) == "push":
		var path: Array = preview.get("push_path", [])
		text += " · 击退 %d 格" % maxi(0, path.size() - 1)
		if bool(preview.get("collision", false)):
			text += " · 受阻碰撞 +%d（已计入）" % int(skill.get("collision_bonus", 0))
		else:
			text += " · 敌方红格随落点更新"
	elif bool(preview.get("will_interrupt", false)):
		var cancelled := false
		for plan: Dictionary in _state().get("plans", []):
			if str(plan.get("unit_id", "")) == str(preview.get("target_id", "")):
				cancelled = bool(plan.get("interrupted", false))
		text += " · 本轮已打断" if cancelled else " · 取消本轮移动与攻击"
	return text


func _skill_short(skill: Dictionary) -> String:
	match str(skill.get("effect", skill.get("id", ""))):
		"push": return "伤害 %d · 距离 %d · 击退 %d 格 · 碰撞加伤 %d" % [int(skill.get("damage", 0)), int(skill.get("range", 1)), int(skill.get("push_distance", 2)), int(skill.get("collision_bonus", 0))]
		"interrupt": return "打断 · 取消本轮蓄势"
		"guard": return "护身 · 减少所受伤害"
		"strike": return "伤害 %d · 可破木栅" % int(skill.get("damage", 0))
		"pierce": return "直线贯穿两格 · 每人 %d" % int(skill.get("damage", 0))
		"sweep": return "前方三格横扫 · 每人 %d" % int(skill.get("damage", 0))
	return "伤害 %d · 距离 %d" % [int(skill.get("damage", 0)), int(skill.get("range", 1))]


func _barricade(id: String) -> Dictionary:
	for row: Dictionary in _state().get("barricades", []):
		if str(row.id) == id:
			return row
	return {}


func _barricade_at(tile: Array) -> Dictionary:
	for row: Dictionary in _state().get("barricades", []):
		if row.pos == tile and int(row.hp) > 0:
			return row
	return {}


func _select_unit(id: String) -> void:
	if _busy or _settings_open() or _state().get("phase") != "player":
		return
	var member: Dictionary = _battle.call("unit", id)
	if int(member.get("hp", 0)) <= 0:
		return
	_selected = id
	_action = "strike" if bool(member.get("moved", false)) and not bool(member.get("acted", false)) else "move"
	_hover = []
	_sync()
	if review_tools_enabled:
		_set_feedback("先到棍客左下侧的‘出掌位’，看金色击退箭头再出掌；江砚秋可沿空出的路追击。" if _hover_preview.has("tactic_tile") else "每人每轮可移动一次、出招一次，先后顺序自由。")
	else:
		_set_feedback("")


func _choose_action(id: String) -> void:
	if _busy or _settings_open() or _state().get("phase") != "player":
		return
	var member: Dictionary = _battle.call("unit", _selected)
	if id == "move" and bool(member.get("moved", false)):
		_action = "move"
		_hover = []
		_set_feedback("已取消招式。本轮已经移动，可重新选择出招，或点选另一位同伴。")
		_sync()
		return
	if id != "move" and (bool(member.get("acted", false)) or not (member.get("skills", []) as Array).has(id)):
		return
	_action = id
	_hover = []
	_set_feedback(_action_prompt(id))
	if id == "guard":
		_resolve(_battle.call("use_skill", _selected, id, member.pos))
	else:
		_sync()


func _action_prompt(id: String) -> String:
	if id == "move":
		return "点选青色格子移动。" if review_tools_enabled else ""
	return str(_skill(id).get("description", "点选目标。")) if review_tools_enabled else _skill_short(_skill(id))


func _on_tile_hovered(tile: Array) -> void:
	if _busy or _settings_open() or _state().get("phase") != "player" or tile == _hover:
		return
	_hover = tile.duplicate()
	if not tile.is_empty() and _action != "move":
		var preview: Dictionary = _battle.call("preview", _selected, _action, tile)
		if preview.get("ok", false):
			_set_feedback(_preview_feedback(preview), "control" if _action in ["push", "palm", "interrupt"] else "hit")
		else:
			_set_feedback(str(preview.get("reason", "此处不能出招")), "danger")
	elif not tile.is_empty() and not _barricade_at(tile).is_empty():
		_set_feedback(str(_barricade_at(tile).name) + "挡住了路，选择松风剑可拆开。", "control")
	elif tile.is_empty():
		_set_feedback(_action_prompt(_action))
	_sync()


func _on_tile_clicked(tile: Array) -> void:
	if _busy or _settings_open() or tile.is_empty() or _state().get("phase") != "player":
		return
	for member: Dictionary in _state().get("units", []):
		if member.pos == tile and member.team == "player" and int(member.hp) > 0 and not _action in ["pierce", "sweep"]:
			_select_unit(str(member.id))
			return
	if _action == "move":
		if not _barricade_at(tile).is_empty():
			_set_feedback("木栅挡住了路，先选择松风剑拆开。", "control")
			return
		_resolve(_battle.call("move_unit", _selected, tile))
	else:
		_resolve(_battle.call("use_skill", _selected, _action, tile))


func _end_round() -> void:
	if not _busy and not _settings_open() and _state().get("phase") == "player":
		_resolve(_battle.call("end_round"))


func _resolve(result: Dictionary) -> void:
	if not result.get("ok", false):
		_set_feedback(str(result.get("reason", "这一步不能完成。")), "danger")
		return
	_busy = true
	_end_button.disabled = true
	_return_button.disabled = true
	_restart_button.disabled = true
	_camera_reset_button.disabled = true
	_stage.call("set_camera_input_enabled", false)
	_stage.call("set_detail_input_enabled", false)
	_detail_button.disabled = true
	_staff_inspect_button.disabled = true
	_workshop_button.disabled = true
	_inspect_button.disabled = true
	_lighting_button.disabled = true
	_combat_light_button.disabled = true
	_combat_replay_button.disabled = true
	_preview_choice.disabled = true
	_sound_button.disabled = true
	if is_instance_valid(_settings_button):
		_settings_button.disabled = true
	_palm_button.disabled = true
	_palm_style.disabled = true
	for id: String in _skills:
		(_skills[id] as Button).disabled = true
	for id: String in _cards:
		(_cards[id] as Button).disabled = true
	_stage.call("animate_events", result.get("events", []), _state())
	while is_instance_valid(_stage) and bool(_stage.call("is_animating")):
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_busy = false
	_hover = []
	var selected: Dictionary = _battle.call("unit", _selected)
	if bool(selected.get("moved", false)) and not bool(selected.get("acted", false)):
		_action = "strike"
	elif bool(selected.get("acted", false)):
		_action = "move"
	_sync()
	if str(_state().get("phase", "")) in ["won", "lost"] and not _reported:
		_reported = true
		completed.emit()


func _set_feedback(text: String, tone: String = "neutral") -> void:
	_feedback_tone = tone
	if is_instance_valid(_feedback):
		_feedback.text = text
		_feedback.tooltip_text = text
		_feedback.add_theme_color_override("font_color", RED if tone == "danger" else (GOLD if tone == "hit" else GREEN))


func _request_return() -> void:
	if not _busy:
		return_requested.emit()


func _request_retry() -> void:
	if not _busy:
		retry_requested.emit()


func _toggle_environment() -> void:
	_environment_static = not _environment_static
	_stage.call("set_environment_static", _environment_static)
	_environment_button.text = "景物：静止" if _environment_static else "景物：动态"


func _toggle_lighting() -> void:
	if _busy:
		return
	_enhanced_lighting = not _enhanced_lighting
	_stage.call("set_enhanced_lighting", _enhanced_lighting)
	_lighting_button.text = "光影：增强" if _enhanced_lighting else "光影：原版"

func _cycle_combat_light() -> void:
	if _busy:
		return
	var mode: int = (_combat_light_mode + 1) % 3
	if not bool(_stage.call("set_combat_light_mode", mode)):
		return
	_combat_light_mode = mode
	_combat_light_button.text = ["演出：原演出", "演出：招式光", "演出：光与投影"][mode]
	_set_feedback(["原演出：保留当前战场光影，可试演同一回澜剑。", "招式光：剑光照亮衣服与地面，可与投影档对照。", "光与投影：招式灯照亮近处，人物投影随光变化。"][mode])

func _replay_combat_light() -> void:
	if _busy or is_instance_valid(_character_inspector):
		return
	if int((_battle.call("unit", "player") as Dictionary).get("hp", 0)) <= 0:
		return
	_busy = true
	_replaying = true
	_sync()
	_set_feedback(str(_skill(_preview_skill).get("label", "回澜剑")) + "试演 · 不伤敌，不扣行动与时辰。")
	await _stage.call("preview_combat_lighting", _preview_skill)
	if not is_inside_tree():
		return
	_busy = false
	_replaying = false
	_sync()
	_set_feedback("试演结束 · 战局保持，可切换另一档再看。")

func _replay_palm_vfx() -> void:
	if _busy or is_instance_valid(_character_inspector) or int((_battle.call("unit", "tinglan") as Dictionary).get("hp", 0)) <= 0:
		return
	_busy = true
	_replaying = true
	_sync()
	_set_feedback(("劲风掌" if _palm_style_index == 0 else "气环初稿") + " · 空地试演，不伤敌，不扣行动与时辰。")
	await _stage.call("preview_palm_vfx", _palm_style_index)
	if not is_inside_tree():
		return
	_busy = false
	_replaying = false
	_sync()
	_set_feedback("试演结束 · 掌风与落尘已收起，可继续战斗。")

func _select_palm_style(index: int) -> void:
	if _busy or index < 0 or index > 1:
		return
	_palm_style_index = index

func _select_preview_skill(index: int) -> void:
	if _busy or index < 0 or index > 2:
		return
	_preview_skill = ["push", "pierce", "sweep"][index]
	_combat_replay_button.text = ["近看回澜", "近看穿云", "近看回风"][index]

func _toggle_sound() -> void:
	if _busy:
		return
	_sound_muted = not _sound_muted
	_stage.call("set_skill_audio", _sound_muted)
	_sound_button.text = "招式声：关" if _sound_muted else "招式声：开"

func _open_staff_inspector() -> void:
	if _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop) or is_instance_valid(_staff_inspector):
		return
	_busy = true
	_sync()
	var battle_viewport := _stage.get("viewport") as SubViewport
	_battle_viewport_mode = battle_viewport.render_target_update_mode
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_staff_inspector = StaffInspectorScript.new() as Control
	_staff_inspector.name = "StaffMotionInspector"
	add_child(_staff_inspector)
	_staff_inspector.connect("closed", _close_staff_inspector)
	_staff_inspector.call("setup", theme.default_font)

func _close_staff_inspector() -> void:
	if is_instance_valid(_staff_inspector):
		_staff_inspector.hide()
		_staff_inspector.queue_free()
	_staff_inspector = null
	var battle_viewport := _stage.get("viewport") as SubViewport
	battle_viewport.render_target_update_mode = _battle_viewport_mode
	_busy = false
	_sync()

func _open_characters() -> void:
	if _busy or is_instance_valid(_character_inspector):
		return
	_stage.call("set_camera_input_enabled", false)
	_stage.call("set_detail_input_enabled", false)
	_detail_button.disabled = true
	_camera_reset_button.disabled = true
	_character_inspector = CharacterInspectorScript.new() as Control
	_character_inspector.call("set_refined_details", _refined_details)
	_character_inspector.name = "BattleCharacterInspector"
	add_child(_character_inspector)
	_character_inspector.connect("closed", _close_characters)
	_character_inspector.call("setup", theme.default_font, _selected)


func _close_characters() -> void:
	if is_instance_valid(_character_inspector):
		_character_inspector.hide()
		_character_inspector.queue_free()
	_character_inspector = null
	_sync()


func _reset_camera() -> void:
	if _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop):
		return
	if _settings_open():
		_close_battle_settings()
	_stage.call("reset_camera_view")


func _toggle_refined_details() -> void:
	if _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop):
		return
	if bool(_stage.call("set_refined_details", not _refined_details)):
		_refined_details = not _refined_details
		_detail_button.text = "细节：精细" if _refined_details else "细节：原版"


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _settings_open() or not is_visible_in_tree() or is_instance_valid(_character_inspector):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_ESCAPE: _choose_action("move")
			KEY_2: _choose_action("strike")
			KEY_3: _choose_action("push")
			KEY_4: _choose_action("interrupt")
			KEY_5: _choose_action("guard")
			KEY_6: _choose_action("pierce")
			KEY_7: _choose_action("sweep")
			KEY_8: _choose_action("palm")
			KEY_Q: _select_unit("player")
			KEY_E: _select_unit("tinglan")
			KEY_SPACE: _end_round()
			KEY_HOME: _reset_camera()
		get_viewport().set_input_as_handled()


func ui_control(id: String) -> Control:
	return _controls.get(id) as Control


func audit_tile_center(tile: Array) -> Vector2:
	return _stage.global_position + (_stage.call("tile_to_screen", tile) as Vector2)


func audit_snapshot() -> Dictionary:
	var rects: Dictionary = {}
	for id: String in _controls:
		var control: Control = _controls[id]
		if is_instance_valid(control) and control.is_visible_in_tree():
			rects[id] = control.get_global_rect()
	return {"battle": _state(), "selected": _selected, "action": _action, "busy": _busy, "reported": _reported, "combat_light_mode": _combat_light_mode, "replaying": _replaying, "palm_style": _palm_style_index,
		"camera_control": _stage.call("camera_control_audit"), "refined_details": _refined_details, "feedback": _feedback.text, "feedback_tone": _feedback_tone, "preview": _hover_preview.duplicate(true), "preview_skill": _preview_skill, "sound_muted": _sound_muted, "settings_open": _settings_open(),
		"objective_threat": (_threats.get("objective", {}) as Dictionary).duplicate(true),
		"enemy_threats": (_threats.get("enemies", []) as Array).duplicate(true),
		"objective_warning": _objective_warning.text, "plans_text": _plans_label.text,
		"controls": rects, "staff_inspector": _staff_inspector.call("audit_snapshot") if is_instance_valid(_staff_inspector) else {}, "martial_workshop": _martial_workshop.call("audit_snapshot") if is_instance_valid(_martial_workshop) else {}, "character_inspector": _character_inspector.call("audit_snapshot") if is_instance_valid(_character_inspector) else {}}

func _open_martial_workshop() -> void:
	if _busy or is_instance_valid(_character_inspector) or is_instance_valid(_martial_workshop):
		return
	var result := MoveCatalog.load_catalog()
	if not result.ok:
		_set_feedback(str(result.reason), "danger")
		return
	_busy = true
	_sync()
	var battle_viewport := _stage.get("viewport") as SubViewport
	_battle_viewport_mode = battle_viewport.render_target_update_mode
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_martial_workshop = WorkshopScript.new() as Control
	_martial_workshop.name = "MartialWorkshop"
	add_child(_martial_workshop)
	_martial_workshop.connect("closed", _close_martial_workshop)
	_martial_workshop.call("setup", theme.default_font, _definition, _battle.call("snapshot"), result.catalog)
	_martial_workshop.call("set_skill_audio", _sound_muted)

func _close_martial_workshop() -> void:
	if is_instance_valid(_martial_workshop):
		_martial_workshop.hide()
		_martial_workshop.queue_free()
	_martial_workshop = null
	var battle_viewport := _stage.get("viewport") as SubViewport
	battle_viewport.render_target_update_mode = _battle_viewport_mode
	_busy = false
	_sync()
