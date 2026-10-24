extends "res://scripts/back_mountain_training.gd"

const OLD_MANIFEST := "res://assets/art/jiang_turn_review/old/manifest.json"
const REFINED_MANIFEST := "res://assets/art/jiang_turn_review/refined/manifest.json"
const REVIEW_FONT := "res://assets/fonts/ShuTurnReviewSerif.ttf"
const REVIEW_FPS := 30.0
var REVIEW_FRAME_COUNT := 0
var REVIEW_DURATION := 0.0
const REVIEW_CELL_SIZE := Vector2i(512, 512)
const REVIEW_COLUMNS := 5
const REVIEW_FRAMES_PER_ATLAS := 25
const REVIEW_FOOT_ANCHOR := Vector2(1010.0, 565.0)
const REVIEW_ACTOR_SCALE := 0.62
const REVIEW_SHADOW_SCALE := Vector2(0.36, 0.28)
const STATE_FIELDS := [
	"rules", "day", "time_index", "energy", "cultivation", "understanding", "lesson_bonus",
	"dialogue_open", "tea_accepted", "tea_seen", "tea_stage_complete", "tea_quest_complete",
	"tea_scene_id", "tea_c_seen", "tea_c_complete", "tea_action_done", "tea_active", "tea_session",
	"_tea_read_counter", "_tea_pending_object_id", "_tea_pending_read_token", "tea_story_stage",
	"tea_story_seen", "tea_story_page", "tea_story_object", "tea_story_token", "tea_ending_step",
	"_tea_ending_first_fill_msec", "_tea_story_source"
]
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

var _old_frames: Array[Texture2D] = []
var _refined_frames: Array[Texture2D] = []
var _resized_anchor := Vector2.ZERO
var _anchor_loaded := false
var _review_actor: Node2D
var _review_sprite: Sprite2D
var _contact_shadow: Sprite2D
var _active_variant := 1
var _frame_index := 0
var _clip_seconds := 0.0
var _playback_speed := 1.0
var _clip_paused := true
var _time_option_index := 2
var _weather_option_index := 1
var _updating_timeline := false
var _initial_state_snapshot := PackedByteArray()
var _old_button: Button
var _refined_button: Button
var _play_button: Button
var _replay_button: Button
var _speed_button: Button
var _time_button: Button
var _weather_button: Button
var _timeline: HSlider
var _phase_label: Label


func _ready() -> void:
	get_window().title = "后山 · 持剑动作与色调"
	_initial_state_snapshot = _state_snapshot()
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (config is Dictionary):
		config = {}
	_build_theme()
	_build_gust_schedule()
	_build_blink_schedule()
	if not _load_variant(OLD_MANIFEST, _old_frames):
		return
	if not _load_variant(REFINED_MANIFEST, _refined_frames):
		return
	_build_scene()
	environment_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/back_mountain_environment.json"))
	environment_presenter.configure(environment_config)
	environment_adapter = EnvironmentAdapter.new()
	environment_adapter.name = "BackMountainEnvironment"
	add_child(environment_adapter)
	environment_adapter.setup(self)
	environment_presenter.set_time_profile("si", false)
	environment_presenter.set_weather("cloudy", false)
	_apply_environment()
	_sync_shader_times()
	_refresh_review_frame()
	_refresh_review_ui()
	_check_state_unchanged()


func _load_variant(manifest_path: String, destination: Array[Texture2D]) -> bool:
	var raw := FileAccess.get_file_as_string(manifest_path)
	if raw.is_empty():
		push_error("Missing turn-review manifest: " + manifest_path)
		return false
	var manifest: Variant = JSON.parse_string(raw)
	if not manifest is Dictionary:
		push_error("Invalid turn-review manifest: " + manifest_path)
		return false
	var manifest_frame_count := int(manifest.get("frame_count", 0))
	if (manifest_frame_count != 60 and manifest_frame_count != 120) or not is_equal_approx(float(manifest.get("fps", 0.0)), REVIEW_FPS):
		push_error("Turn-review manifest must contain 60 or 120 frames at 30 fps: " + manifest_path)
		return false
	if REVIEW_FRAME_COUNT == 0:
		REVIEW_FRAME_COUNT = manifest_frame_count
		REVIEW_DURATION = float(REVIEW_FRAME_COUNT) / REVIEW_FPS
	elif manifest_frame_count != REVIEW_FRAME_COUNT:
		push_error("Both turn-review variants must have the same frame count.")
		return false
	var cell_size: Array = manifest.get("cell_size", [])
	if cell_size.size() != 2 or int(cell_size[0]) != REVIEW_CELL_SIZE.x or int(cell_size[1]) != REVIEW_CELL_SIZE.y:
		push_error("Turn-review atlas cells must be 512x512: " + manifest_path)
		return false
	var anchor: Array = manifest.get("anchor_resized_px", [])
	if anchor.size() != 2:
		push_error("Turn-review manifest has no resized anchor: " + manifest_path)
		return false
	var candidate_anchor := Vector2(float(anchor[0]), float(anchor[1]))
	if not _anchor_loaded:
		_resized_anchor = candidate_anchor
		_anchor_loaded = true
	elif candidate_anchor != _resized_anchor:
		push_error("Both turn-review variants must share the same anchor.")
		return false
	var atlas_cache: Dictionary = {}
	var entries: Array = manifest.get("frames", [])
	if entries.size() != REVIEW_FRAME_COUNT:
		push_error("Turn-review manifest frame list does not match its declared frame count: " + manifest_path)
		return false
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			push_error("Malformed frame entry in " + manifest_path)
			return false
		var entry: Dictionary = entry_value
		var atlas_path := str(entry.get("path", ""))
		var atlas: Texture2D = atlas_cache.get(atlas_path)
		if atlas == null:
			atlas = load(atlas_path) as Texture2D
			if atlas == null:
				push_error("Missing turn-review atlas: " + atlas_path)
				return false
			atlas_cache[atlas_path] = atlas
		var region_values: Array = entry.get("region", [])
		if region_values.size() != 4:
			push_error("Invalid atlas region for frame in " + manifest_path)
			return false
		var region := Rect2(float(region_values[0]), float(region_values[1]), float(region_values[2]), float(region_values[3]))
		if region.size != Vector2(REVIEW_CELL_SIZE.x, REVIEW_CELL_SIZE.y) or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region):
			push_error("Atlas region must be a contained 512x512 cell: " + atlas_path)
			return false
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = region
		frame.filter_clip = true
		destination.append(frame)
	return true


func _build_theme() -> void:
	var review_theme := Theme.new()
	review_theme.default_font = load(REVIEW_FONT)
	review_theme.default_font_size = 20
	theme = review_theme


func _build_actor_and_sword() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.12, 0.17, 0.12, 0.34),
		Color(0.12, 0.17, 0.12, 0.20),
		Color(0.12, 0.17, 0.12, 0.065),
		Color(0.12, 0.17, 0.12, 0.0)
	])
	var shadow_texture := GradientTexture2D.new()
	shadow_texture.gradient = gradient
	shadow_texture.width = 256
	shadow_texture.height = 64
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	shadow_texture.fill_from = Vector2(0.5, 0.5)
	shadow_texture.fill_to = Vector2(1.0, 0.5)
	_contact_shadow = Sprite2D.new()
	_contact_shadow.name = "TurnReviewFootContact"
	_contact_shadow.texture = shadow_texture
	_contact_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_contact_shadow.position = REVIEW_FOOT_ANCHOR
	_contact_shadow.scale = REVIEW_SHADOW_SCALE
	_foreground_layer.add_child(_contact_shadow)
	_art_nodes.append(_contact_shadow)

	_review_actor = Node2D.new()
	_review_actor.name = "JiangTurnReviewActor"
	_review_actor.position = REVIEW_FOOT_ANCHOR
	_review_actor.scale = Vector2.ONE * REVIEW_ACTOR_SCALE
	_foreground_layer.add_child(_review_actor)
	_review_sprite = Sprite2D.new()
	_review_sprite.name = "TurnReviewFrame"
	_review_sprite.centered = false
	_review_sprite.position = -_resized_anchor
	_review_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_review_actor.add_child(_review_sprite)
	_art_nodes.append(_review_actor)


func _build_header() -> void:
	_add_panel(Rect2(0, 0, VIEW_SIZE.x, ART_TOP), PAPER, GOLD, 1)
	_add_line(Vector2(24, 81), Vector2(1416, 81), Color("cdbb99"), 1)
	_make_label("后山 · 持剑动作与色调", Rect2(24, 7, 340, 39), 27, INK)
	_make_label("江砚秋 · 原色／暖色", Rect2(26, 47, 330, 24), 16, MUTED)
	_old_button = _make_button("原色", Rect2(378, 23, 140, 42), _select_old)
	_refined_button = _make_button("暖色", Rect2(528, 23, 140, 42), _select_refined, true)
	_time_button = _make_button("巳时", Rect2(695, 23, 130, 42), _cycle_time)
	_weather_button = _make_button("多云", Rect2(840, 23, 145, 42), _cycle_weather)
	dynamic_button = _make_button("动态", Rect2(1000, 23, 155, 42), _toggle_review_dynamic, true)
	_make_label("A/B 同帧 · 4 静态", Rect2(1170, 26, 226, 34), 16, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


func _build_footer() -> void:
	_add_panel(Rect2(0, FOOTER_TOP, VIEW_SIZE.x, VIEW_SIZE.y - FOOTER_TOP), PAPER, GOLD, 1)
	_add_line(Vector2(24, FOOTER_TOP + 11), Vector2(1416, FOOTER_TOP + 11), Color("cdbb99"), 1)
	_phase_label = _make_label("第 1 / %d 帧 · 00.00 秒" % REVIEW_FRAME_COUNT, Rect2(28, 820, 198, 28), 16, INK)
	_timeline = HSlider.new()
	_timeline.min_value = 0
	_timeline.max_value = REVIEW_FRAME_COUNT - 1
	_timeline.step = 1
	_timeline.value = 0
	_timeline.value_changed.connect(_seek_from_timeline)
	_place(_timeline, Rect2(232, 824, 530, 26), self)
	_timeline.z_index = 19
	_play_button = _make_button("播放", Rect2(790, 817, 148, 42), _toggle_playback, true)
	_speed_button = _make_button("正常速度", Rect2(948, 817, 168, 42), _toggle_speed)
	_replay_button = _make_button("重播", Rect2(1126, 817, 132, 42), _replay_review)
	_make_label("空格 播放／暂停 · ← → 逐帧 · R 重播", Rect2(28, 859, 650, 25), 15, MUTED)
	_make_label("动态／静态会冻结整幅场景", Rect2(790, 859, 430, 25), 15, MUTED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _art_root != null:
		_art_pointer = _art_root.get_global_transform_with_canvas().affine_inverse() * event.position


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_toggle_playback()
		KEY_R:
			_replay_review()
		KEY_LEFT:
			_seek_relative(-1)
		KEY_RIGHT:
			_seek_relative(1)
		KEY_A:
			_select_old()
		KEY_B:
			_select_refined()
		KEY_4:
			set_dynamic(not dynamic_enabled)
		KEY_T:
			_cycle_time()
		KEY_7:
			_select_weather(0)
		KEY_8:
			_select_weather(1)
		KEY_9:
			_select_weather(2)
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if dynamic_enabled:
		presentation_time += delta
		environment_presenter.advance(delta)
		_update_parallax(delta)
		_update_leaf_art(presentation_time)
		_sync_shader_times()
		if not _clip_paused:
			_clip_seconds = minf(_clip_seconds + delta * _playback_speed, REVIEW_DURATION)
			var next_frame := mini(int(floor(_clip_seconds * REVIEW_FPS)), REVIEW_FRAME_COUNT - 1)
			if next_frame != _frame_index:
				_frame_index = next_frame
				_refresh_review_frame()
			if _clip_seconds >= REVIEW_DURATION:
				_clip_paused = true
	_apply_environment()
	_refresh_review_ui()
	_check_state_unchanged()


func set_dynamic(value: bool) -> void:
	dynamic_enabled = value
	if dynamic_enabled:
		_sync_shader_times()
	_refresh_review_ui()
	_apply_environment()
	_check_state_unchanged()


func _select_old() -> void:
	set_variant(0)


func _select_refined() -> void:
	set_variant(1)


func set_variant(value: Variant) -> bool:
	var index := -1
	if typeof(value) == TYPE_INT:
		index = int(value)
	elif typeof(value) == TYPE_STRING:
		match str(value).strip_edges().to_lower():
			"old", "v5":
				index = 0
			"refined", "improved":
				index = 1
	if index < 0 or index > 1:
		return false
	_active_variant = index
	_refresh_review_frame()
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func _active_frames() -> Array[Texture2D]:
	return _old_frames if _active_variant == 0 else _refined_frames


func _refresh_review_frame() -> void:
	if _review_sprite == null or _active_frames().is_empty():
		return
	_frame_index = clampi(_frame_index, 0, REVIEW_FRAME_COUNT - 1)
	_review_sprite.texture = _active_frames()[_frame_index]
	_review_sprite.position = -_resized_anchor


func _seek_from_timeline(value: float) -> void:
	if _updating_timeline:
		return
	_frame_index = clampi(int(round(value)), 0, REVIEW_FRAME_COUNT - 1)
	_clip_seconds = float(_frame_index) / REVIEW_FPS
	_clip_paused = true
	_refresh_review_frame()
	_refresh_review_ui()
	_check_state_unchanged()


func _seek_relative(offset: int) -> void:
	_frame_index = clampi(_frame_index + offset, 0, REVIEW_FRAME_COUNT - 1)
	_clip_seconds = float(_frame_index) / REVIEW_FPS
	_clip_paused = true
	_refresh_review_frame()
	_refresh_review_ui()
	_check_state_unchanged()


func _toggle_playback() -> void:
	set_playing(_clip_paused)


func set_playing(playing: bool) -> bool:
	if playing and not dynamic_enabled:
		return false
	if playing and _clip_paused and _clip_seconds >= REVIEW_DURATION:
		seek_frame(0)
	_clip_paused = not playing
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func _replay_review() -> void:
	if not dynamic_enabled:
		return
	seek_frame(0)
	set_playing(true)


func _toggle_speed() -> void:
	set_speed(0.5 if _playback_speed >= 1.0 else 1.0)


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


func seek_frame(index: int) -> void:
	_frame_index = clampi(index, 0, REVIEW_FRAME_COUNT - 1)
	_clip_seconds = float(_frame_index) / REVIEW_FPS
	_clip_paused = true
	_refresh_review_frame()
	_refresh_review_ui()
	_check_state_unchanged()


func _toggle_review_dynamic() -> void:
	set_dynamic(not dynamic_enabled)


func _cycle_time() -> void:
	_time_option_index = (_time_option_index + 1) % TIME_OPTIONS.size()
	var profile: Dictionary = TIME_OPTIONS[_time_option_index]
	set_time(str(profile.id), dynamic_enabled)


func _cycle_weather() -> void:
	_select_weather((_weather_option_index + 1) % WEATHER_OPTIONS.size())


func _select_weather(index: int) -> void:
	var bounded_index := clampi(index, 0, WEATHER_OPTIONS.size() - 1)
	var profile: Dictionary = WEATHER_OPTIONS[bounded_index]
	set_weather(str(profile.id), dynamic_enabled)


func set_time(id: String, smooth: bool = true) -> bool:
	var matched_index := -1
	for index in TIME_OPTIONS.size():
		if str(TIME_OPTIONS[index].id) == id:
			matched_index = index
			break
	if matched_index < 0:
		return false
	if not environment_presenter.set_time_profile(id, smooth and dynamic_enabled):
		return false
	_time_option_index = matched_index
	_apply_environment()
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func set_weather(id: String, smooth: bool = true) -> bool:
	var matched_index := -1
	for index in WEATHER_OPTIONS.size():
		if str(WEATHER_OPTIONS[index].id) == id:
			matched_index = index
			break
	if matched_index < 0:
		return false
	if not environment_presenter.set_weather(id, smooth and dynamic_enabled):
		return false
	_weather_option_index = matched_index
	_apply_environment()
	_refresh_review_ui()
	_check_state_unchanged()
	return true


func _refresh_review_ui() -> void:
	if _phase_label == null:
		return
	_phase_label.text = "第 %d / %d 帧 · %.2f 秒" % [_frame_index + 1, REVIEW_FRAME_COUNT, float(_frame_index) / REVIEW_FPS]
	_play_button.text = "播放" if _clip_paused else "暂停"
	_play_button.disabled = not dynamic_enabled
	_replay_button.disabled = not dynamic_enabled
	_speed_button.text = "半速" if _playback_speed < 1.0 else "正常速度"
	_time_button.text = str(TIME_OPTIONS[_time_option_index].label)
	_weather_button.text = str(WEATHER_OPTIONS[_weather_option_index].label)
	dynamic_button.text = "动态" if dynamic_enabled else "静态"
	_old_button.modulate = Color("b7d4bd") if _active_variant == 0 else Color.WHITE
	_refined_button.modulate = Color("b7d4bd") if _active_variant == 1 else Color.WHITE
	_updating_timeline = true
	_timeline.value = _frame_index
	_updating_timeline = false


func qa_state() -> Dictionary:
	return {
		"variant": "v5" if _active_variant == 0 else "refined",
		"variant_index": _active_variant,
		"frame_index": _frame_index,
		"frame_number": _frame_index + 1,
		"frame_time_seconds": float(_frame_index) / REVIEW_FPS,
		"clip_time_seconds": _clip_seconds,
		"playing": not _clip_paused,
		"playback_speed": _playback_speed,
		"dynamic_enabled": dynamic_enabled,
		"time_profile_id": str(TIME_OPTIONS[_time_option_index].id),
		"weather_id": str(WEATHER_OPTIONS[_weather_option_index].id),
		"presentation_time": presentation_time,
		"scene_foot_anchor": [REVIEW_FOOT_ANCHOR.x, REVIEW_FOOT_ANCHOR.y],
		"actor_scale": REVIEW_ACTOR_SCALE,
		"source_anchor_resized_px": [_resized_anchor.x, _resized_anchor.y],
		"demo_state_unchanged": _initial_state_snapshot == _state_snapshot(),
		"frame_count": REVIEW_FRAME_COUNT,
		"duration_seconds": REVIEW_DURATION
	}


func _state_snapshot() -> PackedByteArray:
	var fields: Dictionary = {}
	for field_name: String in STATE_FIELDS:
		fields[field_name] = state.get(field_name)
	return var_to_bytes(fields)


func _check_state_unchanged() -> void:
	if _initial_state_snapshot.is_empty():
		return
	if _state_snapshot() != _initial_state_snapshot:
		push_error("Turn scene review must not mutate DemoState.")
