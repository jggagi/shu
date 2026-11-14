extends "res://tests/cultivation_engine_chengdu_finished_street_render.gd"


func _check_art_street() -> bool:
 var original: bool=super._check_art_street()
 var audit: Dictionary=_large_audit().get("layered_street",{})
 var grounding: Dictionary=audit.get("grounding",{})
 check(float(grounding.get("contact_corner_max_height_error",1.0))<0.00001 and int(grounding.get("actual_contact_mesh_vertices",0))>=54,"all painted foundation corners meet the actual horizontal floor")
 check(int(grounding.get("apron_segments",0))==36 and int(audit.get("drainage_seams",-1))==0,"feathered paving replaces the old separate border seams")
 return original
