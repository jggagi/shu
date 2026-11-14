extends "res://addons/cultivation_mode/chengdu_illustrated_street_stage.gd"

var _layered_street: Node


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker, font, definition)
	_layered_street=_create_layered_street()
	_layered_street.name="LayeredStreetFinish"
	add_child(_layered_street)
	_layered_street.call("setup",self)


func _create_layered_street() -> Node:
	return load("res://addons/cultivation_mode/chengdu_layered_street.gd").new()


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	super._build_dense_ward(bounds,label)
	if is_instance_valid(_layered_street):
		_layered_street.call("attach_houses")


func sync(point: Vector2, facing: String, walking: bool, stride: float, enabled: bool) -> void:
	super.sync(point,facing,walking,stride,enabled)
	if is_instance_valid(_layered_street):
		_layered_street.call("sync",ambient_elapsed)


func audit() -> Dictionary:
	var result:=super.audit()
	result["layered_street"]=_layered_street.call("audit") if is_instance_valid(_layered_street) else {}
	return result
