extends Control
## Compact anchored presentation, reusable for any scene prop and host actions.
signal action_requested(object_id: String, action_id: String, session: int)

var object_id := ""
var session := 0
var buttons: Dictionary = {}
var anchor_x := 0.0
var anchor_point := Vector2.ZERO

func present(data: Dictionary, actions: Array, object_rect: Rect2, scene_size: Vector2, active_session: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	object_id = data.id
	session = active_session
	size = Vector2(310, 138 + actions.size()*48)
	position = Vector2(clampf(object_rect.get_center().x-size.x/2, 18, scene_size.x-size.x-18), maxf(18, object_rect.position.y-size.y-22))
	position.y = minf(position.y, scene_size.y-size.y-24)
	anchor_point = Vector2(object_rect.get_center().x, object_rect.position.y-5)-position
	anchor_x = clampf(anchor_point.x, 24, size.x-24)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := NinePatchRect.new()
	paper.texture = load("res://assets/art/v2/paper-frame-v2.png")
	paper.patch_margin_left = 100
	paper.patch_margin_right = 100
	paper.patch_margin_top = 100
	paper.patch_margin_bottom = 100
	paper.size = size / 0.07
	paper.scale = Vector2(0.07,0.07)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	_label(data.label, Rect2(20,12,270,35),25)
	var description := _label(data.text, Rect2(20,52,270,74),19)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in actions.size():
		var action: Dictionary = actions[i]
		var button := Button.new()
		button.text = action.label + (" · 已完成" if action.done else "   精力 -%d" % action.cost)
		button.disabled = not action.enabled
		button.tooltip_text = action.reason
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.position = Vector2(19,128+i*48)
		button.size = Vector2(272,40)
		button.add_theme_font_size_override("font_size",20)
		for style in ["normal","hover","pressed","focus","disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("e6dfcc") if style == "normal" else Color("d1c4a7")
			if style == "disabled": box.bg_color = Color("eee7d8")
			box.border_color = Color("88704b")
			box.set_border_width_all(2 if style == "focus" else 1)
			box.set_corner_radius_all(2)
			button.add_theme_stylebox_override(style,box)
		button.add_theme_color_override("font_color",Color("354137"))
		button.add_theme_color_override("font_hover_color",Color("32695c"))
		button.add_theme_color_override("font_pressed_color",Color("354137"))
		button.add_theme_color_override("font_disabled_color",Color("918573"))
		button.pressed.connect(_request.bind(object_id, str(action.id), session))
		add_child(button)
		buttons[action.id] = button
	visible = true
	queue_redraw()

func _request(id: String, action_id: String, active_session: int) -> void:
	action_requested.emit(id, action_id, active_session)

func _label(text: String, rect: Rect2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("354137"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _draw() -> void:
	if not visible: return
	var left := Vector2(anchor_x-10,size.y-1)
	var right := Vector2(anchor_x+10,size.y-1)
	var tip := Vector2(anchor_x,size.y+14)
	draw_colored_polygon(PackedVector2Array([left,right,tip]),Color("f4eddf"))
	draw_polyline(PackedVector2Array([left,tip,right]),Color("88704b"),1.5,true)
	if anchor_point.distance_to(tip) > 16:
		draw_line(tip,anchor_point,Color("ad8959"),1.0,true)
	draw_circle(anchor_point,3.0,Color("ad8959"))
