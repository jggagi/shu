extends Control
## Isolated review of the battle actor. One preview clock, no game state.

signal closed

const ActorScript = preload("res://addons/cultivation_mode/ambush_actor.gd")
const INK := Color("#34433d")
const GREEN := Color("#486c5c")
const PAPER := Color("#f1ebdf")
const CLIPS := [
	["attack", "抡棍"], ["interrupt", "被打断"], ["stagger", "踉跄退步"],
	["recoil", "撞栅回震"], ["walk", "走步"]
]

var viewport: SubViewport
var camera: Camera3D
var world_root: Node3D
var actor: Node3D
var _controls: Dictionary = {}
var _clip_buttons: Dictionary = {}
var _model_area: Control
var _phase_label: Label
var _time_label: Label
var _scrub: HSlider
var _motion_button: Button
var _play_button: Button
var _rate_button: Button
var _clip := "attack"
var _elapsed := 0.0
var _duration := 1.6
var _playing := false
var _rate := 1.0
var _new_motion := true
var _yaw := PI * 0.18
var _updating_slider := false
var _dragging := false
var _motion_audit: Dictionary = {}


func setup(font: Font) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var style := Theme.new()
	style.default_font = font
	style.default_font_size = 17
	for property: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		style.set_color(property, "Button", INK)
	style.set_color("font_color", "Label", INK)
	style.set_stylebox("normal", "Button", _panel(Color("#faf6ec"), Color("#c3c6b3")))
	style.set_stylebox("hover", "Button", _panel(Color("#e2e9dc"), GREEN))
	style.set_stylebox("pressed", "Button", _panel(Color("#cadbc9"), GREEN))
	theme = style
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
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var title := _label("持棍动作", 26, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_motion_button = _button("动作：新版", "StaffMotionToggleButton", _toggle_motion)
	_motion_button.tooltip_text = "在同一时刻比较动作；保留镜头、暂停状态和速度。"
	header.add_child(_motion_button)
	header.add_child(_button("回到战斗", "CloseStaffButton", _close))
	var clips := HBoxContainer.new()
	clips.add_theme_constant_override("separation", 8)
	column.add_child(clips)
	for row: Array in CLIPS:
		var button := _button(str(row[1]), "StaffClip_" + str(row[0]), select_clip.bind(str(row[0])))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clips.add_child(button)
		_clip_buttons[str(row[0])] = button
	_model_area = Control.new()
	_model_area.name = "StaffModelArea"
	_model_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_area.custom_minimum_size.y = 220
	_model_area.mouse_default_cursor_shape = Control.CURSOR_DRAG
	column.add_child(_model_area)
	_controls["StaffModelArea"] = _model_area
	_build_world()
	var readout := HBoxContainer.new()
	readout.add_theme_constant_override("separation", 10)
	column.add_child(readout)
	_phase_label = _label("沉肩蓄力", 19, INK)
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.add_child(_phase_label)
	_time_label = _label("", 16, GREEN)
	readout.add_child(_time_label)
	_scrub = HSlider.new()
	_scrub.name = "StaffScrubSlider"
	_scrub.min_value = 0.0
	_scrub.max_value = _duration
	_scrub.step = 0.001
	_scrub.custom_minimum_size.y = 24
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.tooltip_text = "拖动查看动作的任一时刻；拖动会暂停播放。"
	_scrub.value_changed.connect(_scrub_changed)
	column.add_child(_scrub)
	_controls["StaffScrubSlider"] = _scrub
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	_play_button = _button("播放", "StaffPlayButton", _toggle_play)
	actions.add_child(_play_button)
	_rate_button = _button("速度 1×", "StaffRateButton", _toggle_rate)
	actions.add_child(_rate_button)
	actions.add_child(_button("复位", "StaffResetButton", _reset))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(space)
	actions.add_child(_button("正面", "StaffFrontButton", set_angle.bind(0.0)))
	actions.add_child(_button("侧面", "StaffSideButton", set_angle.bind(PI * 0.5)))
	actions.add_child(_button("斜前", "StaffThreeQuarterButton", set_angle.bind(PI * 0.18)))
	select_clip("attack")


func _panel(fill: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(7)
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _button(text: String, id: String, callback: Callable) -> Button:
	var result := Button.new()
	result.name = id
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(callback)
	_controls[id] = result
	return result


func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "StaffReviewViewport"
	viewport.size = Vector2i(1100, 500)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_model_area.add_child(viewport)
	var surface := TextureRect.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	surface.stretch_mode = TextureRect.STRETCH_SCALE
	surface.texture = viewport.get_texture()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_model_area.add_child(surface)
	_model_area.gui_input.connect(_model_input)
	_model_area.mouse_exited.connect(_stop_drag)
	_model_area.resized.connect(_resize)
	world_root = Node3D.new()
	viewport.add_child(world_root)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#e7e5d6")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#dce4df")
	world.environment.ambient_light_energy = 0.42
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_root.add_child(world)
	for source: Array in [[Vector3(-34, -26, 0), 0.58, Color("#fff3e4")], [Vector3(-25, 145, 0), 0.18, Color("#d1dfed")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = source[0]
		light.light_energy = float(source[1])
		light.light_color = source[2]
		light.shadow_enabled = float(source[1]) > 0.5
		world_root.add_child(light)
	var ground := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.25
	mesh.bottom_radius = 1.28
	mesh.height = 0.04
	mesh.radial_segments = 64
	ground.mesh = mesh
	ground.position.y = -0.025
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#a6ae99")
	material.roughness = 0.95
	ground.material_override = material
	world_root.add_child(ground)
	actor = ActorScript.new() as Node3D
	actor.name = "StaffReviewBrute"
	world_root.add_child(actor)
	actor.call("setup", "brute", "brute", false)
	actor.call("set_refined_details", true)
	actor.set_process(false)
	actor.call("set_staff_motion_enabled", _new_motion)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.95
	camera.position = Vector3(0, 1.75, 6)
	world_root.add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	set_angle(_yaw)
	_resize()


func _resize() -> void:
	if is_instance_valid(viewport):
		viewport.size = Vector2i(maxi(320, roundi(_model_area.size.x)), maxi(220, roundi(_model_area.size.y)))


func select_clip(clip: String) -> void:
	if not _clip_buttons.has(clip):
		return
	_clip = clip
	_elapsed = 0.0
	_playing = false
	_duration = maxf(0.001, float(actor.call("staff_clip_duration", _clip)))
	for key: String in _clip_buttons:
		(_clip_buttons[key] as Button).add_theme_stylebox_override("normal", _panel(Color("#d7e2d2") if key == _clip else Color("#faf6ec"), GREEN if key == _clip else Color("#c3c6b3")))
	_sample()


func _sample() -> void:
	if not is_instance_valid(actor):
		return
	actor.call("sample_staff_motion", _clip, _elapsed, {})
	_motion_audit = actor.call("staff_motion_audit")
	_duration = maxf(0.001, float(_motion_audit.get("duration", _duration)))
	if is_instance_valid(_scrub):
		_updating_slider = true
		_scrub.max_value = _duration
		_scrub.value = _elapsed
		_updating_slider = false
	if is_instance_valid(_phase_label):
		_phase_label.text = _phase_text()
	if is_instance_valid(_time_label):
		_time_label.text = "%.2f / %.2f 秒" % [_elapsed, _duration]
	if is_instance_valid(_play_button):
		_play_button.text = "暂停" if _playing else "播放"
	if is_instance_valid(_motion_button):
		_motion_button.text = "动作：新版" if _new_motion else "动作：原版"
	if is_instance_valid(_rate_button):
		_rate_button.text = "速度 0.5×" if _rate < 1.0 else "速度 1×"


func _phase_text() -> String:
	var phase: String = str(_motion_audit.get("phase", ""))
	var names := {
		"anticipation": "沉肩蓄力", "windup": "沉肩蓄力", "charge": "沉肩蓄力",
		"ready": "沉肩蓄力", "load": "沉肩蓄力", "loaded": "沉肩蓄力", "waist_lead": "跨步抡击", "release": "跨步抡击",
		"swing": "跨步抡击", "strike": "跨步抡击", "attack": "跨步抡击",
		"contact": "接触", "impact": "接触", "follow_through": "随势收棍",
		"followthrough": "随势收棍", "recovery": "随势收棍", "recover": "随势收棍",
		"settle": "站稳", "settled": "站稳", "idle": "站稳", "guard": "站稳", "recover_step": "随势收棍",
		"interrupted": "蓄力被打断", "interrupt": "蓄力被打断", "stagger": "踉跄退步",
		"recoil": "撞栅回震", "absorb": "撞栅回震", "walk": "交替迈步", "step": "交替迈步",
		"left_step": "交替迈步", "right_step": "交替迈步", "first_backstep": "踉跄退步",
		"second_backstep": "踉跄退步", "collision_brace": "撞栅站稳", "settle_guard": "站稳"
	}
	if names.has(phase):
		return str(names[phase])
	if phase in ["沉肩蓄力", "跨步抡击", "接触", "随势收棍", "站稳"]:
		return phase
	if _clip != "attack":
		return {"interrupt":"蓄力被打断", "stagger":"踉跄退步", "recoil":"撞栅回震", "walk":"交替迈步"}.get(_clip, "站稳")
	var fraction := _elapsed / _duration
	if fraction < 0.30:
		return "沉肩蓄力"
	if fraction < 0.47:
		return "跨步抡击"
	if fraction < 0.55:
		return "接触"
	return "随势收棍" if fraction < 0.90 else "站稳"


func _toggle_motion() -> void:
	_new_motion = not _new_motion
	actor.call("set_staff_motion_enabled", _new_motion)
	_sample()


func _toggle_play() -> void:
	if not _playing and _elapsed >= _duration - 0.0001:
		_elapsed = 0.0
	_playing = not _playing
	_sample()


func _toggle_rate() -> void:
	_rate = 0.5 if _rate > 0.5 else 1.0
	_sample()


func _reset() -> void:
	_playing = false
	_elapsed = 0.0
	_sample()


func _scrub_changed(value: float) -> void:
	if _updating_slider:
		return
	_playing = false
	_elapsed = clampf(value, 0.0, _duration)
	_sample()


func set_angle(radians: float) -> void:
	_yaw = radians
	_dragging = false
	if is_instance_valid(actor):
		actor.rotation.y = _yaw


func _model_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-0.14 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.14), 2.5, 3.8)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.009
		actor.rotation.y = _yaw
		accept_event()


func _stop_drag() -> void:
	_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_stop_drag()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _playing or not is_instance_valid(actor):
		return
	_elapsed = minf(_duration, _elapsed + maxf(0.0, delta) * _rate)
	if _elapsed >= _duration:
		_playing = false
	_sample()


func _close() -> void:
	_stop_drag()
	_playing = false
	closed.emit()


func ui_control(id: String) -> Control:
	return _controls.get(id) as Control


func audit_snapshot() -> Dictionary:
	# Modifiers finish in the deferred skeleton pass. Read the completed solve
	# without sampling again or advancing this preview clock.
	if is_instance_valid(actor):
		_motion_audit = actor.call("staff_motion_audit")
	var rectangles: Dictionary = {}
	for id: String in _controls:
		var control: Control = _controls[id]
		if is_instance_valid(control):
			rectangles[id] = control.get_global_rect()
	return {"clip":_clip, "time":_elapsed, "elapsed":_elapsed, "duration":_duration,
		"playing":_playing, "rate":_rate, "enabled":_new_motion, "yaw":_yaw,
		"camera_size":camera.size if is_instance_valid(camera) else 0.0,
		"viewport_size":viewport.size if is_instance_valid(viewport) else Vector2i.ZERO,
		"controls":rectangles, "motion":_motion_audit.duplicate(true),
		"scope":"isolated preview; no battle or save authority"}
