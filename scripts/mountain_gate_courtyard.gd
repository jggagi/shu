extends Control

const State = preload("res://scripts/demo_state.gd")
const EnvironmentAdapter = preload("res://scripts/courtyard_environment.gd")
const Cat = preload("res://scripts/courtyard_cat.gd")
const TIME_LABELS := ["卯时", "辰时", "巳时", "午时", "申时", "酉时"]
const WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const WEATHER_LABELS := ["晴", "多云", "小雨"]
var state = State.new()
var environment = EnvironmentAdapter.new()
var cat = Cat.new()
var world := Node2D.new()
var dynamic_enabled := true
var weather_id := "cloudy"
var preview_time_index := -1
var _time_buttons: Array[Button] = []
var _weather_buttons: Array[Button] = []
var _dynamic_button: Button
var _status: Label
var _note: Label
var _pet_note_age := 0.0
var _panel: PanelContainer

func _ready() -> void:
	DisplayServer.window_set_title("蜀 · 山门庭院 v1 · 独立试玩")
	var backdrop := ColorRect.new()
	backdrop.color = Color("eee7d5")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	world.name = "PaintedWorld"
	add_child(world)
	var art := TextureRect.new()
	art.name = "CourtyardPainting"
	art.texture = preload("res://assets/art/courtyard/mountain-gate-v1.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = Vector2(1280,720)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(art)
	add_child(environment)
	environment.configure(art, world)
	world.add_child(cat)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/courtyard_layout.json"))
	# Geometry is authored for the actual gallery stone landing.
	layout["path"] = layout.cat_path
	cat.configure(layout)
	cat.petted.connect(_on_petted)
	_build_ui()
	resized.connect(_layout)
	_layout()
	_refresh()

func _process(delta: float) -> void:
	advance_presentation(delta)

func advance_presentation(delta: float) -> void:
	var index: int = state.time_index if preview_time_index < 0 else preview_time_index
	environment.observe(index,weather_id)
	environment.advance(delta,dynamic_enabled)
	var observed: Dictionary = environment.snapshot()
	observed["foreground_busy"] = false
	var tint: Color = observed.world_tint
	var sheltered_brightness := lerpf(1.0,float(observed.brightness),0.25)
	cat.modulate = Color.WHITE.lerp(tint,0.25) * Color(sheltered_brightness,sheltered_brightness,sheltered_brightness,1.0)
	cat.update_presentation(observed,dynamic_enabled,delta)
	if dynamic_enabled and _pet_note_age > 0.0:
		_pet_note_age = maxf(0.0,_pet_note_age-delta)
		if _pet_note_age == 0.0:
			_note.text = "檐下的大橘，可轻轻摸摸。"

func set_time_preview(index: int) -> void:
	preview_time_index = clampi(index,0,5)
	_refresh()

func set_weather_preview(id: String) -> void:
	if not WEATHER_IDS.has(id):
		return
	weather_id = id
	_refresh()

func toggle_dynamic() -> void:
	dynamic_enabled = not dynamic_enabled
	advance_presentation(0.0)
	_refresh()

func reset_scene() -> void:
	state.reset()
	preview_time_index = -1
	weather_id = "cloudy"
	dynamic_enabled = true
	_pet_note_age = 0.0
	environment.reset()
	cat.reset()
	_note.text = "檐下的大橘，可轻轻摸摸。"
	advance_presentation(0.0)
	_refresh()

func get_snapshot() -> Dictionary:
	return {"environment":environment.snapshot(),"cat":cat.get_snapshot(),"dynamic":dynamic_enabled,"preview_time":preview_time_index,"weather":weather_id,"host_time":state.time_index,"host_energy":state.energy,"host_cultivation":state.cultivation}

func _on_petted() -> void:
	_note.text = "大橘眯起眼，轻轻蹭了蹭。"
	_pet_note_age = 3.0

func _build_ui() -> void:
	var font = preload("res://assets/fonts/ShuDemoSerif.ttf")
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 21
	for kind in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f4eddb") if kind == "normal" else Color("dfd5bd")
		style.border_color = Color("968064")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 11
		style.content_margin_right = 11
		theme.set_stylebox(kind,"Button",style)
	theme.set_color("font_color","Button",Color("453c30"))
	theme.set_color("font_hover_color","Button",Color("453c30"))
	theme.set_color("font_pressed_color","Button",Color("453c30"))
	_panel = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("eee7d5")
	paper.border_color = Color("9e896c")
	paper.border_width_top = 2
	paper.content_margin_left = 22
	paper.content_margin_right = 22
	paper.content_margin_top = 8
	paper.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel",paper)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",5)
	_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	col.add_child(row)
	var title := Label.new()
	title.text = "山门庭院"
	title.add_theme_color_override("font_color",Color("423e31"))
	row.add_child(title)
	for i in 6:
		var b := _button(TIME_LABELS[i],row)
		b.pressed.connect(set_time_preview.bind(i))
		_time_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for i in 3:
		var b := _button(WEATHER_LABELS[i],row)
		b.pressed.connect(set_weather_preview.bind(WEATHER_IDS[i]))
		_weather_buttons.append(b)
	_dynamic_button = _button("静态",row)
	_dynamic_button.pressed.connect(toggle_dynamic)
	_button("重置",row).pressed.connect(reset_scene)
	var line := HBoxContainer.new()
	col.add_child(line)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size",17)
	_status.add_theme_color_override("font_color",Color("665d4d"))
	line.add_child(_status)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(gap)
	_note = Label.new()
	_note.text = "檐下的大橘，可轻轻摸摸。"
	_note.add_theme_font_size_override("font_size",17)
	_note.add_theme_color_override("font_color",Color("665d4d"))
	line.add_child(_note)

func _button(text: String,parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _layout() -> void:
	var scale_factor := minf(size.x/1280.0,maxf(1.0,size.y-90.0)/720.0)
	world.scale = Vector2.ONE*scale_factor
	world.position = Vector2((size.x-1280.0*scale_factor)*0.5,(size.y-90.0-720.0*scale_factor)*0.5)
	_panel.position = Vector2(0,size.y-90)
	_panel.size = Vector2(size.x,90)

func _refresh() -> void:
	if _status == null:return
	var index: int = state.time_index if preview_time_index < 0 else preview_time_index
	for i in _time_buttons.size():
		_time_buttons[i].modulate = Color("c6b897") if i==index else Color.WHITE
	for i in _weather_buttons.size():
		_weather_buttons[i].modulate = Color("c6b897") if WEATHER_IDS[i]==weather_id else Color.WHITE
	_dynamic_button.text = "静态" if dynamic_enabled else "继续动态"
	_status.text = "%s · %s · %s    时辰仅预览 / 4 动静 / R 重置" % [TIME_LABELS[index],WEATHER_LABELS[WEATHER_IDS.find(weather_id)],"动态" if dynamic_enabled else "静态"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	match event.keycode:
		KEY_4:toggle_dynamic()
		KEY_R:reset_scene()
		KEY_7:set_weather_preview("clear")
		KEY_8:set_weather_preview("cloudy")
		KEY_9:set_weather_preview("light_rain")
		KEY_T:set_time_preview((maxi(preview_time_index,state.time_index)+1)%6)
