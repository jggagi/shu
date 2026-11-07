extends "res://addons/cultivation_mode/journey_mode_view.gd"
## The existing journey host owns every action, checkpoint and battle result.
## This adapter brings the approved town presentation into that same chapter.

const TOWN_SOURCE_RECORD := "res://assets/data/unified-town-source.json"
var _street_motion := true


func _unified_town() -> bool:
	return _town_scene() and str(_current_pack().get("id", "")) == "shu_first_journey"


func _render() -> void:
	var carried: Dictionary = {}
	if _unified_town() and is_instance_valid(_town_walker) and _town_walker.is_visible_in_tree():
		var state := _snapshot()
		var context: Dictionary = _session.call("ambush_context")
		if context.is_empty() and str(state.run_id) == str(_town_walker.get("_run_id")) and str(state.scene) == str(_town_walker.get("scene_id")):
			carried = {"elapsed": _town_walker.call("get_presentation_elapsed"),
				"characters": _town_walker.call("get_character_presentation_state"),
				"camera": _town_walker.call("get_camera_presentation_state")}
	super._render()
	if not carried.is_empty() and _unified_town() and is_instance_valid(_town_walker) and _town_walker.is_visible_in_tree():
		_town_walker.call("set_presentation_elapsed", carried.elapsed)
		_town_walker.call("set_character_presentation_state", carried.characters)
		_town_walker.call("set_camera_presentation_state", carried.camera)


func _build_scene_surface(scene_info: Dictionary) -> void:
	if not _unified_town():
		super._build_scene_surface(scene_info)
		return
	_town_walker = HD2DWalkerScript.new() as Control
	_town_walker.name = "TownWalker"
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	var map_id := str(state.scene)
	# A view-only opt-in: the pack's original JSON/fingerprint stays unchanged.
	var map: Dictionary = _current_pack().walks.scenes[map_id].duplicate(true)
	map["character_reactions"] = true
	var enabled := str(state.phase) == "ready" and _confirmation.is_empty() and not _input_busy and not _journey_menu_open
	_town_walker.call("setup", _session, map_id, map, _theme_resource.default_font, enabled)
	_town_walker.call("set_motion_enabled", _street_motion)
	_town_walker.call("set_lighting_enabled", true)
	var partner := ""
	if str(state.phase) == "result" and str(state.get("last_result", {}).get("action_id", "")) in ["greet_tea_seller", "greet_tea_seller_again"]:
		partner = "tea_seller"
	_town_walker.call("set_conversation_role", partner)
	_town_walker.connect("interaction_requested", _on_town_interaction)
	_town_walker.connect("feedback", _on_town_feedback)


func _build_game_view() -> Control:
	if not _unified_town():
		return super._build_game_view()
	var state := _snapshot()
	if bool(state.get("flags", {}).get("journey_complete", false)) and _ending_dismissed_run != str(state.get("run_id", "")):
		return super._build_game_view()
	var body := VBoxContainer.new()
	body.name = "UnifiedTownColumns"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_left_column = null
	_right_column = null
	body.add_child(_build_scene_column())
	var flags: Dictionary = state.get("flags", {})
	if str(state.phase) == "ready" and bool(flags.get("journey_commission", false)) and not bool(flags.get("ambush_resolved", false)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var begin := _available_action("begin_ambush")
		row.add_child(_make_button("上山道 · 护药", "BeginAmbushButton", _start_ambush, not bool(begin.get("enabled", false))))
		row.add_child(_make_label("此役计1时辰", 14, MUTED_INK, false))
		body.add_child(row)
	return body


func _sync_responsive_sizes() -> void:
	super._sync_responsive_sizes()
	if _unified_town() and is_instance_valid(_scene_panel):
		_scene_panel.custom_minimum_size.y = 240


func _input(event: InputEvent) -> void:
	if _unified_town() and not _journey_menu_open and _confirmation.is_empty() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_4:
		_toggle_street_motion()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _toggle_street_motion() -> void:
	_street_motion = not _street_motion
	if is_instance_valid(_town_walker):
		_town_walker.call("set_motion_enabled", _street_motion)
	var toggle := ui_control("StreetMotionButton") as Button
	if is_instance_valid(toggle):
		toggle.text = "街景：动态" if _street_motion else "街景：静态"


func _add_journey_menu() -> void:
	super._add_journey_menu()
	if not _unified_town() or not _confirmation.is_empty():
		return
	var panel := ui_control("JourneyMenuPanel") as PanelContainer
	if panel == null:
		return
	var body := _panel_body(panel)
	var toggle := _make_button("街景：动态" if _street_motion else "街景：静态", "StreetMotionButton", _toggle_street_motion)
	body.add_child(toggle)
	body.move_child(toggle, 2)
	var help := _make_label("滚轮或±缩放 · 放大后中键拖动 · 全景复位 · 4切换动静", 14, MUTED_INK, true)
	body.add_child(help)
	body.move_child(help, 3)


func audit_snapshot() -> Dictionary:
	var result := super.audit_snapshot()
	result["unified_town"] = _unified_town()
	result["street_motion"] = _street_motion
	return result
