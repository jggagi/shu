extends SceneTree

const TrialScene := preload("res://scenes/demos/dialogue_tools_trial.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/dialogue-tools-lab-render"
const OPENING_TEXT := "师父，刚才那一剑，我明明已经快了，怎么还是收不住？"
const CHOICE_TEXT := "先陪我听一会儿雨。等肩膀松了，再想刚才那一剑。"
const ACCEPTED_TEXT := "好，我不抢。先把这一口气放稳。"
const DECLINED_TEXT := "那我先去试试。要是还不对，我再来找您。"
const DEADLINE_MSEC := 20000

var app: Control
var output_dir := DEFAULT_OUTPUT
var qa_size := Vector2i.ZERO
var isolated_store_dir := ""
var deadline_msec := 0
var checks := 0
var failures := 0
var failure_messages: Array[String] = []
var check_records: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var snapshots: Dictionary = {}
var _finished := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	deadline_msec = Time.get_ticks_msec() + DEADLINE_MSEC
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	if qa_size != Vector2i.ZERO:
		root.size = qa_size
	else:
		qa_size = Vector2i(root.size)
	Engine.max_fps = 60
	var output_path := _absolute_output_dir()
	var mkdir_result := DirAccess.make_dir_recursive_absolute(output_path)
	check(mkdir_result == OK or mkdir_result == ERR_ALREADY_EXISTS, "独立截图目录可以写入")
	check(DisplayServer.get_name() != "headless", "GUI 验收使用可交互的显示后端")
	if DisplayServer.get_name() == "headless":
		_finish()
		return

	app = TrialScene.instantiate() as Control
	check(app != null, "独立试样场景实例化为 Control")
	if app == null:
		_finish()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	if not _within_deadline("试样初始化"):
		_finish()
		return

	var saves: Variant = app.get("saves")
	check(saves != null, "控制器初始化了本机存档器")
	if saves == null:
		_finish()
		return
	isolated_store_dir = _allocate_store_dir()
	check(not isolated_store_dir.is_empty(), "为本轮试跑分配独立存档目录")
	if isolated_store_dir.is_empty():
		_finish()
		return
	saves.set("base_dir", isolated_store_dir)
	check(str(saves.get("base_dir")) == isolated_store_dir, "试跑只写入独立的 user:// 存档目录")
	await process_frame

	var initial := _snapshot()
	snapshots["initial"] = initial.duplicate(true)
	check(_is_ready_snapshot(initial), "初始状态为第一日卯时、精力100、修为0")
	await _capture("00_initial.png", "初始状态与剧情工具对照")

	# Exercise busy-time UI guards with real pointer input. The visible dialogue
	# controls remain usable; the outside actions are visibly disabled.
	if not await _start_talk_and_wait(OPENING_TEXT):
		_finish()
		return
	check(bool(_audit().get("busy", false)), "请教开始后控制器处于交谈中")
	var parser_audit: Dictionary = _audit().get("tool", {})
	check(bool(parser_audit.get("used_real_parser", false)), "Dialogue Manager 已使用插件真实解析器")
	check(not _node_disabled("DialogueToolsLabCanvas/DialoguePaper/AdvanceButton"), "交谈中可点击对白推进")
	check(not _node_disabled("DialogueToolsLabCanvas/DialoguePaper/CancelButton"), "交谈中可点击收起")
	var busy_snapshot := _snapshot().duplicate(true)
	for probe: Dictionary in [
		{"rect": "footer_save", "node": "DialogueToolsLabCanvas/SaveButton", "name": "存档"},
		{"rect": "backend_dialogic", "node": "DialogueToolsLabCanvas/BackendDialogic", "name": "切换工具"},
		{"rect": "footer_reset", "node": "DialogueToolsLabCanvas/ResetButton", "name": "重置"},
	]:
		check(_node_disabled(str(probe.node)), "%s 在交谈时禁用" % str(probe.name))
		await _click_ui_rect(str(probe.rect))
		check(_snapshot() == busy_snapshot and bool(_audit().get("busy", false)), "%s 的真实鼠标输入不改变交谈状态" % str(probe.name))
	check(str(_audit().get("backend", "")) == "dm", "交谈中点击另一工具不会切换后端")

	# Cancel, immediately reset, and send the retired driver's late signal before
	# the queued Node deletion runs. The normal UI event path must ignore it.
	var retired_driver := app.get("driver") as Node
	check(is_instance_valid(retired_driver), "交谈期间可观察到当前剧情工具实例")
	_send_escape_immediate()
	check(not bool(_audit().get("busy", true)), "Esc 收起交谈并释放行动状态")
	_click_ui_rect_immediate("footer_reset")
	var reset_after_cancel := _snapshot().duplicate(true)
	snapshots["cancel_reset"] = reset_after_cancel.duplicate(true)
	if is_instance_valid(retired_driver):
		retired_driver.emit_signal("line_ready", "叶知闲", "迟到的旧对白", [])
	else:
		check(false, "旧剧情工具在排队释放前仍可发送迟到回调")
	await process_frame
	await process_frame
	check(_snapshot() == reset_after_cancel and not bool(_audit().get("busy", true)), "重置后旧剧情工具的迟到回调不改变状态")
	check(_is_ready_snapshot(_snapshot()), "Esc 取消并重置后仍回到干净初始状态")

	if not await _click_ui_rect("action_train"):
		_finish()
		return
	var after_cancel_action := _snapshot()
	check(str(after_cancel_action.get("phase", "")) == "result", "Esc 取消后可以通过真实行动按钮继续试玩")
	check(_stat(after_cancel_action, "energy") == 78 and _stat(after_cancel_action, "cultivation") == 12 and int(after_cancel_action.get("slot", -1)) == 2, "取消后的修习按内容包数值结算")
	if not await _click_ui_rect("advance"):
		_finish()
		return
	if not await _wait_snapshot_ready():
		_finish()
		return
	if not await _click_ui_rect("footer_reset"):
		_finish()
		return
	check(_is_ready_snapshot(_snapshot()), "重新开始后恢复内容包初始状态")

	# Take the lesson through the same screen controls used by the player.
	if not await _start_talk_and_wait(OPENING_TEXT):
		_finish()
		return
	if not await _reach_question():
		_finish()
		return
	check(_choice_exists("take_lesson"), "真实对白页面显示领会提示选项")
	check(not _node_disabled("DialogueToolsLabCanvas/DialoguePaper/ChoiceHost/Choice_take_lesson"), "交谈中可点选已启用的剧情选项")
	await _capture("01_choice.png", "师傅提出是否领会提示的选择")
	var take_rect := _choice_rect("take_lesson")
	check(take_rect.size.x > 0.0 and take_rect.size.y > 0.0, "领会提示选项提供真实屏幕命中区域")
	if take_rect.size.x <= 0.0 or take_rect.size.y <= 0.0:
		_finish()
		return
	await _click_rect(take_rect, 2)
	var after_choice := _snapshot()
	snapshots["accepted_choice"] = after_choice.duplicate(true)
	check(_stat(after_choice, "energy") == 92, "重复点击领会提示只扣除一次精力")
	check(_stat(after_choice, "cultivation") == 0 and _stat(after_choice, "understanding") == 1, "领会提示只增加一次理解，不提前增加修为")
	check(int(after_choice.get("slot", -1)) == 1 and bool(after_choice.get("flags", {}).get("breathing_hint", false)), "领会提示推进一个时辰并留下修习提示")
	if not await _wait_dialogue_text(ACCEPTED_TEXT):
		_finish()
		return
	if not await _finish_branch("这就对了。待会儿再出剑，记住此刻肩上的轻松。"):
		_finish()
		return
	var accepted_result := _snapshot()
	snapshots["accepted_result"] = accepted_result.duplicate(true)
	check(str(accepted_result.get("phase", "")) == "result", "接受提示后剧情进入结果")
	check(bool(_audit().get("tool", {}).get("used_real_parser", false)), "结束时仍保留 Dialogue Manager 真实解析器证据")
	await _capture("02_accepted_result.png", "接受提示后的剧情结果")
	if not await _click_ui_rect("advance") or not await _wait_snapshot_ready():
		_finish()
		return

	if not await _click_ui_rect("action_train"):
		_finish()
		return
	var trained := _snapshot()
	snapshots["training_result"] = trained.duplicate(true)
	check(str(trained.get("phase", "")) == "result", "修习行动完成并显示结果")
	check(_stat(trained, "energy") == 70 and _stat(trained, "cultivation") == 18, "修习结算为精力70、修为18")
	check(int(trained.get("slot", -1)) == 3, "修习推进两个时辰")
	await _capture("03_training_result.png", "修习后的精力与修为结果")
	if not await _click_ui_rect("advance") or not await _wait_snapshot_ready():
		_finish()
		return

	if not await _click_ui_rect("footer_save"):
		_finish()
		return
	var saved_snapshot := _snapshot().duplicate(true)
	snapshots["saved"] = saved_snapshot.duplicate(true)
	check(_has_checkpoint(), "存档按钮写入本轮独立检查点")
	check(_snapshot() == saved_snapshot, "存档操作不改变当前 Session 快照")
	if not await _click_ui_rect("footer_reset"):
		_finish()
		return
	check(_is_ready_snapshot(_snapshot()), "重置按钮开始新的初始试样")
	if not await _click_ui_rect("footer_load"):
		_finish()
		return
	var restored := _snapshot()
	snapshots["restored"] = restored.duplicate(true)
	check(restored == saved_snapshot, "读档精确恢复完整存档快照")
	check(_stat(restored, "energy") == 70 and _stat(restored, "cultivation") == 18 and int(restored.get("slot", -1)) == 3, "读档恢复修习后的资源与时辰")

	# Reset once more and exercise the no-cost branch.
	if not await _click_ui_rect("footer_reset"):
		_finish()
		return
	if not await _start_talk_and_wait(OPENING_TEXT):
		_finish()
		return
	if not await _reach_question():
		_finish()
		return
	var decline_rect := _choice_rect("return_to_practice")
	check(decline_rect.size.x > 0.0 and decline_rect.size.y > 0.0, "返回修习选项提供真实屏幕命中区域")
	if decline_rect.size.x <= 0.0 or decline_rect.size.y <= 0.0:
		_finish()
		return
	await _click_rect(decline_rect)
	var after_decline := _snapshot()
	snapshots["declined_choice"] = after_decline.duplicate(true)
	check(_stat(after_decline, "energy") == 100 and _stat(after_decline, "cultivation") == 0 and _stat(after_decline, "understanding") == 0, "记下话头不花精力，也不增加属性")
	check(int(after_decline.get("slot", -1)) == 0 and not bool(after_decline.get("flags", {}).get("breathing_hint", false)), "记下话头不推进时辰，也不留下加成")
	if not await _wait_dialogue_text(DECLINED_TEXT):
		_finish()
		return
	if not await _finish_branch("去吧。慢半步，也无妨。"):
		_finish()
		return
	if not await _click_ui_rect("advance") or not await _wait_snapshot_ready():
		_finish()
		return

	check(captures.size() == 4, "报告收录初始、选择、接受结果、修习结果四张截图")
	check(Time.get_ticks_msec() < deadline_msec, "完整GUI旅程在20秒总期限内完成")
	_finish()


func _start_talk_and_wait(expected_text: String) -> bool:
	if not await _click_ui_rect("action_talk"):
		return false
	return await _wait_dialogue_text(expected_text)


func _reach_question() -> bool:
	for text in ["过来坐。你这口气，还留在剑坪上呢。", "我就是想早些练好，免得总让您等。", "剑快一点不难。难的是出剑时，心里不抢那一步。", CHOICE_TEXT]:
		if not await _click_ui_rect("advance") or not await _wait_dialogue_text(text):
			return false
	return true


func _finish_branch(reply: String) -> bool:
	if not await _click_ui_rect("advance") or not await _wait_dialogue_text(reply):
		return false
	return await _click_ui_rect("advance") and await _wait_for_result()


func _wait_dialogue_text(expected: String) -> bool:
	while Time.get_ticks_msec() < deadline_msec:
		var view_audit: Dictionary = _audit().get("view", {})
		if bool(view_audit.get("dialogue", {}).get("visible", false)) and str(view_audit.get("dialogue_text", "")) == expected:
			return true
		await process_frame
	check(false, "等待对白：%s 在20秒期限内完成" % expected)
	return false


func _wait_snapshot_ready() -> bool:
	while Time.get_ticks_msec() < deadline_msec:
		if str(_snapshot().get("phase", "")) == "ready" and not bool(_audit().get("busy", false)):
			return true
		await process_frame
	check(false, "等待返回可行动状态在20秒期限内完成")
	return false


func _wait_for_result() -> bool:
	while Time.get_ticks_msec() < deadline_msec:
		if str(_snapshot().get("phase", "")) == "result" and not bool(_audit().get("busy", false)):
			return true
		await process_frame
	check(false, "等待剧情结果在20秒期限内完成")
	return false


func _click_ui_rect(key: String) -> bool:
	var rect := _ui_rect(key)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		check(false, "审计返回可点击区域：" + key)
		return false
	await _click_rect(rect)
	return _within_deadline("点击 " + key)


func _click_rect(rect: Rect2, click_count: int = 1) -> void:
	var point := root.get_final_transform() * rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	await process_frame
	for unused in range(click_count):
		var down := InputEventMouseButton.new()
		down.position = point
		down.global_position = point
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		root.push_input(down)
		var up := InputEventMouseButton.new()
		up.position = point
		up.global_position = point
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		root.push_input(up)
	await process_frame
	await process_frame


func _click_ui_rect_immediate(key: String) -> void:
	var rect := _ui_rect(key)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		check(false, "审计返回可点击区域：" + key)
		return
	_click_rect_immediate(rect)


func _click_rect_immediate(rect: Rect2) -> void:
	var point := root.get_final_transform() * rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)


func _send_escape_immediate() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)


func _ui_rect(key: String) -> Rect2:
	var view_audit: Dictionary = _audit().get("view", {})
	var rects: Dictionary = view_audit.get("ui_rects", {})
	var value: Variant = rects.get(key, Rect2())
	return value if value is Rect2 else Rect2()


func _choice_rect(choice_id: String) -> Rect2:
	var view_audit: Dictionary = _audit().get("view", {})
	var choices: Array = view_audit.get("choices", [])
	for entry_value in choices:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("id", "")) == choice_id:
			var value: Variant = entry.get("global_rect", Rect2())
			return value if value is Rect2 else Rect2()
	return Rect2()


func _choice_exists(choice_id: String) -> bool:
	return _choice_rect(choice_id).size.x > 0.0 and _choice_rect(choice_id).size.y > 0.0


func _node_disabled(path: String) -> bool:
	var view: Node = app.get("view")
	var candidate: Node = view.get_node_or_null(path) if is_instance_valid(view) else null
	if candidate is BaseButton:
		return (candidate as BaseButton).disabled
	check(false, "找到需要检查禁用状态的按钮：" + path)
	return false


func _audit() -> Dictionary:
	if not is_instance_valid(app):
		return {}
	var value: Variant = app.call("audit")
	return value as Dictionary if value is Dictionary else {}


func _snapshot() -> Dictionary:
	var value: Variant = _audit().get("snapshot", {})
	return value as Dictionary if value is Dictionary else {}


func _stat(snapshot: Dictionary, stat_id: String) -> int:
	return int(snapshot.get("stats", {}).get(stat_id, -1))


func _is_ready_snapshot(snapshot: Dictionary) -> bool:
	return str(snapshot.get("phase", "")) == "ready" and int(snapshot.get("day", -1)) == 1 and int(snapshot.get("slot", -1)) == 0 and _stat(snapshot, "energy") == 100 and _stat(snapshot, "cultivation") == 0 and _stat(snapshot, "understanding") == 0 and not bool(snapshot.get("flags", {}).get("breathing_hint", false))


func _has_checkpoint() -> bool:
	var saves: Variant = app.get("saves")
	var session: Variant = app.get("session")
	return bool(saves.call("has_save", session.get("pack"))) if saves != null and session != null else false


func _capture(filename: String, description: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var full_path: String = _absolute_output_dir().path_join(filename)
	var save_result: Error = image.save_png(full_path)
	check(save_result == OK, "截图写入：" + filename)
	var view_audit: Dictionary = _audit().get("view", {})
	var logical_size: Vector2 = view_audit.get("viewport_size", Vector2.ZERO)
	captures.append({
		"file": filename,
		"description": description,
		"image_pixels": [image.get_width(), image.get_height()],
		"window_size": [root.size.x, root.size.y],
		"viewport_size": [root.get_viewport().get_visible_rect().size.x, root.get_viewport().get_visible_rect().size.y],
		"logical_viewport_size": [logical_size.x, logical_size.y],
		"phase": str(_snapshot().get("phase", "")),
		"busy": bool(_audit().get("busy", false)),
		"dialogue_text": str(view_audit.get("dialogue_text", "")),
	})
	check(image.get_width() == root.size.x and image.get_height() == root.size.y, "截图像素尺寸与实际窗口尺寸一致：" + filename)


func check(condition: bool, message: String) -> void:
	checks += 1
	check_records.append({"ok": condition, "message": message})
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)


func _parse_user_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := str(args[index])
		if argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
		elif argument == "--out" and index + 1 < args.size():
			index += 1
			output_dir = str(args[index])
		elif argument.begins_with("--qa-size="):
			_parse_size(argument.trim_prefix("--qa-size="))
		elif argument == "--qa-size" and index + 1 < args.size():
			index += 1
			_parse_size(str(args[index]))
		index += 1


func _parse_size(value: String) -> void:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		check(false, "--qa-size 使用 WIDTHxHEIGHT 格式")
		return
	qa_size = Vector2i(int(parts[0]), int(parts[1]))
	check(qa_size in [Vector2i(1152, 720), Vector2i(960, 600), Vector2i(1440, 900)], "QA 窗口使用约定尺寸")


func _allocate_store_dir() -> String:
	for attempt in range(20):
		var candidate := "user://dialogue_tools_lab_qa_%d_%d" % [Time.get_ticks_usec(), attempt]
		var absolute := ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func _absolute_output_dir() -> String:
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(output_dir)
	return output_dir


func _within_deadline(label: String) -> bool:
	var ok := Time.get_ticks_msec() < deadline_msec
	if not ok:
		check(false, "%s 在20秒总期限内完成" % label)
	return ok


func _finish() -> void:
	if _finished:
		return
	_finished = true
	# Retire awaited tool/layout work before tearing down the native window.
	if is_instance_valid(app):
		if bool(app.audit().get("busy", false)):
			app._cancel()
		await process_frame
		await process_frame
		app.queue_free()
		await process_frame
		await process_frame
		app = null
	await create_timer(0.15).timeout
	_cleanup_store_dir()
	var adapter := RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else ""
	var report := {
		"test": "dialogue_tools_lab_render",
		"result": "PASS" if failures == 0 else "FAIL",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"check_records": check_records,
		"window_size": [root.size.x, root.size.y],
		"viewport_size": [root.get_viewport().get_visible_rect().size.x, root.get_viewport().get_visible_rect().size.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": adapter,
		"snapshots": snapshots,
		"captures": captures,
	}
	var report_path := _absolute_output_dir().path_join("dialogue-tools-lab-render-report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("无法写入试跑报告：" + report_path)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		file.close()
	print("DIALOGUE_TOOLS_LAB_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)


func _cleanup_store_dir() -> void:
	if isolated_store_dir.is_empty():
		return
	var absolute_root := ProjectSettings.globalize_path(isolated_store_dir)
	var pack_path := absolute_root.path_join("dialogue_tools_sample")
	for slot in range(2):
		for suffix in [".json", ".json.pending"]:
			var candidate := pack_path.path_join("checkpoint_%d%s" % [slot, suffix])
			if FileAccess.file_exists(candidate):
				DirAccess.remove_absolute(candidate)
	if DirAccess.dir_exists_absolute(pack_path):
		DirAccess.remove_absolute(pack_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		DirAccess.remove_absolute(absolute_root)
	check(not DirAccess.dir_exists_absolute(absolute_root), "仅清理本轮独立临时存档目录")
