extends Button
## A scene prop emits intent; the host owns inspection, costs and story state.
signal object_selected(object_id: String)

var object_id := ""
var object_label := ""
var inspected := false
var selected := false
var hovered := false
var prop: TextureRect
var hint: Label
var mark: Label
var motion: Tween
var ink_material: ShaderMaterial
var emphasis := 0.0:
	set(value):
		emphasis = value
		if ink_material != null: ink_material.set_shader_parameter("emphasis",value)

func configure(id: String, label: String, texture: Texture2D) -> void:
	object_id = id
	object_label = label
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(style, empty)
	prop = TextureRect.new()
	prop.texture = texture
	prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(prop)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float emphasis = 0.0;
void fragment() {
 vec4 c = texture(TEXTURE, UV);
 vec2 d = TEXTURE_PIXEL_SIZE * 6.0;
 float edge = max(max(texture(TEXTURE, UV+vec2(d.x,0.0)).a, texture(TEXTURE, UV-vec2(d.x,0.0)).a), max(texture(TEXTURE, UV+vec2(0.0,d.y)).a, texture(TEXTURE, UV-vec2(0.0,d.y)).a));
 float outline = max(0.0, edge-c.a) * emphasis * 0.85;
 COLOR = vec4(mix(vec3(0.83,0.65,0.36), c.rgb*(1.0+emphasis*0.07), c.a), max(c.a,outline));
}
"""
	ink_material = ShaderMaterial.new()
	ink_material.shader = shader
	prop.material = ink_material
	hint = Label.new()
	hint.text = label + " · 查看"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("354137"))
	hint.add_theme_color_override("font_shadow_color", Color("f4eddf"))
	hint.add_theme_constant_override("shadow_outline_size", 5)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	mark = Label.new()
	mark.text = "已阅"
	mark.add_theme_font_size_override("font_size", 15)
	mark.add_theme_color_override("font_color", Color("75634c"))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	resized.connect(_layout_labels)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_hover.bind(true))
	focus_exited.connect(_hover.bind(false))
	pressed.connect(func(): object_selected.emit(object_id))
	_layout_labels()
	set_state(false, false)

func _layout_labels() -> void:
	hint.position = Vector2(-35, -32)
	hint.size = Vector2(size.x+70, 28)
	mark.position = Vector2(size.x-37, size.y-13)
	mark.size = Vector2(38, 22)

func set_state(is_selected: bool, is_inspected: bool) -> void:
	selected = is_selected
	inspected = is_inspected
	mark.visible = inspected and not selected
	_update_visual()

func _hover(value: bool) -> void:
	hovered = value
	_update_visual()

func _update_visual() -> void:
	hint.visible = hovered and not selected
	if motion != null:
		motion.kill()
	if not is_inside_tree():
		return
	motion = create_tween().set_parallel(true)
	motion.tween_property(prop, "position:y", -2.0 if selected else 0.0, 0.18)
	motion.tween_property(self, "emphasis", 1.0 if selected else (0.5 if hovered else 0.0), 0.18)
