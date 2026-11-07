extends Node3D
## Adapter for the exact approved warm Jiang model, derived from source SHA256
## 9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65.
## Meshes, palette, rig, grip and sword come from that source. No game rules.
## The parent actor is the sole presentation clock; this node never self-ticks.
const MODEL_PATH: String = "res://assets/art/mountain_ambush/jiang-approved.glb"
const IDLE_CLIP: StringName = &"Idle"
const SOURCE_CLIP: StringName = &"ApprovedSwordPhrase"
const SOURCE_FLOOR: float = 0.000216
const SOURCE_HEIGHT: float = 2.096643 - SOURCE_FLOOR
const DISPLAY_HEIGHT: float = 1.90
const ATTACK_SECONDS: float = 0.32
const ATTACK_READY_SOURCE: float = 1.40
const ATTACK_END_SOURCE: float = 2.05
const MARTIAL_CLIPS_PATH: String = "res://assets/art/mountain_ambush/jiang-martial-clips.glb"
const MARTIAL_MANIFEST_PATH: String = "res://assets/art/mountain_ambush/source-martial-clips.json"
const CLOUD_PIERCE_SECONDS: float = 0.32
const RETURNING_SWEEP_SECONDS: float = 0.32
const MARTIAL_LIBRARY: StringName = &"Martial"
const MARTIAL_CLIPS := {"pierce": "CloudPierce", "sweep": "ReturningSweep"}

var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var motion_mode: String = "idle"
var motion_time: float = 0.0
var _neutral: Array[Transform3D] = []
var _flash: StandardMaterial3D
var _current_clip: StringName = IDLE_CLIP
var _source_time: float = 0.0
var _foot_origin: Vector3 = Vector3.ZERO
var _ready: bool = false
var _warm_surfaces: int = 0
var _skill_id: String = ""
var _martial_ready: bool = false
var _weapon_ready: bool = false
var _weapon_bone: int = -1
var _weapon_bind: Transform3D = Transform3D.IDENTITY
var _blade_base: Vector3
var _blade_tip: Vector3

func setup() -> Dictionary:
	set_process(false)
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "Approved Jiang model could not be loaded"}
	model = packed.instantiate() as Node3D
	if model == null:
		return {"ok": false, "reason": "Approved Jiang model root is not Node3D"}
	add_child(model)
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	if skeleton == null or animation_player == null or meshes.size() != 4:
		return {"ok": false, "reason": "Approved Jiang GLB rig, animation or four source meshes are missing"}
	_restore_source_vertex_colors()
	if skeleton.get_bone_count() != 22 or not animation_player.has_animation(IDLE_CLIP) or not animation_player.has_animation(SOURCE_CLIP):
		return {"ok": false, "reason": "Approved Jiang GLB does not match its verified 22-bone/two-clip contract"}
	for bone_name: String in ["pelvis", "chest", "upper_arm.R", "hand.R", "foot.R", "foot.L"]:
		if skeleton.find_bone(bone_name) < 0:
			return {"ok": false, "reason": "Approved Jiang GLB lacks source bone " + bone_name}
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_sample_clip(IDLE_CLIP, 0.0)
	_neutral = _capture_pose()
	var martial_error: String = _install_martial_clips()
	if not martial_error.is_empty():
		return {"ok": false, "reason": martial_error}
	if not _setup_weapon_anchors():
		return {"ok": false, "reason": "Original Jiang sword skin/landmarks are unavailable"}
	# Verified glTF conversion: +Y up, +Z front. One uniform display scale and
	# a fixed midpoint between the original feet keep the external tile anchor.
	var inverse: Transform3D = model.global_transform.affine_inverse()
	var right_foot: Vector3 = inverse * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot.R")).origin
	var left_foot: Vector3 = inverse * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot.L")).origin
	_foot_origin = (right_foot + left_foot) * 0.5
	_foot_origin.y = SOURCE_FLOOR
	var factor: float = DISPLAY_HEIGHT / SOURCE_HEIGHT
	model.scale = Vector3.ONE * factor
	model.position = -_foot_origin * factor
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1.0, 0.67, 0.40, 0.0)
	_ready = true
	set_motion("idle")
	return {"ok": true, "reason": "", "height": DISPLAY_HEIGHT, "bones": skeleton.get_bone_count(), "clips": animation_player.get_animation_list()}

func _install_martial_clips() -> String:
	var packed: PackedScene = load(MARTIAL_CLIPS_PATH) as PackedScene
	if packed == null:
		return "Authored Jiang attack clips are unavailable"
	var source: Node = packed.instantiate()
	var source_skeleton: Skeleton3D
	var source_player: AnimationPlayer
	for node: Node in source.find_children("*", "Skeleton3D", true, false):
		source_skeleton = node as Skeleton3D
		break
	for node: Node in source.find_children("*", "AnimationPlayer", true, false):
		source_player = node as AnimationPlayer
		break
	if source_skeleton == null or source_player == null or source_skeleton.get_bone_count() != 22:
		source.free()
		return "Authored Jiang clips lack the matching 22-bone skeleton"
	for index: int in range(skeleton.get_bone_count()):
		var bone: int = source_skeleton.find_bone(skeleton.get_bone_name(index))
		if bone < 0 or not skeleton.get_bone_rest(index).is_equal_approx(source_skeleton.get_bone_rest(bone)):
			source.free()
			return "Authored Jiang clip skeleton rest differs from the approved rig"
	var library := AnimationLibrary.new()
	var animation_root: Node = animation_player.get_node(animation_player.root_node)
	var skeleton_path: String = str(animation_root.get_path_to(skeleton))
	for clip_name: String in MARTIAL_CLIPS.values():
		if not source_player.has_animation(clip_name):
			source.free()
			return "Authored Jiang clip is missing: " + clip_name
		var animation: Animation = source_player.get_animation(clip_name).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_NONE
		for track: int in range(animation.get_track_count()):
			var path: NodePath = animation.track_get_path(track)
			if path.get_subname_count() != 1 or skeleton.find_bone(path.get_subname(0)) < 0:
				source.free()
				return "Authored Jiang clip contains a non-bone animation track"
			animation.track_set_path(track, NodePath(skeleton_path + ":" + str(path.get_subname(0))))
		library.add_animation(clip_name, animation)
	animation_player.add_animation_library(MARTIAL_LIBRARY, library)
	# The three-vertex import carrier and its Skeleton3D never join the actor.
	source.free()
	_martial_ready = true
	return ""

func _setup_weapon_anchors() -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARTIAL_MANIFEST_PATH))
	if not data is Dictionary:
		return false
	var landmarks: Dictionary = data.get("weapon_landmarks", {})
	var base: Array = landmarks.get("base", [])
	var tip: Array = landmarks.get("tip", [])
	if base.size() != 3 or tip.size() != 3:
		return false
	_blade_base = Vector3(float(base[0]), float(base[1]), float(base[2]))
	_blade_tip = Vector3(float(tip[0]), float(tip[1]), float(tip[2]))
	_weapon_bone = skeleton.find_bone("hand.R")
	for instance: MeshInstance3D in meshes:
		if not str(instance.name).contains("JiangRightGrip_Jian"):
			continue
		var skin: Skin = instance.skin
		if skin == null:
			continue
		for bind: int in range(skin.get_bind_count()):
			if skin.get_bind_name(bind) == &"hand.R" or skin.get_bind_bone(bind) == _weapon_bone:
				_weapon_bind = skin.get_bind_pose(bind)
				_weapon_ready = true
				return true
	return false

func get_weapon_anchors() -> Dictionary:
	if not _ready or not _weapon_ready:
		return {"valid": false, "space": "global"}
	var transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_weapon_bone) * _weapon_bind
	return {"valid": true, "base": transform * _blade_base, "tip": transform * _blade_tip, "space": "global"}

func attack_duration() -> float:
	if _skill_id == "pierce":
		return CLOUD_PIERCE_SECONDS
	if _skill_id == "sweep":
		return RETURNING_SWEEP_SECONDS
	return ATTACK_SECONDS

func _restore_source_vertex_colors() -> void:
	# The approved multiplier is linear. Compatibility shades in sRGB; encode
	# a local mesh copy for that renderer, without changing the source GLB.
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

func set_motion(mode: String, _strength: float = 1.0, skill_id: String = "") -> void:
	if not _ready:
		return
	motion_mode = mode
	motion_time = 0.0
	_skill_id = skill_id if mode == "attack" else ""
	_clear_flash()
	_sample_clip(IDLE_CLIP, 0.0)
	_apply_pose(_neutral)
	if mode == "attack" and MARTIAL_CLIPS.has(_skill_id):
		_sample_clip(StringName(str(MARTIAL_LIBRARY) + "/" + str(MARTIAL_CLIPS[_skill_id])), 0.0)

func step(delta: float) -> void:
	if not _ready:
		return
	motion_time += maxf(0.0, delta)
	_clear_flash()
	if motion_mode == "attack":
		if motion_time >= attack_duration():
			set_motion("idle")
			return
		if MARTIAL_CLIPS.has(_skill_id):
			_sample_clip(StringName(str(MARTIAL_LIBRARY) + "/" + str(MARTIAL_CLIPS[_skill_id])), motion_time)
			return
		# These are actual poses from the approved original sword animation.
		# Blend in/out in bone space so a short combat response never leaves the
		# model stuck in the source four-second clip's non-neutral final pose.
		if motion_time < 0.065:
			_sample_clip(SOURCE_CLIP, ATTACK_READY_SOURCE)
			_blend_to_neutral(1.0 - smoothstep(0.0, 0.065, motion_time))
		elif motion_time < 0.225:
			var progress: float = inverse_lerp(0.065, 0.225, motion_time)
			_sample_clip(SOURCE_CLIP, lerpf(ATTACK_READY_SOURCE, ATTACK_END_SOURCE, progress))
		else:
			_sample_clip(SOURCE_CLIP, ATTACK_END_SOURCE)
			_blend_to_neutral(smoothstep(0.225, ATTACK_SECONDS, motion_time))
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

func audit() -> Dictionary:
	var pose: Dictionary = {}
	if skeleton != null:
		for name: String in ["pelvis", "chest", "upper_arm.R", "forearm.R", "hand.R", "thigh.R", "foot.R", "foot.L"]:
			var index: int = skeleton.find_bone(name)
			if index >= 0:
				pose[name] = skeleton.get_bone_pose(index)
	return {"approved": _ready, "model": MODEL_PATH, "mode": motion_mode, "elapsed": motion_time, "source_clip": str(_current_clip), "source_seconds": _source_time, "skill_id": _skill_id, "martial_clips_ready": _martial_ready, "martial_clip_asset": MARTIAL_CLIPS_PATH, "weapon_anchors": get_weapon_anchors(), "bone_poses": pose, "warm_color_surfaces": _warm_surfaces, "skeleton_path": str(skeleton.get_path()) if skeleton != null and skeleton.is_inside_tree() else "", "animation_player_path": str(animation_player.get_path()) if animation_player != null and animation_player.is_inside_tree() else "", "height": DISPLAY_HEIGHT, "foot_origin": _foot_origin}
