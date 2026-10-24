extends Control

signal backend_requested(id: String)
signal action_requested(id: String)
signal advance_requested
signal choice_requested(id: String)
signal cancel_requested

const DESIGN_SIZE := Vector2(1440.0, 900.0)
const FONT_PATH := "res://assets/fonts/ShuDialogueLabSerif.ttf"
const BACKGROUND_PATH := "res://assets/art/weather3/tingyu-clean-v3.png"
const PLAYER_PATH := "res://assets/art/v2/jiang-yanqiu-v2.png"
const MENTOR_PATH := "res://assets/art/v2/ye-zhixian-v2.png"
const DESK_PATH := "res://assets/art/v2/desk-v2.png"

const INK := Color("#302d28")
const MUTED_INK := Color("#766d60")
const PAPER := Color("#f3ead8")
const PAPER_LIGHT := Color("#fbf5e9")
const JADE := Color("#416c61")
const JADE_DARK := Color("#31584f")
const CINNABAR := Color("#9b5545")
const GOLD := Color("#b89b69")

var _canvas: Control
var _voice_layer: CanvasLayer
var _backend_buttons: Dictionary = {}
var _status_labels: Dictionary = {}
var _action_buttons: Dictionary = {}
var _footer_buttons: Dictionary = {}
var _dialogue_panel: Control
var _speaker_label: Label
var _speaker_role_label: Label
var _dialogue_text_label: Label
var _choice_host: Control
var _advance_button: Button
var _cancel_button: Button
var _notice_panel: Control
var _notice_label: Label
var _mentor_button: Button
var _voice_toggle_button: Button
var _choice_entries: Array[Dictionary] = []
var _status: Dictionary = {
	"backend_label": "Dialogue Manager",
	"day_label": "第一日 · 卯时",
	"energy": 100,
	"cultivation": 0,
	"hint": "点师傅，聊聊刚才那一剑。",
	"lesson_claimed": false,
	"busy": false,
	"save_enabled": false,
	"load_enabled": false,
}
var _dialogue_speaker := ""
var _dialogue_text := ""
var _dialogue_choices: Array[Dictionary] = []
var _dialogue_can_advance := true
var _dialogue_visible := true
var _notice_text := ""
var _notice_visible := false
var _result_mode := false
var _backend_id := "dm"
var _voice_enabled := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_view()
	_sync_canvas_layout()
	_sync_backend_buttons()
	_sync_status_labels()
	_sync_enabled_states()
	if _dialogue_text.is_empty():
		_dialogue_speaker = "叶知闲"
		_dialogue_text = "这方廊下，先听一句口诀。切换上方工具，看看同一段故事怎样展开。"
	_render_dialogue()
	_dialogue_panel.visible = _dialogue_visible
	_notice_label.text = _notice_text
	_notice_panel.visible = _notice_visible
	call_deferred("_sync_canvas_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_canvas_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()


func set_status(data: Dictionary) -> void:
	_status.merge(data, true)
	if data.has("backend_label"):
		var backend_label := str(_status.get("backend_label", "Dialogue Manager"))
		if backend_label.to_lower().contains("dialogic"):
			_backend_id = "dialogic"
		else:
			_backend_id = "dm"
	_sync_backend_buttons()
	_sync_status_labels()
	_sync_enabled_states()


func show_dialogue(speaker: String, text: String, choices: Array = [], can_advance: bool = true) -> void:
	_dialogue_speaker = speaker
	_dialogue_text = text
	_dialogue_choices.clear()
	for entry in choices:
		if entry is Dictionary:
			_dialogue_choices.append((entry as Dictionary).duplicate(true))
	_dialogue_can_advance = can_advance
	_result_mode = false
	_dialogue_visible = true
	_notice_visible = false
	if is_instance_valid(_dialogue_panel):
		_render_dialogue()
		_dialogue_panel.visible = true
		_notice_panel.visible = false


func hide_dialogue() -> void:
	_dialogue_visible = false
	_notice_visible = false
	if is_instance_valid(_dialogue_panel):
		_dialogue_panel.visible = false
	if is_instance_valid(_notice_panel):
		_notice_panel.visible = false


func show_result(message: String) -> void:
	_dialogue_speaker = "本次回响"
	_dialogue_text = message
	_dialogue_choices.clear()
	_dialogue_can_advance = true
	_result_mode = true
	_dialogue_visible = true
	_notice_visible = false
	if is_instance_valid(_dialogue_panel):
		_render_dialogue()
		_dialogue_panel.visible = true
		_notice_panel.visible = false


func show_notice(message: String) -> void:
	_notice_text = message
	_notice_visible = true
	if is_instance_valid(_notice_panel):
		_notice_label.text = message
		_notice_panel.visible = true


func audit() -> Dictionary:
	var rects := {
		"backend_dm": _global_rect(_backend_buttons.get("dm")),
		"backend_dialogic": _global_rect(_backend_buttons.get("dialogic")),
		"action_talk": _global_rect(_action_buttons.get("talk")),
		"action_train": _global_rect(_action_buttons.get("train")),
		"action_rest": _global_rect(_action_buttons.get("rest")),
		"mentor_talk": _global_rect(_mentor_button),
		"footer_save": _global_rect(_footer_buttons.get("save")),
		"footer_load": _global_rect(_footer_buttons.get("load")),
		"footer_reset": _global_rect(_footer_buttons.get("reset")),
		"footer_voice_toggle": _global_rect(_voice_toggle_button),
		"advance": _global_rect(_advance_button),
		"cancel": _global_rect(_cancel_button),
	}
	var choices: Array[Dictionary] = []
	for entry in _choice_entries:
		var button := entry.get("button") as Button
		if is_instance_valid(button) and button.is_visible_in_tree():
			choices.append({
				"id": str(entry.get("id", "")),
				"label": str(entry.get("label", "")),
				"global_rect": button.get_global_rect(),
			})
	return {
		"ui_rects": rects,
		"choices": choices,
		"dialogue": {
			"visible": is_instance_valid(_dialogue_panel) and _dialogue_panel.visible,
			"speaker": _dialogue_speaker,
			"text": _dialogue_text,
			"result_mode": _result_mode,
		},
		"dialogue_text": _dialogue_text,
		"backend_id": _backend_id,
		"voice_enabled": _voice_enabled,
		"canvas_scale": _canvas.scale.x if is_instance_valid(_canvas) else 0.0,
		"viewport_size": size,
	}


func _build_view() -> void:
	_canvas = Control.new()
	_canvas.name = "DialogueToolsLabCanvas"
	_canvas.size = DESIGN_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.clip_contents = true
	_canvas.theme = _make_theme()
	add_child(_canvas)

	_add_art(BACKGROUND_PATH, Rect2(Vector2.ZERO, DESIGN_SIZE), TextureRect.STRETCH_KEEP_ASPECT_COVERED, "TingyuBackground")
	_add_art(PLAYER_PATH, Rect2(475, 281, 332, 495), TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "JiangPortrait", true)
	_add_art(MENTOR_PATH, Rect2(764, 263, 346, 513), TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "YePortrait", true)
	# This painted asset is a foreground desk edge without legs. Its lower
	# edge must continue beyond the frame instead of exposing floor below it.
	_add_art(DESK_PATH, Rect2(283, 544, 1076, 368), TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "ForegroundDesk", true)
	_build_header()
	_build_action_panel()
	_build_dialogue_panel()
	_build_footer()
	_build_notice()


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 19
	if ResourceLoader.exists(FONT_PATH):
		var font_resource: Resource = ResourceLoader.load(FONT_PATH)
		if font_resource is Font:
			theme.default_font = font_resource as Font
	return theme


func _build_header() -> void:
	_make_panel(Rect2(24, 18, 420, 97), Color(0.97, 0.94, 0.87, 0.94), GOLD, 14, "TitlePaper")
	var title := _make_label("慢半步 · 听雨廊", Rect2(38, 20, 365, 44), 34, INK, HORIZONTAL_ALIGNMENT_LEFT, "LabTitle")
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.96, 0.87, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	_make_label("师徒对话 · 慢下来再出剑", Rect2(42, 65, 390, 28), 17, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "LabSubtitle")

	var tools_panel := _make_panel(Rect2(462, 18, 532, 93), Color(0.96, 0.92, 0.84, 0.94), GOLD, 14, "BackendSwitchPanel")
	_make_label("切换剧情框架", Rect2(481, 23, 200, 25), 15, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "BackendPrompt")
	_backend_buttons["dm"] = _make_button("A  Dialogue Manager", Rect2(478, 54, 244, 43), "BackendDialogueManager", Callable(self, "_on_backend_pressed").bind("dm"), JADE, "dm")
	_backend_buttons["dialogic"] = _make_button("B  Dialogic", Rect2(734, 54, 242, 43), "BackendDialogic", Callable(self, "_on_backend_pressed").bind("dialogic"), CINNABAR, "dialogic")

	_make_panel(Rect2(1021, 24, 382, 72), Color(0.97, 0.94, 0.87, 0.92), Color("#c6b796"), 13, "StatusPanel")
	_status_labels["day"] = _make_label("第一日 · 卯时", Rect2(1040, 30, 154, 26), 18, INK, HORIZONTAL_ALIGNMENT_LEFT, "DayLabel")
	_status_labels["energy"] = _make_label("精力 100", Rect2(1200, 30, 92, 26), 17, JADE_DARK, HORIZONTAL_ALIGNMENT_LEFT, "EnergyLabel")
	_status_labels["cultivation"] = _make_label("修为 0", Rect2(1290, 30, 96, 26), 17, CINNABAR, HORIZONTAL_ALIGNMENT_LEFT, "CultivationLabel")
	_status_labels["lesson"] = _make_label("口诀尚未领悟", Rect2(1041, 58, 175, 24), 14, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "LessonLabel")
	_status_labels["busy"] = _make_label("可自由行动", Rect2(1213, 58, 170, 24), 14, JADE, HORIZONTAL_ALIGNMENT_RIGHT, "BusyLabel")


func _build_action_panel() -> void:
	_make_panel(Rect2(36, 276, 211, 293), Color(0.97, 0.94, 0.87, 0.93), Color("#c8b997"), 14, "ActionPanel")
	_make_label("廊下小课", Rect2(55, 293, 171, 30), 21, INK, HORIZONTAL_ALIGNMENT_LEFT, "ActionHeading")
	_make_label("依心选一项功课", Rect2(57, 324, 165, 22), 13, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "ActionSubheading")
	_action_buttons["talk"] = _make_button("请教师傅", Rect2(53, 365, 178, 51), "ActionTalk", Callable(self, "_on_action_pressed").bind("talk"), JADE)
	_action_buttons["train"] = _make_button("修习", Rect2(53, 428, 178, 49), "ActionTrain", Callable(self, "_on_action_pressed").bind("train"), JADE_DARK)
	_action_buttons["rest"] = _make_button("歇息", Rect2(53, 489, 178, 49), "ActionRest", Callable(self, "_on_action_pressed").bind("rest"), CINNABAR)
	var rule := ColorRect.new()
	rule.name = "ActionRule"
	rule.position = Vector2(57, 548)
	rule.size = Vector2(166, 1)
	rule.color = Color("#cdbf9f")
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(rule)
	_make_panel(Rect2(36, 578, 211, 71), Color(0.97, 0.94, 0.87, 0.93), Color("#c8b997"), 12, "HintPaper")
	_status_labels["hint"] = _make_label("点击师傅，听一句今日口诀。", Rect2(51, 586, 182, 52), 14, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "HintLabel", true)
	_mentor_button = Button.new()
	_mentor_button.name = "MentorTalkHotspot"
	_mentor_button.position = Vector2(766, 266)
	_mentor_button.size = Vector2(342, 507)
	_mentor_button.flat = true
	_mentor_button.focus_mode = Control.FOCUS_NONE
	_mentor_button.tooltip_text = "点击叶知闲，请教今日口诀。"
	_mentor_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mentor_button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0)))
	_mentor_button.add_theme_stylebox_override("hover", _flat_style(Color(0.77, 0.69, 0.48, 0.08)))
	_mentor_button.add_theme_stylebox_override("pressed", _flat_style(Color(0.55, 0.66, 0.58, 0.12)))
	_mentor_button.pressed.connect(Callable(self, "_on_action_pressed").bind("talk"))
	_canvas.add_child(_mentor_button)


func _build_dialogue_panel() -> void:
	_dialogue_panel = _make_panel(Rect2(259, 630, 1148, 208), Color(0.98, 0.95, 0.88, 0.97), Color("#bca77d"), 16, "DialoguePaper")
	_make_label("师徒一席", Rect2(24, 10, 145, 20), 13, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "DialogueSectionLabel", false, _dialogue_panel)
	_speaker_label = _make_label("叶知闲", Rect2(23, 32, 151, 38), 25, JADE_DARK, HORIZONTAL_ALIGNMENT_LEFT, "DialogueSpeaker", false, _dialogue_panel)
	_speaker_role_label = _make_label("掌门 · 生活导师", Rect2(25, 71, 151, 27), 14, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "DialogueSpeakerRole", false, _dialogue_panel)
	var divider := ColorRect.new()
	divider.name = "DialogueDivider"
	divider.position = Vector2(188, 28)
	divider.size = Vector2(1, 151)
	divider.color = Color("#cfc1a4")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(divider)
	_dialogue_text_label = _make_label("", Rect2(209, 25, 408, 150), 22, INK, HORIZONTAL_ALIGNMENT_LEFT, "DialogueText", true, _dialogue_panel)
	_choice_host = Control.new()
	_choice_host.name = "ChoiceHost"
	_choice_host.position = Vector2(636, 20)
	_choice_host.size = Vector2(300, 164)
	_dialogue_panel.add_child(_choice_host)
	_advance_button = _make_button("往下听", Rect2(953, 97, 166, 55), "AdvanceButton", Callable(self, "_on_advance_pressed"), JADE, "", _dialogue_panel)
	_cancel_button = _make_button("收起 · Esc", Rect2(1028, 9, 93, 27), "CancelButton", Callable(self, "_on_cancel_pressed"), Color("#887963"), "", _dialogue_panel, true)


func _build_footer() -> void:
	_make_label("", Rect2(278, 853, 355, 30), 14, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT, "FooterCaption")
	_voice_toggle_button = _make_button("语音：开", Rect2(53, 205, 178, 45), "VoiceToggleButton", Callable(self, "_on_action_pressed").bind("voice_toggle"), JADE, "", null, true)
	# Dialogic owns a full-screen input layer while its timeline is active.
	# Keep this one persistent control above it, without covering the dialogue.
	_voice_layer = CanvasLayer.new()
	_voice_layer.name = "PersistentVoiceControls"
	_voice_layer.layer = 100
	add_child(_voice_layer)
	_voice_toggle_button.theme = _canvas.theme
	_voice_toggle_button.reparent(_voice_layer, false)
	set_voice_enabled(_voice_enabled)
	_footer_buttons["save"] = _make_button("存档", Rect2(1027, 851, 112, 39), "SaveButton", Callable(self, "_on_action_pressed").bind("save"), JADE, "", null, true)
	_footer_buttons["load"] = _make_button("读档", Rect2(1147, 851, 112, 39), "LoadButton", Callable(self, "_on_action_pressed").bind("load"), JADE, "", null, true)
	_footer_buttons["reset"] = _make_button("重置", Rect2(1267, 851, 112, 39), "ResetButton", Callable(self, "_on_action_pressed").bind("reset"), CINNABAR, "", null, true)


func _build_notice() -> void:
	_notice_panel = _make_panel(Rect2(493, 188, 490, 48), Color(0.97, 0.93, 0.84, 0.95), GOLD, 13, "NoticePanel")
	_notice_label = _make_label("", Rect2(18, 8, 455, 31), 16, JADE_DARK, HORIZONTAL_ALIGNMENT_CENTER, "NoticeLabel", true, _notice_panel)
	_notice_panel.visible = false


func _add_art(path: String, rect: Rect2, stretch: int, node_name: String, crop_transparency: bool = false) -> TextureRect:
	var texture := ResourceLoader.load(path) as Texture2D
	if texture != null and crop_transparency:
		texture = _crop_texture(texture)
	return _add_texture_art(texture, rect, stretch, node_name)


func _add_texture_art(texture: Texture2D, rect: Rect2, stretch: int, node_name: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = stretch
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = rect.position
	art.size = rect.size
	_canvas.add_child(art)
	return art


func _crop_texture(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var used_rect := image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return texture
	if used_rect.position == Vector2i.ZERO and used_rect.size == image.get_size():
		return texture
	return _make_atlas_texture(texture, used_rect)


func _make_atlas_texture(texture: Texture2D, region: Rect2i) -> AtlasTexture:
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(Vector2(region.position), Vector2(region.size))
	cropped.filter_clip = true
	return cropped


func _make_panel(rect: Rect2, fill: Color, border: Color, radius: int, node_name: String, parent: Control = null) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _panel_style(fill, border, radius, 1))
	(parent if parent != null else _canvas).add_child(panel)
	return panel


func _make_label(text: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment, node_name: String, wrap: bool = false, parent: Control = null) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.clip_text = not wrap
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(1.0, 0.96, 0.88, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _canvas).add_child(label)
	return label


func _make_button(text: String, rect: Rect2, node_name: String, callback: Callable, accent: Color, backend_id: String = "", parent: Control = null, compact: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18 if not compact else 15)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", JADE_DARK)
	button.add_theme_color_override("font_pressed_color", JADE_DARK)
	button.add_theme_color_override("font_disabled_color", Color("#a79d8e"))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.98, 0.94, 0.85, 0.94), Color("#c8b997"), 9, 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.92, 0.90, 0.79, 0.99), accent.lightened(0.1), 9, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.83, 0.86, 0.78, 0.99), accent, 9, 1))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.91, 0.87, 0.79, 0.9), Color("#d1c8b7"), 9, 1))
	button.pressed.connect(callback)
	(parent if parent != null else _canvas).add_child(button)
	if not backend_id.is_empty():
		button.set_meta("backend_id", backend_id)
	return button


func _panel_style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.18, 0.16, 0.12, 0.16)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _flat_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(0)
	style.set_corner_radius_all(24)
	return style


func _sync_canvas_layout() -> void:
	if not is_instance_valid(_canvas):
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * scale_factor
	_canvas.position = (viewport_size - DESIGN_SIZE * scale_factor) * 0.5
	if is_instance_valid(_voice_layer):
		_voice_layer.transform = _canvas.get_global_transform()


func _sync_status_labels() -> void:
	if _status_labels.is_empty():
		return
	_status_labels["day"].text = str(_status.get("day_label", "第一日 · 卯时"))
	_status_labels["energy"].text = "精力 %s" % str(_status.get("energy", "—"))
	_status_labels["cultivation"].text = "修为 %s" % str(_status.get("cultivation", "—"))
	_status_labels["lesson"].text = "口诀已领悟" if bool(_status.get("lesson_claimed", false)) else "口诀尚未领悟"
	_status_labels["busy"].text = "师徒正交谈…" if bool(_status.get("busy", false)) else "可自由行动"
	_status_labels["busy"].add_theme_color_override("font_color", CINNABAR if bool(_status.get("busy", false)) else JADE)
	_status_labels["hint"].text = str(_status.get("hint", "点师傅，聊聊刚才那一剑。"))


func set_voice_enabled(enabled: bool) -> void:
	_voice_enabled = enabled
	if not is_instance_valid(_voice_toggle_button):
		return
	_voice_toggle_button.text = "语音：开" if enabled else "语音：关"


func _sync_backend_buttons() -> void:
	if _backend_buttons.is_empty():
		return
	for backend_id in ["dm", "dialogic"]:
		var button := _backend_buttons[backend_id] as Button
		var accent := JADE if backend_id == "dm" else CINNABAR
		var selected: bool = backend_id == _backend_id
		button.add_theme_stylebox_override(
			"normal",
			_panel_style(Color(0.84, 0.90, 0.83, 1.0) if selected else Color(0.98, 0.94, 0.85, 0.94), accent if selected else Color("#c8b997"), 9, 2 if selected else 1)
		)
		button.add_theme_color_override("font_color", JADE_DARK if selected else INK)


func _sync_enabled_states() -> void:
	if _action_buttons.is_empty():
		return
	var busy := bool(_status.get("busy", false))
	for button_value in _backend_buttons.values():
		(button_value as Button).disabled = busy
	_action_buttons["talk"].disabled = busy
	_action_buttons["train"].disabled = busy
	_action_buttons["rest"].disabled = busy
	_mentor_button.disabled = busy
	_footer_buttons["save"].disabled = busy or not bool(_status.get("save_enabled", false))
	_footer_buttons["load"].disabled = busy or not bool(_status.get("load_enabled", false))
	_footer_buttons["reset"].disabled = busy
	_advance_button.disabled = not _dialogue_can_advance
	_cancel_button.disabled = false
	for entry in _choice_entries:
		var choice_button := entry.get("button") as Button
		choice_button.disabled = not bool(entry.get("enabled", true))


func _render_dialogue() -> void:
	if not is_instance_valid(_dialogue_panel):
		return
	_speaker_label.text = _dialogue_speaker
	_speaker_role_label.text = "本次结算" if _result_mode else "掌门 · 生活导师" if _dialogue_speaker == "叶知闲" else "听雨廊"
	_dialogue_text_label.text = _dialogue_text
	_advance_button.text = "继续" if _result_mode else "往下听"
	_advance_button.visible = _dialogue_can_advance
	_choice_host.visible = not _dialogue_choices.is_empty()
	_cancel_button.visible = true
	_clear_choices()
	var choice_count := _dialogue_choices.size()
	var separation := 7.0 if choice_count <= 3 else 4.0
	var choice_height := minf(48.0, (_choice_host.size.y - float(maxi(choice_count - 1, 0)) * separation) / float(maxi(choice_count, 1)))
	var total_height := float(choice_count) * choice_height + float(maxi(choice_count - 1, 0)) * separation
	var start_y := maxf(0.0, (_choice_host.size.y - total_height) * 0.5)
	for index in range(choice_count):
		var choice: Dictionary = _dialogue_choices[index]
		var choice_id := str(choice.get("id", "choice_%d" % index))
		var choice_label := str(choice.get("label", "继续"))
		var button := _make_button(
			choice_label,
			Rect2(Vector2.ZERO, Vector2(_choice_host.size.x, choice_height)),
			"Choice_%s" % _safe_name(choice_id),
			Callable(self, "_on_choice_pressed").bind(choice_id),
			JADE,
			"",
			_choice_host,
			true
		)
		button.position = Vector2(0, start_y + float(index) * (choice_height + separation))
		button.size = Vector2(_choice_host.size.x, choice_height)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var enabled := bool(choice.get("enabled", true))
		var choice_entry := {"id": choice_id, "label": choice_label, "enabled": enabled, "button": button}
		_choice_entries.append(choice_entry)
		button.disabled = not enabled


func _clear_choices() -> void:
	for child in _choice_host.get_children():
		_choice_host.remove_child(child)
		child.queue_free()
	_choice_entries.clear()


func _on_backend_pressed(backend_id: String) -> void:
	if bool(_status.get("busy", false)):
		return
	_backend_id = backend_id
	_sync_backend_buttons()
	backend_requested.emit(backend_id)


func _on_action_pressed(action_id: String) -> void:
	if action_id == "voice_toggle":
		action_requested.emit(action_id)
		return
	if bool(_status.get("busy", false)):
		return
	action_requested.emit(action_id)


func _on_advance_pressed() -> void:
	if not _dialogue_can_advance:
		return
	advance_requested.emit()


func _on_choice_pressed(choice_id: String) -> void:
	for entry in _choice_entries:
		if str(entry.get("id", "")) == choice_id and bool(entry.get("enabled", true)):
			choice_requested.emit(choice_id)
			return


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _global_rect(value: Variant) -> Rect2:
	if value is Control and is_instance_valid(value as Control):
		var control := value as Control
		return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	return Rect2()


func _safe_name(value: String) -> String:
	var safe := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character == "-":
			safe += character
		else:
			safe += "_"
	return safe if not safe.is_empty() else "choice"
