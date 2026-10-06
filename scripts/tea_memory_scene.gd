extends Control

## Full-screen, presentation-only view for brief memories and old diary pages.
signal action_requested(object_id: String, action_id: String, session: int)
signal close_requested

var buttons: Dictionary = {}
var body: Label
var heading: Label
var backdrop: TextureRect
var current_shot := ""
var caption: Label

var _layout: Dictionary = {}
var _matte: ColorRect
var _old_backdrop: TextureRect
var _shade: ColorRect
var _bubble: Panel
var _continue_button: Button
var _close_button: Button
var _transition_tween: Tween
var _drift_tween: Tween
var _black_tween: Tween
var _presentation_key := ""
var _generation := 0
var _object_id := ""
var _source: Dictionary = {}
var _page_index := 0
var _token := 0
var _session := 0
var _hold_deadline_msec := 0
var _current_tone := Color.WHITE

const CANVAS_SIZE := Vector2(1440, 900)
const IMAGE_OVERSCAN := Vector2(36, 24)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	_layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tea-memory-layout.json"))
	_build_view()

func _build_view() -> void:
	_matte = ColorRect.new()
	_matte.color = Color("282b27")
	_matte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_matte.size = CANVAS_SIZE
	_matte.z_index = 0
	add_child(_matte)

	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.position = -IMAGE_OVERSCAN
	backdrop.size = CANVAS_SIZE + IMAGE_OVERSCAN * 2.0
	backdrop.z_index = 1
	add_child(backdrop)

	_old_backdrop = TextureRect.new()
	_old_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_old_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_old_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_old_backdrop.position = backdrop.position
	_old_backdrop.size = backdrop.size
	_old_backdrop.visible = false
	_old_backdrop.z_index = 2
	add_child(_old_backdrop)

	_shade = ColorRect.new()
	_shade.color = Color(0.10, 0.09, 0.075, 0.16)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.size = CANVAS_SIZE
	_shade.z_index = 3
	add_child(_shade)

	_bubble = Panel.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.95, 0.92, 0.84, 0.94)
	paper.border_color = Color("ad8959")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(9)
	paper.content_margin_left = 15
	paper.content_margin_right = 15
	paper.content_margin_top = 10
	paper.content_margin_bottom = 10
	_bubble.add_theme_stylebox_override("panel", paper)
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.z_index = 4
	add_child(_bubble)

	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color("756248"))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(heading)

	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color("354137"))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(body)

	_continue_button = _make_button("继续读这段对话")
	_continue_button.custom_minimum_size = Vector2(0, 36)
	_bubble.add_child(_continue_button)

	_close_button = _make_button("返回旧院")
	_close_button.position = Vector2(1272, 22)
	_close_button.size = Vector2(142, 42)
	_close_button.z_index = 5
	_close_button.pressed.connect(_close_pressed)
	add_child(_close_button)

	caption = Label.new()
	caption.text = "旧记 · 问天峰往日"
	caption.position = Vector2(28, 24)
	caption.size = Vector2(280, 32)
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color("5a5041"))
	caption.add_theme_color_override("font_shadow_color", Color(1.0, 0.96, 0.88, 0.9))
	caption.add_theme_constant_override("shadow_outline_size", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.z_index = 4
	add_child(caption)
	buttons["continue"] = _continue_button
	buttons["close"] = _close_button

func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 36)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("354137"))
	button.add_theme_color_override("font_hover_color", Color("32695c"))
	button.add_theme_color_override("font_pressed_color", Color("354137"))
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e8dfcd") if style_name != "hover" else Color("d9caaa")
		style.border_color = Color("ad8959")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(style_name, style)
	return button

func present(object_id: String, source: Dictionary, page_index: int, token: int, session: int) -> void:
	var pages: Array = source.get("pages", [])
	if page_index < 0 or page_index >= pages.size():
		close_view()
		return
	var was_visible := visible
	var previous_shot := current_shot
	var new_key := "%s|%d|%d|%d" % [object_id, page_index, token, session]
	var is_new_presentation := new_key != _presentation_key or not visible
	_object_id = object_id
	_source = source
	_page_index = page_index
	_token = token
	_session = session
	_presentation_key = new_key
	visible = true
	var page: Dictionary = pages[page_index]
	heading.text = "%s · %d / %d" % [str(page.get("speaker", "")), page_index + 1, pages.size()]
	var page_text := str(page.get("text", ""))
	# Set the wrapping width while empty, before text can inflate minimum height.
	body.text = ""
	var final_page := page_index == pages.size() - 1
	var speaker_name := str(page.get("speaker", ""))
	var continuation := "听下去" if speaker_name in ["顾青萝", "谢长安"] else "继续看下去"
	if is_new_presentation:
		_bubble.remove_child(_continue_button)
		_continue_button.hide()
		_continue_button.queue_free()
		_continue_button = _make_button("")
		_bubble.add_child(_continue_button)
		var action_id := "memory_close" if final_page else "page:%d" % token
		_continue_button.pressed.connect(_request_action.bind(object_id, action_id, token, session))
		buttons["continue"] = _continue_button
	var close_label := "合上旧记 · 回到旧院"
	if object_id in ["tea.medical_early", "tea.medical_habits"]:
		close_label = "合上诊录 · 回到旧院"
	elif object_id == "tea.letter":
		close_label = "收起信 · 回到旧院"
	elif object_id in ["tea.notice_death", "tea.notice_cups"]:
		close_label = "合上记录 · 回到旧院"
	_continue_button.text = close_label if final_page else continuation
	_continue_button.visible = true
	for button_key in buttons.keys():
		if str(button_key).begins_with("page:") or button_key == "memory_close":
			buttons.erase(button_key)
	buttons["memory_close" if final_page else "page:%d" % token] = _continue_button
	_close_button.text = "返回旧院"
	caption.text = str(_page_layout(object_id, page_index).get("caption", "旧记 · 问天峰往日"))
	_apply_bubble_anchor(str(page.get("speaker", "")), page_text)
	body.text = page_text
	_fit_bubble_text()
	if not is_new_presentation:
		return
	_generation += 1
	_cancel_tweens()
	_hold_deadline_msec = 0
	var page_layout := _page_layout(object_id, page_index)
	var shot := str(page_layout.get("shot", _layout.get("default_shot", "standing")))
	var needs_transition := not was_visible or shot != previous_shot
	var hold_ms := int(page_layout.get("hold_ms", 0))
	if needs_transition:
		hold_ms = maxi(hold_ms, int(_layout.get("transition_ms", 0)))
	if hold_ms > 0:
		_hold_deadline_msec = Time.get_ticks_msec() + hold_ms
	_continue_button.disabled = hold_ms > 0
	_restart_camera_drift(_generation)
	_apply_page_shot(page_layout, _generation, true)
	if hold_ms > 0:
		call_deferred("_enable_continue_after_hold", _continue_button, _generation, _object_id, _token, _session)

func close_view() -> void:
	_generation += 1
	_presentation_key = ""
	_object_id = ""
	_source = {}
	_page_index = 0
	_token = 0
	_session = 0
	_hold_deadline_msec = 0
	_cancel_tweens()
	for button_key in buttons.keys():
		if str(button_key).begins_with("page:") or button_key == "memory_close":
			buttons.erase(button_key)
	current_shot = ""
	backdrop.texture = null
	backdrop.modulate = Color.WHITE
	_old_backdrop.texture = null
	_old_backdrop.visible = false
	visible = false

func _page_layout(object_id: String, page_index: int) -> Dictionary:
	var object_layouts: Dictionary = _layout.get("page_shots", {})
	var entries: Array = object_layouts.get(object_id, [])
	if page_index >= 0 and page_index < entries.size():
		return entries[page_index]
	return {"shot": str(_layout.get("default_shot", "standing")), "tone": "neutral"}

func _apply_page_shot(page_layout: Dictionary, generation: int, fade_in: bool) -> void:
	if not _is_current(generation):
		return
	var shot := str(page_layout.get("shot", _layout.get("default_shot", "standing")))
	var tone_name := str(page_layout.get("tone", "neutral"))
	var tones: Dictionary = _layout.get("tones", {})
	var tone_values: Array = tones.get(tone_name, [1.0, 1.0, 1.0])
	var tone := Color(float(tone_values[0]), float(tone_values[1]), float(tone_values[2]), 1.0)
	if bool(page_layout.get("fade_to_black", false)):
		_start_shot_transition(shot, tone, generation, fade_in)
		_black_tween = create_tween()
		_black_tween.tween_interval(_transition_seconds() if fade_in else 0.0)
		_black_tween.tween_property(backdrop, "modulate", Color(0.035, 0.032, 0.030, 1.0), _transition_seconds())
		_black_tween.tween_callback(func():
			if _is_current(generation):
				current_shot = "near_black"
		)
		return
	_start_shot_transition(shot, tone, generation, fade_in)
	if page_layout.has("auto_shot") and page_layout.has("auto_after_ms"):
		_auto_transition_to_shot(
			str(page_layout.auto_shot),
			str(page_layout.get("auto_tone", "neutral")),
			int(page_layout.auto_after_ms),
			generation
		)

func _start_shot_transition(shot: String, tone: Color, generation: int, fade_in: bool) -> void:
	if not _is_current(generation):
		return
	var paths: Dictionary = _layout.get("shot_paths", {})
	var path := str(paths.get(shot, ""))
	var texture := load(path) as Texture2D if not path.is_empty() else null
	var changed := shot != current_shot or backdrop.texture == null
	if not changed:
		_current_tone = tone
		if _transition_tween != null and _transition_tween.is_running():
			_transition_tween.kill()
		_transition_tween = create_tween()
		_transition_tween.tween_property(backdrop, "modulate", tone, _transition_seconds())
		return
	if _transition_tween != null and _transition_tween.is_running():
		_transition_tween.kill()
	if _old_backdrop.visible:
		_old_backdrop.visible = false
	var had_previous := backdrop.texture != null and not current_shot.is_empty()
	if had_previous:
		_old_backdrop.texture = backdrop.texture
		_old_backdrop.modulate = _current_tone
		_old_backdrop.modulate.a = backdrop.modulate.a
		_old_backdrop.position = backdrop.position
		_old_backdrop.size = backdrop.size
		_old_backdrop.visible = true
	backdrop.texture = texture
	backdrop.position = Vector2(-IMAGE_OVERSCAN.x - _layout_camera_drift().x, -IMAGE_OVERSCAN.y - _layout_camera_drift().y)
	backdrop.modulate = Color(tone.r, tone.g, tone.b, 0.0 if (fade_in or had_previous) else 1.0)
	_current_tone = tone
	current_shot = shot
	_transition_tween = create_tween()
	if had_previous:
		_transition_tween.set_parallel(true)
		_transition_tween.tween_property(backdrop, "modulate:a", 1.0, _transition_seconds())
		_transition_tween.tween_property(_old_backdrop, "modulate:a", 0.0, _transition_seconds())
	else:
		_transition_tween.tween_property(backdrop, "modulate:a", 1.0, _transition_seconds())
	_transition_tween.chain().tween_callback(func():
		if _is_current(generation):
			_old_backdrop.visible = false
			_old_backdrop.texture = null
	)

func _auto_transition_to_shot(shot: String, tone_name: String, delay_ms: int, generation: int) -> void:
	await get_tree().create_timer(float(delay_ms) / 1000.0).timeout
	if not _is_current(generation):
		return
	var tones: Dictionary = _layout.get("tones", {})
	var values: Array = tones.get(tone_name, [1.0, 1.0, 1.0])
	var tone := Color(float(values[0]), float(values[1]), float(values[2]), 1.0)
	_start_shot_transition(shot, tone, generation, false)

func _apply_bubble_anchor(speaker_name: String, page_text: String) -> void:
	var anchors: Dictionary = _layout.get("bubble_anchors", {})
	var anchor: Array = anchors.get(speaker_name, anchors.get("叙述", [130, 100, 650, 225]))
	var base_height := float(anchor[3])
	var extra_height := 35.0 if page_text.length() > 44 else 0.0
	_bubble.position = Vector2(float(anchor[0]), maxf(24.0, float(anchor[1]) - extra_height))
	_bubble.size = Vector2(float(anchor[2]), base_height + extra_height)
	# A wrapping Label can report a huge minimum height before a Container has
	# assigned its first width. Fixed scene geometry keeps the first read usable.
	heading.position = Vector2(15, 10)
	heading.size = Vector2(_bubble.size.x - 30, 28)
	body.add_theme_font_size_override("font_size", 20 if page_text.length() > 44 else 28)
	body.position = Vector2(15, 45)
	body.size = Vector2(_bubble.size.x - 30, _bubble.size.y - 100)
	_continue_button.position = Vector2(15, _bubble.size.y - 46)
	_continue_button.size = Vector2(_bubble.size.x - 30, 36)

func _fit_bubble_text() -> void:
	# Font ascent/descent and explicit newlines also count, beyond line_height.
	var height := maxf(_bubble.size.y - 100, ceilf(body.get_minimum_size().y) + 4)
	body.size = Vector2(_bubble.size.x - 30, height)
	_bubble.size.y = height + 100
	_continue_button.position.y = _bubble.size.y - 46

func _layout_camera_drift() -> Vector2:
	var values: Array = _layout.get("camera_drift", [8.0, 5.0])
	return Vector2(float(values[0]), float(values[1]))

func _transition_seconds() -> float:
	return float(_layout.get("transition_ms", 0)) / 1000.0

func _restart_camera_drift(generation: int) -> void:
	if _drift_tween != null and _drift_tween.is_running():
		_drift_tween.kill()
	var drift := _layout_camera_drift()
	var home := Vector2(-IMAGE_OVERSCAN.x - drift.x, -IMAGE_OVERSCAN.y - drift.y)
	backdrop.position = home
	_drift_tween = create_tween().set_loops()
	_drift_tween.tween_property(backdrop, "position", home + drift, 18.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_drift_tween.tween_property(backdrop, "position", home, 18.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_drift_tween.tween_callback(func():
		if not _is_current(generation) and visible and _drift_tween != null and _drift_tween.is_running():
			_drift_tween.kill()
	)

func _cancel_tweens() -> void:
	if _transition_tween != null and _transition_tween.is_running():
		_transition_tween.kill()
	if _drift_tween != null and _drift_tween.is_running():
		_drift_tween.kill()
	if _black_tween != null and _black_tween.is_running():
		_black_tween.kill()
	_transition_tween = null
	_drift_tween = null
	_black_tween = null

func _is_current(generation: int) -> bool:
	return visible and generation == _generation and not _presentation_key.is_empty()

func remaining_hold_seconds() -> float:
	return maxf(0.0, float(_hold_deadline_msec - Time.get_ticks_msec()) / 1000.0)

func _enable_continue_after_hold(button: Button, generation: int, object_id: String, token: int, session: int) -> void:
	while true:
		if not _is_current(generation) or button != _continue_button or object_id != _object_id or token != _token or session != _session:
			return
		var remaining := remaining_hold_seconds()
		if remaining <= 0.0:
			break
		await get_tree().create_timer(remaining).timeout
	if _is_current(generation) and button == _continue_button and button.is_inside_tree() and object_id == _object_id and token == _token and session == _session:
		button.disabled = false

func _request_action(object_id: String, action_id: String, token: int, session: int) -> void:
	# A retired page button carries its own read identity, never the next page's.
	if not visible or object_id != _object_id or token != _token or session != _session or remaining_hold_seconds() > 0.0:
		return
	action_requested.emit(object_id, action_id, session)

func _close_pressed() -> void:
	if visible:
		close_requested.emit()
