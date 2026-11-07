extends Control
## Painted portrait practice, not five newly illustrated sword animations.
## The host still owns costs, rewards, busy phases and completion identity.

signal phase_changed(phase: String, label: String)
signal finished(run_id: String, operation_id: String)

const TEXTURE_PATH := "res://assets/art/back_mountain_training/actor-sheet.png"
const SHEET_SIZE := Vector2i(1774, 887)
const CELL_SIZE := Vector2i(887, 887)
const PAINTED_ANCHOR := Vector2(492.0, 872.0)
const VISIBLE_HEIGHT := 856.0
const CLOCK_EPSILON := 0.000001

var playing := false
var neutral := true
var motion_id := ""
var clip_id := ""
var run_id := ""
var operation_id := ""
var current_frame := 0
var current_phase := "idle"
var current_phase_label := "静息"
var last_error := ""

var _prepared := false
var _sheet: Texture2D
var _open_texture: AtlasTexture
var _closed_texture: AtlasTexture
var _frame_rect: TextureRect
var _anchor_local := Vector2.ZERO
var _settle_seconds := 0.0
var _hold_seconds := 0.0
var _action_duration := 0.0
var _action_frame_count := 0
var _action_fps := 0.0
var _stage := "idle"
var _stage_elapsed := 0.0
var _breath_elapsed := 0.0
var _completed_operations: Dictionary = {}
var _completion_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_frame_rect()
	set_process(true)
	_update_visual()


func configure_idle(motion: Dictionary, assets: Dictionary) -> Dictionary:
	if playing:
		return _failure("当前原画修习尚未结束，不能重新配置人物。")
	_prepared = false
	var requested_motion: Variant = assets.get("motion_id")
	if not requested_motion is String or str(requested_motion).is_empty():
		return _failure("原画修习缺少已登记的动作身份。")
	var settle_value: Variant = assets.get("settle_seconds", motion.get("settle_seconds"))
	var hold_value: Variant = assets.get("hold_seconds", motion.get("hold_seconds"))
	if not _valid_duration(settle_value, 2.0) or not _valid_duration(hold_value, 5.0):
		return _failure("原画修习的准备或收息时长无效。")
	if not ResourceLoader.exists(TEXTURE_PATH, "Texture2D"):
		return _failure("缺少后山配套的2D原画人像。")
	var loaded: Resource = ResourceLoader.load(TEXTURE_PATH, "Texture2D")
	if not loaded is Texture2D:
		return _failure("后山2D原画人像无法载入。")
	var texture := loaded as Texture2D
	if Vector2i(texture.get_size()) != SHEET_SIZE:
		return _failure("后山原画人像须为1774×887的双格图。")
	var image: Image = texture.get_image()
	if image == null or image.is_empty() or image.get_size() != SHEET_SIZE:
		return _failure("后山原画人像无法读取真实图像。")
	if image.is_compressed() and image.decompress() != OK:
		return _failure("后山原画人像无法检查透明度。")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for index: int in range(2):
		var region := Rect2i(index * CELL_SIZE.x, 0, CELL_SIZE.x, CELL_SIZE.y)
		var cell: Image = image.get_region(region)
		if cell.is_empty() or cell.get_size() != CELL_SIZE or cell.get_used_rect().size == Vector2i.ZERO:
			return _failure("后山原画的睁眼或闭眼人像为空。")
		if cell.detect_alpha() == Image.ALPHA_NONE:
			return _failure("后山原画人像缺少真实透明背景。")
		if cell.get_pixel(0, 0).a > 0.01 or cell.get_pixel(CELL_SIZE.x - 1, 0).a > 0.01:
			return _failure("后山原画人像的透明留边无效。")
	var open_texture := AtlasTexture.new()
	open_texture.atlas = texture
	open_texture.region = Rect2(0, 0, CELL_SIZE.x, CELL_SIZE.y)
	open_texture.filter_clip = true
	var closed_texture := AtlasTexture.new()
	closed_texture.atlas = texture
	closed_texture.region = Rect2(CELL_SIZE.x, 0, CELL_SIZE.x, CELL_SIZE.y)
	closed_texture.filter_clip = true
	if motion_id != str(requested_motion):
		_completed_operations.clear()
		run_id = ""
		operation_id = ""
		clip_id = ""
	motion_id = str(requested_motion)
	_sheet = texture
	_open_texture = open_texture
	_closed_texture = closed_texture
	_settle_seconds = minf(0.25, float(settle_value))
	_hold_seconds = float(hold_value)
	_stage = "idle"
	_stage_elapsed = 0.0
	neutral = true
	_prepared = true
	last_error = ""
	_ensure_frame_rect()
	_set_phase("idle", "静息")
	_update_visual()
	return {"ok": true}


func is_prepared() -> bool:
	return _prepared and is_instance_valid(_sheet) and is_instance_valid(_open_texture) and is_instance_valid(_closed_texture) and not motion_id.is_empty()


func set_scene_layout(surface_size: Vector2, x: float, y: float, height: float, flip: bool) -> void:
	if not is_prepared() or not surface_size.is_finite() or surface_size.x <= 0.0 or surface_size.y <= 0.0:
		return
	if not is_finite(x) or not is_finite(y) or not is_finite(height) or height <= 0.0:
		return
	_ensure_frame_rect()
	var scale_value := height * surface_size.y / VISIBLE_HEIGHT
	if not is_finite(scale_value) or scale_value <= 0.0:
		return
	var body_size := Vector2(CELL_SIZE) * scale_value
	var foot := Vector2(clampf(x, 0.0, 1.0) * surface_size.x, clampf(y, 0.0, 1.0) * surface_size.y)
	var anchor_x := float(CELL_SIZE.x) - PAINTED_ANCHOR.x if flip else PAINTED_ANCHOR.x
	_anchor_local = Vector2(anchor_x, PAINTED_ANCHOR.y) * scale_value
	position = foot - _anchor_local
	size = body_size
	_frame_rect.position = Vector2.ZERO
	_frame_rect.size = body_size
	_frame_rect.pivot_offset = _anchor_local
	_frame_rect.flip_h = flip
	_update_visual()


func play_presentation(presentation: Dictionary) -> Dictionary:
	if not is_prepared():
		return _failure("后山2D原画人物尚未准备好。")
	var requested_motion: Variant = presentation.get("motion_id")
	var requested_clip: Variant = presentation.get("clip_id")
	var requested_run: Variant = presentation.get("run_id")
	var requested_operation: Variant = presentation.get("operation_id")
	if not requested_motion is String or str(requested_motion) != motion_id or not requested_clip is String or str(requested_clip).is_empty():
		return _failure("原画修习与当前人物动作身份不匹配。")
	if not requested_run is String or str(requested_run).is_empty() or not requested_operation is String or str(requested_operation).is_empty():
		return _failure("原画修习缺少真实的开局或行动身份。")
	var identity := JSON.stringify([requested_run, requested_operation])
	if playing:
		if run_id == str(requested_run) and operation_id == str(requested_operation) and clip_id == str(requested_clip):
			return {"ok": true, "already_playing": true}
		return _failure("当前原画修习尚未收息，不能开始另一行动。")
	if _completed_operations.has(identity):
		if str(_completed_operations[identity]) != str(requested_clip):
			return _failure("这个行动身份已经用于另一段修习。")
		return {"ok": true, "already_completed": true}
	var assets_value: Variant = presentation.get("assets")
	if not assets_value is Dictionary:
		return _failure("原画修习缺少原行动的时序资料。")
	var assets: Dictionary = assets_value
	var frames_value: Variant = assets.get("action_frames")
	var fps_value: Variant = assets.get("action_fps")
	var settle_value: Variant = assets.get("settle_seconds", _settle_seconds)
	var hold_value: Variant = assets.get("hold_seconds", _hold_seconds)
	if not frames_value is Array or frames_value.is_empty() or not _finite_number(fps_value) or float(fps_value) <= 0.0:
		return _failure("原行动的修习帧数或时长无效。")
	if not _valid_duration(settle_value, 2.0) or not _valid_duration(hold_value, 5.0):
		return _failure("原行动的准备或收息时长无效。")
	# Read only the original timing. Never retain, draw or copy its model frames.
	var frame_count: int = frames_value.size()
	var fps := float(fps_value)
	var duration := float(frame_count) / fps
	if not is_finite(duration) or duration <= 0.0 or duration > 120.0:
		return _failure("原行动的修习时长超出有效范围。")
	_action_frame_count = frame_count
	_action_fps = fps
	_action_duration = duration
	_settle_seconds = minf(0.25, float(settle_value))
	_hold_seconds = float(hold_value)
	clip_id = str(requested_clip)
	run_id = str(requested_run)
	operation_id = str(requested_operation)
	_stage = "settle"
	_stage_elapsed = 0.0
	_breath_elapsed = 0.0
	playing = true
	neutral = false
	last_error = ""
	_set_phase("settle", "准备")
	_update_visual()
	return {"ok": true}


func presentation_snapshot() -> Dictionary:
	var paths: Array[String] = []
	if is_prepared():
		paths.append(TEXTURE_PATH)
	return {
		"route": "painted_2d_portrait",
		"texture_path": TEXTURE_PATH,
		"prepared": is_prepared(),
		"playing": playing,
		"neutral": neutral,
		"frame": current_frame,
		"phase": current_phase,
		"phase_label": current_phase_label,
		"motion_id": motion_id,
		"clip_id": clip_id,
		"run_id": run_id,
		"operation_id": operation_id,
		"loaded_action_atlas_paths": paths.duplicate(),
		"loaded_idle_atlas_paths": paths.duplicate(),
		"idle_atlas_paths": paths.duplicate(),
		"action_duration": _action_duration,
		"source_frame_count": _action_frame_count,
		"source_fps": _action_fps,
		"settle_seconds": _settle_seconds,
		"hold_seconds": _hold_seconds,
		"stage_elapsed": _stage_elapsed,
		"anchor": PAINTED_ANCHOR,
		"cell_size": CELL_SIZE,
		"completion_count": _completion_count,
		"description": "后山配套2D原画人像练功示意；未新增五套2D挥剑动画。",
	}


func _process(delta: float) -> void:
	if not is_prepared() or not is_finite(delta) or delta < 0.0:
		return
	_breath_elapsed += delta
	if playing:
		_advance_playback(delta)
	_update_visual()


func _advance_playback(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while playing:
		var duration := _settle_seconds if _stage == "settle" else (_action_duration if _stage == "action" else _hold_seconds)
		var step := minf(remaining, maxf(duration - _stage_elapsed, 0.0))
		_stage_elapsed += step
		remaining -= step
		if _stage_elapsed + CLOCK_EPSILON < duration:
			return
		_stage_elapsed = 0.0
		if _stage == "settle":
			_stage = "action"
			_set_phase("action", "修习")
		elif _stage == "action":
			_stage = "neutral_hold"
			_set_phase("neutral_hold", "收息")
		else:
			_complete_presentation()
			return
		var next_duration := _action_duration if _stage == "action" else _hold_seconds
		if remaining <= 0.0 and next_duration > 0.0:
			_update_visual()
			return


func _complete_presentation() -> void:
	var completed_run := run_id
	var completed_operation := operation_id
	_completed_operations[JSON.stringify([completed_run, completed_operation])] = clip_id
	_completion_count += 1
	playing = false
	neutral = true
	_stage = "idle"
	_stage_elapsed = 0.0
	_breath_elapsed = 0.0
	_set_phase("idle", "静息")
	_update_visual()
	finished.emit(completed_run, completed_operation)


func _ensure_frame_rect() -> void:
	if is_instance_valid(_frame_rect):
		return
	_frame_rect = TextureRect.new()
	_frame_rect.name = "PaintedPortraitFrame"
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_rect)


func _update_visual() -> void:
	if not is_prepared() or not is_instance_valid(_frame_rect):
		return
	var closed := playing and _stage == "action"
	if not playing:
		closed = fmod(_breath_elapsed, 5.4) >= 5.28
	current_frame = 1 if closed else 0
	_frame_rect.texture = _closed_texture if closed else _open_texture
	var breath := sin(_breath_elapsed * TAU / 4.8) * 0.0025
	_frame_rect.scale = Vector2(1.0 - breath * 0.25, 1.0 + breath)


func _set_phase(phase: String, label: String) -> void:
	var changed := current_phase != phase or current_phase_label != label
	current_phase = phase
	current_phase_label = label
	if changed:
		phase_changed.emit(phase, label)


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _valid_duration(value: Variant, maximum: float) -> bool:
	return _finite_number(value) and float(value) >= 0.0 and float(value) <= maximum


func _failure(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason}
