extends Node3D
## Offline-authored Effekseer and Material Maker assets, played as native meshes.
## The battlefield owns the only clock; this helper never reads combat rules.
const CONFIG_PATH := "res://assets/art/mountain_ambush/palm_lab/palm-vfx.json"
const IMPACT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha;
uniform sampler2D atlas_tex : filter_linear, repeat_disable;
uniform vec2 atlas_grid = vec2(8.0, 3.0);
uniform float frame = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 cell = vec2(mod(frame, atlas_grid.x), floor(frame / atlas_grid.x));
	vec4 pixel = texture(atlas_tex, (UV + cell) / atlas_grid);
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
}
"""
var _config: Dictionary = {}
var _assets: Dictionary = {}
var _textures: Dictionary = {}
var _ready := false
var _active := false
var _phase := "idle"
var _elapsed := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _root: Node3D
var _wind: Array[Sprite3D] = []
var _burst: MeshInstance3D
var _dust: Array[MeshInstance3D] = []
var _begin_count := 0
var _impact_count := 0
var _finish_count := 0
var _impacted := false
var _atlas_frame := 0

func setup() -> Dictionary:
	cancel()
	_ready = false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or not parsed.get("assets") is Dictionary:
		return {"ok": false, "reason": "Palm sample configuration is missing"}
	_config = parsed
	_assets = parsed.assets.duplicate(true)
	for id: String in ["wind", "dust", "impact"]:
		var path: String = str(_assets.get(id, ""))
		if not path.begins_with("res://assets/art/mountain_ambush/palm_lab/"):
			return {"ok": false, "reason": "Palm sample asset path is invalid"}
		var texture := load(path) as Texture2D
		if texture == null:
			return {"ok": false, "reason": "Palm sample texture is missing: " + path}
		_textures[id] = texture
	var impact: Texture2D = _textures.impact
	if impact.get_width() != int(_config.atlas.columns) * int(_config.atlas.frame_pixels) or impact.get_height() != int(_config.atlas.rows) * int(_config.atlas.frame_pixels):
		return {"ok": false, "reason": "Palm sample atlas dimensions differ"}
	_ready = true
	return {"ok": true, "reason": ""}

func begin_demo(from: Vector3, to: Vector3) -> void:
	cancel()
	if not _ready:
		return
	_from = to_local(from)
	_to = to_local(to)
	_active = true
	_phase = "flight"
	_elapsed = 0.0
	_impacted = false
	_atlas_frame = 0
	_begin_count += 1
	_root = Node3D.new()
	_root.name = "TransientPalmWind"
	add_child(_root)
	for index: int in range(2):
		var wind := _sprite(_textures.wind, float(_config.wind_size), Color(str(_config.wind_color)))
		wind.name = "PalmWind" + str(index)
		_wind.append(wind)
	_burst = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(_config.impact_size)
	_burst.mesh = quad
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = IMPACT_SHADER
	var impact_material := ShaderMaterial.new()
	impact_material.shader = shader
	impact_material.set_shader_parameter("atlas_tex", _textures.impact)
	impact_material.set_shader_parameter("atlas_grid", Vector2(float(_config.atlas.columns), float(_config.atlas.rows)))
	_burst.material_override = impact_material
	_root.add_child(_burst)
	_burst.name = "EffekseerImpact"
	_burst.position = _to
	_burst.visible = false
	for index: int in range(2):
		var dust := MeshInstance3D.new()
		dust.name = "MaterialMakerDust" + str(index)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		dust.mesh = plane
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = _textures.dust
		mat.albedo_color = Color(str(_config.dust_color))
		mat.albedo_color.a = 0.0
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		dust.material_override = mat
		dust.position = Vector3(_to.x, 0.035 + float(index) * 0.012, _to.z)
		dust.rotation.y = float(index) * 1.71
		_root.add_child(dust)
		_dust.append(dust)
	_update()

func _sprite(texture: Texture2D, world_size: float, color: Color, frame_pixels: int = 0) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = world_size / float(frame_pixels if frame_pixels > 0 else texture.get_width())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.modulate = color
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(sprite)
	return sprite

func step(delta: float) -> void:
	if not _active:
		return
	_elapsed += maxf(0.0, delta)
	if _elapsed >= float(_config.duration):
		_finish_count += 1
		cancel()
		return
	_update()

func _update() -> void:
	var flight: float = float(_config.flight_seconds)
	var progress: float = clampf(_elapsed / flight, 0.0, 1.0)
	for index: int in range(_wind.size()):
		var wind: Sprite3D = _wind[index]
		var offset: float = float(index) * 0.15
		var p: float = clampf(progress - offset, 0.0, 1.0)
		wind.position = _from.lerp(_to, p)
		wind.scale = Vector3.ONE * lerpf(0.30, 1.0, p)
		wind.rotation.z = -0.3 + _elapsed * (1.4 if index == 0 else -1.2)
		wind.modulate.a = sin(p * PI) * (0.90 if index == 0 else 0.48)
		wind.visible = _elapsed < flight
	if _elapsed < flight:
		return
	if not _impacted:
		_impacted = true
		_impact_count += 1
	_phase = "impact" if _elapsed < flight + 0.16 else "dissipating"
	var since: float = _elapsed - flight
	var impact_life: float = float(_config.impact_seconds)
	_burst.visible = since < impact_life
	_atlas_frame = mini(int(_config.atlas.frames) - 1, int(since / impact_life * float(_config.atlas.frames)))
	(_burst.material_override as ShaderMaterial).set_shader_parameter("frame", float(_atlas_frame))
	for index: int in range(_dust.size()):
		var dust: MeshInstance3D = _dust[index]
		var fade: float = clampf(since / float(_config.dust_seconds), 0.0, 1.0)
		dust.scale = Vector3.ONE * lerpf(0.50, float(_config.dust_size), ease(fade, 0.55))
		var mat: StandardMaterial3D = dust.material_override
		mat.albedo_color.a = sin(fade * PI) * (0.42 if index == 0 else 0.20)
		dust.visible = fade < 1.0

func cancel() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null
	_wind.clear()
	_dust.clear()
	_burst = null
	_active = false
	_phase = "idle"
	_elapsed = 0.0

func audit() -> Dictionary:
	var visible_nodes := 0
	for sprite: Sprite3D in _wind:
		if is_instance_valid(sprite) and sprite.visible and sprite.modulate.a > 0.01:
			visible_nodes += 1
	if is_instance_valid(_burst) and _burst.visible and _atlas_frame > 0 and _atlas_frame < 21:
		visible_nodes += 1
	for dust: MeshInstance3D in _dust:
		if is_instance_valid(dust) and dust.visible and (dust.material_override as StandardMaterial3D).albedo_color.a > 0.01:
			visible_nodes += 1
	return {"ready": _ready, "active": _active, "phase": _phase, "elapsed": _elapsed,
		"visible_nodes": visible_nodes, "impact_frame": _atlas_frame,
		"begin_count": _begin_count, "impact_count": _impact_count, "finish_count": _finish_count,
		"live_nodes": _root.get_child_count() if is_instance_valid(_root) else 0,
		"assets": _assets.duplicate(true), "authority": "presentation only",
		"clock": "Stage.step only", "audio_player_count": 0}
