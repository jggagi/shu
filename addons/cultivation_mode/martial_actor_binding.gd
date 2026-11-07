extends RefCounted
## Retarget only matching authored skeletons; no heuristic AI retargeting at runtime.
var _actor: Node3D
var _adapter: Node3D
var _installed := {}
var _clip := ""
var _move: Dictionary = {}
var _processing := true
var _rest_error := 0.0
var _source_seconds := 0.0

func bind_move(actor: Node3D, move: Dictionary, profile: Dictionary) -> Dictionary:
	_actor = actor
	_adapter = actor.call("workshop_adapter") as Node3D
	if _adapter == null:
		return {"ok": false, "reason": "角色没有兼容的动画适配器"}
	var skeleton := _adapter.get("skeleton") as Skeleton3D
	var player := _adapter.get("animation_player") as AnimationPlayer
	if skeleton == null or player == null:
		return {"ok": false, "reason": "角色骨架或播放器缺失"}
	var key := str(move.animation.asset) + ":" + str(move.animation.clip) + ":" + str(move.animation.get("sha256", ""))
	if not _installed.has(key):
		var installed := _install(skeleton, player, move, profile)
		if not installed.ok:
			return installed
		_installed[key] = installed.clip
	_clip = str(_installed[key])
	_move = move.duplicate(true)
	_processing = actor.is_processing()
	actor.set_process(false)
	actor.call("prepare_workshop_motion", move)
	sample(0.0)
	return {"ok": true, "reason": "", "clip": _clip, "rest_error": _rest_error}

func _install(target: Skeleton3D, player: AnimationPlayer, move: Dictionary, profile: Dictionary) -> Dictionary:
	var packed := load(str(move.animation.asset)) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "无法载入动作资源"}
	var source := packed.instantiate()
	var rig: Skeleton3D
	var source_player: AnimationPlayer
	for node: Node in source.find_children("*", "Skeleton3D", true, false):
		rig = node as Skeleton3D
		break
	for node: Node in source.find_children("*", "AnimationPlayer", true, false):
		source_player = node as AnimationPlayer
		break
	var error := ""
	if rig == null or source_player == null or rig.get_bone_count() != target.get_bone_count():
		error = "动作骨架数量或播放器不匹配"
	else:
		_rest_error = 0.0
		for index: int in range(target.get_bone_count()):
			var name_value := target.get_bone_name(index)
			var bone := rig.find_bone(name_value)
			if bone < 0:
				error = "动作缺少骨骼：" + name_value
				break
			var a := target.get_bone_rest(index)
			var b := rig.get_bone_rest(bone)
			_rest_error = maxf(_rest_error, a.origin.distance_to(b.origin))
			for axis: int in range(3):
				_rest_error = maxf(_rest_error, a.basis[axis].distance_to(b.basis[axis]))
			var pa := target.get_bone_parent(index)
			var pb := rig.get_bone_parent(bone)
			if (pa < 0) != (pb < 0) or (pa >= 0 and target.get_bone_name(pa) != rig.get_bone_name(pb)):
				error = "动作骨架层级不同"
				break
		if _rest_error > float(profile.get("rest_tolerance", 0.00002)):
			error = "动作 rest pose 与固定角色不符"
	var raw_clip := str(move.animation.clip)
	if error.is_empty() and not source_player.has_animation(raw_clip):
		error = "动作资源缺少片段：" + raw_clip
	if not error.is_empty():
		source.free()
		return {"ok": false, "reason": error}
	var animation := source_player.get_animation(raw_clip).duplicate(true) as Animation
	if absf(animation.length - float(move.animation.source_seconds)) > 0.025:
		source.free()
		return {"ok": false, "reason": "动作片段时长不符"}
	var animation_root := player.get_node(player.root_node)
	var skeleton_path := str(animation_root.get_path_to(target))
	for track: int in range(animation.get_track_count()):
		var path := animation.track_get_path(track)
		if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or path.get_subname_count() != 1 or target.find_bone(path.get_subname(0)) < 0:
			source.free()
			return {"ok": false, "reason": "动作包含未授权的非骨骼轨道"}
		animation.track_set_path(track, NodePath(skeleton_path + ":" + str(path.get_subname(0))))
	animation.loop_mode = Animation.LOOP_NONE
	# The compatibility libraries are identified by their source asset, never by
	# a raw clip name alone: another authored asset may use that same name.
	var existing_libraries := {
		"res://assets/art/mountain_ambush/jiang-martial-clips.glb": "Martial",
		"res://assets/art/mountain_ambush/palm_lab/v2/motion/tinglan-palm-clips.glb": "Palm"
	}
	var existing := str(existing_libraries.get(str(move.animation.asset), "")) + "/" + raw_clip
	if existing_libraries.has(str(move.animation.asset)) and player.has_animation(existing):
		source.free()
		return {"ok": true, "reason": "", "clip": existing}
	if not player.has_animation_library("Workshop"):
		player.add_animation_library("Workshop", AnimationLibrary.new())
	var library := player.get_animation_library("Workshop")
	var unique := (str(move.animation.asset) + raw_clip + str(move.animation.get("sha256", ""))).sha256_text().substr(0, 16)
	library.add_animation(unique, animation)
	source.free()
	return {"ok": true, "reason": "", "clip": "Workshop/" + unique}

func sample(seconds: float) -> void:
	if not is_instance_valid(_actor) or _move.is_empty():
		return
	var mapping: Array = _move.timing.source_map
	var t := clampf(seconds, 0.0, float(_move.timing.duration))
	_source_seconds = float(mapping[-1][1])
	for index: int in range(1, mapping.size()):
		if t <= float(mapping[index][0]):
			var amount := inverse_lerp(float(mapping[index - 1][0]), float(mapping[index][0]), t)
			_source_seconds = lerpf(float(mapping[index - 1][1]), float(mapping[index][1]), amount)
			break
	_actor.call("sample_workshop_motion", _clip, _source_seconds, t)

func finish() -> void:
	if _move.is_empty():
		return
	if is_instance_valid(_actor):
		_actor.call("set_motion", "idle")
		_actor.set_process(_processing)
	_move.clear()

func audit() -> Dictionary:
	return {"clip": _clip, "animation_asset": str(_move.get("animation", {}).get("asset", "")), "source_seconds": _source_seconds, "rest_error": _rest_error, "installed_count": _installed.size()}
