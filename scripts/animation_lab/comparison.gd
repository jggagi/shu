extends Control

const NativeActor = preload("res://scripts/animation_lab/native_actor.gd")
const DATA_PATH := "res://assets/data/animation_lab/motion.json"
const PALETTE := [Color("f5eee0"),Color("35493f"),Color("3d746c"),Color("ac895a")]
var data: Dictionary
var native_actor: Node2D
var baked_actor: TextureRect
var live_viewport: SubViewport
var live_model: Node3D
var live_player: AnimationPlayer
var live_animations: Dictionary = {}
var cards: Array[Control] = []
var card_notes: Array[Label] = []
var backgrounds: Array[Control] = []
var clip := "thrust"
var seconds := 0.0
var playing := true
var loop_enabled := true
var speed := 1.0
var single_mode := -1
var neutral_stage := false
var joints_enabled := false
var timeline: HSlider
var time_label: Label
var play_button: Button
var speed_button: Button
var loop_button: Button
var background_button: Button
var motion_buttons: Dictionary = {}
var baked_frames: Dictionary = {}
var _updating_slider := false
var _joint_overlay: Node2D
var _clock_cycles := 0

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_build_theme()
	_build_controls()
	_build_cards()
	_build_baked()
	_build_live()
	select_clip("thrust")

func _build_theme() -> void:
	var shared := Theme.new()
	shared.default_font = load("res://assets/fonts/ShuAnimationLabSerif.ttf")
	shared.default_font_size = 23
	theme = shared
	var paper := ColorRect.new()
	paper.color = PALETTE[0]
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)

func _label(text: String, rect: Rect2, font_size: int = 24, color: Color = PALETTE[1]) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for kind in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("ded4be") if kind == "hover" or kind == "pressed" else Color("f5eee0")
		style.border_color = PALETTE[3]
		style.set_border_width_all(2 if kind == "focus" else 1)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(kind,style)
	button.add_theme_color_override("font_color",PALETTE[1])
	button.add_theme_color_override("font_hover_color",PALETTE[2])
	button.add_theme_color_override("font_pressed_color",PALETTE[1])
	button.pressed.connect(callback)
	add_child(button)
	return button

func _build_controls() -> void:
	_label("蜀山 · 动作方案对照",Rect2(26,14,900,46),34)
	_label("原创研究角色 · 三种方案共用动作与镜头 · 零付费探索",Rect2(28,61,1100,32),21,Color("766b59"))
	for index in 3:
		var id: String = ["thrust","cut","staff"][index]
		motion_buttons[id] = _button(str(data.labels[id]),Rect2(26+index*170,106,158,48),func():select_clip(id))
	_button("并排比较",Rect2(570,106,152,48),func():set_single_mode(-1))
	_button("只看 A",Rect2(734,106,132,48),func():set_single_mode(0))
	_button("只看 B",Rect2(878,106,132,48),func():set_single_mode(1))
	_button("只看 C",Rect2(1022,106,132,48),func():set_single_mode(2))
	background_button = _button("背景：后山",Rect2(1166,106,246,48),_toggle_background)
	play_button = _button("暂停",Rect2(26,747,140,47),toggle_play)
	_button("重看",Rect2(178,747,140,47),reset_motion)
	_button("前一帧",Rect2(330,747,146,47),func():step_frame(-1))
	_button("后一帧",Rect2(488,747,146,47),func():step_frame(1))
	speed_button = _button("速度：正常",Rect2(646,747,195,47),_cycle_speed)
	loop_button = _button("循环：开",Rect2(853,747,180,47),_toggle_loop)
	_button("观察关节",Rect2(1045,747,180,47),_toggle_joints)
	time_label = _label("0.00 / 4.00 秒",Rect2(1240,747,178,47),22)
	timeline = HSlider.new()
	timeline.name = "MotionTimeline"
	timeline.position = Vector2(28,815)
	timeline.size = Vector2(1375,29)
	timeline.min_value = 0
	timeline.max_value = float(data.duration)
	timeline.step = 0.001
	timeline.value_changed.connect(_on_seek)
	add_child(timeline)
	_label("看脚步与重心、手与武器、转身遮挡。空格暂停；← → 逐帧；1 / 2 / 3 换动作。",Rect2(28,854,1390,32),20,Color("766b59"))

func _build_cards() -> void:
	var titles := ["A · 原生 2D 骨骼","B · Blender 预渲染","C · Blender 实时 3D"]
	var notes := ["分层造型／连续关节 · 转身仍依赖二维美术","透明序列帧 · 30 帧／秒 · 固定镜头","同一模型与动作 · 连续插值 · 可换镜头"]
	for index in 3:
		var card := Control.new()
		card.name = "Candidate%d" % index
		card.position = Vector2(26+index*470,176)
		card.size = Vector2(448,553)
		add_child(card)
		cards.append(card)
		var heading := _label(titles[index],Rect2(Vector2.ZERO,Vector2(448,43)),26)
		heading.reparent(card)
		heading.position = Vector2.ZERO
		var stage := Control.new()
		stage.name = "Stage"
		stage.position = Vector2(0,49)
		stage.size = Vector2(448,448)
		stage.clip_contents = true
		card.add_child(stage)
		var fill := ColorRect.new()
		fill.color = Color("e8e4d9")
		fill.size = Vector2(448,448)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(fill)
		var layers := Control.new()
		layers.name = "PaintedBackground"
		layers.size = Vector2(448,448)
		stage.add_child(layers)
		backgrounds.append(layers)
		for layer in ["far","mid","near"]:
			var image := TextureRect.new()
			var atlas := AtlasTexture.new()
			atlas.atlas = load("res://assets/art/back_mountain_training/%s.png" % layer)
			atlas.region = Rect2(970,0,750,887)
			image.texture = atlas
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.size = Vector2(448,448)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layers.add_child(image)
		var shadow := FloorMark.new()
		shadow.name = "GroundMark"
		shadow.position = _screen_origin()
		stage.add_child(shadow)
		var note := _label(notes[index],Rect2(0,507,448,44),18,Color("766b59"))
		note.reparent(card)
		note.position = Vector2(0,507)
		card_notes.append(note)
		if index == 0:
			native_actor = NativeActor.new()
			native_actor.name = "Native2DActor"
			stage.add_child(native_actor)
			native_actor.configure(data)
			native_actor.position = _screen_origin()
			native_actor.scale = Vector2.ONE * (448.0 / float(data.camera.ortho) / 100.0)
			_joint_overlay = JointOverlay.new()
			(_joint_overlay as JointOverlay).data = data
			(_joint_overlay as JointOverlay).origin = _screen_origin()
			(_joint_overlay as JointOverlay).factor = 448.0 / float(data.camera.ortho)
			stage.add_child(_joint_overlay)
			_joint_overlay.visible = false
		elif index == 1:
			baked_actor = TextureRect.new()
			baked_actor.name = "PreRenderedActor"
			baked_actor.size = Vector2(448,448)
			baked_actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			baked_actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage.add_child(baked_actor)
		else:
			var container := SubViewportContainer.new()
			container.name = "Live3DContainer"
			container.size = Vector2(448,448)
			container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.stretch = true
			stage.add_child(container)
			live_viewport = SubViewport.new()
			live_viewport.size = Vector2i(448,448)
			live_viewport.transparent_bg = true
			live_viewport.own_world_3d = true
			live_viewport.msaa_3d = Viewport.MSAA_2X
			container.add_child(live_viewport)

func _screen_origin() -> Vector2:
	var target := Vector3(data.camera.target[0],data.camera.target[1],data.camera.target[2])
	var up := Vector3(data.camera.up[0],data.camera.up[1],data.camera.up[2])
	return Vector2(224,224 + target.dot(up)*448.0/float(data.camera.ortho))

func _build_baked() -> void:
	for id in ["thrust","cut","staff"]:
		var textures: Array[Texture2D] = []
		# Atlases keep texture switching and Web import overhead bounded.
		var manifest_path := "res://assets/art/animation_lab/atlas.json"
		if FileAccess.file_exists(manifest_path):
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			for entry: Dictionary in manifest.clips[id]:
				var atlas := AtlasTexture.new()
				atlas.atlas = load(str(entry.path))
				atlas.region = Rect2(entry.region[0],entry.region[1],entry.region[2],entry.region[3])
				atlas.filter_clip = true
				textures.append(atlas)
		baked_frames[id] = textures
	if baked_frames.thrust.is_empty():
		card_notes[1].text = "预渲染素材尚未生成"

func _find_nodes(node: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type_name):found.append(node)
	for child in node.get_children():found.append_array(_find_nodes(child,type_name))
	return found

func _build_live() -> void:
	if not ResourceLoader.exists("res://assets/art/animation_lab/model.glb"):
		card_notes[2].text = "实时模型尚未生成"
		return
	var scene := load("res://assets/art/animation_lab/model.glb") as PackedScene
	live_model = scene.instantiate()
	live_model.name = "BlenderStudyModel"
	live_viewport.add_child(live_model)
	var players := _find_nodes(live_model,"AnimationPlayer")
	if not players.is_empty():
		live_player = players[0] as AnimationPlayer
		live_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for name in live_player.get_animation_list():
			for id in ["thrust","cut","staff"]:
				if str(name).to_lower().contains(id):live_animations[id]=str(name)
	var cameras := _find_nodes(live_model,"Camera3D")
	if not cameras.is_empty():
		(cameras[0] as Camera3D).current = true
	else:
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = float(data.camera.ortho)
		camera.position = Vector3(4,3.3,7)
		live_viewport.add_child(camera)
		camera.look_at(Vector3(0,1.4,0))
		camera.current = true
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("eee9df")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	live_viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_color = Color("fff2df")
	light.light_energy = 0.9
	live_viewport.add_child(light)

func select_clip(id: String) -> void:
	if not data.clips.has(id):return
	clip = id
	seconds = 0.0
	for key in motion_buttons:
		motion_buttons[key].modulate = Color("c1d9ca") if key == id else Color.WHITE
	for mesh in _find_nodes(live_model,"MeshInstance3D") if live_model != null else []:
		if str(mesh.name).contains("Sword"):mesh.visible = id != "staff"
		if str(mesh.name).contains("Staff"):mesh.visible = id == "staff"
	_sample_all()

func _sample_all() -> void:
	if native_actor != null:native_actor.sample(clip,seconds)
	var frames: Array = baked_frames.get(clip,[])
	if not frames.is_empty():
		baked_actor.texture = frames[clampi(int(floor(seconds*float(data.fps))),0,frames.size()-1)]
	if live_player != null and live_animations.has(clip):
		var animation_name: String = live_animations[clip]
		if live_player.current_animation != animation_name:live_player.play(animation_name)
		
		# Blender starts at frame 1; glTF retains its 1/fps time origin.
		live_player.seek(seconds + 1.0/float(data.fps),true)
		live_player.advance(0.0)
	if _joint_overlay != null:
		(_joint_overlay as JointOverlay).clip = clip
		(_joint_overlay as JointOverlay).seconds = seconds
		_joint_overlay.queue_redraw()
	_updating_slider = true
	timeline.value = seconds
	_updating_slider = false
	time_label.text = "%.2f / %.2f 秒" % [seconds,float(data.duration)]

func seek_motion(value: float) -> void:
	seconds = clampf(value,0,float(data.duration))
	_sample_all()

func _on_seek(value: float) -> void:
	if _updating_slider:return
	playing = false
	_sync_play_button()
	seek_motion(value)

func toggle_play() -> void:
	playing = not playing
	if playing and seconds >= float(data.duration):seconds = 0
	_sync_play_button()

func _sync_play_button() -> void:
	play_button.text = "暂停" if playing else "播放"

func reset_motion() -> void:
	seek_motion(0)

func step_frame(direction: int) -> void:
	playing = false
	_sync_play_button()
	seek_motion(roundf(seconds*float(data.fps))/float(data.fps) + float(direction)/float(data.fps))

func _cycle_speed() -> void:
	speed = 0.5 if is_equal_approx(speed,1.0) else (0.25 if is_equal_approx(speed,0.5) else 1.0)
	speed_button.text = "速度：" + ("正常" if speed == 1.0 else ("半速" if speed == 0.5 else "四分之一"))

func _toggle_loop() -> void:
	loop_enabled = not loop_enabled
	loop_button.text = "循环：" + ("开" if loop_enabled else "关")

func _toggle_background() -> void:
	neutral_stage = not neutral_stage
	for background in backgrounds:background.visible = not neutral_stage
	background_button.text = "背景：" + ("素纸" if neutral_stage else "后山")

func _toggle_joints() -> void:
	joints_enabled = not joints_enabled
	native_actor.set_bones_visible(joints_enabled)
	_joint_overlay.visible = joints_enabled

func set_single_mode(index: int) -> void:
	single_mode = index
	for i in cards.size():
		cards[i].visible = index < 0 or i == index
		cards[i].scale = Vector2.ONE if index < 0 else Vector2.ONE * 1.02
		cards[i].position = Vector2(26+i*470,176) if index < 0 else Vector2(496,176)

func _process(delta: float) -> void:
	if not playing:return
	seconds += delta*speed
	if seconds >= float(data.duration):
		if loop_enabled:
			seconds = fmod(seconds,float(data.duration))
			_clock_cycles += 1
		else:
			seconds = float(data.duration)
			playing = false
			_sync_play_button()
	_sample_all()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	match event.keycode:
		KEY_SPACE:toggle_play()
		KEY_LEFT:step_frame(-1)
		KEY_RIGHT:step_frame(1)
		KEY_1:select_clip("thrust")
		KEY_2:select_clip("cut")
		KEY_3:select_clip("staff")
		KEY_R:reset_motion()
		_:return
	get_viewport().set_input_as_handled()

func diagnostics() -> Dictionary:
	return {"clip":clip,"seconds":seconds,"playing":playing,"native":native_actor.diagnostics(),"baked_counts":baked_frames.keys().map(func(id):return baked_frames[id].size()),"live_animation_names":live_player.get_animation_list() if live_player != null else [],"live_clip_mapping":live_animations,"loop_cycles":_clock_cycles,"gameplay_state_instances":0}

class FloorMark extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO,0,Vector2(1,.19))
		draw_circle(Vector2.ZERO,65,Color(0.13,.18,.13,.18))

class JointOverlay extends Node2D:
	var data: Dictionary
	var clip := "thrust"
	var seconds := 0.0
	var origin := Vector2.ZERO
	var factor := 100.0
	func project(point: Array) -> Vector2:
		var p := Vector3(point[0],point[1],point[2])
		var right := Vector3(data.camera.right[0],data.camera.right[1],data.camera.right[2])
		var up := Vector3(data.camera.up[0],data.camera.up[1],data.camera.up[2])
		return origin + Vector2(p.dot(right),-p.dot(up))*factor
	func _draw() -> void:
		var poses: Array = data.clips[clip]
		var index := clampi(int(round(seconds*float(data.fps))),0,poses.size()-1)
		var joints: Dictionary = poses[index].joints
		for bone: Dictionary in data.bones:
			var a := project(joints[bone.head])
			var b := project(joints[bone.tail])
			draw_line(a,b,Color("a86831"),1.5,true)
			draw_circle(a,3,Color("a86831"))
