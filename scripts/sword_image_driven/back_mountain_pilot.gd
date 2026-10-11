extends "res://scripts/back_mountain_training.gd"
# Research-only scene: reuse the painted world; replace the demo actor and controls.
const Clip = preload("res://scripts/sword_image_driven/clip_actor.gd")
const CLEAN_MANIFEST := "res://assets/art/sword_image_clean_matte_v1/atlas.json"
const PILOT_FONT := "res://assets/fonts/ShuSwordImageSerif.ttf"
var clip: Node2D
var play_button: Button
var replay_button: Button
var speed_button: Button
var weather_button: Button
var time_button: Button
var phase_label: Label
var timeline: HSlider
var matte_enabled := true
var matte_button: Button
var original_frames: Array[AtlasTexture] = []
var clean_frames: Array[AtlasTexture] = []
var paper_enabled := true
var paper_button: Button
var blend_enabled := true
var blend_button: Button
var blend_material: ShaderMaterial
var contact_shadow: Sprite2D
var legacy_contact_shadow: Polygon2D
var sample_time_index := 2
var _updating_timeline := false
var _resume_clip_after_static := false

func _ready() -> void:
	get_window().title = "江砚秋 · 后山转身挥剑"
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	_build_theme()
	_build_gust_schedule()
	_build_blink_schedule()
	_build_scene()
	_prepare_clean_matte()
	set_matte_cleanup(true)
	environment_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/back_mountain_environment.json"))
	environment_presenter.configure(environment_config)
	environment_adapter = EnvironmentAdapter.new()
	add_child(environment_adapter)
	environment_adapter.setup(self)
	environment_presenter.set_time_profile("si", false)
	environment_presenter.set_weather("cloudy", false)
	_apply_environment()
	_sync_shader_times()
	clip.completed.connect(_refresh_pilot_ui)
	set_scene_blending(true)
	set_paper_texture(true)
	_refresh_pilot_ui()

func _build_theme() -> void:
	var game_theme := Theme.new()
	game_theme.default_font = load(PILOT_FONT)
	game_theme.default_font_size = 20
	theme = game_theme

func _build_actor_and_sword() -> void:
	clip = Clip.new()
	clip.name = "JiangImageMotion"
	clip.position = Vector2(1010, 565)
	clip.scale = Vector2.ONE * 0.62
	_foreground_layer.add_child(clip)
	_art_nodes.append(clip)
	blend_material = ShaderMaterial.new()
	blend_material.shader = preload("res://assets/shaders/sword_image_scene_blend.gdshader")
	var shadow := Polygon2D.new()
	legacy_contact_shadow = shadow
	shadow.name = "FootContact"
	shadow.color = Color(0.13, 0.17, 0.13, 0.13)
	var points := PackedVector2Array()
	for i in 40:
		var angle := float(i) * TAU / 40.0
		points.append(Vector2(cos(angle) * 40.0, sin(angle) * 7.0))
	shadow.polygon = points
	shadow.position = clip.position + Vector2(0, 2)
	_foreground_layer.add_child(shadow)
	_foreground_layer.move_child(shadow, 0)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0.12, 0.17, 0.12, 0.34), Color(0.12, 0.17, 0.12, 0.20), Color(0.12, 0.17, 0.12, 0.065), Color(0.12, 0.17, 0.12, 0.0)])
	var soft_shadow := GradientTexture2D.new()
	soft_shadow.gradient = gradient
	soft_shadow.width = 256
	soft_shadow.height = 64
	soft_shadow.fill = GradientTexture2D.FILL_RADIAL
	soft_shadow.fill_from = Vector2(0.5, 0.5)
	soft_shadow.fill_to = Vector2(1.0, 0.5)
	contact_shadow = Sprite2D.new()
	contact_shadow.name = "SoftFootContact"
	contact_shadow.texture = soft_shadow
	contact_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	contact_shadow.position = clip.position + Vector2(0, 3)
	contact_shadow.scale = Vector2(0.36, 0.28)
	_foreground_layer.add_child(contact_shadow)
	_foreground_layer.move_child(contact_shadow, 0)
	_art_nodes.append(contact_shadow)

func _build_header() -> void:
	_add_panel(Rect2(0, 0, VIEW_SIZE.x, ART_TOP), PAPER, GOLD, 1)
	_make_label("后山 · 转身挥剑", Rect2(36, 12, 330, 42), 30, INK)
	_make_label("江砚秋 · 单式小样", Rect2(38, 53, 330, 25), 17, MUTED)
	matte_button = _make_button("干净边缘", Rect2(375, 23, 160, 42), _toggle_matte_cleanup)
	paper_button = _make_button("轻纸感", Rect2(550, 23, 120, 42), _toggle_paper_texture)
	blend_button = _make_button("融入山色", Rect2(685, 23, 180, 42), _toggle_scene_blending)
	time_button = _make_button("巳时", Rect2(880, 23, 122, 42), _next_pilot_time)
	weather_button = _make_button("多云", Rect2(1017, 23, 145, 42), _next_pilot_weather)
	dynamic_button = _make_button("静态", Rect2(1177, 23, 223, 42), _toggle_dynamic)

func _build_footer() -> void:
	_add_panel(Rect2(0, FOOTER_TOP, VIEW_SIZE.x, VIEW_SIZE.y - FOOTER_TOP), PAPER, GOLD, 1)
	phase_label = _make_label("准备", Rect2(36, 816, 160, 29), 19, INK)
	timeline = HSlider.new()
	timeline.min_value = 0.0
	timeline.max_value = 2.44
	timeline.step = 0.001
	timeline.value_changed.connect(_seek_from_slider)
	_place(timeline, Rect2(213, 826, 620, 24), self)
	timeline.z_index = 19
	_make_label("空格 播放／暂停 · R 重播 · ← → 逐帧", Rect2(37, 856, 740, 26), 16, MUTED)
	play_button = _make_button("播放", Rect2(883, 827, 155, 43), _toggle_clip, true)
	speed_button = _make_button("正常速度", Rect2(1052, 827, 171, 43), _toggle_speed)
	replay_button = _make_button("重播", Rect2(1237, 827, 162, 43), _replay_clip)

func _process(delta: float) -> void:
	if dynamic_enabled and not qa_motion_paused:
		presentation_time += delta
		clip.advance(delta)
		_update_leaf_art(presentation_time)
		_sync_shader_times()
	environment_presenter.advance(delta)
	_apply_environment()
	_refresh_pilot_ui()

func _refresh_pilot_ui() -> void:
	if clip == null or phase_label == null:
		return
	phase_label.text = "末帧停留" if clip.seconds >= clip.duration else ("准备" if clip.seconds <= 0.0 else "转身挥剑")
	play_button.text = "播放" if clip.paused else "暂停"
	play_button.disabled = not dynamic_enabled
	replay_button.disabled = not dynamic_enabled
	speed_button.text = "半速" if clip.speed < 1.0 else "正常速度"
	if matte_button != null:
		matte_button.text = "干净边缘" if matte_enabled else "原始边缘"
	if paper_button != null:
		paper_button.text = "轻纸感" if paper_enabled else "无纸感"
		paper_button.disabled = not blend_enabled
	if blend_button != null:
		blend_button.text = "融入山色" if blend_enabled else "原片色彩"
	if blend_material != null and not clip.anchors.is_empty():
		blend_material.set_shader_parameter("foot_y", clip.anchors[clip.frame_index].y)
	_updating_timeline = true
	timeline.max_value = clip.duration
	timeline.value = clip.seconds
	_updating_timeline = false
	dynamic_button.text = "继续动态" if not dynamic_enabled else "静态"

func _toggle_clip() -> void:
	if not dynamic_enabled:
		return
	if clip.seconds >= clip.duration:
		clip.replay()
	else:
		clip.paused = not clip.paused
	_refresh_pilot_ui()

func _replay_clip() -> void:
	if dynamic_enabled:
		clip.replay()
	_refresh_pilot_ui()

func _toggle_speed() -> void:
	clip.speed = 0.5 if clip.speed >= 1.0 else 1.0
	_refresh_pilot_ui()

func _seek_from_slider(value: float) -> void:
	if _updating_timeline:
		return
	clip.paused = true
	_resume_clip_after_static = false
	clip.seek(value)
	_refresh_pilot_ui()

func set_dynamic(value: bool) -> void:
	if dynamic_enabled == value:
		return
	if not value:
		_resume_clip_after_static = not clip.paused
		clip.paused = true
	else:
		clip.paused = not _resume_clip_after_static
	dynamic_enabled = value
	_refresh_pilot_ui()

func _next_pilot_time() -> void:
	sample_time_index = (sample_time_index + 1) % 6
	environment_presenter.set_time_profile(Presenter.TIME_PROFILE_IDS[sample_time_index], true)
	time_button.text = str(state.rules.times[sample_time_index])

func _next_pilot_weather() -> void:
	var names := ["晴", "多云", "小雨"]
	var i := (Presenter.WEATHER_PROFILE_IDS.find(environment_presenter.weather_id) + 1) % 3
	environment_presenter.set_weather(Presenter.WEATHER_PROFILE_IDS[i], true)
	weather_button.text = names[i]

func _update_controls() -> void:
	pass

func _update_breath_pose() -> void:
	pass

func _update_actor_face() -> void:
	pass

func _input(event: InputEvent) -> void:
	super._input(event)
	# Study shortcuts remain consistent after a button or slider receives focus.
	if event is InputEventKey:
		_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_toggle_clip()
		KEY_R:
			_replay_clip()
		KEY_4:
			set_dynamic(not dynamic_enabled)
		KEY_LEFT, KEY_RIGHT:
			clip.paused = true
			_resume_clip_after_static = false
			clip.seek(clip.seconds + (-1.0 if event.keycode == KEY_LEFT else 1.0) / clip.fps)
			_refresh_pilot_ui()
		_:
			return
	get_viewport().set_input_as_handled()

func _toggle_scene_blending() -> void:
	set_scene_blending(not blend_enabled)

func set_scene_blending(value: bool) -> void:
	blend_enabled = value
	clip.sprite.material = blend_material if value else null
	contact_shadow.visible = value
	legacy_contact_shadow.visible = not value
	_refresh_pilot_ui()

func _toggle_paper_texture() -> void:
	set_paper_texture(not paper_enabled)

func set_paper_texture(value: bool) -> void:
	paper_enabled = value
	blend_material.set_shader_parameter("paper_strength", 0.85 if value else 0.0)
	_refresh_pilot_ui()


func _prepare_clean_matte() -> void:
	original_frames.assign(clip.frames)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLEAN_MANIFEST))
	assert(manifest.frames.size() == original_frames.size())
	assert(manifest.fps == clip.fps and manifest.duration == clip.duration)
	var pages: Dictionary = {}
	for i in original_frames.size():
		var entry: Dictionary = manifest.frames[i]
		assert(entry.region == clip.data.frames[i].region)
		assert(entry.source_anchor_px == clip.data.frames[i].source_anchor_px)
		if not pages.has(entry.path):
			pages[entry.path] = load(entry.path)
		var frame := AtlasTexture.new()
		frame.atlas = pages[entry.path]
		frame.region = original_frames[i].region
		frame.filter_clip = true
		clean_frames.append(frame)

func _toggle_matte_cleanup() -> void:
	set_matte_cleanup(not matte_enabled)

func set_matte_cleanup(value: bool) -> void:
	matte_enabled = value
	if not original_frames.is_empty() and not clean_frames.is_empty():
		clip.frames = clean_frames if value else original_frames
		# Re-sample the same clock and same unchanged anchors; no activity is settled.
		clip.seek(clip.seconds)
	_refresh_pilot_ui()
