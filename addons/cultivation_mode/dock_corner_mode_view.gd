extends "res://addons/cultivation_mode/chengdu_mode_view.gd"
const DockWalker = preload("res://addons/cultivation_mode/dock_corner_walker.gd")
const DOCK_LAYOUT = "res://assets/data/dock-corner-layout.json"
const DOCK_SOURCE = "res://assets/art/dock_corner_20261113/source.json"
const DOCK_FONT_SOURCE = "res://assets/fonts/source-dock-corner.json"
const THROW_SOURCE = "res://assets/motion/dock_pebble/source.json"
const THROW_SOUND = preload("res://assets/audio/dock_pebble/plop.wav")
const THROW_CONFIG = "res://assets/data/dock-corner-pebble-motion.json"
var _dock_elapsed := 0.0
const DIALOGUE_UI = "res://assets/data/dock-corner-dialogue-ui.json"
var _dock_dialogue: PanelContainer

func _render() -> void:
	super._render()
	_dock_dialogue = null
	if _session==null or _view_mode!="game" or str(_snapshot().get("phase",""))!="event":
		return
	_dock_dialogue = _build_dock_dialogue()
	_screen.add_child(_dock_dialogue)
	# Existing modal surfaces retain input priority over the conversation.
	for name: String in ["CityMenuCover","CityConfirmationCover"]:
		var cover := _screen.get_node_or_null(name)
		if cover!=null:
			_screen.move_child(_dock_dialogue,cover.get_index())
	_layout_dock_dialogue()

func _build_phase_panel() -> PanelContainer:
	if _session!=null and str(_snapshot().get("phase",""))=="event":
		var empty := PanelContainer.new()
		empty.name = "PhasePanel"
		empty.visible = false
		return empty
	return super._build_phase_panel()

func _layout_dock_dialogue() -> void:
	if not is_instance_valid(_dock_dialogue):
		return
	var height: float = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_UI)).height
	_dock_dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dock_dialogue.offset_left = _horizontal_margin()
	_dock_dialogue.offset_right = -_horizontal_margin()
	_dock_dialogue.offset_bottom = -66.0 if _town_scene() else -16.0
	_dock_dialogue.offset_top = _dock_dialogue.offset_bottom-height

func _sync_responsive_sizes() -> void:
	super._sync_responsive_sizes()
	_layout_dock_dialogue()

func _build_dock_dialogue() -> PanelContainer:
	var event: Dictionary = _session.call("event_view")
	var panel := PanelContainer.new()
	panel.name = "DockDialoguePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",_panel_style(Color("#f5eddb"),Color("#8c8267"),10,2,16))
	_register_control(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",22)
	panel.add_child(row)
	var portrait_card := PanelContainer.new()
	portrait_card.name = "DockDialogueAvatarFrame"
	portrait_card.custom_minimum_size = Vector2(158,190)
	portrait_card.add_theme_stylebox_override("panel",_panel_style(Color("#e8dfc9"),Color("#b4a487"),7,1,5))
	row.add_child(portrait_card)
	var speaker := str(event.get("speaker",""))
	var portraits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_UI)).portraits
	if portraits.has(speaker):
		var record: Dictionary = portraits[speaker]
		var texture := load(str(record.texture)) as Texture2D
		if record.has("region"):
			var crop := AtlasTexture.new()
			crop.atlas = texture
			var region: Array = record.region
			crop.region = Rect2(region[0],region[1],region[2],region[3])
			texture = crop
		var avatar := TextureRect.new()
		avatar.name = "DockDialoguePortrait"
		avatar.texture = texture
		avatar.set_meta("speaker",speaker)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_card.add_child(avatar)
		_register_control(avatar)
	else:
		var narration := _make_label("见闻",24,TEAL,false,"DockDialogueNarration")
		narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		narration.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait_card.add_child(narration)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	row.add_child(content)
	_build_event_content(content,_snapshot())
	return panel
const DockLife = preload("res://addons/cultivation_mode/dock_corner_life.gd")
var _dock_life := DockLife.new()
var _dock_dynamic := true
var _dock_run_id := ""
var _dock_light_enabled := true
var _dock_time_light := "afternoon"
var _dock_pebble_count := 0
var _dock_splash_started := -99.0
var _dock_splash_from := Vector2.ZERO
var _dock_throw_age := -1.0
var _dock_hit_played := true
var _dock_sound_enabled := true
var _dock_sound: AudioStreamPlayer
var _dock_sound_count := 0
var _dock_cast_shadows := true
var _dock_motion: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THROW_CONFIG))

func _make_theme() -> Theme:
	var theme := super._make_theme()
	if ResourceLoader.exists("res://assets/fonts/ShuDockCornerSerif.ttf"):
		theme.default_font = load("res://assets/fonts/ShuDockCornerSerif.ttf") as Font
	return theme

func _next_city_step() -> String:
	return "点茶商、石阶或柳下标记，走近后互动 · 菜单保存" if _town_scene() else "听雨廊 · 可请教师父，或再去柳岸小埠"

func _build_header() -> PanelContainer:
	var panel := super._build_header()
	if _view_mode == "game" and _session != null:
		var row := panel.get_child(0).get_child(0)
		row.get_child(0).text = "蜀 · 柳岸小埠"
	return panel

func _build_scene_surface(scene_info: Dictionary) -> void:
	if str(_snapshot().get("scene", "")) != "dock_corner":
		super._build_scene_surface(scene_info)
		return
	_town_walker = DockWalker.new()
	_town_walker.name = "TownWalker"
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	_town_walker.call("setup", _session, "dock_corner", _current_pack().walks.scenes.dock_corner, _theme_resource.default_font, state.phase == "ready" and not _menu_open and _confirmation.is_empty())
	_town_walker.set("life",_dock_life)
	_town_walker.connect("interaction_requested", _on_town_interaction)
	_town_walker.connect("feedback", _on_town_feedback)
	_town_walker.call("present", _dock_elapsed)
	_town_walker.call("set_lighting", _dock_light_enabled)
	_town_walker.call("set_time_light",_dock_time_light)
	_town_walker.call("set_cast_shadows",_dock_cast_shadows)
	_town_walker.call("set_throw_age",_dock_throw_age)
	_town_walker.call("present",_dock_elapsed)
	if str(state.get("event",{}).get("id","")).begins_with("dock_keeper_"):
		_town_walker.get("_stage").call("face_keeper")

func _build_scene_column() -> Control:
	var column := super._build_scene_column()
	if not _town_scene():
		return column
	var row := HBoxContainer.new()
	row.name = "DockStops"
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var stops: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DOCK_LAYOUT)).waypoints
	for pair: Array in [["tea","茶棚前"],["mooring","岸边看船"],["steps","石阶上"]]:
		row.add_child(_make_button(pair[1], "DockStop_" + pair[0], _walk_to.bind(stops[pair[0]])))
	row.add_child(_make_button("景动" if _dock_dynamic else "静景", "DockMotionButton", _toggle_dock_motion))
	row.add_child(_make_button("午后光" if _dock_light_enabled else "原画光", "DockLightButton", _toggle_dock_light))
	row.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for pair: Array in [["morning","清晨"],["afternoon","午后"],["dusk","黄昏"],["moonlight","月夜"]]:
		var button := _make_button(pair[1],"DockTime_"+pair[0],_select_dock_time_light.bind(pair[0]))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(_dock_time_light==pair[0])
		button.tooltip_text = "光景预览，不推进游戏时辰"
		row.add_child(button)
	_update_dock_light_button(row.get_node("DockLightButton"))
	row.add_child(_make_button("水声开" if _dock_sound_enabled else "水声关","DockSoundButton",_toggle_dock_sound))
	row.add_child(_make_button("人物影开" if _dock_cast_shadows else "人物影关","DockShadowButton",_toggle_dock_shadows))
	return column

func _walk_to(point: Array) -> void:
	if _town_walker != null and not _menu_open and _confirmation.is_empty():
		_town_walker.call("walk_only", Vector2(point[0],point[1]))

func _toggle_dock_motion() -> void:
	_dock_dynamic = not _dock_dynamic
	_render()

func _process(delta: float) -> void:
	var state := _snapshot() if _session != null else {}
	if not state.is_empty():
		var run_id := str(state.get("run_id",""))
		var pebble_count := int(state.get("counts",{}).get("toss_dock_pebble",0))
		if run_id != _dock_run_id or pebble_count != _dock_pebble_count or str(state.get("scene",""))!="dock_corner":
			if run_id != _dock_run_id:
				_dock_elapsed = 0.0
				_dock_life.reset()
			_clear_dock_throw()
			_dock_run_id = run_id
			_dock_pebble_count = pebble_count
	var paused := _menu_open or not _confirmation.is_empty()
	if is_instance_valid(_dock_sound):
		_dock_sound.stream_paused = paused
	if _dock_throw_age>=0.0 and not paused:
		_dock_throw_age += minf(delta,0.05)
		var impact := float(_dock_motion.release)+float(_dock_motion.flight)
		if not _dock_hit_played and _dock_throw_age>=impact:
			_dock_hit_played = true
			if _dock_sound_enabled:
				_dock_sound.play()
				_dock_sound_count += 1
			_render()
		if _dock_throw_age>=impact+float(_dock_motion.ripple_duration):
			_dock_throw_age = -1.0
	if _town_walker != null and _town_walker is DockWalker:
		var focus := _dock_throw_age>=0.0
		if _dock_dynamic and (bool(_town_walker.call("_current")) or focus) and not paused:
			_dock_elapsed += minf(delta,0.05)
		_dock_life.advance(delta,_dock_dynamic,paused or not bool(_town_walker.call("_current")),_town_walker.get("player_position"),_dock_time_light)
		_town_walker.call("set_throw_age",_dock_throw_age)
		_town_walker.call("present",_dock_elapsed)
		if str(state.get("event",{}).get("id","")).begins_with("dock_keeper_"):
			_town_walker.get("_stage").call("face_keeper")
	_sync_dock_throw_controls()

func _throw_busy() -> bool:
	return _dock_throw_age>=0.0 and _dock_throw_age<float(_dock_motion.duration)

func _clear_dock_throw() -> void:
	_dock_throw_age = -1.0
	_dock_splash_started = -99.0
	_dock_hit_played = true
	if is_instance_valid(_dock_sound):
		_dock_sound.stop()

func _choose_option(option_id: String, captured_operation_id: String) -> void:
	if _throw_busy():
		return
	var before := _snapshot()
	var is_throw := option_id=="toss_pebble" and str(before.get("event",{}).get("id",""))=="dock_pebble"
	if is_throw:
		if _town_walker==null or not bool(_town_walker.get("_stage").call("can_throw")):
			_set_status("投石动作暂不可用。",true)
			return
		if not is_instance_valid(_dock_sound):
			_dock_sound = AudioStreamPlayer.new()
			_dock_sound.name = "DockWaterSound"
			_dock_sound.stream = THROW_SOUND
			_dock_sound.volume_db = -8.0
			add_child(_dock_sound)
	super._choose_option(option_id,captured_operation_id)
	var after := _snapshot()
	if is_throw and str(after.run_id)==str(before.run_id) and int(after.counts.get("toss_dock_pebble",0))==int(before.counts.get("toss_dock_pebble",0))+1:
		_dock_throw_age = 0.0
		_dock_hit_played = false
		_dock_splash_started = _dock_elapsed
		_dock_run_id = str(after.run_id)
		_dock_pebble_count = int(after.counts.get("toss_dock_pebble",0))
		_render()
		_sync_dock_throw_controls()

func _continue_event(captured_run_id: String = "", captured_revision: int = -1) -> void:
	if not _throw_busy():
		super._continue_event(captured_run_id,captured_revision)

func _cancel_event() -> void:
	if not _throw_busy():
		super._cancel_event()

func _build_event_content(parent: VBoxContainer, state: Dictionary) -> void:
	var event: Dictionary = _session.call("event_view")
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",18)
	parent.add_child(heading)
	var speaker := str(event.get("speaker_name",""))
	heading.add_child(_make_label(speaker if not speaker.is_empty() else "旁白",25,TEAL,false,"DockDialogueSpeaker"))
	var title := _make_label(str(event.get("title","")),14,MUTED_INK,false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(title)
	if _throw_busy() and _dock_throw_age<float(_dock_motion.release)+float(_dock_motion.flight) and str(state.get("event",{}).get("id",""))=="dock_pebble":
		var phase := _make_label("站稳 · 抬臂 · 出手",24,INK,true,"DockThrowPhaseLabel")
		phase.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(phase)
		parent.add_child(_make_button("投石中…","DialogContinueButton",Callable(),true))
		return
	var line := _make_label(str(event.get("text","")),24,INK,true,"DockDialogueText")
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(line)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",12)
	parent.add_child(controls)
	if str(event.get("type",""))=="choice":
		for option: Dictionary in event.get("options",[]):
			var id := str(option.id)
			var operation := _choice_operation_id(str(state.run_id),str(event.event_id),str(event.node_id),int(state.sequence),id)
			var button := _make_button(str(option.label),"ChoiceButton_"+_safe_name(id),_choose_option.bind(id,operation),not bool(option.get("enabled",false)))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(130,46)
			button.add_theme_font_size_override("font_size",18)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.tooltip_text = str(option.get("reason",""))
			controls.add_child(button)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(spacer)
		var button := _make_button("继续" if str(event.get("type",""))=="say" else "收起这段交谈","DialogContinueButton",_continue_event.bind(str(state.run_id),int(state.revision)))
		button.custom_minimum_size = Vector2(164,46)
		controls.add_child(button)
	if not _town_scene():
		controls.add_child(_make_button("结束交谈","DialogCancelButton",_cancel_event))

func _sync_dock_throw_controls() -> void:
	if _session==null or str(_snapshot().get("scene",""))!="dock_corner":
		return
	for id: String in ["DialogContinueButton","DialogCancelButton"]:
		var button := ui_control(id) as Button
		if button!=null:
			button.disabled = _throw_busy()
	var label := ui_control("DockThrowPhaseLabel") as Label
	if label!=null:
		label.text = "站稳" if _dock_throw_age<0.2 else ("抬臂蓄势" if _dock_throw_age<float(_dock_motion.release) else "出手 · 望向落点")

func _toggle_dock_sound() -> void:
	_dock_sound_enabled = not _dock_sound_enabled
	if not _dock_sound_enabled and is_instance_valid(_dock_sound):
		_dock_sound.stop()
	var button := ui_control("DockSoundButton") as Button
	if button!=null:
		button.text = "水声开" if _dock_sound_enabled else "水声关"

func _perform_launch(index: int, mode: String) -> void:
	_clear_dock_throw()
	super._perform_launch(index,mode)

func _toggle_dock_shadows() -> void:
	_dock_cast_shadows = not _dock_cast_shadows
	if _town_walker!=null and _town_walker is DockWalker:
		_town_walker.call("set_cast_shadows",_dock_cast_shadows)
	var button := ui_control("DockShadowButton") as Button
	if button!=null:
		button.text = "人物影开" if _dock_cast_shadows else "人物影关"

func _toggle_dock_light() -> void:
	_dock_light_enabled = not _dock_light_enabled
	if _town_walker != null and _town_walker is DockWalker:
		_town_walker.call("set_lighting", _dock_light_enabled)
	var button := ui_control("DockLightButton") as Button
	if button != null:
		_update_dock_light_button(button)

func _select_dock_time_light(id: String) -> void:
	# Presentation preview only: no clock command, cost, revision or save mutation.
	_dock_time_light = id
	_dock_light_enabled = true
	if _town_walker != null and _town_walker is DockWalker:
		_town_walker.call("set_time_light",id)
		_town_walker.call("set_lighting",true)
	var button := ui_control("DockLightButton") as Button
	if button != null:
		_update_dock_light_button(button)

func _update_dock_light_button(button: Button) -> void:
	var labels := {"morning":"清晨光","afternoon":"午后光","dusk":"黄昏光","moonlight":"月夜光"}
	button.text = str(labels[_dock_time_light]) if _dock_light_enabled else "原画光"
