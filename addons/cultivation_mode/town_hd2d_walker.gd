extends "res://addons/cultivation_mode/town_walker.gd"
## A projected 3D view of the existing P1b logical walking plane.
## All movement, arrival, host validation and persistence remain in the parent.

const StageScript = preload("res://addons/cultivation_mode/town_hd2d_stage.gd")
const PlayerSheet = preload("res://assets/art/shanxia_hd2d/player-walk.svg")
const SellerSheet = preload("res://assets/art/shanxia_hd2d/tea-seller-walk.svg")
const ART_SOURCE_PATH := "res://assets/art/shanxia_hd2d/source.json"
var _stage: Node
var _motion_enabled: bool = true
var _lighting_enabled: bool = true
const NATURAL_WALK_SPEED: float = 150.0
var _visual_facing: String = "down"
const CAMERA_FRAME := Vector2(1280, 720)
const CAMERA_MAX_ZOOM: float = 1.2
const CAMERA_ZOOM_STEP: float = 0.05
var _camera_zoom: float = 1.0
var _camera_center := CAMERA_FRAME * 0.5
var _manual_zoom: float = 1.0
var _manual_center := CAMERA_FRAME * 0.5
var _camera_role: String = ""
var _camera_override: bool = false
var _camera_dragging: bool = false
var _camera_drag_at := Vector2.ZERO
var _camera_readout: Label
var _camera_zoom_in: Button
var _camera_zoom_out: Button


func setup(host: RefCounted, map_id: String, map: Dictionary, font: Font, enabled: bool) -> void:
	super.setup(host, map_id, map, font, enabled)
	clip_contents = true
	_stage = StageScript.new()
	_stage.name = "TownHD2DStage"
	add_child(_stage)
	_stage.call("setup", self, font, map)
	_stage.call("set_actor_frames", _frames(PlayerSheet), _frames(SellerSheet))
	_stage.call("set_time_slot", int(session.call("snapshot").get("slot", 0)))
	_stage.call("set_lighting_enabled", _lighting_enabled)
	_stage.call("sync", player_position, facing, false, walk_distance, active)
	resized.connect(_resize_stage)
	_resize_stage()
	_build_camera_controls()
	queue_redraw()


func _frames(sheet: Texture2D) -> Dictionary:
	var result: Dictionary = {"world_height": 1.55, "frame_size": Vector2(80, 112), "foot_anchor": Vector2(40, 104)}
	var directions: Array[String] = ["down", "up", "left", "right"]
	for row: int in range(directions.size()):
		var frames: Array[Texture2D] = []
		for column: int in range(4):
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(column * 80, row * 112, 80, 112)
			frame.filter_clip = true
			frames.append(frame)
		result[directions[row]] = frames
	return result


func audit() -> Dictionary:
	var result := super.audit()
	result["hd2d"] = _stage.call("audit") if is_instance_valid(_stage) and _stage.has_method("audit") else {}
	result["hd2d"]["walk_speed"] = NATURAL_WALK_SPEED
	result["hd2d"]["visual_facing"] = _visual_facing
	result["camera_view"] = camera_audit()
	return result


func logical_to_local(point: Vector2) -> Vector2:
	if not is_instance_valid(_stage):
		return super.logical_to_local(point)
	var projected: Vector2 = _stage.call("logical_to_screen", point, 0.0)
	return _map_offset() + projected * _map_scale()


func local_to_logical(point: Vector2) -> Vector2:
	if not is_instance_valid(_stage):
		return Vector2(-1, -1)
	return _stage.call("screen_to_logical", (point - _map_offset()) / maxf(_map_scale(), 0.001))


func _base_map_scale() -> float:
	# The camera composition fills the scene panel; only distant roofs/water may
	# crop as a result card changes its height. All walking anchors stay central.
	return maxf(size.x / 1280.0, size.y / 720.0)


func _map_scale() -> float:
	return _base_map_scale() * _camera_zoom


func _map_offset() -> Vector2:
	return size * 0.5 - _bounded_camera_center(_camera_center, _camera_zoom) * _map_scale()


func _bounded_camera_center(value: Vector2, zoom: float) -> Vector2:
	var half_visible := size * 0.5 / maxf(_base_map_scale() * zoom, 0.001)
	return Vector2(clampf(value.x, half_visible.x, CAMERA_FRAME.x - half_visible.x),
		clampf(value.y, half_visible.y, CAMERA_FRAME.y - half_visible.y))


func _camera_goal() -> Dictionary:
	if not _camera_role.is_empty() and not _camera_override and is_instance_valid(_stage):
		var player: Vector2 = _stage.call("logical_to_screen", player_position, 0.85)
		var partner: Vector2 = _stage.call("target_screen_position", _camera_role)
		return {"zoom": CAMERA_MAX_ZOOM,
			"center": _bounded_camera_center((player + partner) * 0.5, CAMERA_MAX_ZOOM)}
	return {"zoom": _manual_zoom, "center": _bounded_camera_center(_manual_center, _manual_zoom)}


func camera_audit() -> Dictionary:
	var goal := _camera_goal()
	return {"zoom": _camera_zoom, "manual_zoom": _manual_zoom, "target_zoom": goal.zoom,
		"center": _bounded_camera_center(_camera_center, _camera_zoom), "manual_center": _manual_center,
		"target_center": goal.center, "offset": _map_offset(), "scale": _map_scale(),
		"frame_rect": Rect2(_map_offset(), CAMERA_FRAME * _map_scale()),
		"focus_role": _camera_role, "focus_overridden": _camera_override, "dragging": _camera_dragging}


func get_camera_presentation_state() -> Dictionary:
	return {"zoom": _camera_zoom, "center": _camera_center,
		"manual_zoom": _manual_zoom, "manual_center": _manual_center,
		"role": _camera_role, "override": _camera_override}


func set_camera_presentation_state(value: Dictionary) -> void:
	_camera_zoom = clampf(float(value.get("zoom", 1.0)), 1.0, CAMERA_MAX_ZOOM)
	_manual_zoom = clampf(float(value.get("manual_zoom", 1.0)), 1.0, CAMERA_MAX_ZOOM)
	_camera_center = _bounded_camera_center(value.get("center", CAMERA_FRAME * 0.5), _camera_zoom)
	_manual_center = _bounded_camera_center(value.get("manual_center", CAMERA_FRAME * 0.5), _manual_zoom)
	_camera_override = bool(value.get("override", false)) and str(value.get("role", "")) == _camera_role
	_update_camera_controls()
	queue_redraw()


func _build_camera_controls() -> void:
	var panel := PanelContainer.new()
	panel.name = "TownCameraControls"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -202
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = 44
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var paper := _camera_control_style(Color(0.96, 0.93, 0.85, 0.96), Color("#b9a989"))
	panel.add_theme_stylebox_override("panel", paper)
	panel.tooltip_text = "滚轮缩放 · 放大后按住中键拖动"
	add_child(panel)
	var bar := HBoxContainer.new()
	bar.name = "CameraButtons"
	bar.add_theme_constant_override("separation", 4)
	panel.add_child(bar)
	_camera_zoom_out = _camera_button("−", "CameraZoomOutButton", bar)
	_camera_zoom_out.pressed.connect(func() -> void: _zoom_camera(-CAMERA_ZOOM_STEP, size * 0.5))
	_camera_readout = Label.new()
	_camera_readout.name = "CameraZoomReadout"
	_camera_readout.custom_minimum_size.x = 44
	_camera_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camera_readout.add_theme_font_size_override("font_size", 14)
	_camera_readout.add_theme_color_override("font_color", Color("#3e4a40"))
	bar.add_child(_camera_readout)
	_camera_zoom_in = _camera_button("+", "CameraZoomInButton", bar)
	_camera_zoom_in.pressed.connect(func() -> void: _zoom_camera(CAMERA_ZOOM_STEP, size * 0.5))
	var reset := _camera_button("全景", "CameraResetButton", bar)
	reset.tooltip_text = "回到完整街景"
	reset.pressed.connect(reset_camera_view)
	_update_camera_controls()


func _camera_button(text: String, control_name: String, parent: Control) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(30, 30)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("#494438"))
	button.add_theme_color_override("font_hover_color", Color("#3e4a40"))
	button.add_theme_color_override("font_pressed_color", Color("#3e4a40"))
	button.add_theme_color_override("font_disabled_color", Color("#a59b87"))
	button.add_theme_stylebox_override("normal", _camera_control_style(Color("#eee4ce"), Color("#b9a989")))
	button.add_theme_stylebox_override("hover", _camera_control_style(Color("#e5d7b7"), Color("#8d9b85")))
	button.add_theme_stylebox_override("pressed", _camera_control_style(Color("#d8c7a2"), Color("#8d9b85")))
	button.add_theme_stylebox_override("disabled", _camera_control_style(Color("#eee8d9"), Color("#d2c8b2")))
	button.tooltip_text = "缩小街景" if control_name == "CameraZoomOutButton" else "放大街景"
	parent.add_child(button)
	return button


func _camera_control_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _update_camera_controls() -> void:
	if is_instance_valid(_camera_readout):
		_camera_readout.text = "%d%%" % roundi(_camera_zoom * 100.0)
		_camera_zoom_out.disabled = _camera_zoom <= 1.0001
		_camera_zoom_in.disabled = _camera_zoom >= CAMERA_MAX_ZOOM - 0.0001


func _zoom_camera(amount: float, anchor: Vector2) -> void:
	var before := (anchor - _map_offset()) / maxf(_map_scale(), 0.001)
	_manual_zoom = clampf(_camera_zoom + amount, 1.0, CAMERA_MAX_ZOOM)
	_manual_center = _bounded_camera_center(before - (anchor - size * 0.5) / maxf(_base_map_scale() * _manual_zoom, 0.001), _manual_zoom)
	if is_equal_approx(_manual_zoom, 1.0):
		_manual_center = CAMERA_FRAME * 0.5
	_camera_zoom = _manual_zoom
	_camera_center = _manual_center
	_camera_override = not _camera_role.is_empty()
	_hover = ""
	_update_camera_controls()
	queue_redraw()


func reset_camera_view() -> void:
	_manual_zoom = 1.0
	_camera_zoom = 1.0
	_manual_center = CAMERA_FRAME * 0.5
	_camera_center = _manual_center
	_camera_override = not _camera_role.is_empty()
	_camera_dragging = false
	_hover = ""
	_update_camera_controls()
	queue_redraw()


func _resize_stage() -> void:
	if is_instance_valid(_stage) and size.x > 0 and size.y > 0:
		var width := clampi(ceili(size.x * CAMERA_MAX_ZOOM), 640, 1280)
		_stage.call("resize_view", Vector2i(width, ceili(float(width) * 9.0 / 16.0)))
	queue_redraw()


func _target_at(render_point: Vector2) -> String:
	var nearest := 46.0
	var found := ""
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var foot: Vector2 = _stage.call("logical_to_screen", at, 0.0)
		var marker: Vector2 = _stage.call("target_screen_position", id)
		var distance := minf(render_point.distance_to(foot), render_point.distance_to(marker))
		if id == "tea_seller":
			var head: Vector2 = _stage.call("logical_to_screen", at, 1.55)
			if Rect2(Vector2(foot.x - 28, head.y - 6), Vector2(56, foot.y - head.y + 20)).has_point(render_point):
				distance = minf(distance, 12.0)
		if distance < nearest:
			nearest = distance
			found = id
	return found


func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(_stage):
		return
	if event is InputEventMouseMotion:
		var mouse := event as InputEventMouseMotion
		if _camera_dragging and (mouse.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_manual_center = _bounded_camera_center(_camera_center - (mouse.position - _camera_drag_at) / maxf(_map_scale(), 0.001), _camera_zoom)
			_manual_zoom = _camera_zoom
			_camera_center = _manual_center
			_camera_drag_at = mouse.position
			_hover = ""
			queue_redraw()
			accept_event()
			return
		_camera_dragging = false
		var point := (mouse.position - _map_offset()) / maxf(_map_scale(), 0.001)
		_hover = _target_at(point)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_dragging = mouse.pressed and _camera_zoom > 1.0001
			_camera_drag_at = mouse.position
			if _camera_dragging:
				_camera_override = not _camera_role.is_empty()
				_manual_zoom = _camera_zoom
				_manual_center = _bounded_camera_center(_camera_center, _camera_zoom)
			accept_event()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			_zoom_camera(direction * CAMERA_ZOOM_STEP * (mouse.factor if mouse.factor > 0 else 1.0), mouse.position)
			accept_event()
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			if _camera_dragging:
				accept_event()
				return
			var point := (mouse.position - _map_offset()) / maxf(_map_scale(), 0.001)
			if not Rect2(0, 0, 1280, 720).has_point(point):
				return
			var target_id := _target_at(point)
			if target_id.is_empty():
				click_at(local_to_logical(mouse.position))
			else:
				var coordinates: Array = definition.interactions[target_id].position
				# Reuse the original selection/arrival rules with the real ground anchor.
				click_at(Vector2(float(coordinates[0]), float(coordinates[1])))
			accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_camera_dragging = false


func _process(delta: float) -> void:
	# Parent delta is used only for its walking-distance budget. Keep that
	# tested movement/arrival implementation intact while slowing this view's
	# pace to match its 90-unit authored double step. Stage ambience still reads
	# real elapsed time independently; gameplay slots and costs are unchanged.
	super._process(minf(delta, 0.05) * NATURAL_WALK_SPEED / SPEED)
	_visual_facing = _route_facing()
	if is_instance_valid(_stage):
		_stage.call("sync", player_position, _visual_facing, not route.is_empty(), walk_distance, active and is_visible_in_tree())
		if _motion_enabled and is_visible_in_tree() and not _camera_dragging:
			var goal := _camera_goal()
			var blend := 1.0 - exp(-6.0 * minf(delta, 0.05))
			_camera_zoom = lerpf(_camera_zoom, float(goal.zoom), blend)
			_camera_center = _bounded_camera_center(_camera_center.lerp(goal.center, blend), _camera_zoom)
			if absf(_camera_zoom - float(goal.zoom)) < 0.0001 and _camera_center.distance_to(goal.center) < 0.05:
				_camera_zoom = float(goal.zoom)
				_camera_center = goal.center
		_update_camera_controls()
		queue_redraw()


func _route_facing() -> String:
	if route.is_empty():
		return _visual_facing
	# Use the actual unrounded path segment, with a small dominant-axis margin.
	# Integer movement commits may alternate dx/dy near 45 degrees; that does
	# not mean the illustrated person should flip between front and side.
	var heading: Vector2 = route[0] - player_position
	if heading.length_squared() < 0.36:
		return _visual_facing
	var horizontal: bool = _visual_facing == "left" or _visual_facing == "right"
	if horizontal and absf(heading.y) > absf(heading.x) * 1.2:
		horizontal = false
	elif not horizontal and absf(heading.x) > absf(heading.y) * 1.2:
		horizontal = true
	return ("right" if heading.x > 0 else "left") if horizontal else ("down" if heading.y > 0 else "up")


func get_character_presentation_state() -> Dictionary:
	var volume := _volume_character()
	var cast := _volume_cast()
	return {"facing": _visual_facing, "stride": walk_distance,
		"cast": cast.call("get_presentation_state") if cast != null else {},
		"volume": volume.call("get_presentation_state") if volume != null else {}}


func set_character_presentation_state(value: Dictionary) -> void:
	var remembered := str(value.get("facing", "down"))
	if remembered in ["down", "up", "left", "right"]:
		_visual_facing = remembered
	walk_distance = maxf(float(value.get("stride", walk_distance)), 0.0)
	if is_instance_valid(_stage):
		_stage.call("sync", player_position, _visual_facing, not route.is_empty(), walk_distance, active and is_visible_in_tree())
	var volume := _volume_character()
	if volume != null:
		volume.call("set_presentation_state", value.get("volume", {}))
	var cast := _volume_cast()
	if cast != null and value.get("cast", {}) is Dictionary:
		cast.call("set_presentation_state", value.get("cast", {}))


func set_conversation_role(role: String) -> void:
	var focus_role := role if role in ["tea_seller", "tea_patron"] else ""
	if focus_role != _camera_role:
		_camera_override = false
	_camera_role = focus_role
	if is_instance_valid(_stage):
		_stage.set("conversation_role", role)


func _volume_cast() -> Node3D:
	if not is_instance_valid(_stage):
		return null
	var painting := _stage.get("_painted_street") as Node
	return painting.get("_volume_cast") as Node3D if is_instance_valid(painting) else null


func _volume_character() -> Node3D:
	if not is_instance_valid(_stage):
		return null
	var painting := _stage.get("_painted_street") as Node
	return painting.get("_volume_character") as Node3D if is_instance_valid(painting) else null


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#cbd1bd"))
	if not is_instance_valid(_stage) or _font == null:
		return
	var texture: Texture2D = _stage.call("texture")
	if texture == null:
		return
	draw_set_transform(_map_offset(), 0.0, Vector2.ONE * _map_scale())
	draw_texture_rect(texture, Rect2(0, 0, 1280, 720), false)
	if not active and bool(definition.get("character_reactions", false)):
		return
	if not route.is_empty():
		var points := PackedVector2Array()
		points.append(_stage.call("logical_to_screen", player_position, 0.025))
		for point: Vector2 in route:
			points.append(_stage.call("logical_to_screen", point, 0.025))
		if points.size() > 1:
			draw_polyline(points, Color(0.85, 0.85, 0.65, 0.75), 2.5, true)
		draw_arc(points[-1], 7, 0, TAU, 24, Color("#e1d5ac"), 2)
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var ground: Vector2 = _stage.call("logical_to_screen", at, 0.02)
		var highlighted := _hover == id or pending_target == id
		var nearby := player_position.distance_to(at) < 150.0
		if not highlighted and not nearby and id != "mountain_exit":
			continue
		if highlighted or nearby:
			draw_arc(ground, 15 if highlighted else 11, 0, TAU, 32, Color("#e1d5ac") if highlighted else Color(0.91, 0.87, 0.73, 0.7), 2)
		var height := 1.78 if id == "tea_seller" else 2.0 if id == "street_sign" else 0.1
		var label_at: Vector2 = _stage.call("logical_to_screen", at, height)
		label_at += Vector2(0, -10 if id == "tea_seller" else 26)
		if id == "tea_patron":
			label_at = _stage.call("target_screen_position", id) + Vector2(0, -14)
		var label_text := str(item.label)
		var label_width := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_style_box(_label_style(), Rect2(label_at - Vector2(label_width * 0.5 + 8, 21), Vector2(label_width + 16, 28)))
		_label(label_at, label_text, Color("#3e4a40"), 20)


func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.81, 0.88)
	style.set_corner_radius_all(4)
	return style


func set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if is_instance_valid(_stage):
		_stage.call("set_motion_enabled", enabled)


func set_lighting_enabled(enabled: bool) -> void:
	_lighting_enabled = enabled
	if is_instance_valid(_stage):
		_stage.call("set_lighting_enabled", enabled)
	queue_redraw()


func get_lighting_enabled() -> bool:
	return _lighting_enabled


func get_presentation_elapsed() -> float:
	return float(_stage.get("ambient_elapsed")) if is_instance_valid(_stage) else 0.0


func set_presentation_elapsed(value: float) -> void:
	if is_instance_valid(_stage):
		_stage.set("ambient_elapsed", maxf(value, 0.0))
		_stage.call("_update_ambient")
