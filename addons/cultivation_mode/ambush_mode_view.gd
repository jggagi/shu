extends "res://addons/cultivation_mode/town_hd2d_mode_view.gd"
## One isolated presentation adapter; the old catalog uses the original Session.

const AmbushSessionScript = preload("res://addons/cultivation_mode/ambush_session.gd")
const AmbushViewScript = preload("res://addons/cultivation_mode/ambush_view.gd")
@export var auto_start_ambush: bool = true
@export var battle_on_new_run: bool = true
@export var review_tools_enabled: bool = true
var _ambush_view: Control
var _ambush_key := ""


func _ready() -> void:
	super._ready()
	if auto_start_ambush:
		call_deferred("_launch_ambush_entry")


func _launch_ambush_entry() -> void:
	if _catalog.is_empty() or not bool(_catalog[0].get("ok", false)):
		return
	var mode := "continue" if bool(_store.call("has_save", _catalog[0].get("pack", {}))) else "new"
	_perform_launch(0, mode)


func _create_session(data: Dictionary) -> RefCounted:
	return AmbushSessionScript.new() if data.has("ambush") else super._create_session(data)


func _perform_launch(index: int, mode: String) -> void:
	super._perform_launch(index, mode)
	if battle_on_new_run and mode == "new" and _active_index == index and _session != null and _session.has_method("begin_ambush") and str(_snapshot().get("phase", "")) == "ready":
		_start_ambush()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_ambush_view):
		return
	super._input(event)


func _render() -> void:
	var context: Dictionary = _session.call("ambush_context") if _session != null and _session.has_method("ambush_context") else {}
	if not context.is_empty() and _view_mode == "game":
		var key := "%s:%s" % [str(context.run_id), str(context.operation_id)]
		if is_instance_valid(_ambush_view) and key == _ambush_key:
			return
		_clear_ambush_view()
		if is_instance_valid(_town_walker):
			_town_walker.call("cancel_walk")
			_town_walker.set("active", false)
		if is_instance_valid(_screen):
			_screen.hide()
		if is_instance_valid(_voice_player):
			_voice_player.call("stop", "ambush")
		_ambush_key = key
		_ambush_view = AmbushViewScript.new() as Control
		_ambush_view.name = "AmbushBattleView"
		_ambush_view.set("review_tools_enabled", review_tools_enabled)
		_ambush_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_ambush_view)
		_ambush_view.connect("completed", _on_ambush_completed.bind(str(context.run_id), str(context.operation_id)))
		_ambush_view.connect("return_requested", _on_ambush_return.bind(str(context.run_id), str(context.operation_id)))
		_ambush_view.connect("retry_requested", _on_ambush_retry.bind(str(context.run_id), str(context.operation_id)))
		_ambush_view.call("setup", _session, _session.call("battle"), context)
		return
	_clear_ambush_view()
	super._render()


func _clear_ambush_view() -> void:
	if is_instance_valid(_ambush_view):
		_ambush_view.hide()
		_ambush_view.queue_free()
	_ambush_view = null
	_ambush_key = ""


func _run_action(action_id: String) -> void:
	if action_id == "begin_ambush":
		_start_ambush()
		return
	super._run_action(action_id)


func _start_ambush() -> void:
	if _session == null or not _session.has_method("begin_ambush") or _input_busy:
		return
	var before := _snapshot()
	var result: Dictionary = _session.call("begin_ambush", str(before.run_id), "", int(before.revision))
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("reason", "暂时不能进入山道")), true)
	_render()


func _on_ambush_completed(run_id: String, operation_id: String) -> void:
	if _session == null or not _session.has_method("finish_ambush"):
		return
	var result: Dictionary = _session.call("finish_ambush", run_id, operation_id)
	_set_status(str(result.get("message", result.get("reason", "战斗已结束"))), not bool(result.get("ok", false)))


func _on_ambush_return(run_id: String, operation_id: String) -> void:
	if _session == null or not _session.has_method("abandon_ambush"):
		return
	var result: Dictionary = _session.call("abandon_ambush", run_id, operation_id)
	if bool(result.get("ok", false)):
		var closed: Dictionary = _session.call("close_ambush", run_id, operation_id)
		if not bool(closed.get("ok", false)):
			return
		_set_status(str(result.get("message", "已返回原来的旅程")))
		_render()
	else:
		_set_status(str(result.get("reason", "暂时不能返回")), true)


func _on_ambush_retry(run_id: String, operation_id: String) -> void:
	if _session == null or not _session.has_method("close_ambush"):
		return
	var context: Dictionary = _session.call("ambush_context")
	if context.get("run_id", "") != run_id or context.get("operation_id", "") != operation_id:
		return
	if not bool(context.get("settled", false)):
		var abandoned: Dictionary = _session.call("abandon_ambush", run_id, operation_id)
		if not bool(abandoned.get("ok", false)):
			_set_status(str(abandoned.get("reason", "暂时不能重开本战")), true)
			return
	var closed: Dictionary = _session.call("close_ambush", run_id, operation_id)
	if not bool(closed.get("ok", false)):
		return
	if str(_snapshot().get("phase", "")) == "result":
		_session.call("acknowledge_result")
	_clear_ambush_view()
	_start_ambush()


func _build_game_view() -> Control:
	var body := super._build_game_view()
	if _town_scene() and _session != null and _session.has_method("begin_ambush") and is_instance_valid(_right_column):
		var start := _make_button("再走山道 · 遇袭", "BeginAmbushButton", _start_ambush, str(_snapshot().get("phase", "")) != "ready")
		_right_column.add_child(start)
		_right_column.move_child(start, 1)
	return body


func audit_snapshot() -> Dictionary:
	var result := super.audit_snapshot()
	result["ambush"] = _session.call("ambush_context") if _session != null and _session.has_method("ambush_context") else {}
	if is_instance_valid(_ambush_view) and _ambush_view.has_method("audit_snapshot"):
		result["battle_view"] = _ambush_view.call("audit_snapshot")
	return result
