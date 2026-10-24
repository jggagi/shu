extends "res://scripts/back_mountain_training.gd"

const IDLE_MANIFEST := "res://assets/art/jiang_sword_cycle/idle/frames.json"
const ACTION_MANIFEST := "res://assets/art/jiang_sword_cycle/action/frames.json"
const SETS_CATALOG := "res://assets/art/jiang_sword_cycle/sets.json"
const CYCLE_FONT := "res://assets/fonts/ShuSwordCycleSerif.ttf"
const SETS_FONT := "res://assets/fonts/ShuSwordSetsSerif.ttf"
const CYCLE_FPS := 30.0
const IDLE_FRAME_COUNT := 60
const ACTION_FRAME_COUNT := 180
const CELL_SIZE := Vector2i(512, 512)
const ATLAS_COLUMNS := 5
const FRAMES_PER_ATLAS := 25
const FOOT_ANCHOR := Vector2(1010.0, 565.0)
const SOURCE_ANCHOR := Vector2(478.95962, 911.13357)
const RESIZED_ANCHOR := Vector2(245.22732544, 466.50038784)
const ACTOR_SCALE := 0.62
const SETTLE_SECONDS := 0.25
const IDLE_SECONDS := float(IDLE_FRAME_COUNT) / CYCLE_FPS
const ACTION_SECONDS := float(ACTION_FRAME_COUNT) / CYCLE_FPS
const TIME_OPTIONS := [
	{"id": "mao", "label": "卯时"},
	{"id": "chen", "label": "辰时"},
	{"id": "si", "label": "巳时"},
	{"id": "wu", "label": "午时"},
	{"id": "shen", "label": "申时"},
	{"id": "you", "label": "酉时"}
]
const WEATHER_OPTIONS := [
	{"id": "clear", "label": "晴"},
	{"id": "cloudy", "label": "多云"},
	{"id": "light_rain", "label": "小雨"}
]
const STATE_FIELDS := [
	"rules", "day", "time_index", "energy", "cultivation", "understanding", "lesson_bonus",
	"dialogue_open", "tea_accepted", "tea_seen", "tea_stage_complete", "tea_quest_complete",
	"tea_scene_id", "tea_c_seen", "tea_c_complete", "tea_action_done", "tea_active", "tea_session",
	"_tea_read_counter", "_tea_pending_object_id", "_tea_pending_read_token", "tea_story_stage",
	"tea_story_seen", "tea_story_page", "tea_story_object", "tea_story_token", "tea_ending_step",
	"_tea_ending_first_fill_msec", "_tea_story_source"
]

var _idle_frames: Array[Texture2D] = []
var _action_frames: Array[Texture2D] = []
var _loaded_action_atlas_paths: Array[String] = []
var _set_catalog_entries: Array = []
var _set_buttons: Array[Button] = []
var _sets_catalog_enabled := false
var _selected_set_index := -1
var _resized_anchor := RESIZED_ANCHOR
var _cycle_actor: Node2D
var _cycle_sprite: Sprite2D
var _contact_shadow: Sprite2D
var _practice_button: Button
var _speed_button: Button
var _time_button: Button
var _weather_button: Button
var _status_label: Label
var _header_status: Label
var _progress: ProgressBar
var _time_option_index := 3
var _weather_option_index := 0
var _playback_speed := 1.0
var _actor_state := "idle"
var _idle_elapsed := 0.0
var _settle_elapsed := 0.0
var _settle_from_frame := 0
var _settle_target_frame := 0
var _action_elapsed := 0.0
var _actor_clock := 0.0
var _cycle_count := 0
var _current_frame_index := 0
var _initial_state_snapshot := PackedByteArray()


func _ready() -> void:
	get_window().title = "后山 · 江砚秋练剑"
	_initial_state_snapshot = _state_snapshot()
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (config is Dictionary):
		config = {}
	if FileAccess.file_exists(SETS_CATALOG):
		if not _load_set_catalog():
			return
	_build_theme()
	_build_gust_schedule()
	_build_blink_schedule()
	var idle_atlas_paths: Array[String] = []
	if not _load_clip(IDLE_MANIFEST, IDLE_FRAME_COUNT, _idle_frames, idle_atlas_paths):
		return
	if _sets_catalog_enabled:
		if not _activate_set(0):
			return
	else:
		if not _load_clip(ACTION_MANIFEST, ACTION_FRAME_COUNT, _action_frames, _loaded_action_atlas_paths):
			return
	_build_scene()
	environment_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/back_mountain_environment.json"))
	if not (environment_config is Dictionary):
		push_error("Missing Back Mountain environment profile.")
		return
	environment_presenter.configure(environment_config)
	environment_adapter = EnvironmentAdapter.new()
	environment_adapter.name = "BackMountainEnvironment"
	add_child(environment_adapter)
	environment_adapter.setup(self)
	set_time("wu", false)
	set_weather("clear", false)
	_apply_environment()
	_sync_shader_times()
	_apply_actor_frame(0)
	_refresh_review_ui()
	_check_state_unchanged()


func _is_integral_catalog_number(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return is_finite(number) and floor(number) == number and number >= minimum and number <= maximum
	return false


func _load_set_catalog() -> bool:
	var raw := FileAccess.get_file_as_string(SETS_CATALOG)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary or not _is_integral_catalog_number(parsed.get("version", null), 1, 1):
		push_error("Invalid sword-set catalog: " + SETS_CATALOG)
		return false
	var entries: Variant = parsed.get("sets", null)
	if not entries is Array or entries.size() != 5:
		push_error("Sword-set catalog must contain exactly five sets: " + SETS_CATALOG)
		return false
	var seen_ids: Dictionary = {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			push_error("Malformed sword-set catalog entry.")
			return false
		var entry: Dictionary = entry_value
		var set_id := str(entry.get("id", ""))
		var label := str(entry.get("label", ""))
		var description := str(entry.get("description", ""))
		var manifest_path := str(entry.get("manifest_path", ""))
		if set_id.is_empty() or seen_ids.has(set_id) or label.strip_edges().is_empty() or description.strip_edges().is_empty() or not manifest_path.begins_with("res://"):
			push_error("Sword-set catalog has an invalid ID, label, description, or manifest path.")
			return false
		seen_ids[set_id] = true
		var phases: Variant = entry.get("phases", null)
		if not phases is Array or phases.is_empty():
			push_error("Sword-set catalog entries need ordered phase labels: " + set_id)
			return false
		var previous_start := 0
		for phase_value: Variant in phases:
			if not phase_value is Dictionary:
				push_error("Malformed phase in sword-set catalog: " + set_id)
				return false
			var phase: Dictionary = phase_value
			var start_value: Variant = phase.get("start_frame", null)
			var phase_label := str(phase.get("label", ""))
			if not _is_integral_catalog_number(start_value, 1, ACTION_FRAME_COUNT) or int(start_value) <= previous_start or phase_label.strip_edges().is_empty():
				push_error("Sword-set phases must have ordered frame starts and nonempty labels: " + set_id)
				return false
			previous_start = int(start_value)
		if int(phases[0].get("start_frame", 0)) != 1:
			push_error("Sword-set phases must start at frame 1: " + set_id)
			return false
	_set_catalog_entries = entries
	_sets_catalog_enabled = true
	return true


func _activate_set(index: int) -> bool:
	if index < 0 or index >= _set_catalog_entries.size():
		return false
	if index == _selected_set_index:
		_actor_state = "idle"
		busy = false
		_idle_elapsed = 0.0
		_settle_elapsed = 0.0
		_action_elapsed = 0.0
		_current_frame_index = 0
		_apply_actor_frame(0)
		_refresh_review_ui()
		return true
	var entry: Dictionary = _set_catalog_entries[index]
	var new_frames: Array[Texture2D] = []
	var new_atlas_paths: Array[String] = []
	if not _load_clip(str(entry.get("manifest_path", "")), ACTION_FRAME_COUNT, new_frames, new_atlas_paths):
		return false
	# Replacing the array releases this review's references to the previous action atlases.
	_action_frames = new_frames
	_loaded_action_atlas_paths = new_atlas_paths
	_selected_set_index = index
	_actor_state = "idle"
	busy = false
	_idle_elapsed = 0.0
	_settle_elapsed = 0.0
	_action_elapsed = 0.0
	_current_frame_index = 0
	_apply_actor_frame(0)
	_refresh_review_ui()
	return true


func _load_clip(path: String, expected_count: int, destination: Array[Texture2D], loaded_atlas_paths: Array[String]) -> bool:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_error("Missing sword-cycle frame manifest: " + path)
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_error("Invalid sword-cycle frame manifest: " + path)
		return false
	var manifest: Dictionary = parsed
	if int(manifest.get("frame_count", 0)) != expected_count or not is_equal_approx(float(manifest.get("fps", 0.0)), CYCLE_FPS):
		push_error("Sword-cycle clip must contain %d frames at 30 fps: %s" % [expected_count, path])
		return false
	var cell_values: Array = manifest.get("cell_size", [])
	if cell_values.size() != 2 or int(cell_values[0]) != CELL_SIZE.x or int(cell_values[1]) != CELL_SIZE.y:
		push_error("Sword-cycle atlas cells must be 512x512: " + path)
		return false
	var source_anchor_values: Array = manifest.get("anchor_source_px", [])
	var resized_anchor_values: Array = manifest.get("anchor_resized_px", [])
	if source_anchor_values.size() != 2 or resized_anchor_values.size() != 2:
		push_error("Sword-cycle manifest must carry both source and resized foot anchors: " + path)
		return false
	var source_anchor := Vector2(float(source_anchor_values[0]), float(source_anchor_values[1]))
	var resized_anchor := Vector2(float(resized_anchor_values[0]), float(resized_anchor_values[1]))
	if source_anchor.distance_to(SOURCE_ANCHOR) > 0.0001 or resized_anchor.distance_to(RESIZED_ANCHOR) > 0.0001:
		push_error("Sword-cycle clips must preserve the approved shared foot anchor: " + path)
		return false
	var frames: Array = manifest.get("frames", [])
	if frames.size() != expected_count:
		push_error("Sword-cycle frame list does not match its declared count: " + path)
		return false
	var atlas_cache: Dictionary = {}
	for entry_value: Variant in frames:
		if not entry_value is Dictionary:
			push_error("Malformed frame record in " + path)
			return false
		var entry: Dictionary = entry_value
		var atlas_path := str(entry.get("path", ""))
		var atlas: Texture2D = atlas_cache.get(atlas_path)
		if atlas == null:
			atlas = load(atlas_path) as Texture2D
			if atlas == null:
				push_error("Missing sword-cycle atlas: " + atlas_path)
				return false
			atlas_cache[atlas_path] = atlas
		if not loaded_atlas_paths.has(atlas_path):
			loaded_atlas_paths.append(atlas_path)
		var region_values: Array = entry.get("region", [])
		if region_values.size() != 4:
			push_error("Invalid atlas region in " + path)
			return false
		var region := Rect2(float(region_values[0]), float(region_values[1]), float(region_values[2]), float(region_values[3]))
		if region.size != Vector2(CELL_SIZE) or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region):
			push_error("Sword-cycle atlas regions must be contained 512x512 cells: " + atlas_path)
			return false
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = region
		frame.filter_clip = true
		destination.append(frame)
	return true


func _build_theme() -> void:
	var review_theme := Theme.new()
	review_theme.default_font = _load_review_font()
	review_theme.default_font_size = 20
	theme = review_theme


func _load_review_font() -> Font:
	var font_path := SETS_FONT if _sets_catalog_enabled else CYCLE_FONT
	var review_font := load(font_path) as Font
	if review_font == null and _sets_catalog_enabled:
		push_error("Missing sword-sets review font: " + SETS_FONT)
	return review_font


func _build_actor_and_sword() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.12, 0.17, 0.12, 0.34), Color(0.12, 0.17, 0.12, 0.20),
		Color(0.12, 0.17, 0.12, 0.065), Color(0.12, 0.17, 0.12, 0.0)
	])
	var shadow_texture := GradientTexture2D.new()
	shadow_texture.gradient = gradient
	shadow_texture.width = 256
	shadow_texture.height = 64
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	shadow_texture.fill_from = Vector2(0.5, 0.5)
	shadow_texture.fill_to = Vector2(1.0, 0.5)
	_contact_shadow = Sprite2D.new()
	_contact_shadow.name = "SwordCycleFootContact"
	_contact_shadow.texture = shadow_texture
	_contact_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_contact_shadow.position = FOOT_ANCHOR
	_contact_shadow.scale = Vector2(0.36, 0.28)
	_foreground_layer.add_child(_contact_shadow)
	_art_nodes.append(_contact_shadow)
	_cycle_actor = Node2D.new()
	_cycle_actor.name = "JiangSwordCycleActor"
	_cycle_actor.position = FOOT_ANCHOR
	_cycle_actor.scale = Vector2.ONE * ACTOR_SCALE
	_foreground_layer.add_child(_cycle_actor)
	_cycle_sprite = Sprite2D.new()
	_cycle_sprite.name = "JiangSwordCycleFrame"
	_cycle_sprite.centered = false
	_cycle_sprite.position = -_resized_anchor
	_cycle_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cycle_actor.add_child(_cycle_sprite)
	_art_nodes.append(_cycle_actor)


func _build_header() -> void:
	_add_panel(Rect2(0, 0, VIEW_SIZE.x, ART_TOP), PAPER, GOLD, 1)
	_add_line(Vector2(28, 81), Vector2(1412, 81), Color("cdbb99"), 1)
	_make_label("蜀山行记", Rect2(32, 7, 220, 40), 30, INK)
	_make_label("后山 · 江砚秋练剑", Rect2(35, 48, 275, 27), 17, MUTED)
	_header_status = _make_label("午时 · 晴 · 动态", Rect2(350, 20, 245, 40), 22, INK)
	_time_button = _make_button("更换时辰", Rect2(625, 22, 142, 40), _cycle_time)
	_weather_button = _make_button("更换天气", Rect2(780, 22, 142, 40), _cycle_weather)
	dynamic_button = _make_button("动态", Rect2(1000, 22, 142, 40), _toggle_review_dynamic, true)
	reset_button = _make_button("重置", Rect2(1242, 22, 160, 40), _reset_review_from_button)


func _build_footer() -> void:
	_add_panel(Rect2(0, FOOTER_TOP, VIEW_SIZE.x, VIEW_SIZE.y - FOOTER_TOP), PAPER, GOLD, 1)
	_add_line(Vector2(28, FOOTER_TOP + 11), Vector2(1412, FOOTER_TOP + 11), Color("cdbb99"), 1)
	if _sets_catalog_enabled:
		for index in _set_catalog_entries.size():
			var entry: Dictionary = _set_catalog_entries[index]
			var button := _make_button(str(entry.get("label", "")), Rect2(34 + 178 * index, 815, 168, 34), Callable(self, "select_set").bind(index))
			button.focus_mode = Control.FOCUS_NONE
			button.toggle_mode = true
			button.tooltip_text = str(entry.get("description", ""))
			_set_buttons.append(button)
		_status_label = _make_label("状态 · 待机", Rect2(34, 858, 400, 25), 17, INK)
		_progress = _make_bar(Rect2(460, 872, 250, 12), 1, Color("548d9a"))
		_practice_button = _make_button("练剑", Rect2(950, 815, 175, 34), practice, true)
		_speed_button = _make_button("正常速度", Rect2(1140, 815, 200, 34), _toggle_speed)
		_speed_button.focus_mode = Control.FOCUS_NONE
		_make_label("[ / ] 招式 · Space / 1 练剑 · T 时辰 · 7/8/9 天气 · 4 动静 · R 重置", Rect2(750, 858, 650, 25), 15, MUTED)
	else:
		_status_label = _make_label("状态 · 待机", Rect2(34, 818, 270, 32), 18, INK)
		_progress = _make_bar(Rect2(325, 827, 285, 12), 1, Color("548d9a"))
		_practice_button = _make_button("练剑", Rect2(665, 815, 175, 46), practice, true)
		_speed_button = _make_button("正常速度", Rect2(858, 815, 175, 46), _toggle_speed)
		_speed_button.focus_mode = Control.FOCUS_NONE
		_make_label("Space / 1 练剑 · T 时辰 · 7/8/9 天气 · 4 动静 · R 重置", Rect2(34, 858, 745, 25), 15, MUTED)


func _process(delta: float) -> void:
	if dynamic_enabled and not qa_motion_paused:
		presentation_time += delta
		environment_presenter.advance(delta)
		_update_parallax(delta)
		_update_leaf_art(presentation_time)
		_sync_shader_times()
		var actor_delta := delta * _playback_speed
		_actor_clock += actor_delta
		_advance_actor(actor_delta)
		_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()


func _advance_actor(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while remaining > 0.0 and _actor_state != "idle":
		if _actor_state == "settle":
			var settle_step := minf(remaining, SETTLE_SECONDS - _settle_elapsed)
			_settle_elapsed += settle_step
			remaining -= settle_step
			var weight := clampf(_settle_elapsed / SETTLE_SECONDS, 0.0, 1.0)
			var eased := weight * weight * (3.0 - 2.0 * weight)
			_current_frame_index = clampi(roundi(lerpf(float(_settle_from_frame), float(_settle_target_frame), eased)), 0, IDLE_FRAME_COUNT - 1)
			_apply_actor_frame(_current_frame_index)
			if _settle_elapsed >= SETTLE_SECONDS:
				_current_frame_index = _settle_target_frame
				_apply_actor_frame(_current_frame_index)
				_begin_action()
		elif _actor_state == "action":
			var action_step := minf(remaining, ACTION_SECONDS - _action_elapsed)
			_action_elapsed += action_step
			remaining -= action_step
			if _action_elapsed >= ACTION_SECONDS:
				_complete_action()
			else:
				_current_frame_index = mini(int(floor(_action_elapsed * CYCLE_FPS)), ACTION_FRAME_COUNT - 1)
				_apply_actor_frame(_current_frame_index)
	if _actor_state == "idle" and remaining > 0.0:
		_idle_elapsed = fposmod(_idle_elapsed + remaining, IDLE_SECONDS)
		_current_frame_index = mini(int(floor(_idle_elapsed * CYCLE_FPS)), IDLE_FRAME_COUNT - 1)
		_apply_actor_frame(_current_frame_index)


func practice() -> bool:
	if _actor_state != "idle" or busy or not dynamic_enabled:
		return false
	var idle_frame := _idle_frame_at_clock()
	if idle_frame == 0 or idle_frame == IDLE_FRAME_COUNT - 1:
		_current_frame_index = idle_frame
		_begin_action()
	else:
		_actor_state = "settle"
		busy = true
		_settle_elapsed = 0.0
		_settle_from_frame = idle_frame
		_settle_target_frame = 0 if idle_frame <= (IDLE_FRAME_COUNT - 1) / 2 else IDLE_FRAME_COUNT - 1
		_current_frame_index = idle_frame
		_apply_actor_frame(_current_frame_index)
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func select_set(index: int) -> bool:
	if not _sets_catalog_enabled or not dynamic_enabled or busy or _actor_state != "idle":
		return false
	if index < 0 or index >= _set_catalog_entries.size():
		return false
	var changed := _activate_set(index)
	if changed:
		_refresh_review_ui()
		_check_state_unchanged()
	return changed


func _begin_action() -> void:
	_actor_state = "action"
	busy = true
	_action_elapsed = 0.0
	_current_frame_index = 0
	_apply_actor_frame(0)


func _complete_action() -> void:
	_cycle_count += 1
	_actor_state = "idle"
	busy = false
	_action_elapsed = 0.0
	_settle_elapsed = 0.0
	_idle_elapsed = 0.0
	_current_frame_index = 0
	_apply_actor_frame(0)


func _idle_frame_at_clock() -> int:
	return mini(int(floor(_idle_elapsed * CYCLE_FPS)), IDLE_FRAME_COUNT - 1)


func _apply_actor_frame(index: int) -> void:
	if _cycle_sprite == null:
		return
	var frames := _action_frames if _actor_state == "action" else _idle_frames
	if frames.is_empty():
		return
	var bounded_index := clampi(index, 0, frames.size() - 1)
	_cycle_sprite.texture = frames[bounded_index]
	_cycle_sprite.position = -_resized_anchor


func set_dynamic(value: bool) -> void:
	dynamic_enabled = value
	_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()


func set_speed(value: float) -> bool:
	if is_equal_approx(value, 0.5):
		_playback_speed = 0.5
	elif is_equal_approx(value, 1.0):
		_playback_speed = 1.0
	else:
		return false
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func set_time(id: String, smooth: bool = true) -> bool:
	var matched_index := -1
	for index in TIME_OPTIONS.size():
		if str(TIME_OPTIONS[index].id) == id:
			matched_index = index
			break
	if matched_index < 0 or not environment_presenter.set_time_profile(id, smooth and dynamic_enabled):
		return false
	_time_option_index = matched_index
	_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()
	return true


func set_weather(id: String, smooth: bool = true) -> bool:
	var matched_index := -1
	for index in WEATHER_OPTIONS.size():
		if str(WEATHER_OPTIONS[index].id) == id:
			matched_index = index
			break
	if matched_index < 0 or not environment_presenter.set_weather(id, smooth and dynamic_enabled):
		return false
	_weather_option_index = matched_index
	_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()
	return true


func reset_review() -> bool:
	if _sets_catalog_enabled and _selected_set_index != 0:
		if not _activate_set(0):
			return false
	dynamic_enabled = true
	qa_motion_paused = false
	presentation_time = 0.0
	_playback_speed = 1.0
	_actor_state = "idle"
	busy = false
	_idle_elapsed = 0.0
	_settle_elapsed = 0.0
	_action_elapsed = 0.0
	_actor_clock = 0.0
	_cycle_count = 0
	_current_frame_index = 0
	_cycle_sprite.position = -_resized_anchor
	_cycle_sprite.scale = Vector2.ONE
	_cycle_sprite.rotation = 0.0
	_cycle_sprite.self_modulate = Color.WHITE
	for layer in _parallax_layers:
		layer.position = Vector2.ZERO
	if environment_presenter.night_preview:
		environment_presenter.set_night_preview(false, false)
	set_time("wu", false)
	set_weather("clear", false)
	environment_presenter.finish_transition()
	_sync_shader_times()
	_update_leaf_art(0.0)
	_apply_actor_frame(0)
	_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()
	return true


func seek_action_frame(index: int) -> bool:
	if index < 0 or index >= ACTION_FRAME_COUNT:
		return false
	qa_motion_paused = true
	_actor_state = "action"
	busy = true
	_action_elapsed = float(index) / CYCLE_FPS
	_settle_elapsed = 0.0
	_current_frame_index = index
	_apply_actor_frame(index)
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func qa_state() -> Dictionary:
	var clip_name := "action" if _actor_state == "action" else "idle"
	var frame_count := ACTION_FRAME_COUNT if clip_name == "action" else IDLE_FRAME_COUNT
	var duration := ACTION_SECONDS if clip_name == "action" else IDLE_SECONDS
	var phase := _phase_name()
	return {
		"clip_name": clip_name,
		"frame_index": _current_frame_index,
		"frame_number": _current_frame_index + 1,
		"phase": phase,
		"cycle_count": _cycle_count,
		"busy": busy,
		"actor_state": _actor_state,
		"actor_clock": _actor_clock,
		"idle_time_seconds": _idle_elapsed,
		"settle_time_seconds": _settle_elapsed,
		"action_time_seconds": _action_elapsed,
		"playback_speed": _playback_speed,
		"dynamic_enabled": dynamic_enabled,
		"qa_motion_paused": qa_motion_paused,
		"time_profile_id": str(TIME_OPTIONS[_time_option_index].id),
		"weather_id": str(WEATHER_OPTIONS[_weather_option_index].id),
		"selected_set_id": str(_set_catalog_entries[_selected_set_index].get("id", "")) if _sets_catalog_enabled and _selected_set_index >= 0 else "",
		"selected_set_index": _selected_set_index if _sets_catalog_enabled else 0,
		"set_count": _set_catalog_entries.size() if _sets_catalog_enabled else 0,
		"loaded_action_atlas_pages": _loaded_action_atlas_paths.size(),
		"presentation_time": presentation_time,
		"scene_foot_anchor": [FOOT_ANCHOR.x, FOOT_ANCHOR.y],
		"source_anchor_resized_px": [_resized_anchor.x, _resized_anchor.y],
		"actor_scale": ACTOR_SCALE,
		"frame_count": frame_count,
		"duration_seconds": duration,
		"state_unchanged": _initial_state_snapshot == _state_snapshot()
	}


func _phase_name() -> String:
	if _actor_state == "idle":
		return "待机"
	if _actor_state == "settle":
		return "起势"
	var action_frame := _current_frame_index
	if _sets_catalog_enabled and _selected_set_index >= 0:
		var phases: Array = _set_catalog_entries[_selected_set_index].get("phases", [])
		var active_label := str(phases[0].get("label", ""))
		for phase_value: Variant in phases:
			var phase: Dictionary = phase_value
			if action_frame + 1 < int(phase.get("start_frame", 1)):
				break
			active_label = str(phase.get("label", active_label))
		return active_label
	if action_frame < 44:
		return "起势"
	if action_frame < 60:
		return "出剑"
	if action_frame < 102:
		return "收势"
	return "回位"


func _refresh_review_ui() -> void:
	if _status_label == null:
		return
	var phase_text := "状态 · " + _phase_name()
	if _sets_catalog_enabled and _selected_set_index >= 0:
		phase_text = str(_set_catalog_entries[_selected_set_index].get("label", "")) + " · " + _phase_name()
	if _status_label.text != phase_text:
		_status_label.text = phase_text
	_header_status.text = "%s · %s · %s" % [str(TIME_OPTIONS[_time_option_index].label), str(WEATHER_OPTIONS[_weather_option_index].label), "动态" if dynamic_enabled else "静态"]
	dynamic_button.text = "动态" if dynamic_enabled else "静态"
	_speed_button.text = "半速" if _playback_speed < 1.0 else "正常速度"
	_practice_button.disabled = busy or not dynamic_enabled
	for index in _set_buttons.size():
		var set_button := _set_buttons[index]
		set_button.button_pressed = index == _selected_set_index
		set_button.disabled = busy or not dynamic_enabled or _actor_state != "idle"
	reset_button.disabled = false
	var max_value := float(IDLE_FRAME_COUNT - 1)
	var progress_value := float(_current_frame_index)
	if _actor_state == "settle":
		max_value = SETTLE_SECONDS
		progress_value = _settle_elapsed
	elif _actor_state == "action":
		max_value = ACTION_SECONDS
		progress_value = _action_elapsed
	_progress.max_value = max_value
	_progress.value = progress_value


func _toggle_speed() -> void:
	set_speed(0.5 if _playback_speed >= 1.0 else 1.0)


func _cycle_time() -> void:
	var next_index := (_time_option_index + 1) % TIME_OPTIONS.size()
	set_time(str(TIME_OPTIONS[next_index].id), true)


func _cycle_weather() -> void:
	var next_index := (_weather_option_index + 1) % WEATHER_OPTIONS.size()
	set_weather(str(WEATHER_OPTIONS[next_index].id), true)


func _toggle_review_dynamic() -> void:
	set_dynamic(not dynamic_enabled)


func _reset_review_from_button() -> void:
	reset_review()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE, KEY_1:
			practice()
		KEY_4:
			set_dynamic(not dynamic_enabled)
		KEY_R:
			reset_review()
		KEY_T:
			_cycle_time()
		KEY_7:
			set_weather("clear")
		KEY_8:
			set_weather("cloudy")
		KEY_9:
			set_weather("light_rain")
		KEY_BRACKETLEFT:
			if _sets_catalog_enabled:
				select_set((_selected_set_index + _set_catalog_entries.size() - 1) % _set_catalog_entries.size())
			else:
				return
		KEY_BRACKETRIGHT:
			if _sets_catalog_enabled:
				select_set((_selected_set_index + 1) % _set_catalog_entries.size())
			else:
				return
		_:
			return
	get_viewport().set_input_as_handled()


func _state_snapshot() -> PackedByteArray:
	var fields: Dictionary = {}
	for field_name: String in STATE_FIELDS:
		fields[field_name] = state.get(field_name)
	return var_to_bytes(fields)


func _check_state_unchanged() -> void:
	if _initial_state_snapshot.is_empty():
		return
	if _state_snapshot() != _initial_state_snapshot:
		push_error("Sword-cycle review must not mutate DemoState.")
