extends "res://addons/cultivation_mode/chengdu_painted_gate_stage.gd"
## Extend the approved gate's brushwork across the existing continuous city.
## Geometry, navigation, camera and state remain in the retained parent stages.

const PaintedCitySurfaces = preload("res://addons/cultivation_mode/chengdu_painted_city_surfaces.gd")
var _painted_city_surfaces: Node


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker,font,definition)
	_painted_city_surfaces=PaintedCitySurfaces.new()
	_painted_city_surfaces.name="PaintedCitySurfaces"
	add_child(_painted_city_surfaces)
	_painted_city_surfaces.call("setup",self)


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var first := world_root.get_child_count()
	super._build_dense_ward(bounds,label)
	if is_instance_valid(_painted_city_surfaces):
		for index: int in range(first,world_root.get_child_count()):
			_painted_city_surfaces.call("attach_tree",world_root.get_child(index))


func _garden_tree(parent: Node3D, at: Vector3, height: float, peach: bool) -> void:
	var first := parent.get_child_count()
	super._garden_tree(parent,at,height,peach)
	# Shared plaster/flat materials also appear on leaves. Keep their authored
	# botanical colours, rather than mistaking a crown for an ivory wall.
	for index: int in range(first,parent.get_child_count()):
		parent.get_child(index).set_meta("painted_city_preserve",true)


func _lot_root(bounds: Rect2, name_text: String) -> Node3D:
	var body := super._lot_root(bounds,name_text)
	if bool(_building_profile(bounds).get("individual_house",false)):
		body.set_meta("painted_city_house",true)
	return body


func audit() -> Dictionary:
	var result := super.audit()
	result["painted_city_surfaces"]=_painted_city_surfaces.call("audit") if is_instance_valid(_painted_city_surfaces) else {}
	return result
