extends "res://addons/cultivation_mode/chengdu_compact_street_stage.gd"


func _create_layered_street() -> Node:
	return load("res://addons/cultivation_mode/chengdu_tea_corner.gd").new()


func audit() -> Dictionary:
	var result:=super.audit()
	if not is_instance_valid(_layered_street):
		return result
	var corner: Dictionary=_layered_street.audit().tea_corner
	if corner.enabled and corner.seller_anchor_clear and corner.seller_frontage_valid:
		var merchant: Dictionary=result.tea_polish.merchant
		merchant["source_anchor"]=merchant.logical_anchor
		merchant["logical_anchor"]=corner.seller_anchor
		merchant["shoe_world_y"]=corner.seller_shoe_y
		merchant["original_navigation_walkable"]=true
		merchant["current_frontage_source"]="res://assets/data/chengdu-tea-corner-layout.json"
	return result
