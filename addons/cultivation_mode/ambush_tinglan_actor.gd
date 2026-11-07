extends Node3D
## Independent Tinglan combat candidate. Meshes and clips share one fixed source.
## The outer battle actor owns the only clock. This adapter never settles rules.

const MODEL_PATH: String = "res://assets/art/mountain_ambush/tinglan-candidate.glb"
const METADATA_PATH: String = "res://assets/art/mountain_ambush/tinglan-candidate.json"
const IDLE_CLIP: StringName = &"Idle"
const SWORD_CLIP: StringName = &"ApprovedSwordPhrase"
const INTERRUPT_CLIP: StringName = &"TinglanInterrupt"
const PALM_MODEL_PATH := "res://assets/art/mountain_ambush/palm_lab/v2/motion/tinglan-palm-clips.glb"
const PALM_CLIP: StringName = &"Palm/TinglanPalm"
const PALM_SECONDS := 1.45
const DEFAULT_FLOOR: float = 0.000216
const DEFAULT_HEIGHT: float = 2.13 - DEFAULT_FLOOR
const DEFAULT_DISPLAY_HEIGHT: float = 1.90
const SWORD_SECONDS: float = 0.32
const INTERRUPT_SECONDS: float = 0.40
const SWORD_READY_SOURCE: float = 1.40
const SWORD_END_SOURCE: float = 2.05

var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var motion_mode: String = "idle"
var motion_time: float = 0.0
var _skill_id: String = ""
var _neutral: Array[Transform3D] = []
var _relaxed_hand: MeshInstance3D
var _pointing_hand: MeshInstance3D
var _open_palm: MeshInstance3D
var _palm_ready := false
var _right_grip: MeshInstance3D
var _jian: MeshInstance3D
var _flash: StandardMaterial3D
var _current_clip: StringName = IDLE_CLIP
var _source_time: float = 0.0
var _foot_origin: Vector3 = Vector3.ZERO
var _source_floor: float = DEFAULT_FLOOR
var _source_height: float = DEFAULT_HEIGHT
var _display_height: float = DEFAULT_DISPLAY_HEIGHT
var _warm_surfaces: int = 0
var _ready: bool = false


func setup() -> Dictionary:
	set_process(false)
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "Tinglan candidate GLB could not be loaded"}
	model = packed.instantiate() as Node3D
	if model == null:
		return {"ok": false, "reason": "Tinglan candidate root is not Node3D"}
	add_child(model)
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			return {"ok": false, "reason": "Tinglan candidate contains an empty mesh"}
		meshes.append(instance)
		match str(instance.name):
			"TinglanRelaxedHand": _relaxed_hand = instance
			"TinglanPointingHand": _pointing_hand = instance
			"TinglanRightGrip": _right_grip = instance
			"TinglanJian": _jian = instance
	if skeleton == null or animation_player == null or meshes.is_empty():
		return {"ok": false, "reason": "Tinglan candidate rig, animation or meshes are missing"}
	if _relaxed_hand == null or _pointing_hand == null or _right_grip == null or _jian == null:
		return {"ok": false, "reason": "Tinglan candidate hand variants or right-hand sword are missing"}
	if skeleton.get_bone_count() != 22:
		return {"ok": false, "reason": "Tinglan candidate does not match its 22-bone contract"}
	for clip: StringName in [IDLE_CLIP, SWORD_CLIP, INTERRUPT_CLIP]:
		if not animation_player.has_animation(clip):
			return {"ok": false, "reason": "Tinglan candidate lacks animation " + str(clip)}
	for bone_name: String in ["pelvis", "chest", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "foot.L", "foot.R"]:
		if skeleton.find_bone(bone_name) < 0:
			return {"ok": false, "reason": "Tinglan candidate lacks bone " + bone_name}
	var palm_error := _load_palm_motion()
	if not palm_error.is_empty():
		return {"ok": false, "reason": palm_error}
	_restore_source_vertex_colors()
	_read_calibration()
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_sample_clip(IDLE_CLIP, 0.0)
	_neutral = _capture_pose()
	# The fixed midpoint comes from the actual neutral feet; floor/height are
	# source measurements. Scale only this inner model: the stage owns the root.
	var inverse: Transform3D = model.global_transform.affine_inverse()
	var right_foot: Vector3 = inverse * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot.R")).origin
	var left_foot: Vector3 = inverse * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot.L")).origin
	_foot_origin = (right_foot + left_foot) * 0.5
	_foot_origin.y = _source_floor
	var factor: float = _display_height / _source_height
	model.scale = Vector3.ONE * factor
	model.position = -_foot_origin * factor
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1.0, 0.67, 0.40, 0.0)
	_ready = true
	set_motion("idle")
	return {"ok": true, "reason": "", "height": _display_height,
		"bones": skeleton.get_bone_count(), "clips": animation_player.get_animation_list()}


func _packed_transform(node: Node3D) -> Transform3D:
	var value := node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D:
		value = (parent as Node3D).transform * value
		parent = parent.get_parent()
	return value

func _rest_difference(a: Transform3D, b: Transform3D) -> float:
	# glTF/Blender round-tripping can change the same rest by a few micrometres.
	return maxf(a.origin.distance_to(b.origin), maxf((a.basis.x - b.basis.x).length(), maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length())))

func _load_palm_motion() -> String:
	var packed := load(PALM_MODEL_PATH) as PackedScene
	if packed == null:
		return "Dedicated palm motion is missing"
	var source: Node = packed.instantiate()
	var rig: Skeleton3D
	var player: AnimationPlayer
	var hand: MeshInstance3D
	for node: Node in source.find_children("*", "Skeleton3D", true, false):
		rig = node as Skeleton3D
		break
	for node: Node in source.find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		break
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		if str(node.name) == "TinglanOpenPalm":
			hand = node as MeshInstance3D
	if rig == null or player == null or hand == null or hand.skin == null or not player.has_animation("TinglanPalm") or rig.get_bone_count() != skeleton.get_bone_count():
		source.free()
		return "Dedicated palm motion lacks its matching rig, clip or hand"
	for index: int in range(skeleton.get_bone_count()):
		var bone := rig.find_bone(skeleton.get_bone_name(index))
		if bone < 0 or _rest_difference(skeleton.get_bone_rest(index), rig.get_bone_rest(bone)) > 0.00002:
			source.free()
			return "Dedicated palm motion skeleton differs"
	var animation: Animation = player.get_animation("TinglanPalm").duplicate(true) as Animation
	var animation_root: Node = animation_player.get_node(animation_player.root_node)
	var path := str(animation_root.get_path_to(skeleton))
	for track: int in range(animation.get_track_count()):
		var target: NodePath = animation.track_get_path(track)
		if target.get_subname_count() != 1 or skeleton.find_bone(target.get_subname(0)) < 0:
			source.free()
			return "Dedicated palm clip contains a non-bone track"
		animation.track_set_path(track, NodePath(path + ":" + str(target.get_subname(0))))
	animation.loop_mode = Animation.LOOP_NONE
	var library := AnimationLibrary.new()
	library.add_animation("TinglanPalm", animation)
	animation_player.add_animation_library(&"Palm", library)
	_open_palm = hand.duplicate() as MeshInstance3D
	_open_palm.name = "TinglanOpenPalm"
	_open_palm.skin = hand.skin.duplicate() as Skin
	for bind: int in range(_open_palm.skin.get_bind_count()):
		var bone_name := _open_palm.skin.get_bind_name(bind)
		if bone_name.is_empty():
			bone_name = rig.get_bone_name(_open_palm.skin.get_bind_bone(bind))
		_open_palm.skin.set_bind_bone(bind, skeleton.find_bone(bone_name))
		_open_palm.skin.set_bind_name(bind, bone_name)
	_open_palm.transform = _packed_transform(rig).affine_inverse() * _packed_transform(hand)
	_open_palm.skeleton = NodePath("..")
	skeleton.add_child(_open_palm)
	_open_palm.visible = false
	meshes.append(_open_palm)
	source.free()
	_palm_ready = true
	return ""

func sample_palm_preview(seconds: float) -> bool:
	if not _ready or not _palm_ready:
		return false
	if seconds >= PALM_SECONDS:
		set_motion("idle")
		return true
	motion_mode = "palm_preview"
	motion_time = maxf(0.0, seconds)
	_skill_id = "palm_preview"
	_clear_flash()
	_set_hand_variant(false)
	_relaxed_hand.visible = false
	_pointing_hand.visible = false
	_open_palm.visible = true
	_sample_clip(PALM_CLIP, motion_time)
	return true

func get_palm_origin() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand.L")) * Vector3(0.0, 0.055, 0.018)

func _read_calibration() -> void:
	var calibration: Dictionary = {}
	if FileAccess.file_exists(METADATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("calibration") is Dictionary:
			calibration = parsed.calibration
	var floor_value := float(calibration.get("floor", DEFAULT_FLOOR))
	var height_value := float(calibration.get("height", DEFAULT_HEIGHT))
	var display_value := float(calibration.get("display_height", DEFAULT_DISPLAY_HEIGHT))
	_source_floor = floor_value if is_finite(floor_value) else DEFAULT_FLOOR
	_source_height = height_value if is_finite(height_value) and height_value > 0.0 else DEFAULT_HEIGHT
	_display_height = display_value if is_finite(display_value) and display_value > 0.0 else DEFAULT_DISPLAY_HEIGHT


func _restore_source_vertex_colors() -> void:
	# Same Compatibility encoding as the verified Jiang adapter. Keep the source
	# GLB immutable; only local mesh/material copies consume its linear COLOR_0.
	for instance: MeshInstance3D in meshes:
		var source: Mesh = instance.mesh
		var has_colors := false
		for surface: int in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] != null:
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				has_colors = has_colors or not colors.is_empty()
		if not has_colors:
			continue
		var local_mesh := ArrayMesh.new()
		local_mesh.resource_name = source.resource_name + "_SourceColors"
		for surface: int in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface)
			var material: Material = instance.get_active_material(surface)
			if arrays[Mesh.ARRAY_COLOR] != null:
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				if not colors.is_empty():
					for i: int in range(colors.size()):
						colors[i] = colors[i].linear_to_srgb()
					arrays[Mesh.ARRAY_COLOR] = colors
					var original := material as StandardMaterial3D
					if original != null:
						var adapted := original.duplicate() as StandardMaterial3D
						adapted.vertex_color_use_as_albedo = true
						adapted.vertex_color_is_srgb = true
						material = adapted
						_warm_surfaces += 1
			local_mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			local_mesh.surface_set_material(surface, material)
		instance.mesh = local_mesh


func _sample_clip(clip: StringName, seconds: float) -> void:
	animation_player.play(clip)
	animation_player.seek(seconds, true)
	animation_player.pause()
	_current_clip = clip
	_source_time = seconds
	skeleton.force_update_all_bone_transforms()


func _capture_pose() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i: int in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_pose(i))
	return result


func _apply_pose(pose: Array[Transform3D]) -> void:
	for i: int in range(pose.size()):
		skeleton.set_bone_pose(i, pose[i])
	skeleton.force_update_all_bone_transforms()


func _blend_to_neutral(amount: float) -> void:
	for i: int in range(_neutral.size()):
		var sampled: Transform3D = skeleton.get_bone_pose(i)
		skeleton.set_bone_pose(i, sampled.interpolate_with(_neutral[i], amount))
	skeleton.force_update_all_bone_transforms()


func _clear_flash() -> void:
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = null


func _set_hand_variant(pointing: bool) -> void:
	if is_instance_valid(_open_palm):
		_open_palm.visible = false
	_relaxed_hand.visible = not pointing
	_pointing_hand.visible = pointing
	_right_grip.visible = true
	_jian.visible = true


func set_motion(mode: String, _strength: float = 1.0, skill_id: String = "") -> void:
	if not _ready:
		return
	motion_mode = mode
	motion_time = 0.0
	_skill_id = skill_id if mode == "attack" else ""
	_clear_flash()
	_sample_clip(IDLE_CLIP, 0.0)
	_apply_pose(_neutral)
	var pointing := mode == "attack" and _skill_id == "interrupt"
	_set_hand_variant(pointing)
	if pointing:
		_sample_clip(INTERRUPT_CLIP, 0.0)


func step(delta: float) -> void:
	if not _ready:
		return
	motion_time += maxf(0.0, delta)
	_clear_flash()
	if motion_mode == "attack":
		if _skill_id == "interrupt":
			if motion_time >= INTERRUPT_SECONDS:
				set_motion("idle")
			else:
				_sample_clip(INTERRUPT_CLIP, minf(motion_time, INTERRUPT_SECONDS))
		elif motion_time >= SWORD_SECONDS:
			set_motion("idle")
		elif motion_time < 0.065:
			_sample_clip(SWORD_CLIP, SWORD_READY_SOURCE)
			_blend_to_neutral(1.0 - smoothstep(0.0, 0.065, motion_time))
		elif motion_time < 0.225:
			var progress: float = inverse_lerp(0.065, 0.225, motion_time)
			_sample_clip(SWORD_CLIP, lerpf(SWORD_READY_SOURCE, SWORD_END_SOURCE, progress))
		else:
			_sample_clip(SWORD_CLIP, SWORD_END_SOURCE)
			_blend_to_neutral(smoothstep(0.225, SWORD_SECONDS, motion_time))
	elif motion_mode == "walk":
		_sample_clip(IDLE_CLIP, 0.0)
		_apply_pose(_neutral)
		var stride: float = sin(motion_time * 18.0) * 0.19
		_offset_rotation("thigh.R", Vector3.RIGHT, stride)
		_offset_rotation("thigh.L", Vector3.RIGHT, -stride)
		_offset_rotation("shin.R", Vector3.RIGHT, maxf(0.0, -stride) * 0.65)
		_offset_rotation("shin.L", Vector3.RIGHT, maxf(0.0, stride) * 0.65)
		_offset_rotation("upper_arm.L", Vector3.RIGHT, stride * 0.22)
		_offset_rotation("skirt.front.R", Vector3.RIGHT, stride * 0.15)
		_offset_rotation("skirt.front.L", Vector3.RIGHT, -stride * 0.15)
		skeleton.force_update_all_bone_transforms()
	elif motion_mode == "hit":
		_sample_clip(IDLE_CLIP, 0.0)
		_apply_pose(_neutral)
		var recoil: float = sin(clampf(motion_time / 0.24, 0.0, 1.0) * PI)
		_offset_rotation("chest", Vector3.RIGHT, -recoil * 0.10)
		_flash.albedo_color.a = recoil * 0.23
		for mesh: MeshInstance3D in meshes:
			mesh.material_overlay = _flash if recoil > 0.02 else null
		skeleton.force_update_all_bone_transforms()
		if motion_time >= 0.25:
			set_motion("idle")
	else:
		_sample_clip(IDLE_CLIP, 0.0)
		_apply_pose(_neutral)


func _offset_rotation(bone_name: String, axis: Vector3, angle: float) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index >= 0:
		skeleton.set_bone_pose_rotation(index, _neutral[index].basis.get_rotation_quaternion() * Quaternion(axis, angle))


func get_action_origin(skill_id: String) -> Vector3:
	if _ready and skill_id == "interrupt":
		var index: int = skeleton.find_bone("hand.L")
		# The authored two-finger hand extends 0.183 m on its hand-bone Y axis.
		return skeleton.global_transform * skeleton.get_bone_global_pose(index) * Vector3(0, 0.183, -0.003)
	return global_position + Vector3.UP * 0.9

func _visible_mesh_bounds() -> AABB:
	var result := AABB()
	var found := false
	var inverse: Transform3D = global_transform.affine_inverse()
	for mesh: MeshInstance3D in meshes:
		if not mesh.visible:
			continue
		var bounds: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		result = result.merge(bounds) if found else bounds
		found = true
	return result


func audit() -> Dictionary:
	var pose: Dictionary = {}
	if skeleton != null:
		for name: String in ["pelvis", "chest", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "thigh.R", "foot.L", "foot.R"]:
			var index: int = skeleton.find_bone(name)
			if index >= 0:
				pose[name] = skeleton.get_bone_pose(index)
	var mesh_rows: Array[Dictionary] = []
	for mesh: MeshInstance3D in meshes:
		mesh_rows.append({"name": str(mesh.name), "visible": mesh.visible, "local_aabb": mesh.get_aabb()})
	var pointing := _pointing_hand != null and _pointing_hand.visible
	var relaxed := _relaxed_hand != null and _relaxed_hand.visible
	return {"candidate": true, "approved": false, "ready": _ready, "model": MODEL_PATH,
		"mode": motion_mode, "elapsed": motion_time, "skill_id": _skill_id,
		"source_clip": str(_current_clip), "source_seconds": _source_time, "bone_poses": pose,
		"left_hand_variant": "palm" if is_instance_valid(_open_palm) and _open_palm.visible else ("pointing" if pointing else ("relaxed" if relaxed else "missing")),
		"palm_ready": _palm_ready, "palm_visible": is_instance_valid(_open_palm) and _open_palm.visible,
		"visible_pointing_hands": 1 if pointing else 0, "visible_relaxed_hands": 1 if relaxed else 0,
		"right_grip_visible": _right_grip != null and _right_grip.visible,
		"sword_visible": _jian != null and _jian.visible, "mesh_count": meshes.size(), "meshes": mesh_rows,
		"bounds": _visible_mesh_bounds() if is_inside_tree() else AABB(),
		"bounds_space": "adapter local, visible mesh AABBs", "height": _display_height,
		"source_floor": _source_floor, "source_height": _source_height, "foot_origin": _foot_origin,
		"warm_color_surfaces": _warm_surfaces,
		"skeleton_path": str(skeleton.get_path()) if skeleton != null and skeleton.is_inside_tree() else "",
		"animation_player_path": str(animation_player.get_path()) if animation_player != null and animation_player.is_inside_tree() else ""}
