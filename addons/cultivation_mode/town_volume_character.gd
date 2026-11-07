extends Node3D
## One real skinned protagonist in the fixed painted town. The existing walker
## owns movement and distance; the stage owns idle time. No independent ticker.

const MODEL := "res://assets/art/town_volume_character/jiang-town.glb"
const SOURCE := "res://assets/art/town_volume_character/source.json"
const DISPLAY_HEIGHT: float = 1.90
const SOURCE_HEIGHT: float = 2.096427
const IDLE: StringName = &"TownIdle"
const WALK: StringName = &"TownWalk"

var _stage: Node
var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _enabled := false
var _available := false
var _yaw := 0.0
var _point := Vector2.ZERO
var _last_stride := -1.0
var _phase := 0.0
var _clip: StringName = IDLE
var _cycle_distance := 90.0
var _foot_origin := Vector3.ZERO
var _review_yaw := false
var _review_light := false
var _lit := true
var _warm_surfaces := 0
var _foot_shadows: Dictionary = {}
var _ankle_floor_height := 0.0


func setup(stage: Node) -> void:
	_stage = stage
	set_process(false)
	if not ResourceLoader.exists(MODEL):
		return
	var packed := load(MODEL) as PackedScene
	if packed == null:
		return
	_model = packed.instantiate() as Node3D
	add_child(_model)
	for child: Node in _model.find_children("*", "Skeleton3D", true, false):
		_skeleton = child as Skeleton3D
		break
	for child: Node in _model.find_children("*", "AnimationPlayer", true, false):
		_player = child as AnimationPlayer
		break
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.layers = 3
		_meshes.append(mesh)
	if _skeleton == null or _player == null or _skeleton.get_bone_count() != 22:
		return
	if not _player.has_animation(IDLE) or not _player.has_animation(WALK):
		return
	_restore_source_vertex_colors()
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_sample(IDLE, 0.0)
	var inverse := _model.global_transform.affine_inverse()
	var right := inverse * _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("foot.R")).origin
	var left := inverse * _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("foot.L")).origin
	_foot_origin = (right + left) * 0.5
	_foot_origin.y = 0.000216
	var factor := DISPLAY_HEIGHT / SOURCE_HEIGHT
	_model.scale = Vector3.ONE * factor
	_model.position = -_foot_origin * factor
	_skeleton.force_update_all_bone_transforms()
	_ankle_floor_height = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("foot.R")).origin).y
	_create_foot_contacts()
	if FileAccess.file_exists(SOURCE):
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if record is Dictionary:
			_cycle_distance = float(record.get("walk_cycle_source_distance", 1.24)) * factor * 80.0
	_available = true
	visible = false
	_point = stage.get("_player")
	position = stage.call("logical_to_world", _point)


func apply(enabled: bool) -> void:
	_enabled = enabled and _available
	visible = _enabled
	if not _enabled and is_instance_valid(_stage):
		var sprite := (_stage.get("actor_nodes") as Dictionary).get("player") as Sprite3D
		if sprite != null:
			sprite.visible = true
		var old_contact := (_stage.get("shadow_nodes") as Dictionary).get("player") as MeshInstance3D
		if old_contact != null:
			old_contact.visible = true
	if _enabled:
		sync()


func sync() -> void:
	if not _enabled:
		return
	var point: Vector2 = _stage.get("_player")
	var stride: float = _stage.get("_stride")
	var walking: bool = bool(_stage.get("_walking")) and bool(_stage.get("_active"))
	var distance := maxf(stride - _last_stride, 0.0) if _last_stride >= 0.0 else 0.0
	if not _review_yaw:
		var heading := point - _point
		var view := _stage.get("_view") as Control
		if walking and is_instance_valid(view):
			var route: Array = view.get("route")
			if not route.is_empty():
				heading = (route[0] as Vector2) - point
		if walking and heading.length_squared() > 0.25:
			var target_yaw := atan2(heading.x, heading.y)
			_yaw = rotate_toward(_yaw, target_yaw, distance * 0.085)
	rotation.y = _yaw
	position = _stage.call("logical_to_world", point)
	_phase = fposmod(stride / _cycle_distance, 1.0) if walking else fposmod(float(_stage.get("ambient_elapsed")), _player.get_animation(IDLE).length) / _player.get_animation(IDLE).length
	_clip = WALK if walking else IDLE
	_sample(_clip, _phase * _player.get_animation(_clip).length)
	_sync_foot_contacts()
	_point = point
	_last_stride = stride
	var sprite := (_stage.get("actor_nodes") as Dictionary).get("player") as Sprite3D
	if sprite != null:
		sprite.visible = false
	var old_caster := (_stage.get("_actor_casters") as Dictionary).get("player") as Sprite3D
	if old_caster != null:
		old_caster.visible = false
	var old_contact := (_stage.get("shadow_nodes") as Dictionary).get("player") as MeshInstance3D
	if old_contact != null:
		old_contact.visible = false


func _sample(clip: StringName, seconds: float) -> void:
	_player.play(clip)
	_player.seek(seconds, true)
	_player.pause()
	_skeleton.force_update_all_bone_transforms()


func get_presentation_state() -> Dictionary:
	return {"yaw": _yaw}


func set_presentation_state(value: Dictionary) -> void:
	_yaw = float(value.get("yaw", _yaw))
	rotation.y = _yaw


func get_model_root() -> Node3D:
	return _model


func set_review_yaw(radians: float) -> void:
	_review_yaw = true
	_yaw = radians
	rotation.y = radians


func clear_review_yaw() -> void:
	_review_yaw = false


func set_review_lighting(enabled: bool) -> void:
	_review_light = true
	_lit = enabled
	for material: StandardMaterial3D in _materials:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if enabled else BaseMaterial3D.SHADING_MODE_UNSHADED


func clear_review_lighting() -> void:
	set_review_lighting(true)
	_review_light = false


func foot_bones() -> Dictionary:
	var result := {}
	if _skeleton != null:
		for bone: String in ["foot.L", "foot.R"]:
			result[bone] = _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin
	return result


func audit() -> Dictionary:
	return {"available": _available, "enabled": _enabled, "model": MODEL, "source": SOURCE,
		"mesh_count": _meshes.size(), "bone_count": _skeleton.get_bone_count() if _skeleton != null else 0,
		"animation": str(_clip), "phase": _phase, "yaw": _yaw, "foot_position": position,
		"scale": _model.scale if _model != null else Vector3.ZERO, "display_height": DISPLAY_HEIGHT,
		"cycle_distance": _cycle_distance, "lighting_enabled": _lit, "warm_surfaces": _warm_surfaces,
		"clips": _player.get_animation_list() if _player != null else PackedStringArray(),
		"foot_bones": foot_bones(), "contact_shadow": "two soft sole contacts follow real ankle positions and fade on lift; not a shape-cast shadow",
		"time_authority": "host travelled distance for walking; existing stage ambient_elapsed for idle",
		"review_override": _review_yaw or _review_light}


func _create_foot_contacts() -> void:
	var original := (_stage.get("shadow_nodes") as Dictionary).get("player") as MeshInstance3D
	if original == null:
		return
	for bone: String in ["foot.L", "foot.R"]:
		var contact := MeshInstance3D.new()
		contact.name = "SoleContact_" + bone.replace(".", "_")
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.25, 0.43)
		contact.mesh = plane
		contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		contact.material_override = original.material_override.duplicate() as StandardMaterial3D
		add_child(contact)
		_foot_shadows[bone] = contact


func _sync_foot_contacts() -> void:
	var feet := foot_bones()
	for bone: String in _foot_shadows:
		var contact := _foot_shadows[bone] as MeshInstance3D
		var ankle: Vector3 = feet[bone]
		var lift := maxf(ankle.y - _ankle_floor_height, 0.0)
		var toe := global_basis * Vector3(0.0, 0.0, 0.065)
		contact.global_position = Vector3(ankle.x + toe.x, 0.003, ankle.z + toe.z)
		var material := contact.material_override as StandardMaterial3D
		material.albedo_color = Color(0.16, 0.18, 0.13, lerpf(0.38, 0.08, clampf(lift / 0.14, 0.0, 1.0)))


func _restore_source_vertex_colors() -> void:
	# Same Compatibility color conversion as the approved source adapter. Copies
	# only runtime surfaces; the approved GLB and its textures stay unchanged.
	for instance: MeshInstance3D in _meshes:
		var source := instance.mesh
		var local_mesh := ArrayMesh.new()
		for surface: int in range(source.get_surface_count()):
			var arrays := source.surface_get_arrays(surface)
			var original := instance.get_active_material(surface) as StandardMaterial3D
			var material := original.duplicate() as StandardMaterial3D if original != null else StandardMaterial3D.new()
			if arrays[Mesh.ARRAY_COLOR] != null:
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				if not colors.is_empty():
					for index: int in range(colors.size()):
						colors[index] = colors[index].linear_to_srgb()
					arrays[Mesh.ARRAY_COLOR] = colors
					material.vertex_color_use_as_albedo = true
					material.vertex_color_is_srgb = true
					_warm_surfaces += 1
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.roughness = maxf(material.roughness, 0.82)
			material.metallic = 0.0
			_materials.append(material)
			local_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			local_mesh.surface_set_material(surface, material)
		instance.mesh = local_mesh
