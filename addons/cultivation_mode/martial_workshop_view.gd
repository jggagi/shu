extends Control
class_name MartialWorkshopView
## A local review desk over an independent battle presentation, never a Session.

signal closed

const StageScript = preload("res://addons/cultivation_mode/ambush_stage.gd")
const REVIEW_PATH := "user://martial_workshop/reviews.json"
const INK := Color("#304139")
const MUTED := Color("#727b6c")
const PAPER := Color("#f0eadc")
const LIGHT := Color("#faf6ec")
const LINE := Color("#c8c7b4")
const GREEN := Color("#426c5b")
const RED := Color("#a35642")
const STATUS_LABELS := {"pending": "待审阅", "accepted": "已通过", "needs_revision": "待修改"}

var _definition: Dictionary = {}
var _state: Dictionary = {}
var _catalog: Dictionary = {}
var _catalog_hash := ""
var _moves: Dictionary = {}
var _move_order: Array[String] = []
var _visible_ids: Array[String] = []
var _selected_id := ""
var _selected_variant_id := "original"
var _previous_id := ""
var _category_filter := "all"
var _style_filter := "all"
var _speed := 1.0
var _camera_mode := "close"
var _closed := false
var _stage_ready := false
var _stage: Control
var _controls: Dictionary = {}
var _move_buttons: Dictionary = {}
var _reviews: Dictionary = {}
var _previous_catalogs: Array = []
var _review_error := ""
var _review_read_blocked := false
var _review_invalidated := false
var _loading_reason := false
var _dirty_reason := false
var _timeline_dragging := false
var _timeline_stopped := true
var _transport_feedback := false
var _drag_was_paused := false
var _category_choice: OptionButton
var _style_choice: OptionButton
var _speed_choice: OptionButton
var _camera_choice: OptionButton
var _variant_choice: OptionButton
var _variant_compare_button: Button
var _pause_button: Button
var _compare_button: Button
var _name_label: Label
var _description_label: Label
var _phase_label: Label
var _time_label: Label
var _count_label: Label
var _review_label: Label
var _feedback_label: Label
var _empty_label: Label
var _reason_edit: TextEdit
var _timeline: HSlider


func setup(font: Font, definition: Dictionary, state: Dictionary, catalog: Dictionary) -> void:
	_definition = definition.duplicate(true)
	_state = state.duplicate(true)
	_catalog = catalog.duplicate(true)
	_catalog_hash = str(_catalog.get("catalog_sha256", ""))
	if _catalog_hash.is_empty():
		_catalog_hash = JSON.stringify(_catalog, "", true).sha256_text()
	for entry: Variant in _catalog.get("moves", []):
		if not entry is Dictionary:
			continue
		var move: Dictionary = entry
		var id := str(move.get("id", ""))
		if id.is_empty() or _moves.has(id):
			continue
		_moves[id] = move.duplicate(true)
		_move_order.append(id)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 45
	_build_theme(font)
	_build()
	reload_reviews()
	_build_stage(font)
	if _moves.has("sword_cleave"):
		select_move("sword_cleave")
	_apply_filters()
	set_process(true)
	set_process_input(true)
	if _stage_ready:
		_set_feedback("本轮重做：落雁斩、劲风掌；播放后可同刻对照。审阅只保存在本机。")
		if _review_invalidated:
			_set_feedback("资源已更新，本批招式重新待审；旧审阅记录仍保留。")
	if not _review_error.is_empty():
		_set_feedback(_review_error, true)


func _build_theme(font: Font) -> void:
	var style := Theme.new()
	style.default_font = font if font != null else ThemeDB.fallback_font
	style.default_font_size = 15
	for kind: String in ["Label", "Button", "OptionButton", "TextEdit"]:
		style.set_color("font_color", kind, INK)
	for kind: String in ["Button", "OptionButton"]:
		for state: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			style.set_color(state, kind, INK)
		style.set_stylebox("normal", kind, _panel(LIGHT, LINE, 7, 6))
		style.set_stylebox("hover", kind, _panel(Color("#e5ebdf"), GREEN, 7, 6))
		style.set_stylebox("pressed", kind, _panel(Color("#d1dfce"), GREEN, 7, 6))
		style.set_stylebox("disabled", kind, _panel(Color("#e5e2d7"), LINE, 7, 6))
		style.set_color("font_disabled_color", kind, Color("#969b8d"))
	style.set_stylebox("normal", "TextEdit", _panel(LIGHT, LINE, 8, 6))
	style.set_stylebox("focus", "TextEdit", _panel(LIGHT, GREEN, 8, 6))
	theme = style


func _panel(fill: Color, border: Color, horizontal: int = 10, vertical: int = 8) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(6)
	result.content_margin_left = horizontal
	result.content_margin_right = horizontal
	result.content_margin_top = vertical
	result.content_margin_bottom = vertical
	return result


func _label(text: String, id: String = "", font_size: int = 15, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if not id.is_empty():
		result.name = id
		_controls[id] = result
	return result


func _button(text: String, id: String, callback: Callable) -> Button:
	var result := Button.new()
	result.name = id
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.custom_minimum_size.y = 32
	result.pressed.connect(callback)
	_controls[id] = result
	return result


func _choice(id: String, labels: Array, callback: Callable, minimum_width: float) -> OptionButton:
	var result := OptionButton.new()
	result.name = id
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size = Vector2(minimum_width, 32)
	for text: String in labels:
		result.add_item(text)
	result.item_selected.connect(callback)
	_controls[id] = result
	return result


func _build() -> void:
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_label("武学工坊", "WorkshopTitleLabel", 25))
	var subtitle := _label("试演 · 对照 · 本机审阅", "", 14, MUTED)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	header.add_child(_button("回到战斗", "WorkshopCloseButton", _close))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 9)
	column.add_child(filters)
	filters.add_child(_label("类别"))
	_category_choice = _choice("WorkshopCategoryChoice", ["全部武学", "剑法", "掌法"], _change_category, 112)
	filters.add_child(_category_choice)
	filters.add_child(_label("风格"))
	_style_choice = _choice("WorkshopStyleChoice", ["全部风格", "轻灵", "刚劲"], _change_style, 112)
	filters.add_child(_style_choice)
	_count_label = _label("", "WorkshopCountLabel", 14, MUTED)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	filters.add_child(_count_label)
	var variants := HBoxContainer.new()
	variants.add_theme_constant_override("separation", 9)
	column.add_child(variants)
	variants.add_child(_label("动作版本"))
	_variant_choice = _choice("WorkshopVariantChoice", ["原版"], _change_variant, 112)
	_variant_choice.set_item_metadata(0, "original")
	variants.add_child(_variant_choice)
	_variant_compare_button = _button("同刻对照：增强版", "WorkshopVariantCompareButton", _compare_variant)
	_variant_compare_button.tooltip_text = "在同一招的相同时间切换动作版本，保留暂停、速度与镜头；切换采样无声。"
	variants.add_child(_variant_compare_button)
	var variant_hint := _label("同一时间 · 相同劲气与声音", "WorkshopVariantHintLabel", 14, MUTED)
	variant_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	variant_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	variants.add_child(variant_hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	column.add_child(body)
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size.x = 202
	list_panel.add_theme_stylebox_override("panel", _panel(Color("#e8e5d8"), LINE, 8, 8))
	body.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "WorkshopMoveList"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)
	_controls[scroll.name] = scroll
	var move_column := VBoxContainer.new()
	move_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_column.add_theme_constant_override("separation", 6)
	scroll.add_child(move_column)
	for id: String in _move_order:
		var pick := _button("", "WorkshopMove_" + id, select_move.bind(id))
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.custom_minimum_size = Vector2(176, 42)
		pick.clip_text = true
		move_column.add_child(pick)
		_move_buttons[id] = pick
	_empty_label = _label("没有符合条件的招式", "WorkshopEmptyLabel", 14, MUTED)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_column.add_child(_empty_label)
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 5)
	body.add_child(preview)
	_name_label = _label("", "WorkshopNameLabel", 20)
	preview.add_child(_name_label)
	_description_label = _label("", "WorkshopDescriptionLabel", 14, GREEN)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.max_lines_visible = 2
	_description_label.custom_minimum_size.y = 36
	preview.add_child(_description_label)
	var stage_frame := PanelContainer.new()
	stage_frame.name = "WorkshopStageFrame"
	stage_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_frame.custom_minimum_size.y = 160
	stage_frame.add_theme_stylebox_override("panel", _panel(Color("#cbd3be"), Color("#adb8a3"), 2, 2))
	preview.add_child(stage_frame)
	_controls[stage_frame.name] = stage_frame
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 6)
	preview.add_child(transport)
	transport.add_child(_button("播放", "WorkshopPlayButton", _play))
	transport.add_child(_button("停止", "WorkshopStopButton", _stop))
	_pause_button = _button("暂停", "WorkshopPauseButton", _toggle_pause)
	transport.add_child(_pause_button)
	_speed_choice = _choice("WorkshopSpeedChoice", ["1×速度", "0.5×速度"], _change_speed, 100)
	_speed_choice.tooltip_text = "改变速度时，从起势重新试演。"
	transport.add_child(_speed_choice)
	_camera_choice = _choice("WorkshopCameraChoice", ["战术镜头", "正面镜头", "侧面镜头", "近看动作"], _change_camera, 112)
	_camera_choice.select(3)
	transport.add_child(_camera_choice)
	_compare_button = _button("对照上一招", "WorkshopCompareButton", _compare_previous)
	_compare_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compare_button.clip_text = true
	transport.add_child(_compare_button)
	var timeline_row := HBoxContainer.new()
	timeline_row.add_theme_constant_override("separation", 7)
	preview.add_child(timeline_row)
	_phase_label = _label("待机", "WorkshopPhaseLabel", 14, GREEN)
	_phase_label.custom_minimum_size.x = 72
	timeline_row.add_child(_phase_label)
	_timeline = HSlider.new()
	_timeline.name = "WorkshopTimelineSlider"
	_timeline.min_value = 0.0
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.focus_mode = Control.FOCUS_NONE
	_timeline.custom_minimum_size.y = 24
	_timeline.value_changed.connect(_seek)
	_timeline.drag_started.connect(_begin_scrub)
	_timeline.drag_ended.connect(_end_scrub)
	_controls[_timeline.name] = _timeline
	timeline_row.add_child(_timeline)
	_time_label = _label("", "WorkshopTimeLabel", 14, MUTED)
	_time_label.custom_minimum_size.x = 112
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timeline_row.add_child(_time_label)
	var review_panel := PanelContainer.new()
	review_panel.add_theme_stylebox_override("panel", _panel(Color("#e6e8da"), LINE, 10, 7))
	column.add_child(review_panel)
	var review_column := VBoxContainer.new()
	review_column.add_theme_constant_override("separation", 5)
	review_panel.add_child(review_column)
	var review_actions := HBoxContainer.new()
	review_actions.add_theme_constant_override("separation", 8)
	review_column.add_child(review_actions)
	_review_label = _label("待审阅", "WorkshopReviewStatusLabel", 17, GREEN)
	_review_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_actions.add_child(_review_label)
	review_actions.add_child(_button("通过", "WorkshopAcceptButton", _mark_review.bind("accepted")))
	review_actions.add_child(_button("退回修改", "WorkshopReturnButton", _mark_review.bind("needs_revision")))
	review_actions.add_child(_button("重置审阅", "WorkshopPendingButton", _mark_review.bind("pending")))
	_reason_edit = TextEdit.new()
	_reason_edit.name = "WorkshopReasonEdit"
	_reason_edit.placeholder_text = "审阅意见；退回修改时，请写明需要调整的地方。"
	_reason_edit.custom_minimum_size.y = 42
	_reason_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_reason_edit.text_changed.connect(_reason_changed)
	_reason_edit.focus_exited.connect(_flush_reason)
	_controls[_reason_edit.name] = _reason_edit
	review_column.add_child(_reason_edit)
	_feedback_label = _label("", "WorkshopFeedbackLabel", 14, MUTED)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.max_lines_visible = 2
	_feedback_label.custom_minimum_size.y = 20
	column.add_child(_feedback_label)


func _build_stage(font: Font) -> void:
	_stage = StageScript.new() as Control
	_stage.name = "WorkshopStage"
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls[_stage.name] = _stage
	(ui_control("WorkshopStageFrame") as PanelContainer).add_child(_stage)
	_stage.call("setup", _definition.duplicate(true), font)
	_stage.call("sync_state", _state.duplicate(true), "player", [], {})
	if not _stage.has_method("set_workshop_catalog"):
		_set_feedback("演武场尚未就绪，请稍后再试。", true)
		return
	var result: Variant = _stage.call("set_workshop_catalog", _catalog.duplicate(true))
	_stage_ready = result is Dictionary and bool(result.get("ok", false))
	if not _stage_ready:
		_set_feedback(str(result.get("reason", "招式目录未能载入")) if result is Dictionary else "招式目录未能载入", true)
	elif _stage.has_method("set_workshop_camera"):
		_stage.call("set_workshop_camera", _camera_mode)


func _process(_delta: float) -> void:
	if _closed:
		return
	var data := _player_audit()
	var matches := _matches_audit(data)
	var active := bool(data.get("active", false)) and matches and not _timeline_stopped
	var paused := bool(data.get("paused", false))
	var elapsed := _display_elapsed(data)
	var total := _move_total()
	if matches:
		total = maxf(0.001, float(data.get("total", total)))
	_timeline.max_value = total
	if not _timeline_dragging:
		_timeline.set_value_no_signal(clampf(elapsed, 0.0, total))
	_time_label.text = "%.2f / %.2f秒" % [elapsed, total]
	_phase_label.text = _phase_text(str(data.get("phase", "idle"))) if active else ("已结束" if not _timeline_stopped and matches and elapsed >= total else "待机")
	_pause_button.text = "继续" if paused and active else "暂停"
	_pause_button.disabled = not active or not _stage_ready
	(ui_control("WorkshopPlayButton") as Button).disabled = _selected_id.is_empty() or not _stage_ready
	(ui_control("WorkshopStopButton") as Button).disabled = (not active and _timeline_stopped) or not _stage_ready
	_timeline.editable = not _selected_id.is_empty() and _stage_ready
	if _transport_feedback and matches and not active and not _timeline_stopped:
		var reason := str(data.get("reason", ""))
		if not reason.is_empty():
			_set_feedback(_selected_label() + " · " + reason, true)
		else:
			_set_feedback(_selected_label() + " · 试演已结束；可拖动时间线查看。")


func _player_audit() -> Dictionary:
	if not is_instance_valid(_stage) or not _stage.has_method("workshop_audit"):
		return {}
	var result: Variant = _stage.call("workshop_audit")
	if not result is Dictionary:
		return {}
	var data: Dictionary = result
	if data.get("player") is Dictionary:
		data = data.player
	return data.duplicate(true)


func _phase_text(phase: String) -> String:
	return str({"idle": "待机", "ready": "起势", "charge": "蓄势", "gather": "蓄势", "release": "出手", "strike": "出手", "flight": "劲气前行", "impact": "命中", "hit_stop": "命中短停", "follow": "余势", "follow_through": "余势", "recover": "收势", "recovery": "收势", "settle": "收势", "finished": "已结束"}.get(phase, "试演中"))


func _matches_audit(data: Dictionary) -> bool:
	return str(data.get("move_id", "")) == _selected_id and str(data.get("variant_id", "original")) == _selected_variant_id


func _display_elapsed(data: Dictionary) -> float:
	if _timeline_stopped or not _matches_audit(data):
		return 0.0
	return float(data.get("elapsed", 0.0))


func _selected_move() -> Dictionary:
	var move: Dictionary = _moves.get(_selected_id, {})
	if _selected_variant_id != "original":
		return move.get("variants", {}).get(_selected_variant_id, {}) as Dictionary
	return move


func _available_variants(id: String = "") -> Array[String]:
	var result: Array[String] = ["original"]
	var move: Dictionary = _moves.get(id if not id.is_empty() else _selected_id, {})
	var variants: Dictionary = move.get("variants", {})
	for variant_id: String in variants:
		if variant_id != "original" and variants[variant_id] is Dictionary:
			result.append(variant_id)
	return result


func _variant_label(variant_id: String = "") -> String:
	var requested := variant_id if not variant_id.is_empty() else _selected_variant_id
	if requested == "original":
		return "原版"
	var move: Dictionary = (_moves.get(_selected_id, {}) as Dictionary).get("variants", {}).get(requested, {})
	return str(move.get("variant_label", "增强版"))


func _selected_label() -> String:
	return str(_selected_move().get("label", "")) + " · " + _variant_label()


func _review_key(id: String = "", variant_id: String = "") -> String:
	var requested_id := id if not id.is_empty() else _selected_id
	var requested_variant := variant_id if not variant_id.is_empty() else _selected_variant_id
	return requested_id if requested_variant == "original" else requested_id + "@" + requested_variant


func _move_total() -> float:
	var move := _selected_move()
	var timing: Dictionary = move.get("timing", {})
	return maxf(0.001, float(timing.get("total", timing.get("duration", 1.0))))


func _change_category(index: int) -> void:
	_category_filter = str(["all", "sword", "palm"][clampi(index, 0, 2)])
	_apply_filters()


func _change_style(index: int) -> void:
	_style_filter = str(["all", "light", "strong"][clampi(index, 0, 2)])
	_apply_filters()


func _apply_filters() -> void:
	_visible_ids.clear()
	for id: String in _move_order:
		var move: Dictionary = _moves[id]
		var shown := (_category_filter == "all" or str(move.get("category", "")) == _category_filter) and (_style_filter == "all" or str(move.get("style", "")) == _style_filter)
		(_move_buttons[id] as Button).visible = shown
		if shown:
			_visible_ids.append(id)
	_empty_label.visible = _visible_ids.is_empty()
	_count_label.text = "%d / %d招 · 试演不扣行动" % [_visible_ids.size(), _move_order.size()]
	if not _selected_id in _visible_ids:
		select_move(_visible_ids[0] if not _visible_ids.is_empty() else "")
	_refresh_move_buttons()


func select_move(id: String) -> void:
	if _closed or (not id.is_empty() and not _moves.has(id)):
		return
	_flush_reason()
	_stop()
	if id != _selected_id and not _selected_id.is_empty():
		_previous_id = _selected_id
	_selected_id = id
	_selected_variant_id = "enhanced" if "enhanced" in _available_variants(id) else "original"
	if is_instance_valid(_stage):
		var move: Dictionary = _moves.get(id, {})
		_stage.call("sync_state", _state.duplicate(true), str(move.get("actor", "player")), [], {})
		if not id.is_empty() and _stage.has_method("show_workshop_move"):
			_stage.call("show_workshop_move", id, _selected_variant_id)
		if _stage.has_method("set_workshop_camera"):
			_stage.call("set_workshop_camera", _camera_mode)
	_refresh_selected()


func _refresh_selected(reset_timeline: bool = true) -> void:
	var move := _selected_move()
	_name_label.text = _selected_label() if not move.is_empty() else "请选择招式"
	_refresh_variant_controls()
	var category := "剑法" if str(move.get("category", "")) == "sword" else "掌法"
	var style := "轻灵" if str(move.get("style", "")) == "light" else "刚劲"
	_description_label.text = "%s · %s  %s" % [category, style, str(move.get("description", ""))] if not move.is_empty() else "可调整筛选，选择要试演的武学。"
	_loading_reason = true
	_reason_edit.text = str((_reviews.get(_review_key(), {}) as Dictionary).get("reason", ""))
	_loading_reason = false
	_dirty_reason = false
	_reason_edit.editable = not _selected_id.is_empty()
	for id: String in ["WorkshopAcceptButton", "WorkshopReturnButton", "WorkshopPendingButton"]:
		(ui_control(id) as Button).disabled = _selected_id.is_empty()
	_compare_button.disabled = _previous_id.is_empty() or not _moves.has(_previous_id)
	_compare_button.text = "对照上一招：" + str((_moves.get(_previous_id, {}) as Dictionary).get("label", "")) if not _previous_id.is_empty() else "对照上一招"
	_compare_button.tooltip_text = "切换到上一招，再点播放；可反复交换对照。"
	_timeline.max_value = _move_total()
	if reset_timeline:
		_timeline.set_value_no_signal(0.0)
	_refresh_review_status()
	_refresh_move_buttons()


func _refresh_variant_controls() -> void:
	_variant_choice.clear()
	var variants := _available_variants()
	for variant_id: String in variants:
		_variant_choice.add_item(_variant_label(variant_id))
		_variant_choice.set_item_metadata(_variant_choice.item_count - 1, variant_id)
	_variant_choice.select(maxi(0, variants.find(_selected_variant_id)))
	_variant_choice.disabled = variants.size() < 2 or not _stage_ready
	_variant_compare_button.disabled = variants.size() < 2 or not _stage_ready
	_variant_compare_button.text = "同刻对照：" + ("增强版" if _selected_variant_id == "original" else "原版")
	_variant_choice.tooltip_text = "保留当前时点切换动作版本。" if variants.size() > 1 else "这招目前仅有原版动作。"


func _change_variant(index: int) -> void:
	if index < 0 or index >= _variant_choice.item_count:
		return
	select_variant(str(_variant_choice.get_item_metadata(index)))


func _compare_variant() -> void:
	var variants := _available_variants()
	if variants.size() < 2:
		return
	var next := (variants.find(_selected_variant_id) + 1) % variants.size()
	select_variant(variants[next])


func select_variant(variant_id: String) -> void:
	if _closed or not _stage_ready or _selected_id.is_empty() or variant_id == _selected_variant_id or not variant_id in _available_variants():
		return
	_flush_reason()
	var data := _player_audit()
	var elapsed := _display_elapsed(data)
	var was_active := bool(data.get("active", false)) and _matches_audit(data) and not _timeline_stopped
	var was_paused := bool(data.get("paused", false))
	var was_stopped := _timeline_stopped
	_stage.call("stop_workshop_move")
	_selected_variant_id = variant_id
	_timeline_dragging = false
	if not was_stopped:
		# Begin and pause before yielding; seek samples without replaying earlier cues.
		_stage.call("preview_workshop_move", _selected_id, _speed, _selected_variant_id)
		_stage.call("set_workshop_paused", true)
		_stage.call("seek_workshop_move", elapsed)
		_stage.call("set_workshop_camera", _camera_mode)
		_stage.call("set_workshop_paused", was_paused if was_active else true)
	else:
		_stage.call("show_workshop_move", _selected_id, _selected_variant_id)
		_stage.call("set_workshop_camera", _camera_mode)
	_timeline_stopped = was_stopped
	_refresh_selected(false)
	_timeline.set_value_no_signal(elapsed)
	_set_feedback(_selected_label() + (" · 已在同一时点切换" if not was_stopped else " · 已切换动作版本"))
	_transport_feedback = was_active


func _refresh_move_buttons() -> void:
	for id: String in _move_order:
		var button: Button = _move_buttons[id]
		var move: Dictionary = _moves[id]
		var key := _review_key() if id == _selected_id else id
		var status := str((_reviews.get(key, {}) as Dictionary).get("status", "pending"))
		button.text = str(move.get("label", id)) + " · " + str(STATUS_LABELS.get(status, "待审阅"))
		button.tooltip_text = str(move.get("description", "")) + ("\n当前审阅：" + _variant_label() if id == _selected_id else "\n原版审阅")
		button.add_theme_stylebox_override("normal", _panel(Color("#d6e2d0") if id == _selected_id else LIGHT, GREEN if id == _selected_id else LINE, 8, 7))


func _play() -> void:
	if not _stage_ready or _selected_id.is_empty() or not is_instance_valid(_stage):
		return
	_stage.call("stop_workshop_move")
	_timeline_stopped = false
	_stage.call("preview_workshop_move", _selected_id, _speed, _selected_variant_id)
	_set_feedback(_selected_label() + " · 正在试演")
	_transport_feedback = true


func _stop() -> void:
	_timeline_dragging = false
	_timeline_stopped = true
	if is_instance_valid(_stage) and _stage.has_method("stop_workshop_move"):
		_stage.call("stop_workshop_move")
	if is_instance_valid(_timeline):
		_timeline.set_value_no_signal(0.0)
	if not _selected_id.is_empty():
		_set_feedback(_selected_label() + " · 已停止，回到起势。")


func _toggle_pause() -> void:
	var data := _player_audit()
	if is_instance_valid(_stage) and bool(data.get("active", false)):
		var pause := not bool(data.get("paused", false))
		_stage.call("set_workshop_paused", pause)
		_set_feedback(_selected_label() + (" · 已暂停" if pause else " · 正在试演"))
		_transport_feedback = true


func _change_speed(index: int) -> void:
	_speed = 0.5 if index == 1 else 1.0
	if bool(_player_audit().get("active", false)):
		_play()
		_set_feedback("速度已调整，从起势重新试演。")
		_transport_feedback = true


func _change_camera(index: int) -> void:
	_camera_mode = str(["tactical", "front", "side", "close"][clampi(index, 0, 3)])
	if is_instance_valid(_stage) and _stage.has_method("set_workshop_camera"):
		_stage.call("set_workshop_camera", _camera_mode)


func _compare_previous() -> void:
	if _previous_id.is_empty() or not _moves.has(_previous_id):
		return
	var previous := _previous_id
	if not previous in _visible_ids:
		_category_filter = "all"
		_style_filter = "all"
		_category_choice.select(0)
		_style_choice.select(0)
	select_move(previous)
	_apply_filters()
	_set_feedback("已切到上一招，点播放即可对照。")


func _seek(seconds: float) -> void:
	if not _stage_ready or _selected_id.is_empty() or not is_instance_valid(_stage):
		return
	if not bool(_player_audit().get("active", false)):
		_play()
		_stage.call("set_workshop_paused", true)
	_stage.call("seek_workshop_move", clampf(seconds, 0.0, _move_total()))
	_set_feedback(_selected_label() + (" · 已暂停查看" if bool(_player_audit().get("paused", false)) else " · 正在试演"))
	_transport_feedback = true


func _begin_scrub() -> void:
	_timeline_dragging = true
	var data := _player_audit()
	_drag_was_paused = bool(data.get("paused", false)) or not bool(data.get("active", false))
	if bool(data.get("active", false)) and is_instance_valid(_stage):
		_stage.call("set_workshop_paused", true)


func _end_scrub(_changed: bool) -> void:
	_timeline_dragging = false
	if is_instance_valid(_stage) and bool(_player_audit().get("active", false)):
		_stage.call("set_workshop_paused", _drag_was_paused)
		_set_feedback(_selected_label() + (" · 已暂停查看" if _drag_was_paused else " · 正在试演"))
		_transport_feedback = true


func _set_feedback(text: String, error: bool = false) -> void:
	_transport_feedback = false
	if is_instance_valid(_feedback_label):
		_feedback_label.text = text
		_feedback_label.add_theme_color_override("font_color", RED if error else MUTED)


func _review_status() -> String:
	return str((_reviews.get(_review_key(), {}) as Dictionary).get("status", "pending"))


func _refresh_review_status() -> void:
	var status := _review_status()
	_review_label.text = "本机审阅 · " + _variant_label() + " · " + str(STATUS_LABELS.get(status, "待审阅"))
	_review_label.add_theme_color_override("font_color", RED if status == "needs_revision" else GREEN)


func _reason_changed() -> void:
	if not _loading_reason:
		_dirty_reason = true


func _flush_reason() -> void:
	if not _dirty_reason or _selected_id.is_empty() or not is_instance_valid(_reason_edit):
		return
	var previous: Dictionary = _reviews.duplicate(true)
	var entry: Dictionary = (_reviews.get(_review_key(), {}) as Dictionary).duplicate(true)
	entry["status"] = str(entry.get("status", "pending"))
	entry["reason"] = _reason_edit.text.strip_edges()
	_reviews[_review_key()] = entry
	if _save_reviews():
		_dirty_reason = false
	else:
		_reviews = previous
		_set_feedback(_review_error, true)


func _mark_review(status: String) -> void:
	if _selected_id.is_empty() or not STATUS_LABELS.has(status):
		return
	var reason := _reason_edit.text.strip_edges()
	if status == "needs_revision" and reason.is_empty():
		_set_feedback("请先写明需要修改的原因，再退回。", true)
		_reason_edit.grab_focus()
		return
	var previous: Dictionary = _reviews.duplicate(true)
	_reviews[_review_key()] = {"status": status, "reason": reason, "updated_unix": int(Time.get_unix_time_from_system())}
	if not _save_reviews():
		_reviews = previous
		_set_feedback(_review_error, true)
		return
	_dirty_reason = false
	_refresh_review_status()
	_refresh_move_buttons()
	_set_feedback("已保存本机审阅：" + str(STATUS_LABELS[status]))


func reload_reviews() -> void:
	_reviews = {}
	_previous_catalogs = []
	_review_error = ""
	_review_read_blocked = false
	_review_invalidated = false
	if FileAccess.file_exists(REVIEW_PATH):
		var json := JSON.new()
		var parse_error := json.parse(FileAccess.get_file_as_string(REVIEW_PATH))
		var parsed: Variant = json.data if parse_error == OK else null
		if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1 or not parsed.get("reviews") is Dictionary:
			_review_error = "本机审阅记录无法读取，未覆盖原文件。"
			_review_read_blocked = true
		else:
			if parsed.get("previous_catalogs", []) is Array:
				_previous_catalogs = (parsed.get("previous_catalogs", []) as Array).duplicate(true)
			if str(parsed.get("catalog_hash", "")) == _catalog_hash:
				for id: String in _move_order:
					for variant_id: String in _available_variants(id):
						var key := _review_key(id, variant_id)
						var entry: Variant = parsed.reviews.get(key, {})
						if entry is Dictionary and STATUS_LABELS.has(str(entry.get("status", "pending"))):
							_reviews[key] = entry.duplicate(true)
			else:
				_review_invalidated = true
				_previous_catalogs.append({"catalog_hash": str(parsed.get("catalog_hash", "")), "reviews": parsed.reviews.duplicate(true)})
	if is_instance_valid(_reason_edit):
		_refresh_selected()


func _save_reviews() -> bool:
	if _review_read_blocked:
		_review_error = "原审阅文件无法读取，暂不写入；请保留原文件后重新载入。"
		return false
	_review_error = ""
	var directory_error := DirAccess.make_dir_recursive_absolute("user://martial_workshop")
	if directory_error != OK:
		_review_error = "本机审阅目录无法写入，请稍后重试。"
		return false
	var file := FileAccess.open(REVIEW_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		_review_error = "本机审阅未能保存，请稍后重试。"
		return false
	var payload := {"schema": 1, "catalog_hash": _catalog_hash, "catalog_schema": int(_catalog.get("schema_version", 1)), "reviews": _reviews, "previous_catalogs": _previous_catalogs}
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(REVIEW_PATH + ".tmp", REVIEW_PATH)
	if error != OK:
		_review_error = "本机审阅未能替换，原记录仍保留。"
		return false
	return true


func _input(event: InputEvent) -> void:
	if _closed or not is_visible_in_tree() or not event is InputEventKey:
		return
	var key: InputEventKey = event
	var focus := get_viewport().gui_get_focus_owner()
	if focus is TextEdit or focus is LineEdit:
		return
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _dispose_stage() -> void:
	if not is_instance_valid(_stage):
		return
	if _stage.has_method("stop_workshop_move"):
		_stage.call("stop_workshop_move")
	var stage_viewport: Variant = _stage.get("viewport")
	if stage_viewport is SubViewport:
		stage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage.queue_free()
	_stage = null
	_controls.erase("WorkshopStage")


func _close() -> void:
	if _closed:
		return
	_flush_reason()
	_closed = true
	set_process(false)
	set_process_input(false)
	_dispose_stage()
	closed.emit()


func _exit_tree() -> void:
	_dispose_stage()


func ui_control(id: String) -> Control:
	return _controls.get(id) as Control


func set_skill_audio(muted: bool) -> void:
	if is_instance_valid(_stage) and _stage.has_method("set_skill_audio"):
		_stage.call("set_skill_audio", muted)


func audit_snapshot() -> Dictionary:
	var rectangles: Dictionary = {}
	for id: String in _controls:
		var control: Control = _controls[id]
		if is_instance_valid(control) and control.is_visible_in_tree():
			rectangles[id] = control.get_global_rect()
	var data := _player_audit()
	var viewport_size := Vector2i.ZERO
	if is_instance_valid(_stage):
		var value: Variant = _stage.get("viewport")
		if value is SubViewport:
			viewport_size = value.size
	return {"selected_id": _selected_id, "previous_id": _previous_id,
		"variant_id": _selected_variant_id, "variant_label": _variant_label(), "review_key": _review_key(), "available_variants": _available_variants(),
		"category_filter": _category_filter, "style_filter": _style_filter,
		"visible_move_ids": _visible_ids.duplicate(), "speed": _speed, "camera": _camera_mode,
		"catalog_hash": _catalog_hash, "review_status": _review_status(),
		"reason": _reason_edit.text if is_instance_valid(_reason_edit) else "",
		"reviews": _reviews.duplicate(true), "review_path": REVIEW_PATH, "review_error": _review_error,
		"review_read_blocked": _review_read_blocked,
		"review_invalidated": _review_invalidated, "closed": _closed, "stage_ready": _stage_ready,
		"elapsed": _display_elapsed(data), "duration": float(data.get("total", _move_total())) if _matches_audit(data) else _move_total(),
		"phase": str(data.get("phase", "idle")), "feedback": _feedback_label.text if is_instance_valid(_feedback_label) else "",
		"paused": bool(data.get("paused", false)), "active": bool(data.get("active", false)),
		"sourceclock": float(data.get("source_seconds", 0.0)) if _matches_audit(data) and not _timeline_stopped else 0.0,
		"body_source_seconds": float(data.get("body_source_seconds", data.get("source_seconds", data.get("elapsed", 0.0)))),
		"fx_elapsed": float(data.get("fx_elapsed", data.get("effect_elapsed", data.get("elapsed", 0.0)))),
		"player": data, "controls": rectangles, "viewport_size": viewport_size,
		"authority": "local presentation and review only", "state_copy": _state.duplicate(true)}
