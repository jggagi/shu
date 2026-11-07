extends Node3D
## The two town NPCs share the stage's already-controlled ambient phase.
## The optional attention response is advanced explicitly by the host. It owns
## no process/timer, movement, game time, interaction or disk-save authority.

const SOURCE := "res://assets/art/town_volume_cast/source.json"
const ROLES: Array[String] = ["tea_seller", "tea_patron"]
const ATTENTION_LIMIT: float = PI * 35.0 / 180.0
const ATTENTION_SPEED: float = PI * 52.0 / 180.0
const RETURN_SPEED: float = PI * 65.0 / 180.0
const REJOIN_SECONDS: float = 0.35

var _stage: Node
var _actors: Dictionary = {}
var _available := false
var _enabled := false
var _review_times: Dictionary = {}
var _review_lights: Dictionary = {}
var _attention_enabled := false
var _attention_target_valid := false
var _attention_target := Vector3.ZERO
var _conversation_role := ""
var _attention_advances := 0


func setup(stage: Node) -> void:
	_stage = stage
	set_process(false)
	visible = false
	if not FileAccess.file_exists(SOURCE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not data is Dictionary:
		return
	var profiles: Dictionary = data.get("actors", {})
	for role: String in ROLES:
		var profile: Dictionary = profiles.get(role, {})
		if not _load_actor(role, profile):
			return
	_available = _actors.size() == ROLES.size()


func _load_actor(role: String, profile: Dictionary) -> bool:
	var path := str(profile.get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var root := Node3D.new()
	root.name = "VolumeTeaSeller" if role == "tea_seller" else "VolumeTeaPatron"
	add_child(root)
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	var meshes: Array[MeshInstance3D] = []
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		break
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.layers = 3
		meshes.append(mesh)
	var clip := StringName(str(profile.get("clip", "")))
	if skeleton == null or player == null or meshes.is_empty() or not player.has_animation(clip):
		return false
	var period := float(profile.get("period", 14.0 if role == "tea_seller" else 12.0))
	var bone_indices := {}
	for bone: String in ["pelvis", "spine", "chest", "neck", "head", "foot.L", "foot.R", "hand.L", "hand.R"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			return false
		bone_indices[bone] = index
	var skinned_mesh_count := 0
	var surface_count := 0
	for mesh: MeshInstance3D in meshes:
		var array_mesh := mesh.mesh as ArrayMesh
		if array_mesh == null:
			return false
		if mesh.skin != null:
			skinned_mesh_count += 1
		surface_count += mesh.mesh.get_surface_count()
		# The adapter rebuilds surfaces without morph targets; the retained assets
		# have none. Reject a different payload instead of silently dropping one.
		if array_mesh.get_blend_shape_count() != 0:
			return false
	var clip_length := player.get_animation(clip).length
	if period <= 0.0 or absf(clip_length - period) > 0.001 or skinned_mesh_count != meshes.size():
		return false
	var materials := _prepare_materials(meshes)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.seek(0.0, true)
	player.pause()
	skeleton.force_update_all_bone_transforms()
	var factor := float(profile.get("display_scale", 1.0))
	var anchor := _vector(profile.get("source_anchor", [0, 0, 0]))
	model.scale = Vector3.ONE * factor
	model.position = -anchor * factor
	var sprite := _legacy_sprite(role)
	if sprite == null:
		return false
	root.position = sprite.position
	if role == "tea_seller":
		# The stage can enter the tree before set_actor_frames initializes the
		# legacy sprite. Read the original map's authoritative interaction point.
		var definition: Dictionary = _stage.get("_definition")
		var coordinates: Array = definition.get("interactions", {}).get("tea_seller", {}).get("position", [])
		if coordinates.size() != 2:
			return false
		root.position = _stage.call("logical_to_world", Vector2(float(coordinates[0]), float(coordinates[1])))
	root.rotation.y = 0.0 if role == "tea_seller" else PI * 0.5
	var floor_y := root.position.y + (float(profile.get("source_floor_y", 0.0)) - anchor.y) * factor
	var contacts := _create_contacts(root, skeleton)
	_actors[role] = {"root": root, "model": model, "skeleton": skeleton, "player": player,
		"meshes": meshes, "materials": materials, "profile": profile, "path": path,
		"clip": clip, "period": period, "bone_indices": bone_indices,
		"anchor": anchor, "scale": factor, "floor_y": floor_y, "contacts": contacts,
		"phase": 0.0, "seconds": 0.0, "attention": _new_attention(),
		"payload": {"loaded": true, "skinned_mesh_count": skinned_mesh_count,
			"surface_count": surface_count, "bone_count": skeleton.get_bone_count(),
			"clip_length": clip_length, "required_bones_present": true, "morph_targets": 0}}
	return true


func apply(enabled: bool) -> void:
	_enabled = enabled and _available
	visible = _enabled
	if _enabled:
		sync()
	else:
		for role: String in ROLES:
			var sprite := _legacy_sprite(role)
			if sprite != null:
				sprite.visible = true
		var contact := (_stage.get("shadow_nodes") as Dictionary).get("tea_seller") as MeshInstance3D
		if contact != null:
			contact.visible = true


func sync() -> void:
	if not _enabled:
		return
	var elapsed := float(_stage.get("ambient_elapsed"))
	for role: String in ROLES:
		var row: Dictionary = _actors[role]
		var period := float(row.period)
		var sampled := fposmod(maxf(elapsed, 0.0), period)
		var state: Dictionary = row.attention
		if _attention_enabled and str(state.mode) != "ambient":
			sampled = float(state.cursor)
		var review := _review_times.has(role)
		if review:
			sampled = fposmod(maxf(float(_review_times[role]), 0.0), period)
		_sample_actor(row, sampled)
		var skeleton := row.skeleton as Skeleton3D
		if not review and _attention_enabled:
			if str(state.mode) == "rejoin":
				_blend_rest_to_ambient(row, fposmod(maxf(elapsed, 0.0), period), float(state.rejoin))
			_apply_attention_yaw(row, float(state.yaw))
		skeleton.force_update_all_bone_transforms()
		row.phase = sampled / period
		row.seconds = sampled
		_sync_contacts(row)
		var sprite := _legacy_sprite(role)
		if sprite != null:
			sprite.visible = false
	var caster := (_stage.get("_actor_casters") as Dictionary).get("tea_seller") as Sprite3D
	if caster != null:
		caster.visible = false
	var patron_caster := _stage.get("_patron_shadow") as Sprite3D
	if patron_caster != null:
		patron_caster.visible = false
	var contact := (_stage.get("shadow_nodes") as Dictionary).get("tea_seller") as MeshInstance3D
	if contact != null:
		contact.visible = false


func _new_attention() -> Dictionary:
	return {"mode": "ambient", "cursor": 0.0, "yaw": 0.0,
		"near": false, "requested": false, "rejoin": 0.0}


func set_attention_enabled(enabled: bool) -> void:
	# Opt-in per content pack; legacy town packs retain their exact old render.
	if _attention_enabled == enabled:
		return
	_attention_enabled = enabled
	if not enabled:
		for role: String in _actors:
			_actors[role].attention = _new_attention()
		_attention_target_valid = false
		_conversation_role = ""
	sync()


func set_attention_state(target_role: String, target_world: Vector3, conversational: bool) -> void:
	if not target_world.is_finite():
		return
	_attention_target_valid = true
	_attention_target = target_world
	_conversation_role = target_role if conversational and ROLES.has(target_role) else ""
	# Intent changes never move the pose. Static remains frozen, including when
	# a dialogue rebuild changes the target before the next host advance.


func clear_attention_state() -> void:
	_attention_target_valid = false
	_conversation_role = ""


func advance_presentation(delta: float, allow_motion: bool) -> void:
	if not _attention_enabled or not _enabled or not allow_motion or not is_finite(delta) or delta <= 0.0:
		return
	var step := minf(delta, 0.05)
	_attention_advances += 1
	for role: String in ROLES:
		var row: Dictionary = _actors[role]
		var state: Dictionary = row.attention
		var requested := _wants_attention(role, row)
		state.requested = requested
		var mode := str(state.mode)
		if mode == "ambient" and requested:
			state.cursor = fposmod(maxf(float(_stage.get("ambient_elapsed")), 0.0), float(row.period))
			state.mode = "settling" if _gesture_active(role, float(state.cursor)) else "attending"
			mode = str(state.mode)
		if mode == "settling":
			# Traverse the original authored recovery, never blend the wiping hand
			# through the cup or turn a drinking face away from a still-raised rim.
			var end := _gesture_end(role)
			state.cursor = minf(float(state.cursor) + step * 1.35, end)
			if float(state.cursor) >= end:
				state.mode = "attending" if requested else "returning"
		elif mode == "attending":
			if not requested:
				state.mode = "returning"
			else:
				state.yaw = move_toward(float(state.yaw), _target_yaw(row), ATTENTION_SPEED * step)
		elif mode == "returning":
			if requested:
				state.mode = "attending"
			else:
				state.yaw = move_toward(float(state.yaw), 0.0, RETURN_SPEED * step)
				var ambient := fposmod(maxf(float(_stage.get("ambient_elapsed")), 0.0), float(row.period))
				if absf(float(state.yaw)) < 0.000001 and not _gesture_active(role, ambient):
					state.mode = "rejoin"
					state.rejoin = 0.0
		elif mode == "rejoin":
			if requested:
				state.mode = "attending"
			else:
				var ambient := fposmod(maxf(float(_stage.get("ambient_elapsed")), 0.0), float(row.period))
				if _gesture_active(role, ambient):
					state.mode = "returning"
					state.rejoin = 0.0
				else:
					state.rejoin = minf(float(state.rejoin) + step / REJOIN_SECONDS, 1.0)
					if float(state.rejoin) >= 1.0:
						state.mode = "ambient"
	sync()


func _wants_attention(role: String, row: Dictionary) -> bool:
	var state: Dictionary = row.attention
	if not _attention_target_valid:
		state.near = false
		return false
	if not _conversation_role.is_empty():
		state.near = false
		return _conversation_role == role
	var root := row.root as Node3D
	var local := root.global_basis.inverse() * (_attention_target - root.global_position)
	var radius := 2.20 if role == "tea_seller" else 1.75
	if bool(state.near):
		radius += 0.40
	# A person passing behind does not cause a strained back-facing head pose.
	state.near = Vector2(local.x, local.z).length() < radius and absf(atan2(local.x, local.z)) < PI * 0.60
	return bool(state.near)


func _target_yaw(row: Dictionary) -> float:
	var root := row.root as Node3D
	var local := root.global_basis.inverse() * (_attention_target - root.global_position)
	return clampf(atan2(local.x, local.z), -ATTENTION_LIMIT, ATTENTION_LIMIT)


func _gesture_active(role: String, seconds: float) -> bool:
	return seconds >= (1.55 if role == "tea_seller" else 7.0) and seconds < _gesture_end(role)


func _gesture_end(role: String) -> float:
	return 5.45 if role == "tea_seller" else 9.20


func _sample_actor(row: Dictionary, seconds: float) -> void:
	var player := row.player as AnimationPlayer
	player.play(row.clip)
	player.seek(seconds, true)
	player.pause()
	(row.skeleton as Skeleton3D).force_update_all_bone_transforms()


func _blend_rest_to_ambient(row: Dictionary, seconds: float, weight: float) -> void:
	var skeleton := row.skeleton as Skeleton3D
	var poses: Array[Transform3D] = []
	for index: int in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_pose(index))
	_sample_actor(row, seconds)
	var mix := smoothstep(0.0, 1.0, weight)
	for index: int in range(skeleton.get_bone_count()):
		var target := skeleton.get_bone_pose(index)
		skeleton.set_bone_pose_position(index, poses[index].origin.lerp(target.origin, mix))
		skeleton.set_bone_pose_rotation(index, poses[index].basis.orthonormalized().get_rotation_quaternion().slerp(target.basis.orthonormalized().get_rotation_quaternion(), mix))
		skeleton.set_bone_pose_scale(index, poses[index].basis.get_scale().lerp(target.basis.get_scale(), mix))


func _apply_attention_yaw(row: Dictionary, yaw: float) -> void:
	if absf(yaw) < 0.000001:
		return
	var skeleton := row.skeleton as Skeleton3D
	# All three rotations stay above pelvis/legs/seat. Cup and cloth follow the
	# same chest transform as their hands, and are already in a safe held pose.
	_add_world_yaw(skeleton, int(row.bone_indices.chest), yaw * 0.08)
	_add_world_yaw(skeleton, int(row.bone_indices.neck), yaw * 0.22)
	_add_world_yaw(skeleton, int(row.bone_indices.head), yaw * 0.70)


func _add_world_yaw(skeleton: Skeleton3D, index: int, yaw: float) -> void:
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var rest_basis := skeleton.get_bone_rest(index).basis
	var skeleton_up := skeleton.global_basis.inverse() * Vector3.UP
	var local_axis := ((parent_basis * rest_basis).inverse() * skeleton_up).normalized()
	var rotation := Quaternion(local_axis, yaw) * skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, rotation.normalized())
	skeleton.force_update_all_bone_transforms()


func get_presentation_state() -> Dictionary:
	var actors := {}
	for role: String in _actors:
		actors[role] = (_actors[role].attention as Dictionary).duplicate(true)
	return {"enabled": _attention_enabled, "target_valid": _attention_target_valid,
		"target": _attention_target, "conversation_role": _conversation_role, "actors": actors}


func set_presentation_state(value: Dictionary) -> void:
	# This snapshot belongs only to an existing host view/run, never Session or
	# disk persistence. The host decides whether the current pack enables it.
	if not _attention_enabled or not bool(value.get("enabled", false)):
		return
	var target: Variant = value.get("target", Vector3.ZERO)
	if target is Vector3 and (target as Vector3).is_finite():
		_attention_target = target
	_attention_target_valid = bool(value.get("target_valid", false))
	var role := str(value.get("conversation_role", ""))
	_conversation_role = role if ROLES.has(role) else ""
	var saved: Dictionary = value.get("actors", {})
	for actor_role: String in ROLES:
		if not _actors.has(actor_role) or not saved.get(actor_role) is Dictionary:
			continue
		var input: Dictionary = saved[actor_role]
		var state := _new_attention()
		var mode := str(input.get("mode", "ambient"))
		state.mode = mode if ["ambient", "settling", "attending", "returning", "rejoin"].has(mode) else "ambient"
		state.cursor = clampf(float(input.get("cursor", 0.0)), 0.0, float(_actors[actor_role].period))
		state.yaw = clampf(float(input.get("yaw", 0.0)), -ATTENTION_LIMIT, ATTENTION_LIMIT)
		state.rejoin = clampf(float(input.get("rejoin", 0.0)), 0.0, 1.0)
		state.near = bool(input.get("near", false))
		state.requested = bool(input.get("requested", false))
		_actors[actor_role].attention = state
	sync()


func _legacy_sprite(role: String) -> Sprite3D:
	if role == "tea_seller":
		return (_stage.get("actor_nodes") as Dictionary).get("tea_seller") as Sprite3D
	return _stage.get("_tea_patron") as Sprite3D


func get_actor(role: String) -> Node3D:
	return _actors.get(role, {}).get("root") as Node3D


func get_model_root(role: String) -> Node3D:
	return _actors.get(role, {}).get("model") as Node3D


func set_review_time(role: String, seconds: float) -> void:
	_review_times[role] = seconds
	sync()


func clear_review_time(role: String) -> void:
	_review_times.erase(role)
	sync()


func set_review_lighting(role: String, enabled: bool) -> void:
	if not _actors.has(role):
		return
	_review_lights[role] = enabled
	for material: StandardMaterial3D in _actors[role].materials:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if enabled else BaseMaterial3D.SHADING_MODE_UNSHADED


func clear_review_lighting(role: String) -> void:
	set_review_lighting(role, true)
	_review_lights.erase(role)


func bone_points(role: String) -> Dictionary:
	var result := {}
	if not _actors.has(role):
		return result
	var skeleton := _actors[role].skeleton as Skeleton3D
	for bone: String in ["foot.L", "foot.R", "hand.L", "hand.R", "head", "pelvis"]:
		var index := skeleton.find_bone(bone)
		if index >= 0:
			result[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return result


func audit() -> Dictionary:
	var actors := {}
	for role: String in ROLES:
		if not _actors.has(role):
			continue
		var row: Dictionary = _actors[role]
		var root := row.root as Node3D
		var skeleton := row.skeleton as Skeleton3D
		var model := row.model as Node3D
		var head_index := skeleton.find_bone("head")
		var head_basis := skeleton.global_basis * skeleton.get_bone_global_pose(head_index).basis
		actors[role] = {"model": row.path, "mesh_count": (row.meshes as Array).size(),
			"bone_count": skeleton.get_bone_count(), "clip": str(row.clip), "period": row.period,
			"phase": row.phase, "seconds": row.seconds, "position": root.position,
			"yaw": root.rotation.y, "scale": model.scale, "source_anchor": row.anchor,
			"world_anchor": model.global_transform * (row.anchor as Vector3),
			"floor_y": row.floor_y, "bones": bone_points(role),
			"head_world_rotation": head_basis.orthonormalized().get_rotation_quaternion(),
			"attention": (row.attention as Dictionary).duplicate(true), "payload": row.payload,
			"legacy_sprite_hidden": not _legacy_sprite(role).visible,
			"lighting_enabled": bool(_review_lights.get(role, true))}
	return {"available": _available, "enabled": _enabled, "actors": actors, "source": SOURCE,
		"time_authority": "existing stage ambient_elapsed; optional host-advanced recovery/look response; no independent ticker or game-time change",
		"attention_enabled": _attention_enabled, "attention_target_valid": _attention_target_valid,
		"attention_target": _attention_target, "conversation_role": _conversation_role,
		"attention_advances": _attention_advances,
		"attention_contract": "opt-in; Static freezes response; complete original cup recovery before gaze; at most35deg above fixed pelvis/feet/seat; original ambient rejoins only in rest",
		"contact_shadow": "two soft shoe contacts per NPC; not shape-cast shadows",
		"review_override": not _review_times.is_empty() or not _review_lights.is_empty()}


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _create_contacts(root: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var contacts := {}
	var original := (_stage.get("shadow_nodes") as Dictionary).get("tea_seller") as MeshInstance3D
	if original == null:
		return contacts
	for bone: String in ["foot.L", "foot.R"]:
		if skeleton.find_bone(bone) < 0:
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = "SoleContact_" + bone.replace(".", "_")
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.25, 0.43)
		mesh.mesh = plane
		mesh.material_override = original.material_override.duplicate() as StandardMaterial3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
		contacts[bone] = mesh
	return contacts


func _sync_contacts(row: Dictionary) -> void:
	var skeleton := row.skeleton as Skeleton3D
	var root := row.root as Node3D
	var floor_y := float(row.floor_y)
	for bone: String in row.contacts:
		var ankle := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
		var mesh := row.contacts[bone] as MeshInstance3D
		var toe := root.global_basis * Vector3(0.0, 0.0, 0.065)
		mesh.global_position = Vector3(ankle.x + toe.x, floor_y + 0.003, ankle.z + toe.z)
		(mesh.material_override as StandardMaterial3D).albedo_color = Color(0.16, 0.18, 0.13, 0.35)


func _prepare_materials(meshes: Array[MeshInstance3D]) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	for instance: MeshInstance3D in meshes:
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
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			# Keep the authored distinction between fabric and ceramic vessels.
			material.roughness = clampf(material.roughness, 0.28, 1.0)
			material.metallic = 0.0
			materials.append(material)
			local_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			local_mesh.surface_set_material(surface, material)
		instance.mesh = local_mesh
	return materials
