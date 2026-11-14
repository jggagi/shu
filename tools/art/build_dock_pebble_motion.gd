extends SceneTree
## Offline authoring on the unchanged approved rig. No geometry/skin/GLB writes.
var actor: Node3D
var skeleton: Skeleton3D

func _initialize() -> void:
	call_deferred("_build")

func _aim(index: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(index)
	var direction := skeleton.get_bone_global_pose(child).origin-pose.origin
	var delta := Quaternion(direction.normalized(),(target-pose.origin).normalized())
	var parent := skeleton.get_bone_parent(index)
	var basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index,(basis.inverse()*Basis(delta)*pose.basis).orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func _arm(target: Vector3) -> void:
	var upper := skeleton.find_bone("upper_arm.R")
	var lower := skeleton.find_bone("forearm.R")
	var hand := skeleton.find_bone("hand.R")
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(hand).origin
	var goal := skeleton.to_local(actor.to_global(target))
	var pole := skeleton.to_local(actor.to_global(Vector3(-0.65,1.0,-0.07)))
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var distance := clampf(a.distance_to(goal),absf(l1-l2)+0.001,l1+l2-0.001)
	var forward := (goal-a).normalized()
	var bend := (pole-a-forward*(pole-a).dot(forward)).normalized()
	var along := (l1*l1-l2*l2+distance*distance)/(2.0*distance)
	var elbow := a+forward*along+bend*sqrt(maxf(l1*l1-along*along,0.0))
	_aim(upper,lower,elbow)
	_aim(lower,hand,a+forward*distance)

func _build() -> void:
	var repo := OS.get_cmdline_user_args()[0]
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo+"/assets/data/dock-corner-pebble-motion.json"))
	var stage = load("res://addons/cultivation_mode/dock_corner_stage.gd").new()
	root.add_child(stage)
	stage.setup(Vector2(778,373))
	actor = stage.actors.player
	skeleton = actor.get("skeleton")
	var animator: AnimationPlayer = actor.get("animator")
	var idle := animator.get_animation("TownIdle")
	var animation := Animation.new()
	animation.length = float(config.duration)
	var tracks := []
	for index: int in range(idle.get_track_count()):
		var path := idle.track_get_path(index)
		if path.get_subname_count()!=1:
			continue
		var bone := skeleton.find_bone(str(path.get_subname(0)))
		var type := idle.track_get_type(index)
		if bone<0 or type not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			continue
		var track := animation.add_track(type)
		animation.track_set_path(track,path)
		tracks.append([track,bone,type])
	var keys: Array = config.keys
	for frame: int in range(roundi(float(config.duration)*float(config.fps))+1):
		var time := float(frame)/float(config.fps)
		actor.call("_sample","TownIdle",0.0)
		var neutral: Array[Quaternion] = []
		for bone: int in range(skeleton.get_bone_count()):
			neutral.append(skeleton.get_bone_pose_rotation(bone))
		var k := 0
		while k<keys.size()-2 and time>float(keys[k+1][0]):
			k+=1
		var a: Array = keys[k]
		var b: Array = keys[k+1]
		var t := smoothstep(0.0,1.0,clampf((time-float(a[0]))/(float(b[0])-float(a[0])),0.0,1.0))
		var start := Vector3(a[1][0],a[1][1],a[1][2])
		var finish := Vector3(b[1][0],b[1][1],b[1][2])
		skeleton.set_bone_pose_rotation(skeleton.find_bone("spine"),Quaternion(Vector3.UP,lerpf(a[2],b[2],t)))
		skeleton.set_bone_pose_rotation(skeleton.find_bone("chest"),Quaternion(Vector3.RIGHT,lerpf(a[3],b[3],t)))
		skeleton.force_update_all_bone_transforms()
		_arm(start.lerp(finish,t))
		var weight := smoothstep(0.18,0.36,time)*(1.0-smoothstep(1.45,2.1,time))
		for bone: int in range(skeleton.get_bone_count()):
			skeleton.set_bone_pose_rotation(bone,neutral[bone].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		for entry: Array in tracks:
			var value: Variant = skeleton.get_bone_pose_rotation(entry[1])
			if entry[2]==Animation.TYPE_POSITION_3D:
				value = skeleton.get_bone_pose_position(entry[1])
			elif entry[2]==Animation.TYPE_SCALE_3D:
				value = skeleton.get_bone_pose_scale(entry[1])
			animation.track_insert_key(entry[0],time,value)
	var output := repo+"/assets/motion/dock_pebble/throw.tres"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := ResourceSaver.save(animation,output)
	print("DOCK_MOTION_AUTHOR: ",error," / ",tracks.size()," tracks")
	quit(0 if error==OK else 1)
