extends Control
## One spatial presenter. EngineSession owns all persistent position and actions.
## Route / arrival rules adapted from Chengping a4a6c1c; see source audit.

signal interaction_requested(id: String, run_id: String, revision: int)
signal feedback(message: String)

const NavigationScript = preload("res://addons/cultivation_mode/town_navigation.gd")
const INK := Color("#494438")
const TEAL := Color("#476f6a")
const SPEED := 210.0

var definition: Dictionary = {}
var scene_id := ""
var session: RefCounted
var navigation: RefCounted
var player_position := Vector2.ZERO
var route: Array[Vector2] = []
var pending_target := ""
var facing := "down"
var walk_distance := 0.0
var interaction_count := 0
var active := false
var _run_id := ""
var _revision := -1
var _font: Font
var _hover := ""
var _movement_budget := 0.0


func setup(host: RefCounted, map_id: String, map: Dictionary, font: Font, enabled: bool) -> void:
	session = host
	scene_id = map_id
	definition = map.duplicate(true)
	_font = font
	navigation = NavigationScript.new()
	navigation.call("configure", definition)
	var state: Dictionary = session.call("snapshot")
	_run_id = str(state.run_id)
	_revision = int(state.revision)
	var coordinates: Array = state.exploration.positions[scene_id]
	player_position = Vector2(float(coordinates[0]), float(coordinates[1]))
	active = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	queue_redraw()


func audit() -> Dictionary:
	return {"position": player_position, "route": route.duplicate(), "pending_target": pending_target,
		"active": active, "facing": facing, "walk_distance": walk_distance,
		"interaction_count": interaction_count, "definition": definition.duplicate(true),
		"run_id": _run_id, "revision": _revision}


func _map_scale() -> float:
	return minf(size.x / 1280.0, size.y / 720.0)


func _map_offset() -> Vector2:
	return (size - Vector2(1280, 720) * _map_scale()) * 0.5


func logical_to_local(point: Vector2) -> Vector2:
	return _map_offset() + point * _map_scale()


func local_to_logical(point: Vector2) -> Vector2:
	return (point - _map_offset()) / maxf(_map_scale(), 0.001)


func cancel_walk() -> void:
	route.clear()
	pending_target = ""
	_movement_budget = 0.0
	queue_redraw()


func _current() -> bool:
	if not active or session == null or not is_visible_in_tree():
		return false
	var state: Dictionary = session.call("snapshot")
	return str(state.run_id) == _run_id and int(state.revision) == _revision and str(state.phase) == "ready" and str(state.scene) == scene_id


func click_at(point: Vector2) -> bool:
	if not _current():
		return false
	cancel_walk()
	var clicked := ""
	var nearest := 44.0
	var interactions: Dictionary = definition.get("interactions", {})
	for id: String in interactions:
		var target: Dictionary = interactions[id]
		var coordinates: Array = target.position
		var at := Vector2(float(coordinates[0]), float(coordinates[1]))
		var center := at - Vector2(0, 24) if id == "tea_seller" else at
		var distance := point.distance_to(center)
		if distance < nearest:
			nearest = distance
			clicked = id
	var destination := point.round()
	var radius := 0.0
	if not clicked.is_empty():
		var target: Dictionary = interactions[clicked]
		destination = Vector2(float(target.position[0]), float(target.position[1]))
		radius = float(target.radius)
	route.assign(navigation.call("route", player_position, destination, radius))
	if route.is_empty():
		feedback.emit("那里走不到。请点石路，或人物、木牌与返山出口。")
		return false
	pending_target = clicked
	feedback.emit("走近后互动。" if not clicked.is_empty() else "沿石路走过去。")
	queue_redraw()
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var logical := local_to_logical((event as InputEventMouseMotion).position)
		_hover = ""
		for id: String in definition.get("interactions", {}):
			var target: Dictionary = definition.interactions[id]
			if logical.distance_to(Vector2(float(target.position[0]), float(target.position[1])) - Vector2(0, 16)) < 50:
				_hover = id
		queue_redraw()
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			click_at(local_to_logical(mouse.position))
			accept_event()


func _process(delta: float) -> void:
	if route.is_empty():
		return
	if not _current():
		cancel_walk()
		return
	# Keep subpixel distance across frames; high-refresh displays must not stall.
	var budget := _movement_budget + SPEED * clampf(delta, 0.0, 0.05)
	while budget > 0.01 and not route.is_empty():
		var destination: Vector2 = route[0]
		var distance := player_position.distance_to(destination)
		if distance < 0.6:
			route.pop_front()
			continue
		var next := player_position.move_toward(destination, minf(budget, distance)).round()
		if next == player_position:
			break
		var direction := next - player_position
		var result: Dictionary = session.call("commit_walk_position", scene_id, [int(next.x), int(next.y)], _run_id, _revision)
		if not bool(result.get("ok", false)):
			cancel_walk()
			feedback.emit(str(result.get("reason", "暂时不能走动。")))
			return
		var state: Dictionary = session.call("snapshot")
		_revision = int(state.revision)
		walk_distance += direction.length()
		budget -= direction.length()
		player_position = next
		facing = ("right" if direction.x > 0 else "left") if absf(direction.x) > absf(direction.y) else ("down" if direction.y > 0 else "up")
	_movement_budget = budget if not route.is_empty() else 0.0
	if route.is_empty() and not pending_target.is_empty():
		var arriving := pending_target
		# Clear before emitting: repeated frames/clicks cannot replay an arrival.
		pending_target = ""
		interaction_count += 1
		interaction_requested.emit(arriving, _run_id, _revision)
	queue_redraw()


func _label(at: Vector2, text: String, color: Color = INK, font_size: int = 20) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _polygon(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)


func _draw() -> void:
	if _font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#e5dcc6"))
	draw_set_transform(_map_offset(), 0, Vector2.ONE * _map_scale())
	draw_rect(Rect2(0, 0, 1280, 720), Color("#e9e1ca"))
	# Original code-native map; architecture feet and path collisions share data.
	_polygon([Vector2(0,170),Vector2(120,38),Vector2(260,148),Vector2(380,42),Vector2(530,170)], Color("#c1c6ad"))
	_polygon([Vector2(680,155),Vector2(880,35),Vector2(1040,140),Vector2(1190,60),Vector2(1280,180)], Color("#ccd0b7"))
	draw_rect(Rect2(60,160,1160,490), Color("#d5d0b6"))
	draw_rect(Rect2(68,282,1144,354), Color("#dfd8c1"))
	for y in range(300, 646, 38):
		for x in range(75 + (19 if y % 76 == 0 else 0), 1210, 78):
			draw_line(Vector2(x,y), Vector2(x+59,y-2), Color(0.62,0.59,0.48,0.14), 1.5)
	for i in range(7):
		draw_line(Vector2(108,145+i*16), Vector2(212,145+i*16), Color("#b6b49a"), 4)
	_label(Vector2(160,113), "上山石阶", TEAL, 20)
	var obstacles: Array = definition.get("obstacles", [])
	for index in range(obstacles.size()):
		var box: Array = obstacles[index]
		var rect := Rect2(float(box[0]),float(box[1]),float(box[2]),float(box[3]))
		_building(rect, index == 1)
	# Tea stall and a bench sit beyond the central obstacle.
	draw_rect(Rect2(930,264,176,30), Color("#8a7352"))
	draw_line(Vector2(942,290),Vector2(942,318),Color("#806a4f"),6)
	draw_line(Vector2(1092,290),Vector2(1092,318),Color("#806a4f"),6)
	draw_circle(Vector2(975,259),10,Color("#b5a88d"))
	draw_circle(Vector2(1017,259),7,Color("#efe6d3"))
	for at in [Vector2(80,650),Vector2(1180,164),Vector2(1200,655)]:
		draw_line(at,at-Vector2(0,70),Color("#8a8065"),9)
		draw_circle(at-Vector2(4,87),35,Color("#8e9f7f"))
		draw_circle(at+Vector2(18,-67),27,Color("#a6ad88"))
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]),float(item.position[1]))
		var selected := pending_target == id or _hover == id
		draw_arc(at, 30 if selected else 23, 0, TAU, 32, Color("#799387") if selected else Color("#ada58d"), 3 if selected else 1.5)
		if id == "tea_seller":
			_person(at, "down", 0, Color("#9c8063"), false)
			_label(at+Vector2(82,-36), str(item.label), INK, 21)
		elif id == "street_sign":
			draw_line(at,at-Vector2(0,48),Color("#786b54"),6)
			draw_rect(Rect2(at-Vector2(30,62),Vector2(60,39)),Color("#b8a47e"))
			_label(at-Vector2(0,36), "集", INK, 22)
			_label(at+Vector2(0,46),str(item.label),INK,20)
		else:
			_polygon([at+Vector2(0,-18),at+Vector2(-10,2),at+Vector2(10,2)], TEAL)
			_label(at+Vector2(0,48),str(item.label),TEAL,20)
	if not route.is_empty():
		var points := PackedVector2Array([player_position])
		points.append_array(PackedVector2Array(route))
		if points.size() > 1:
			draw_polyline(points, Color(0.24,0.41,0.37,0.48), 3, true)
		draw_arc(points[-1],8,0,TAU,24,TEAL,2)
	_person(player_position,facing,sin(walk_distance/15.0)*4.0 if not route.is_empty() else 0.0,Color("#547c88"),true)
	_label(player_position+Vector2(0,27),"江砚秋",TEAL,19)
	draw_line(Vector2(60,671),Vector2(1220,671),Color("#b9ac8e"),1)
	_label(Vector2(640,702),"点石路行走 · 点人物、木牌或出口，走近互动",INK,21)


func _building(rect: Rect2, shop: bool) -> void:
	draw_rect(Rect2(rect.position+Vector2(7,10),rect.size),Color(0.25,0.22,0.16,0.13))
	draw_rect(rect,Color("#c0ac83") if shop else Color("#b99c72"))
	for x in range(int(rect.position.x+15),int(rect.end.x),55):
		draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color("#a58c65"),2)
	var roof_y := rect.position.y - (55 if shop else 34)
	_polygon([Vector2(rect.position.x-20,rect.position.y+28),Vector2(rect.position.x+18,roof_y),Vector2(rect.end.x-18,roof_y),Vector2(rect.end.x+20,rect.position.y+28)],Color("#6c796e") if shop else Color("#9c8061"))
	draw_line(Vector2(rect.position.x-20,rect.position.y+28),Vector2(rect.end.x+20,rect.position.y+28),Color("#596357"),6)
	_label(Vector2(rect.get_center().x,rect.position.y+64),"临街铺面" if shop else "遮雨摊棚",Color("#514b3b"),21)
	if not shop:
		for x in [rect.position.x+10,rect.end.x-10]:
			draw_line(Vector2(x,rect.position.y+27),Vector2(x,rect.end.y),Color("#7a6548"),7)


func _person(at: Vector2, direction: String, stride: float, robe: Color, player: bool) -> void:
	# Full body, independently drawn front/back/left/right, feet on world anchor.
	# Walk phase is actual distance, never an indoor portrait or practice atlas.
	draw_set_transform(_map_offset()+at*_map_scale(),0,Vector2.ONE*_map_scale())
	draw_ellipse_shadow()
	var side := direction == "left" or direction == "right"
	var sign_x := -1.0 if direction == "left" else 1.0
	var skin := Color("#dabd94")
	var hair := Color("#494237")
	for i in range(2):
		var leg_x := (-6.0 if i==0 else 6.0) if not side else (-3.0 if i==0 else 3.0)
		var lift := stride if i == 0 else -stride
		draw_line(Vector2(leg_x,-18),Vector2(leg_x+lift*0.45,-3-absf(lift)*0.4),Color("#eee4cb"),7)
		draw_line(Vector2(leg_x+lift*0.45-3,-3-absf(lift)*0.4),Vector2(leg_x+lift*0.45+5,-3-absf(lift)*0.4),hair,5)
	_polygon([Vector2(-12,-41),Vector2(12,-41),Vector2(16,-17),Vector2(-16,-17)],robe)
	draw_line(Vector2(-11,-40),Vector2(-18,-23+stride),robe.darkened(0.08),9)
	draw_line(Vector2(11,-40),Vector2(18,-23-stride),robe.lightened(0.03),9)
	draw_circle(Vector2(-18,-23+stride),3.7,skin)
	draw_circle(Vector2(18,-23-stride),3.7,skin)
	draw_line(Vector2(-11,-28),Vector2(11,-28),Color("#e3d5ae"),4)
	draw_circle(Vector2(0,-54),13,hair)
	if direction != "up":
		draw_circle(Vector2(sign_x*4 if side else 0,-51),10,skin)
		draw_arc(Vector2(0,-55),12,PI,TAU,16,hair,7)
		if side:
			draw_circle(Vector2(sign_x*10,-52),1.7,hair)
			_polygon([Vector2(sign_x*11,-52),Vector2(sign_x*15,-49),Vector2(sign_x*11,-48)],skin)
		else:
			draw_circle(Vector2(-4,-51),1.5,hair)
			draw_circle(Vector2(4,-51),1.5,hair)
	else:
		draw_line(Vector2(0,-51),Vector2(1,-34),hair,7)
	draw_circle(Vector2(-2,-68),5.5,hair)
	if player:
		draw_line(Vector2(-7,-63),Vector2(7,-63),Color("#ddd3b7"),3)
		if direction == "up":
			draw_line(Vector2(5,-61),Vector2(12,-45),Color("#ddd3b7"),2)
	draw_set_transform(_map_offset(),0,Vector2.ONE*_map_scale())


func draw_ellipse_shadow() -> void:
	# A compact contact shadow stays attached to both moving feet.
	draw_style_box(_shadow_style(),Rect2(-19,-4,38,9))


func _shadow_style() -> StyleBoxFlat:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.24,0.23,0.17,0.18)
	shadow.set_corner_radius_all(8)
	return shadow
