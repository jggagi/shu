extends "res://addons/cultivation_mode/chengdu_art_street_stage.gd"
## An independent, fixed-angle painted comparison. Original gameplay is reused.

var _illustrated_street: Node


func setup(walker: Control,font: Font,definition: Dictionary) -> void:
	super.setup(walker,font,definition)
	_illustrated_street=load("res://addons/cultivation_mode/chengdu_illustrated_street.gd").new()
	_illustrated_street.name="PaintedStreetComposition"
	add_child(_illustrated_street)
	_illustrated_street.call("setup",self)
	_update_follow_camera(_player,0.0,true)


func _update_follow_camera(point: Vector2,delta: float,snap: bool) -> void:
	super._update_follow_camera(point,delta,snap)
	# Keep the same lens, distance and continuous follow rule; use a fixed
	# isometric direction so painted ground corners match the original lots.
	var basis:=Basis.from_euler(Vector3(deg_to_rad(-FOLLOW_ELEVATION),deg_to_rad(45.0),0.0))
	camera.basis=basis
	camera.position=logical_to_world(_camera_center)+basis.z*FOLLOW_DISTANCE


func _build_dense_ward(bounds: Rect2,label: String) -> void:
	super._build_dense_ward(bounds,label)
	var id:=str(_building_profile(bounds).get("id",""))
	if is_instance_valid(_illustrated_street) and _art_roots.has(id):
		_illustrated_street.call("attach_house",_art_roots[id])


func audit() -> Dictionary:
	var result:=super.audit()
	result.art_street["continuous_follow_unchanged"]=false
	result.art_street["camera_change"]="Fixed yaw45; original pitch52, lens39, distance13.5 and continuous follow rule retained"
	result["illustrated_street"]=_illustrated_street.call("audit") if is_instance_valid(_illustrated_street) else {}
	return result
