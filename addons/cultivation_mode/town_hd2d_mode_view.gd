extends "res://addons/cultivation_mode/town_mode_view.gd"
## Presentation-only replacement. Keeps the exact P1b content and checkpoint IDs.

const HD2DWalkerScript = preload("res://addons/cultivation_mode/town_hd2d_walker.gd")


func audit_snapshot() -> Dictionary:
	var result := super.audit_snapshot()
	result["hd2d"] = result.get("town", {}).get("hd2d", {})
	return result


func _build_scene_surface(scene_info: Dictionary) -> void:
	if not _town_scene():
		super._build_scene_surface(scene_info)
		return
	_town_walker = HD2DWalkerScript.new() as Control
	_town_walker.name = "TownWalker"
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	var map_id := str(state.scene)
	var map: Dictionary = _current_pack().walks.scenes[map_id]
	var enabled := str(state.phase) == "ready" and _confirmation.is_empty() and not _input_busy
	_town_walker.call("setup", _session, map_id, map, _theme_resource.default_font, enabled)
	_town_walker.connect("interaction_requested", _on_town_interaction)
	_town_walker.connect("feedback", _on_town_feedback)


func _build_header() -> PanelContainer:
	var header := super._build_header()
	if _town_scene():
		var eyebrow := header.get_child(0).get_child(0).get_child(0).get_child(0) as Label
		eyebrow.text = "蜀 · 山下集镇"
	return header
