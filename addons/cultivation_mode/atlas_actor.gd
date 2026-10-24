extends Control
## Generic atlas-frame player for content-pack cultivation motions.

signal phase_changed(phase: String, label: String)
signal finished(run_id: String, operation_id: String)

const SHADOW_COLOR := Color(0.12, 0.13, 0.12, 0.16)

var playing: bool = false
var neutral: bool = true
var motion_id: String = ""
var clip_id: String = ""
var run_id: String = ""
var operation_id: String = ""
var current_frame: int = -1
var current_phase: String = "idle"
var current_phase_label: String = ""

var _idle_frames: Array[Texture2D] = []
var _action_frames: Array[Texture2D] = []
var _idle_fps: float = 0.0
var _action_fps: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _cell_size: Vector2 = Vector2.ZERO
var _visible_height: float = 0.0
var _settle_seconds: float = 0.0
var _hold_seconds: float = 0.0
var _phases: Array = []
var _idle_atlas_paths: Array[String] = []
var _action_atlas_paths: Array[String] = []

var _frame_rect: TextureRect
var _idle_elapsed: float = 0.0
var _stage_elapsed: float = 0.0
var _action_duration: float = 0.0
var _settle_start_frame: int = 0
var _settle_target_frame: int = 0
var _stage: String = "idle"
var _anchor_local: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_rect = TextureRect.new()
	_frame_rect.name = "AtlasFrame"
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_rect)
	set_process(true)


func configure_idle(motion: Dictionary, assets: Dictionary) -> Dictionary:
	var frames := _texture_frames(assets.get("idle_frames", []))
	var fps := float(assets.get("idle_fps", 0.0))
	var anchor_value: Variant = assets.get("anchor", Vector2.ZERO)
	var size_value: Variant = assets.get("cell_size", Vector2.ZERO)
	var visible_height := float(assets.get("visible_height", 0.0))
	if frames.is_empty() or not is_finite(fps) or fps <= 0.0:
		return {"ok": false, "reason": "静息动作帧资料无效。"}
	if not anchor_value is Vector2 or not size_value is Vector2i:
		return {"ok": false, "reason": "动作锚点或格子尺寸无效。"}
	if not is_finite(visible_height) or visible_height <= 0.0:
		return {"ok": false, "reason": "动作可见高度无效。"}
	var cell_size_value := Vector2(size_value)
	if cell_size_value.x <= 0.0 or cell_size_value.y <= 0.0:
		return {"ok": false, "reason": "动作格子尺寸无效。"}
	var settle := float(assets.get("settle_seconds", motion.get("settle_seconds", -1.0)))
	var hold := float(assets.get("hold_seconds", motion.get("hold_seconds", -1.0)))
	if not is_finite(settle) or settle < 0.0 or not is_finite(hold) or hold < 0.0:
		return {"ok": false, "reason": "动作过渡时长无效。"}

	motion_id = str(assets.get("motion_id", motion.get("id", "")))
	_idle_frames = frames
	_idle_fps = fps
	_anchor = anchor_value
	_cell_size = cell_size_value
	_visible_height = visible_height
	_settle_seconds = minf(0.25, settle)
	_hold_seconds = hold
	_idle_atlas_paths = _string_paths(assets.get("idle_atlas_paths", []))
	if not is_instance_valid(_frame_rect):
		return {"ok": true}
	if not playing:
		_stage = "idle"
		_set_phase("idle", "静息")
		_set_idle_frame()
	return {"ok": true}


func set_scene_layout(surface_size: Vector2, x: float, y: float, height: float, flip: bool) -> void:
	if _visible_height <= 0.0 or _cell_size.x <= 0.0 or _cell_size.y <= 0.0:
		return
	var scale_value := height * surface_size.y / _visible_height
	var body_size := _cell_size * scale_value
	var foot := Vector2(clampf(x, 0.0, 1.0) * surface_size.x, clampf(y, 0.0, 1.0) * surface_size.y)
	var anchor_x := _cell_size.x - _anchor.x if flip else _anchor.x
	_anchor_local = Vector2(anchor_x, _anchor.y) * scale_value
	position = foot - _anchor_local
	size = body_size
	_frame_rect.position = Vector2.ZERO
	_frame_rect.size = body_size
	_frame_rect.flip_h = flip
	queue_redraw()


func play_presentation(presentation: Dictionary) -> Dictionary:
	var pending_assets: Variant = presentation.get("assets", {})
	if not pending_assets is Dictionary:
		return {"ok": false, "reason": "演练动作资源缺失。"}
	var assets: Dictionary = pending_assets
	var requested_motion := str(presentation.get("motion_id", ""))
	var requested_clip := str(presentation.get("clip_id", ""))
	if requested_motion.is_empty() or requested_motion != motion_id or requested_clip.is_empty():
		return {"ok": false, "reason": "演练动作与当前人物不匹配。"}
	var action_frames := _texture_frames(assets.get("action_frames", []))
	var action_fps := float(assets.get("action_fps", 0.0))
	var pending_idle := _texture_frames(assets.get("idle_frames", []))
	var pending_anchor: Variant = assets.get("anchor", Vector2.ZERO)
	var pending_cell: Variant = assets.get("cell_size", Vector2.ZERO)
	var pending_visible_height := float(assets.get("visible_height", 0.0))
	var settle := float(assets.get("settle_seconds", _settle_seconds))
	var hold := float(assets.get("hold_seconds", _hold_seconds))
	if action_frames.is_empty() or pending_idle.is_empty() or not is_finite(action_fps) or action_fps <= 0.0:
		return {"ok": false, "reason": "演练动作帧资料无效。"}
	if not pending_anchor is Vector2 or not pending_cell is Vector2i or not is_finite(pending_visible_height) or pending_visible_height <= 0.0:
		return {"ok": false, "reason": "演练动作锚点资料无效。"}
	if not is_finite(settle) or settle < 0.0 or not is_finite(hold) or hold < 0.0:
		return {"ok": false, "reason": "演练动作过渡时长无效。"}
	if playing and run_id == str(presentation.get("run_id", "")) and operation_id == str(presentation.get("operation_id", "")):
		return {"ok": true, "already_playing": true}

	_idle_frames = pending_idle
	_idle_fps = float(assets.get("idle_fps", _idle_fps))
	_action_frames = action_frames
	_action_fps = action_fps
	_anchor = pending_anchor
	_cell_size = Vector2(pending_cell)
	_visible_height = pending_visible_height
	_settle_seconds = minf(0.25, settle)
	_hold_seconds = hold
	_phases = assets.get("phases", []) if assets.get("phases", []) is Array else []
	_idle_atlas_paths = _string_paths(assets.get("idle_atlas_paths", _idle_atlas_paths))
	_action_atlas_paths = _string_paths(assets.get("action_atlas_paths", []))
	clip_id = requested_clip
	run_id = str(presentation.get("run_id", ""))
	operation_id = str(presentation.get("operation_id", ""))
	_action_duration = float(_action_frames.size()) / _action_fps
	_settle_start_frame = clampi(current_frame, 0, _idle_frames.size() - 1)
	var idle_midpoint := float(_idle_frames.size() - 1) * 0.5
	_settle_target_frame = 0 if float(_settle_start_frame) <= idle_midpoint else _idle_frames.size() - 1
	_stage_elapsed = 0.0
	_stage = "settle"
	playing = true
	neutral = false
	_set_phase("settle", "准备")
	_update_settle_frame()
	return {"ok": true}


func presentation_snapshot() -> Dictionary:
	return {
		"playing": playing,
		"neutral": neutral,
		"frame": current_frame,
		"phase": current_phase,
		"phase_label": current_phase_label,
		"motion_id": motion_id,
		"clip_id": clip_id,
		"run_id": run_id,
		"operation_id": operation_id,
		"loaded_action_atlas_paths": _action_atlas_paths.duplicate(),
		"loaded_idle_atlas_paths": _idle_atlas_paths.duplicate(),
		"idle_atlas_paths": _idle_atlas_paths.duplicate(),
	}


func _process(delta: float) -> void:
	if not playing:
		_idle_elapsed += delta
		_set_idle_frame()
		return
	_advance_playback(delta)


func _advance_playback(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while playing:
		if _stage == "settle":
			var settle_left := maxf(_settle_seconds - _stage_elapsed, 0.0)
			var settle_step := minf(remaining, settle_left)
			_stage_elapsed += settle_step
			remaining -= settle_step
			_update_settle_frame()
			if _stage_elapsed + 0.000001 < _settle_seconds:
				return
			_set_idle_frame_index(_settle_target_frame)
			_stage = "action"
			_stage_elapsed = 0.0
			_set_action_frame(0)
			_update_action_phase(0)
			if remaining <= 0.0:
				return
		elif _stage == "action":
			var action_left := maxf(_action_duration - _stage_elapsed, 0.0)
			var action_step := minf(remaining, action_left)
			_stage_elapsed += action_step
			remaining -= action_step
			var action_frame := mini(int(floor(_stage_elapsed * _action_fps)), _action_frames.size() - 1)
			_set_action_frame(action_frame)
			_update_action_phase(action_frame)
			if _stage_elapsed + 0.000001 < _action_duration:
				return
			_stage = "neutral_hold"
			_stage_elapsed = 0.0
			_idle_elapsed = 0.0
			_set_phase("neutral_hold", "回到静息")
			_set_idle_frame_index(0)
			if remaining <= 0.0:
				return
		elif _stage == "neutral_hold":
			var hold_left := maxf(_hold_seconds - _stage_elapsed, 0.0)
			var hold_step := minf(remaining, hold_left)
			_stage_elapsed += hold_step
			remaining -= hold_step
			_set_idle_frame_index(0)
			if _stage_elapsed + 0.000001 < _hold_seconds:
				return
			_complete_presentation()
			return
		else:
			_complete_presentation()
			return


func _complete_presentation() -> void:
	playing = false
	neutral = true
	_stage = "idle"
	_stage_elapsed = 0.0
	_idle_elapsed = 0.0
	_set_idle_frame_index(0)
	_set_phase("idle", "静息")
	finished.emit(run_id, operation_id)


func _set_idle_frame() -> void:
	if _idle_frames.is_empty() or _idle_fps <= 0.0 or not is_instance_valid(_frame_rect):
		return
	var frame_index := posmod(int(floor(_idle_elapsed * _idle_fps)), _idle_frames.size())
	_set_idle_frame_index(frame_index)


func _set_idle_frame_index(frame_index: int) -> void:
	if _idle_frames.is_empty() or not is_instance_valid(_frame_rect):
		return
	var safe_index := clampi(frame_index, 0, _idle_frames.size() - 1)
	current_frame = safe_index
	_frame_rect.texture = _idle_frames[safe_index]


func _update_settle_frame() -> void:
	if _idle_frames.is_empty():
		return
	var progress := 1.0 if _settle_seconds <= 0.0 else clampf(_stage_elapsed / _settle_seconds, 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var interpolated := lerpf(float(_settle_start_frame), float(_settle_target_frame), eased)
	_set_idle_frame_index(int(round(interpolated)))


func _set_action_frame(frame_index: int) -> void:
	if _action_frames.is_empty() or not is_instance_valid(_frame_rect):
		return
	var safe_index := clampi(frame_index, 0, _action_frames.size() - 1)
	current_frame = safe_index
	_frame_rect.texture = _action_frames[safe_index]


func _update_action_phase(frame_index: int) -> void:
	var best_start := -1
	var label := "演练"
	var frame_number := frame_index + 1
	for raw_phase in _phases:
		if not raw_phase is Dictionary:
			continue
		var phase_data: Dictionary = raw_phase as Dictionary
		var start_frame := int(phase_data.get("start_frame", -1))
		if start_frame <= frame_number and start_frame >= best_start:
			best_start = start_frame
			label = str(phase_data.get("label", label))
	_set_phase("action", label)


func _set_phase(phase: String, label: String) -> void:
	var changed := phase != current_phase or label != current_phase_label
	current_phase = phase
	current_phase_label = label
	if changed:
		phase_changed.emit(phase, label)


func _texture_frames(value: Variant) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if not value is Array:
		return result
	for raw_frame in value as Array:
		if raw_frame is Texture2D:
			result.append(raw_frame as Texture2D)
	return result


func _string_paths(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for raw_path in value as Array:
		var path := str(raw_path)
		if not path.is_empty():
			result.append(path)
	return result


func _draw() -> void:
	if _visible_height <= 0.0:
		return
	var points := PackedVector2Array()
	var radius_x := size.y * 0.18
	var radius_y := maxf(size.y * 0.024, 2.0)
	for index in range(28):
		var angle := TAU * float(index) / 28.0
		points.append(_anchor_local + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, SHADOW_COLOR)
