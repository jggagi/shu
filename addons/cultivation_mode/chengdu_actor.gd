extends Node3D
## Selective reuse of Shu's approved daily town models and original clips.
## Presentation samples only; EngineSession / walker own position and actions.

var stage: Node
var role := ""
var skeleton: Skeleton3D
var animator: AnimationPlayer
var model: Node3D
var meshes: Array[MeshInstance3D] = []
var source_path := ""
var idle_clip: StringName
var walk_clip: StringName
var source_anchor := Vector3.ZERO
var display_scale := 1.0
var ground := Vector2.ZERO
var seat_height := 0.0
var elapsed := 0.0
var yaw := 0.0
var previous_point := Vector2.ZERO
var previous_stride := 0.0
var cycle_distance := 101.5
var available := false
var sampled_clip := ""
var sampled_seconds := 0.0
var contacts: Array[MeshInstance3D] = []
var floor_height := 0.0


func setup(host: Node, actor_role: String, profile: Dictionary, at: Vector2) -> void:
	stage = host
	role = actor_role
	source_path = str(profile.model)
	ground = at
	previous_point = at
	idle_clip = StringName(str(profile.idle))
	walk_clip = StringName(str(profile.get("walk", "")))
	display_scale = float(profile.get("scale", 1.0))
	var anchor: Array = profile.get("anchor", [0, 0, 0])
	source_anchor = Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2]))
	seat_height = float(profile.get("seat_height", 0.0))
	yaw = float(profile.get("yaw", 0.0))
	cycle_distance = float(profile.get("cycle_distance", 101.5))
	position = stage.call("logical_to_world", ground) + Vector3.UP * seat_height
	rotation.y = yaw
	set_process(false)
	if not ResourceLoader.exists(source_path):
		return
	var scene := load(source_path) as PackedScene
	if scene == null:
		return
	model = scene.instantiate() as Node3D
	add_child(model)
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		animator = node as AnimationPlayer
		break
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	if skeleton == null or animator == null or not animator.has_animation(idle_clip):
		return
	_prepare_materials()
	model.scale = Vector3.ONE * display_scale
	model.position = -source_anchor * display_scale
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_sample(idle_clip, 0.0)
	for bone_name: String in ["foot.L", "foot.R"]:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var sole := _bone_position(index)
		floor_height = sole.y if contacts.is_empty() else minf(floor_height, sole.y)
		contacts.append(_make_contact())
	available = true
	_sync_contacts()


func sync(point: Vector2, stride: float, walking: bool, seconds: float) -> void:
	if not available:
		return
	if role == "player":
		var travel := maxf(stride - previous_stride, 0.0)
		var direction := point - previous_point
		if walking and direction.length_squared() > 0.25:
			yaw = rotate_toward(yaw, atan2(direction.x, direction.y), travel * 0.085)
		rotation.y = yaw
		ground = point
		position = stage.call("logical_to_world", ground)
		var clip := walk_clip if walking and animator.has_animation(walk_clip) else idle_clip
		var length := animator.get_animation(clip).length
		var phase := fposmod(stride / cycle_distance, 1.0) if clip == walk_clip else fposmod(seconds, length) / length
		_sample(clip, phase * length)
		previous_point = point
		previous_stride = stride
	else:
		_sample(idle_clip, fposmod(seconds, animator.get_animation(idle_clip).length))
	_sync_contacts()


func _sample(clip: StringName, seconds: float) -> void:
	animator.play(clip)
	animator.seek(seconds, true)
	animator.pause()
	skeleton.force_update_all_bone_transforms()
	sampled_clip = str(clip)
	sampled_seconds = seconds


func _make_contact() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.25, 0.43)
	node.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.5)
	fade.fill_to = Vector2(0.5, 1)
	mat.albedo_texture = fade
	mat.albedo_color = Color(0.16, 0.18, 0.13, 0.35)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _sync_contacts() -> void:
	var names: Array[String] = ["foot.L", "foot.R"]
	for index: int in range(contacts.size()):
		var at := _bone_position(skeleton.find_bone(names[index]))
		# Contacts are actor children. Local coordinates work before the view is
		# attached and follow its yaw without global-transform access.
		contacts[index].position = Vector3(at.x, 0.004 - position.y, at.z + 0.065)
		var lift := maxf(at.y - floor_height, 0.0)
		(contacts[index].material_override as StandardMaterial3D).albedo_color.a = lerpf(0.36, 0.08, clampf(lift / 0.14, 0.0, 1.0))


func _bone_position(index: int) -> Vector3:
	# Bone global poses are relative to Skeleton3D, not the scene tree. Compose
	# the authored local node chain so detached UI construction stays valid.
	var relative := Transform3D.IDENTITY
	var cursor: Node = skeleton
	while cursor != null and cursor != self:
		if cursor is Node3D:
			relative = (cursor as Node3D).transform * relative
		cursor = cursor.get_parent()
	return relative * skeleton.get_bone_global_pose(index).origin


func _prepare_materials() -> void:
	# Retain original embedded texture payloads. Match the approved Compatibility
	# adapter's vertex-color conversion once at runtime, never rebake the GLBs.
	for instance: MeshInstance3D in meshes:
		var source := instance.mesh
		var local_mesh := ArrayMesh.new()
		for surface: int in range(source.get_surface_count()):
			var arrays := source.surface_get_arrays(surface)
			var original := instance.get_active_material(surface) as StandardMaterial3D
			var mat := original.duplicate() as StandardMaterial3D if original != null else StandardMaterial3D.new()
			if arrays[Mesh.ARRAY_COLOR] != null:
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				if not colors.is_empty():
					for index: int in range(colors.size()):
						colors[index] = colors[index].linear_to_srgb()
					arrays[Mesh.ARRAY_COLOR] = colors
					mat.vertex_color_use_as_albedo = true
					mat.vertex_color_is_srgb = true
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.roughness = maxf(mat.roughness, 0.82) if role == "player" else clampf(mat.roughness, 0.28, 1.0)
			mat.metallic = 0.0
			local_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			local_mesh.surface_set_material(surface, mat)
		instance.mesh = local_mesh


func audit() -> Dictionary:
	return {"available": available, "role": role, "model": source_path,
		"bone_count": skeleton.get_bone_count() if skeleton != null else 0,
		"mesh_count": meshes.size(), "clip": sampled_clip, "seconds": sampled_seconds,
		"point": ground, "world_position": position, "yaw": yaw,
		"model_scale": display_scale, "source_anchor": source_anchor,
		"time_authority": "walker distance for walk; stage controlled elapsed for idle",
		"foot_contacts": contacts.size()}
