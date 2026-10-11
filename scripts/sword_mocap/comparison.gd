extends Control

const DESIGN_SIZE := Vector2(1152.0, 720.0)
@export_file var atlas_path: String = "res://assets/art/sword_mocap/atlas.json"
@export_file var model_path: String = "res://assets/art/sword_mocap/study.glb"
@export_file var study_path: String = "res://assets/data/sword_mocap/study.json"
@export_file var font_path: String = "res://assets/fonts/ShuSwordMocapSerif.ttf"
const BACKGROUND_DIR := "res://assets/art/back_mountain_training"
const PAPER := Color("f5eee0")
const INK := Color("35493f")
const JADE := Color("3d746c")
const OCHRE := Color("ac895a")
const MUTED := Color("766b59")
const STAGE := Color("e8e4d9")
# Identical fixed crop; all rendered frames retain at least 66 px of transparent margin.
@export var view_crop := Rect2(48, 48, 224, 224)
@export var actor_offset := Vector2.ZERO
@export var study_title := "剑术动作 · 真人捕捉对照"
@export var study_subtitle := "同一动作、同一镜头，比较全身协调与播放效果"
@export var study_footer := "CMU 02_09 真人动作 · 研究灰模，尚非江砚秋造型或考证剑法；不接入养成。"

var study_data: Dictionary = {}
var atlas_data: Dictionary = {}
var phases: Array = []
var source_label := ""
var duration := 0.0
var fps := 60.0
var frame_count := 0
var atlas_size := Vector2i(320, 320)
var baked_frames: Array[Texture2D] = []
var background_layers: Array[Array] = []
var cards: Array[Control] = []
var card_titles: Array[Label] = []
var stage_rect := Rect2(94, 52, 350, 350)
var ui_canvas: Control
var timeline: HSlider
var time_label: Label
var phase_label: Label
var play_button: Button
var speed_button: Button
var repeat_button: Button
var background_button: Button
var live_viewport: SubViewport
var live_model: Node3D
var live_player: AnimationPlayer
var live_animation := ""
var live_camera: Camera3D
var live_skeleton: Skeleton3D
var baked_actor: TextureRect
var seconds := 0.0
var speed := 1.0
var playing := true
var loop_enabled := false
var single_mode := -1
var painted_background := true
var _updating_timeline := false
var _live_time := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_read_study_data()
	_read_atlas()
	_build_theme()
	_build_interface()
	_build_cards()
	_build_live_model()
	set_background(false)
	_sample_all()
	resized.connect(_layout_ui)
	_layout_ui()

func _read_study_data() -> void:
	var parsed_study: Variant = _read_json(study_path)
	if parsed_study is Dictionary:
		study_data = parsed_study
		duration = maxf(0.0, float(study_data.get("duration", 0.0)))
		fps = maxf(1.0, float(study_data.get("fps", 60.0)))
		source_label = str(study_data.get("source_label", ""))
		var raw_phases: Variant = study_data.get("phases", [])
		if raw_phases is Array:
			phases = raw_phases

func _read_atlas() -> void:
	var parsed_atlas: Variant = _read_json(atlas_path)
	if parsed_atlas is Dictionary:
		atlas_data = parsed_atlas
		var width := int(atlas_data.get("width", atlas_size.x))
		var height := int(atlas_data.get("height", atlas_size.y))
		if width > 0 and height > 0:
			atlas_size = Vector2i(width, height)
		if duration <= 0.0:
			duration = maxf(0.0, float(atlas_data.get("duration", 0.0)))
		if fps <= 0.0:
			fps = maxf(1.0, float(atlas_data.get("fps", 60.0)))
		var raw_frames: Variant = atlas_data.get("frames", [])
		if raw_frames is Array:
			for entry_value: Variant in raw_frames:
				if not entry_value is Dictionary:
					continue
				var entry: Dictionary = entry_value
				var texture_path := str(entry.get("path", ""))
				var region_value: Variant = entry.get("region", [])
				if texture_path.is_empty() or not region_value is Array or region_value.size() < 4:
					continue
				if not ResourceLoader.exists(texture_path):
					continue
				var atlas_texture := AtlasTexture.new()
				atlas_texture.atlas = load(texture_path) as Texture2D
				if atlas_texture.atlas == null:
					continue
				atlas_texture.region = Rect2(
					float(region_value[0]) + view_crop.position.x, float(region_value[1]) + view_crop.position.y,
					view_crop.size.x, view_crop.size.y
				)
				atlas_texture.filter_clip = true
				baked_frames.append(atlas_texture)
	frame_count = baked_frames.size()
	if duration <= 0.0 and fps > 0.0 and frame_count > 0:
		duration = float(frame_count) / fps
	if frame_count > 0:
		var declared_count := int(atlas_data.get("frame_count", frame_count))
		if declared_count != frame_count:
			push_warning("Sword mocap atlas declares %d frames but provides %d" % [declared_count, frame_count])

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)

func _build_theme() -> void:
	var shared := Theme.new()
	if ResourceLoader.exists(font_path):
		shared.default_font = load(font_path) as Font
	shared.default_font_size = 19
	theme = shared
	var paper := ColorRect.new()
	paper.name = "PaperBackground"
	paper.color = PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	ui_canvas = Control.new()
	ui_canvas.name = "StudyCanvas"
	ui_canvas.position = Vector2.ZERO
	ui_canvas.size = DESIGN_SIZE
	ui_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ui_canvas)

func _layout_ui() -> void:
	if ui_canvas == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var factor := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	ui_canvas.scale = Vector2.ONE * factor
	ui_canvas.position = (available - DESIGN_SIZE * factor) * 0.5

func _build_interface() -> void:
	_add_label(ui_canvas, study_title, Rect2(26, 8, 550, 38), 31, INK)
	_add_label(ui_canvas, study_subtitle, Rect2(28, 43, 1065, 25), 17, MUTED)
	card_titles.append(_add_label(ui_canvas, "B · 预渲染 2D", Rect2(34, 77, 500, 32), 24, INK))
	card_titles.append(_add_label(ui_canvas, "C · 实时 3D", Rect2(602, 77, 500, 32), 24, INK))

	play_button = _add_button(ui_canvas, "暂停", Rect2(28, 557, 88, 38), toggle_play)
	_add_button(ui_canvas, "重置", Rect2(122, 557, 82, 38), reset_motion)
	_add_button(ui_canvas, "前一帧", Rect2(210, 557, 92, 38), func() -> void: step_frame(-1))
	_add_button(ui_canvas, "后一帧", Rect2(308, 557, 92, 38), func() -> void: step_frame(1))
	speed_button = _add_button(ui_canvas, "速度：1×", Rect2(406, 557, 112, 38), _cycle_speed)
	repeat_button = _add_button(ui_canvas, "重复：关", Rect2(524, 557, 112, 38), _toggle_repeat)
	background_button = _add_button(ui_canvas, "背景：后山", Rect2(642, 557, 130, 38), func() -> void: set_background(not painted_background))
	_add_button(ui_canvas, "只看 B", Rect2(778, 557, 82, 38), func() -> void: set_single_mode(0))
	_add_button(ui_canvas, "只看 C", Rect2(866, 557, 82, 38), func() -> void: set_single_mode(1))
	_add_button(ui_canvas, "并排", Rect2(954, 557, 78, 38), func() -> void: set_single_mode(-1))

	timeline = HSlider.new()
	timeline.name = "MotionTimeline"
	timeline.position = Vector2(28, 605)
	timeline.size = Vector2(1096, 22)
	timeline.min_value = 0.0
	timeline.max_value = maxf(duration, 0.001)
	timeline.step = 0.001
	timeline.value_changed.connect(_on_timeline_changed)
	ui_canvas.add_child(timeline)
	time_label = _add_label(ui_canvas, "0.00 / 0.00 s", Rect2(28, 630, 300, 22), 17, INK)
	phase_label = _add_label(ui_canvas, "", Rect2(330, 630, 794, 22), 17, MUTED)
	_add_label(
		ui_canvas,
		study_footer,
		Rect2(28, 663, 1096, 38), 16, MUTED
	)

func _build_cards() -> void:
	_build_card(0, "CandidateB")
	_build_card(1, "CandidateC")

func _build_card(index: int, node_name: String) -> void:
	var card := Panel.new()
	card.name = node_name
	card.position = Vector2(24 if index == 0 else 592, 109)
	card.size = Vector2(536, 438)
	card.add_theme_stylebox_override("panel", _panel_style())
	ui_canvas.add_child(card)
	cards.append(card)

	var stage_backdrop := ColorRect.new()
	stage_backdrop.name = "StageBackdrop"
	stage_backdrop.position = stage_rect.position
	stage_backdrop.size = stage_rect.size
	stage_backdrop.color = STAGE
	stage_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stage_backdrop)
	var layer_group: Array = []
	for layer_name in ["far", "mid", "near"]:
		var image := TextureRect.new()
		image.name = "Painted_%s" % layer_name
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var atlas_texture := AtlasTexture.new()
		var path := "%s/%s.png" % [BACKGROUND_DIR, layer_name]
		if ResourceLoader.exists(path):
			atlas_texture.atlas = load(path) as Texture2D
			atlas_texture.region = Rect2(970, 0, 750, 887)
			image.texture = atlas_texture
		image.position = stage_rect.position
		image.size = stage_rect.size
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(image)
		layer_group.append(image)
	background_layers.append(layer_group)

	if index == 0:
		baked_actor = TextureRect.new()
		baked_actor.name = "BakedActor"
		baked_actor.position = stage_rect.position + actor_offset
		baked_actor.size = stage_rect.size
		baked_actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		baked_actor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		baked_actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(baked_actor)
	else:
		var container := TextureRect.new()
		container.name = "Live3DContainer"
		container.position = stage_rect.position + actor_offset
		container.size = stage_rect.size
		container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		container.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(container)
		live_viewport = SubViewport.new()
		live_viewport.name = "Live3DViewport"
		live_viewport.size = atlas_size
		live_viewport.transparent_bg = true
		live_viewport.own_world_3d = true
		live_viewport.msaa_3d = Viewport.MSAA_2X
		live_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(live_viewport)
		var live_texture := AtlasTexture.new()
		live_texture.atlas = live_viewport.get_texture()
		live_texture.region = view_crop
		live_texture.filter_clip = true
		container.texture = live_texture

	var note := _add_label(
		card,
		("透明序列 · 60 帧／秒" if index == 0 else "完整 3D 骨架 · 连续插值"),
		Rect2(14, 407, 508, 23), 16, MUTED
	)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fbf8ef")
	style.border_color = Color("d5c9ad")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _add_label(parent: Control, text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _add_button(parent: Control, text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	for kind in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e6ddcb") if kind in ["hover", "pressed"] else PAPER
		style.border_color = OCHRE
		style.set_border_width_all(1 if kind != "focus" else 2)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(kind, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", JADE)
	button.add_theme_color_override("font_pressed_color", INK)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_live_model() -> void:
	if live_viewport == null or not ResourceLoader.exists(model_path):
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	live_model = packed.instantiate() as Node3D
	if live_model == null:
		return
	live_model.name = "SwordStudyModel"
	live_viewport.add_child(live_model)
	for node: Node in _find_nodes(live_model, "Skeleton3D"):
		if live_skeleton == null:
			live_skeleton = node as Skeleton3D
	for node: Node in _find_nodes(live_model, "Camera3D"):
		if live_camera == null:
			live_camera = node as Camera3D
	if live_camera != null:
		live_camera.current = true
	for node: Node in _find_nodes(live_model, "AnimationPlayer"):
		var candidate := node as AnimationPlayer
		candidate.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for animation_name: StringName in candidate.get_animation_list():
			if str(animation_name).to_lower().contains("swordstudy"):
				live_player = candidate
				live_animation = str(animation_name)
				break
		if live_player != null:
			break
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7d8d6")
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	live_viewport.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	light.light_energy = 0.8
	light.shadow_enabled = false
	live_viewport.add_child(light)

func _find_nodes(node: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type_name):
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_find_nodes(child, type_name))
	return found

func _frame_index() -> int:
	if frame_count <= 0:
		return 0
	return clampi(int(floor(seconds * fps)), 0, frame_count - 1)

func _sample_all() -> void:
	if baked_actor != null and frame_count > 0:
		baked_actor.texture = baked_frames[_frame_index()]
	if live_player != null and not live_animation.is_empty():
		# The host clock owns playback; this player only samples its assigned clip.
		if live_player.assigned_animation != live_animation:
			live_player.assigned_animation = live_animation
		live_player.seek(seconds, true)
		_live_time = live_player.current_animation_position
	else:
		_live_time = -1.0
	if timeline != null:
		_updating_timeline = true
		timeline.set_value_no_signal(seconds)
		_updating_timeline = false
	if time_label != null:
		time_label.text = "%.3f / %.3f s · frame %d" % [seconds, duration, _frame_index()]
	if phase_label != null:
		var phase := _phase_for_time(seconds)
		phase_label.text = "当前：%s" % str(phase.get("label", "")) if not phase.is_empty() else ""

func _phase_for_time(value: float) -> Dictionary:
	var selected: Dictionary = {}
	var selected_start := -INF
	for phase_value: Variant in phases:
		if not phase_value is Dictionary:
			continue
		var phase: Dictionary = phase_value
		var start := float(phase.get("start", INF))
		if start <= value and start >= selected_start:
			selected = phase
			selected_start = start
	return selected

func seek_motion(value: float) -> void:
	seconds = clampf(value, 0.0, duration)
	_sample_all()

func toggle_play() -> void:
	if playing:
		playing = false
	else:
		if seconds >= duration and not loop_enabled:
			seek_motion(0.0)
		playing = true
	_sync_transport_labels()

func reset_motion() -> void:
	seek_motion(0.0)

func step_frame(direction: int) -> void:
	playing = false
	_sync_transport_labels()
	if frame_count <= 0:
		return
	var target_index := clampi(_frame_index() + signi(direction), 0, frame_count - 1)
	var target_time := minf(float(target_index) / fps, duration)
	seek_motion(target_time)

func set_speed(value: float) -> void:
	for allowed in [1.0, 0.5, 0.25]:
		if is_equal_approx(value, allowed):
			speed = allowed
			break
	_sync_transport_labels()

func _cycle_speed() -> void:
	if is_equal_approx(speed, 1.0):
		set_speed(0.5)
	elif is_equal_approx(speed, 0.5):
		set_speed(0.25)
	else:
		set_speed(1.0)

func _toggle_repeat() -> void:
	loop_enabled = not loop_enabled
	_sync_transport_labels()

func _sync_transport_labels() -> void:
	if play_button != null:
		play_button.text = "暂停" if playing else "播放"
	if speed_button != null:
		speed_button.text = "速度：%s×" % ("1" if is_equal_approx(speed, 1.0) else ("0.5" if is_equal_approx(speed, 0.5) else "0.25"))
	if repeat_button != null:
		repeat_button.text = "重复：开" if loop_enabled else "重复：关"

func set_single_mode(index: int) -> void:
	if index not in [-1, 0, 1]:
		return
	single_mode = index
	for card_index in cards.size():
		var card := cards[card_index]
		card.visible = index < 0 or card_index == index
		card_titles[card_index].visible = card.visible
		card_titles[card_index].position.x = (34.0 if card_index == 0 else 602.0) if index < 0 else 318.0
		card.position = Vector2(24 if card_index == 0 else 592, 109) if index < 0 else Vector2(308, 109)

func set_background(painted: bool) -> void:
	painted_background = painted
	for group: Array in background_layers:
		for layer_value: Variant in group:
			(layer_value as Control).visible = painted
	if background_button != null:
		background_button.text = "背景：后山" if painted else "背景：素纸"

func _on_timeline_changed(value: float) -> void:
	if _updating_timeline:
		return
	playing = false
	_sync_transport_labels()
	seek_motion(value)

func _process(delta: float) -> void:
	if not playing or duration <= 0.0:
		return
	seconds += delta * speed
	if seconds >= duration:
		if loop_enabled:
			seconds = fposmod(seconds, duration)
		else:
			seconds = duration
			playing = false
			_sync_transport_labels()
	_sample_all()

func diagnostics() -> Dictionary:
	return {
		"seconds": seconds,
		"speed": speed,
		"playing": playing,
		"frame_index": _frame_index(),
		"live_time": _live_time,
		"duration": duration,
		"assigned_animation": live_player.assigned_animation if live_player != null else "",
		"animation_name": live_animation,
		"bone_count": live_skeleton.get_bone_count() if live_skeleton != null else 0,
		"skeleton_bone_count": live_skeleton.get_bone_count() if live_skeleton != null else 0,
		"gameplay_state_instances": 0,
		"clip_label": source_label,
		"phase_label": str(_phase_for_time(seconds).get("label", "")),
		"frame_count": frame_count,
		"fps": fps,
		"atlas_size": atlas_size,
		"camera_found": live_camera != null
	}

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	match event.keycode:
		KEY_SPACE:toggle_play()
		KEY_LEFT:step_frame(-1)
		KEY_RIGHT:step_frame(1)
		KEY_R:reset_motion()
		_:return
	get_viewport().set_input_as_handled()
