extends SceneTree
const Actor = preload("res://addons/cultivation_mode/ambush_actor.gd")
const Motion = preload("res://addons/cultivation_mode/ambush_staff_motion.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var actor := Actor.new() as Node3D
	root.add_child(actor)
	actor.call("setup", "brute", "brute", false)
	actor.set_process(false)
	actor.position = Vector3(2.0, 0.0, -1.0)
	actor.rotation.y = 0.55
	var initial := actor.transform
	var old_meshes: Array = actor.get("_original_enemy_meshes").duplicate()
	var identities: Array = []
	for mesh: MeshInstance3D in old_meshes:
		identities.append([mesh.mesh, mesh.material_override])
	for clip: String in ["idle", "intent", "attack", "interrupt", "recoil", "stagger", "walk"]:
		for amount: float in [0.0, 0.27, 0.55, 0.85, 1.0]:
			var seconds := amount * Motion.duration(clip)
			actor.call("sample_staff_motion", clip, seconds)
			await process_frame
			await process_frame
			var data: Dictionary = actor.call("staff_motion_audit")
			var rig: Dictionary = data.rig
			_check(data.clip == clip and is_equal_approx(float(data.time), seconds), "Caller remains the sole clip-time authority")
			_check(actor.transform == initial and not actor.is_processing(), "Sampling never translates or enables the actor root")
			_check(int(rig.sample_revision) == int(rig.solved_revision) and int(rig.bone_count) == 16, "The actual native skeleton completes the requested revision")
			for side: String in ["left", "right"]:
				_check(float(rig.arms[side].world_grip_error) <= 0.015, "The actual hand remains on its staff grip")
				_check(float(rig.feet[side].contact_error) <= 0.02, "The actual boot sole reaches the authored contact")
	actor.call("sample_staff_motion", "attack", 0.55)
	for enabled: bool in [false, true, false, true]:
		actor.call("set_staff_motion_enabled", enabled)
		await process_frame
		var data: Dictionary = actor.call("staff_motion_audit")
		_check(data.enabled == enabled and is_equal_approx(float(data.time), 0.55) and data.clip == "attack", "Motion comparison preserves the exact requested phrase time")
		_check(actor.transform == initial, "Motion comparison preserves the world anchor")
	for refined: bool in [false, true, false, true]:
		actor.call("set_refined_details", refined)
		await process_frame
		var index := 0
		for mesh: MeshInstance3D in old_meshes:
			_check(mesh.mesh == identities[index][0] and mesh.material_override == identities[index][1], "Archived appearance resource identity remains exact")
			_check(mesh.visible == not refined, "Original art remains exactly available for comparison")
			index += 1
	actor.call("set_motion", "hit")
	actor.call("_process", 0.09)
	_check((actor.get("_mode") as String) == "hit", "A real damage request enters articulated recoil")
	actor.call("_process", 0.6)
	_check((actor.get("_mode") as String) == "idle", "A real recoil recovers to guard")
	for mesh: MeshInstance3D in actor.get("_meshes"):
		_check(mesh.material_overlay == null, "Recovery clears both retained and articulated hit overlays")
	actor.queue_free()
	await process_frame
	var output := "res://.local/qa/staff-rules"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"scope":"Actual Actor/Skeleton contact, sampling, retained-resource identity and recoil cleanup; headless, not art review"},"\t")+"\n")
	print("STAFF ACTOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: " + message)
