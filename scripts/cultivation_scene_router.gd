extends RefCounted

# Only the two actual cultivation locations. The host decides availability.
var current_scene_id := "tingyu"
var return_scene_id := ""

func enter_back_mountain(available: bool) -> bool:
	if not available or current_scene_id != "tingyu":
		return false
	return_scene_id = current_scene_id
	current_scene_id = "back_mountain"
	return true

func return_to_tingyu() -> bool:
	if current_scene_id != "back_mountain" or return_scene_id != "tingyu":
		return false
	current_scene_id = return_scene_id
	return_scene_id = ""
	return true
