extends "res://addons/cultivation_mode/chengdu_detail_stage.gd"
## The accepted continuous following camera remains unchanged. The local art
## helper projects a recorded painting onto matching original world surfaces.

const PaintedGateArt = preload("res://addons/cultivation_mode/chengdu_painted_gate_art.gd")
var _painted_gate: Node


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	# The constructor supplies the default. Keep an explicit scene variant's
	# layout so presentation and Session can use the same moved lots.
	super.setup(walker,font,definition)
	_painted_gate = PaintedGateArt.new()
	_painted_gate.name = "WorldProjectiveGateArt"
	add_child(_painted_gate)
	_painted_gate.call("setup",self)


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var first := world_root.get_child_count()
	super._build_dense_ward(bounds,label)
	if is_instance_valid(_painted_gate):
		for index: int in range(first,world_root.get_child_count()):
			_painted_gate.call("attach_tree",world_root.get_child(index))


func _lot_root(bounds: Rect2, name_text: String) -> Node3D:
	var root := super._lot_root(bounds,name_text)
	# Both returns use the same historical name, which Godot may rename. Keep
	# this local art scope explicit without depending on generated NodePaths.
	if name_text=="SouthGateStoneReturn":
		root.set_meta("painted_gate_return",true)
	return root


func sync(player_position: Vector2, facing: String, walking: bool, stride_distance: float, enabled: bool) -> void:
	super.sync(player_position,facing,walking,stride_distance,enabled)
	if is_instance_valid(_painted_gate):
		_painted_gate.call("sync")


func audit() -> Dictionary:
	var result := super.audit()
	result["painted_gate"] = _painted_gate.call("audit") if is_instance_valid(_painted_gate) else {}
	return result
