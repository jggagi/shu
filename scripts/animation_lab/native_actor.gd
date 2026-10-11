extends Node2D
## Original, procedural 2D study actor driven by the shared 3D motion samples.
## The geometry is intentionally a paper-cut exploration model, not production art.

const PIXELS_PER_METER := 100.0
const DEFAULT_RIGHT := Vector3(1.0, 0.0, 0.0)
const DEFAULT_UP := Vector3(0.0, 0.0, 1.0)

const INK := Color("#263d4d")
const ROBE := Color("#37677d")
const ROBE_LIGHT := Color("#dce9e6")
const ROBE_BLUE := Color("#83b5c1")
const ROBE_DARK := Color("#294e66")
const PANTS := Color("#334958")
const SKIN := Color("#e7b990")
const SKIN_SHADE := Color("#c98768")
const HAIR := Color("#302e31")
const HAIR_LIGHT := Color("#574b47")
const WOOD := Color("#80583c")
const WOOD_LIGHT := Color("#b4865c")
const GOLD := Color("#b8884e")
const BOOT := Color("#493d37")

var _data: Dictionary = {}
var _descriptors: Array = []
var _clip_frames: Dictionary = {}
var _bone_nodes: Dictionary = {}
var _bone_paths: Dictionary = {}
var _bone_lines: Dictionary = {}
var _hand_anchors: Dictionary = {}
var _rest_pose: Dictionary = {}
var _joint_points: Dictionary = {}
var _last_pose: Dictionary = {}
var _last_joints: Dictionary = {}
var _generated_roots: Array[Node] = []
var _skeleton: Skeleton2D
var _player: AnimationPlayer
var _weapon_bone: Bone2D
var _sword_art: Node2D
var _staff_art: Node2D
var _sword_blade: Polygon2D
var _sword_edge: Polygon2D
var _staff_shaft: Polygon2D
var _staff_grain: Polygon2D
var _staff_wrap: Polygon2D
var _staff_wrap_local := Vector2.ZERO
var _staff_butt_local := Vector2.ZERO
var _active_clip := ""
var _last_seconds := 0.0
var _weighted_polygon_count := 0
var _bones_visible := false


func configure(data: Dictionary) -> void:
	_clear_generated()
	_data = data.duplicate(true)
	_descriptors = _data.get("bones", [])
	_clip_frames = _data.get("clips", {})
	_weighted_polygon_count = 0
	_active_clip = ""
	_last_seconds = 0.0

	if _descriptors.is_empty() or _clip_frames.is_empty():
		push_error("Native actor needs bone descriptors and motion clips.")
		return

	var first_clip := "thrust" if _clip_frames.has("thrust") else String(_clip_frames.keys()[0])
	var first_frames: Array = _clip_frames[first_clip]
	if first_frames.is_empty():
		push_error("Native actor clip '%s' has no samples." % first_clip)
		return

	_last_joints = first_frames[0].get("joints", {})
	_last_pose = _pose_from_joints(_last_joints)
	_joint_points = _project_joints(_last_joints)
	_create_rig()
	_create_character_art()
	_create_animations()
	set_bones_visible(_bones_visible)
	sample(first_clip, 0.0)


func sample(clip: String, seconds: float) -> void:
	if _player == null or not _clip_frames.has(clip):
		return
	var duration := float(_data.get("duration", 4.0))
	var position := clampf(seconds, 0.0, duration)
	var animation_name := "motion/%s" % clip
	_player.play(animation_name)
	_player.seek(position, true)
	_player.pause()
	_active_clip = clip
	_last_seconds = position
	_last_joints = _interpolated_joints(clip, position)
	_last_pose = _pose_from_joints(_last_joints)
	_update_debug_lengths(_last_pose)
	_update_weapon_geometry()
	if _sword_art != null:
		_sword_art.visible = clip != "staff"
	if _staff_art != null:
		_staff_art.visible = clip == "staff"


func set_bones_visible(enabled: bool) -> void:
	_bones_visible = enabled
	for parts in _bone_lines.values():
		for part in parts:
			if is_instance_valid(part):
				part.visible = enabled


func diagnostics() -> Dictionary:
	var animation_names: Array[String] = []
	if _player != null:
		for full_name in _player.get_animation_list():
			var name := String(full_name)
			animation_names.append(name.get_slice("/", 1) if name.contains("/") else name)
	var source_contacts: Dictionary = {}
	for joint_name in ["hand_R", "hand_L", "knee_R", "knee_L", "ankle_R", "ankle_L", "tip", "butt"]:
		if _last_joints.has(joint_name):
			source_contacts[joint_name] = _screen_point(_last_joints[joint_name])
	var rendered_contacts := _rendered_contact_points()
	var contact_errors: Dictionary = {}
	for joint_name in rendered_contacts.keys():
		if source_contacts.has(joint_name):
			contact_errors[joint_name] = Vector2(rendered_contacts[joint_name]).distance_to(Vector2(source_contacts[joint_name]))
	var staff_error := -1.0
	if _active_clip == "staff" and _staff_wrap != null and rendered_contacts.has("hand_L"):
		var rendered_wrap := to_local(_staff_wrap.to_global(Vector2.ZERO))
		staff_error = rendered_wrap.distance_to(Vector2(rendered_contacts["hand_L"]))
	return {
		"bone_count": _skeleton.get_bone_count() if _skeleton != null else 0,
		"animation_names": animation_names,
		"weighted_polygon_count": _weighted_polygon_count,
		"clip": _active_clip,
		"seconds": _last_seconds,
		"contacts": rendered_contacts,
		"source_contacts": source_contacts,
		"contact_errors_px": contact_errors,
		"hand_R_contact_error_px": float(contact_errors.get("hand_R", -1.0)),
		"hand_L_contact_error_px": float(contact_errors.get("hand_L", -1.0)),
		"weapon_tip_error_px": float(contact_errors.get("tip", -1.0)),
		"staff_contact_error_px": staff_error,
		"debug_bones_visible": _bones_visible,
	}


func _clear_generated() -> void:
	for node in _generated_roots:
		if is_instance_valid(node):
			node.free()
	_generated_roots.clear()
	_bone_nodes.clear()
	_bone_paths.clear()
	_bone_lines.clear()
	_hand_anchors.clear()
	_rest_pose.clear()
	_joint_points.clear()
	_last_pose.clear()
	_last_joints.clear()
	_skeleton = null
	_player = null
	_weapon_bone = null
	_sword_art = null
	_staff_art = null
	_sword_blade = null
	_sword_edge = null
	_staff_shaft = null
	_staff_grain = null
	_staff_wrap = null
	_staff_wrap_local = Vector2.ZERO
	_staff_butt_local = Vector2.ZERO


func _create_rig() -> void:
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton"
	for descriptor in _descriptors:
		var bone_name := String(descriptor.get("name", ""))
		var entry: Dictionary = _last_pose.get(bone_name, {})
		if bone_name.is_empty() or entry.is_empty():
			continue
		var bone := Bone2D.new()
		bone.name = "Bone_" + bone_name
		var parent_value: Variant = descriptor.get("parent")
		var parent_name := "" if parent_value == null else String(parent_value)
		var parent_node: Node = _skeleton if parent_name.is_empty() else _bone_nodes.get(parent_name, _skeleton)
		parent_node.add_child(bone)
		var parent_path := "" if parent_name.is_empty() else String(_bone_paths.get(parent_name, ""))
		_bone_paths[bone_name] = bone.name if parent_path.is_empty() else parent_path + "/" + bone.name
		bone.position = entry["position"]
		bone.rotation = entry["rotation"]
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(entry["length"])
		bone.set_rest(Transform2D(bone.rotation, bone.position))
		_bone_nodes[bone_name] = bone
		_rest_pose[bone_name] = entry.duplicate()
		if bone_name == "weapon":
			_weapon_bone = bone
		_add_debug_bone(bone, entry["length"])
	add_child(_skeleton)
	_generated_roots.append(_skeleton)

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_player.root_node = NodePath("..")
	add_child(_player)
	_generated_roots.append(_player)


func _create_animations() -> void:
	var library := AnimationLibrary.new()
	for clip_variant in _clip_frames.keys():
		var clip := String(clip_variant)
		var frames: Array = _clip_frames[clip]
		var animation := Animation.new()
		animation.resource_name = clip
		animation.length = float(_data.get("duration", 4.0))
		animation.loop_mode = Animation.LOOP_LINEAR
		var position_tracks: Dictionary = {}
		var rotation_tracks: Dictionary = {}
		var hand_anchor_tracks: Dictionary = {}
		var previous_angles: Dictionary = {}
		for descriptor in _descriptors:
			var bone_name := String(descriptor.get("name", ""))
			if not _bone_nodes.has(bone_name):
				continue
			var position_track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(position_track, NodePath("Skeleton/%s:position" % _bone_paths[bone_name]))
			var rotation_track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(rotation_track, NodePath("Skeleton/%s:rotation" % _bone_paths[bone_name]))
			position_tracks[bone_name] = position_track
			rotation_tracks[bone_name] = rotation_track
		for side_variant in ["R", "L"]:
			var side := String(side_variant)
			var fore_name := "fore_" + side
			if not _hand_anchors.has(side) or not _bone_paths.has(fore_name):
				continue
			var anchor_track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(anchor_track, NodePath("Skeleton/%s/HandAnchor_%s:position" % [_bone_paths[fore_name], side]))
			hand_anchor_tracks[side] = anchor_track
		for frame in frames:
			var frame_joints: Dictionary = frame.get("joints", {})
			var pose := _pose_from_joints(frame_joints)
			var at := float(frame.get("at", 0.0))
			for bone_name in position_tracks.keys():
				var entry: Dictionary = pose.get(bone_name, {})
				if entry.is_empty():
					continue
				var angle := float(entry["rotation"])
				if previous_angles.has(bone_name):
					var previous := float(previous_angles[bone_name])
					while angle - previous > PI:
						angle -= TAU
					while angle - previous < -PI:
						angle += TAU
				previous_angles[bone_name] = angle
				animation.track_insert_key(position_tracks[bone_name], at, entry["position"])
				animation.track_insert_key(rotation_tracks[bone_name], at, angle)
			for side in hand_anchor_tracks.keys():
				var fore_entry: Dictionary = pose.get("fore_" + side, {})
				if not fore_entry.is_empty():
					animation.track_insert_key(hand_anchor_tracks[side], at, Vector2(float(fore_entry["length"]), 0.0))
		library.add_animation(clip, animation)
	var add_error := _player.add_animation_library("motion", library)
	if add_error != OK:
		push_error("Could not register native actor motion library: %s" % error_string(add_error))


func _create_character_art() -> void:
	var shadow := Polygon2D.new()
	shadow.name = "SoftFootShadow"
	shadow.polygon = _ellipse_points(Vector2.ZERO, Vector2(35.0, 7.0), 28)
	shadow.color = Color(0.19, 0.20, 0.19, 0.16)
	shadow.z_index = -10
	shadow.z_as_relative = false
	add_child(shadow)
	_generated_roots.append(shadow)

	_add_limb("thigh_L", 13.0, PANTS, Color("#61717a"), 1)
	_add_limb("shin_L", 10.5, PANTS, Color("#71808a"), 1)
	_add_limb("foot_L", 7.5, BOOT, WOOD_LIGHT, 3)
	_add_limb("thigh_R", 13.0, PANTS, Color("#61717a"), 2)
	_add_limb("shin_R", 10.5, PANTS, Color("#71808a"), 2)
	_add_limb("foot_R", 7.5, BOOT, WOOD_LIGHT, 4)
	_add_lower_robe()
	_add_upper_robe()
	_add_weighted_sleeve("L")
	_add_weighted_sleeve("R")
	_create_hand_anchor("L")
	_create_hand_anchor("R")
	_add_arm_hand(_hand_anchors["L"], 7)
	_add_arm_hand(_hand_anchors["R"], 8)
	_add_head()
	_add_weapon()


func _add_lower_robe() -> void:
	var bone: Bone2D = _bone_nodes.get("hips")
	if bone == null:
		return
	var length := float(_rest_pose["hips"]["length"])
	var outer := PackedVector2Array([
		Vector2(-8.0, -19.0), Vector2(-2.0, -26.0), Vector2(length * 0.30, -29.0),
		Vector2(length * 0.73, -24.0), Vector2(length + 7.0, -17.0), Vector2(length + 8.0, 17.0),
		Vector2(length * 0.73, 24.0), Vector2(length * 0.30, 29.0), Vector2(-2.0, 26.0), Vector2(-8.0, 19.0),
	])
	_add_polygon(bone, outer, INK, 3, "RobeOutline")
	var fill := PackedVector2Array([
		Vector2(-5.0, -16.0), Vector2(0.0, -23.0), Vector2(length * 0.30, -25.5),
		Vector2(length * 0.70, -21.0), Vector2(length + 3.0, -14.0), Vector2(length + 4.0, 14.0),
		Vector2(length * 0.70, 21.0), Vector2(length * 0.30, 25.5), Vector2(0.0, 23.0), Vector2(-5.0, 16.0),
	])
	_add_polygon(bone, fill, ROBE, 4, "RobeBody")
	_add_polygon(bone, PackedVector2Array([
		Vector2(7.0, -4.0), Vector2(length + 1.0, -9.0), Vector2(length + 2.0, -2.5),
		Vector2(9.0, 3.0),
	]), ROBE_LIGHT, 5, "FrontFold")
	_add_polygon(bone, PackedVector2Array([
		Vector2(8.0, -26.0), Vector2(15.0, -28.0), Vector2(15.0, 28.0), Vector2(8.0, 26.0),
	]), GOLD, 6, "WaistSash")
	_add_polygon(bone, PackedVector2Array([
		Vector2(9.0, -25.0), Vector2(13.0, -25.0), Vector2(13.0, 25.0), Vector2(9.0, 25.0),
	]), WOOD, 7, "BeltLeather")
	_add_polygon(bone, PackedVector2Array([
		Vector2(10.0, -3.0), Vector2(16.0, -3.0), Vector2(16.0, 3.0), Vector2(10.0, 3.0),
	]), GOLD, 8, "BeltClasp")


func _add_upper_robe() -> void:
	var bone: Bone2D = _bone_nodes.get("chest")
	if bone == null:
		return
	var length := float(_rest_pose["chest"]["length"])
	_add_polygon(bone, PackedVector2Array([
		Vector2(-9.0, -22.0), Vector2(-3.0, -29.0), Vector2(length * 0.50, -27.0),
		Vector2(length + 8.0, -17.0), Vector2(length + 9.0, 17.0), Vector2(length * 0.50, 27.0),
		Vector2(-3.0, 29.0), Vector2(-9.0, 22.0),
	]), INK, 3, "ShoulderRobeOutline")
	_add_polygon(bone, PackedVector2Array([
		Vector2(-6.0, -19.0), Vector2(-1.0, -25.0), Vector2(length * 0.48, -23.0),
		Vector2(length + 5.0, -14.0), Vector2(length + 6.0, 14.0), Vector2(length * 0.48, 23.0),
		Vector2(-1.0, 25.0), Vector2(-6.0, 19.0),
	]), ROBE, 4, "ShoulderRobe")
	_add_polygon(bone, PackedVector2Array([
		Vector2(-3.0, -8.0), Vector2(4.0, -16.0), Vector2(length + 2.0, -9.0),
		Vector2(length + 3.0, -2.0), Vector2(3.0, -8.0), Vector2(-3.0, 2.0),
	]), ROBE_LIGHT, 5, "CrossCollar")
	_add_polygon(bone, PackedVector2Array([
		Vector2(2.0, 13.0), Vector2(length + 4.0, 7.0), Vector2(length + 5.0, 12.0),
		Vector2(4.0, 20.0),
	]), ROBE_BLUE, 5, "BlueLapel")


func _add_limb(bone_name: String, width: float, fill: Color, highlight: Color, z: int) -> void:
	var bone: Bone2D = _bone_nodes.get(bone_name)
	if bone == null:
		return
	var length := maxf(float(_rest_pose[bone_name]["length"]), 8.0)
	_add_polygon(bone, _limb_shape(length, width + 3.0), INK, z, bone_name + "Outline")
	_add_polygon(bone, _limb_shape(length, width), fill, z + 1, bone_name + "Fill")
	_add_polygon(bone, PackedVector2Array([
		Vector2(length * 0.22, -width * 0.34), Vector2(length * 0.77, -width * 0.38),
		Vector2(length * 0.82, -width * 0.12), Vector2(length * 0.19, -width * 0.08),
	]), highlight, z + 2, bone_name + "LightFold")
	if bone_name.begins_with("foot_"):
		_add_polygon(bone, PackedVector2Array([
			Vector2(length * 0.38, -width * 0.68), Vector2(length * 0.60, -width * 0.68),
			Vector2(length * 0.62, width * 0.68), Vector2(length * 0.36, width * 0.68),
		]), GOLD, z + 3, bone_name + "BootSeam")


func _add_weighted_sleeve(side: String) -> void:
	var shoulder_name := "shoulder_" + side
	var elbow_name := "elbow_" + side
	var hand_name := "hand_" + side
	if not _joint_points.has(shoulder_name) or not _joint_points.has(elbow_name) or not _joint_points.has(hand_name):
		return
	var centerline: Array[Vector2] = [
		_joint_points[shoulder_name], _joint_points[elbow_name], _joint_points[hand_name],
	]
	var outer := _ribbon(centerline, [15.5, 14.0, 11.5])
	var inner := _ribbon(centerline, [11.0, 10.0, 8.0])
	_add_skinned_polygon(outer, ["upper_" + side, "fore_" + side], INK, 5, "SleeveOutline_" + side)
	_add_skinned_polygon(inner, ["upper_" + side, "fore_" + side], ROBE_LIGHT, 6, "Sleeve_" + side)
	var cuff := _ribbon([centerline[1].lerp(centerline[2], 0.84), centerline[2]], [9.0, 8.0])
	_add_skinned_polygon(cuff, ["fore_" + side], ROBE_BLUE, 7, "SleeveCuff_" + side)


func _create_hand_anchor(side: String) -> void:
	var fore_name := "fore_" + side
	var fore: Bone2D = _bone_nodes.get(fore_name)
	if fore == null:
		return
	var anchor := Node2D.new()
	anchor.name = "HandAnchor_" + side
	anchor.position = Vector2(float(_rest_pose[fore_name]["length"]), 0.0)
	fore.add_child(anchor)
	_hand_anchors[side] = anchor


func _add_arm_hand(anchor: Node2D, z: int) -> void:
	_add_polygon(anchor, _ellipse_points(Vector2.ZERO, Vector2(8.5, 7.0), 18), SKIN_SHADE, z, "PalmShadow")
	_add_polygon(anchor, _ellipse_points(Vector2(1.0, -1.0), Vector2(7.2, 6.2), 18), SKIN, z + 1, "Palm")
	var fingers := Line2D.new()
	fingers.name = "FingerMarks"
	fingers.points = PackedVector2Array([Vector2(3.0, -3.0), Vector2(7.0, -1.0), Vector2(7.5, 2.0)])
	fingers.width = 1.2
	fingers.default_color = SKIN_SHADE
	fingers.z_index = z + 2
	fingers.z_as_relative = false
	anchor.add_child(fingers)


func _add_head() -> void:
	var bone: Bone2D = _bone_nodes.get("head")
	if bone == null:
		return
	var length := float(_rest_pose["head"]["length"])
	var face_center := Vector2(length * 0.65, -1.0)
	_add_polygon(bone, PackedVector2Array([
		Vector2(-5.0, -8.0), Vector2(2.0, -10.5), Vector2(length * 0.43, -8.5),
		Vector2(length * 0.48, 8.5), Vector2(2.0, 10.5), Vector2(-5.0, 8.0),
	]), SKIN_SHADE, 8, "NeckShadow")
	_add_polygon(bone, PackedVector2Array([
		Vector2(-3.0, -6.5), Vector2(3.0, -8.0), Vector2(length * 0.43, -6.5),
		Vector2(length * 0.48, 6.5), Vector2(3.0, 8.0), Vector2(-3.0, 6.5),
	]), SKIN, 9, "NeckBridge")
	_add_polygon(bone, _ellipse_points(face_center + Vector2(0.0, 1.0), Vector2(25.0, 24.0), 24), HAIR, 8, "HairSilhouette")
	_add_polygon(bone, _ellipse_points(face_center + Vector2(-3.0, -3.0), Vector2(20.5, 19.5), 24), SKIN_SHADE, 9, "FaceShadow")
	_add_polygon(bone, _ellipse_points(face_center + Vector2(-4.0, -4.0), Vector2(19.0, 18.5), 24), SKIN, 10, "Face")
	_add_polygon(bone, PackedVector2Array([
		Vector2(length * 0.40, -20.0), Vector2(length * 0.77, -22.0), Vector2(length + 1.0, -13.0),
		Vector2(length + 3.0, -3.0), Vector2(length * 0.82, -1.0), Vector2(length * 0.70, -8.0),
		Vector2(length * 0.52, -11.0),
	]), HAIR, 11, "HairCap")
	_add_polygon(bone, _ellipse_points(Vector2(length * 0.91, -13.0), Vector2(10.0, 9.0), 18), HAIR, 11, "Topknot")
	_add_polygon(bone, _ellipse_points(Vector2(length * 0.91, -13.0), Vector2(5.5, 4.5), 16), HAIR_LIGHT, 12, "TopknotLight")
	_add_polygon(bone, PackedVector2Array([
		Vector2(length * 0.66, -20.0), Vector2(length * 0.76, -21.5), Vector2(length * 0.92, -15.0),
		Vector2(length * 0.83, -13.0),
	]), GOLD, 13, "HairTie")
	# The face is angled toward projected +X; paired marks read as a front-quarter view.
	for eye_y in [-11.0, -4.0]:
		_add_polygon(bone, _ellipse_points(Vector2(length * 0.60, eye_y), Vector2(2.0, 1.7), 12), INK, 14, "Eye")
		_add_polygon(bone, PackedVector2Array([
			Vector2(length * 0.65, eye_y - 3.5), Vector2(length * 0.63, eye_y + 2.5),
			Vector2(length * 0.69, eye_y + 2.4), Vector2(length * 0.71, eye_y - 3.2),
		]), HAIR, 13, "Brow")
	_add_polygon(bone, _ellipse_points(Vector2(length * 0.48, -13.8), Vector2(2.2, 2.0), 12), SKIN_SHADE, 12, "Nose")
	var mouth := Line2D.new()
	mouth.name = "Mouth"
	mouth.points = PackedVector2Array([Vector2(length * 0.39, -12.0), Vector2(length * 0.36, -9.0), Vector2(length * 0.32, -8.0)])
	mouth.width = 1.4
	mouth.default_color = Color("#875b50")
	mouth.z_index = 13
	mouth.z_as_relative = false
	bone.add_child(mouth)


func _add_weapon() -> void:
	var bone: Bone2D = _bone_nodes.get("weapon")
	if bone == null:
		return
	_sword_art = Node2D.new()
	_sword_art.name = "StudySword"
	_sword_art.z_index = 5
	_sword_art.z_as_relative = false
	bone.add_child(_sword_art)
	var length := maxf(float(_rest_pose["weapon"]["length"]), 30.0)
	_add_polygon(_sword_art, PackedVector2Array([
		Vector2(-16.0, -3.0), Vector2(7.0, -3.0), Vector2(9.0, 3.0), Vector2(-16.0, 3.0),
	]), WOOD, 5, "SwordGrip")
	_add_polygon(_sword_art, PackedVector2Array([
		Vector2(5.0, -15.0), Vector2(8.0, -15.0), Vector2(8.0, 15.0), Vector2(5.0, 15.0),
	]), GOLD, 6, "SwordGuard")
	_sword_blade = _add_polygon(_sword_art, PackedVector2Array([
		Vector2(9.0, -7.0), Vector2(length * 0.79, -4.1), Vector2(length, 0.0),
		Vector2(length * 0.79, 4.1), Vector2(9.0, 7.0),
	]), Color("#b9c9c8"), 5, "SwordBlade")
	_sword_edge = _add_polygon(_sword_art, PackedVector2Array([
		Vector2(12.0, -1.2), Vector2(length * 0.79, -1.0), Vector2(length * 0.94, 0.0),
		Vector2(length * 0.79, 1.0), Vector2(12.0, 1.2),
	]), Color("#f0eee2"), 6, "SwordEdge")

	_staff_art = Node2D.new()
	_staff_art.name = "StudyStaff"
	_staff_art.z_index = 5
	_staff_art.z_as_relative = false
	bone.add_child(_staff_art)
	_staff_shaft = _add_polygon(_staff_art, PackedVector2Array([
		Vector2(-68.0, -3.5), Vector2(-64.0, -5.0), Vector2(length - 3.0, -4.0),
		Vector2(length, 0.0), Vector2(length - 3.0, 4.0), Vector2(-64.0, 5.0), Vector2(-68.0, 3.5),
	]), WOOD, 5, "StaffShaft")
	_staff_grain = _add_polygon(_staff_art, PackedVector2Array([
		Vector2(-60.0, -1.2), Vector2(length - 8.0, -1.1), Vector2(length - 9.0, 0.1),
		Vector2(-60.0, 1.0),
	]), WOOD_LIGHT, 6, "StaffGrain")
	_staff_wrap = _add_polygon(_staff_art, PackedVector2Array([
		Vector2(-3.5, -5.4), Vector2(3.5, -5.4), Vector2(3.5, 5.4), Vector2(-3.5, 5.4),
	]), Color("#e3d5b6"), 7, "SecondGripWrap")
	_staff_art.visible = false
	_update_weapon_geometry()


func _update_weapon_geometry() -> void:
	if _weapon_bone == null or not _last_pose.has("weapon"):
		return
	var weapon_pose: Dictionary = _last_pose["weapon"]
	var tip_x := maxf(float(weapon_pose["length"]), 8.0)
	if _sword_blade != null:
		_sword_blade.polygon = PackedVector2Array([
			Vector2(9.0, -7.0), Vector2(tip_x * 0.79, -4.1), Vector2(tip_x, 0.0),
			Vector2(tip_x * 0.79, 4.1), Vector2(9.0, 7.0),
		])
	if _sword_edge != null:
		_sword_edge.polygon = PackedVector2Array([
			Vector2(12.0, -1.2), Vector2(tip_x * 0.79, -1.0), Vector2(tip_x * 0.94, 0.0),
			Vector2(tip_x * 0.79, 1.0), Vector2(12.0, 1.2),
		])
	var hand_point := _screen_point(_last_joints.get("hand_R", [0.0, 0.0, 0.0]))
	var butt_point := _screen_point(_last_joints.get("butt", [0.0, 0.0, 0.0]))
	_staff_butt_local = (butt_point - hand_point).rotated(-float(weapon_pose["global_angle"]))
	var left_hand_point := _screen_point(_last_joints.get("hand_L", [0.0, 0.0, 0.0]))
	_staff_wrap_local = (left_hand_point - hand_point).rotated(-float(weapon_pose["global_angle"]))
	if _staff_shaft != null:
		_staff_shaft.polygon = _staff_shaft_polygon(_staff_butt_local.x, tip_x)
	if _staff_grain != null:
		var grain_start := _staff_butt_local.x + 8.0
		var grain_end := tip_x - 8.0
		_staff_grain.polygon = PackedVector2Array([
			Vector2(grain_start, -1.2), Vector2(grain_end, -1.1),
			Vector2(grain_end - 1.0, 0.1), Vector2(grain_start, 1.0),
		])
	if _staff_wrap != null:
		_staff_wrap.position = _staff_wrap_local


func _staff_shaft_polygon(start_x: float, end_x: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(start_x, -3.5), Vector2(start_x + 4.0, -5.0), Vector2(end_x - 3.0, -4.0),
		Vector2(end_x, 0.0), Vector2(end_x - 3.0, 4.0), Vector2(start_x + 4.0, 5.0), Vector2(start_x, 3.5),
	])


func _add_debug_bone(bone: Bone2D, length: float) -> void:
	var line := Line2D.new()
	line.name = "DebugBoneLine"
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])
	line.width = 2.2
	line.default_color = Color(1.0, 0.58, 0.18, 0.96)
	line.z_index = 40
	line.z_as_relative = false
	line.visible = _bones_visible
	bone.add_child(line)
	var joint := Polygon2D.new()
	joint.name = "DebugJoint"
	joint.polygon = _ellipse_points(Vector2.ZERO, Vector2(3.2, 3.2), 12)
	joint.color = Color("#fff0b9")
	joint.z_index = 41
	joint.z_as_relative = false
	joint.visible = _bones_visible
	bone.add_child(joint)
	_bone_lines[bone.name] = [line, joint]


func _update_debug_lengths(pose: Dictionary) -> void:
	for bone_name in _bone_lines.keys():
		var entry: Dictionary = pose.get(String(bone_name).trim_prefix("Bone_"), {})
		if entry.is_empty():
			continue
		var parts: Array = _bone_lines[bone_name]
		var line: Line2D = parts[0]
		line.points = PackedVector2Array([Vector2.ZERO, Vector2(float(entry["length"]), 0.0)])


func _rendered_contact_points() -> Dictionary:
	var points: Dictionary = {}
	var bone_for_joint := {
		"hip": "hips", "chest": "chest", "neck": "head",
		"shoulder_R": "upper_R", "elbow_R": "fore_R",
		"shoulder_L": "upper_L", "elbow_L": "fore_L",
		"hip_R": "thigh_R", "knee_R": "shin_R", "ankle_R": "foot_R",
		"hip_L": "thigh_L", "knee_L": "shin_L", "ankle_L": "foot_L",
	}
	for joint_name in bone_for_joint.keys():
		var bone_name := String(bone_for_joint[joint_name])
		if _bone_nodes.has(bone_name):
			var bone: Bone2D = _bone_nodes[bone_name]
			points[joint_name] = to_local(bone.global_position)
	for side in ["R", "L"]:
		var anchor: Node2D = _hand_anchors.get(side)
		if anchor != null:
			points["hand_" + side] = to_local(anchor.global_position)
	if _weapon_bone != null and _last_pose.has("weapon"):
		var tip_length := float(_last_pose["weapon"]["length"])
		points["tip"] = to_local(_weapon_bone.to_global(Vector2(tip_length, 0.0)))
		if _active_clip == "staff":
			points["butt"] = to_local(_weapon_bone.to_global(_staff_butt_local))
	return points


func _pose_from_joints(joints: Dictionary) -> Dictionary:
	var pose: Dictionary = {}
	for descriptor in _descriptors:
		var bone_name := String(descriptor.get("name", ""))
		var head_name := String(descriptor.get("head", ""))
		var tail_name := String(descriptor.get("tail", ""))
		if not joints.has(head_name) or not joints.has(tail_name):
			continue
		var head := _screen_point(joints[head_name])
		var tail := _screen_point(joints[tail_name])
		var delta := tail - head
		var angle := delta.angle() if delta.length_squared() > 0.0001 else 0.0
		var parent_value: Variant = descriptor.get("parent")
		var parent_name := "" if parent_value == null else String(parent_value)
		var local_position := head
		var local_rotation := angle
		if not parent_name.is_empty() and pose.has(parent_name):
			var parent_entry: Dictionary = pose[parent_name]
			local_position = (head - parent_entry["head"]).rotated(-float(parent_entry["global_angle"]))
			local_rotation = wrapf(angle - float(parent_entry["global_angle"]), -PI, PI)
		pose[bone_name] = {
			"head": head,
			"tail": tail,
			"global_angle": angle,
			"position": local_position,
			"rotation": local_rotation,
			"length": delta.length(),
		}
	return pose


func _project_joints(joints: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for joint_name in joints.keys():
		var value: Variant = joints[joint_name]
		if value is Array or value is Vector3:
			output[String(joint_name)] = _screen_point(value)
	return output


func _screen_point(value: Variant) -> Vector2:
	var point := _as_vector3(value)
	var camera: Dictionary = _data.get("camera", {})
	var right := _as_vector3(camera.get("right", DEFAULT_RIGHT), DEFAULT_RIGHT)
	var up := _as_vector3(camera.get("up", DEFAULT_UP), DEFAULT_UP)
	return Vector2(point.dot(right), -point.dot(up)) * PIXELS_PER_METER


func _as_vector3(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _interpolated_joints(clip: String, seconds: float) -> Dictionary:
	var frames: Array = _clip_frames.get(clip, [])
	if frames.is_empty():
		return {}
	if seconds <= float(frames[0].get("at", 0.0)):
		return frames[0].get("joints", {}).duplicate(true)
	for index in range(1, frames.size()):
		var right_frame: Dictionary = frames[index]
		var right_time := float(right_frame.get("at", 0.0))
		if seconds <= right_time:
			var left_frame: Dictionary = frames[index - 1]
			var left_time := float(left_frame.get("at", 0.0))
			var amount := inverse_lerp(left_time, right_time, seconds)
			var left_joints: Dictionary = left_frame.get("joints", {})
			var right_joints: Dictionary = right_frame.get("joints", {})
			var result: Dictionary = {}
			for joint_name in left_joints.keys():
				if not right_joints.has(joint_name):
					continue
				var left_point := _as_vector3(left_joints[joint_name])
				var right_point := _as_vector3(right_joints[joint_name])
				result[joint_name] = [
					lerpf(left_point.x, right_point.x, amount),
					lerpf(left_point.y, right_point.y, amount),
					lerpf(left_point.z, right_point.z, amount),
				]
			return result
	return frames[frames.size() - 1].get("joints", {}).duplicate(true)


func _add_polygon(parent: Node2D, points: Variant, color: Color, z: int, node_name: String) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = PackedVector2Array(points)
	polygon.color = color
	polygon.antialiased = true
	polygon.z_index = z
	polygon.z_as_relative = false
	parent.add_child(polygon)
	return polygon


func _add_skinned_polygon(points: PackedVector2Array, bone_names: Array, color: Color, z: int, node_name: String) -> void:
	if points.size() < 3:
		return
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.antialiased = true
	polygon.skeleton = NodePath("..")
	polygon.z_index = z
	polygon.z_as_relative = false
	_skeleton.add_child(polygon)
	var weight_arrays: Dictionary = {}
	for bone_name_variant in bone_names:
		var bone_name := String(bone_name_variant)
		if not _rest_pose.has(bone_name):
			continue
		weight_arrays[bone_name] = PackedFloat32Array()
	for point in points:
		var raw_weights: Dictionary = {}
		var total := 0.0
		for bone_name in weight_arrays.keys():
			var rest: Dictionary = _rest_pose[bone_name]
			var distance := _distance_to_segment(point, rest["head"], rest["tail"])
			var weight := 1.0 / pow(distance + 14.0, 2.0)
			raw_weights[bone_name] = weight
			total += weight
		for bone_name in weight_arrays.keys():
			var weights: PackedFloat32Array = weight_arrays[bone_name]
			weights.append(float(raw_weights[bone_name]) / maxf(total, 0.000001))
			weight_arrays[bone_name] = weights
	for bone_name in weight_arrays.keys():
		polygon.add_bone(NodePath(_bone_paths[bone_name]), weight_arrays[bone_name])
	_weighted_polygon_count += 1


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta := end - start
	if delta.length_squared() <= 0.0001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(start + delta * amount)


func _ribbon(points: Array[Vector2], widths: Array[float]) -> PackedVector2Array:
	if points.size() < 2:
		return PackedVector2Array()
	var normals: Array[Vector2] = []
	for index in range(points.size() - 1):
		var direction := (points[index + 1] - points[index]).normalized()
		normals.append(direction.orthogonal())
	var positive: Array[Vector2] = []
	var negative: Array[Vector2] = []
	for index in range(points.size()):
		var normal: Vector2
		if index == 0:
			normal = normals[0]
		elif index == points.size() - 1:
			normal = normals[normals.size() - 1]
		else:
			normal = (normals[index - 1] + normals[index]).normalized()
			if normal.length_squared() < 0.01:
				normal = normals[index]
		var offset := normal * float(widths[index])
		positive.append(points[index] + offset)
		negative.append(points[index] - offset)
	for index in range(negative.size() - 1, -1, -1):
		positive.append(negative[index])
	return PackedVector2Array(positive)


func _limb_shape(length: float, width: float) -> PackedVector2Array:
	var start_cap := minf(width * 0.45, length * 0.20)
	var end_cap := minf(width * 0.45, length * 0.20)
	return PackedVector2Array([
		Vector2(-start_cap, -width * 0.58), Vector2(length * 0.18, -width),
		Vector2(length * 0.72, -width * 0.78), Vector2(length + end_cap, -width * 0.34),
		Vector2(length + end_cap, width * 0.34), Vector2(length * 0.72, width * 0.78),
		Vector2(length * 0.18, width), Vector2(-start_cap, width * 0.58),
	])


func _ellipse_points(center: Vector2, radii: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
