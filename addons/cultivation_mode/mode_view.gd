extends Control

const PackLoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript = preload("res://addons/cultivation_mode/session.gd")
const SaveStoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const MotionAssetsScript = preload("res://addons/cultivation_mode/motion_assets.gd")
const AtlasActorScript = preload("res://addons/cultivation_mode/atlas_actor.gd")
const VoicePlayerScript = preload("res://addons/cultivation_mode/voice_player.gd")

const CATALOG_PATH := "res://games/catalog.json"
const FONT_PATH := "res://assets/fonts/ShuCultivationEngineSerif.ttf"
const BASE_FONT_SIZE := 17

const INK := Color("#302d28")
const MUTED_INK := Color("#6b6257")
const PAPER := Color("#eee4d1")
const PAPER_LIGHT := Color("#f7f0e3")
const PAPER_DEEP := Color("#e4d7bf")
const BORDER := Color("#b8a889")
const TEAL := Color("#42675f")
const CINNABAR := Color("#9a4d3d")
const ERROR_RED := Color("#8c3e34")
const SUCCESS_GREEN := Color("#42675f")

@export var edition_label: String = "v0.1"
@export var save_base_dir: String = "user://cultivation_engine_v01"
@export var catalog_path: String = CATALOG_PATH

var _loader: RefCounted
var _store: RefCounted
var _catalog: Array[Dictionary] = []
var _selected_index: int = -1
var _active_index: int = -1
var _session: RefCounted
var _saved_revision: int = 0
var _view_mode: String = "library"
var _status_text: String = "本机存档 · 内容包各自独立"
var _status_is_error: bool = false
var _confirmation: Dictionary = {}
var _input_busy: bool = false
var _screen: Control
var _theme_resource: Theme
var _control_registry: Dictionary = {}
var _scene_surface: Control
var _actor_layouts: Array[Dictionary] = []
var _left_column: Control
var _right_column: Control
var _scene_panel: Control
var _scene_description: Label
var _object_layouts: Array[Dictionary] = []
var _object_popover: Control
var _selected_object_id: String = ""
var _selected_object_context_key: String = ""
var _selected_object_description: String = ""
var _selected_object_repeat: bool = false
var _body_margin: MarginContainer
var _presentation_player: Control
var _presentation_context_key: String = ""
var _presentation_motion_id: String = ""
var _presentation_phase_label: Label
var _presentation_error: String = ""
var _presentation_started_run_id: String = ""
var _presentation_started_operation_id: String = ""
var _presentation_failed_run_id: String = ""
var _presentation_failed_operation_id: String = ""
var _voice_player: Node
var _voice_configured_fingerprint: String = ""
var _voice_has_configuration: bool = false
var _voice_event_key: String = ""
var _voice_warning: String = ""
var _voice_warning_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE
	_loader = PackLoaderScript.new()
	_store = SaveStoreScript.new()
	_store.set("base_dir", save_base_dir)
	_voice_player = VoicePlayerScript.new() as Node
	_voice_player.name = "CultivationVoicePlayer"
	add_child(_voice_player)
	_theme_resource = _make_theme()
	_load_catalog()
	_render()


func _exit_tree() -> void:
	if is_instance_valid(_voice_player):
		_voice_player.call("stop", "scene_exit")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_responsive_sizes()
		call_deferred("_layout_scene_actors")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and is_instance_valid(_object_popover):
		var click_event := event as InputEventMouseButton
		# Let the release reach another prop before retiring this control tree.
		if not click_event.pressed and click_event.button_index == MOUSE_BUTTON_LEFT and not _object_popover.get_global_rect().has_point(click_event.position):
			call_deferred("_close_popover_if_unchanged", _object_popover.get_instance_id())
	if event is InputEventKey:
		var escape_event := event as InputEventKey
		if escape_event.pressed and not escape_event.echo and escape_event.keycode == KEY_ESCAPE and is_instance_valid(_object_popover):
			_close_object_popover()
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or _input_busy or _view_mode != "game":
		return
	if key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER and key_event.keycode != KEY_SPACE:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		return
	if _session == null:
		return
	if _is_quest_active():
		return
	var state: Dictionary = _snapshot()
	var phase := str(state.get("phase", ""))
	if phase == "performing":
		return
	if phase == "result":
		_acknowledge_result()
	elif phase == "event":
		var view: Dictionary = _session.call("event_view")
		var node_type := str(view.get("type", ""))
		if node_type == "say" or node_type == "end":
			_continue_event()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT or not is_instance_valid(_object_popover):
		return
	if _object_popover.get_global_rect().has_point(mouse_event.position):
		return
	_close_object_popover()


func _close_popover_if_unchanged(popover_instance_id: int) -> void:
	if is_instance_valid(_object_popover) and _object_popover.get_instance_id() == popover_instance_id:
		_close_object_popover()


func audit_snapshot() -> Dictionary:
	var rects: Dictionary = {}
	for control_name in _control_registry.keys():
		var control: Control = _control_registry[control_name] as Control
		if is_instance_valid(control) and control.is_visible_in_tree():
			rects[str(control_name)] = control.get_global_rect()
	if rects.has("SwitchPackButton"):
		rects["LibraryButton"] = rects["SwitchPackButton"]
	var state: Dictionary = _snapshot() if _session != null else {}
	var quest: Dictionary = _quest_view() if _session != null else {}
	var pack_id := ""
	var presentation: Dictionary = {}
	if _session != null:
		var pack: Dictionary = _session.get("pack")
		pack_id = str(pack.get("id", ""))
	if is_instance_valid(_presentation_player):
		presentation = _presentation_player.call("presentation_snapshot")
	return {
		"view_mode": _view_mode,
		"active_catalog_index": _active_index,
		"selected_catalog_index": _selected_index,
		"pack_id": pack_id,
		"state": state,
		"quest": quest,
		"selected_object": _selected_object_id,
		"ui_rects": rects,
		"status": _status_text,
		"presentation": presentation,
		"voice": _voice_player.call("audit") if is_instance_valid(_voice_player) else {},
		"voice_warning": _voice_warning,
	}


func audit_select_pack(index: int) -> Dictionary:
	if _is_performing():
		return {"ok": false, "reason": "动作演练结束前不能切换篇章。"}
	if index < 0 or index >= _catalog.size():
		return {"ok": false, "reason": "篇章索引无效。"}
	if _view_mode != "library":
		_show_library()
	_select_catalog_index(index)
	var entry: Dictionary = _catalog[index]
	return {
		"ok": bool(entry.get("ok", false)),
		"index": index,
		"pack": entry.get("pack", {}),
		"reason": str(entry.get("error", "")),
	}


func ui_control(control_name: String) -> Control:
	if control_name == "LibraryButton":
		control_name = "SwitchPackButton"
	var search_root: Node = _screen if is_instance_valid(_screen) else self
	var found: Node = search_root.find_child(control_name, true, false)
	return found as Control if found is Control else null


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE
	if ResourceLoader.exists(FONT_PATH):
		var font_resource: Resource = ResourceLoader.load(FONT_PATH)
		if font_resource is Font:
			theme.default_font = font_resource as Font
	return theme


func _load_catalog() -> void:
	_catalog.clear()
	if not _is_games_json_path(catalog_path):
		_set_status("篇章目录路径必须位于 games 目录内。", true)
		return
	if not FileAccess.file_exists(catalog_path):
		_set_status("暂时没有找到篇章目录。", true)
		return
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		_set_status("无法读取本机篇章目录。", true)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		_set_status("篇章目录格式无法读取。", true)
		return
	for raw_entry in parsed as Array:
		if not raw_entry is Dictionary:
			continue
		var catalog_row: Dictionary = raw_entry as Dictionary
		var manifest_path := str(catalog_row.get("manifest", "")).strip_edges()
		if not _is_games_json_path(manifest_path) or not manifest_path.ends_with("/game.json"):
			continue
		var load_result: Dictionary = _loader.call("load_pack", manifest_path)
		if bool(load_result.get("ok", false)):
			var loaded_pack: Dictionary = load_result.get("pack", {})
			_catalog.append({
				"manifest": manifest_path,
				"ok": true,
				"pack": loaded_pack,
				"catalog": catalog_row.duplicate(true),
				"error": "",
			})
		else:
			var errors := _string_array(load_result.get("errors", []))
			var error_text := "；".join(errors)
			_catalog.append({
				"manifest": manifest_path,
				"ok": false,
				"pack": {},
				"catalog": catalog_row.duplicate(true),
				"error": error_text if not error_text.is_empty() else "篇章资料未通过检查。",
			})
	if _catalog.is_empty():
		_set_status("篇章目录中没有可读取的内容。", true)
		return
	for index in range(_catalog.size()):
		var entry: Dictionary = _catalog[index]
		if bool(entry.get("ok", false)):
			_selected_index = index
			break
	if _selected_index < 0:
		_set_status("目录中的篇章目前都无法读取。", true)


func _render() -> void:
	var next_object_context := _object_context_key()
	if not _selected_object_id.is_empty() and next_object_context != _selected_object_context_key:
		_selected_object_id = ""
		_selected_object_context_key = ""
		_selected_object_description = ""
		_selected_object_repeat = false
	var next_context_key := _current_presentation_context_key()
	var can_preserve_player := _view_mode == "game" and next_context_key == _presentation_context_key
	if not can_preserve_player:
		_presentation_player = null
		_presentation_motion_id = ""
		_presentation_error = ""
		_presentation_started_run_id = ""
		_presentation_started_operation_id = ""
		_presentation_failed_run_id = ""
		_presentation_failed_operation_id = ""
	_presentation_context_key = next_context_key if _view_mode == "game" else ""
	_presentation_phase_label = null
	var old_screen := _screen
	if old_screen != null and is_instance_valid(old_screen):
		old_screen.visible = false
	var screen := Control.new()
	screen.name = "ModeViewScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = _theme_resource
	screen.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(screen)
	_screen = screen
	_control_registry.clear()
	_actor_layouts.clear()
	_object_layouts.clear()
	_object_popover = null

	var background := ColorRect.new()
	background.name = "PaperBackground"
	background.color = _current_paper_color()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(background)

	_body_margin = MarginContainer.new()
	_body_margin.name = "BodyMargin"
	_body_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body_margin.add_theme_constant_override("margin_left", _horizontal_margin())
	_body_margin.add_theme_constant_override("margin_right", _horizontal_margin())
	_body_margin.add_theme_constant_override("margin_top", 18)
	_body_margin.add_theme_constant_override("margin_bottom", 16)
	screen.add_child(_body_margin)

	var layout := VBoxContainer.new()
	layout.name = "PageLayout"
	layout.add_theme_constant_override("separation", 12)
	_body_margin.add_child(layout)
	layout.add_child(_build_header())
	if _view_mode == "game" and _session != null:
		layout.add_child(_build_game_view())
	else:
		layout.add_child(_build_library_view())
	_sync_presentation()
	_sync_responsive_sizes()
	call_deferred("_layout_scene_actors")

	if old_screen != null and is_instance_valid(old_screen):
		old_screen.queue_free()
	_sync_voice()


func _is_games_json_path(path: String) -> bool:
	return path.begins_with("res://games/") and path.ends_with(".json") and ".." not in path and "\\" not in path


func _sync_voice() -> void:
	if not is_instance_valid(_voice_player):
		return
	var has_active_session := _view_mode == "game" and _session != null
	if not has_active_session:
		_stop_voice("context_left", true)
		return

	var pack := _current_pack()
	var fingerprint := str(pack.get("_fingerprint", ""))
	if not _voice_has_configuration or fingerprint != _voice_configured_fingerprint:
		_voice_player.call("stop", "pack_changed")
		_voice_event_key = ""
		var voices_value: Variant = pack.get("voices", {})
		var voices: Dictionary = voices_value as Dictionary if voices_value is Dictionary else {}
		var configured: Variant = _voice_player.call("configure", voices)
		_voice_configured_fingerprint = fingerprint
		_voice_has_configuration = true
		var configure_result: Dictionary = configured as Dictionary if configured is Dictionary else {}
		if not bool(configure_result.get("ok", false)) and not voices.is_empty():
			_set_voice_warning("部分配音暂不可用，仍可阅读对白和继续行动。")
		else:
			_set_voice_warning("")

	if not _confirmation.is_empty():
		_stop_voice("confirmation", true)
		return

	var state := _snapshot()
	if str(state.get("phase", "")) != "event":
		_stop_voice("non_event", true)
		return
	var event_value: Variant = _session.call("event_view")
	if not event_value is Dictionary:
		_stop_voice("event_unavailable", true)
		return
	var event_view: Dictionary = event_value
	var node_type := str(event_view.get("type", ""))
	var voice_id := str(event_view.get("voice", ""))
	if (node_type != "say" and node_type != "choice") or voice_id.is_empty():
		_stop_voice("unvoiced_node", true)
		return

	var run_id := str(state.get("run_id", ""))
	var event_id := str(event_view.get("event_id", ""))
	var node_id := str(event_view.get("node_id", ""))
	var event_key := "%s|%s|%s|%s" % [fingerprint, run_id, event_id, node_id]
	if event_key == _voice_event_key:
		return
	_voice_player.call("stop", "node_changed")
	_voice_event_key = event_key
	if not bool(_voice_player.call("is_voice_enabled")):
		return

	var speaker_id := str(event_view.get("speaker", ""))
	var spoken_text := str(event_view.get("text", ""))
	var played_value: Variant = _voice_player.call("play_clip", voice_id, speaker_id, spoken_text)
	var played: Dictionary = played_value as Dictionary if played_value is Dictionary else {}
	if not bool(played.get("ok", false)):
		_set_voice_warning("这句配音暂不可用，仍可阅读对白和继续行动。")


func _stop_voice(reason: String, clear_event_key: bool) -> void:
	if is_instance_valid(_voice_player):
		_voice_player.call("stop", reason)
	if clear_event_key:
		_voice_event_key = ""


func _set_voice_warning(message: String) -> void:
	_voice_warning = message
	if is_instance_valid(_voice_warning_label):
		_voice_warning_label.text = message
		_voice_warning_label.visible = _view_mode == "game" and not message.is_empty()


func _sync_presentation() -> void:
	if not _is_performing():
		return
	var pending_value: Variant = _session.call("pending_presentation")
	if not pending_value is Dictionary:
		_set_presentation_error("当前没有可播放的动作包。", true)
		return
	var pending: Dictionary = pending_value
	var pending_run_id := str(pending.get("run_id", ""))
	var pending_operation_id := str(pending.get("operation_id", ""))
	if pending_run_id.is_empty() or pending_operation_id.is_empty():
		_set_presentation_error("当前动作身份无效，回报尚未完成。", true)
		return
	if not is_instance_valid(_presentation_player):
		_set_presentation_error("场景中的动作人物无法载入；本次结算已保留。", true)
		return
	if pending_run_id == _presentation_failed_run_id and pending_operation_id == _presentation_failed_operation_id:
		return
	if pending_run_id != _presentation_started_run_id or pending_operation_id != _presentation_started_operation_id:
		_presentation_started_run_id = pending_run_id
		_presentation_started_operation_id = pending_operation_id
		var play_result: Dictionary = _presentation_player.call("play_presentation", pending)
		if not bool(play_result.get("ok", false)):
			_presentation_failed_run_id = pending_run_id
			_presentation_failed_operation_id = pending_operation_id
			_set_presentation_error(str(play_result.get("reason", "动作资源无法播放。")), true)
			return
	var playback: Dictionary = _presentation_player.call("presentation_snapshot")
	_on_presentation_phase_changed(str(playback.get("phase", "settle")), str(playback.get("phase_label", "准备")))


func _on_presentation_phase_changed(phase: String, label: String) -> void:
	if not is_instance_valid(_presentation_phase_label):
		return
	var phase_text := label
	if phase_text.is_empty():
		match phase:
			"settle":
				phase_text = "准备"
			"action":
				phase_text = "演练"
			"neutral_hold":
				phase_text = "回到静息"
			_:
				phase_text = "静息"
	_presentation_phase_label.text = "当前阶段：%s" % phase_text


func _on_presentation_finished(run_id: String, operation_id: String) -> void:
	if not is_instance_valid(_presentation_player) or _session == null:
		return
	var playback: Dictionary = _presentation_player.call("presentation_snapshot")
	if bool(playback.get("playing", true)) or not bool(playback.get("neutral", false)):
		return
	if str(playback.get("run_id", "")) != run_id or str(playback.get("operation_id", "")) != operation_id:
		return
	var pending_value: Variant = _session.call("pending_presentation")
	if not pending_value is Dictionary:
		return
	var pending: Dictionary = pending_value
	if str(pending.get("run_id", "")) != run_id or str(pending.get("operation_id", "")) != operation_id:
		return
	var result: Dictionary = _session.call("finish_presentation", run_id, operation_id)
	if not bool(result.get("ok", false)):
		_presentation_failed_run_id = run_id
		_presentation_failed_operation_id = operation_id
		_set_presentation_error(str(result.get("reason", "动作回报尚未完成。")), true)
		return
	_presentation_error = ""
	_presentation_failed_run_id = ""
	_presentation_failed_operation_id = ""
	_set_status("动作完成，实际回报已记入行旅。")
	_render()


func _set_presentation_error(reason: String, recovery: bool) -> void:
	var message := reason if not reason.is_empty() else "动作演练无法继续。"
	_set_status(message, true)
	var status_label := ui_control("StatusLabel")
	if is_instance_valid(status_label) and status_label is Label:
		(status_label as Label).text = message
		(status_label as Label).add_theme_color_override("font_color", ERROR_RED)
	if recovery:
		_presentation_error = message
		if is_instance_valid(_presentation_phase_label):
			_presentation_phase_label.text = "动作已结算，画面尚未完成：%s" % message
			var panel_content := _presentation_phase_label.get_parent() as VBoxContainer
			if panel_content != null and panel_content.get_node_or_null("PresentationRecoveryError") == null:
				panel_content.add_child(_make_label(message, 14, ERROR_RED, true, "PresentationRecoveryError"))


func _build_header() -> PanelContainer:
	var header := PanelContainer.new()
	header.name = "HeaderPanel"
	header.custom_minimum_size.y = 90
	header.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 8, 1))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	header.add_child(content)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	content.add_child(top_row)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	top_row.add_child(title_column)
	var eyebrow := "养成引擎 %s · 内容库" % edition_label if _view_mode == "library" else ("养成引擎 %s · 物件支线" % edition_label if _is_quest_active() else "养成引擎 %s · 固定场景" % edition_label)
	title_column.add_child(_make_label(eyebrow, 14, MUTED_INK, false))
	var title_text := "选择一段新旅程" if _view_mode == "library" else _current_title()
	title_column.add_child(_make_label(title_text, 26, INK, false))
	if _view_mode == "game" and _session != null:
		var performing := _is_performing()
		var clock_label := _clock_and_location_text()
		top_row.add_child(_make_label(clock_label, 16, TEAL, false))
		var library_button := _make_button("切换篇章", "SwitchPackButton", Callable(self, "_show_library"), performing)
		library_button.custom_minimum_size.x = 78
		top_row.add_child(library_button)
		var can_save := bool(_session.call("can_save")) and not performing
		var save_button := _make_button("存档", "SaveButton", Callable(self, "_save_current"), not can_save or not _confirmation.is_empty())
		save_button.tooltip_text = "动作演练结束后才能保存本机进度。" if performing else ("请先结束当前对话，再保存本机进度。" if not can_save else "把当前进度保存到本机")
		save_button.custom_minimum_size.x = 68
		top_row.add_child(save_button)
		var has_save := bool(_store.call("has_save", _current_pack()))
		var load_button := _make_button("读档", "LoadButton", Callable(self, "_request_load_current"), performing or not has_save or not _confirmation.is_empty())
		load_button.tooltip_text = "读档会以本机存档替换当前进度。" if has_save else "这个篇章还没有本机存档。"
		load_button.custom_minimum_size.x = 68
		top_row.add_child(load_button)
		var new_button := _make_button("新开局", "NewRunButton", Callable(self, "_request_new_run"), performing or not _confirmation.is_empty())
		new_button.tooltip_text = "重新开始这段修行；已有进度会先询问。"
		new_button.custom_minimum_size.x = 76
		top_row.add_child(new_button)
		if _active_pack_has_voices():
			var voice_button := _make_button(_voice_toggle_text(), "VoiceToggleButton", Callable(self, "_toggle_voice"))
			voice_button.custom_minimum_size.x = 88
			top_row.add_child(voice_button)
	elif _session != null:
		var return_button := _make_button("回到当前修行", "ReturnToSessionButton", Callable(self, "_return_to_session"), _is_performing() or not _confirmation.is_empty())
		top_row.add_child(return_button)
	content.add_child(_make_label(_status_text, 14, ERROR_RED if _status_is_error else MUTED_INK, true, "StatusLabel"))
	_voice_warning_label = _make_label(_voice_warning, 12, CINNABAR, true, "VoiceWarningLabel")
	_voice_warning_label.visible = _view_mode == "game" and not _voice_warning.is_empty()
	content.add_child(_voice_warning_label)
	return header


func _build_library_view() -> Control:
	var page := VBoxContainer.new()
	page.name = "LibraryView"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	var intro := PanelContainer.new()
	intro.name = "LibraryIntro"
	intro.add_theme_stylebox_override("panel", _panel_style(PAPER_DEEP, BORDER, 8, 1))
	var intro_content := VBoxContainer.new()
	intro_content.add_theme_constant_override("separation", 4)
	intro.add_child(intro_content)
	intro_content.add_child(_make_label("两种生活，同一套养成规则引擎。", 21, INK, true))
	intro_content.add_child(_make_label("可从新局开始，也可读取本机存档；切换篇章时，尚未保存的进度会先询问。", 15, MUTED_INK, true))
	if _confirmation.is_empty():
		page.add_child(intro)
	else:
		page.add_child(_build_confirmation_panel("LibraryConfirmation"))
		page.add_child(intro)

	var cards_scroll := ScrollContainer.new()
	cards_scroll.name = "PackCardsScroll"
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(cards_scroll)
	var grid := GridContainer.new()
	grid.name = "PackCards"
	grid.columns = 2 if get_viewport_rect().size.x >= 880.0 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	cards_scroll.add_child(grid)
	for index in range(_catalog.size()):
		grid.add_child(_build_pack_card(index))
	if _catalog.is_empty():
		var empty := PanelContainer.new()
		empty.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 8, 1))
		empty.add_child(_make_label("内容目录尚未就绪。请稍后再来。", 18, MUTED_INK, true))
		grid.add_child(empty)
	return page


func _build_pack_card(index: int) -> PanelContainer:
	var entry: Dictionary = _catalog[index]
	var pack: Dictionary = entry.get("pack", {})
	var valid := bool(entry.get("ok", false))
	var accent := _pack_accent(pack)
	var card := PanelContainer.new()
	card.name = "PackCard_%d" % index
	card.custom_minimum_size = Vector2(350, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected := index == _selected_index
	card.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, accent if selected else BORDER, 9, 2 if selected else 1))
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	card.add_child(contents)
	var title := str(pack.get("title", "篇章暂不可用")) if valid else "篇章暂不可用"
	var subtitle := str(pack.get("subtitle", "")) if valid else str(entry.get("error", ""))
	var select_button := _make_button(title, "PackSelectButton_%d" % index, Callable(self, "_select_catalog_index").bind(index), not valid or not _confirmation.is_empty())
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.custom_minimum_size.y = 54
	select_button.add_theme_font_size_override("font_size", 21)
	select_button.tooltip_text = "选择《%s》" % title
	contents.add_child(select_button)
	contents.add_child(_make_label(subtitle, 15, MUTED_INK, true))
	if valid:
		var scene_catalog: Dictionary = pack.get("scenes", {})
		var starting_scene: Dictionary = scene_catalog.get(pack.get("initial_scene", ""), {})
		var cover_path: String = str(starting_scene.get("background", ""))
		if not cover_path.is_empty():
			var cover := TextureRect.new()
			cover.name = "PackCover_%d" % index
			cover.texture = load(cover_path) as Texture2D
			cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			cover.custom_minimum_size.y = 180
			cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
			contents.add_child(cover)
		contents.add_child(_make_label(str(pack.get("description", "")), 15, INK, true))
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 8)
		contents.add_child(footer)
		var save_hint := "已有本机存档" if bool(_store.call("has_save", pack)) else "尚无本机存档"
		var save_hint_label := _make_label(save_hint, 14, TEAL if save_hint.begins_with("已有") else MUTED_INK, false)
		save_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(save_hint_label)
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 8)
		action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		contents.add_child(action_row)
		var start_button := _make_button("开始新局", "PackStartButton_%d" % index, Callable(self, "_request_pack_start").bind(index), not _confirmation.is_empty())
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(start_button)
		var continue_button := _make_button("继续", "PackContinueButton_%d" % index, Callable(self, "_request_pack_continue").bind(index), not bool(_store.call("has_save", pack)) or not _confirmation.is_empty())
		continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		continue_button.tooltip_text = "读取此篇章的本机存档" if not continue_button.disabled else "这个篇章还没有本机存档。"
		action_row.add_child(continue_button)
	else:
		contents.add_child(_make_label("检查讯息：%s" % str(entry.get("error", "篇章无法载入。")), 14, ERROR_RED, true))
	return card


func _build_game_view() -> Control:
	if _is_quest_active():
		var viewport_width := get_viewport_rect().size.x
		var quest_body: Control
		if viewport_width < 850.0:
			var stacked := VBoxContainer.new()
			stacked.name = "QuestColumnsStacked"
			stacked.add_theme_constant_override("separation", 10)
			quest_body = stacked
		else:
			var columns := HBoxContainer.new()
			columns.name = "QuestColumns"
			columns.add_theme_constant_override("separation", 14)
			quest_body = columns
		quest_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_left_column = null
		var quest_center := _build_scene_column()
		quest_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quest_body.add_child(quest_center)
		_right_column = _build_quest_column(_quest_view())
		if viewport_width < 850.0:
			_right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			_right_column.custom_minimum_size.x = 248
		quest_body.add_child(_right_column)
		return quest_body

	var body := HBoxContainer.new()
	body.name = "CultivationColumns"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_left_column = _build_information_column()
	body.add_child(_left_column)
	var center := _build_scene_column()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_right_column = _build_action_column()
	body.add_child(_right_column)
	return body


func _build_quest_column(quest: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "QuestSidebarScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_theme_constant_override("separation", 9)
	if not _confirmation.is_empty():
		column.add_child(_build_confirmation_panel("InlineConfirmation"))
	column.add_child(_build_quest_progress_panel(quest))
	column.add_child(_build_stats_panel())
	column.add_child(_build_quest_receipt_panel())
	var rest_action_id := str(quest.get("rest_action", ""))
	if not rest_action_id.is_empty():
		var action := _available_action(rest_action_id)
		var rest_panel := _titled_panel("支线内歇息", "QuestRestPanel")
		var rest_body := _panel_body(rest_panel)
		rest_body.add_child(_make_label(str(action.get("description", "暂歇片刻，再继续查看。")), 14, MUTED_INK, true))
		var rest_details := _action_preview_text(action) if not action.is_empty() else "依照本篇章的歇息规则恢复精力。"
		var rest_button := _make_button(
			"歇息片刻 · %s" % rest_details,
			"QuestRestButton",
			Callable(self, "_run_quest_action").bind(rest_action_id, _snapshot().get("run_id", ""), int(_snapshot().get("revision", -1))),
			action.is_empty() or not bool(action.get("enabled", false)) or _input_busy or _is_performing()
		)
		rest_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rest_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rest_button.tooltip_text = str(action.get("reason", action.get("description", "支线内歇息")))
		rest_body.add_child(rest_button)
		column.add_child(rest_panel)
	if bool(quest.get("complete", false)):
		var return_action_id := str(quest.get("return_action", ""))
		var return_action := _available_action(return_action_id)
		var return_enabled := not return_action_id.is_empty() and bool(quest.get("complete", false))
		var return_button := _make_button(
			str(return_action.get("label", "返回修行")),
			"QuestReturnButton",
			Callable(self, "_run_quest_action").bind(return_action_id, _snapshot().get("run_id", ""), int(_snapshot().get("revision", -1))),
			not return_enabled or _input_busy or _is_performing()
		)
		return_button.custom_minimum_size.y = 52
		column.add_child(return_button)
	return scroll


func _build_quest_progress_panel(quest: Dictionary) -> PanelContainer:
	var panel := _titled_panel(str(quest.get("title", "当前支线")), "QuestProgressPanel")
	var body := _panel_body(panel)
	body.add_child(_make_label("当前阶段 · %s" % str(quest.get("stage_label", "继续调查")), 15, INK, true))
	var completed_stages: Variant = quest.get("completed_stages", [])
	var stage_count: int = (completed_stages as Array).size() if completed_stages is Array else 0
	var progress_text := "已查看 %d / %d 件物件 · 完成 %d 个阶段" % [int(quest.get("seen", 0)), int(quest.get("total", 0)), stage_count]
	body.add_child(_make_label(progress_text, 14, MUTED_INK, true))
	var total := maxi(1, int(quest.get("total", 0)))
	var progress := ProgressBar.new()
	progress.name = "QuestObjectProgress"
	progress.custom_minimum_size.y = 11
	progress.min_value = 0
	progress.max_value = total
	progress.value = clampi(int(quest.get("seen", 0)), 0, total)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _plain_bar_style(PAPER_DEEP))
	progress.add_theme_stylebox_override("fill", _plain_bar_style(TEAL))
	body.add_child(progress)
	if bool(quest.get("stage_complete", false)) and not bool(quest.get("complete", false)):
		var boundary_text := str(quest.get("boundary_text", ""))
		if not boundary_text.is_empty():
			var boundary := PanelContainer.new()
			boundary.name = "QuestBoundaryNotice"
			boundary.add_theme_stylebox_override("panel", _panel_style(Color("#f3ead7"), BORDER, 5, 1, 9))
			boundary.add_child(_make_label(boundary_text, 14, MUTED_INK, true))
			body.add_child(boundary)
	return panel


func _build_quest_receipt_panel() -> PanelContainer:
	var panel := _titled_panel("刚才留下的札记", "QuestReceiptPanel")
	var body := _panel_body(panel)
	var state := _snapshot()
	var receipt: Dictionary = state.get("last_result", {})
	if bool(receipt.get("ok", false)):
		body.add_child(_make_label(str(receipt.get("action_label", "物件调查")), 14, TEAL, false))
		body.add_child(_make_label(str(receipt.get("message", "这一刻已记入札记。")), 15, INK, true))
		body.add_child(_make_label(_receipt_summary(receipt), 13, MUTED_INK, true))
		var journal: Variant = state.get("journal", [])
		if journal is Array and not (journal as Array).is_empty():
			body.add_child(_make_label(_journal_text((journal as Array)[(journal as Array).size() - 1]), 13, MUTED_INK, true))
	else:
		body.add_child(_make_label("查看与阅读会直接留在札记中。", 14, MUTED_INK, true))
	return panel


func _build_information_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "InformationColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	column.add_child(_build_stats_panel())
	column.add_child(_build_goals_panel())
	column.add_child(_build_journal_panel())
	return column


func _build_stats_panel() -> PanelContainer:
	var panel := _titled_panel("人物状态", "StatsPanel")
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	_panel_body(panel).add_child(rows)
	var pack := _current_pack()
	var state := _snapshot()
	var rules: Dictionary = pack.get("rules", {})
	var stat_definitions: Array = rules.get("stats", [])
	var state_stats: Dictionary = state.get("stats", {})
	if stat_definitions.is_empty():
		rows.add_child(_make_label("尚未设置人物状态。", 15, MUTED_INK, true))
	for raw_stat in stat_definitions:
		if not raw_stat is Dictionary:
			continue
		var stat: Dictionary = raw_stat as Dictionary
		var stat_id := str(stat.get("id", ""))
		var value := _number(state_stats.get(stat_id, stat.get("initial", 0)))
		var minimum := _number(stat.get("min", 0))
		var maximum := _number(stat.get("max", 100))
		var stat_row := VBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 2)
		rows.add_child(stat_row)
		var title_row := HBoxContainer.new()
		stat_row.add_child(title_row)
		title_row.add_child(_make_label(str(stat.get("label", stat_id)), 16, INK, false))
		var value_label := _make_label("%s / %s" % [_format_number(value), _format_number(maximum)], 15, MUTED_INK, false)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(value_label)
		var bar := ProgressBar.new()
		bar.name = "StatProgress_%s" % _safe_name(stat_id)
		bar.custom_minimum_size.y = 12
		bar.min_value = minimum
		bar.max_value = maxf(maximum, minimum + 1.0)
		bar.value = clampf(value, minimum, maximum)
		bar.show_percentage = false
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = PAPER_DEEP
		bar_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("background", bar_style)
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = _color_from_data(str(stat.get("color", "")), TEAL)
		fill_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("fill", fill_style)
		stat_row.add_child(bar)
	return panel


func _build_goals_panel() -> PanelContainer:
	var panel := _titled_panel("眼前目标", "GoalsPanel")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	_panel_body(panel).add_child(body)
	var rules: Dictionary = _current_pack().get("rules", {})
	var goals: Array = rules.get("goals", [])
	var state := _snapshot()
	var stats: Dictionary = state.get("stats", {})
	var flags: Dictionary = state.get("flags", {})
	if goals.is_empty():
		body.add_child(_make_label("暂无特别目标，依照自己的节奏修行。", 15, MUTED_INK, true))
	for raw_goal in goals:
		if not raw_goal is Dictionary:
			continue
		var goal: Dictionary = raw_goal as Dictionary
		var stat_id := str(goal.get("stat", ""))
		var target := _number(goal.get("target", 0))
		var current := _number(stats.get(stat_id, 0))
		var done := bool(flags.get(str(goal.get("completion_flag", "")), false))
		var goal_label := str(goal.get("label", "继续修行"))
		var detail := "已达成" if done else "%s / %s" % [_format_number(current), _format_number(target)]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		body.add_child(row)
		var goal_text := _make_label(goal_label, 15, INK, true)
		goal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(goal_text)
		row.add_child(_make_label(detail, 14, TEAL if done else MUTED_INK, false))
		if not done and target > 0:
			var progress := ProgressBar.new()
			progress.name = "GoalProgress_%s" % _safe_name(str(goal.get("id", "goal")))
			progress.custom_minimum_size.y = 10
			progress.min_value = 0
			progress.max_value = target
			progress.value = clampf(current, 0.0, target)
			progress.show_percentage = false
			progress.add_theme_stylebox_override("background", _plain_bar_style(PAPER_DEEP))
			progress.add_theme_stylebox_override("fill", _plain_bar_style(CINNABAR))
			body.add_child(progress)
	return panel


func _build_journal_panel() -> PanelContainer:
	var panel := _titled_panel("行旅札记", "JournalPanel")
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "JournalScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body(panel).add_child(scroll)
	var entries_box := VBoxContainer.new()
	entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_box.add_theme_constant_override("separation", 6)
	scroll.add_child(entries_box)
	var state := _snapshot()
	var journal: Array = state.get("journal", [])
	var hidden_operation_id := ""
	if str(state.get("phase", "")) == "performing":
		var pending_value: Variant = _session.call("pending_presentation")
		if pending_value is Dictionary:
			hidden_operation_id = str((pending_value as Dictionary).get("operation_id", ""))
	var visible_indices: Array[int] = []
	for index in range(journal.size()):
		var item_value: Variant = journal[index]
		if hidden_operation_id.is_empty() or not item_value is Dictionary or str((item_value as Dictionary).get("operation_id", "")) != hidden_operation_id:
			visible_indices.append(index)
	if visible_indices.is_empty():
		entries_box.add_child(_make_label("落笔处仍是空白。", 14, MUTED_INK, true))
	else:
		var start := maxi(0, visible_indices.size() - 8)
		for list_index in range(visible_indices.size() - 1, start - 1, -1):
			var item: Variant = journal[visible_indices[list_index]]
			var journal_label := _make_label(_journal_text(item), 14, INK, true)
			journal_label.custom_minimum_size.y = 34
			entries_box.add_child(journal_label)
	return panel


func _build_scene_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "SceneColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	var scene_info := _current_scene()
	var scene_heading := HBoxContainer.new()
	scene_heading.name = "SceneHeading"
	column.add_child(scene_heading)
	var scene_title := _make_label(str(scene_info.get("label", "眼前景致")), 21, INK, false)
	scene_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_heading.add_child(scene_title)
	scene_heading.add_child(_make_label("点击物件查看" if _is_quest_active() else "固定场景 · 按行动缓缓向前", 14, MUTED_INK, false))
	_scene_panel = PanelContainer.new()
	_scene_panel.name = "ScenePanel"
	_register_control(_scene_panel)
	_scene_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_panel.add_theme_stylebox_override("panel", _panel_style(PAPER_DEEP, _scene_accent(scene_info), 8, 1))
	column.add_child(_scene_panel)
	_scene_surface = Control.new()
	_scene_surface.name = "SceneSurface"
	_register_control(_scene_surface)
	_scene_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	_scene_surface.clip_contents = true
	_scene_surface.resized.connect(_layout_scene_actors)
	_scene_panel.add_child(_scene_surface)
	_build_scene_surface(scene_info)
	_scene_description = _make_label(str(scene_info.get("description", "")), 15, MUTED_INK, true, "SceneDescription")
	_scene_description.custom_minimum_size.y = 32
	column.add_child(_scene_description)
	column.add_child(_build_phase_panel())
	return column


func _build_scene_surface(scene_info: Dictionary) -> void:
	var backdrop := TextureRect.new()
	backdrop.name = "SceneBackground"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if _is_quest_active() else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_path := str(scene_info.get("background", ""))
	if not background_path.is_empty():
		var image_resource: Resource = ResourceLoader.load(background_path)
		if image_resource is Texture2D:
			backdrop.texture = image_resource as Texture2D
	_scene_surface.add_child(backdrop)
	var layers: Array = scene_info.get("layers", [])
	for layer_index in range(layers.size()):
		var raw_layer: Variant = layers[layer_index]
		if not raw_layer is Dictionary:
			continue
		var layer: Dictionary = raw_layer as Dictionary
		var layer_path := str(layer.get("texture", ""))
		if layer_path.is_empty():
			continue
		var layer_resource: Resource = ResourceLoader.load(layer_path)
		if not layer_resource is Texture2D:
			continue
		var layer_rect := TextureRect.new()
		layer_rect.name = "SceneLayer_%d" % layer_index
		layer_rect.texture = layer_resource as Texture2D
		layer_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if _is_quest_active() else TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_surface.add_child(layer_rect)
	var shade := ColorRect.new()
	shade.name = "SceneTone"
	shade.color = Color(0.16, 0.18, 0.17, 0.11)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_surface.add_child(shade)
	var corner := PanelContainer.new()
	corner.name = "SceneNameCard"
	corner.position = Vector2(12, 12)
	corner.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.93, 0.84, 0.90), _scene_accent(scene_info), 5, 1))
	var corner_label := _make_label(str(scene_info.get("label", "眼前景致")), 14, INK, false)
	corner.add_child(corner_label)
	_scene_surface.add_child(corner)
	var characters: Dictionary = _current_pack().get("characters", {})
	var actors: Array = scene_info.get("actors", [])
	var actor_ids: Dictionary = {}
	for raw_actor in actors:
		if not raw_actor is Dictionary:
			continue
		var actor: Dictionary = raw_actor as Dictionary
		var character_id := str(actor.get("character", ""))
		if character_id.is_empty():
			continue
		actor_ids[character_id] = true
		var character: Dictionary = characters.get(character_id, {})
		_add_scene_actor(character_id, character, actor)
	var present: Array = scene_info.get("present", [])
	var card_index := _text_card_count()
	for raw_character_id in present:
		var character_id := str(raw_character_id)
		if actor_ids.has(character_id):
			continue
		var character: Dictionary = characters.get(character_id, {})
		_add_text_character_card(character_id, character, card_index)
		card_index += 1
	var foreground: Variant = scene_info.get("foreground", {})
	if foreground is Dictionary:
		_add_scene_foreground(foreground as Dictionary)
	if _is_quest_active():
		_build_quest_objects()
		if not _selected_object_id.is_empty():
			_build_object_popover()


func _build_quest_objects() -> void:
	if _session == null or not _session.has_method("available_objects"):
		return
	var available_value: Variant = _session.call("available_objects")
	if not available_value is Array:
		return
	for raw_object in available_value as Array:
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = raw_object as Dictionary
		var object_id := str(object.get("id", ""))
		if object_id.is_empty():
			continue
		var object_rect := _normalized_rect(object.get("rect", []))
		if object_rect.size.x <= 0.0 or object_rect.size.y <= 0.0:
			var anchor := _normalized_point(object.get("anchor", []), Vector2(0.5, 0.5))
			object_rect = Rect2(anchor.x - 0.035, anchor.y - 0.045, 0.07, 0.09)
		var control_name := "Object_%s" % _safe_control_name(object_id)
		var button := Button.new()
		button.name = control_name
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = not bool(object.get("enabled", false)) or _is_performing() or _input_busy
		button.tooltip_text = str(object.get("label", object_id))
		if not bool(object.get("enabled", false)):
			button.tooltip_text += " · " + str(object.get("reason", "目前尚不能查看。"))
		var transparent := StyleBoxFlat.new()
		transparent.bg_color = Color(0, 0, 0, 0)
		transparent.border_color = Color(0, 0, 0, 0)
		transparent.set_border_width_all(0)
		transparent.set_content_margin_all(0)
		var hovered := StyleBoxFlat.new()
		hovered.bg_color = Color(0.95, 0.89, 0.72, 0.08)
		hovered.border_color = Color(0.62, 0.48, 0.30, 0.72)
		hovered.set_border_width_all(1)
		hovered.set_corner_radius_all(5)
		hovered.set_content_margin_all(0)
		button.add_theme_stylebox_override("normal", transparent)
		button.add_theme_stylebox_override("hover", hovered)
		button.add_theme_stylebox_override("pressed", hovered)
		button.add_theme_stylebox_override("disabled", transparent)
		_register_control(button)
		button.pressed.connect(Callable(self, "_inspect_quest_object").bind(object_id, str(_snapshot().get("run_id", "")), int(_snapshot().get("revision", -1))))
		var texture_path := str(object.get("texture", ""))
		if not texture_path.is_empty():
			var texture_resource: Resource = ResourceLoader.load(texture_path)
			if texture_resource is Texture2D:
				var prop := TextureRect.new()
				prop.name = "ObjectTexture_%s" % _safe_control_name(object_id)
				prop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var region: Rect2i = _pixel_region(object.get("region", []))
				if region.size.x > 0 and region.size.y > 0:
					prop.texture = _make_atlas_texture(texture_resource as Texture2D, region)
				else:
					prop.texture = texture_resource as Texture2D
				button.add_child(prop)
		else:
			button.text = str(object.get("label", "物件"))
			button.add_theme_font_size_override("font_size", 12)
		var marker := _make_label("✓" if bool(object.get("inspected", false)) else "·", 16 if bool(object.get("inspected", false)) else 20, TEAL if bool(object.get("inspected", false)) else Color("#776c5b"), false)
		marker.name = "ObjectMarker_%s" % _safe_control_name(object_id)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		marker.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		marker.position = Vector2(-20, -13)
		marker.size = Vector2(22, 22)
		button.add_child(marker)
		_scene_surface.add_child(button)
		_object_layouts.append({
			"button": button,
			"id": object_id,
			"rect": object_rect,
			"anchor": _normalized_point(object.get("anchor", []), object_rect.get_center()),
			"inspected": bool(object.get("inspected", false)),
		})
	if not _selected_object_id.is_empty() and not _find_available_object(_selected_object_id).is_empty():
		return
	if not _selected_object_id.is_empty():
		_selected_object_id = ""
		_selected_object_context_key = ""
		_selected_object_description = ""
		_selected_object_repeat = false


func _build_object_popover() -> void:
	var object := _find_available_object(_selected_object_id)
	if object.is_empty():
		return
	var panel := PanelContainer.new()
	panel.name = "ObjectPopover"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, _scene_accent(_current_scene()), 7, 2, 10))
	_scene_surface.add_child(panel)
	_object_popover = panel
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	panel.add_child(outer)
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	var title := _make_label(str(object.get("label", "物件")), 18, INK, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_make_button("收起", "ObjectCloseButton", Callable(self, "_close_object_popover")))
	var scroll := ScrollContainer.new()
	scroll.name = "ObjectPopoverScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 7)
	scroll.add_child(contents)
	var description := _selected_object_description if not _selected_object_description.is_empty() else str(object.get("description", ""))
	contents.add_child(_make_label(description, 15, INK, true, "ObjectDescription"))
	if bool(object.get("inspected", false)):
		contents.add_child(_make_label("已查看 · 可再次阅读", 12, MUTED_INK, false))
	if _selected_object_repeat:
		contents.add_child(_make_label("再看不消耗精力或时辰。", 12, MUTED_INK, false))
	var actions_value: Variant = object.get("actions", [])
	if actions_value is Array:
		for raw_action in actions_value as Array:
			if not raw_action is Dictionary:
				continue
			var action: Dictionary = raw_action as Dictionary
			var action_id := str(action.get("id", ""))
			if action_id.is_empty():
				continue
			var details := _object_action_preview(action)
			var action_button := _make_button(
				"%s\n%s" % [str(action.get("label", "行动")), details],
				"ObjectAction_%s" % _safe_control_name(action_id),
				Callable(self, "_execute_quest_object_action").bind(
					_selected_object_id,
					action_id,
					str(_snapshot().get("run_id", "")),
					int(_snapshot().get("revision", -1))
				),
				not bool(action.get("enabled", false)) or _input_busy or _is_performing()
			)
			action_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			action_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			action_button.tooltip_text = str(action.get("reason", action.get("description", "")))
			contents.add_child(action_button)
	if actions_value is Array and (actions_value as Array).is_empty():
		contents.add_child(_make_label("查看内容已留在札记中。", 13, MUTED_INK, true))
	_object_popover.custom_minimum_size = Vector2(260, 188)
	_object_popover.size = Vector2(300, 220)
	call_deferred("_layout_object_popover")


func _object_action_preview(action: Dictionary) -> String:
	var parts: Array[String] = []
	var costs: Dictionary = action.get("costs", {})
	var gains: Dictionary = action.get("gains", {})
	var duration := int(action.get("duration", 0))
	if not costs.is_empty():
		parts.append("消耗 %s" % _stat_changes_text(costs, false))
	if not gains.is_empty():
		parts.append("收获 %s" % _stat_changes_text(gains, true))
	if duration > 0:
		parts.append("%d %s" % [duration, _clock_unit()])
	var reason := str(action.get("reason", ""))
	if not bool(action.get("enabled", false)) and not reason.is_empty():
		parts.append(reason)
	elif parts.is_empty():
		parts.append(str(action.get("description", "依照当前条件进行")))
	return " · ".join(parts)


func _add_scene_actor(character_id: String, character: Dictionary, actor: Dictionary) -> void:
	var actor_motion_id := str(actor.get("motion", ""))
	if not actor_motion_id.is_empty():
		_add_motion_scene_actor(character_id, character, actor, actor_motion_id)
		return
	var portrait_path := str(actor.get("texture", ""))
	if portrait_path.is_empty():
		portrait_path = str(character.get("portrait", ""))
	var portrait: Texture2D
	if not portrait_path.is_empty():
		var portrait_resource: Resource = ResourceLoader.load(portrait_path)
		if portrait_resource is Texture2D:
			portrait = portrait_resource as Texture2D
	if portrait == null:
		_add_text_character_card(character_id, character, _text_card_count())
		return
	var source_region: Variant = actor.get("region", [])
	var has_source_region := false
	var source_region_rect := Rect2i()
	if source_region is Array and (source_region as Array).size() >= 4:
		var region_values: Array = source_region as Array
		var source_size := portrait.get_size()
		var region_x := int(_number(region_values[0], -1.0))
		var region_y := int(_number(region_values[1], -1.0))
		var region_width := int(_number(region_values[2], 0.0))
		var region_height := int(_number(region_values[3], 0.0))
		if region_x >= 0 and region_y >= 0 and region_width > 0 and region_height > 0 and region_x + region_width <= int(source_size.x) and region_y + region_height <= int(source_size.y):
			source_region_rect = Rect2i(region_x, region_y, region_width, region_height)
			has_source_region = true
	if has_source_region:
		portrait = _crop_transparent_region(portrait, source_region_rect)
	else:
		portrait = _crop_transparent_texture(portrait)
	var texture_rect := TextureRect.new()
	texture_rect.name = "ActorPortrait_%s" % _safe_name(character_id)
	texture_rect.texture = portrait
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var flip_actor := bool(actor.get("flip", false))
	texture_rect.scale.x = -1.0 if flip_actor else 1.0
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_surface.add_child(texture_rect)
	var action_info := _character_action(character_id)
	var actor_button: Button
	if not action_info.is_empty():
		actor_button = _make_button("", "ActorButton_%s" % _safe_name(character_id), Callable(self, "_run_action").bind(str(action_info.get("id", ""))), _is_performing() or not _confirmation.is_empty() or not bool(action_info.get("enabled", false)))
		actor_button.flat = true
		actor_button.tooltip_text = "%s · %s" % [str(character.get("name", character_id)), str(action_info.get("reason", "与此人交谈"))]
		actor_button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0)))
		actor_button.add_theme_stylebox_override("hover", _flat_style(Color(0.96, 0.88, 0.68, 0.16)))
		actor_button.add_theme_stylebox_override("pressed", _flat_style(Color(0.70, 0.50, 0.32, 0.15)))
		_scene_surface.add_child(actor_button)
	var texture_size := portrait.get_size()
	var aspect := 0.65
	if texture_size.y > 0.0:
		aspect = texture_size.x / texture_size.y
	_actor_layouts.append({
		"portrait": texture_rect,
		"button": actor_button,
		"x": _number(actor.get("x", 0.5)),
		"y": _number(actor.get("y", 0.9)),
		"height": _number(actor.get("height", 0.70)),
		"aspect": aspect,
	})


func _add_motion_scene_actor(character_id: String, character: Dictionary, actor: Dictionary, actor_motion_id: String) -> void:
	var pack := _current_pack()
	var motions: Dictionary = pack.get("motions", {})
	var motion_value: Variant = motions.get(actor_motion_id, {})
	if not motion_value is Dictionary:
		_set_presentation_error("场景动作定义不存在：%s" % actor_motion_id, false)
		_add_text_character_card(character_id, character, _text_card_count())
		return
	var motion: Dictionary = motion_value as Dictionary
	var player: Control
	if is_instance_valid(_presentation_player) and _presentation_motion_id == actor_motion_id:
		player = _presentation_player
		var old_parent := player.get_parent()
		if old_parent != _scene_surface:
			if old_parent != null:
				old_parent.remove_child(player)
			_scene_surface.add_child(player)
	else:
		var helper: RefCounted = MotionAssetsScript.new()
		var idle_result: Dictionary = helper.call("load_idle", pack, actor_motion_id)
		if not bool(idle_result.get("ok", false)):
			_set_presentation_error(str(idle_result.get("reason", "静息动作资源无法载入。")), false)
			_add_text_character_card(character_id, character, _text_card_count())
			return
		var assets_value: Variant = idle_result.get("assets", {})
		if not assets_value is Dictionary:
			_set_presentation_error("静息动作资源无法载入。", false)
			_add_text_character_card(character_id, character, _text_card_count())
			return
		player = AtlasActorScript.new() as Control
		player.name = "AtlasActor_%s" % _safe_name(character_id)
		_scene_surface.add_child(player)
		player.connect("phase_changed", Callable(self, "_on_presentation_phase_changed"))
		player.connect("finished", Callable(self, "_on_presentation_finished"))
		var configured: Dictionary = player.call("configure_idle", motion, assets_value)
		if not bool(configured.get("ok", false)):
			player.queue_free()
			_set_presentation_error(str(configured.get("reason", "静息动作资源无效。")), false)
			_add_text_character_card(character_id, character, _text_card_count())
			return
		_presentation_player = player
		_presentation_motion_id = actor_motion_id
	var action_info := _character_action(character_id)
	var actor_button: Button
	if not action_info.is_empty():
		actor_button = _make_button("", "ActorButton_%s" % _safe_name(character_id), Callable(self, "_run_action").bind(str(action_info.get("id", ""))), _is_performing() or not _confirmation.is_empty() or not bool(action_info.get("enabled", false)))
		actor_button.flat = true
		actor_button.tooltip_text = "%s · %s" % [str(character.get("name", character_id)), str(action_info.get("reason", "与此人交谈"))]
		actor_button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0)))
		actor_button.add_theme_stylebox_override("hover", _flat_style(Color(0.96, 0.88, 0.68, 0.16)))
		actor_button.add_theme_stylebox_override("pressed", _flat_style(Color(0.70, 0.50, 0.32, 0.15)))
		_scene_surface.add_child(actor_button)
	_actor_layouts.append({
		"player": player,
		"button": actor_button,
		"x": _number(actor.get("x", 0.5)),
		"y": _number(actor.get("y", 0.9)),
		"height": _number(actor.get("height", 0.7)),
		"flip": bool(actor.get("flip", false)),
	})


func _add_scene_foreground(foreground: Dictionary) -> void:
	var texture_path := str(foreground.get("texture", ""))
	if texture_path.is_empty():
		return
	var foreground_resource: Resource = ResourceLoader.load(texture_path)
	if not foreground_resource is Texture2D:
		return
	var texture := _crop_transparent_texture(foreground_resource as Texture2D)
	var foreground_rect := TextureRect.new()
	foreground_rect.name = "SceneForeground"
	foreground_rect.texture = texture
	foreground_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foreground_rect.stretch_mode = TextureRect.STRETCH_SCALE
	foreground_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_surface.add_child(foreground_rect)
	_actor_layouts.append({
		"foreground": foreground_rect,
		"x": _number(foreground.get("x", 0.5)),
		"y": _number(foreground.get("y", 1.0)),
		"width": _number(foreground.get("width", 0.5)),
		"height": _number(foreground.get("height", 0.5)),
	})


func _crop_transparent_texture(texture: Texture2D) -> Texture2D:
	var source_image: Image = texture.get_image()
	if source_image == null or source_image.is_empty():
		return texture
	var used_rect: Rect2i = source_image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return texture
	if used_rect.position == Vector2i.ZERO and used_rect.size == source_image.get_size():
		return texture
	return _make_atlas_texture(texture, used_rect)


func _crop_transparent_region(texture: Texture2D, source_region: Rect2i) -> Texture2D:
	var source_image: Image = texture.get_image()
	if source_image == null or source_image.is_empty():
		return _make_atlas_texture(texture, source_region)
	var image_bounds := Rect2i(Vector2i.ZERO, source_image.get_size())
	if source_region.position.x < 0 or source_region.position.y < 0 or source_region.end.x > image_bounds.end.x or source_region.end.y > image_bounds.end.y:
		return _make_atlas_texture(texture, source_region)
	var frame_image: Image = source_image.get_region(source_region)
	if frame_image == null or frame_image.is_empty():
		return _make_atlas_texture(texture, source_region)
	var used_rect: Rect2i = frame_image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return _make_atlas_texture(texture, source_region)
	return _make_atlas_texture(texture, Rect2i(source_region.position + used_rect.position, used_rect.size))


func _make_atlas_texture(texture: Texture2D, region: Rect2i) -> AtlasTexture:
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(Vector2(region.position), Vector2(region.size))
	cropped.filter_clip = true
	return cropped


func _add_text_character_card(character_id: String, character: Dictionary, card_index: int) -> void:
	var action_info := _character_action(character_id)
	var card_width := 160.0
	var card_height := 58.0
	var card: Control
	if not action_info.is_empty():
		var button := _make_button(
			"%s\n%s" % [str(character.get("name", character_id)), str(character.get("role", "在场人物"))],
			"ActorButton_%s" % _safe_name(character_id),
			Callable(self, "_run_action").bind(str(action_info.get("id", ""))),
			_is_performing() or not _confirmation.is_empty() or not bool(action_info.get("enabled", false))
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(card_width, card_height)
		button.tooltip_text = "%s · %s" % [str(character.get("name", character_id)), str(action_info.get("reason", "与此人交谈"))]
		card = button
	else:
		var panel := PanelContainer.new()
		panel.name = "ActorCard_%s" % _safe_name(character_id)
		panel.custom_minimum_size = Vector2(card_width, card_height)
		panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.93, 0.84, 0.93), BORDER, 5, 1))
		var card_content := VBoxContainer.new()
		card_content.add_child(_make_label(str(character.get("name", character_id)), 15, INK, false))
		card_content.add_child(_make_label(str(character.get("role", "在场人物")), 12, MUTED_INK, false))
		panel.add_child(card_content)
		card = panel
	card.position = Vector2(14 + float(card_index) * (card_width + 10.0), 0)
	_scene_surface.add_child(card)
	_actor_layouts.append({"card": card, "card_index": card_index, "width": card_width, "height_px": card_height})


func _text_card_count() -> int:
	var count := 0
	for entry in _actor_layouts:
		if entry.has("card"):
			count += 1
	return count


func _layout_scene_actors() -> void:
	if not is_instance_valid(_scene_surface):
		return
	var surface_size := _scene_surface.size
	if surface_size.x <= 0.0 or surface_size.y <= 0.0:
		return
	var art_rect := _scene_art_rect()
	var layout_size := art_rect.size if _is_quest_active() else surface_size
	for entry in _actor_layouts:
		if entry.has("player"):
			var player: Control = entry.get("player") as Control
			player.call(
				"set_scene_layout",
				layout_size,
				_number(entry.get("x", 0.5)),
				_number(entry.get("y", 0.9)),
				_number(entry.get("height", 0.7)),
				bool(entry.get("flip", false))
			)
			if _is_quest_active():
				player.position += art_rect.position
			var actor_button: Control = entry.get("button") as Control
			if actor_button != null:
				actor_button.position = player.position
				actor_button.size = player.size
		elif entry.has("foreground"):
			var foreground: Control = entry.get("foreground") as Control
			var center_x := art_rect.position.x + clampf(_number(entry.get("x", 0.5)), 0.0, 1.0) * layout_size.x
			var bottom_y := art_rect.position.y + clampf(_number(entry.get("y", 1.0)), 0.0, 1.0) * layout_size.y
			var foreground_width := clampf(_number(entry.get("width", 0.5)), 0.0, 1.0) * layout_size.x
			var foreground_height := clampf(_number(entry.get("height", 0.5)), 0.0, 1.0) * layout_size.y
			foreground.position = Vector2(center_x - foreground_width * 0.5, bottom_y - foreground_height)
			foreground.size = Vector2(foreground_width, foreground_height)
		elif entry.has("portrait"):
			var portrait: Control = entry.get("portrait") as Control
			var x := art_rect.position.x + clampf(_number(entry.get("x", 0.5)), 0.0, 1.0) * layout_size.x
			var bottom := art_rect.position.y + clampf(_number(entry.get("y", 0.9)), 0.0, 1.0) * layout_size.y
			var height := clampf(_number(entry.get("height", 0.7)), 0.08, 0.98) * layout_size.y
			var width := height * clampf(_number(entry.get("aspect", 0.65)), 0.25, 1.5)
			width = minf(width, layout_size.x * 0.43)
			portrait.position = Vector2(x - width * 0.5, bottom - height)
			portrait.size = Vector2(width, height)
			portrait.pivot_offset = Vector2(width * 0.5, height * 0.5)
			var actor_button: Control = entry.get("button") as Control
			if actor_button != null:
				actor_button.position = portrait.position
				actor_button.size = portrait.size
		elif entry.has("card"):
			var card: Control = entry.get("card") as Control
			var card_width := _number(entry.get("width", 160.0))
			var card_height := _number(entry.get("height_px", 58.0))
			var index := int(entry.get("card_index", 0))
			card.position = Vector2(14 + float(index) * (card_width + 10.0), surface_size.y - card_height - 12.0)
			card.size = Vector2(card_width, card_height)
	for object_entry in _object_layouts:
		var object_button: Control = object_entry.get("button") as Control
		if object_button == null or not is_instance_valid(object_button):
			continue
		var object_rect: Rect2 = object_entry.get("rect", Rect2())
		object_button.position = art_rect.position + Vector2(object_rect.position) * layout_size
		object_button.size = Vector2(object_rect.size) * layout_size
		var marker_name := "ObjectMarker_%s" % _safe_control_name(str(object_entry.get("id", "")))
		var marker := object_button.get_node_or_null(marker_name) as Control
		if marker != null:
			marker.position = Vector2(object_button.size.x - 19, -14)
	if is_instance_valid(_object_popover):
		_layout_object_popover()


func _scene_art_rect() -> Rect2:
	if not is_instance_valid(_scene_surface):
		return Rect2()
	var surface_size := _scene_surface.size
	if not _is_quest_active():
		return Rect2(Vector2.ZERO, surface_size)
	var background_path := str(_current_scene().get("background", ""))
	if background_path.is_empty():
		return Rect2(Vector2.ZERO, surface_size)
	var texture := ResourceLoader.load(background_path) as Texture2D
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return Rect2(Vector2.ZERO, surface_size)
	var scale_factor := minf(surface_size.x / float(texture.get_width()), surface_size.y / float(texture.get_height()))
	var art_size := Vector2(texture.get_size()) * scale_factor
	return Rect2((surface_size - art_size) * 0.5, art_size)


func _layout_object_popover() -> void:
	if not is_instance_valid(_object_popover) or not is_instance_valid(_scene_surface):
		return
	var art_rect := _scene_art_rect()
	if art_rect.size.x <= 0.0 or art_rect.size.y <= 0.0:
		return
	var panel_width := minf(360.0, maxf(210.0, art_rect.size.x * 0.46))
	panel_width = maxf(1.0, minf(panel_width, art_rect.size.x - 12.0))
	var panel_height := minf(350.0, maxf(190.0, art_rect.size.y * 0.76))
	panel_height = maxf(1.0, minf(panel_height, art_rect.size.y - 12.0))
	_object_popover.custom_minimum_size = Vector2(panel_width, panel_height)
	_object_popover.size = Vector2(panel_width, panel_height)
	var anchor := _normalized_object_anchor(_selected_object_id)
	var point := art_rect.position + anchor * art_rect.size
	var gap := 12.0
	var candidates := [
		Vector2(point.x + gap, point.y - 18.0),
		Vector2(point.x + gap, point.y - panel_height + 18.0),
		Vector2(point.x - panel_width - gap, point.y - 18.0),
		Vector2(point.x - panel_width - gap, point.y - panel_height + 18.0),
		Vector2(art_rect.position.x + 6.0, point.y - panel_height * 0.5),
		Vector2(art_rect.end.x - panel_width - 6.0, point.y - panel_height * 0.5),
	]
	var best_position := art_rect.position
	var best_score := INF
	for candidate in candidates:
		var bounded := Vector2(
			clampf(candidate.x, art_rect.position.x + 6.0, art_rect.end.x - panel_width - 6.0),
			clampf(candidate.y, art_rect.position.y + 6.0, art_rect.end.y - panel_height - 6.0)
		)
		var candidate_rect := Rect2(bounded, Vector2(panel_width, panel_height))
		var score := bounded.distance_squared_to(candidate)
		for object_entry in _object_layouts:
			var object_rect: Rect2 = object_entry.get("rect", Rect2())
			var placed_rect := Rect2(art_rect.position + Vector2(object_rect.position) * art_rect.size, Vector2(object_rect.size) * art_rect.size)
			var overlap := candidate_rect.intersection(placed_rect)
			if overlap.size.x > 0.0 and overlap.size.y > 0.0:
				score += overlap.size.x * overlap.size.y * 8.0
		var name_card := _scene_surface.get_node_or_null("SceneNameCard") as Control
		if name_card != null:
			var card_overlap := candidate_rect.intersection(name_card.get_rect())
			if card_overlap.size.x > 0.0 and card_overlap.size.y > 0.0:
				score += card_overlap.size.x * card_overlap.size.y * 24.0
		if score < best_score:
			best_score = score
			best_position = bounded
	_object_popover.position = best_position


func _normalized_object_anchor(object_id: String) -> Vector2:
	for entry in _object_layouts:
		if str(entry.get("id", "")) == object_id:
			var anchor_value: Variant = entry.get("anchor", Vector2(0.5, 0.5))
			if anchor_value is Vector2:
				return Vector2(anchor_value)
			var object_rect: Rect2 = entry.get("rect", Rect2())
			return _normalized_point(anchor_value, object_rect.get_center())
	var object := _find_available_object(object_id)
	var rect := _normalized_rect(object.get("rect", []))
	return _normalized_point(object.get("anchor", []), rect.get_center())


func _normalized_rect(value: Variant) -> Rect2:
	if value is Array and (value as Array).size() >= 4:
		var values: Array = value as Array
		return Rect2(_number(values[0]), _number(values[1]), _number(values[2]), _number(values[3]))
	return Rect2()


func _normalized_point(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value as Array
		return Vector2(_number(values[0]), _number(values[1]))
	return fallback


func _pixel_region(value: Variant) -> Rect2i:
	if value is Array and (value as Array).size() >= 4:
		var values: Array = value as Array
		return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
	return Rect2i()


func _build_phase_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PhasePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 142 if get_viewport_rect().size.y < 690.0 else 168
	panel.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 7, 1))
	var content := VBoxContainer.new()
	content.name = "PhaseContent"
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var state := _snapshot()
	var phase := str(state.get("phase", "ready"))
	if _is_quest_active():
		var receipt: Dictionary = state.get("last_result", {})
		content.add_child(_make_label("支线仍在继续", 17, TEAL, false))
		if bool(receipt.get("ok", false)):
			content.add_child(_make_label(str(receipt.get("message", "线索已留在札记。")), 14, MUTED_INK, true))
		else:
			content.add_child(_make_label("点击场景中的物件，直接查看线索。", 14, MUTED_INK, true))
	elif phase == "event":
		_build_event_content(content, state)
	elif phase == "result":
		_build_result_content(content, state)
	elif phase == "performing":
		var receipt: Dictionary = state.get("last_result", {})
		content.add_child(_make_label("%s · 演练" % str(receipt.get("action_label", "动作")), 17, TEAL, false))
		_presentation_phase_label = _make_label("准备载入动作……", 15, INK, true, "PresentationPhaseLabel")
		content.add_child(_presentation_phase_label)
		if not _presentation_error.is_empty():
			content.add_child(_make_label(_presentation_error, 14, ERROR_RED, true, "PresentationRecoveryError"))
	else:
		content.add_child(_make_label("继续行动", 17, TEAL, false))
		var last_result: Dictionary = state.get("last_result", {})
		if bool(last_result.get("ok", false)):
			content.add_child(_make_label(str(last_result.get("message", "")), 14, MUTED_INK, true))
		else:
			content.add_child(_make_label("从右侧选择行动，眼前景物与人物状态会随之改变。", 14, MUTED_INK, true))
	return panel


func _build_event_content(parent: VBoxContainer, state: Dictionary) -> void:
	var event_view: Dictionary = _session.call("event_view")
	var node_type := str(event_view.get("type", ""))
	var event_title := str(event_view.get("title", "一段交谈"))
	var speaker_name := str(event_view.get("speaker_name", ""))
	var line := str(event_view.get("text", ""))
	parent.add_child(_make_label(event_title, 17, CINNABAR, false))
	if not speaker_name.is_empty():
		parent.add_child(_make_label(speaker_name, 14, TEAL, false))
	if node_type == "say" or node_type == "end":
		parent.add_child(_make_label(line, 16, INK, true))
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 8)
		parent.add_child(controls)
		var continue_text := "继续" if node_type == "say" else "收起这段交谈"
		var continue_callback := Callable(self, "_continue_event").bind(str(state.get("run_id", "")), int(state.get("revision", -1)))
		var continue_button := _make_button(continue_text, "DialogContinueButton", continue_callback)
		continue_button.custom_minimum_size.x = 130
		controls.add_child(continue_button)
		var cancel_button := _make_button("结束交谈", "DialogCancelButton", Callable(self, "_cancel_event"))
		cancel_button.custom_minimum_size.x = 108
		controls.add_child(cancel_button)
	elif node_type == "choice":
		parent.add_child(_make_label(line, 16, INK, true))
		var choice_row := HBoxContainer.new()
		choice_row.add_theme_constant_override("separation", 8)
		parent.add_child(choice_row)
		var options: Array = event_view.get("options", [])
		var snapshot := _snapshot()
		var run_id := str(snapshot.get("run_id", ""))
		var event_id := str(event_view.get("event_id", ""))
		var node_id := str(event_view.get("node_id", ""))
		var sequence := int(snapshot.get("sequence", 0))
		for raw_option in options:
			if not raw_option is Dictionary:
				continue
			var option: Dictionary = raw_option as Dictionary
			var option_id := str(option.get("id", ""))
			var option_label := str(option.get("label", "作出选择"))
			var enabled := bool(option.get("enabled", false))
			var reason := str(option.get("reason", ""))
			var operation_id := _choice_operation_id(run_id, event_id, node_id, sequence, option_id)
			var button := _make_button(
				option_label if enabled or reason.is_empty() else "%s\n%s" % [option_label, reason],
				"ChoiceButton_%s" % _safe_name(option_id),
				Callable(self, "_choose_option").bind(option_id, operation_id),
				not enabled
			)
			button.custom_minimum_size = Vector2(124, 50)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.tooltip_text = reason
			choice_row.add_child(button)
		var cancel_button := _make_button("暂且告退", "DialogCancelButton", Callable(self, "_cancel_event"))
		cancel_button.custom_minimum_size.x = 112
		choice_row.add_child(cancel_button)
	else:
		parent.add_child(_make_label(line if not line.is_empty() else "交谈仍在继续。", 15, INK, true))
		parent.add_child(_make_button("收起", "DialogCancelButton", Callable(self, "_cancel_event")))
	var last_result: Dictionary = state.get("last_result", {})
	if bool(last_result.get("ok", false)):
		parent.add_child(_make_label("本次行动：%s" % _receipt_summary(last_result), 13, MUTED_INK, true))


func _build_result_content(parent: VBoxContainer, state: Dictionary) -> void:
	var receipt: Dictionary = state.get("last_result", {})
	parent.add_child(_make_label("行动回报", 18, CINNABAR, false))
	parent.add_child(_make_label(str(receipt.get("message", "这一刻已记入行旅。")), 16, INK, true))
	parent.add_child(_make_label(_receipt_summary(receipt), 15, TEAL, true))
	var continue_button := _make_button("收下回报，继续修行", "ResultContinueButton", Callable(self, "_acknowledge_result"))
	continue_button.custom_minimum_size.x = 200
	parent.add_child(continue_button)


func _build_action_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "ActionColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	if not _confirmation.is_empty():
		column.add_child(_build_confirmation_panel("InlineConfirmation"))
	var actions_panel := _titled_panel("行止选择", "ActionsPanel")
	actions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "ActionScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body(actions_panel).add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "ActionList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var available: Array = _session.call("available_actions")
	if available.is_empty():
		list.add_child(_make_label("此处暂时没有可执行的行动。", 14, MUTED_INK, true))
	for raw_action in available:
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action as Dictionary
		var action_id := str(action.get("id", ""))
		var action_button := _make_button(
			str(action.get("label", "行动")),
			"ActionButton_%s" % _safe_name(action_id),
			Callable(self, "_run_action").bind(action_id),
			_is_performing() or not bool(action.get("enabled", false)) or not _confirmation.is_empty()
		)
		action_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		action_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action_button.custom_minimum_size.y = 72
		var details := _action_preview_text(action)
		var count_line := _action_count_text(action_id)
		if not count_line.is_empty():
			details += "\n" + count_line
		action_button.text = "%s\n%s" % [str(action.get("label", "行动")), details]
		action_button.tooltip_text = str(action.get("reason", action.get("description", "")))
		list.add_child(action_button)
	column.add_child(actions_panel)
	var local_note := _titled_panel("本机进度", "LocalSavePanel")
	var note_content := VBoxContainer.new()
	note_content.add_theme_constant_override("separation", 4)
	_panel_body(local_note).add_child(note_content)
	var persistent := OS.is_userfs_persistent()
	note_content.add_child(_make_label("本机文件存档 · %s" % ("可持久保存" if persistent else "临时文件系统"), 14, TEAL if persistent else CINNABAR, true))
	var has_save := bool(_store.call("has_save", _current_pack()))
	note_content.add_child(_make_label("已有本机存档" if has_save else "尚未保存这一篇章", 14, MUTED_INK, true))
	column.add_child(local_note)
	return column


func _build_confirmation_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#f3dfca"), CINNABAR, 7, 2))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	panel.add_child(content)
	content.add_child(_make_label("需要确认", 16, CINNABAR, false))
	content.add_child(_make_label(str(_confirmation.get("message", "继续此操作？")), 14, INK, true))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)
	var accept := _make_button("确认继续", "ConfirmAcceptButton", Callable(self, "_accept_confirmation"), _is_performing())
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(accept)
	var cancel := _make_button("返回", "ConfirmCancelButton", Callable(self, "_cancel_confirmation"), _is_performing())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel)
	return panel


func _titled_panel(title: String, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	_register_control(panel)
	panel.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 7, 1))
	var box := VBoxContainer.new()
	box.name = "%sContent" % node_name
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	box.add_child(_make_label(title, 17, TEAL, false))
	return panel


func _panel_body(panel: PanelContainer) -> VBoxContainer:
	var child := panel.get_node_or_null("%sContent" % panel.name)
	return child as VBoxContainer if child is VBoxContainer else VBoxContainer.new()


func _make_button(text: String, node_name: String, callback: Callable = Callable(), disabled: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 40.0)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED_INK.darkened(0.15))
	button.add_theme_stylebox_override("normal", _panel_style(PAPER_DEEP, BORDER, 5, 1, 7))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#e7dcc6"), TEAL, 5, 1, 7))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("#d9c9ad"), CINNABAR, 5, 1, 7))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#e8dfd1"), Color("#c9beaa"), 5, 1, 7))
	_register_control(button)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _make_label(text: String, size: int, color: Color, wrap: bool = true, node_name: String = "") -> Label:
	var label := Label.new()
	label.text = text
	if not node_name.is_empty():
		label.name = node_name
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not node_name.is_empty():
		_register_control(label)
	return label


func _panel_style(fill: Color, border: Color, radius: int, border_width: int, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _flat_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(1)
	style.border_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(0)
	return style


func _plain_bar_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(5)
	return style


func _register_control(control: Control) -> void:
	_control_registry[control.name] = control


func _sync_responsive_sizes() -> void:
	if not is_instance_valid(_right_column):
		return
	var viewport := get_viewport_rect().size
	if _is_quest_active():
		if viewport.x < 850.0:
			_right_column.custom_minimum_size.x = 0
		else:
			_right_column.custom_minimum_size.x = 248 if viewport.x < 1260.0 else 270
	else:
		if not is_instance_valid(_left_column):
			return
		if viewport.x >= 1260.0:
			_left_column.custom_minimum_size.x = 270
			_right_column.custom_minimum_size.x = 340
		elif viewport.x >= 1024.0:
			_left_column.custom_minimum_size.x = 220
			_right_column.custom_minimum_size.x = 285
		else:
			_left_column.custom_minimum_size.x = 185
			_right_column.custom_minimum_size.x = 235
	if is_instance_valid(_scene_panel):
		_scene_panel.custom_minimum_size.y = 215 if viewport.y < 690.0 else (285 if viewport.y < 820.0 else 365)
	if is_instance_valid(_body_margin):
		_body_margin.add_theme_constant_override("margin_left", _horizontal_margin())
		_body_margin.add_theme_constant_override("margin_right", _horizontal_margin())


func _horizontal_margin() -> int:
	return 16 if get_viewport_rect().size.x < 1024.0 else 24


func _current_paper_color() -> Color:
	var pack := _current_pack()
	if pack.is_empty():
		return PAPER
	var theme: Dictionary = pack.get("theme", {})
	return _color_from_data(str(theme.get("paper", "")), PAPER)


func _current_title() -> String:
	var pack := _current_pack()
	return str(pack.get("title", "修行篇章"))


func _current_pack() -> Dictionary:
	if _session != null:
		var session_pack: Variant = _session.get("pack")
		if session_pack is Dictionary:
			return session_pack as Dictionary
	if _active_index >= 0 and _active_index < _catalog.size():
		var entry: Dictionary = _catalog[_active_index]
		return entry.get("pack", {})
	if _selected_index >= 0 and _selected_index < _catalog.size():
		var selected: Dictionary = _catalog[_selected_index]
		return selected.get("pack", {})
	return {}


func _active_pack_has_voices() -> bool:
	if _session == null or _view_mode != "game":
		return false
	var voices_value: Variant = _current_pack().get("voices", {})
	return voices_value is Dictionary and not (voices_value as Dictionary).is_empty()


func _voice_toggle_text() -> String:
	var enabled := is_instance_valid(_voice_player) and bool(_voice_player.call("is_voice_enabled"))
	return "语音：开" if enabled else "语音：关"


func _toggle_voice() -> void:
	if not is_instance_valid(_voice_player):
		return
	var enabled := not bool(_voice_player.call("is_voice_enabled"))
	_voice_player.call("set_enabled", enabled)
	if not enabled:
		_voice_player.call("stop", "disabled")
	var button := ui_control("VoiceToggleButton") as Button
	if is_instance_valid(button):
		button.text = _voice_toggle_text()
	_render()


func _snapshot() -> Dictionary:
	if _session == null:
		return {}
	var snapshot: Variant = _session.call("snapshot")
	return snapshot as Dictionary if snapshot is Dictionary else {}


func _quest_view() -> Dictionary:
	if _session == null or not _session.has_method("quest_view"):
		return {}
	var quest_value: Variant = _session.call("quest_view")
	return quest_value as Dictionary if quest_value is Dictionary else {}


func _is_quest_active() -> bool:
	var quest := _quest_view()
	return not str(quest.get("id", "")).is_empty()


func _object_context_key() -> String:
	if _session == null or _view_mode != "game":
		return ""
	var state := _snapshot()
	var quest := _quest_view()
	return "%s|%s|%s|%s" % [
		str(_current_pack().get("id", "")),
		str(state.get("run_id", "")),
		str(state.get("scene", "")),
		str(quest.get("id", "")),
	]


func _available_objects() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if _session == null or not _session.has_method("available_objects"):
		return output
	var value: Variant = _session.call("available_objects")
	if not value is Array:
		return output
	for raw_object in value as Array:
		if raw_object is Dictionary:
			output.append((raw_object as Dictionary).duplicate(true))
	return output


func _find_available_object(object_id: String) -> Dictionary:
	for object in _available_objects():
		if str(object.get("id", "")) == object_id:
			return object
	return {}


func _available_action(action_id: String) -> Dictionary:
	if action_id.is_empty() or _session == null:
		return {}
	var actions_value: Variant = _session.call("available_actions")
	if not actions_value is Array:
		return {}
	for raw_action in actions_value as Array:
		if raw_action is Dictionary and str((raw_action as Dictionary).get("id", "")) == action_id:
			return (raw_action as Dictionary).duplicate(true)
	var definitions: Dictionary = _current_pack().get("actions", {})
	var definition: Variant = definitions.get(action_id, {})
	if definition is Dictionary:
		var fallback: Dictionary = (definition as Dictionary).duplicate(true)
		fallback["id"] = action_id
		fallback["enabled"] = false
		return fallback
	return {}


func _close_object_popover() -> void:
	if _selected_object_id.is_empty() and not is_instance_valid(_object_popover):
		return
	_selected_object_id = ""
	_selected_object_context_key = ""
	_selected_object_description = ""
	_selected_object_repeat = false
	_render()


func _is_performing() -> bool:
	return _session != null and str(_snapshot().get("phase", "")) == "performing"


func _current_presentation_context_key() -> String:
	if _view_mode != "game" or _session == null:
		return ""
	var pack := _current_pack()
	var state := _snapshot()
	return "%s|%s|%s|%s" % [
		str(pack.get("id", "")),
		str(state.get("run_id", "")),
		str(state.get("scene", "")),
		_view_mode,
	]


func _current_scene() -> Dictionary:
	var pack := _current_pack()
	var state := _snapshot()
	var scenes: Dictionary = pack.get("scenes", {})
	var scene_id := str(state.get("scene", pack.get("initial_scene", "")))
	var scene: Variant = scenes.get(scene_id, {})
	return scene as Dictionary if scene is Dictionary else {}


func _clock_and_location_text() -> String:
	var pack := _current_pack()
	var state := _snapshot()
	var rules: Dictionary = pack.get("rules", {})
	var clock: Dictionary = rules.get("clock", {})
	var slots: Array = clock.get("slots", [])
	var slot_index := int(state.get("slot", 0))
	var slot_name := str(slots[slot_index]) if slot_index >= 0 and slot_index < slots.size() else ""
	var scene: Dictionary = _current_scene()
	return "第 %s 日 · %s · %s" % [str(state.get("day", 1)), slot_name, str(scene.get("label", ""))]


func _scene_accent(scene: Dictionary) -> Color:
	var default_color := _pack_accent(_current_pack())
	return _color_from_data(str(scene.get("accent", "")), default_color)


func _pack_accent(pack: Dictionary) -> Color:
	var theme: Dictionary = pack.get("theme", {})
	return _color_from_data(str(theme.get("accent", "")), TEAL)


func _color_from_data(value: String, fallback: Color) -> Color:
	if value.is_empty():
		return fallback
	var parsed := Color.from_string(value, fallback)
	return parsed


func _clock_unit() -> String:
	var rules: Dictionary = _current_pack().get("rules", {})
	var clock: Dictionary = rules.get("clock", {})
	return str(clock.get("unit", "时段"))


func _action_preview_text(action: Dictionary) -> String:
	var parts: Array[String] = []
	var costs: Dictionary = action.get("costs", {})
	var gains: Dictionary = action.get("gains", {})
	var duration := int(action.get("duration", 0))
	if not costs.is_empty():
		parts.append("消耗 %s" % _stat_changes_text(costs, false))
	if not gains.is_empty():
		parts.append("收获 %s" % _stat_changes_text(gains, true))
	if duration > 0:
		parts.append("%d %s" % [duration, _clock_unit()])
	var reason := str(action.get("reason", ""))
	if not bool(action.get("enabled", false)) and not reason.is_empty():
		parts.append(reason)
	elif parts.is_empty():
		parts.append(str(action.get("description", "可在此场景进行")))
	return " · ".join(parts)


func _action_count_text(action_id: String) -> String:
	var actions: Dictionary = _current_pack().get("actions", {})
	var action_value: Variant = actions.get(action_id, {})
	if not action_value is Dictionary or not bool((action_value as Dictionary).get("show_count", false)):
		return ""
	var counts: Dictionary = _snapshot().get("counts", {})
	return "累计 %d 次" % int(counts.get(action_id, 0))


func _receipt_summary(receipt: Dictionary) -> String:
	var delta: Dictionary = receipt.get("delta", {})
	var stats: Dictionary = delta.get("stats", {})
	var parts: Array[String] = []
	for stat_id in stats.keys():
		var amount := _number(stats[stat_id])
		if amount == 0.0:
			continue
		parts.append("%s %s%s" % [_stat_label(str(stat_id)), "+" if amount > 0.0 else "−", _format_number(absf(amount))])
	var slots := int(delta.get("slots", 0))
	if slots > 0:
		parts.append("%s +%d" % [_clock_unit(), slots])
	var before: Dictionary = receipt.get("before", {})
	var after: Dictionary = receipt.get("after", {})
	if not before.is_empty() and not after.is_empty():
		if int(before.get("day", 1)) != int(after.get("day", 1)):
			parts.append("第 %s 日" % str(after.get("day", 1)))
		var before_scene := str(before.get("scene", ""))
		var after_scene := str(after.get("scene", ""))
		if not after_scene.is_empty() and before_scene != after_scene:
			var scenes: Dictionary = _current_pack().get("scenes", {})
			var destination: Variant = scenes.get(after_scene, {})
			var destination_label := str((destination as Dictionary).get("label", after_scene)) if destination is Dictionary else after_scene
			parts.append("前往%s" % destination_label)
	if parts.is_empty():
		return "本次状态无数值变化。"
	return "实际变化：%s" % "，".join(parts)


func _stat_changes_text(changes: Dictionary, positive: bool) -> String:
	var parts: Array[String] = []
	for stat_id in changes.keys():
		var amount := _number(changes[stat_id])
		if amount == 0.0:
			continue
		var prefix := "+" if amount > 0.0 else "−"
		if not positive and amount > 0.0:
			prefix = "−"
		parts.append("%s%s%s" % [_stat_label(str(stat_id)), prefix, _format_number(absf(amount))])
	return "、".join(parts) if not parts.is_empty() else "无"


func _stat_label(stat_id: String) -> String:
	var rules: Dictionary = _current_pack().get("rules", {})
	for raw_stat in rules.get("stats", []):
		if raw_stat is Dictionary and str((raw_stat as Dictionary).get("id", "")) == stat_id:
			return str((raw_stat as Dictionary).get("label", stat_id))
	return stat_id


func _journal_text(item: Variant) -> String:
	if item is String:
		return str(item)
	if item is Dictionary:
		var record: Dictionary = item as Dictionary
		var message := str(record.get("message", record.get("action_label", record.get("text", "行旅留痕"))))
		var before: Dictionary = record.get("before", {})
		var day := str(before.get("day", record.get("day", "")))
		return ("第 %s 日 · %s" % [day, message]) if not day.is_empty() else message
	return "行旅留下一笔。"


func _character_action(character_id: String) -> Dictionary:
	if _session == null:
		return {}
	var available: Array = _session.call("available_actions")
	var action_definitions: Dictionary = _current_pack().get("actions", {})
	var unavailable_fallback: Dictionary = {}
	for raw_action in available:
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action as Dictionary
		var action_id := str(action.get("id", ""))
		var definition: Variant = action_definitions.get(action_id, {})
		if definition is Dictionary and str((definition as Dictionary).get("character", "")) == character_id:
			var resolved: Dictionary = action.duplicate(true)
			resolved["character"] = character_id
			if bool(resolved.get("enabled", false)):
				return resolved
			if unavailable_fallback.is_empty():
				unavailable_fallback = resolved
	return unavailable_fallback


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if value is Array:
		for item in value as Array:
			output.append(str(item))
	return output


func _number(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float:
		var numeric := float(value)
		return numeric if is_finite(numeric) else fallback
	return fallback


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _safe_name(value: String) -> String:
	var output := value
	output = output.replace("/", "_").replace("\\", "_").replace(":", "_").replace(" ", "_")
	return output


func _safe_control_name(value: String) -> String:
	var output := _safe_name(value)
	output = output.replace(".", "_").replace("|", "_")
	return output


func _choice_operation_id(run_id: String, event_id: String, node_id: String, sequence: int, option_id: String) -> String:
	return "ui-choice:%s:%s:%s:%d:%s" % [run_id, event_id, node_id, sequence, option_id]


func _set_status(message: String, is_error: bool = false) -> void:
	_status_text = message
	_status_is_error = is_error


func _select_catalog_index(index: int) -> void:
	if _is_performing():
		return
	if index < 0 or index >= _catalog.size():
		return
	_selected_index = index
	var entry: Dictionary = _catalog[index]
	if bool(entry.get("ok", false)):
		_set_status("已选择《%s》。" % str((entry.get("pack", {}) as Dictionary).get("title", "修行篇章")))
	else:
		_set_status(str(entry.get("error", "篇章无法读取。")), true)
	_render()


func _request_pack_start(index: int) -> void:
	if _is_performing():
		return
	_request_replace(index, "new")


func _request_pack_continue(index: int) -> void:
	if _is_performing():
		return
	_request_replace(index, "continue")


func _request_replace(index: int, mode: String) -> void:
	if _input_busy or _is_performing():
		return
	if index < 0 or index >= _catalog.size():
		return
	var entry: Dictionary = _catalog[index]
	if not bool(entry.get("ok", false)):
		_set_status(str(entry.get("error", "篇章无法读取。")), true)
		_render()
		return
	var target_pack: Dictionary = entry.get("pack", {})
	var target_title := str(target_pack.get("title", "这段修行"))
	var needs_confirmation := false
	var message := ""
	if mode == "new" and _session != null and _session_has_progress():
		needs_confirmation = true
		message = "开始《%s》新一局，会替换当前运行中的进度。是否确认？" % target_title
	elif mode == "continue" and _session != null and _session_has_progress():
		needs_confirmation = true
		message = "读取《%s》的本机存档，会替换当前运行中的进度。是否确认？" % target_title
	elif _session != null and index != _active_index and _session_is_dirty():
		needs_confirmation = true
		var source_title := _current_title()
		message = "切换至《%s》会丢弃《%s》尚未保存的进度。是否继续？" % [target_title, source_title]
	if needs_confirmation:
		_confirmation = {"index": index, "mode": mode, "message": message}
		_selected_index = index
		_set_status("请先确认如何处理当前进度。")
		_render()
		return
	_perform_launch(index, mode)


func _accept_confirmation() -> void:
	if _input_busy or _is_performing():
		return
	if _confirmation.is_empty():
		return
	var request: Dictionary = _confirmation.duplicate(true)
	_confirmation.clear()
	_perform_launch(int(request.get("index", -1)), str(request.get("mode", "new")))


func _cancel_confirmation() -> void:
	if _input_busy or _is_performing():
		return
	_confirmation.clear()
	_set_status("已保留当前进度。")
	_render()


func _perform_launch(index: int, mode: String) -> void:
	if _input_busy or _is_performing() or index < 0 or index >= _catalog.size():
		return
	var entry: Dictionary = _catalog[index]
	if not bool(entry.get("ok", false)):
		_set_status(str(entry.get("error", "篇章无法读取。")), true)
		_render()
		return
	_input_busy = true
	var candidate: RefCounted = SessionScript.new()
	var launch_message := "新一局已经开始。"
	var setup: Dictionary = candidate.call("configure", entry.get("pack", {}))
	if not bool(setup.get("ok", false)):
		_input_busy = false
		_set_status(str(setup.get("reason", "篇章无法开始。")), true)
		_render()
		return
	if mode == "continue":
		var load_result: Dictionary = _store.call("load_session", candidate)
		if not bool(load_result.get("ok", false)):
			_input_busy = false
			_set_status(str(load_result.get("reason", "本机存档无法读取。")), true)
			_render()
			return
		launch_message = str(load_result.get("message", "已从本机继续。"))
	_session = candidate
	_selected_object_id = ""
	_selected_object_context_key = ""
	_selected_object_description = ""
	_selected_object_repeat = false
	_active_index = index
	_selected_index = index
	_view_mode = "game"
	_saved_revision = int(_snapshot().get("revision", 0))
	_confirmation.clear()
	_input_busy = false
	_set_status(launch_message)
	_render()


func _show_library() -> void:
	if _input_busy or _is_performing():
		return
	_view_mode = "library"
	_confirmation.clear()
	if _active_index >= 0:
		_selected_index = _active_index
	_set_status("本机存档 · 内容包各自独立")
	_render()


func _return_to_session() -> void:
	if _session == null or _input_busy or _is_performing():
		return
	_view_mode = "game"
	_confirmation.clear()
	_set_status("已回到《%s》。" % _current_title())
	_render()


func _request_new_run() -> void:
	if _active_index < 0 or _input_busy or _is_performing():
		return
	_request_replace(_active_index, "new")


func _request_load_current() -> void:
	if _active_index < 0 or _session == null or _input_busy or _is_performing():
		return
	_request_replace(_active_index, "continue")


func _save_current() -> void:
	if _input_busy or _is_performing() or _session == null or not bool(_session.call("can_save")):
		return
	_input_busy = true
	var result: Dictionary = _store.call("save_session", _session)
	_input_busy = false
	if bool(result.get("ok", false)):
		_saved_revision = int(_snapshot().get("revision", 0))
		var message: String = str(result.get("message", "已保存到本机。"))
		if OS.has_feature("web") and not bool(result.get("persistent", false)):
			message += " · 当前浏览器未启用持久存储，关闭页面可能丢失。"
		_set_status(message)
	else:
		_set_status(str(result.get("reason", "本机存档未能写入。")), true)
	_render()


func _run_action(action_id: String) -> void:
	if _input_busy or _is_performing() or _session == null:
		return
	_input_busy = true
	var result: Dictionary = _session.call("select_action", action_id, "")
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("正在演练，收势后可继续。" if _is_performing() else "行动已记入行旅。")
	else:
		_set_status(str(result.get("reason", "行动暂时无法进行。")), true)
	_render()


func _inspect_quest_object(object_id: String, captured_run_id: String, captured_revision: int) -> void:
	if _input_busy or _is_performing() or _session == null or not _session.has_method("inspect_object"):
		return
	var state := _snapshot()
	if str(state.get("run_id", "")) != captured_run_id or int(state.get("revision", -1)) != captured_revision:
		_set_status("当前场景已更新，请重新选择物件。", true)
		_render()
		return
	_input_busy = true
	var operation_id := "ui-object-inspect:%s:%d:%s" % [captured_run_id, captured_revision, object_id]
	var result: Dictionary = _session.call("inspect_object", object_id, operation_id, captured_run_id, captured_revision)
	_input_busy = false
	if bool(result.get("ok", false)):
		_selected_object_id = object_id
		_selected_object_context_key = _object_context_key()
		_selected_object_description = str(result.get("description", ""))
		_selected_object_repeat = bool(result.get("repeat", false))
		_set_status("")
	else:
		_set_status(str(result.get("reason", "此刻无法查看这件物品。")), true)
	_render()


func _execute_quest_object_action(object_id: String, action_id: String, captured_run_id: String, captured_revision: int) -> void:
	if _input_busy or _is_performing() or _session == null or not _session.has_method("execute_object_action"):
		return
	var state := _snapshot()
	if str(state.get("run_id", "")) != captured_run_id or int(state.get("revision", -1)) != captured_revision:
		_set_status("当前场景已更新，请重新选择物件。", true)
		_render()
		return
	_input_busy = true
	var operation_id := "ui-object-action:%s:%d:%s:%s" % [captured_run_id, captured_revision, object_id, action_id]
	var result: Dictionary = _session.call("execute_object_action", object_id, action_id, operation_id, captured_run_id, captured_revision)
	_input_busy = false
	if bool(result.get("ok", false)):
		_selected_object_description = ""
		_selected_object_repeat = false
		_set_status("")
	else:
		_set_status(str(result.get("reason", "此刻无法进行这项行动。")), true)
	_render()


func _run_quest_action(action_id: String, captured_run_id: String, captured_revision: int) -> void:
	if _input_busy or _is_performing() or _session == null or action_id.is_empty():
		return
	var state := _snapshot()
	if str(state.get("run_id", "")) != captured_run_id or int(state.get("revision", -1)) != captured_revision:
		_set_status("当前支线已更新，请使用新的行动按钮。", true)
		_render()
		return
	if not _is_quest_active():
		_set_status("这段支线已经结束。", true)
		_render()
		return
	_input_busy = true
	var operation_id := "ui-quest-action:%s:%d:%s" % [captured_run_id, captured_revision, action_id]
	var result: Dictionary = _session.call("select_action", action_id, operation_id)
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("")
	else:
		_set_status(str(result.get("reason", "此刻无法进行这项行动。")), true)
	_render()


func _choose_option(option_id: String, captured_operation_id: String) -> void:
	if _input_busy or _is_performing() or _session == null:
		return
	_input_busy = true
	var result: Dictionary = _session.call("choose", option_id, captured_operation_id)
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("选择已记下。")
	else:
		_set_status(str(result.get("reason", "这项选择暂时无法进行。")), true)
	_render()


func _continue_event(captured_run_id: String = "", captured_revision: int = -1) -> void:
	if _input_busy or _is_performing() or _session == null:
		return
	_input_busy = true
	var result: Dictionary = _session.call("continue_event", captured_run_id, captured_revision)
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("交谈继续。")
	else:
		_set_status(str(result.get("reason", "此刻无法继续。")), true)
	_render()


func _cancel_event() -> void:
	if _input_busy or _is_performing() or _session == null:
		return
	_input_busy = true
	var result: Dictionary = _session.call("cancel_event")
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("交谈已收起，已完成的行动仍保留。")
	else:
		_set_status(str(result.get("reason", "此刻无法结束交谈。")), true)
	_render()


func _acknowledge_result() -> void:
	if _input_busy or _is_performing() or _session == null:
		return
	_input_busy = true
	var result: Dictionary = _session.call("acknowledge_result")
	_input_busy = false
	if bool(result.get("ok", false)):
		_set_status("可以继续选择行动。")
	else:
		_set_status(str(result.get("reason", "回报暂时无法收起。")), true)
	_render()


func _session_has_progress() -> bool:
	if _session == null:
		return false
	var state := _snapshot()
	if int(state.get("sequence", 0)) > 0 or int(state.get("revision", 0)) > 0:
		return true
	var pack := _current_pack()
	var rules: Dictionary = pack.get("rules", {})
	var clock: Dictionary = rules.get("clock", {})
	if int(state.get("day", clock.get("start_day", 1))) != int(clock.get("start_day", 1)):
		return true
	if int(state.get("slot", clock.get("start_slot", 0))) != int(clock.get("start_slot", 0)):
		return true
	if str(state.get("scene", pack.get("initial_scene", ""))) != str(pack.get("initial_scene", "")):
		return true
	var stats: Dictionary = state.get("stats", {})
	for raw_stat in rules.get("stats", []):
		if raw_stat is Dictionary:
			var stat: Dictionary = raw_stat as Dictionary
			var id := str(stat.get("id", ""))
			if not is_equal_approx(_number(stats.get(id, stat.get("initial", 0))), _number(stat.get("initial", 0))):
				return true
	var flags: Dictionary = state.get("flags", {})
	var initial_flags: Dictionary = pack.get("initial_flags", {})
	for flag_id in flags.keys():
		if bool(flags[flag_id]) != bool(initial_flags.get(flag_id, false)):
			return true
	var journal: Variant = state.get("journal", [])
	return journal is Array and not (journal as Array).is_empty()


func _session_is_dirty() -> bool:
	return _session != null and int(_snapshot().get("revision", 0)) > _saved_revision
