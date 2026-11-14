extends "res://addons/cultivation_mode/town_mode_view.gd"
## A city slice on the existing Session: spatial scenes, ordinary events and saves.

const ChengduWalker = preload("res://addons/cultivation_mode/chengdu_walker.gd")
const CITY_FONT = "res://assets/fonts/ShuChengduSerif.ttf"
var _menu_open := false


func _make_theme() -> Theme:
	var result := super._make_theme()
	if ResourceLoader.exists(CITY_FONT):
		result.default_font = load(CITY_FONT) as Font
	return result


func _ready() -> void:
	super._ready()
	if not _catalog.is_empty() and bool(_catalog[0].get("ok", false)):
		var mode := "continue" if bool(_store.call("has_save", _catalog[0].pack)) else "new"
		_perform_launch(0, mode)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not _confirmation.is_empty():
			_cancel_confirmation()
		elif _menu_open:
			_toggle_menu()
		elif _view_mode == "game":
			_toggle_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu_open or not _confirmation.is_empty():
		return
	super._input(event)


func _render() -> void:
	super._render()
	if not _confirmation.is_empty() and _view_mode == "game":
		var cover := ColorRect.new()
		cover.name = "CityConfirmationCover"
		cover.color = Color(0.12, 0.14, 0.12, 0.46)
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_screen.add_child(cover)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.add_child(center)
		var panel := _build_confirmation_panel("CityConfirmationDialog")
		panel.custom_minimum_size.x = minf(530, get_viewport_rect().size.x - 60)
		center.add_child(panel)
	elif _menu_open and _view_mode == "game":
		_build_city_menu()


func _build_header() -> PanelContainer:
	if _view_mode != "game" or _session == null:
		return super._build_header()
	var panel := PanelContainer.new()
	panel.name = "HeaderPanel"
	panel.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 7, 1, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	row.add_child(_make_label("蜀 · 成都行记", 23, INK, false))
	var place := _make_label(_clock_and_location_text(), 16, TEAL, false)
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(place)
	var stats: Dictionary = _snapshot().get("stats", {})
	row.add_child(_make_label("精力 %d · 剑术 %d" % [int(stats.get("energy", 0)), int(stats.get("sword", 0))], 16, INK, false))
	row.add_child(_make_button("菜单", "CityMenuButton", _toggle_menu))
	column.add_child(_make_label(_status_text if _status_is_error else _next_city_step(), 15, ERROR_RED if _status_is_error else MUTED_INK, true, "StatusLabel"))
	_voice_warning_label = _make_label(_voice_warning, 13, CINNABAR, true, "VoiceWarningLabel")
	_voice_warning_label.visible = not _voice_warning.is_empty()
	column.add_child(_voice_warning_label)
	return panel


func _next_city_step() -> String:
	var state := _snapshot()
	var flags: Dictionary = state.get("flags", {})
	if not _town_scene():
		return "山中修行照旧，也可下山到成都走走。"
	if bool(flags.get("chengdu_umbrella_returned", false)):
		return "竹伞已放回茶馆失物架。再逛逛街巷，或从西门返山。"
	if bool(flags.get("chengdu_umbrella_carrying", false)):
		return "带着竹伞，去茶馆的失物架看看。"
	return "沿街闲逛 · 点人物或门口，走近后互动 · 菜单中保存进度"


func _build_game_view() -> Control:
	if not _town_scene():
		return super._build_game_view()
	var body := VBoxContainer.new()
	body.name = "ChengduCityBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_left_column = null
	_right_column = null
	if not _confirmation.is_empty():
		body.add_child(_build_confirmation_panel("InlineConfirmation"))
	body.add_child(_build_scene_column())
	return body


func _build_scene_column() -> Control:
	if not _town_scene():
		return super._build_scene_column()
	var column := VBoxContainer.new()
	column.name = "SceneColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_scene_panel = PanelContainer.new()
	_scene_panel.name = "ScenePanel"
	_scene_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_panel.add_theme_stylebox_override("panel", _panel_style(PAPER_DEEP, BORDER, 6, 1, 0))
	_register_control(_scene_panel)
	column.add_child(_scene_panel)
	_scene_surface = Control.new()
	_scene_surface.name = "SceneSurface"
	_scene_surface.clip_contents = true
	_scene_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	_register_control(_scene_surface)
	_scene_panel.add_child(_scene_surface)
	_build_scene_surface(_current_scene())
	_scene_description = null
	column.add_child(_build_phase_panel())
	return column


func _build_scene_surface(scene_info: Dictionary) -> void:
	if not _town_scene():
		super._build_scene_surface(scene_info)
		return
	_town_walker = ChengduWalker.new()
	_town_walker.name = "TownWalker"
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	var map_id := str(state.scene)
	var map: Dictionary = _current_pack().walks.scenes[map_id]
	var enabled: bool = state.phase == "ready" and _confirmation.is_empty() and not _menu_open and not _input_busy
	_town_walker.call("setup", _session, map_id, map, _theme_resource.default_font, enabled)
	var stage: Node = _town_walker.get("_stage")
	if stage != null and stage.has_method("set_city_flags"):
		stage.call("set_city_flags", state.get("flags", {}))
	_town_walker.connect("interaction_requested", _on_town_interaction)
	_town_walker.connect("feedback", _on_town_feedback)


func _on_town_interaction(id: String, captured_run_id: String, captured_revision: int) -> void:
	if _input_busy or _menu_open or not _confirmation.is_empty() or not _town_scene():
		return
	var before := _snapshot()
	if str(before.run_id) != captured_run_id or int(before.revision) != captured_revision:
		return
	_input_busy = true
	var operation := "%s:walk:%d:%s" % [captured_run_id, captured_revision, id]
	var result: Dictionary = _session.call("execute_walk_interaction", id, operation, captured_run_id, captured_revision)
	if bool(result.get("ok", false)):
		_town_interactions += 1
		var after := _snapshot()
		var maps: Dictionary = _current_pack().get("walks", {}).get("scenes", {})
		# Free neighborhood doors remain ordinary Session actions and receipts.
		# Acknowledge only their travel result so walking resumes at the doorway.
		if str(before.scene) != str(after.scene) and maps.has(before.scene) and maps.has(after.scene) and str(after.phase) == "result" and int(after.get("last_result", {}).get("delta", {}).get("slots", 0)) == 0:
			result = _session.call("acknowledge_result")
	_input_busy = false
	_set_status("已走到相邻街巷。" if bool(result.get("ok", false)) else str(result.get("reason", "暂时不能互动。")), not bool(result.get("ok", false)))
	_render()


func _build_phase_panel() -> PanelContainer:
	if not _town_scene():
		return super._build_phase_panel()
	# City actions use the existing event/receipt controls. Empty panels are absent.
	var panel := PanelContainer.new()
	panel.name = "PhasePanel"
	panel.add_theme_stylebox_override("panel", _panel_style(PAPER_LIGHT, BORDER, 6, 1, 10))
	var content := VBoxContainer.new()
	content.name = "PhaseContent"
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var state := _snapshot()
	if state.phase == "event":
		_build_event_content(content, state)
	elif state.phase == "result":
		var result: Dictionary = state.get("last_result", {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		content.add_child(row)
		var label := _make_label(str(result.get("message", "")), 16, INK, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_make_button("继续走走", "ResultContinueButton", _acknowledge_result))
		if int(result.get("delta", {}).get("slots", 0)) != 0:
			content.add_child(_make_label(_receipt_summary(result), 14, TEAL, true))
	else:
		panel.visible = false
	return panel


func _build_event_content(parent: VBoxContainer, state: Dictionary) -> void:
	if not _town_scene():
		super._build_event_content(parent, state)
		return
	var event: Dictionary = _session.call("event_view")
	parent.add_child(_make_label(str(event.get("title", "街巷见闻")), 17, CINNABAR, false))
	parent.add_child(_make_label(str(event.get("text", "")), 16, INK, true))
	if event.get("type", "") == "choice":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)
		for raw: Variant in event.get("options", []):
			var option: Dictionary = raw
			if not bool(option.get("enabled", false)):
				continue
			var option_id := str(option.id)
			var operation := _choice_operation_id(str(state.run_id), str(event.event_id), str(event.node_id), int(state.sequence), option_id)
			var button := _make_button(str(option.label), "ChoiceButton_" + _safe_name(option_id), Callable(self, "_choose_option").bind(option_id, operation))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(120, 44)
			row.add_child(button)
	else:
		parent.add_child(_make_button("收起，继续走走", "DialogContinueButton", Callable(self, "_continue_event").bind(str(state.run_id), int(state.revision))))


func _sync_responsive_sizes() -> void:
	if not _town_scene():
		super._sync_responsive_sizes()
		return
	if is_instance_valid(_scene_panel):
		_scene_panel.custom_minimum_size.y = 220
	if is_instance_valid(_body_margin):
		_body_margin.add_theme_constant_override("margin_left", _horizontal_margin())
		_body_margin.add_theme_constant_override("margin_right", _horizontal_margin())


func _toggle_menu() -> void:
	_menu_open = not _menu_open
	_render()


func _build_confirmation_panel(node_name: String) -> PanelContainer:
	# A single modal surface owns confirmation input; inherited inline callers
	# receive no duplicate controls beneath it.
	if _view_mode == "game" and node_name != "CityConfirmationDialog":
		var placeholder := PanelContainer.new()
		placeholder.visible = false
		return placeholder
	return super._build_confirmation_panel(node_name)


func _menu_load() -> void:
	_menu_open = false
	_request_load_current()


func _menu_restart() -> void:
	_menu_open = false
	_request_new_run()


func _build_city_menu() -> void:
	var cover := ColorRect.new()
	cover.name = "CityMenuCover"
	cover.color = Color(0.12, 0.14, 0.12, 0.46)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var panel := _titled_panel("行旅菜单", "CityMenuPanel")
	panel.custom_minimum_size.x = minf(530, get_viewport_rect().size.x - 60)
	center.add_child(panel)
	var content := _panel_body(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var safe := bool(_session.call("can_save")) and not _is_performing()
	row.add_child(_make_button("保存", "SaveButton", _save_current, not safe))
	row.add_child(_make_button("继续存档", "LoadButton", _menu_load, _is_performing() or not bool(_store.call("has_save", _current_pack()))))
	row.add_child(_make_button("重新开始", "NewRunButton", _menu_restart, _is_performing()))
	if _active_pack_has_voices():
		row.add_child(_make_button(_voice_toggle_text(), "VoiceToggleButton", _toggle_voice))
	content.add_child(_make_label(_status_text, 14, ERROR_RED if _status_is_error else TEAL, true))
	var stats: Dictionary = _snapshot().get("stats", {})
	content.add_child(_make_label("修为 %d · 理解 %d" % [int(stats.get("cultivation", 0)), int(stats.get("understanding", 0))], 15, INK, true))
	var journal: Array = _snapshot().get("journal", [])
	if not journal.is_empty():
		content.add_child(_make_label("最近见闻", 17, CINNABAR, false))
		for item: Variant in journal.slice(maxi(0, journal.size() - 3)):
			content.add_child(_make_label(str(item.get("message", "")), 14, INK, true))
	content.add_child(_make_button("回到眼前", "CityMenuCloseButton", _toggle_menu))
