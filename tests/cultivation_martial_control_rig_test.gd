extends SceneTree
## CPU resource/schema proof. Naturalness is a separate rendered/user judgement.
const Catalog := preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const OLD_TEST := preload("res://tests/cultivation_martial_workshop_catalog_test.gd")
const BASE_PATH := "res://assets/data/martial_workshop/catalog.json"
const VARIANT_PATH := "res://assets/data/martial_workshop/control_variants.json"
const IDS := ["pierce", "sweep", "palm_gale", "sword_cleave", "palm_cloud", "palm_brace"]
const ENHANCED := ["sword_cleave", "palm_gale"]
const PROTECTED := {
	"res://assets/data/martial_workshop/catalog.json": "bd226cf15f942368a9af6954a6ae958e678bc0fc360f6a311d4a501c04bb5bc6",
	"res://assets/data/martial_workshop/profiles.json": "c05803ba114109dfc1f271f37624a382e2c83905d0480e3e63d5412305312bd0",
	"res://assets/art/mountain_ambush/jiang-approved.glb": "e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27",
	"res://assets/art/mountain_ambush/tinglan-candidate.glb": "cdbec85183a9e2d452546c6a5a1a164c854042c9a2f4f783b5d184c750d5856b",
	"res://assets/art/mountain_ambush/jiang-martial-clips.glb": "c12e21def1323b9ed5a436870d0f5eb560a71a2d626c706ea7a34a0b83745a92",
	"res://assets/art/mountain_ambush/palm_lab/v2/motion/tinglan-palm-clips.glb": "7cfaf94d17313df4274d9cfdfa815fb70576a4a72679f1d6c915bda9fa793c83",
	"res://assets/data/martial_workshop/recipes/palm_brace.json": "6f4b17a5631ac566eb97a58a957a4aa655ce802ff0d66c73a123f97ca8a79498",
	"res://assets/data/martial_workshop/recipes/palm_cloud.json": "501658220dd8d57a55eec326b9f7ed576842a8c3608f43f1d9fa7dd034df2eea",
	"res://assets/data/martial_workshop/recipes/palm_gale.json": "4167d00caeba8cbbb8c2410273303799bad224001f8cead868165f9185070564",
	"res://assets/data/martial_workshop/recipes/pierce.json": "b4932ddd480a6de39277711bf21330a9171ad78f861a38dc7378fd0f36ac4dd1",
	"res://assets/data/martial_workshop/recipes/sweep.json": "a073ab560059c01f74347e9389dfd7bd485caa4a95130b4533d0bd2cdec39ea1",
	"res://assets/data/martial_workshop/recipes/sword_cleave.json": "ff83ec05f27d1b4b4e25e56da7a21a0c49cfc2296c7805818a429909ed3354ec",
}
var checks := 0
var failures: Array[String] = []
var output := "res://.local/qa/martial-control-rig/catalog"
var base: Dictionary = {}
var variants: Dictionary = {}
var catalog: Dictionary = {}
var rejected: Array[Dictionary] = []
var resources: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(FileAccess.file_exists(VARIANT_PATH), "The independently authored enhancement sidecar exists")
	if not FileAccess.file_exists(VARIANT_PATH):
		_finish()
		return
	base = JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	variants = JSON.parse_string(FileAccess.get_file_as_string(VARIANT_PATH))
	var before := variants.duplicate(true)
	var loaded := Catalog.load_catalog()
	_check(bool(loaded.get("ok", false)), "The default catalog loads its real original and enhanced resource set: " + str(loaded.get("reason", "")))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	catalog = loaded.catalog
	_check(Catalog.validate_variants(base, variants, true).ok, "Standalone sidecar validation accepts the real assets")
	_check(str(catalog.base_catalog_sha256) == FileAccess.get_sha256(BASE_PATH) and str(catalog.catalog_sha256) == (FileAccess.get_file_as_string(BASE_PATH) + "\n" + FileAccess.get_file_as_string(VARIANT_PATH)).sha256_text(), "The review fingerprint covers both exact JSON sources and exposes the immutable base revision")
	var ids: Array = []
	for move: Dictionary in catalog.moves:
		ids.append(move.id)
		var original: Dictionary = Catalog.find_move(catalog, str(move.id))
		var authored: Dictionary = _base_move(str(move.id))
		for key: String in authored:
			_check(original.get(key) == authored[key], str(move.id) + " retains its authored original field " + key)
		_check(str(original.get("variant_id", "original")) == "original", "Default resolution always selects original for " + str(move.id))
		if str(move.id) not in ENHANCED:
			_check(Catalog.find_move(catalog, str(move.id), "enhanced").is_empty(), "Unsupported enhancement cannot silently substitute another move: " + str(move.id))
	_check(ids == IDS and variants.variants.size() == 2, "The six-move list remains exact and only two enhanced variants are authored")
	_check(Catalog.find_move(catalog, "not_a_move", "enhanced").is_empty() and Catalog.find_move(catalog, "sword_cleave", "not_a_variant").is_empty(), "Unknown moves/variants are explicit lookup failures")
	for id: String in ENHANCED:
		_check_variant_resource(id)
	_negative_cases()
	_check(variants == before, "Valid and invalid variant validation never rewrites the caller's recipe")
	for paths: Dictionary in [PROTECTED, OLD_TEST.PROTECTED]:
		for path: String in paths:
			_check(FileAccess.get_sha256(path) == paths[path], "Original source/authority bytes remain frozen: " + path)
	_finish()


func _check_variant_resource(id: String) -> void:
	var original: Dictionary = Catalog.find_move(catalog, id, "original")
	var enhanced: Dictionary = Catalog.find_move(catalog, id, "enhanced")
	_check(not enhanced.is_empty(), id + " resolves to its own enhanced descriptor")
	if enhanced.is_empty():
		return
	for key: String in ["id", "actor", "profile", "category", "style", "timing", "audio", "visual", "camera"]:
		_check(enhanced[key] == original[key], id + " A/B uses identical " + key)
	_check(bool(enhanced.preview_only) and str(enhanced.combat_skill).is_empty(), id + " enhancement cannot introduce combat authority")
	_check(str(enhanced.animation.asset) != str(original.animation.asset) and str(enhanced.animation.clip) != str(original.animation.clip), id + " enhancement is a different real clip/resource")
	var path := str(enhanced.animation.asset)
	var model := (load(path) as PackedScene).instantiate()
	var old_model := (load(str(original.animation.asset)) as PackedScene).instantiate()
	var source_model := (load(str(catalog.profiles[enhanced.profile].source_asset)) as PackedScene).instantiate()
	root.add_child(model)
	root.add_child(old_model)
	root.add_child(source_model)
	var rig := _first(model, "Skeleton3D") as Skeleton3D
	var old_rig := _first(old_model, "Skeleton3D") as Skeleton3D
	var source_rig := _first(source_model, "Skeleton3D") as Skeleton3D
	var animations := _first(model, "AnimationPlayer") as AnimationPlayer
	var old_animations := _first(old_model, "AnimationPlayer") as AnimationPlayer
	_check(rig != null and old_rig != null and source_rig != null and animations != null and old_animations != null, id + " imports genuine source skeletons and animation players")
	if rig == null or old_rig == null or source_rig == null or animations == null or old_animations == null:
		model.free()
		old_model.free()
		source_model.free()
		return
	_check(rig.get_bone_count() == 22, id + " imports exactly the original 22 bones")
	var max_rest := 0.0
	for i: int in range(source_rig.get_bone_count()):
		var bone := rig.find_bone(source_rig.get_bone_name(i))
		_check(bone >= 0, id + " preserves bone " + str(source_rig.get_bone_name(i)))
		if bone < 0:
			continue
		var source_parent := source_rig.get_bone_parent(i)
		var parent := rig.get_bone_parent(bone)
		_check((parent < 0 and source_parent < 0) or (parent >= 0 and source_parent >= 0 and rig.get_bone_name(parent) == source_rig.get_bone_name(source_parent)), id + " preserves original parent of " + str(source_rig.get_bone_name(i)))
		max_rest = maxf(max_rest, _transform_error(source_rig.get_bone_rest(i), rig.get_bone_rest(bone)))
	_check(max_rest <= 0.00002, id + " actual imported bone rest stays within the protected 20 micrometre component tolerance")
	_check(animations.has_animation(str(enhanced.animation.clip)) and old_animations.has_animation(str(original.animation.clip)), id + " both raw authored clips exist")
	var animation := animations.get_animation(str(enhanced.animation.clip))
	_check(animation.get_track_count() >= 22 and absf(animation.length - float(enhanced.animation.source_seconds)) < 0.025, id + " enhanced clip contains populated original bone tracks for its full duration")
	for track: int in range(animation.get_track_count()):
		var track_path := animation.track_get_path(track)
		_check(animation.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] and track_path.get_subname_count() == 1 and rig.find_bone(track_path.get_subname(0)) >= 0, id + " authored track only addresses an original bone")
	var document := _glb_json(path)
	var skin: Dictionary = document.get("skins", [{}])[0]
	_check((skin.get("joints", []) as Array).size() == 22, id + " GLB skin binds only 22 protected joints")
	var source_asset := str(catalog.profiles[enhanced.profile].source_asset)
	var source_document := _glb_json(source_asset)
	var inverse_binds := _inverse_binds(path, document)
	var source_binds := _inverse_binds(source_asset, source_document)
	var max_skin := 0.0
	_check(inverse_binds.size() == 22 and source_binds.size() == 22, id + " enhanced and original GLBs contain the complete original skin inverse bind matrices")
	for bone_name: String in source_binds:
		_check(inverse_binds.has(bone_name), id + " preserves the original skin joint " + bone_name)
		if inverse_binds.has(bone_name):
			for component: int in range(16):
				max_skin = maxf(max_skin, absf(float(source_binds[bone_name][component]) - float(inverse_binds[bone_name][component])))
	_check(max_skin <= 0.00002, id + " raw original skin inverse bind components survive export within 20 micrometres")
	var arm_steps := _arm_rotation_steps(path, document)
	_check(arm_steps.has("upper_arm.L") and arm_steps.has("upper_arm.R"), id + " contains both real upper-arm rotation tracks")
	for arm: String in arm_steps:
		_check(float(arm_steps[arm].degrees_per_10ms) <= 30.0, id + " " + arm + " avoids a single 100fps step above 30 degrees (limb/pole-flip regression)")
	var vertices := 0
	for mesh: Dictionary in document.get("meshes", []):
		for primitive: Dictionary in mesh.primitives:
			vertices += int(document.accessors[int(primitive.attributes.POSITION)].count)
	_check(vertices == 3, id + " output contains only the three-vertex animation carrier, no copied character mesh")
	var new_track := _trajectory(rig, animations, str(enhanced.animation.clip), float(enhanced.animation.source_seconds))
	var old_track := _trajectory(old_rig, old_animations, str(original.animation.clip), float(original.animation.source_seconds))
	var difference := 0.0
	for index: int in range(new_track.samples.size()):
		for bone: String in ["pelvis", "chest", "hand.L", "hand.R"]:
			difference = maxf(difference, (new_track.samples[index][bone] as Vector3).distance_to(old_track.samples[index][bone]))
	_check(difference > 0.01, id + " enhanced pelvis/chest/wrist trajectory actually differs by over one centimetre")
	var source_path := path.get_base_dir().path_join("source-motion.json")
	_check(FileAccess.file_exists(source_path), id + " exports its controller/source measurement report alongside the baked motion")
	var source_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path)) if FileAccess.file_exists(source_path) else {}
	var footwork: Variant = source_report.get("footwork")
	if footwork is Dictionary and not (footwork as Dictionary).is_empty():
		new_track["declared_footwork_checks"] = _check_footwork(id, new_track, source_report)
	else:
		# Preserve the original contract for clips which author no step. A real
		# step must declare and meet its stricter support/contact/target contract.
		_check(float(new_track.max_foot_drift_m) <= 0.001, id + " both actual imported foot anchors remain planted within 1 mm")
		_check(float(new_track.max_foot_drift_m) <= float(old_track.max_foot_drift_m) + 0.001, id + " planted-foot drift does not regress against the actual original clip")
	_check(float(new_track.max_foot_rotation_radians) <= deg_to_rad(0.1), id + " imported feet retain their original orientation within 0.1 degrees")
	_check(float(new_track.max_leg_length_change_m) <= 0.00005, id + " actual imported leg segments keep their original length within 50 micrometres while stepping")
	_check(float(new_track.hip_motion_m) > 0.005, id + " foot locking retains real pelvis weight movement")
	var boundary_error := 0.0
	for endpoint: int in range(2):
		for bone: int in range(22):
			boundary_error = maxf(boundary_error, _transform_error(new_track.endpoint_poses[endpoint][bone], old_track.endpoint_poses[endpoint][bone]))
	_check(boundary_error <= 0.00005, id + " both exported action endpoints retain the original complete neutral pose within 50 micrometres")
	var controls: Dictionary = source_report.get("controller_rig", {})
	_check(str(source_report.get("output", {}).get("sha256", "")) == FileAccess.get_sha256(path), id + " source report is bound to the exact baked GLB bytes")
	_check(bool(source_report.get("all_pass", false)) and str(source_report.get("source", {}).get("sha256", "")) == str(catalog.profiles[enhanced.profile].source_sha256), id + " source report passed its own source/control invariants against the immutable character")
	_check(not (controls.get("controls", []) as Array).is_empty() and not (controls.get("constraints", []) as Array).is_empty(), id + " source report describes real controls and Blender constraints")
	var has_ik := false
	for constraint: Dictionary in controls.get("constraints", []):
		if str(constraint.get("type", "")) == "IK" and int(constraint.get("chain_count", 0)) == 2:
			has_ik = true
	_check(has_ik, id + " controller source includes an actual two-bone IK constraint")
	# Local editable .blend is checked by the offline receipt/root. It is not
	# shipped into the game package and is not asserted available in Web exports.
	resources.append({"id": id, "original_asset": original.animation.asset, "enhanced_asset": path, "rest_max_component_error": max_rest, "skin_max_component_error": max_skin, "actual_boundary_pose_max_error": boundary_error, "raw_arm_rotation_steps": arm_steps, "enhanced_motion": new_track, "original_motion": old_track, "max_body_trajectory_difference_m": difference, "source_measurements": source_report.get("measurements", {}), "controls": controls, "naturalness": "Requires rendered review; drift/track difference is not aesthetic approval"})
	model.free()
	old_model.free()
	source_model.free()


func _trajectory(rig: Skeleton3D, player: AnimationPlayer, clip: String, duration: float) -> Dictionary:
	var rows: Array[Dictionary] = []
	var endpoint_poses: Array = []
	var feet: Dictionary = {}
	var foot_rotation: Dictionary = {}
	var hip := Vector3.ZERO
	var max_foot := 0.0
	var max_hip := 0.0
	var max_rotation := 0.0
	var leg_lengths := {}
	var max_leg_length_change := 0.0
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var frame_count := roundi(duration * 100.0)
	for sample: int in range(frame_count + 1):
		var seconds := duration * float(sample) / float(frame_count)
		player.play(clip)
		player.seek(seconds, true)
		player.pause()
		rig.force_update_all_bone_transforms()
		if sample in [0, frame_count]:
			var pose: Array[Transform3D] = []
			for bone: int in range(rig.get_bone_count()):
				pose.append(rig.get_bone_pose(bone))
			endpoint_poses.append(pose)
		var row := {"seconds": seconds}
		for name_value: String in ["pelvis", "chest", "hand.L", "hand.R", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]:
			var pose := rig.get_bone_global_pose(rig.find_bone(name_value))
			var point := pose.origin
			row[name_value] = point
			if sample == 0:
				if name_value.begins_with("foot."):
					feet[name_value] = point
					foot_rotation[name_value] = pose.basis.get_rotation_quaternion()
				elif name_value == "pelvis":
					hip = point
			if name_value.begins_with("foot."):
				max_foot = maxf(max_foot, point.distance_to(feet[name_value]))
				max_rotation = maxf(max_rotation, pose.basis.get_rotation_quaternion().angle_to(foot_rotation[name_value]))
			elif name_value == "pelvis":
				max_hip = maxf(max_hip, point.distance_to(hip))
		for side: String in ["L", "R"]:
			for segment: Array in [["thigh.", "shin."], ["shin.", "foot."]]:
				var key := str(segment[0]) + side
				var length := (row[str(segment[0]) + side] as Vector3).distance_to(row[str(segment[1]) + side])
				if sample == 0:
					leg_lengths[key] = length
				max_leg_length_change = maxf(max_leg_length_change, absf(length - float(leg_lengths[key])))
		rows.append(row)
	return {"max_leg_length_change_m": max_leg_length_change, "max_foot_drift_m": max_foot, "max_foot_rotation_radians": max_rotation, "hip_motion_m": max_hip, "endpoint_poses": endpoint_poses, "samples": rows}


func _check_footwork(id: String, track: Dictionary, source_report: Dictionary) -> Dictionary:
	var recipe_path := "res://assets/data/martial_workshop/control_rig/" + id + ".json"
	var template_path := "res://assets/data/martial_workshop/control_rig/step_plant_return.template.json"
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(template_path))
	var contract: Dictionary = source_report.footwork
	var parameters: Dictionary = recipe.get("footwork", {})
	_check(not parameters.is_empty() and contract.get("parameters", {}) == parameters, id + " actual step has an explicit matching authored recipe contract")
	_check(str(contract.get("template", {}).get("sha256", "")) == FileAccess.get_sha256(template_path) and contract.get("keys", []) == template.get("keys", []), id + " step source binds the exact reusable template bytes and authored curve")
	_check(str(template.get("id", "")) == "step_plant_return" and str(parameters.get("active_side", "")) in ["L", "R"], id + " authored step uses the supported single-foot contact template")
	var active := "foot." + str(parameters.get("active_side", "R"))
	var support := "foot.L" if active == "foot.R" else "foot.R"
	var samples: Array = track.samples
	var initial: Dictionary = samples[0]
	var support_drift := 0.0
	var target_error := 0.0
	var planted_error := 0.0
	var forward_travel := 0.0
	var lift := 0.0
	for sample: Dictionary in samples:
		var u := float(sample.seconds) / float(recipe.seconds)
		var curve := _foot_curve(template.keys, u)
		var expected := (initial[active] as Vector3) + Vector3(0.0, float(parameters.lift_m) * curve.y, float(parameters.distance_m) * curve.x)
		support_drift = maxf(support_drift, (sample[support] as Vector3).distance_to(initial[support]))
		target_error = maxf(target_error, (sample[active] as Vector3).distance_to(expected))
		forward_travel = maxf(forward_travel, (sample[active] as Vector3).z - (initial[active] as Vector3).z)
		lift = maxf(lift, (sample[active] as Vector3).y - (initial[active] as Vector3).y)
		if u >= float(template.planted_interval[0]) and u <= float(template.planted_interval[1]):
			var planted := (initial[active] as Vector3) + Vector3(0.0, 0.0, float(parameters.distance_m))
			planted_error = maxf(planted_error, (sample[active] as Vector3).distance_to(planted))
	var boundary := (samples[-1][active] as Vector3).distance_to(initial[active])
	_check(support_drift <= 0.00005, id + " actual imported support foot stays locked within 50 micrometres")
	_check(target_error <= 0.00005, id + " actual moving ankle follows the independently evaluated authored target within 50 micrometres")
	_check(planted_error <= 0.00005, id + " actual active foot stays on its new ground contact throughout the authored planted interval within 50 micrometres")
	_check(boundary <= 0.00005, id + " active foot returns to its original full neutral boundary within 50 micrometres")
	_check(absf(forward_travel - float(parameters.distance_m)) <= 0.00005 and absf(lift - float(parameters.lift_m)) < 0.0002 and forward_travel >= 0.15 and lift >= 0.035, id + " imported move has the authored meaningful forward step and lift")
	return {"support_foot_drift_m": support_drift, "active_target_error_m": target_error, "planted_contact_error_m": planted_error, "active_boundary_error_m": boundary, "active_forward_travel_m": forward_travel, "active_lift_m": lift, "template_sha256": FileAccess.get_sha256(template_path), "source": "Actual imported 100fps original-bone global poses; independent smoothstep template evaluation"}


func _foot_curve(keys: Array, u: float) -> Vector2:
	for index: int in range(1, keys.size()):
		if u <= float(keys[index].t):
			var a: Dictionary = keys[index - 1]
			var b: Dictionary = keys[index]
			var x := clampf((u - float(a.t)) / (float(b.t) - float(a.t)), 0.0, 1.0)
			var smooth := x * x * (3.0 - 2.0 * x)
			return Vector2(lerpf(float(a.advance), float(b.advance), smooth), lerpf(float(a.lift), float(b.lift), smooth))
	return Vector2(float(keys[-1].advance), float(keys[-1].lift))


func _negative_cases() -> void:
	_reject_path(["schema_version"], 9, "Unknown sidecar schema")
	_reject_path(["base_catalog_sha256"], "0".repeat(64), "Enhancement targets an unrelated original catalog")
	_reject_path(["variants", 0, "move_id"], "missing_move", "Enhancement has no original move")
	_reject_path(["variants", 0, "variant_id"], "original", "Sidecar cannot replace the original variant")
	_reject_path(["variants", 0, "variant_label"], "", "Variant requires a player-visible label")
	_reject_path(["variants", 0, "move", "id"], "different_id", "Variant cannot remap move identity")
	_reject_path(["variants", 0, "move", "actor"], "tinglan" if str(variants.variants[0].move.actor) == "player" else "player", "Variant cannot exchange actor")
	_reject_path(["variants", 0, "move", "timing", "impact"], 0.7, "A/B timing mismatch")
	_reject_path(["variants", 0, "move", "camera", "zoom"], 0.9, "A/B camera mismatch")
	_reject_path(["variants", 0, "move", "visual", "config", "width"], 0.3, "A/B effect mismatch")
	_reject_path(["variants", 0, "move", "audio", "release"], "res://assets/%s.wav" % "missing", "A/B sound mismatch")
	_reject_path(["variants", 0, "move", "preview_only"], false, "Enhancement cannot become a new combat rule")
	_reject_path(["variants", 0, "move", "animation", "sha256"], "0".repeat(64), "Changed enhanced resource bytes")
	_reject_path(["variants", 0, "move", "variants"], {"nested": {}}, "Nested variants cannot enter runtime")
	var duplicate := variants.duplicate(true)
	duplicate.variants.append(duplicate.variants[0].duplicate(true))
	_reject(duplicate, "Duplicate move/variant pair")
	var missing := variants.duplicate(true)
	missing.variants[0].move.animation.asset = "res://assets/%s.glb" % "missing-enhancement"
	_reject(missing, "Missing enhanced imported motion")


func _reject_path(path: Array, value: Variant, label: String) -> void:
	var data := variants.duplicate(true)
	var cursor: Variant = data
	for index: int in range(path.size() - 1):
		cursor = cursor[path[index]]
	cursor[path[-1]] = value
	_reject(data, label)


func _reject(data: Dictionary, label: String) -> void:
	var result: Dictionary = Catalog.validate_variants(base, data, true)
	_check(not bool(result.get("ok", true)) and not str(result.get("reason", "")).is_empty(), label + " is rejected with a useful reason")
	rejected.append({"case": label, "result": result})


func _base_move(id: String) -> Dictionary:
	for move: Dictionary in base.moves:
		if str(move.id) == id:
			return move
	return {}


func _first(node: Node, type: String) -> Node:
	var found := node.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


func _transform_error(a: Transform3D, b: Transform3D) -> float:
	var value := a.origin.distance_to(b.origin)
	for axis: int in range(3):
		value = maxf(value, a.basis[axis].distance_to(b.basis[axis]))
	return value


func _glb_json(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	_check(bytes.size() > 20 and bytes.decode_u32(0) == 0x46546c67 and bytes.decode_u32(4) == 2, "Real glTF 2 binary header: " + path.get_file())
	if bytes.size() <= 20:
		return {}
	var size := bytes.decode_u32(12)
	return JSON.parse_string(bytes.slice(20, 20 + size).get_string_from_utf8())


func _inverse_binds(path: String, document: Dictionary) -> Dictionary:
	var result := {}
	if (document.get("skins", []) as Array).is_empty():
		return result
	var skin: Dictionary = document.skins[0]
	if not skin.has("inverseBindMatrices"):
		return result
	var accessor: Dictionary = document.accessors[int(skin.inverseBindMatrices)]
	_check(str(accessor.type) == "MAT4" and int(accessor.componentType) == 5126, "Raw skin bind matrices are explicit float MAT4 values")
	if str(accessor.type) != "MAT4" or int(accessor.componentType) != 5126:
		return result
	var bytes := FileAccess.get_file_as_bytes(path)
	var view: Dictionary = document.bufferViews[int(accessor.bufferView)]
	var offset := 20 + int(bytes.decode_u32(12)) + 8 + int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var stride := int(view.get("byteStride", 64))
	for index: int in range(int(accessor.count)):
		var node: Dictionary = document.nodes[int(skin.joints[index])]
		var matrix: Array[float] = []
		for component: int in range(16):
			matrix.append(bytes.decode_float(offset + index * stride + component * 4))
		result[str(node.name)] = matrix
	return result


func _arm_rotation_steps(path: String, document: Dictionary) -> Dictionary:
	var result := {}
	for channel: Dictionary in document.animations[0].channels:
		var name_value := str(document.nodes[int(channel.target.node)].name)
		if str(channel.target.path) != "rotation":
			continue
		var sampler: Dictionary = document.animations[0].samplers[int(channel.sampler)]
		var times := _float_accessor(path, document, int(sampler.input), 1)
		var rotations := _float_accessor(path, document, int(sampler.output), 4)
		var largest := 0.0
		var at := 0.0
		for index: int in range(1, rotations.size()):
			var a: Array = rotations[index - 1]
			var b: Array = rotations[index]
			var previous := Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
			var current := Quaternion(float(b[0]), float(b[1]), float(b[2]), float(b[3])).normalized()
			var step := float(times[index][0]) - float(times[index - 1][0])
			if step <= 0.0:
				continue
			var degrees := rad_to_deg(previous.angle_to(current)) * 0.01 / step
			if degrees > largest:
				largest = degrees
				at = float(times[index - 1][0])
		result[name_value] = {"degrees_per_10ms": largest, "at_source_seconds": at}
	return result


func _float_accessor(path: String, document: Dictionary, index: int, components: int) -> Array:
	var result: Array = []
	var accessor: Dictionary = document.accessors[index]
	var view: Dictionary = document.bufferViews[int(accessor.bufferView)]
	var bytes := FileAccess.get_file_as_bytes(path)
	var offset := 20 + int(bytes.decode_u32(12)) + 8 + int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var stride := int(view.get("byteStride", components * 4))
	for row: int in range(int(accessor.count)):
		var values: Array[float] = []
		for component: int in range(components):
			values.append(bytes.decode_float(offset + row * stride + component * 4))
		result.append(values)
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)


func _finish() -> void:
	var report := {"test": "martial_control_rig", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "variants_sha256": FileAccess.get_sha256(VARIANT_PATH) if FileAccess.file_exists(VARIANT_PATH) else "", "rejections": rejected, "actual_resource_trajectories": resources, "boundary": "CPU actual imported 22-bone animation and raw GLB/schema/hash validation. This cannot establish natural-looking choreography or browser/Windows/device-audio acceptance."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("MARTIAL CONTROL RIG: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
