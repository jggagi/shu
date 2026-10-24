extends SceneTree

const TrialScene := preload("res://scenes/demos/dialogue_tools_trial.tscn")
const MANIFEST_PATH := "res://assets/audio/mentor_pause/manifest.json"
const OPENING_NODES := ["opening", "sit", "hurry", "advice", "choice"]
const MAX_ADVANCE_STEPS := 240
const DEADLINE_MSEC := 45000

var app: Control
var started_msec := 0
var deadline_msec := 0
var checks := 0
var failures := 0
var failure_messages: Array[String] = []
var qa_save_dirs: Array[String] = []
var backend_results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 120
	started_msec = Time.get_ticks_msec()
	deadline_msec = started_msec + DEADLINE_MSEC
	for backend in ["dm", "dialogic"]:
		if not _within_deadline("启动 " + backend):
			break
		await _exercise_backend(str(backend))
	await _finish()


func _exercise_backend(target_backend: String) -> void:
	var failures_before := failures
	app = TrialScene.instantiate() as Control
	_check(app != null, target_backend + " 场景实例化成功")
	if app == null:
		backend_results.append({"backend": target_backend, "started": false})
		return
	root.add_child(app)
	await process_frame
	await process_frame
	if not _within_deadline(target_backend + " 初始化"):
		await _dispose_app()
		return

	var initial_snapshot := _snapshot(app)
	_check(str(app.get("backend")) == "dm", target_backend + " 试样从 Dialogue Manager 初始后端启动")
	_check(str(initial_snapshot.get("phase", "")) == "ready", target_backend + " 初始化 Session 处于可行动状态")
	var voice_warning := str(_audit(app).get("voice_warning", ""))
	_check(voice_warning.is_empty(), target_backend + " 本地配音清单可用：" + voice_warning)
	var voice := app.get("voice") as Node
	_check(is_instance_valid(voice), target_backend + " 控制器创建语音播放器")
	if not is_instance_valid(voice):
		await _dispose_app()
		return

	var manifest_clip := _first_manifest_clip()
	_check(not manifest_clip.is_empty(), "语音清单包含可播放片段")
	if manifest_clip.is_empty():
		await _dispose_app()
		return
	app.call("_select_backend", target_backend)
	var probe_play: Dictionary = voice.call("play_line", str(manifest_clip.get("speaker", "")), str(manifest_clip.get("text", "")))
	_check(bool(probe_play.get("ok", false)) and bool(_voice_audit(app).get("playing", false)), target_backend + " 切换前语音能开始播放")
	var other_backend := "dialogic" if target_backend == "dm" else "dm"
	app.call("_select_backend", other_backend)
	_check(str(app.get("backend")) == other_backend, target_backend + " 可切换到另一剧情工具")
	_check(_voice_stopped(app), target_backend + " 切换工具会停止并清空旧语音")
	app.call("_select_backend", target_backend)
	_check(str(app.get("backend")) == target_backend, target_backend + " 可切回目标剧情工具")
	_check(_voice_stopped(app), target_backend + " 切回工具后没有旧语音")

	var save_base := _allocate_save_dir(target_backend)
	var saves := app.get("saves") as Object
	_check(is_instance_valid(saves), target_backend + " 控制器初始化 SaveStore")
	if not is_instance_valid(saves):
		await _dispose_app()
		return
	saves.set("base_dir", save_base)
	_check(str(saves.get("base_dir")) == save_base, target_backend + " SaveStore 使用独立 QA 存档目录")

	# Confirm a duplicate line callback cannot start a second overlapping clip.
	app.call("_action", "talk")
	if not await _wait_for_node("opening"):
		_check(false, target_backend + " 真实工具开始五句开场对白：" + _runtime_failure(app))
		await _dispose_app()
		backend_results.append({"backend": target_backend, "started": false, "runtime_failure": _runtime_failure(app)})
		return
	_check(_real_backend_started(target_backend), target_backend + " 使用已安装插件的真实解析／时间线运行时")
	var opening_voice := _voice_audit(app)
	_check(bool(opening_voice.get("enabled", false)) and bool(opening_voice.get("playing", false)), target_backend + " 开场语音确实开始播放")
	_check(str(opening_voice.get("current_id", "")) == "opening", target_backend + " 开场语音与当前对白匹配")
	var voice_player := voice.get_node_or_null("MentorVoicePlayer") as AudioStreamPlayer
	_check(is_instance_valid(voice_player), target_backend + " 使用唯一 AudioStreamPlayer")
	var player_instance_id := voice_player.get_instance_id() if is_instance_valid(voice_player) else 0
	var play_count_before_duplicate := int(opening_voice.get("play_count", -1))
	var old_driver := app.get("driver") as Node
	if is_instance_valid(old_driver) and old_driver.has_signal("line_ready"):
		var opening_event := _event(app)
		old_driver.emit_signal("line_ready", str(opening_event.get("speaker_name", "")), str(opening_event.get("text", "")), [])
	else:
		_check(false, target_backend + " 当前真实工具提供 line_ready 信号")
	_check(int(_voice_audit(app).get("play_count", -2)) == play_count_before_duplicate, target_backend + " 重复对白回调不会重复播放")

	# Muting stops the active voice without changing authoritative Session state.
	var before_mute := _snapshot(app)
	app.call("_action", "voice_toggle")
	_check(_snapshot(app) == before_mute, target_backend + " 静音不改变 Session")
	_check(not bool(_voice_audit(app).get("enabled", true)) and _voice_stopped(app), target_backend + " 静音会停止当前片段")
	var count_before_muted_line := int(_voice_audit(app).get("play_count", -1))
	if not await _advance_to_node("sit"):
		_check(false, target_backend + " 静音期间继续对白：" + _runtime_failure(app))
		await _dispose_app()
		return
	_check(_snapshot(app).get("stats", {}) == before_mute.get("stats", {}), target_backend + " 静音期间对白仍不修改 Session 属性")
	_check(int(_voice_audit(app).get("play_count", -2)) == count_before_muted_line and not bool(_voice_audit(app).get("playing", true)), target_backend + " 静音期间新对白不播放")
	app.call("_action", "voice_toggle")
	if not await _advance_to_node("hurry"):
		_check(false, target_backend + " 恢复声音后继续对白：" + _runtime_failure(app))
		await _dispose_app()
		return
	var next_voice := _voice_audit(app)
	_check(bool(next_voice.get("enabled", false)) and bool(next_voice.get("playing", false)), target_backend + " 恢复声音后下一句开始播放")
	_check(str(next_voice.get("current_id", "")) == "hurry" and int(next_voice.get("play_count", -1)) == count_before_muted_line + 1, target_backend + " 恢复后只播放当前新句")
	voice_player = voice.get_node_or_null("MentorVoicePlayer") as AudioStreamPlayer
	_check(is_instance_valid(voice_player) and voice_player.get_instance_id() == player_instance_id, target_backend + " 连续对白共用单一播放器，避免重叠")

	# Cancel while the real tool and voice are active, then deliver its stale callback.
	var cancelled_driver := app.get("driver") as Node
	var cancelled_token := int(app.get("trial_token"))
	app.call("_cancel")
	_check(not bool(app.get("busy")) and _voice_stopped(app), target_backend + " 取消交谈会停止语音并释放忙碌状态")
	_check(str(_snapshot(app).get("phase", "")) == "ready" and app.get("driver") == null, target_backend + " 取消后 Session 回到可行动状态且控制器释放工具")
	var count_after_cancel := int(_voice_audit(app).get("play_count", -1))
	var stale_event := _event(app)
	var stale_speaker := str(stale_event.get("speaker_name", "叶知闲"))
	var stale_text := str(stale_event.get("text", "迟到的旧对白"))
	if is_instance_valid(cancelled_driver) and cancelled_driver.has_signal("line_ready"):
		cancelled_driver.emit_signal("line_ready", stale_speaker, stale_text, [])
	else:
		app.call("_on_tool_line", stale_speaker, stale_text, [], cancelled_token)
	_check(int(_voice_audit(app).get("play_count", -2)) == count_after_cancel and _voice_stopped(app), target_backend + " 取消后的迟到回调不能重新播放旧语音")
	await _wait_for_driver_release(cancelled_driver)
	_check(not is_instance_valid(cancelled_driver), target_backend + " 取消后退休的剧情工具已释放")

	# Switch once more while audio is active, checking the controller's teardown path.
	probe_play = voice.call("play_line", str(manifest_clip.get("speaker", "")), str(manifest_clip.get("text", "")))
	_check(bool(probe_play.get("ok", false)) and bool(_voice_audit(app).get("playing", false)), target_backend + " 切换清理复测前语音正在播放")
	app.call("_select_backend", other_backend)
	_check(str(app.get("backend")) == other_backend and _voice_stopped(app), target_backend + " 活跃语音期间切换工具会停止旧片段")
	app.call("_select_backend", target_backend)
	saves.set("base_dir", save_base)
	_check(str(app.get("backend")) == target_backend and _voice_stopped(app), target_backend + " 切回后旧片段仍已停止")

	# Acceptance branch: five opening lines, choice, two reply lines, then result.
	app.call("_action", "talk")
	if not await _drive_opening_to_choice():
		_check(false, target_backend + " 五句开场抵达选择节点：" + _runtime_failure(app))
		await _dispose_app()
		return
	var choice_event := _event(app)
	_check(str(choice_event.get("node_id", "")) == "choice" and str(choice_event.get("type", "")) == "choice", target_backend + " 五句开场后显示 Session 白名单选择")
	_check(str(_voice_audit(app).get("current_id", "")) == "choice", target_backend + " 选择提示也有对应的语音片段")
	var before_choice := _snapshot(app)
	app.call("_choice", "take_lesson")
	if not await _wait_until_accepted():
		_check(false, target_backend + " 接受选择由 Session 结算：" + _runtime_failure(app))
		await _dispose_app()
		return
	var after_choice := _snapshot(app)
	_check(_stat(after_choice, "energy") == 92 and _stat(after_choice, "understanding") == 1, target_backend + " 领会后精力92、理解1")
	_check(int(after_choice.get("slot", -1)) == 1 and int(after_choice.get("counts", {}).get("claim_mentor_lesson", 0)) == 1, target_backend + " 领会只推进一时辰并结算一次")
	_check(_stat(after_choice, "cultivation") == _stat(before_choice, "cultivation"), target_backend + " 领会时不提前增加修为")
	if not await _advance_to_node("lesson_taken") or not await _advance_to_node("lesson_reply") or not await _finish_dialogue():
		_check(false, target_backend + " 接受分支两句对白可结束：" + _runtime_failure(app))
		await _dispose_app()
		return
	_check(str(_snapshot(app).get("phase", "")) == "result" and not bool(app.get("busy")), target_backend + " 接受分支结束后释放对白工具")
	_check(_voice_stopped(app), target_backend + " 接受分支结束会停止语音")

	app.call("_action", "train")
	var trained := _snapshot(app)
	_check(str(trained.get("phase", "")) == "result", target_backend + " 修习行动完成")
	_check(_stat(trained, "energy") == 70 and _stat(trained, "cultivation") == 18, target_backend + " 修习后精力70、修为18，提示加成只用一次")
	_check(int(trained.get("slot", -1)) == 3 and int(trained.get("counts", {}).get("train_mountain", 0)) == 1, target_backend + " 修习推进两时辰且只结算一次")
	var save_result: Dictionary = saves.call("save_session", app.get("session"))
	_check(bool(save_result.get("ok", false)), target_backend + " SaveStore 写入真实本机存档")
	var saved_snapshot := _snapshot(app).duplicate(true)
	var checkpoint := ProjectSettings.globalize_path(save_base.path_join("dialogue_tools_sample/checkpoint_0.json"))
	_check(FileAccess.file_exists(checkpoint), target_backend + " 独立 QA 目录中存在 SaveStore 检查点")
	var session := app.get("session") as Object
	session.call("start_new")
	_check(_snapshot(app) != saved_snapshot, target_backend + " 存档读取前 Session 已改变")
	var load_result: Dictionary = saves.call("load_session", session)
	_check(bool(load_result.get("ok", false)) and _snapshot(app) == saved_snapshot, target_backend + " SaveStore 真实读档精确恢复 Session")

	# Decline branch: no resource change, gain, time, flag, or action count.
	app.call("_action", "reset")
	app.call("_action", "talk")
	if not await _drive_opening_to_choice():
		_check(false, target_backend + " 拒绝路径抵达选择节点：" + _runtime_failure(app))
		await _dispose_app()
		return
	var before_decline := _snapshot(app)
	app.call("_choice", "return_to_practice")
	if not await _wait_for_node("lesson_skipped"):
		_check(false, target_backend + " Session 接受不领会选择：" + _runtime_failure(app))
		await _dispose_app()
		return
	var declined := _snapshot(app)
	_check(declined.get("stats", {}) == before_decline.get("stats", {}), target_backend + " 拒绝分支不消耗精力或增加属性")
	_check(int(declined.get("slot", -1)) == int(before_decline.get("slot", -2)) and declined.get("flags", {}) == before_decline.get("flags", {}), target_backend + " 拒绝分支不推进时间或写入领会标记")
	_check(declined.get("counts", {}) == before_decline.get("counts", {}), target_backend + " 拒绝分支不增加养成行动次数")
	if not await _advance_to_node("skip_reply") or not await _finish_dialogue():
		_check(false, target_backend + " 拒绝分支两句对白可结束：" + _runtime_failure(app))
	else:
		_check(str(_snapshot(app).get("phase", "")) == "result" and _voice_stopped(app), target_backend + " 拒绝分支结束并停止语音")

	backend_results.append({"backend": target_backend, "started": true, "checks": checks, "new_failures": failures - failures_before})
	await _dispose_app()


func _drive_opening_to_choice() -> bool:
	if not await _wait_for_node(OPENING_NODES[0]):
		return false
	for index in range(1, OPENING_NODES.size()):
		if not await _advance_to_node(str(OPENING_NODES[index])):
			return false
	if str(app.get("backend")) == "dialogic":
		for unused in range(MAX_ADVANCE_STEPS):
			var current_driver := app.get("driver") as Node
			if is_instance_valid(current_driver) and bool(current_driver.get("_waiting_question")):
				await create_timer(float(ProjectSettings.get_setting("dialogic/choices/delay", 0.2)) + 0.05).timeout
				return true
			if not _runtime_failure(app).is_empty() or not _within_deadline("等待原生选择显示"):
				return false
			app.call("_advance")
			await process_frame
		return false
	return true


func _wait_for_node(node_id: String) -> bool:
	for unused in range(MAX_ADVANCE_STEPS):
		if _node_presented(node_id):
			return true
		if not _runtime_failure(app).is_empty() or not _within_deadline("等待对白 " + node_id):
			return false
		await process_frame
	return _node_presented(node_id)


func _advance_to_node(node_id: String) -> bool:
	for unused in range(MAX_ADVANCE_STEPS):
		if _node_presented(node_id):
			return true
		if not bool(app.get("busy")) or not _runtime_failure(app).is_empty() or not _within_deadline("推进对白到 " + node_id):
			return false
		app.call("_advance")
		await process_frame
	return _node_presented(node_id)


func _node_presented(node_id: String) -> bool:
	if str(_event(app).get("node_id", "")) != node_id:
		return false
	var audio := _voice_audit(app)
	if bool(audio.get("enabled", true)):
		return str(audio.get("current_id", "")) == node_id
	return _real_backend_started(str(app.get("backend")))


func _wait_until_accepted() -> bool:
	for unused in range(MAX_ADVANCE_STEPS):
		var snapshot := _snapshot(app)
		if _stat(snapshot, "energy") == 92 and _stat(snapshot, "understanding") == 1 and int(snapshot.get("slot", -1)) == 1:
			return true
		if not _runtime_failure(app).is_empty() or not _within_deadline("等待领会结算"):
			return false
		await process_frame
	return false


func _finish_dialogue() -> bool:
	for unused in range(MAX_ADVANCE_STEPS):
		var snapshot := _snapshot(app)
		if str(snapshot.get("phase", "")) == "result" and not bool(app.get("busy")):
			return true
		if not bool(app.get("busy")) or not _runtime_failure(app).is_empty() or not _within_deadline("等待对白结束"):
			return false
		app.call("_advance")
		await process_frame
	return str(_snapshot(app).get("phase", "")) == "result" and not bool(app.get("busy"))


func _wait_for_driver_release(retired: Node) -> void:
	for unused in range(MAX_ADVANCE_STEPS):
		if not is_instance_valid(retired) or not _within_deadline("等待旧工具释放"):
			return
		await process_frame


func _real_backend_started(target_backend: String) -> bool:
	var driver := app.get("driver") as Node
	if not is_instance_valid(driver) or not driver.has_method("audit"):
		return false
	var tool_audit: Dictionary = driver.call("audit")
	return bool(tool_audit.get("used_real_parser", false)) if target_backend == "dm" else bool(tool_audit.get("used_real_timeline", false))


func _first_manifest_clip() -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK or not parser.data is Dictionary:
		return {}
	var clips: Variant = parser.data.get("clips", [])
	if not clips is Array or (clips as Array).is_empty() or not (clips as Array)[0] is Dictionary:
		return {}
	return (clips as Array)[0] as Dictionary


func _allocate_save_dir(target_backend: String) -> String:
	var path := "user://mentor_voice_scene_qa_%d_%s" % [Time.get_ticks_usec(), target_backend]
	qa_save_dirs.append(path)
	return path


func _audit(target: Control) -> Dictionary:
	var value: Variant = target.call("audit") if is_instance_valid(target) else {}
	return value as Dictionary if value is Dictionary else {}


func _snapshot(target: Control) -> Dictionary:
	var value: Variant = _audit(target).get("snapshot", {})
	return value as Dictionary if value is Dictionary else {}


func _event(target: Control) -> Dictionary:
	var value: Variant = _audit(target).get("event", {})
	return value as Dictionary if value is Dictionary else {}


func _voice_audit(target: Control) -> Dictionary:
	return _audit(target).get("voice", {}) as Dictionary


func _voice_stopped(target: Control) -> bool:
	var voice := _voice_audit(target)
	return not bool(voice.get("playing", true)) and str(voice.get("current_id", "")).is_empty()


func _stat(snapshot: Dictionary, stat_id: String) -> int:
	return int(snapshot.get("stats", {}).get(stat_id, -1))


func _runtime_failure(target: Control) -> String:
	return str(_audit(target).get("failure", ""))


func _within_deadline(label: String) -> bool:
	if Time.get_ticks_msec() < deadline_msec:
		return true
	_check(false, "45秒测试期限内完成：" + label)
	return false


func _dispose_app() -> void:
	if is_instance_valid(app):
		var retired := app.get("driver") as Node
		if bool(app.get("busy")):
			app.call("_cancel")
		if is_instance_valid(retired):
			await _wait_for_driver_release(retired)
		app.queue_free()
		await process_frame
	app = null


func _cleanup_save_dirs() -> void:
	for base_dir in qa_save_dirs:
		var game_dir := ProjectSettings.globalize_path(str(base_dir).path_join("dialogue_tools_sample"))
		for filename in ["checkpoint_0.json", "checkpoint_1.json", "checkpoint_0.json.pending", "checkpoint_1.json.pending"]:
			DirAccess.remove_absolute(game_dir.path_join(filename))
		DirAccess.remove_absolute(game_dir)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(base_dir)))


func _finish() -> void:
	await _dispose_app()
	_cleanup_save_dirs()
	var report := {
		"test": "mentor_voice_scene_test",
		"checks": checks,
		"failures": failures,
		"elapsed_msec": Time.get_ticks_msec() - started_msec,
		"backend_results": backend_results,
		"failure_messages": failure_messages,
		"audio_listening_tested": false,
	}
	print(JSON.stringify(report, "", true))
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	failure_messages.append(message)
	push_error(message)
