extends "res://addons/cultivation_mode/ambush_mode_view.gd"
## Only immediate intent and feedback stay in view. Records live in the menu.

const JourneySessionScript = preload("res://addons/cultivation_mode/journey_session.gd")
const PaintedPracticeActorScript = preload("res://addons/cultivation_mode/painted_practice_actor.gd")
const TrainingGroundActorScript = preload("res://addons/cultivation_mode/training_ground_actor.gd")
const JOURNEY_FONT_PATH := "res://assets/fonts/ShuFirstJourneySerif.ttf"
var _ending_dismissed_run := ""
var _journey_menu_open := false
var _training_context: Dictionary = {}
var _training_actor: Control


func _create_session(data: Dictionary) -> RefCounted:
	return JourneySessionScript.new() if str(data.get("id", "")) == "shu_first_journey" else super._create_session(data)


func _painted_mountain() -> bool:
	return _mountain_scene() and _training_context.is_empty()


func _mountain_scene() -> bool:
	return str(_current_pack().get("id", "")) == "shu_first_journey" and str(_snapshot().get("scene", "")) == "back_mountain"


func _current_presentation_context_key() -> String:
	return super._current_presentation_context_key() + "|%s|%s" % [str(_session.get_instance_id()) if _session != null else "", "painted" if _training_context.is_empty() else "training3d"]


func _enter_training_ground() -> void:
	if not _painted_mountain() or _input_busy or str(_snapshot().get("phase", "")) != "ready" or _journey_menu_open or not _confirmation.is_empty():
		return
	_training_context = {"session": _session.get_instance_id(), "run_id": _snapshot().get("run_id", "")}
	_set_status("")
	_render()


func _return_from_training_ground() -> void:
	if _is_performing() or _input_busy or _journey_menu_open or not _confirmation.is_empty():
		return
	_clear_training_ground()
	_set_status("")
	_render()


func _clear_training_ground() -> void:
	_training_context.clear()
	if is_instance_valid(_training_actor):
		if _presentation_player == _training_actor:
			_presentation_player = null
		_training_actor.hide()
		_training_actor.queue_free()
	_training_actor = null


func _build_scene_surface(scene_info: Dictionary) -> void:
	if _training_context.is_empty():
		super._build_scene_surface(scene_info)
		return
	if not is_instance_valid(_training_actor):
		_training_actor = TrainingGroundActorScript.new() as Control
		_training_actor.name = "TrainingGroundActor"
		_training_actor.z_index = 1
		# Keep Stage in a stable tree: leaving the tree cancels its real clock.
		add_child(_training_actor)
		_training_actor.call("configure_ground", _session.get("_encounter"), _theme_resource.default_font)
		_training_actor.connect("phase_changed", _on_presentation_phase_changed)
		_training_actor.connect("finished", _on_presentation_finished)
		var motion: Dictionary = _current_pack().get("motions", {}).get("jiang_sword", {})
		var idle: Dictionary = MotionAssetsScript.new().call("load_idle", _current_pack(), "jiang_sword")
		var configured: Dictionary = _training_actor.call("configure_idle", motion, idle.get("assets", {})) if bool(idle.get("ok", false)) else idle
		if not bool(configured.get("ok", false)):
			_set_status(str(configured.get("reason", "练武场尚未准备好，请返回后再试。")), true)
	_presentation_player = _training_actor
	_presentation_motion_id = "jiang_sword"
	_register_control(_training_actor)
	_layout_training_ground()


func _layout_scene_actors() -> void:
	super._layout_scene_actors()
	_layout_training_ground()


func _layout_training_ground() -> void:
	if _training_context.is_empty() or not is_instance_valid(_training_actor) or not is_instance_valid(_scene_surface):
		return
	_training_actor.global_position = _scene_surface.global_position
	_training_actor.call("set_scene_layout", _scene_surface.size, 0.5, 0.9, 0.65, false)


func ui_control(control_name: String) -> Control:
	if control_name == "TrainingGroundActor":
		return _training_actor
	if control_name == "TrainingGroundSurface" and not _training_context.is_empty():
		return _scene_surface
	return super.ui_control(control_name)


func _create_motion_actor(character_id: String, actor: Dictionary, motion_id: String) -> Control:
	if _painted_mountain() and motion_id == "jiang_sword":
		return PaintedPracticeActorScript.new() as Control
	return super._create_motion_actor(character_id, actor, motion_id)


func _add_motion_scene_actor(character_id: String, character: Dictionary, actor: Dictionary, motion_id: String) -> void:
	var layout := actor.duplicate(true)
	if _painted_mountain() and motion_id == "jiang_sword":
		# The original seated portrait keeps its own proportions and ground anchor.
		layout["height"] = 0.44
	super._add_motion_scene_actor(character_id, character, layout, motion_id)


func _run_action(action_id: String) -> void:
	if _input_busy or _is_performing() or _session == null or _journey_menu_open or not _confirmation.is_empty():
		return
	var action: Dictionary = _current_pack().get("actions", {}).get(action_id, {})
	if not _training_context.is_empty() and str(action.get("presentation", {}).get("motion", "")) == "jiang_sword":
		var checked: Dictionary = _training_actor.call("preflight_clip", str(action.presentation.clip)) if is_instance_valid(_training_actor) and bool(_training_actor.call("is_prepared")) else {"ok": false, "reason": "练武场人物尚未准备好。"}
		if not bool(checked.get("ok", false)):
			_set_status(str(checked.get("reason", "练武场动作尚未准备好。")), true)
			_render()
			return
	if _painted_mountain() and str(action.get("presentation", {}).get("motion", "")) == "jiang_sword":
		# Do not charge the host until the actual painted presenter is ready.
		if not is_instance_valid(_presentation_player) or not _presentation_player is PaintedPracticeActorScript or not bool(_presentation_player.call("is_prepared")):
			_set_status("后山2D原画人物尚未准备好，请重新进入场景后再修习。", true)
			_render()
			return
	super._run_action(action_id)


func _make_theme() -> Theme:
	var result := super._make_theme()
	result.default_font = load(JOURNEY_FONT_PATH) as Font
	return result


func _perform_launch(index: int, mode: String) -> void:
	_journey_menu_open = false
	super._perform_launch(index, mode)


func _input(event: InputEvent) -> void:
	if _journey_menu_open or not _confirmation.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if not _confirmation.is_empty():
				_cancel_confirmation()
			else:
				_close_journey_menu()
		return
	if not _training_context.is_empty() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_return_from_training_ground()
		return
	super._input(event)


func _render() -> void:
	if not _training_context.is_empty() and (_session == null or _view_mode != "game" or not _mountain_scene() or _training_context.get("session") != _session.get_instance_id() or _training_context.get("run_id") != _snapshot().get("run_id")):
		_clear_training_ground()
	super._render()
	if _view_mode == "game" and not is_instance_valid(_ambush_view) and (_journey_menu_open or not _confirmation.is_empty()):
		_add_journey_menu()


func _next_step() -> String:
	var flags: Dictionary = _snapshot().get("flags", {})
	if not bool(flags.get("mentor_lesson_heard", false)):
		return "向师父听教"
	if not bool(flags.get("mentor_practice_finished", false)):
		return "到后山，任选一套剑法练习"
	if not bool(flags.get("journey_commission", false)):
		return "下山到集镇，走近茶摊接护药委托"
	if not bool(flags.get("ambush_resolved", false)):
		return "与沈听岚上山道护药"
	if not bool(flags.get("journey_complete", false)):
		return "返山，向师父复命"
	return "此行已结，可以继续修行"


func _build_header() -> PanelContainer:
	var panel := _titled_panel("", "HeaderPanel")
	var body := _panel_body(panel)
	(body.get_child(0) as Control).hide()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	body.add_child(row)
	row.add_child(_make_label("初次下山", 24, INK, false))
	var clock := _make_label(_clock_and_location_text() + (" · 练武场" if not _training_context.is_empty() else ""), 16, MUTED_INK, false)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(clock)
	var stats: Dictionary = _snapshot().get("stats", {})
	row.add_child(_make_label("精力 %d · 剑术 %d" % [int(stats.get("energy", 0)), int(stats.get("sword", 0))], 16, TEAL, false))
	row.add_child(_make_button("菜单", "MenuButton", _open_journey_menu))
	body.add_child(_make_label("下一步 · " + _next_step(), 16, TEAL, true, "JourneyNextStep"))
	var status := _make_label(_status_text, 14, ERROR_RED, true, "StatusLabel")
	status.visible = _status_is_error
	body.add_child(status)
	return panel


func _build_game_view() -> Control:
	var state := _snapshot()
	if bool(state.get("flags", {}).get("journey_complete", false)) and _ending_dismissed_run != str(state.get("run_id", "")):
		_left_column = null
		_right_column = null
		_scene_panel = null
		return _build_ending_view()
	var body := HBoxContainer.new()
	body.name = "JourneyColumns"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_left_column = null
	body.add_child(_build_scene_column())
	_right_column = _build_action_column()
	_right_column.visible = (str(state.get("phase", "")) == "ready" or not _training_context.is_empty()) and _right_column.get_child_count() > 0
	body.add_child(_right_column)
	return body


func _build_scene_column() -> Control:
	var column := super._build_scene_column()
	(column.get_node("SceneHeading") as Control).hide()
	_scene_description.hide()
	var card := _scene_surface.get_node_or_null("SceneNameCard") as Control
	if card != null:
		card.hide()
	return column


func _build_action_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "ActionColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	if not _training_context.is_empty():
		column.add_child(_make_button("回到后山", "ReturnTrainingGroundButton", _return_from_training_ground, _is_performing()))
		column.add_child(_make_label("练武场 · 五剑拆招", 17, TEAL, true))
		if str(_snapshot().get("phase", "")) != "ready":
			return column
	elif _painted_mountain() and str(_snapshot().get("phase", "")) == "ready":
		column.add_child(_make_button("进入练武场", "EnterTrainingGroundButton", _enter_training_ground))
	if _town_scene():
		var flags: Dictionary = _snapshot().get("flags", {})
		if bool(flags.get("journey_commission", false)) and not bool(flags.get("ambush_resolved", false)):
			var begin := _available_action("begin_ambush")
			column.add_child(_make_button("上山道 · 护药", "BeginAmbushButton", _start_ambush, not bool(begin.get("enabled", false))))
			column.add_child(_make_label("此役计1时辰", 14, MUTED_INK, true))
		return column
	if str(_snapshot().get("phase", "")) != "ready":
		return column
	for action: Dictionary in _session.call("available_actions"):
		var id := str(action.get("id", ""))
		if not _training_context.is_empty() and id not in ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow", "rest_practice"]:
			continue
		var enabled := bool(action.get("enabled", false))
		if not enabled and id in ["talk_mentor", "go_to_mountain", "go_to_town", "journey_report"]:
			continue
		var label := str(action.get("label", "行动"))
		var cost := ""
		if int(action.get("duration", 0)) > 0 or not action.get("costs", {}).is_empty() or not action.get("gains", {}).is_empty():
			cost = _action_preview_text(action)
		if not cost.is_empty():
			label += "\n" + cost
		var button := _make_button(label, "ActionButton_%s" % _safe_name(id), _run_action.bind(id), not enabled)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 60
		button.tooltip_text = str(action.get("reason", action.get("description", "")))
		column.add_child(button)
	if str(_snapshot().get("scene", "")) == "back_mountain" and not bool(_snapshot().get("flags", {}).get("ambush_resolved", false)):
		var tip := _make_label("剑术20：本次护药体力+4", 14, MUTED_INK, true)
		tip.tooltip_text = "再练一次仍需22精力与1时辰；江砚秋本次战斗的体力由22增加至26。"
		column.add_child(tip)
	return column


func _build_phase_panel() -> PanelContainer:
	var panel := super._build_phase_panel()
	panel.visible = str(_snapshot().get("phase", "")) != "ready"
	panel.custom_minimum_size.y = 0
	return panel


func _build_result_content(parent: VBoxContainer, state: Dictionary) -> void:
	var receipt: Dictionary = state.get("last_result", {})
	parent.add_child(_make_label(str(receipt.get("message", "这一刻已记入行旅。")), 17, INK, true))
	var summary := _receipt_summary(receipt)
	if not summary.is_empty():
		parent.add_child(_make_label(summary, 14, TEAL, true))
	parent.add_child(_make_button("继续", "ResultContinueButton", _acknowledge_result))


func _build_event_content(parent: VBoxContainer, state: Dictionary) -> void:
	super._build_event_content(parent, state)
	for child in parent.get_children():
		if child is Label and child.text.begins_with("本次行动："):
			child.hide()


func _sync_responsive_sizes() -> void:
	super._sync_responsive_sizes()
	if is_instance_valid(_right_column):
		_right_column.custom_minimum_size.x = 250
	if is_instance_valid(_scene_panel):
		_scene_panel.custom_minimum_size.y = 300


func _set_presentation_error(reason: String, recovery: bool) -> void:
	super._set_presentation_error(reason, recovery)
	var status := ui_control("StatusLabel")
	if is_instance_valid(status):
		status.show()


func _on_town_feedback(message: String) -> void:
	var normal := message in ["走近后互动。", "沿石路走过去。"]
	_set_status("" if normal else message, not normal)
	var status := ui_control("StatusLabel") as Label
	if is_instance_valid(status):
		status.text = "" if normal else message
		status.visible = not normal and not message.is_empty()


func _open_journey_menu() -> void:
	_journey_menu_open = true
	_render()


func _close_journey_menu() -> void:
	_journey_menu_open = false
	_render()


func _add_journey_menu() -> void:
	var overlay := Control.new()
	overlay.name = "JourneyMenuOverlay"
	overlay.z_index = 50
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.14, 0.12, 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := _titled_panel("行旅菜单", "JourneyMenuPanel")
	panel.custom_minimum_size.x = 570
	center.add_child(panel)
	var body := _panel_body(panel)
	if not _confirmation.is_empty():
		body.add_child(_build_confirmation_panel("JourneyMenuConfirmation"))
		return
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 12)
	rows.add_theme_constant_override("v_separation", 10)
	body.add_child(rows)
	var can_save := bool(_session.call("can_save")) and not _is_performing()
	rows.add_child(_make_button("保存进度", "SaveButton", _save_current, not can_save))
	rows.add_child(_make_button("读取进度", "LoadButton", _request_load_current, _is_performing() or not bool(_store.call("has_save", _current_pack()))))
	rows.add_child(_make_button(_voice_toggle_text(), "VoiceToggleButton", _toggle_voice))
	rows.add_child(_make_button("重新开始", "NewRunButton", _request_new_run, _is_performing()))
	var stats: Dictionary = _snapshot().get("stats", {})
	body.add_child(_make_label("修为 %d · 理解 %d" % [int(stats.get("cultivation", 0)), int(stats.get("understanding", 0))], 14, MUTED_INK, true))
	if _status_is_error or _status_text.contains("保存"):
		body.add_child(_make_label(_status_text, 14, ERROR_RED if _status_is_error else TEAL, true))
	var journal := _build_journal_panel()
	journal.custom_minimum_size.y = 200
	body.add_child(journal)
	body.add_child(_make_button("返回游戏", "CloseJourneyMenuButton", _close_journey_menu))


func _build_ending_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "JourneyEndingView"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var panel := _titled_panel("此行已结", "JourneyEndingPanel")
	column.add_child(panel)
	var body := _panel_body(panel)
	var ending: Dictionary = _session.call("journey_ending")
	body.add_child(_make_label(str(ending.get("title", "初次下山")), 28, TEAL, true, "JourneyEndingTitle"))
	var prose := str(ending.get("text", "此行已经记下。")).split("\n\n")[0]
	body.add_child(_make_label(prose, 19, INK, true))
	body.add_child(_make_label(_clock_and_location_text(), 14, MUTED_INK, true, "JourneyEndingSummary"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	body.add_child(buttons)
	buttons.add_child(_make_button("保存此行", "JourneySaveButton", _save_current))
	buttons.add_child(_make_button("继续修行", "JourneyContinueButton", _continue_after_ending))
	buttons.add_child(_make_button("再来一局", "JourneyReplayButton", _request_new_run))
	return scroll


func _continue_after_ending() -> void:
	if _session == null or not _confirmation.is_empty():
		return
	if str(_snapshot().get("phase", "")) == "result":
		_session.call("acknowledge_result")
	_ending_dismissed_run = str(_snapshot().get("run_id", ""))
	_set_status("此行已记下。")
	_render()


func _on_ambush_retry(run_id: String, operation_id: String) -> void:
	_on_ambush_return(run_id, operation_id)


func audit_snapshot() -> Dictionary:
	var result := super.audit_snapshot()
	result["journey_menu_open"] = _journey_menu_open
	result["training_ground_open"] = not _training_context.is_empty()
	result["training_ground"] = _training_actor.call("presentation_snapshot") if is_instance_valid(_training_actor) else {}
	result["journey_ending_visible"] = bool(_snapshot().get("flags", {}).get("journey_complete", false)) and _ending_dismissed_run != str(_snapshot().get("run_id", ""))
	return result
