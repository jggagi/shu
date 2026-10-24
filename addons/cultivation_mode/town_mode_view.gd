extends "res://addons/cultivation_mode/mode_view.gd"
## P1b entry: keeps the existing cultivation UI for mountain and stream packs.

const TownWalkerScript = preload("res://addons/cultivation_mode/town_walker.gd")
var _town_walker: Control
var _town_feedback: Label
var _town_interactions := 0
var _town_audit_run := ""


func _town_scene() -> bool:
	if _session == null or _view_mode != "game":
		return false
	var maps: Dictionary = _current_pack().get("walks", {}).get("scenes", {})
	return maps.has(str(_snapshot().get("scene", "")))


func audit_snapshot() -> Dictionary:
	var result := super.audit_snapshot()
	var run_id := str(_snapshot().get("run_id", ""))
	if _town_audit_run != run_id:
		_town_audit_run = run_id
		_town_interactions = 0
	result["town"] = _town_walker.call("audit") if is_instance_valid(_town_walker) and _town_scene() else {}
	if not result.town.is_empty():
		result.town["interaction_count"] = _town_interactions
	return result


func _render() -> void:
	if is_instance_valid(_town_walker):
		_town_walker.call("cancel_walk")
		_town_walker.set("active", false)
	_town_walker = null
	super._render()


func _build_header() -> PanelContainer:
	var header := super._build_header()
	if _town_scene():
		var eyebrow := header.get_child(0).get_child(0).get_child(0).get_child(0) as Label
		eyebrow.text = "蜀 · 街口走走"
	return header


func _build_scene_column() -> Control:
	var column := super._build_scene_column()
	if _town_scene():
		var heading := column.get_node("SceneHeading")
		var instruction := heading.get_child(heading.get_child_count() - 1) as Label
		instruction.text = "点石路行走 · 走近互动"
	return column


func _build_game_view() -> Control:
	if not _town_scene():
		return super._build_game_view()
	var body := HBoxContainer.new()
	body.name = "TownColumns"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	_left_column = null
	var center := _build_scene_column()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation",10)
	_right_column = sidebar
	body.add_child(sidebar)
	if not _confirmation.is_empty():
		sidebar.add_child(_build_confirmation_panel("InlineConfirmation"))
	sidebar.add_child(_build_stats_panel())
	var note := _titled_panel("街口行走", "TownHelpPanel")
	var content := _panel_body(note)
	content.add_child(_make_label("点空地绕过摊棚；点掌柜、木牌或返山石阶，走近后互动。",16,INK,true))
	content.add_child(_make_label("行走、阅读免费。返山花一时辰，不扣精力。",15,TEAL,true))
	_town_feedback = _make_label("可随时存档，继续时回到原地。",14,MUTED_INK,true,"TownFeedback")
	content.add_child(_town_feedback)
	sidebar.add_child(note)
	sidebar.add_child(_build_journal_panel())
	return body


func _build_scene_surface(scene_info: Dictionary) -> void:
	if not _town_scene():
		super._build_scene_surface(scene_info)
		return
	_town_walker = TownWalkerScript.new() as Control
	_town_walker.name = "TownWalker"
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	var map_id := str(state.scene)
	var map: Dictionary = _current_pack().walks.scenes[map_id]
	var enabled := str(state.phase) == "ready" and _confirmation.is_empty() and not _input_busy
	_town_walker.call("setup",_session,map_id,map,_theme_resource.default_font,enabled)
	_town_walker.connect("interaction_requested",_on_town_interaction)
	_town_walker.connect("feedback",_on_town_feedback)


func _build_phase_panel() -> PanelContainer:
	var panel := super._build_phase_panel()
	if _town_scene() and str(_snapshot().phase) == "ready":
		panel.custom_minimum_size.y = 0
		var content := panel.get_node("PhaseContent") as VBoxContainer
		for child in content.get_children():
			child.queue_free()
			content.remove_child(child)
		content.add_child(_make_label("在街口走走，也可随时沿石阶返山。",15,TEAL,true))
	elif _town_scene():
		panel.custom_minimum_size.y = 112
	return panel


func _sync_responsive_sizes() -> void:
	if not _town_scene():
		super._sync_responsive_sizes()
		return
	if is_instance_valid(_right_column):
		_right_column.custom_minimum_size.x = 240 if get_viewport_rect().size.x < 1260 else 270
	if is_instance_valid(_scene_panel):
		_scene_panel.custom_minimum_size.y = 310 if get_viewport_rect().size.y < 690 else 380
	if is_instance_valid(_body_margin):
		_body_margin.add_theme_constant_override("margin_left",_horizontal_margin())
		_body_margin.add_theme_constant_override("margin_right",_horizontal_margin())


func _on_town_feedback(message: String) -> void:
	if is_instance_valid(_town_feedback):
		_town_feedback.text = message


func _on_town_interaction(id: String, captured_run_id: String, captured_revision: int) -> void:
	if _input_busy or not _confirmation.is_empty() or not _town_scene():
		return
	var state := _snapshot()
	if str(state.run_id) != captured_run_id or int(state.revision) != captured_revision:
		return
	_input_busy = true
	var operation := "%s:walk:%d:%s" % [captured_run_id,captured_revision,id]
	var result: Dictionary = _session.call("execute_walk_interaction",id,operation,captured_run_id,captured_revision)
	_input_busy = false
	if bool(result.get("ok",false)):
		_town_interactions += 1
	_set_status("走近后，留下一段街口见闻。" if bool(result.get("ok",false)) else str(result.get("reason","暂时不能互动。")),not bool(result.get("ok",false)))
	_render()
