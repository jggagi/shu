extends Node
## Fixed-camera painted street calibration. Presentation only: the original
## walking plane, Camera3D projection, navigation and Session remain authoritative.
## Opaque proxies sample the same screen pixel as the distant painted backdrop.
## They therefore contribute actual depth without displaying the old materials.
## This is one painted view, not a relightable scene or a reflected 3D town.

const NaturalCharacters = preload("res://addons/cultivation_mode/town_natural_characters.gd")
const VolumeCharacter = preload("res://addons/cultivation_mode/town_volume_character.gd")
const VolumeCast = preload("res://addons/cultivation_mode/town_volume_cast.gd")
const PAINTING_PATH := "res://assets/art/town_painted_street/painted-street.png"
const SOURCE := "res://assets/art/town_painted_street/source.json"
const MERCHANT_SHEET := "res://assets/art/town_painted_street/tea-seller-life.svg"
const MERCHANT_PALETTE_SOURCE := "res://assets/art/town_painted_street/palette-source.json"
const HIDDEN_ENVIRONMENT_LAYER: int = 1 << 18
const PRESENTATION_LAYER: int = 1
const BACKDROP_DISTANCE: float = 50.0
const DISPLAY := Vector2(1280, 720)
const PAINT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D painting : source_color, filter_linear, repeat_disable;
uniform vec2 player_uv = vec2(0.5);
uniform float reveal = 0.0;
void fragment() {
    vec2 delta = (SCREEN_UV - player_uv) * vec2(1280.0, 720.0);
    float near_player = 1.0 - smoothstep(44.0, 92.0, length(delta));
    float pattern = fract(sin(dot(floor(SCREEN_UV * vec2(1280.0, 720.0)),
        vec2(12.9898, 78.233))) * 43758.5453);
    if (pattern < near_player * reveal * 0.88) { discard; }
    ALBEDO = texture(painting, SCREEN_UV).rgb;
}
"""

var _stage: Node
var _world: Node3D
var _camera: Camera3D
var _painting: Texture2D
var _shader: Shader
var _plain_material: ShaderMaterial
var _proxy_root: Node3D
var _backdrop: MeshInstance3D
var _original_geometry: Array[Dictionary] = []
var _preserved: Array[GeometryInstance3D] = []
var _actors: Array[Sprite3D] = []
var _actor_planes: Array[Dictionary] = []
var _reveals: Array[Dictionary] = []
var _original_camera_mask: int = 0
var _reflection_view: SubViewport
var _reflection_update_mode: int = SubViewport.UPDATE_ALWAYS
var _enabled: bool = false
var _requested: bool = false
var _setup_complete: bool = false
var _proxy_count: int = 0
var _merchant_frames: Array[Texture2D] = []
var _merchant_frame_index: int = -1
var _natural_characters = NaturalCharacters.new()
var _volume_character: Node3D
var _volume_cast: Node3D


func setup(stage: Node) -> void:
	if _setup_complete or not is_instance_valid(stage):
		return
	_stage = stage
	_world = stage.get("world_root") as Node3D
	_camera = stage.get("camera") as Camera3D
	if not is_instance_valid(_world) or not is_instance_valid(_camera):
		return
	_original_camera_mask = _camera.cull_mask
	# Loading by the recorded res:// path lets a missing candidate fail safely
	# back to the retained 3D view rather than creating an empty painted scene.
	if ResourceLoader.exists(PAINTING_PATH):
		_painting = load(PAINTING_PATH) as Texture2D
	if _painting == null:
		_setup_complete = true
		return
	_shader = Shader.new()
	_shader.code = PAINT_SHADER
	_plain_material = _make_material()
	_build_merchant_frames()
	_collect_preserved_geometry()
	# Snapshot before adding any helper-owned nodes. These references preserve
	# the old scene intact for the 3D comparison and later source review.
	var old_geometry: Array[Node] = _world.find_children("*", "GeometryInstance3D", true, false)
	for item: Node in old_geometry:
		var geometry := item as GeometryInstance3D
		if geometry != null and not _preserved.has(geometry):
			_original_geometry.append({"node": geometry, "layers": geometry.layers})
	_proxy_root = Node3D.new()
	_proxy_root.name = "PaintedStreetDepthProxies"
	_world.add_child(_proxy_root)
	_proxy_root.visible = false
	for item: Node in old_geometry:
		var mesh := item as MeshInstance3D
		if mesh != null and _needs_proxy(mesh):
			_add_proxy(mesh)
	_add_ground_receiver()
	_add_backdrop()
	_capture_reflection()
	_setup_complete = true
	_volume_character = VolumeCharacter.new()
	_volume_character.name = "JiangVolumeCharacter"
	_world.add_child(_volume_character)
	_volume_character.call("setup", _stage)
	_volume_cast = VolumeCast.new()
	_volume_cast.name = "TownVolumeCast"
	_world.add_child(_volume_cast)
	_volume_cast.call("setup", _stage)


func apply(enabled: bool) -> void:
	_requested = enabled
	_enabled = enabled and _painting != null and _setup_complete
	if not is_instance_valid(_camera):
		return
	_camera.cull_mask = _original_camera_mask & ~HIDDEN_ENVIRONMENT_LAYER if _enabled else _original_camera_mask
	for row: Dictionary in _original_geometry:
		var geometry := row.node as GeometryInstance3D
		if is_instance_valid(geometry):
			geometry.layers = HIDDEN_ENVIRONMENT_LAYER if _enabled else int(row.layers)
	if is_instance_valid(_proxy_root):
		_proxy_root.visible = _enabled
	if is_instance_valid(_backdrop):
		_backdrop.visible = _enabled
	_capture_reflection()
	_set_reflection_mode()
	if is_instance_valid(_volume_character):
		_volume_character.call("apply", _enabled)
	if is_instance_valid(_volume_cast):
		_volume_cast.call("apply", _enabled)
	if _enabled:
		sync()
	else:
		_natural_characters.restore(_stage)
		_restore_merchant_frame()
		for row: Dictionary in _actor_planes:
			var actor := row.node as Sprite3D
			if is_instance_valid(actor):
				actor.billboard = int(row.billboard)
				actor.scale = row.scale
	# The host's existing _apply_lighting/_update_actor restores its own actor
	# shade and tint when returning to the 3D comparison. Do not overwrite it.


func sync() -> void:
	if not _enabled or not is_instance_valid(_stage):
		return
	# The stage may be authored before entering the tree, and create its shared
	# reflection viewport later in _ready. Capture and stop that late instance.
	_capture_reflection()
	_set_reflection_mode()
	var slot: int = int(_stage.get("_slot"))
	var dusk: float = clampf(float(slot - 3) / 2.0, 0.0, 1.0)
	var tint := Color(1.0, 0.97, 0.91).lerp(Color("#d6bbad"), dusk * 0.38)
	for row: Dictionary in _actor_planes:
		var actor := row.node as Sprite3D
		if is_instance_valid(actor):
			actor.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			var original_scale: Vector3 = row.scale
			actor.scale = Vector3(original_scale.x, original_scale.y / maxf(absf(_camera.global_basis.y.y), 0.1), original_scale.z)
	for actor: Sprite3D in _actors:
		if is_instance_valid(actor):
			actor.shaded = false
			actor.modulate = tint
	if _natural_characters.available():
		_natural_characters.apply(_stage)
	else:
		_sync_merchant_frame()
	if is_instance_valid(_volume_character):
		_volume_character.call("sync")
	if is_instance_valid(_volume_cast):
		_volume_cast.call("sync")
	var point: Vector2 = _stage.get("_player")
	var height: float = float(_stage.call("_actor_height", "player")) * 0.5
	var center: Vector2 = _stage.call("logical_to_screen", point, height)
	if center.x < 0.0:
		return
	for entry: Dictionary in _reveals:
		var material := entry.material as ShaderMaterial
		var roof_row: Dictionary = entry.row
		material.set_shader_parameter("player_uv", center / DISPLAY)
		material.set_shader_parameter("reveal", float(roof_row.get("fade", 0.0)))


func audit() -> Dictionary:
	return {"requested": _requested, "enabled": _enabled,
		"painting_available": _painting != null, "painting": PAINTING_PATH, "source": SOURCE,
		"painting_size": _painting.get_size() if _painting != null else Vector2.ZERO,
		"mode": "fixed_camera_painting_with_opaque_projected_depth_proxies" if _enabled else "retained_3d_comparison",
		"depth_proxy_count": _proxy_count, "hidden_environment_count": _original_geometry.size(),
		"preserved_geometry_count": _preserved.size(), "reveal_groups": _reveals.size(),
		"camera_cull_mask": _camera.cull_mask if is_instance_valid(_camera) else 0,
		"original_camera_cull_mask": _original_camera_mask,
		"reflection_paused": _enabled and is_instance_valid(_reflection_view) and _reflection_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"environment_light": "painted into the fixed illustration; no realtime whole-scene relighting",
		"actor_planes": "three opaque skinned characters; legacy billboards retained for A comparison" if _enabled else "original billboards restored",
		"actor_light": "three characters shaded by real scene light; soft sole contacts" if _enabled else "retained 3D actor lighting",
		"natural_characters": _natural_characters.audit(),
		"volume_character": _volume_character.call("audit") if is_instance_valid(_volume_character) else {},
		"volume_cast": _volume_cast.call("audit") if is_instance_valid(_volume_cast) else {},
		"merchant_palette": {"method": "nativeSVG trouser outlines; unchanged shoes and foot anchors",
			"sheet": MERCHANT_SHEET, "source": MERCHANT_PALETTE_SOURCE,
			"frame_count": _merchant_frames.size(), "frame_size": Vector2(80, 112),
			"foot_anchor": Vector2(40, 104), "frame_index": _merchant_frame_index,
			"active": _enabled and not _merchant_frames.is_empty() and not _natural_characters.available(),
			"phase_authority": "original seller life frame_index_at(stage ambient_elapsed)"},
		"occlusion": "retained world geometry at fixed camera; silhouette calibration still requires image review",
		"reflection": "painted water only; realtime town mirror disabled" if _enabled else "retained 3D water pipeline"}


func _build_merchant_frames() -> void:
	if not ResourceLoader.exists(MERCHANT_SHEET):
		return
	var sheet := load(MERCHANT_SHEET) as Texture2D
	if sheet == null:
		return
	for index: int in range(6):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(index * 80, 0, 80, 112)
		frame.filter_clip = true
		_merchant_frames.append(frame)


func _sync_merchant_frame() -> void:
	if _merchant_frames.is_empty():
		return
	var actors: Dictionary = _stage.get("actor_nodes")
	var merchant := actors.get("tea_seller") as Sprite3D
	var life := _stage.get("_seller_life") as RefCounted
	if not is_instance_valid(merchant) or not is_instance_valid(life):
		return
	var phase: float = float(_stage.get("ambient_elapsed"))
	_merchant_frame_index = int(life.call("frame_index_at", phase))
	merchant.texture = _merchant_frames[clampi(_merchant_frame_index, 0, _merchant_frames.size() - 1)]


func _restore_merchant_frame() -> void:
	if not is_instance_valid(_stage) or _merchant_frame_index < 0:
		return
	var actors: Dictionary = _stage.get("actor_nodes")
	var merchant := actors.get("tea_seller") as Sprite3D
	var life := _stage.get("_seller_life") as RefCounted
	if is_instance_valid(merchant) and is_instance_valid(life):
		merchant.texture = life.call("frame_at", float(_stage.get("ambient_elapsed"))) as Texture2D
	_merchant_frame_index = -1


func _collect_preserved_geometry() -> void:
	var visible_actors: Dictionary = _stage.get("actor_nodes")
	for item: Variant in visible_actors.values():
		_preserve(item)
		if item is Sprite3D:
			_actors.append(item as Sprite3D)
			_actor_planes.append({"node": item, "billboard": (item as Sprite3D).billboard, "scale": (item as Sprite3D).scale})
	var foot_contacts: Dictionary = _stage.get("shadow_nodes")
	for item: Variant in foot_contacts.values():
		_preserve(item)
	var patron := _stage.get("_tea_patron") as Sprite3D
	if is_instance_valid(patron):
		_preserve(patron)
		_actors.append(patron)
	_preserve(_stage.get("_patron_shadow"))


func _preserve(item: Variant) -> void:
	if item is GeometryInstance3D and not _preserved.has(item):
		_preserved.append(item as GeometryInstance3D)


func _needs_proxy(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null or not mesh.visible or _preserved.has(mesh):
		return false
	# Small vessels, lattice marks, detached foliage, boats and broad riverbank
	# geometry do not need new depth in this street calibration. A conservative
	# set avoids occluding an actor where the painted contour has moved.
	var bounds: AABB = mesh.get_aabb()
	var dimensions: Vector3 = bounds.size * mesh.scale.abs()
	if maxf(dimensions.x, maxf(dimensions.y, dimensions.z)) < 0.44:
		return false
	var parent: Node = mesh.get_parent()
	while parent != null and parent != _world:
		var label := str(parent.name)
		if label == "TeaHouseOpenServiceBay" or label == "SharedTeaTableAndTwoBenches" or label.begins_with("BackgroundHouse") or label == "NorthShop" or label == "MarketShelter":
			return true
		parent = parent.get_parent()
	return false


func _add_proxy(source: MeshInstance3D) -> void:
	var proxy := MeshInstance3D.new()
	proxy.name = "PaintDepth_%04d" % _proxy_count
	proxy.mesh = source.mesh
	proxy.transform = _relative_to_world(source)
	proxy.material_override = _material_for_source(source)
	proxy.layers = PRESENTATION_LAYER
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_proxy_root.add_child(proxy)
	_proxy_count += 1


func _relative_to_world(source: Node3D) -> Transform3D:
	# Equivalent to a world-root-relative global transform without requiring
	# the scene to have entered the tree during the host's setup() call.
	var result: Transform3D = source.transform
	var parent: Node = source.get_parent()
	while parent != null and parent != _world:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func _material_for_source(source: MeshInstance3D) -> ShaderMaterial:
	var rows: Array = _stage.get("roof_rows")
	for row: Dictionary in rows:
		var body := row.get("body") as Node
		if body == source or (is_instance_valid(body) and body.is_ancestor_of(source)):
			for entry: Dictionary in _reveals:
				if entry.body == body:
					return entry.material as ShaderMaterial
			var material: ShaderMaterial = _make_material()
			_reveals.append({"body": body, "row": row, "material": material})
			return material
	return _plain_material


func _make_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("painting", _painting)
	return material


func _add_ground_receiver() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(46, 46)
	var ground := MeshInstance3D.new()
	ground.name = "PaintedGroundContactPlane"
	ground.mesh = mesh
	ground.position.y = -0.035
	ground.material_override = _plain_material
	ground.layers = PRESENTATION_LAYER
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_proxy_root.add_child(ground)
	_proxy_count += 1


func _add_backdrop() -> void:
	var mesh := QuadMesh.new()
	var half_height: float = tan(deg_to_rad(_camera.fov * 0.5)) * BACKDROP_DISTANCE
	mesh.size = Vector2(half_height * DISPLAY.x / DISPLAY.y * 2.0, half_height * 2.0)
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "FixedPaintedStreetBackdrop"
	_backdrop.mesh = mesh
	_backdrop.material_override = _plain_material
	_backdrop.position.z = -BACKDROP_DISTANCE
	_backdrop.layers = PRESENTATION_LAYER
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_backdrop.visible = false
	_camera.add_child(_backdrop)


func _capture_reflection() -> void:
	if not is_instance_valid(_stage):
		return
	var reflection := _stage.get("_river_reflection") as Node
	if not is_instance_valid(reflection):
		return
	var candidate := reflection.get("reflection_viewport") as SubViewport
	if is_instance_valid(candidate) and candidate != _reflection_view:
		_reflection_view = candidate
		_reflection_update_mode = int(candidate.render_target_update_mode)


func _set_reflection_mode() -> void:
	if is_instance_valid(_reflection_view):
		_reflection_view.render_target_update_mode = SubViewport.UPDATE_DISABLED if _enabled else _reflection_update_mode
