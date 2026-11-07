extends Control
## The same battle figures, viewed up close. Never reads or changes a game clock.

signal closed

const ActorScript = preload("res://addons/cultivation_mode/ambush_actor.gd")
const CAST := [
	{"id": "player", "name": "江砚秋", "role": "swordsman", "detail": "棕发高束 · 蓝白交领 · 单手持剑"},
	{"id": "tinglan", "name": "沈听岚", "role": "disciple", "detail": "新候选 · 深青剑衫 · 长束发与青缎 · 剑式与截脉指"},
	{"id": "brute", "name": "持棍客", "role": "brute", "detail": "赭褐短褂 · 头巾绑腿 · 粗木长棍"},
	{"id": "blade", "name": "刀客", "role": "blade", "detail": "灰紫斜襟 · 收袖护腕 · 单刃腰刀"},
	{"id": "archer", "name": "弓手", "role": "archer", "detail": "苔绿短衣 · 竹编斗笠 · 长弓与背箭"}
]
const INK := Color("#34433d")
const GREEN := Color("#486c5c")
const PAPER := Color("#f1ebdf")

var viewport: SubViewport
var camera: Camera3D
var world_root: Node3D
var actor: Node3D
var selected_id := "player"
var _yaw := 0.0
var _auto_turn := false
var _dragging := false
var _walk_until := 0
var _model_area: Control
var _name_label: Label
var _detail_label: Label
var _controls: Dictionary = {}
var _pick_buttons: Dictionary = {}
var _turn_button: Button
var _interrupt_button: Button
var _detail_button: Button
var _refined_details := true


func setup(font: Font, initial_id: String = "player") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var style := Theme.new()
	style.default_font = font
	style.default_font_size = 18
	style.set_color("font_color", "Label", INK)
	style.set_color("font_color", "Button", INK)
	style.set_color("font_hover_color", "Button", INK)
	style.set_color("font_pressed_color", "Button", INK)
	style.set_color("font_hover_pressed_color", "Button", INK)
	style.set_stylebox("normal", "Button", _panel(Color("#faf6ec"), Color("#c3c6b3")))
	style.set_stylebox("hover", "Button", _panel(Color("#e2e9dc"), GREEN))
	style.set_stylebox("pressed", "Button", _panel(Color("#cadbc9"), GREEN))
	theme = style
	var background := ColorRect.new()
	background.color = PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("同行与来敌", 28, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_detail_button = _button("细节：精细", "DetailToggleButton", _toggle_refined_details)
	_detail_button.tooltip_text = "在同一姿势对照精细与原版；关闭后保留战场原先的细节选择。"
	header.add_child(_detail_button)
	header.add_child(_button("回到战斗", "CloseCharactersButton", _close))
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	column.add_child(choices)
	for row: Dictionary in CAST:
		var pick := _button(str(row.name), "Character_" + str(row.id), select_character.bind(str(row.id)))
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(pick)
		_pick_buttons[str(row.id)] = pick
	_model_area = Control.new()
	_model_area.name = "CharacterModelArea"
	_model_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_area.custom_minimum_size.y = 200
	_model_area.mouse_default_cursor_shape = Control.CURSOR_DRAG
	column.add_child(_model_area)
	_controls[_model_area.name] = _model_area
	_build_world()
	var name_row := HBoxContainer.new()
	column.add_child(name_row)
	_name_label = _label("", 27, INK)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)
	name_row.add_child(_label("拖动转身  ·  滚轮拉近", 15, GREEN))
	_detail_label = _label("", 17, GREEN)
	column.add_child(_detail_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	for entry: Array in [["正面", "FrontButton", 0.0], ["侧面", "SideButton", PI * 0.5], ["背面", "BackButton", PI]]:
		actions.add_child(_button(str(entry[0]), str(entry[1]), set_angle.bind(float(entry[2]))))
	_turn_button = _button("缓缓转身", "AutoTurnButton", _toggle_turn)
	actions.add_child(_turn_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_button("走两步", "CharacterWalkButton", _show_walk))
	actions.add_child(_button("出一招", "CharacterAttackButton", _show_attack))
	_interrupt_button = _button("截脉指", "CharacterInterruptButton", _show_interrupt)
	actions.add_child(_interrupt_button)
	select_character(initial_id)


func _panel(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, id: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	_controls[id] = button
	return button


func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "CharacterPortraitViewport"
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
	var platform := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.95
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.07
	cylinder.radial_segments = 64
	platform.mesh = cylinder
	platform.position.y = -0.04
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#a6ae99")
	material.roughness = 0.95
	platform.material_override = material
	world_root.add_child(platform)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.55
	camera.position = Vector3(0, 1.46, 6)
	world_root.add_child(camera)
	camera.look_at(Vector3(0, 0.97, 0))
	camera.current = true
	_resize()


func _resize() -> void:
	if is_instance_valid(viewport):
		viewport.size = Vector2i(maxi(320, roundi(_model_area.size.x)), maxi(250, roundi(_model_area.size.y)))


func select_character(id: String) -> void:
	var row: Dictionary = {}
	for entry: Dictionary in CAST:
		if entry.id == id:
			row = entry
	if row.is_empty():
		return
	if is_instance_valid(actor):
		actor.hide()
		actor.queue_free()
	selected_id = id
	actor = ActorScript.new() as Node3D
	actor.name = "Portrait_" + id
	world_root.add_child(actor)
	actor.call("setup", id, str(row.role), id in ["player", "tinglan"])
	actor.call("set_refined_details", _refined_details)
	_detail_button.text = "细节：精细" if _refined_details else "细节：原版"
	actor.rotation.y = _yaw
	_walk_until = 0
	_name_label.text = str(row.name)
	_detail_label.text = str(row.detail)
	_interrupt_button.visible = id == "tinglan"
	for key: String in _pick_buttons:
		(_pick_buttons[key] as Button).add_theme_stylebox_override("normal", _panel(Color("#d7e2d2") if key == id else Color("#faf6ec"), GREEN if key == id else Color("#c3c6b3")))


func set_refined_details(enabled: bool) -> void:
	_refined_details = enabled
	if is_instance_valid(actor):
		actor.call("set_refined_details", enabled)
	if is_instance_valid(_detail_button):
		_detail_button.text = "细节：精细" if enabled else "细节：原版"


func _toggle_refined_details() -> void:
	set_refined_details(not _refined_details)


func detail_audit() -> Dictionary:
	return {"enabled": _refined_details, "actor": actor.call("detail_audit") if is_instance_valid(actor) else {},
		"scope": "inspection only; battle detail selection preserved"}


func set_angle(radians: float) -> void:
	_yaw = radians
	_auto_turn = false
	_turn_button.text = "缓缓转身"
	if is_instance_valid(actor):
		actor.rotation.y = _yaw


func _toggle_turn() -> void:
	_auto_turn = not _auto_turn
	_turn_button.text = "停下看看" if _auto_turn else "缓缓转身"


func _show_walk() -> void:
	if is_instance_valid(actor):
		actor.call("set_motion", "walk")
		_walk_until = Time.get_ticks_msec() + 1600


func _show_attack() -> void:
	if is_instance_valid(actor):
		_walk_until = 0
		actor.call("set_motion", "attack", 1.0, "strike")


func _show_interrupt() -> void:
	if selected_id == "tinglan" and is_instance_valid(actor):
		_walk_until = 0
		actor.call("set_motion", "attack", 1.0, "interrupt")


func _model_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-0.14 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.14), 1.8, 3.4)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		set_angle(_yaw + event.relative.x * 0.009)
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _auto_turn and is_instance_valid(actor):
		_yaw += delta * 0.38
		actor.rotation.y = _yaw
	if _walk_until > 0 and Time.get_ticks_msec() >= _walk_until and is_instance_valid(actor):
		_walk_until = 0
		actor.call("set_motion", "idle")


func _close() -> void:
	closed.emit()


func ui_control(id: String) -> Control:
	return _controls.get(id) as Control


func audit_snapshot() -> Dictionary:
	var rectangles: Dictionary = {}
	for id: String in _controls:
		var control: Control = _controls[id]
		if is_instance_valid(control):
			rectangles[id] = control.get_global_rect()
	return {"character": selected_id, "yaw": _yaw, "auto_turn": _auto_turn, "controls": rectangles, "viewport_size": viewport.size, "refined_details": _refined_details, "detail": detail_audit()}
