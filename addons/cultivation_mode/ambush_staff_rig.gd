extends Node3D
## Brute-only, locally authored rigid costume over an actual native skeleton.
## All input is an absolute pose from the owner's existing action clock.
## No _process, AnimationPlayer, gameplay state, root motion or independent time.
const CharacterMesh = preload("res://addons/cultivation_mode/ambush_character_mesh.gd")
const CharacterFinish = preload("res://addons/cultivation_mode/ambush_character_finish.gd")
const UPPER_ARM: float = 0.245
const FOREARM: float = 0.265
const THIGH: float = 0.315
const SHIN: float = 0.265
const ANKLE_HEIGHT: float = 0.08
const STAFF_HALF_LENGTH: float = 0.825
const GRIP_SPACING: float = 0.40
var meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var _bones: Dictionary = {}
var _attachments: Dictionary = {}
var _targets: Dictionary = {}
var _poles: Dictionary = {}
var _staff: Node3D
var _shell: RefCounted
var _builder: RefCounted
var _matte: StandardMaterial3D
var _refined: bool = true
var _sample_revision: int = 0
var _solved_revision: int = 0
var _pose: Dictionary = {}
var _solved: Dictionary = {}
var _ready_once: bool = false
var _triangle_count: int = 0

func setup() -> void:
	if _ready_once:
		return
	_ready_once = true
	_builder = CharacterMesh.new()
	_matte = StandardMaterial3D.new()
	_matte.vertex_color_use_as_albedo = true
	_matte.vertex_color_is_srgb = true
	_matte.roughness = 0.91
	_matte.metallic_specular = 0.18
	_matte.cull_mode = BaseMaterial3D.CULL_DISABLED
	skeleton = Skeleton3D.new()
	skeleton.name = "StaffSkeleton"
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	add_child(skeleton)
	_bone("root", "", Vector3.ZERO)
	_bone("pelvis", "root", Vector3(0, 0.66, 0))
	_bone("chest", "pelvis", Vector3(0, 0.32, 0))
	_bone("head", "chest", Vector3(0, 0.585, 0))
	for side: String in ["right", "left"]:
		var sign_x: float = -1.0 if side == "right" else 1.0
		_bone(side + "_upper_arm", "chest", Vector3(sign_x * 0.28, 0.10, 0))
		_bone(side + "_forearm", side + "_upper_arm", Vector3(0, -UPPER_ARM, 0))
		_bone(side + "_hand", side + "_forearm", Vector3(0, -FOREARM, 0))
		_bone(side + "_thigh", "pelvis", Vector3(sign_x * 0.105, 0, 0))
		_bone(side + "_shin", side + "_thigh", Vector3(0, -THIGH, 0))
		_bone(side + "_foot", side + "_shin", Vector3(0, -SHIN, 0))
	skeleton.reset_bone_poses()
	_build_shell()
	for side: String in ["right", "left"]:
		_build_arm(side)
		_build_leg(side)
		_target(side + "_hand")
		_target(side + "_foot")
		_pole(side + "_arm")
		_pole(side + "_leg")
	_build_staff()
	_build_modifiers()
	skeleton.skeleton_updated.connect(_capture_solved_pose)
	set_refined_details(_refined)
	sample({})

func _bone(label: String, parent: String, origin: Vector3) -> void:
	var index: int = skeleton.add_bone(label)
	_bones[label] = index
	skeleton.set_bone_parent(index, int(_bones[parent]) if not parent.is_empty() else -1)
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))

func _attach(label: String) -> BoneAttachment3D:
	if _attachments.has(label):
		return _attachments[label]
	var result := BoneAttachment3D.new()
	result.name = label.capitalize().replace(" ", "") + "Costume"
	skeleton.add_child(result)
	result.bone_name = label
	result.override_pose = false
	_attachments[label] = result
	return result

func _node(parent: Node3D, label: String, origin: Vector3 = Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = label
	result.position = origin
	parent.add_child(result)
	return result

func _build_shell() -> void:
	var torso: Node3D = _node(_attach("chest"), "TailoredTorso", Vector3(0, -0.98, 0))
	var face: Node3D = _node(_attach("head"), "SourceProportionedHead")
	face.scale = Vector3(0.70, 0.86, 0.70)
	_shell = CharacterFinish.new()
	_shell.call("build_articulated_shell", {"body":torso, "head":face}, {"robe":"#7d705f", "shadow":"#5e584d", "skin":"#c3b099"})
	meshes.append_array(_shell.get("meshes"))

func _build_arm(side: String) -> void:
	var upper: Node3D = _attach(side + "_upper_arm")
	_builder.loft(upper, "ShortSleeve", [[0.025,0.115,0.112,0,0],[-0.06,0.137,0.118,0,0],[-0.16,0.133,0.112,0,0],[-0.185,0.127,0.108,0,0]], "#7d705f", 20)
	_builder.loft(upper, "RolledSleeveHem", [[-0.145,0.139,0.118,0,0],[-0.183,0.138,0.117,0,0]], "#a79373", 20)
	_builder.loft(upper, "UpperArm", [[-0.16,0.089,0.084,0,0],[-0.245,0.082,0.079,0,0]], "#c3b099", 20)
	_merge(upper)
	var lower: Node3D = _attach(side + "_forearm")
	_builder.loft(lower, "ElbowRound", [[0.040,0.053,0.052,0,0],[0,0.086,0.080,0,0],[-0.045,0.086,0.078,0,0],[-0.17,0.069,0.065,0,0],[-0.255,0.049,0.047,0,0]], "#c3b099", 20)
	_builder.strand(lower, "ForearmPlane", [Vector3(-0.035,-0.04,0.07),Vector3(-0.023,-0.12,0.07),Vector3(0,-0.20,0.047)], [0.013,0.019,0.008],0.005,"#d1b99b",6)
	_builder.loft(lower, "WristCuff", [[-0.19,0.072,0.068,0,0],[-0.242,0.061,0.059,0,0]], "#514237", 20)
	_builder.loft(lower, "CuffBinding", [[-0.193,0.074,0.070,0,0],[-0.209,0.071,0.068,0,0]], "#a19376", 20)
	_merge(lower)
	var hand: Node3D = _attach(side + "_hand")
	_builder.bevel_box(hand, "PalmAroundStaff", Vector3(0,0,-0.042), Vector3(0.108,0.092,0.068), "#c3b099")
	for finger: int in range(4):
		var y: float = -0.034 + float(finger) * 0.022
		_builder.strand(hand, "CurledFinger", [Vector3(-0.046,y,-0.040),Vector3(-0.053,y,0.006),Vector3(-0.028,y,0.044),Vector3(0.019,y,0.043),Vector3(0.040,y,0.016)], [0.013,0.014,0.013,0.012,0.010],0.013,"#c3b099",8)
	_builder.strand(hand,"OpposingThumb",[Vector3(0.047,0.038,-0.045),Vector3(0.056,0.017,-0.004),Vector3(0.028,0.004,0.045),Vector3(-0.005,-0.002,0.048)],[0.019,0.018,0.015,0.011],0.016,"#c3b099",8)
	_merge(hand)

func _build_leg(side: String) -> void:
	var thigh: Node3D = _attach(side + "_thigh")
	_builder.loft(thigh, "ThighCloth", [[0.025,0.10,0.094,0,0],[-0.10,0.112,0.101,0,0],[-0.25,0.09,0.088,0,0],[-0.33,0.081,0.079,0,0]], "#504940",20)
	_merge(thigh)
	var shin: Node3D = _attach(side + "_shin")
	_builder.loft(shin, "KneeAndShinCloth", [[0.035,0.06,0.061,0,0],[0,0.085,0.082,0,0],[-0.10,0.078,0.077,0,0],[-0.265,0.071,0.071,0,0]], "#504940",20)
	_builder.strand(shin,"KneeFold",[Vector3(-0.065,0.012,0.060),Vector3(0,-0.009,0.090),Vector3(0.065,0.012,0.06)],[0.007,0.013,0.006],0.007,"#766f60",6)
	for index: int in range(4):
		var y: float = -0.075 - index * 0.038
		_builder.loft(shin,"BroadWrap",[[y,0.080,0.080,0,0],[y-0.025,0.079,0.079,0,0]],"#a79b80" if index % 2 == 0 else "#887c65",20)
	_merge(shin)
	var foot: Node3D = _attach(side + "_foot")
	_builder.loft(foot,"BootAnkle",[[-0.04,0.082,0.096,0,0.015],[0.13,0.083,0.077,0,0],[0.15,0.086,0.075,0,0]],"#3e3730",20)
	_builder.bevel_box(foot,"RoundedBootToe",Vector3(0,-0.008,0.067),Vector3(0.181,0.112,0.29),"#443a31")
	_builder.bevel_box(foot,"LayeredSole",Vector3(0,-0.070,0.067),Vector3(0.188,0.020,0.298),"#786b55")
	_builder.strand(foot,"ToeLeatherFold",[Vector3(-0.068,0.04,0.12),Vector3(0,0.048,0.17),Vector3(0.068,0.04,0.12)],[0.005,0.008,0.005],0.006,"#75614a",6)
	_merge(foot)

func _build_staff() -> void:
	_staff = _node(self, "TwoHandedHardwoodStaff")
	_builder.beam(_staff,"HardwoodShaft",Vector3(0,-STAFF_HALF_LENGTH,0),Vector3(0,STAFF_HALF_LENGTH,0),0.034,"#765039",0.038,20)
	for end: float in [-1.0,1.0]:
		_builder.loft(_staff,"WeightedEndCap",[[end*0.765,0.043,0.043,0,0],[end*0.825,0.043,0.043,0,0]],"#a08b60",20)
	for grip_y: float in [-0.20,0.20]:
		for index: int in range(5):
			var y: float = grip_y - 0.055 + index * 0.023
			_builder.loft(_staff,"GripWrap",[[y,0.039,0.039,0,0],[y+0.017,0.040,0.040,0,0]],"#a58e67" if index%2==0 else "#806b50",16)
	for angle: float in [0.0,1.5,3.4,4.8]:
		_builder.strand(_staff,"LongWoodGrain",[Vector3(sin(angle)*0.035,-0.70,cos(angle)*0.035),Vector3(sin(angle)*0.037,0,cos(angle)*0.037),Vector3(sin(angle)*0.038,0.70,cos(angle)*0.038)],[0.002,0.003,0.002],0.002,"#a37b50",6)
	_merge(_staff)

func _target(label: String) -> void:
	_targets[label] = _node(self, label.capitalize().replace(" ", "") + "Target")

func _pole(label: String) -> void:
	_poles[label] = _node(self, label.capitalize().replace(" ", "") + "Pole")

func _build_modifiers() -> void:
	var ik := TwoBoneIK3D.new()
	ik.name = "NativeFourLimbIK"
	skeleton.add_child(ik)
	ik.set("setting_count",4)
	var rotation := CopyTransformModifier3D.new()
	rotation.name = "GripAndSoleOrientation"
	skeleton.add_child(rotation)
	rotation.set("setting_count",4)
	var index: int = 0
	for side: String in ["right","left"]:
		for limb: String in ["arm","leg"]:
			var end: String = side + ("_hand" if limb == "arm" else "_foot")
			ik.set_root_bone_name(index, side + ("_upper_arm" if limb == "arm" else "_thigh"))
			ik.set_middle_bone_name(index, side + ("_forearm" if limb == "arm" else "_shin"))
			ik.set_end_bone_name(index, end)
			ik.set_target_node(index,ik.get_path_to(_targets[end]))
			ik.set_pole_node(index,ik.get_path_to(_poles[side+"_"+limb]))
			rotation.set_apply_bone_name(index,end)
			rotation.set_reference_type(index,BoneConstraint3D.REFERENCE_TYPE_NODE)
			rotation.set_reference_node(index,rotation.get_path_to(_targets[end]))
			rotation.set_copy_flags(index,CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
			rotation.set_axis_flags(index,CopyTransformModifier3D.AXIS_FLAG_ALL)
			rotation.set_relative(index,false)
			rotation.set_additive(index,false)
			index += 1

func sample(pose: Dictionary) -> void:
	if not _ready_once:
		return
	_pose = pose.duplicate(true)
	_sample_revision += 1
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_position(_bones.pelvis, Vector3(0,0.66,0) + (pose.get("pelvis_position",Vector3(0,-0.022,0)) as Vector3))
	for label: String in ["pelvis","chest","head"]:
		skeleton.set_bone_pose_rotation(_bones[label],Quaternion.from_euler(pose.get(label+"_rotation",Vector3.ZERO)))
	_staff.position = pose.get("staff_position",Vector3(0,0.94,0.25))
	_staff.rotation = pose.get("staff_rotation",Vector3(0,0,-0.85))
	for side: String in ["right","left"]:
		var sign_x: float = -1.0 if side == "right" else 1.0
		var hand: Node3D = _targets[side+"_hand"]
		hand.transform = _staff.transform * Transform3D(Basis.IDENTITY,Vector3(0,sign_x*0.20,0))
		var foot: Node3D = _targets[side+"_foot"]
		var sole: Vector3 = pose.get(side+"_foot",Vector3(sign_x*0.15,0,0.10 if side == "left" else -0.08))
		foot.transform = Transform3D(Basis.from_euler(pose.get(side+"_foot_rotation",Vector3.ZERO)),sole+Vector3.UP*ANKLE_HEIGHT)
		(_poles[side+"_arm"] as Node3D).position = pose.get(side+"_pole",Vector3(sign_x*0.68,0.88,0.18))
		(_poles[side+"_leg"] as Node3D).position = pose.get(side+"_knee_pole",Vector3(sign_x*0.15,0.32,0.8))
	# Godot performs manual modifier updates in its deferred skeleton pass before
	# drawing. Capture the resulting bones from skeleton_updated, not input FK.
	skeleton.advance(0.0)

func set_refined_details(enabled: bool) -> void:
	_refined = enabled
	if _shell == null:
		return
	visible = enabled

func _capture_solved_pose() -> void:
	_solved.clear()
	for label: String in _bones:
		_solved[label] = skeleton.get_bone_global_pose(_bones[label])
	_solved_revision = _sample_revision

func get_weapon_anchors() -> Dictionary:
	if not is_instance_valid(_staff):
		return {}
	return {"base":_staff.to_global(Vector3(0,-STAFF_HALF_LENGTH,0)),"tip":_staff.to_global(Vector3(0,STAFF_HALF_LENGTH,0)),"right_grip":_staff.to_global(Vector3(0,-0.20,0)),"left_grip":_staff.to_global(Vector3(0,0.20,0)),"center":_staff.global_position}

func audit() -> Dictionary:
	var result: Dictionary = {"skeleton":is_instance_valid(skeleton),"bone_count":_bones.size(),"attachment_count":_attachments.size(),"sample_revision":_sample_revision,"solved_revision":_solved_revision,"refined_details":_refined,"pose":_pose.duplicate(true),"mesh_count":meshes.size(),"triangles":_triangle_count+int((_shell.call("audit") as Dictionary).get("triangles",0)) if _shell != null else _triangle_count,"clock":"external absolute sample; manual native modifiers","arms":{},"feet":{},"bone_poses":_solved.duplicate(true)}
	if not is_instance_valid(skeleton):
		return result
	for side: String in ["right","left"]:
		var hand_pose: Transform3D = _solved.get(side+"_hand",Transform3D.IDENTITY)
		var hand_target: Node3D = _targets[side+"_hand"]
		result.arms[side] = {"hand":hand_pose.origin,"target":hand_target.position,"grip_error":hand_pose.origin.distance_to(hand_target.position),"world_grip_error":(skeleton.global_transform*hand_pose.origin).distance_to(hand_target.global_position),"upper_length":UPPER_ARM,"lower_length":FOREARM}
		var foot_pose: Transform3D = _solved.get(side+"_foot",Transform3D.IDENTITY)
		var foot_target: Node3D = _targets[side+"_foot"]
		var sole: Vector3 = foot_pose.origin-foot_pose.basis.y*ANKLE_HEIGHT
		result.feet[side] = {"sole":sole,"target":foot_target.position-Vector3.UP*ANKLE_HEIGHT,"contact_error":sole.distance_to(foot_target.position-Vector3.UP*ANKLE_HEIGHT),"ankle_error":foot_pose.origin.distance_to(foot_target.position),"rotation_error":foot_pose.basis.get_rotation_quaternion().angle_to(foot_target.basis.get_rotation_quaternion())}
	result["anchors"] = get_weapon_anchors()
	return result

func _merge(parent: Node3D) -> void:
	var output := SurfaceTool.new()
	output.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sources: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		var source := child as MeshInstance3D
		if source == null or source.mesh == null:
			continue
		sources.append(source)
		var arrays: Array = source.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		_triangle_count += count/3
		for cursor: int in range(count):
			var index: int = indices[cursor] if not indices.is_empty() else cursor
			output.set_color(colors[index])
			output.set_normal((source.basis*normals[index]).normalized())
			output.add_vertex(source.transform*vertices[index])
	if sources.is_empty():
		return
	output.index()
	var merged := MeshInstance3D.new()
	merged.name = "MergedStaffCostume"
	merged.mesh = output.commit()
	merged.material_override = _matte
	parent.add_child(merged)
	meshes.append(merged)
	for source: MeshInstance3D in sources:
		source.free()
	_builder.meshes.clear()
