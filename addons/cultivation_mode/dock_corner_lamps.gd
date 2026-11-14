extends Node2D
## Small code-drawn paper lanterns, anchored to the actual painted eave/boat.
const LAYOUT = "res://assets/data/dock-corner-lamps.json"
var fixtures: Array = []
var elapsed := 0.0
var strength := 0.0

func _init() -> void:
	fixtures = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)).fixtures

static func flame_level(seconds: float) -> float:
	return 0.97+sin(seconds*1.4)*0.02+sin(seconds*2.6+0.7)*0.01

func present(seconds: float, amount: float) -> void:
	elapsed = seconds
	strength = amount
	visible = strength>0.0
	queue_redraw()

func _draw() -> void:
	var flicker := flame_level(elapsed)
	for fixture: Dictionary in fixtures:
		var center := Vector2(fixture.center[0],fixture.center[1])
		var hanger := Vector2(fixture.hanger[0],fixture.hanger[1])
		var size := Vector2(fixture.size[0],fixture.size[1])
		var ink := Color("#3b342b")
		draw_line(hanger,center-Vector2(0,size.y*0.57),ink,1.2,true)
		# Uneven silk-paper outline and thin ribs keep the fixture subordinate.
		var shell := PackedVector2Array()
		for point: Vector2 in [Vector2(-0.37,-0.46),Vector2(0.30,-0.48),Vector2(0.51,-0.24),Vector2(0.47,0.30),Vector2(0.29,0.48),Vector2(-0.31,0.46),Vector2(-0.51,0.22),Vector2(-0.49,-0.24)]:
			shell.append(center+point*size)
		draw_colored_polygon(shell,Color(0.84,0.41,0.12,1.0))
		var paper := PackedVector2Array()
		for point: Vector2 in shell:
			paper.append(center+(point-center)*Vector2(0.83,0.87))
		draw_colored_polygon(paper,Color(1.0,0.70*flicker,0.30,1.0))
		shell.append(shell[0])
		draw_polyline(shell,ink,0.8,true)
		for side: float in [-0.23,0.22]:
			draw_line(center+Vector2(size.x*side,-size.y*0.43),center+Vector2(size.x*side,size.y*0.43),Color(0.48,0.26,0.10,0.55),0.65,true)
		draw_circle(center, size.x*0.14,Color(1.0,0.91,0.61,flicker*0.8),true,-1.0,true)
		for direction: float in [-1.0,1.0]:
			var y := direction*size.y*0.49
			draw_line(center+Vector2(-size.x*0.33,y),center+Vector2(size.x*0.33,y),ink,1.8,true)
		draw_line(center+Vector2(0,size.y*0.52),center+Vector2(-0.5,size.y*0.69),Color("#97623b"),1.0,true)
