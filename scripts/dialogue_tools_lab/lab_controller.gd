extends Control
## Isolated tool trial. The existing Session remains the sole gameplay authority.

const View = preload("res://scripts/dialogue_tools_lab/lab_view.gd")
const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const Session = preload("res://addons/cultivation_mode/session.gd")
const Saves = preload("res://addons/cultivation_mode/save_store.gd")
const DMDriver = preload("res://scripts/dialogue_tools_lab/dm_driver.gd")
const DialogicDriver = preload("res://scripts/dialogue_tools_lab/dialogic_driver.gd")
const VoicePlayer = preload("res://scripts/dialogue_tools_lab/voice_player.gd")
const VOICE_MANIFEST := "res://assets/audio/mentor_pause/manifest.json"

var view: Control
var session = Session.new()
var saves = Saves.new()
var backend := "dm"
var driver: Node
var busy := false
var trial_token := 0
var current_choice_operation := ""
var current_choice_id := ""
var failure := ""
var before_talk: Dictionary = {}
var last_tool_audit: Dictionary = {}
var voice: Node
var voice_warning := ""
var _last_voice_line := ""


func _ready() -> void:
	view = View.new()
	add_child(view)
	view.backend_requested.connect(_select_backend)
	view.action_requested.connect(_action)
	view.advance_requested.connect(_advance)
	view.choice_requested.connect(_choice)
	view.cancel_requested.connect(_cancel)
	voice = VoicePlayer.new()
	add_child(voice)
	var voice_ready: Dictionary = voice.configure_manifest(VOICE_MANIFEST)
	if not voice_ready.ok:
		voice_warning = "配音暂不可用，仍可阅读对白。"
		voice.set_enabled(false)
	view.set_voice_enabled(voice.is_voice_enabled())
	var loaded: Dictionary = Loader.new().load_pack("res://games/dialogue_tools_sample/game.json")
	if not loaded.ok:
		_fail(str(loaded.errors))
		return
	session.configure(loaded.pack)
	_set_save_folder()
	view.hide_dialogue()
	_sync()


func _set_save_folder() -> void:
	saves.base_dir = "user://mentor_voice_sample/" + backend


func _select_backend(id: String) -> void:
	if busy or not id in ["dm", "dialogic"] or id == backend:
		return
	_stop_driver()
	backend = id
	session.start_new()
	_set_save_folder()
	failure = ""
	view.hide_dialogue()
	view.show_notice("已切换，双方从相同的初始状态开始。")
	_sync()


func _action(id: String) -> void:
	if id == "voice_toggle":
		voice.set_enabled(not voice.is_voice_enabled())
		view.set_voice_enabled(voice.is_voice_enabled())
		return
	if busy:
		return
	if id == "talk":
		if session.snapshot().phase == "result":
			session.acknowledge_result()
		_start_talk()
		return
	if id in ["train", "rest"]:
		if session.snapshot().phase == "result":
			session.acknowledge_result()
		var result: Dictionary = session.select_action("train_mountain" if id == "train" else "rest_practice")
		if result.ok:
			_present_result()
		else:
			view.show_notice(str(result.get("reason", "行动暂不可用")))
	elif id == "save":
		var result: Dictionary = saves.save_session(session)
		view.show_notice(str(result.get("message", result.get("reason", ""))))
	elif id == "load":
		var result: Dictionary = saves.load_session(session)
		if result.ok:
			if session.snapshot().phase == "result":
				_present_result()
			else:
				view.hide_dialogue()
		view.show_notice(str(result.get("message", result.get("reason", ""))))
	elif id == "reset":
		_stop_driver()
		session.start_new()
		failure = ""
		view.hide_dialogue()
		view.show_notice("已重置本次试样，原存档仍可读取。")
	_sync()


func _start_talk() -> void:
	_last_voice_line = ""
	before_talk = session.snapshot()
	var result: Dictionary = session.select_action("talk_mentor")
	if not result.ok:
		view.show_notice(str(result.get("reason", "暂时无法请教")))
		_sync()
		return
	trial_token += 1
	current_choice_operation = str(session.snapshot().run_id) + ":tool_trial:" + str(trial_token)
	current_choice_id = ""
	busy = true
	failure = ""
	view.hide_dialogue()
	driver = DMDriver.new() if backend == "dm" else DialogicDriver.new()
	add_child(driver)
	driver.line_ready.connect(_on_tool_line.bind(trial_token))
	driver.ended.connect(_on_tool_ended.bind(trial_token))
	driver.failed.connect(_on_tool_failed.bind(trial_token))
	_sync()
	driver.begin(self)


func can_take_lesson() -> bool:
	if not busy:
		return false
	# A tool may prepare response buttons before it emits the next line signal.
	# Read the same declared conditions, without changing the Session pointer.
	var option: Dictionary = session.pack.events.mentor_tip.nodes.choice.options[0]
	var snap: Dictionary = session.snapshot()
	for stat: String in option.conditions.get("stats_gte", {}):
		if int(snap.stats.get(stat, 0)) < int(option.conditions.stats_gte[stat]):
			return false
	return current_choice_id.is_empty()


func apply_choice(option_id: String) -> bool:
	if not busy or not option_id in ["take_lesson", "return_to_practice"]:
		return false
	if not current_choice_id.is_empty():
		return false
	var event: Dictionary = session.event_view()
	if event.get("node_id", "") != "choice":
		return false
	var result: Dictionary = session.choose(option_id, current_choice_operation)
	if not result.ok:
		view.show_notice(str(result.get("reason", "选择暂不可用")))
		return false
	current_choice_id = option_id
	_sync()
	return true


func _on_tool_line(speaker: String, text: String, choices: Array, token: int) -> void:
	if token != trial_token or not busy:
		return
	var event: Dictionary = session.event_view()
	# Both tools consume the exact same trusted fixture. Advance only an existing
	# Session say node when the next tool line is the corresponding existing node.
	if event.get("text", "") != text and event.get("type", "") == "say":
		var next_id: String = str(event.get("next", ""))
		var expected: Dictionary = session.pack.events.mentor_tip.nodes.get(next_id, {})
		if expected.get("text", "") == text:
			var snap: Dictionary = session.snapshot()
			session.continue_event(str(snap.run_id), int(snap.revision))
			event = session.event_view()
	if event.get("text", "") != text or event.get("speaker_name", "") != speaker:
		_fail("工具对白与养成事件不同步，请重置试样。")
		return
	if backend == "dm":
		view.show_dialogue(speaker, text, choices, choices.is_empty())
	var line_key := speaker + "\u001f" + text
	if line_key != _last_voice_line:
		_last_voice_line = line_key
		var spoken: Dictionary = voice.play_line(speaker, text)
		if not spoken.ok and voice.is_voice_enabled():
			voice_warning = str(spoken.get("reason", "此句配音暂不可用。"))
		elif spoken.ok:
			voice_warning = ""
	_sync()


func _choice(id: String) -> void:
	if busy and is_instance_valid(driver):
		voice.stop("choice")
		driver.advance_choice(id)


func _advance() -> void:
	if busy and is_instance_valid(driver):
		voice.stop("advance")
		driver.advance()
	elif session.snapshot().get("phase", "") == "result":
		session.acknowledge_result()
		view.hide_dialogue()
		_sync()


func _on_tool_ended(token: int) -> void:
	if token != trial_token or not busy:
		return
	if current_choice_id.is_empty():
		_fail("工具在完成选择前结束，请重新试样。")
		return
	for unused in range(2):
		var snap: Dictionary = session.snapshot()
		if snap.phase != "event":
			break
		var result: Dictionary = session.continue_event(str(snap.run_id), int(snap.revision))
		if not result.ok:
			_fail(str(result.get("reason", "剧情未能结束")))
			return
	busy = false
	if is_instance_valid(driver):
		last_tool_audit = driver.audit()
	_stop_driver()
	_present_result()
	_sync()


func _on_tool_failed(message: String, token: int) -> void:
	if token == trial_token:
		_fail(message)


func _cancel() -> void:
	if busy:
		_stop_driver()
		busy = false
		if session.snapshot().phase == "event":
			session.cancel_event()
		view.hide_dialogue()
		view.show_notice("已收起交谈；已经发生的选择仍保留。")
	elif session.snapshot().phase == "result":
		session.acknowledge_result()
		view.hide_dialogue()
	_sync()


func _stop_driver() -> void:
	if is_instance_valid(voice):
		voice.stop("dialogue_stopped")
	_last_voice_line = ""
	trial_token += 1
	var retired: Node = driver
	driver = null
	if is_instance_valid(retired):
		_retire_driver(retired)


func _retire_driver(retired: Node) -> void:
	await retired.stop()
	if is_instance_valid(retired):
		retired.queue_free()


func _present_result() -> void:
	voice.stop("result")
	var result: Dictionary = session.snapshot().get("last_result", {})
	var text: String = str(result.get("message", "本次行动已完成。"))
	var deltas: Dictionary = result.get("delta", {}).get("stats", {})
	var parts: PackedStringArray = []
	for stat: String in ["energy", "cultivation", "understanding"]:
		var delta: int = int(deltas.get(stat, 0))
		if delta != 0:
			var names := {"energy": "精力", "cultivation": "修为", "understanding": "理解"}
			parts.append(str(names[stat]) + " " + ("+" if delta > 0 else "") + str(delta))
	if not parts.is_empty():
		text += "\n" + " · ".join(parts)
	view.show_result(text)


func _sync() -> void:
	if not is_instance_valid(view) or session.state.is_empty():
		return
	var snap: Dictionary = session.snapshot()
	var slots: Array = session.pack.rules.clock.slots
	view.set_status({"backend_label": "Dialogue Manager" if backend == "dm" else "Dialogic",
		"day_label": "第" + str(snap.day) + "日 · " + str(slots[int(snap.slot)]),
		"energy": snap.stats.energy, "cultivation": snap.stats.cultivation,
		"hint": "先听师父点拨，再修习。配音可随时开关。",
		"lesson_claimed": bool(snap.flags.get("breathing_hint", false)), "busy": busy,
		"save_enabled": not busy and session.can_save(), "load_enabled": not busy})


func _fail(message: String) -> void:
	failure = message
	_stop_driver()
	busy = false
	if not session.state.is_empty() and session.snapshot().phase == "event":
		session.cancel_event()
	if is_instance_valid(view):
		view.hide_dialogue()
		view.show_notice(message)
	_sync()
	push_error(message)


func audit() -> Dictionary:
	return {"backend": backend, "busy": busy, "failure": failure,
		"snapshot": session.snapshot(), "event": session.event_view(),
		"view": view.audit(), "tool": driver.audit() if is_instance_valid(driver) else last_tool_audit,
		"voice": voice.audit() if is_instance_valid(voice) else {}, "voice_warning": voice_warning}


func _exit_tree() -> void:
	if is_instance_valid(voice):
		voice.stop("scene_exit")
