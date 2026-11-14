extends "res://addons/cultivation_mode/chengdu_actor.gd"
## Two dock silhouettes and upper-body actions on the existing adult rig/gait.
const Costume = preload("res://addons/cultivation_mode/dock_corner_costume.gd")
var costume := Costume.new()
var archetype := ""
var action := "quiet"
var arm_residual := 0.0
var body_stretch := Vector3.ONE

func install_daily_clips(source: Node3D, profile: Dictionary) -> void:
	var library := AnimationLibrary.new()
	var root: Node = animator.get_node(animator.root_node)
	var skeleton_path := str(root.get_path_to(skeleton))
	for pair: Array in [["Idle","TownIdle"],["Walk","TownWalk"]]:
		var clip: Animation = source.animator.get_animation(pair[1]).duplicate(true)
		for track: int in range(clip.get_track_count()):
			var path := str(clip.track_get_path(track))
			clip.track_set_path(track,NodePath(skeleton_path+":"+path.get_slice(":",1)))
		library.add_animation(pair[0],clip)
	animator.add_animation_library("resident",library)
	idle_clip = &"resident/Idle"
	walk_clip = &"resident/Walk"
	archetype = str(profile.archetype)
	var stretch: Array = profile.body_stretch
	body_stretch = Vector3(stretch[0],stretch[1],stretch[2])
	model.scale = body_stretch*display_scale
	model.position = -source_anchor*model.scale
	costume.setup(skeleton,profile,meshes)
	_sample(idle_clip,0.0)
	floor_height = minf(_bone_position(skeleton.find_bone("foot.L")).y,_bone_position(skeleton.find_bone("foot.R")).y)
	_sync_contacts()

func sync(_point: Vector2, _stride: float, _walking: bool, _seconds: float) -> void:
	pass # Controlled scene state supplies this resident's own route and clock.

func _rotate_bone(name: String, axis: Vector3, angle: float) -> void:
	var index := skeleton.find_bone(name)
	var pose := skeleton.get_bone_global_pose(index)
	pose.basis = Basis(axis,angle)*pose.basis
	skeleton.set_bone_global_pose(index,pose)
	skeleton.force_update_all_bone_transforms()

func _aim(parent: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(parent)
	var direction := skeleton.get_bone_global_pose(child).origin-pose.origin
	var wanted := target-pose.origin
	pose.basis = Basis(Quaternion(direction.normalized(),wanted.normalized()))*pose.basis
	skeleton.set_bone_global_pose(parent,pose)
	skeleton.force_update_all_bone_transforms()

func _arm(side: String, target: Vector3, pole: Vector3) -> void:
	var upper := skeleton.find_bone("upper_arm."+side)
	var fore := skeleton.find_bone("forearm."+side)
	var hand := skeleton.find_bone("hand."+side)
	var start := skeleton.get_bone_global_pose(upper).origin
	var first := start.distance_to(skeleton.get_bone_global_pose(fore).origin)
	var second := skeleton.get_bone_global_pose(fore).origin.distance_to(skeleton.get_bone_global_pose(hand).origin)
	var direction := (target-start).normalized()
	var distance := clampf(start.distance_to(target),0.02,first+second-0.005)
	var along := (first*first-second*second+distance*distance)/(2.0*distance)
	var height := sqrt(maxf(first*first-along*along,0.0))
	var perpendicular := (pole-direction*pole.dot(direction)).normalized()
	var elbow := start+direction*along+perpendicular*height
	_aim(upper,fore,elbow)
	_aim(fore,hand,target)
	arm_residual = maxf(arm_residual,skeleton.get_bone_global_pose(hand).origin.distance_to(target))

func present(state: Dictionary) -> void:
	ground = state.point
	position = stage.logical_to_world(ground)
	yaw = float(state.yaw)
	rotation.y = yaw
	var walking := bool(state.walking)
	var clip := walk_clip if walking else idle_clip
	var length := animator.get_animation(clip).length
	var phase := fposmod(float(state.stride)/cycle_distance,1.0)*length if walking else 0.0
	_sample(clip,phase)
	var quiet := bool(state.get("quiet",false))
	action = "walk" if walking else ("quiet" if quiet else str(state.get("idle_action","look")))
	var local_phase := float(state.get("rest_age",0.0))
	var envelope := smoothstep(0.0,0.65,local_phase)*smoothstep(0.0,0.65,float(state.wait)) if not quiet and not walking else 0.0
	arm_residual = 0.0
	var left := Vector3(0.11,1.20,-0.24)
	var right := Vector3(-0.09,1.20,-0.26)
	if archetype=="scholar":
		_rotate_bone("head",Vector3.UP,(0.22+0.08*sin(local_phase*0.7))*envelope)
		if action=="read":
			left = left.lerp(Vector3(0.17,1.34,0.42),envelope)
			right = right.lerp(Vector3(-0.17,1.34,0.42),envelope)
			_rotate_bone("head",Vector3.RIGHT,0.18*envelope)
		elif action=="look":
			left = left.lerp(Vector3(0.20,1.10,0.30),envelope)
			right = right.lerp(Vector3(-0.17,1.78,0.37),envelope)
		_arm("L",left,Vector3(1,-0.4,-0.15))
		_arm("R",right,Vector3(-1,0.1,0.10))
	else:
		_rotate_bone("spine",Vector3.RIGHT,0.075+(0.018*sin(phase/length*TAU) if walking else 0.0))
		left = Vector3(0.24,1.34,0.37)
		right = Vector3(-0.24,1.34,0.37)
		if action=="wipe":
			right = right.lerp(Vector3(-0.20,1.77,0.37),envelope)
			_rotate_bone("head",Vector3.RIGHT,-0.08*envelope)
		elif action=="adjust":
			left = left.lerp(Vector3(0.32,1.06,0.27),envelope)
			right = right.lerp(Vector3(-0.22,1.48,0.29),envelope)
		_arm("L",left,Vector3(1,-0.5,0.12))
		_arm("R",right,Vector3(-1,-0.5,0.12))
	costume.present(skeleton,action if envelope>0.7 else "quiet")
	_sync_contacts()

func audit() -> Dictionary:
	var result := super.audit()
	result.merge({"archetype":archetype,"action":action,"body_stretch":body_stretch,"authored_prop_pieces":costume.parts,"arm_target_error":arm_residual})
	return result
