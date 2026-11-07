extends Node3D
## Jiang uses the verified original approved warm model and rig.
## Tinglan uses an independent combat candidate; three enemies remain procedural.
## Jiang always requires his approved production resource.
## Presentation only; no gameplay state or settlement.
const CharacterMesh = preload("res://addons/cultivation_mode/ambush_character_mesh.gd")
const StaffRig = preload("res://addons/cultivation_mode/ambush_staff_rig.gd")
const StaffMotion = preload("res://addons/cultivation_mode/ambush_staff_motion.gd")
const CharacterFinish = preload("res://addons/cultivation_mode/ambush_character_finish.gd")
const ApprovedJiang = preload("res://addons/cultivation_mode/ambush_jiang_actor.gd")
const APPROVED_JIANG_PATH: String = "res://assets/art/mountain_ambush/jiang-approved.glb"
const TINGLAN_ADAPTER_PATH: String = "res://addons/cultivation_mode/ambush_tinglan_actor.gd"
var _staff_rig: Node3D
var _staff_motion_enabled := true
var _staff_clock_external := false
var _staff_clip := "idle"
var _staff_seconds := 0.0
var _staff_context: Dictionary = {}
var _staff_pose: Dictionary = {}
var _approved_actor: Node3D
var _tinglan_actor: Node3D
var unit_id: String = ""
var role: String = ""
var body: Node3D
var right_arm: Node3D
var left_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var weapon: Node3D
var head: Node3D
var _builder: RefCounted
var _character_finish: RefCounted
var _original_enemy_meshes: Array[MeshInstance3D] = []
var _original_enemy_visibility: Array[bool] = []
var _refined_details: bool = true
var _meshes: Array[MeshInstance3D] = []
var _rest_rotations: Dictionary = {}
var _rest_positions: Dictionary = {}
var _flash: StandardMaterial3D
var _phase: float = 0.0
var _mode: String = "idle"
var _strength: float = 0.0
var _pose_time: float = 0.0
## Stage-local attack/recoil rate. Inspection and ordinary walking stay at 1x.
var action_playback_speed: float = 1.0
var _attack_timing: Dictionary = {}
var _attack_real_elapsed: float = 0.0
var _attack_source_clock: float = 0.0
var _attack_skill_id: String = ""
var _height: float = 1.94
var _friendly: bool = false
var _weapon_kind: String = "sword"
var _robe: String
var _robe_shadow: String
var _hair: String
var _skin: String
var _ivory: String = "#e7ddc6"
var _belt: String

func setup(id: String, actor_role: String, friendly: bool) -> void:
	unit_id = id
	role = actor_role
	_friendly = friendly
	if id == "player":
		var approved: Node3D = ApprovedJiang.new()
		approved.name = "ApprovedWarmJiang"
		add_child(approved)
		var loaded: Dictionary = approved.call("setup")
		if bool(loaded.get("ok", false)):
			_approved_actor = approved
			body = approved
			_height = float(loaded.get("height", 1.90))
			_meshes.assign(approved.get("meshes"))
			return
		push_error(str(loaded.get("reason", "Approved Jiang model is unavailable")))
		approved.queue_free()
		return
	if id == "tinglan":
		var candidate_script: Script = load(TINGLAN_ADAPTER_PATH) as Script
		if candidate_script == null:
			push_error("Tinglan candidate adapter is unavailable")
			return
		var candidate: Node3D = candidate_script.new() as Node3D
		if candidate == null:
			push_error("Tinglan candidate adapter is not Node3D")
			return
		candidate.name = "TinglanCombatCandidate"
		candidate.set_process(false)
		add_child(candidate)
		var loaded: Dictionary = candidate.call("setup")
		if bool(loaded.get("ok", false)):
			_tinglan_actor = candidate
			body = candidate
			_height = float(loaded.get("height", 1.90))
			_meshes.assign(candidate.get("meshes"))
			return
		push_error(str(loaded.get("reason", "Tinglan candidate model is unavailable")))
		candidate.queue_free()
		return
	_builder = CharacterMesh.new()
	body = Node3D.new()
	body.name = "AuthoredCombatFigure"
	add_child(body)
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1.0, 0.68, 0.40, 0.0)
	var tinglan: bool = id == "tinglan"
	var brute: bool = id == "brute" or role == "brute"
	var archer: bool = id == "archer" or role == "archer"
	_robe = "#3e6565" if tinglan else "#64859b" if friendly else "#7d705f" if brute else "#6c7560" if archer else "#6e717c"
	_robe_shadow = "#2e4e50" if tinglan else "#48667e" if friendly else "#5e584d" if brute else "#4d584b" if archer else "#4f5862"
	_hair = "#2e2a28" if tinglan else "#483126" if friendly else "#332f2b"
	_skin = "#e6b992" if friendly else "#c3b099" if brute else "#cbbba3"
	_belt = "#34474b" if tinglan else "#314f68" if friendly else "#504a40" if brute else "#545746" if archer else "#4e5158"
	if not friendly:
		_ivory = "#cec5b2"
	_build_body(tinglan, brute, archer)
	_build_face(tinglan, brute, archer)
	_build_hair(tinglan, brute, archer)
	_build_weapon(brute, archer)
	if not friendly:
		_refine_enemy_details(brute, archer)
	if brute:
		body.scale = Vector3(1.12, 0.97, 1.07)
		_height = 1.84
	elif archer:
		body.scale = Vector3(0.95, 1.0, 0.94)
		_height = 1.90
	elif id == "blade":
		body.scale = Vector3(0.93, 1.0, 0.91)
		_height = 1.91
	for node: Node3D in [body, right_arm, left_arm, left_leg, right_leg, head, weapon]:
		_rest_rotations[node] = node.rotation
		_rest_positions[node] = node.position
	_meshes.assign(_builder.meshes)
	if not friendly:
		_original_enemy_meshes.assign(_meshes)
		for mesh: MeshInstance3D in _original_enemy_meshes:
			_original_enemy_visibility.append(mesh.visible)
		_character_finish = CharacterFinish.new()
		_character_finish.call("build", {"body":body,"head":head,"left_arm":left_arm,"right_arm":right_arm,"left_leg":left_leg,"right_leg":right_leg,"weapon":weapon}, {"robe":_robe,"shadow":_robe_shadow,"skin":_skin}, brute, archer)
		_meshes.append_array(_character_finish.get("meshes"))
		set_refined_details(_refined_details)
	if id == "brute":
		_staff_rig = StaffRig.new() as Node3D
		_staff_rig.name = "ArticulatedStaffFigure"
		_staff_rig.scale = body.scale
		add_child(_staff_rig)
		_staff_rig.call("setup")
		_meshes.append_array(_staff_rig.get("meshes"))
		set_refined_details(_refined_details)
		sample_staff_motion("idle", 0.0)
	_phase = float(abs(id.hash()) % 100) * 0.1

func set_refined_details(enabled: bool) -> void:
	_refined_details = enabled
	if _character_finish == null:
		return
	for index: int in range(_original_enemy_meshes.size()):
		_original_enemy_meshes[index].visible = _original_enemy_visibility[index] and not enabled
	_character_finish.call("set_enabled", enabled and not staff_motion_active())
	if is_instance_valid(_staff_rig):
		_staff_rig.call("set_refined_details", staff_motion_active())

func detail_audit() -> Dictionary:
	var result: Dictionary = {"enabled":_refined_details,"applicable":_character_finish != null,"unit_id":unit_id,"original_mesh_count":_original_enemy_meshes.size(),"original_visible_mesh_count":0,"mesh_count":0,"triangles":0,"pose_authority":"existing actor"}
	for mesh: MeshInstance3D in _original_enemy_meshes:
		if mesh.is_visible_in_tree():
			result.original_visible_mesh_count += 1
	if _character_finish != null:
		result.merge(_character_finish.call("audit"), true)
	result["enabled"] = _refined_details
	result["active_geometry"] = "articulated_staff" if staff_motion_active() else "legacy_enemy"
	if is_instance_valid(_staff_rig):
		result["staff_rig"] = _staff_rig.call("audit")
	return result

func staff_motion_active() -> bool:
	return is_instance_valid(_staff_rig) and _staff_motion_enabled and _refined_details

func set_staff_motion_enabled(enabled: bool) -> void:
	_staff_motion_enabled = enabled
	set_refined_details(_refined_details)
	if is_instance_valid(_staff_rig):
		sample_staff_motion(_staff_clip, _staff_seconds, _staff_context)

func set_staff_clock_external(enabled: bool) -> void:
	_staff_clock_external = enabled

func staff_clip_duration(clip: String) -> float:
	return StaffMotion.duration(clip)

func sample_staff_motion(clip: String, seconds: float, context: Dictionary = {}) -> void:
	if not is_instance_valid(_staff_rig):
		return
	_staff_clip = clip
	_staff_seconds = maxf(0.0, seconds)
	_staff_context = context.duplicate(true)
	_staff_pose = StaffMotion.sample(clip, _staff_seconds, context)
	_mode = "attack" if clip == "attack" else ("hit" if clip in ["recoil", "interrupt", "stagger"] else ("idle" if clip == "intent" else clip))
	_pose_time = _staff_seconds
	_attack_real_elapsed = _staff_seconds
	_attack_source_clock = _staff_seconds
	_reset_pose()
	if staff_motion_active():
		_staff_rig.call("sample", _staff_pose)
	else:
		_sample_legacy_staff(clip, _staff_seconds)
	if clip in ["recoil", "interrupt", "stagger"]:
		var flash_weight := sin(clampf(_staff_seconds / 0.28, 0.0, 1.0) * PI)
		_flash.albedo_color.a = flash_weight * 0.20
		for mesh: MeshInstance3D in _meshes:
			mesh.material_overlay = _flash if flash_weight > 0.02 else null

func _sample_legacy_staff(clip: String, seconds: float) -> void:
	# The original archived geometry and shoulder-only gesture remain available
	# for comparison at the same normalized phrase position. No second clock.
	var t := clampf(seconds / StaffMotion.duration(clip), 0.0, 1.0)
	if clip == "attack":
		var stroke := sin(clampf(t * 0.31 / 0.29, 0.0, 1.0) * PI)
		body.rotation.y += stroke * 0.16
		body.rotation.z -= stroke * 0.055
		right_arm.rotation.x += stroke * 1.05
		right_arm.rotation.z -= stroke * 0.38
		left_arm.rotation.x -= stroke * 0.30
	elif clip == "walk":
		right_leg.rotation.x += sin(seconds * 23.0) * 0.23
		left_leg.rotation.x -= sin(seconds * 23.0) * 0.23
	elif clip in ["recoil", "interrupt", "stagger"]:
		body.rotation.x -= sin(t * PI) * 0.16
		body.rotation.z += sin(seconds * 50.0) * sin(t * PI) * 0.045

func staff_motion_audit() -> Dictionary:
	return {"applicable": is_instance_valid(_staff_rig), "enabled": _staff_motion_enabled,
		"active": staff_motion_active(), "external_clock": _staff_clock_external, "clip": _staff_clip, "time": _staff_seconds,
		"duration": StaffMotion.duration(_staff_clip), "phase": _staff_pose.get("phase", "guard"),
		"root_transform": transform, "pose": _staff_pose.duplicate(true),
		"rig": _staff_rig.call("audit") if is_instance_valid(_staff_rig) else {},
		"authority": "presentation only; external absolute sampling"}

func _pivot(parent: Node3D, name: String, at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = name
	node.position = at
	parent.add_child(node)
	return node

func _build_body(tinglan: bool, brute: bool, archer: bool) -> void:
	# Tapered torso, open overlapping coat and continuous bent sleeves.
	_builder.loft(body, "ShapedTorso", [[0.72,0.18,0.135,0,0], [0.81,0.21,0.155,0,0], [1.00,0.225 if tinglan else 0.24 if not brute else 0.27,0.17,0,0], [1.10,0.235 if tinglan else 0.25 if not brute else 0.29,0.15,0,-0.01], [1.17,0.105,0.09,0,0]], _robe, 20)
	_builder.loft(body, "Neck", [[1.13,0.085,0.08,0,0], [1.335 if not _friendly else 1.26,0.060 if not _friendly else 0.075,0.057 if not _friendly else 0.070,0,0]], _skin, 16)
	for side: int in [-1, 1]:
		var leg: Node3D = _pivot(body, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.105, 0.66, 0))
		if side < 0:
			left_leg = leg
		else:
			right_leg = leg
		_builder.loft(leg, "ShapedTrousers", [[-0.50,0.062,0.065,0,0], [-0.39,0.075,0.077,0,0], [-0.25,0.09,0.09,0,0.015], [-0.10,0.115,0.10,0,0], [0.035,0.10,0.09,0,0]], "#354756" if _friendly else "#494640", 14)
		_builder.loft(leg, "BootAnkle", [[-0.59,0.086,0.095,0,0.035], [-0.44,0.081,0.075,0,0.015], [-0.42,0.087,0.075,0,0.015]], "#3c3430", 14)
		_builder.bevel_box(leg, "BootToe", Vector3(0,-0.595,0.065), Vector3(0.18,0.13,0.29), "#3a322d")
		_builder.bevel_box(leg, "BootSole", Vector3(0,-0.645,0.065), Vector3(0.185,0.03,0.295), "#4a4943" if not _friendly else "#5b554a")
		if brute or archer:
			for band: int in range(3):
				_builder.loft(leg, "LegBinding", [[-0.46+float(band)*0.055,0.084,0.083,0,0.014], [-0.44+float(band)*0.055,0.084,0.083,0,0.014]], "#928c79", 12)
	# Distinct skirt panels wrap around the hips and leave real centre gaps.
	var hem_y: float = 0.32 if tinglan else 0.51 if _friendly else 0.51
	for i: int in range(8):
		var centre: float = (float(i)+0.5) * TAU/8.0
		var a: float = centre-0.355
		var b: float = centre+0.355
		var hem: float = hem_y + (0.025 if i % 2 else 0.0)
		var left: Array = [Vector3(sin(a)*0.205,0.78,cos(a)*0.157),Vector3(sin(a)*0.26,0.59,cos(a)*0.205),Vector3(sin(a)*0.30,hem,cos(a)*0.238)]
		var right: Array = [Vector3(sin(b)*0.205,0.78,cos(b)*0.157),Vector3(sin(b)*0.26,0.59,cos(b)*0.205),Vector3(sin(b)*0.30,hem+0.012,cos(b)*0.238)]
		_builder.panel(body,"CoatPanel"+str(i),left,right,_robe if i < 2 or i > 5 else _robe_shadow)
		if _friendly:
			_builder.curved_strip(body,"PanelPiping"+str(i),left,[0.008,0.007,0.007],"#a8aa87" if tinglan else "#b3b697")
	# Real flat, crossing collar bands over the shaped torso.
	_builder.panel(body,"InnerCrossCollar",[Vector3(-0.12,1.16,0.08),Vector3(-0.08,1.07,0.165),Vector3(0.035,1.01,0.186)],[Vector3(-0.065,1.17,0.085),Vector3(-0.02,1.075,0.18),Vector3(0.065,1.035,0.188)],_ivory)
	_builder.panel(body,"OuterCrossCollar",[Vector3(0.11,1.16,0.09),Vector3(0.06,1.065,0.188),Vector3(-0.11,0.86,0.18)],[Vector3(0.17,1.14,0.09),Vector3(0.12,1.04,0.192),Vector3(-0.045,0.85,0.185)],_ivory if _friendly else "#b6a68b")
	_builder.curved_strip(body,"CollarBlueEdge",[Vector3(0.12,1.168,0.10),Vector3(0.065,1.064,0.20),Vector3(-0.10,0.867,0.20)],[0.012,0.012,0.009],_robe_shadow)
	_builder.loft(body,"WrapWaistSash",[[0.745,0.217,0.17,0,0],[0.775,0.225,0.174,0,0],[0.835,0.219,0.169,0,0]],_belt,20)
	_builder.bevel_box(body,"SashKnot",Vector3(-0.04,0.795,0.185),Vector3(0.10,0.065,0.045),"#b39a65" if _friendly else "#887351")
	for side: int in [-1,1]:
		_builder.curved_strip(body,"HangingSash",[Vector3(side*0.045,0.785,0.20),Vector3(side*0.13,0.66,0.25),Vector3(side*0.17,0.48,0.28)],[0.023,0.022,0.015],_belt)
		var arm: Node3D = _pivot(body,"RightShoulder" if side < 0 else "LeftShoulder",Vector3(side*(0.235 if tinglan else 0.25 if not brute else 0.28),1.08,0))
		if side < 0:
			right_arm = arm
		else:
			left_arm = arm
		var sleeve: String = _ivory if unit_id == "player" else _robe
		var shoulder_top: Array = [Vector3(side*0.16,1.125,0.11),Vector3(side*(0.36 if brute else 0.33),1.08,0.07),Vector3(side*(0.36 if brute else 0.33),1.08,-0.075),Vector3(side*0.16,1.125,-0.09)]
		if ((shoulder_top[1]-shoulder_top[0]).cross(shoulder_top[2]-shoulder_top[0]) as Vector3).y < 0:
			shoulder_top.reverse()
		_builder.polygon(body,"ClosedRaglanShoulder",shoulder_top,sleeve)
		if brute:
			_builder.strand(arm,"ShortJacketSleeve",[Vector3(0,0,0),Vector3(side*0.04,-0.10,0.005),Vector3(side*0.055,-0.175,0.03)],[0.12,0.14,0.13],0.12,sleeve,12)
			_builder.strand(arm,"StrongForearm",[Vector3(side*0.055,-0.16,0.03),Vector3(side*0.06,-0.23,0.06),Vector3(side*0.035,-0.32,0.12)],[0.108,0.105,0.083],0.092,_skin,12)
		else:
			_builder.strand(arm,"ContinuousBentSleeve",[Vector3(0,0,0),Vector3(side*0.04,-0.10,0.005),Vector3(side*0.06,-0.21,0.045),Vector3(side*0.035,-0.31,0.11)],[0.105,0.123,0.113,0.092],0.105,sleeve,12)
		_builder.strand(arm,"ClothWristCuff",[Vector3(side*0.037,-0.27,0.09),Vector3(side*0.035,-0.33,0.12)],[0.098,0.095],0.09,_robe_shadow,12)
		_builder.strand(arm,"BroadCuffBinding",[Vector3(side*0.036,-0.29,0.10),Vector3(side*0.035,-0.311,0.112)],[0.096,0.095],0.091,"#8d8a79" if not _friendly else "#9e9472",12)
		_builder.loft(arm,"ShapedHand",[[-0.397,0.045,0.045,side*0.035,0.15],[-0.375,0.062,0.056,side*0.035,0.15],[-0.335,0.057,0.051,side*0.035,0.14]],_skin,12)
		_builder.curved_strip(arm,"SingleFingerCrease",[Vector3(side*0.035-0.030,-0.377,0.202),Vector3(side*0.035+0.029,-0.377,0.202)],[0.0015,0.0015],"#bb8e6d")
		if side < 0:
			weapon=_pivot(arm,"HeldWeapon",Vector3(side*0.035,-0.365,0.155))
		arm.rotation.x=-0.10 if side < 0 else -0.23
		arm.rotation.z=side*0.045

func _build_face(tinglan: bool, brute: bool, archer: bool) -> void:
	head=_pivot(body,"SculptedHead",Vector3(0,1.48,0))
	if tinglan:
		head.scale=Vector3(0.95,1.025,0.97)
	elif not _friendly:
		# Scale the face, hair and hat together. Keep the crown height while
		# removing the round doll-like width beside the two source models.
		head.position.y = 1.565
		head.scale = Vector3(0.70 if brute or archer else 0.68, 0.86, 0.70 if brute or archer else 0.68)
	_builder.loft(head,"TaperedCheeksAndChin",_builder.face_rings(),_skin,32)
	for side: int in [-1,1]:
		var ear: MeshInstance3D = _builder.loft(head,"Ear",[[-0.125,0.028,0.025,side*0.268,0],[-0.08,0.046,0.036,side*0.275,0],[-0.015,0.028,0.025,side*0.268,0]],_skin,12)
		ear.rotation.z=side*0.10
		var x: float=side*0.111
		var eye_y: float=0.023
		var eye_h: float=0.047 if tinglan else 0.059 if _friendly else 0.035
		var eye_w: float=0.075 if tinglan else 0.073
		var whites: Array = []
		for sample: int in range(20):
			var angle: float = TAU * float(sample) / 20.0
			whites.append(Vector2(x + cos(angle) * eye_w, eye_y + sin(angle) * eye_h * (1.0 if sin(angle) >= 0.0 else 0.69)))
		_builder.face_patch(head,"AlmondEyeWhite",whites,"#f3e7d1",0.003)
		_builder.face_oval(head,"Iris",Vector2(x,eye_y+0.002),Vector2(0.028,eye_h*0.80),"#626978" if tinglan else "#84603d" if _friendly else "#594632",0.006)
		_builder.face_oval(head,"Pupil",Vector2(x,eye_y+0.005),Vector2(0.014,eye_h*0.64),"#282523",0.008)
		_builder.face_oval(head,"EyeCatchlight",Vector2(x-0.010,eye_y+0.020),Vector2(0.009,0.012),"#fff3dc",0.010,10)
		_builder.face_patch(head,"UpperLid",[Vector2(x-eye_w,eye_y+0.004),Vector2(x-eye_w*0.52,eye_y+eye_h*1.03),Vector2(x+eye_w*0.45,eye_y+eye_h*1.08),Vector2(x+eye_w*1.05,eye_y+0.010),Vector2(x+eye_w*0.44,eye_y+eye_h*0.91),Vector2(x-eye_w*0.50,eye_y+eye_h*0.91)],"#49372b",0.011)
		var brow_y: float=0.118 if _friendly else 0.106
		_builder.face_patch(head,"Eyebrow",[Vector2(x-0.064,brow_y),Vector2(x-0.030,brow_y+0.015),Vector2(x+0.047,brow_y+0.010),Vector2(x+0.059,brow_y-0.001),Vector2(x-0.020,brow_y+0.003)],_hair,0.004)
		if _friendly:
			_builder.face_oval(head,"SoftCheekTint",Vector2(side*0.174,-0.076),Vector2(0.034,0.013),"#dca58c",0.003,12)
	_builder.polygon(head,"SubtleNose",[Vector3(-0.014,-0.060,_builder.face_z(-0.014,-0.06)+0.003),Vector3(0.008,-0.052,0.252),Vector3(0.015,-0.073,0.241),Vector3(-0.005,-0.081,0.243)],"#c9b59a" if not _friendly else "#d6aa87")
	_builder.face_patch(head,"SmallMouth",[Vector2(-0.030,-0.153),Vector2(-0.007,-0.150),Vector2(0.024,-0.155),Vector2(0.026,-0.160),Vector2(-0.009,-0.157),Vector2(-0.031,-0.158)],"#946e58",0.004)
	if brute:
		_builder.face_patch(head,"StubbleChin",[Vector2(-0.115,-0.17),Vector2(-0.08,-0.235),Vector2(0,-0.263),Vector2(0.08,-0.235),Vector2(0.115,-0.17),Vector2(0.06,-0.205),Vector2(-0.06,-0.205)],"#765947",0.004)

func _build_hair(tinglan: bool, brute: bool, archer: bool) -> void:
	if brute:
		_builder.loft(head,"RoughScalpHair",[[0.16,0.280,0.246,0,-0.005],[0.245,0.230,0.193,0,-0.012],[0.315,0.10,0.09,0,-0.012],[0.345,0.005,0.005,0,-0.012]],_hair,24)
		_builder.loft(head,"TiedHeadCloth",[[0.12,0.287,0.252,0,-0.004],[0.175,0.282,0.248,0,-0.008]],"#6d6255",24)
		_builder.curved_strip(head,"HeadwrapTail",[Vector3(0.20,0.15,-0.16),Vector3(0.29,0.03,-0.22),Vector3(0.28,-0.10,-0.20)],[0.035,0.031,0.012],"#6d6255")
		return
	# Single continuous cap with an authored hairline and broad pointed locks.
	var vertices: Array=[]
	var rows: int=8
	var segments: int=28
	for row: int in range(rows):
		for i: int in range(segments):
			var a: float=TAU*float(i)/float(segments)
			var b: float=TAU*float(i+1)/float(segments)
			var points: Array=[_cap_point(a,float(row)/float(rows)),_cap_point(b,float(row)/float(rows)),_cap_point(b,float(row+1)/float(rows)),_cap_point(a,float(row+1)/float(rows))]
			vertices.append_array([points[0],points[1],points[2],points[0],points[2],points[3]])
	_builder.make_mesh(head,"ContinuousHairCap",vertices,_hair)
	var light_hair: String="#4a4540" if tinglan else "#644735" if _friendly else "#503d30"
	var bangs: Array=[
		[Vector3(-0.14,0.275,0.105),Vector3(-0.20,0.18,0.23),Vector3(-0.23,0.02,0.22),Vector3(-0.225,-0.13,0.17)],
		[Vector3(0.03,0.31,0.09),Vector3(-0.05,0.23,0.23),Vector3(-0.09,0.13,0.25),Vector3(-0.12,0.065,0.24)],
		[Vector3(0.10,0.30,0.07),Vector3(0.14,0.21,0.23),Vector3(0.17,0.10,0.24),Vector3(0.20,0.025,0.20)],
		[Vector3(0.19,0.23,0.06),Vector3(0.25,0.12,0.18),Vector3(0.26,-0.04,0.15),Vector3(0.245,-0.17,0.10)]]
	for i: int in range(bangs.size()):
		_builder.strand(head,"SweptHairLock"+str(i),bangs[i],[0.035,0.075 if i != 1 else 0.085,0.050,0.003],0.030,_hair,8)
		var path: Array=bangs[i]
		_builder.curved_strip(head,"QuietHairHighlight"+str(i),[path[0]+Vector3(0,0,0.012),path[1]+Vector3(0,0,0.034),path[2]+Vector3(0,0,0.021)],[0.004,0.008,0.001],light_hair)
	if archer:
		_build_hat()
		return
	if unit_id == "blade":
		_builder.loft(head,"ShortTiedTopknot",[[0.26,0.078,0.065,0,-0.12],[0.35,0.085,0.075,0,-0.13],[0.39,0.035,0.03,0,-0.13]],_hair,16)
		_builder.loft(head,"DarkClothHairTie",[[0.285,0.088,0.075,0,-0.13],[0.315,0.088,0.075,0,-0.13]],"#77514c",16)
		_builder.strand(head,"ShortBackHair",[Vector3(0,0.34,-0.13),Vector3(0.06,0.25,-0.26),Vector3(0.04,0.01,-0.32),Vector3(-0.04,-0.13,-0.27)],[0.045,0.065,0.052,0.003],0.033,_hair,8)
		return
	var tie_color: String="#66938e" if tinglan else "#a7c6ce"
	_builder.loft(head,"BoundPonytailRoot",[[0.275,0.09,0.07,0,-0.12],[0.34,0.105,0.09,0,-0.14],[0.39,0.075,0.065,0,-0.15]],_hair,16)
	_builder.loft(head,"PonytailClothTie",[[0.285,0.112,0.085,0,-0.13],[0.318,0.112,0.085,0,-0.13]],tie_color,16)
	var tail_end: float=-0.69 if tinglan else -0.14
	for i: int in range(3):
		var offset: float=(float(i)-1.0)*0.07
		var points: Array=[Vector3(offset*0.4,0.35,-0.15),Vector3(0.08+offset,0.32,-0.32),Vector3(0.14+offset,0.02 if tinglan else 0.20,-0.47),Vector3(0.04+offset,-0.29 if tinglan else 0.03,-0.49 if tinglan else -0.43),Vector3(-0.04+offset,tail_end,-0.34)]
		_builder.strand(head,"LongPonytailLock"+str(i),points,[0.065,0.10 if tinglan else 0.13,0.09 if tinglan else 0.12,0.065,0.002],0.050,_hair,10)
		if i==1:
			_builder.curved_strip(head,"PonytailHighlight",[points[1]+Vector3(0,0,-0.048),points[2]+Vector3(0,0,-0.049),points[3]+Vector3(0,0,-0.035)],[0.010,0.008,0.001],light_hair)
	for side: int in [-1,1]:
		_builder.curved_strip(head,"PonytailRibbon",[Vector3(side*0.05,0.32,-0.17),Vector3(side*0.18,0.24,-0.28),Vector3(side*0.20,-0.04 if tinglan else 0.16,-0.43),Vector3(side*0.25,-0.40 if tinglan else -0.02,-0.44)],[0.04,0.039,0.031,0.022],tie_color)
		_builder.curved_strip(head,"RibbonBowLoop",[Vector3(side*0.015,0.31,-0.19),Vector3(side*0.16,0.37,-0.18),Vector3(side*0.22,0.28,-0.20),Vector3(side*0.06,0.285,-0.22)],[0.025,0.033,0.025,0.012],tie_color)

func _cap_point(angle: float, t: float) -> Vector3:
	var front: float = maxf(0.0, cos(angle))
	var edge_y: float = lerpf(-0.16, 0.155, pow(front, 1.4))
	var y: float = lerpf(0.345, edge_y, t)
	var rx: float = 0.008
	var rz: float = 0.008
	var cz: float = -0.012
	var rings: Array = _builder.face_rings()
	for i: int in range(rings.size() - 1):
		if y >= float(rings[i][0]) and y <= float(rings[i + 1][0]):
			var blend: float = inverse_lerp(float(rings[i][0]), float(rings[i + 1][0]), y)
			rx = lerpf(float(rings[i][1]), float(rings[i + 1][1]), blend)
			rz = lerpf(float(rings[i][2]), float(rings[i + 1][2]), blend)
			cz = lerpf(float(rings[i][4]), float(rings[i + 1][4]), blend)
	return Vector3(sin(angle) * (rx + 0.023), y, cos(angle) * (rz + 0.023) + cz - 0.002)

func _build_hat() -> void:
	_builder.loft(head,"WovenTravellerHat",[[0.14,0.38,0.34,0,-0.025],[0.17,0.385,0.345,0,-0.025],[0.285,0.18,0.16,0,-0.025],[0.36,0.035,0.03,0,-0.025]],"#a8956c",28)
	for i: int in range(14):
		var a: float=TAU*float(i)/14.0
		_builder.curved_strip(head,"HatWeaveRib",[Vector3(sin(a)*0.035,0.36,cos(a)*0.03-0.025),Vector3(sin(a)*0.18,0.288,cos(a)*0.16-0.025),Vector3(sin(a)*0.38,0.173,cos(a)*0.34-0.025)],[0.004,0.005,0.004],"#857754")
	for side: int in [-1,1]:
		_builder.curved_strip(head,"HatChinCord",[Vector3(side*0.24,0.14,0.09),Vector3(side*0.21,-0.15,0.16),Vector3(side*0.08,-0.27,0.15)],[0.005,0.005,0.004],"#735c41")

func _build_weapon(brute: bool, archer: bool) -> void:
	if archer:
		_weapon_kind="bow"
		var points: Array=[]
		for i: int in range(11):
			var a: float=-PI*0.5+PI*float(i)/10.0
			points.append(Vector3(0.16*cos(a),0.10+0.37*sin(a),0.018))
		_builder.strand(weapon,"BentWoodBow",points,[0.012,0.015,0.018,0.020,0.021,0.023,0.021,0.020,0.018,0.015,0.012],0.016,"#805d3d",8)
		_builder.beam(weapon,"BowString",Vector3(0,-0.27,0.018),Vector3(0,0.47,0.018),0.003,"#dfd3af")
		var quiver: Node3D=_pivot(body,"BackQuiver",Vector3(0.16,0.96,-0.20))
		quiver.rotation.z=0.20
		_builder.loft(quiver,"LeatherArrowCase",[[-0.22,0.08,0.065,0,0],[0.19,0.09,0.07,0,0],[0.22,0.10,0.075,0,0]],"#6c5038",12)
		for i: int in range(3):
			var x: float=-0.045+float(i)*0.042
			_builder.beam(quiver,"ArrowShaft",Vector3(x,0.13,0),Vector3(x,0.45,0),0.006,"#c7b28a")
			_builder.polygon(quiver,"ArrowFeather",[Vector3(x,0.40,0),Vector3(x+0.032,0.47,0),Vector3(x,0.46,0),Vector3(x-0.032,0.42,0)],"#b9b5a0")
		return
	if brute:
		_weapon_kind="staff"
		_builder.beam(weapon,"HeavyWoodStaff",Vector3(0,-0.27,0),Vector3(0,0.78,0),0.032,"#77513a",0.043)
		for i: int in range(5):
			_builder.loft(weapon,"StaffGripBinding",[[-0.10+float(i)*0.035,0.036,0.036,0,0],[-0.083+float(i)*0.035,0.036,0.036,0,0]],"#b7a27a",12)
		_builder.loft(weapon,"StaffEndCap",[[0.74,0.045,0.045,0,0],[0.81,0.045,0.045,0,0]],"#9c8960",12)
		weapon.rotation.x=0.16
		return
	var blade: bool=unit_id=="blade"
	_builder.beam(weapon,"WrappedSwordGrip",Vector3(0,-0.115,0),Vector3(0,0.035,0),0.022,"#3b4b47")
	_builder.bevel_box(weapon,"SwordGuard",Vector3(0,0.035,0),Vector3(0.15,0.027,0.042),"#b39b66")
	var right: Array=[Vector3(0.020,0.05,0),Vector3(0.026 if blade else 0.021,0.51,0),Vector3(0.012,0.66,0),Vector3(-0.003,0.72,0)]
	var left: Array=[Vector3(-0.022,0.05,0),Vector3(-0.036 if blade else -0.021,0.51,0),Vector3(-0.018,0.66,0),Vector3(-0.003,0.72,0)]
	_builder.panel(weapon,"SteelBlade",left,right,"#96a7a2")
	_builder.loft(weapon,"SteelBladeSection",[[0.05,0.022,0.010,0,0],[0.50,0.021,0.009,0,0],[0.66,0.010,0.005,-0.002,0],[0.72,0.001,0.001,-0.003,0]],"#96a7a2",4)
	_builder.curved_strip(weapon,"SwordCentralRidge",[Vector3(0,0.05,0.009),Vector3(0,0.51,0.009),Vector3(-0.003,0.71,0.002)],[0.006,0.006,0.001],"#e8e4ce")
	weapon.rotation.z=PI-0.34
	weapon.rotation.x=-0.05
	var scabbard: Node3D=_pivot(body,"HipScabbard",Vector3(0.21,0.76,-0.035))
	scabbard.rotation.z=-0.45
	_builder.beam(scabbard,"Scabbard",Vector3.ZERO,Vector3(0,-0.52,0),0.026,_robe_shadow)
	_builder.beam(scabbard,"ScabbardChape",Vector3(0,-0.47,0),Vector3(0,-0.54,0),0.028,"#a49162")

func _refine_enemy_details(brute: bool, archer: bool) -> void:
	# Broad folds and worn edges are visible at the same scale as the approved
	# hero's clothing. Avoid miniature ornaments or extra texture dependencies.
	var seam: String = "#918774" if brute else "#87917c" if archer else "#9496a0"
	_builder.curved_strip(body, "LeftClothFold", [Vector3(-0.12,1.04,0.153),Vector3(-0.13,0.94,0.160),Vector3(-0.08,0.85,0.180)], [0.006,0.010,0.002], seam)
	_builder.curved_strip(body, "RightClothFold", [Vector3(0.13,1.00,0.150),Vector3(0.12,0.92,0.164),Vector3(0.15,0.85,0.170)], [0.004,0.008,0.002], _robe_shadow)
	for y: float in [0.759, 0.821]:
		_builder.loft(body, "SashTurnedEdge", [[y,0.224,0.178,0,0],[y+0.009,0.224,0.178,0,0]], "#746e5f", 16)
	for leg: Node3D in [left_leg, right_leg]:
		_builder.loft(leg, "BootTurnedLeather", [[-0.465,0.084,0.079,0,0.014],[-0.448,0.087,0.079,0,0.014]], "#57544b", 12)
		_builder.curved_strip(leg, "BootCrease", [Vector3(-0.046,-0.51,0.097),Vector3(0.002,-0.52,0.113),Vector3(0.050,-0.51,0.097)], [0.002,0.004,0.002], "#655f52")
	if brute:
		_builder.panel(body, "RepairedJacketPanel", [Vector3(-0.195,1.01,0.128),Vector3(-0.178,0.90,0.145)], [Vector3(-0.117,1.015,0.157),Vector3(-0.110,0.90,0.171)], "#6d6456")
		_builder.curved_strip(body, "RepairSeam", [Vector3(-0.195,1.015,0.131),Vector3(-0.158,1.020,0.151),Vector3(-0.117,1.020,0.161)], [0.003,0.003,0.003], "#a29882")
	elif archer:
		_builder.panel(body, "QuiverShoulderStrap", [Vector3(0.17,1.115,0.114),Vector3(-0.03,0.94,0.184),Vector3(-0.17,0.82,0.125)], [Vector3(0.205,1.10,0.092),Vector3(0.01,0.92,0.186),Vector3(-0.135,0.80,0.152)], "#615f4e")
		_builder.bevel_box(body, "TravelPouch", Vector3(-0.213,0.77,0.092), Vector3(0.095,0.14,0.065), "#706a55")
	else:
		_builder.panel(body, "OverlappingShoulderCloth", [Vector3(-0.11,1.16,0.103),Vector3(-0.20,1.08,0.114),Vector3(-0.17,0.94,0.154)], [Vector3(-0.17,1.15,0.090),Vector3(-0.25,1.07,0.077),Vector3(-0.22,0.94,0.106)], "#59616b")
		_builder.curved_strip(body, "DiagonalWrapEdge", [Vector3(0.12,1.06,0.179),Vector3(0.02,0.97,0.194),Vector3(-0.10,0.88,0.187)], [0.007,0.007,0.003], "#8c8d91")
	# Hex palettes are sRGB, including the vertex colors written by the mesh
	# builder. Explicit consumption avoids the bright, waxy linear-color look.
	for value: Variant in _builder.materials.values():
		var material := value as StandardMaterial3D
		material.vertex_color_is_srgb = true
		material.roughness = 0.96
		material.metallic_specular = 0.14
	for mesh: MeshInstance3D in _builder.meshes:
		var mesh_name: String = str(mesh.name)
		if mesh_name == "TaperedCheeksAndChin" or mesh_name == "ShapedTorso" or mesh_name.begins_with("CoatPanel"):
			_shade_enemy_surface(mesh, mesh_name == "TaperedCheeksAndChin")
		elif mesh_name.begins_with("SteelBlade") or mesh_name == "SwordCentralRidge":
			var steel := (mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			steel.roughness = 0.68
			steel.metallic = 0.12
			steel.metallic_specular = 0.30
			mesh.material_override = steel

func _shade_enemy_surface(mesh: MeshInstance3D, facial: bool) -> void:
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.size() != vertices.size():
		return
	for index: int in range(vertices.size()):
		var at: Vector3 = vertices[index]
		var amount: float
		if facial:
			# A quiet jaw/temple value change keeps the face from reading as one
			# orange sphere; live scene lights still supply the actual shading.
			amount = lerpf(0.13, 0.015, clampf((at.y + 0.29) / 0.60, 0.0, 1.0))
			amount += 0.025 if at.z < 0.03 else 0.0
		else:
			amount = lerpf(0.09, 0.0, clampf((at.y - 0.50) / 0.65, 0.0, 1.0))
		colors[index] = colors[index].darkened(amount)
	arrays[Mesh.ARRAY_COLOR] = colors
	var refined := ArrayMesh.new()
	refined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = refined

func get_visual_height() -> float:
	return _height

func approved_model_active() -> bool:
	return is_instance_valid(_approved_actor)

func candidate_model_active() -> bool:
	return is_instance_valid(_tinglan_actor)

func get_animation_audit() -> Dictionary:
	var result: Dictionary
	if is_instance_valid(_approved_actor):
		result = _approved_actor.call("audit")
	elif is_instance_valid(_tinglan_actor):
		result = _tinglan_actor.call("audit")
	else:
		result = {"approved": false, "mode": _mode, "elapsed": _pose_time}
	if is_instance_valid(_staff_rig):
		result["staff_motion"] = staff_motion_audit()
	result["attack_real_elapsed"] = _attack_real_elapsed
	result["attack_timing_enabled"] = not _attack_timing.is_empty()
	result["attack_source_clock"] = _attack_source_clock
	return result

func set_attack_timing(timing: Dictionary) -> void:
	# Opt-in at the battlefield. An inspector without this configuration keeps
	# the original direct source-time API and action_playback_speed behavior.
	var checked: Dictionary = {}
	for key: String in ["ready_seconds", "strike_seconds", "hit_stop_seconds", "follow_through_seconds", "recover_seconds"]:
		var value: Variant = timing.get(key)
		if (not value is float and not value is int) or not is_finite(float(value)) or float(value) < 0.0 or (key != "hit_stop_seconds" and float(value) == 0.0):
			_attack_timing.clear()
			return
		checked[key] = float(value)
	_attack_timing = checked

func _attack_duration() -> float:
	var duration: float = 0.0
	for value: Variant in _attack_timing.values():
		duration += float(value)
	return duration

func _attack_source_end() -> float:
	if is_instance_valid(_approved_actor):
		return float(_approved_actor.call("attack_duration"))
	if is_instance_valid(_tinglan_actor):
		var script: Script = _tinglan_actor.get_script() as Script
		var constants: Dictionary = script.get_script_constant_map()
		return float(constants["INTERRUPT_SECONDS" if _attack_skill_id == "interrupt" else "SWORD_SECONDS"])
	return 0.31

func _attack_source_at(real_seconds: float) -> float:
	var keys: Array[String] = ["ready_seconds", "strike_seconds", "hit_stop_seconds", "follow_through_seconds", "recover_seconds"]
	var ends: Array[float] = [0.065, 0.13, 0.13, 0.225, _attack_source_end()]
	if real_seconds + 0.0000001 >= _attack_duration():
		return ends[-1]
	var previous: float = 0.0
	var remaining: float = maxf(0.0, real_seconds)
	for index: int in range(keys.size()):
		var duration: float = float(_attack_timing[keys[index]])
		if duration > 0.0 and remaining <= duration:
			return lerpf(previous, ends[index], clampf(remaining / duration, 0.0, 1.0))
		remaining -= duration
		previous = ends[index]
	return ends[-1]

func face_toward(point: Vector3) -> void:
	var difference: Vector3=point-position
	if Vector2(difference.x,difference.z).length_squared()>0.0001:
		rotation.y=atan2(difference.x,difference.z)

func get_action_origin(skill_id: String) -> Vector3:
	if is_instance_valid(_tinglan_actor) and skill_id == "interrupt":
		return _tinglan_actor.call("get_action_origin", skill_id)
	return global_position + Vector3.UP * 0.9

func sample_palm_preview(seconds: float) -> bool:
	if not is_instance_valid(_tinglan_actor):
		return false
	var ok: bool = _tinglan_actor.call("sample_palm_preview", seconds)
	_mode = str(_tinglan_actor.get("motion_mode"))
	_pose_time = float(_tinglan_actor.get("motion_time"))
	return ok

func get_palm_origin() -> Vector3:
	if is_instance_valid(_tinglan_actor):
		return _tinglan_actor.call("get_palm_origin")
	return global_position + Vector3.UP * 0.9

func get_weapon_anchors() -> Dictionary:
	if staff_motion_active():
		var anchors: Dictionary = _staff_rig.call("get_weapon_anchors")
		anchors["valid"] = true
		anchors["space"] = "global"
		return anchors
	if is_instance_valid(_approved_actor):
		return _approved_actor.call("get_weapon_anchors")
	return {"valid": false, "space": "global"}

func _reset_pose() -> void:
	for node: Node3D in _rest_rotations:
		if is_instance_valid(node):
			node.rotation=_rest_rotations[node]
			node.position=_rest_positions[node]
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay=null

func set_motion(mode: String, strength: float=1.0, skill_id: String="") -> void:
	if is_instance_valid(_staff_rig) and staff_motion_active():
		var clip := "recoil" if mode == "hit" else mode
		var context: Dictionary = {}
		if clip in ["interrupt", "recoil"] and not _staff_pose.is_empty():
			context["source_pose"] = _staff_pose.duplicate(true)
		_strength = strength
		sample_staff_motion(clip, 0.0, context)
		return
	_mode=mode
	_strength=strength
	_pose_time=0.0
	if mode == "attack":
		_attack_real_elapsed = 0.0
		_attack_source_clock = 0.0
		_attack_skill_id = skill_id
	if is_instance_valid(_approved_actor):
		_approved_actor.call("set_motion", mode, strength, skill_id)
		return
	if is_instance_valid(_tinglan_actor):
		_tinglan_actor.call("set_motion", mode, strength, skill_id)
		return
	_reset_pose()

func _process(delta: float) -> void:
	if staff_motion_active():
		if _staff_clock_external:
			return
		var next := _staff_seconds + maxf(delta, 0.0)
		if _staff_clip not in ["idle", "walk", "intent"] and next >= StaffMotion.duration(_staff_clip):
			sample_staff_motion("idle", 0.0)
		else:
			sample_staff_motion(_staff_clip, next, _staff_context)
		return
	var motion_delta: float = delta * action_playback_speed if _mode in ["attack", "hit"] else delta
	var timed_attack: bool = _mode == "attack" and not _attack_timing.is_empty()
	var attack_finished: bool = false
	if timed_attack:
		_attack_real_elapsed += maxf(delta, 0.0)
		var source_clock: float = _attack_source_at(_attack_real_elapsed)
		motion_delta = maxf(0.0, source_clock - _attack_source_clock)
		_attack_source_clock = source_clock
		attack_finished = _attack_real_elapsed + 0.0000001 >= _attack_duration()
	if is_instance_valid(_approved_actor):
		_approved_actor.call("step", motion_delta)
		if attack_finished:
			_approved_actor.call("set_motion", "idle")
		_mode = str(_approved_actor.get("motion_mode"))
		_pose_time = float(_approved_actor.get("motion_time"))
		return
	if is_instance_valid(_tinglan_actor):
		_tinglan_actor.call("step", motion_delta)
		if attack_finished:
			_tinglan_actor.call("set_motion", "idle")
		_mode = str(_tinglan_actor.get("motion_mode"))
		_pose_time = float(_tinglan_actor.get("motion_time"))
		return
	if body==null:
		return
	# Timed impact hold freezes the procedural body's small breath offset too.
	# Walking/idle retain their original real-time phase.
	_phase += motion_delta if timed_attack else delta
	_pose_time+=motion_delta
	_reset_pose()
	body.position.y+=sin(_phase*2.0)*0.007
	if _mode=="walk":
		body.position.y+=absf(sin(_pose_time*23.0))*0.028
		right_leg.rotation.x+=sin(_pose_time*23.0)*0.23
		left_leg.rotation.x-=sin(_pose_time*23.0)*0.23
		right_arm.rotation.x-=sin(_pose_time*23.0)*0.10
		left_arm.rotation.x+=sin(_pose_time*23.0)*0.10
	elif _mode=="attack":
		var phase: float=clampf(_pose_time/0.29,0.0,1.0)
		var stroke: float=sin(phase*PI)
		body.rotation.y+=stroke*0.16
		body.rotation.z-=stroke*0.055
		right_arm.rotation.x+=stroke*1.05
		right_arm.rotation.z-=stroke*0.38
		left_arm.rotation.x-=stroke*0.30
		if _weapon_kind=="sword":
			weapon.rotation.z=lerp_angle(float((_rest_rotations[weapon] as Vector3).z),-0.20,stroke)
	elif _mode=="hit":
		var recoil: float=sin(clampf(_pose_time/0.24,0.0,1.0)*PI)
		body.rotation.x-=recoil*0.16
		body.rotation.z+=sin(_pose_time*50.0)*recoil*0.045
		_flash.albedo_color.a=recoil*0.23
		for mesh: MeshInstance3D in _meshes:
			mesh.material_overlay=_flash if recoil>0.02 else null
	if attack_finished or (_mode not in ["idle","walk"] and _pose_time>0.31):
		_mode="idle"
		_reset_pose()

func workshop_adapter() -> Node3D:
	return _approved_actor if is_instance_valid(_approved_actor) else _tinglan_actor

func prepare_workshop_motion(move: Dictionary) -> void:
	set_motion("attack", 1.0, str(move.get("combat_skill", "")))
	var adapter := workshop_adapter()
	if adapter == null:
		return
	if adapter.has_method("_set_hand_variant"):
		adapter.call("_set_hand_variant", false)
		var palm := adapter.get("_open_palm") as MeshInstance3D
		if palm != null and str(move.animation.get("hand", "default")) == "palm":
			palm.visible = true
			for field: String in ["_relaxed_hand", "_pointing_hand"]:
				var hand := adapter.get(field) as MeshInstance3D
				if hand != null:
					hand.visible = false
	adapter.set("motion_mode", "palm_preview" if str(move.category) == "palm" else "attack")

func sample_workshop_motion(clip: String, source_seconds: float, elapsed: float) -> void:
	var adapter := workshop_adapter()
	if adapter == null:
		return
	_attack_real_elapsed = elapsed
	_attack_source_clock = source_seconds
	adapter.set("motion_time", source_seconds)
	adapter.call("_sample_clip", StringName(clip), source_seconds)
