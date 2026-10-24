extends RefCounted
## Versioned, data-only content boundary. No pack-specific identity or rule branches.

const MotionAssetsScript = preload("res://addons/cultivation_mode/motion_assets.gd")
const QuestRuntimeScript = preload("res://addons/cultivation_mode/quest_runtime.gd")
const WalksContractScript = preload("res://addons/cultivation_mode/walks_contract.gd")

var _errors: Array[String] = []

func load_pack(manifest_path: String) -> Dictionary:
	_errors.clear()
	if not manifest_path.begins_with("res://games/") or ".." in manifest_path or not manifest_path.ends_with("/game.json"):
		return {"ok": false, "errors": ["内容包入口须位于 games 目录。"]}
	var raw: String = _read_json_text(manifest_path)
	var pack: Dictionary = _parse_object(raw, manifest_path)
	var sources: String = raw
	var files: Dictionary = _object(pack.get("files"), "game.files")
	for key: String in ["rules", "characters", "scenes", "actions", "events"]:
		var relative: Variant = files.get(key)
		if not relative is String or relative.get_file() != relative or not relative.ends_with(".json") or ".." in relative:
			_error("game.files." + key, "必须为包内 JSON 文件名")
			pack[key] = {}
			continue
		var path: String = manifest_path.get_base_dir().path_join(relative)
		var text: String = _read_json_text(path)
		sources += "\n" + key + "\n" + text
		pack[key] = _parse_object(text, path)
	for optional: String in ["motions", "quests", "voices", "walks"]:
		pack[optional] = {}
		if not files.has(optional):
			continue
		var relative: Variant = files.get(optional)
		if not relative is String or relative.get_file() != relative or not relative.ends_with(".json") or ".." in relative:
			_error("game.files." + optional, "必须为包内 JSON 文件名")
		else:
			var path: String = manifest_path.get_base_dir().path_join(relative)
			var text: String = _read_json_text(path)
			sources += "\n" + optional + "\n" + text
			pack[optional] = _parse_object(text, path)
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	var issues: Array[String] = validate(pack)
	if not issues.is_empty():
		return {"ok": false, "errors": issues}
	pack["_fingerprint"] = sources.sha256_text()
	pack["_manifest_path"] = manifest_path
	return {"ok": true, "pack": pack, "errors": []}

func validate(pack: Dictionary) -> Array[String]:
	_errors.clear()
	if not _integer(pack.get("schema_version")) or int(pack.get("schema_version", 0)) != 1:
		_error("game.schema_version", "仅支持版本 1")
	_id(pack.get("id"), "game.id", 48)
	for key: String in ["version", "title", "subtitle", "description", "initial_scene"]:
		_string(pack.get(key), "game." + key, key != "description")
	var theme: Dictionary = _object(pack.get("theme"), "game.theme")
	_color(theme.get("accent"), "game.theme.accent")
	_color(theme.get("paper"), "game.theme.paper")
	_flags(pack.get("initial_flags"), "game.initial_flags")
	var rules: Dictionary = _object(pack.get("rules"), "rules")
	var clock: Dictionary = _object(rules.get("clock"), "rules.clock")
	if clock.has("unit"):
		_string(clock.unit, "rules.clock.unit", true)
	var slots: Array = _array(clock.get("slots"), "rules.clock.slots")
	if slots.is_empty() or slots.size() > 24:
		_error("rules.clock.slots", "需要 1–24 个时间段")
	for label: Variant in slots:
		_string(label, "rules.clock.slots[]", true)
	_number(clock.get("start_day"), "rules.clock.start_day", 1, 1000000)
	_number(clock.get("start_slot"), "rules.clock.start_slot", 0, maxi(0, slots.size() - 1))
	var stats: Dictionary = {}
	var stat_list: Array = _array(rules.get("stats"), "rules.stats")
	if stat_list.is_empty() or stat_list.size() > 12:
		_error("rules.stats", "需要 1–12 个属性")
	for value: Variant in stat_list:
		var item: Dictionary = _object(value, "rules.stats[]")
		var sid: String = str(item.get("id", ""))
		_id(item.get("id"), "rules.stats[].id")
		if stats.has(sid):
			_error("rules.stats." + sid, "属性标识重复")
		stats[sid] = item
		_string(item.get("label"), "rules.stats." + sid + ".label", true)
		for key: String in ["min", "max", "initial"]:
			_number(item.get(key), "rules.stats." + sid + "." + key, -1000000, 1000000)
		if _integer(item.get("min")) and _integer(item.get("max")) and _integer(item.get("initial")):
			if item.min > item.initial or item.initial > item.max:
				_error("rules.stats." + sid, "初始值须在上下限之间")
		_color(item.get("color"), "rules.stats." + sid + ".color")
	for value: Variant in _array(rules.get("goals"), "rules.goals"):
		var goal: Dictionary = _object(value, "rules.goals[]")
		_id(goal.get("id"), "goal.id")
		_string(goal.get("label"), "goal.label", true)
		_ref(goal.get("stat"), stats, "goal.stat")
		_number(goal.get("target"), "goal.target", 0, 1000000)
		_id(goal.get("completion_flag"), "goal.completion_flag")
	var characters: Dictionary = _object(pack.get("characters"), "characters")
	for cid: Variant in characters:
		_id(cid, "characters key")
		var character: Dictionary = _object(characters[cid], "characters." + str(cid))
		_string(character.get("name"), "characters." + str(cid) + ".name", true)
		_string(character.get("role"), "characters." + str(cid) + ".role", true)
		_asset(character.get("portrait"), "characters." + str(cid) + ".portrait", true)
	var voices: Dictionary = _object(pack.get("voices", {}), "voices")
	for voice_id: Variant in voices:
		var where: String = "voices." + str(voice_id)
		_id(voice_id, where)
		var voice: Dictionary = _object(voices[voice_id], where)
		_ref(voice.get("speaker"), characters, where + ".speaker")
		_string(voice.get("text"), where + ".text", true)
		var file: Variant = voice.get("file")
		if not file is String or not file.begins_with("res://assets/audio/") or "\\" in file or not file.ends_with(".wav"):
			_error(where + ".file", "需要 assets/audio 内的 WAV 资源")
		else:
			for segment: String in file.trim_prefix("res://assets/audio/").split("/", true):
				if segment in ["", ".", ".."]:
					_error(where + ".file", "需要 assets/audio 内的 WAV 资源")
	var motions: Dictionary = _object(pack.get("motions", {}), "motions")
	var motion_assets: RefCounted = MotionAssetsScript.new()
	for motion_id: Variant in motions:
		var where: String = "motions." + str(motion_id)
		_id(motion_id, where)
		var motion: Dictionary = _object(motions[motion_id], where)
		_ref(motion.get("character"), characters, where + ".character")
		for issue: String in motion_assets.validate_definition(motion):
			_error(where, issue)
	var scenes: Dictionary = _object(pack.get("scenes"), "scenes")
	_ref(pack.get("initial_scene"), scenes, "game.initial_scene")
	if scenes.is_empty():
		_error("scenes", "至少登记一个场景")
	for scene_id: Variant in scenes:
		var where: String = "scenes." + str(scene_id)
		var scene_id_pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
		if not scene_id is String or str(scene_id).length() > 96 or scene_id_pattern.search(str(scene_id)) == null:
			_error(where, "需要有效的场景标识")
		var scene: Dictionary = _object(scenes[scene_id], where)
		_string(scene.get("label"), where + ".label", true)
		_string(scene.get("description"), where + ".description", true)
		_asset(scene.get("background"), where + ".background")
		_color(scene.get("accent"), where + ".accent")
		for layer_value: Variant in _array(scene.get("layers", []), where + ".layers"):
			var layer: Dictionary = _object(layer_value, where + ".layers[]")
			_asset(layer.get("texture"), where + ".layers.texture")
		if scene.has("foreground"):
			var front: Dictionary = _object(scene.foreground, where + ".foreground")
			_asset(front.get("texture"), where + ".foreground.texture")
			for key: String in ["x", "y", "width", "height"]:
				var n: Variant = front.get(key)
				if not (n is int or n is float) or not is_finite(float(n)) or float(n) < 0 or float(n) > 1 or (key in ["width", "height"] and float(n) == 0):
					_error(where + ".foreground." + key, "需要有效的 0–1 画面比例")
		for cid: Variant in _array(scene.get("present"), where + ".present"):
			_ref(cid, characters, where + ".present")
		for value: Variant in _array(scene.get("actors"), where + ".actors"):
			var actor: Dictionary = _object(value, where + ".actors[]")
			_ref(actor.get("character"), characters, where + ".actors.character")
			if actor.has("motion"):
				_ref(actor.motion, motions, where + ".actors.motion")
				var motion_value: Variant = motions.get(actor.get("motion", ""), {})
				if motion_value is Dictionary and motion_value.get("character", "") != actor.get("character", ""):
					_error(where + ".actors.motion", "动作人物与场景人物不一致")
			if actor.has("texture"):
				_asset(actor.texture, where + ".actors.texture")
			if actor.has("region"):
				var region: Array = _array(actor.region, where + ".actors.region")
				if region.size() != 4:
					_error(where + ".actors.region", "需要 x／y／宽／高四个整数")
				else:
					for i: int in range(4):
						_number(region[i], where + ".actors.region", 1 if i > 1 else 0, 16384)
					var actor_character: Variant = characters.get(actor.get("character", ""), {})
					var default_portrait: String = str(actor_character.get("portrait", "")) if actor_character is Dictionary else ""
					var texture_path: Variant = actor.get("texture", default_portrait)
					if texture_path is String and ResourceLoader.exists(texture_path, "Texture2D") and region.all(func(n: Variant) -> bool: return _integer(n)):
						var texture: Texture2D = load(texture_path) as Texture2D
						if texture != null and (region[0] + region[2] > texture.get_width() or region[1] + region[3] > texture.get_height()):
							_error(where + ".actors.region", "图集区域超出图片")
			for key: String in ["x", "y", "height"]:
				var n: Variant = actor.get(key)
				if not (n is int or n is float) or not is_finite(float(n)) or float(n) < 0 or float(n) > 1:
					_error(where + ".actors." + key, "需要 0–1 的坐标")
			if not actor.get("flip") is bool:
				_error(where + ".actors.flip", "需要布尔值")
	var actions: Dictionary = _object(pack.get("actions"), "actions")
	var events: Dictionary = _object(pack.get("events"), "events")
	for action_id: Variant in actions:
		var where: String = "actions." + str(action_id)
		_id(action_id, where)
		var action: Dictionary = _object(actions[action_id], where)
		for key: String in ["label", "description", "result"]:
			_string(action.get(key), where + "." + key, true)
		if not action.get("menu") is bool:
			_error(where + ".menu", "需要布尔值")
		if action.has("show_count") and not action.show_count is bool:
			_error(where + ".show_count", "需要布尔值")
		var locations: Array = _array(action.get("scenes"), where + ".scenes")
		if locations.is_empty():
			_error(where + ".scenes", "需要可用场景")
		for sid: Variant in locations:
			_ref(sid, scenes, where + ".scenes")
		_number(action.get("duration"), where + ".duration", 0, 100)
		_deltas(action.get("costs"), stats, where + ".costs")
		_deltas(action.get("gains"), stats, where + ".gains")
		_conditions(action.get("conditions"), stats, where + ".conditions")
		_flags(action.get("set_flags"), where + ".set_flags")
		_string(action.get("once_key"), where + ".once_key")
		if action.get("once_key", "") != "":
			_id(action.get("once_key"), where + ".once_key")
		for value: Variant in _array(action.get("bonuses"), where + ".bonuses"):
			var bonus: Dictionary = _object(value, where + ".bonuses[]")
			_id(bonus.get("flag"), where + ".bonus.flag")
			_deltas(bonus.get("gains"), stats, where + ".bonus.gains")
			if not bonus.get("consume") is bool:
				_error(where + ".bonus.consume", "需要布尔值")
		for key: String in ["event", "target_scene", "character"]:
			_string(action.get(key, ""), where + "." + key)
		_ref(action.get("event", ""), events, where + ".event", true)
		_ref(action.get("target_scene", ""), scenes, where + ".target_scene", true)
		_ref(action.get("character", ""), characters, where + ".character", true)
		if action.get("menu") is bool and action.menu == false and action.get("event", "") != "":
			_error(where + ".event", "选择效果不能再打开另一个事件")
		if action.has("presentation"):
			var presentation: Dictionary = _object(action.presentation, where + ".presentation")
			_ref(presentation.get("motion"), motions, where + ".presentation.motion")
			var motion: Dictionary = motions.get(presentation.get("motion", ""), {}) if presentation.get("motion", "") is String else {}
			var clips: Dictionary = motion.get("clips", {}) if motion.get("clips", {}) is Dictionary else {}
			_ref(presentation.get("clip"), clips, where + ".presentation.clip")
			if action.get("menu", false) != true or action.get("event", "") != "" or action.get("target_scene", "") != "":
				_error(where + ".presentation", "动画行动须为不切场景／不开对话的菜单行动")
			for scene_id: Variant in locations:
				var scene_value: Variant = scenes.get(scene_id, {}) if scene_id is String else {}
				var matching: bool = false
				if scene_value is Dictionary and scene_value.get("actors", []) is Array:
					for actor_value: Variant in scene_value.get("actors", []):
						if actor_value is Dictionary and actor_value.get("motion", "") == presentation.get("motion", "") and actor_value.get("character", "") == motion.get("character", ""):
							matching = true
				if not matching:
					_error(where + ".presentation", "行动场景未放置对应动作人物")
	for eid: Variant in events:
		_validate_event(str(eid), events[eid], characters, actions, stats, voices, QuestRuntimeScript.new().known_flags(pack))
	for issue: String in QuestRuntimeScript.new().validate(pack):
		_error("game", issue)
	for issue: String in WalksContractScript.new().validate(pack):
		_error("game", issue)
	return _errors.duplicate()

func _validate_event(eid: String, value: Variant, characters: Dictionary, actions: Dictionary, stats: Dictionary, voices: Dictionary = {}, reserved_flags: Dictionary = {}) -> void:
	var where: String = "events." + eid
	_id(eid, where)
	var event: Dictionary = _object(value, where)
	_string(event.get("title"), where + ".title", true)
	var nodes: Dictionary = _object(event.get("nodes"), where + ".nodes")
	_ref(event.get("start"), nodes, where + ".start")
	if nodes.is_empty() or nodes.size() > 256:
		_error(where, "需要 1–256 个节点")
	var edges: Dictionary = {}
	var endings: Array[String] = []
	for nid: Variant in nodes:
		_id(nid, where + ".nodes key")
		var here: String = where + ".nodes." + str(nid)
		var node: Dictionary = _object(nodes[nid], here)
		_string(node.get("text"), here + ".text", true)
		if node.has("voice"):
			_ref(node.voice, voices, here + ".voice")
			if node.get("type", "") not in ["say", "choice"]:
				_error(here + ".voice", "仅人物对白可绑定配音")
			var clip: Dictionary = voices.get(node.voice, {}) if node.voice is String and voices.get(node.voice, {}) is Dictionary else {}
			if not clip.is_empty() and (clip.get("speaker") != node.get("speaker") or clip.get("text") != node.get("text")):
				_error(here + ".voice", "配音人物与原文须逐字对应")
		if node.has("set_flags"):
			_flags(node.set_flags, here + ".set_flags")
			if node.get("type", "") != "end":
				_error(here + ".set_flags", "仅结束节点可提交剧情进度")
			if node.set_flags is Dictionary:
				for flag: Variant in node.set_flags:
					if reserved_flags.has(flag):
						_error(here + ".set_flags", "不能改写支线或调查保留旗标")
		edges[nid] = []
		match node.get("type"):
			"end":
				endings.append(str(nid))
			"say":
				_ref(node.get("speaker"), characters, here + ".speaker")
				_ref(node.get("next"), nodes, here + ".next")
				if node.get("next") is String:
					edges[nid].append(node.next)
			"choice":
				_ref(node.get("speaker"), characters, here + ".speaker")
				var ids: Dictionary = {}
				var escape: bool = false
				var options: Array = _array(node.get("options"), here + ".options")
				if options.is_empty() or options.size() > 8:
					_error(here, "需要 1–8 个选项")
				for v: Variant in options:
					var option: Dictionary = _object(v, here + ".options[]")
					_id(option.get("id"), here + ".option.id")
					if ids.has(str(option.get("id", ""))):
						_error(here, "选项标识重复")
					ids[str(option.get("id", ""))] = true
					_string(option.get("label"), here + ".option.label", true)
					_ref(option.get("next"), nodes, here + ".option.next")
					if option.get("next") is String:
						edges[nid].append(option.next)
					_ref(option.get("action", ""), actions, here + ".option.action", true)
					if actions.has(option.get("action", "")) and actions[option.action] is Dictionary and actions[option.action].get("menu", true) == true:
						_error(here, "剧情选择须引用非菜单效果")
					_conditions(option.get("conditions"), stats, here + ".option.conditions")
					var conditions: Variant = option.get("conditions", {})
					if option.get("action", "") == "" and conditions is Dictionary and conditions.get("stats_gte", {}) is Dictionary and conditions.get("flags", {}) is Dictionary and conditions.get("stats_gte", {}).is_empty() and conditions.get("flags", {}).is_empty():
						escape = true
				if not escape:
					_error(here, "需要无条件且无代价的离开选项")
			_:
				_error(here + ".type", "仅支持 say／choice／end")
	if endings.is_empty():
		_error(where, "缺少结束节点")
	var visited: Dictionary = {}
	var active: Dictionary = {}
	_walk(str(event.get("start", "")), edges, visited, active, where)
	for nid: Variant in nodes:
		if not visited.has(nid):
			_error(where + ".nodes." + str(nid), "节点无法从入口到达")

func _walk(node: String, edges: Dictionary, visited: Dictionary, active: Dictionary, where: String) -> void:
	if active.has(node):
		_error(where + ".nodes." + node, "v0.1 不支持循环事件图")
		return
	if visited.has(node) or not edges.has(node):
		return
	visited[node] = true
	active[node] = true
	for next: Variant in edges[node]:
		_walk(str(next), edges, visited, active, where)
	active.erase(node)

func _conditions(value: Variant, stats: Dictionary, where: String) -> void:
	var data: Dictionary = _object(value, where)
	for key: Variant in data:
		if key not in ["stats_gte", "flags"]:
			_error(where + "." + str(key), "未知条件类型")
	_deltas(data.get("stats_gte", {}), stats, where + ".stats_gte")
	_flags(data.get("flags", {}), where + ".flags")

func _deltas(value: Variant, stats: Dictionary, where: String) -> void:
	var data: Dictionary = _object(value, where)
	for sid: Variant in data:
		_ref(sid, stats, where)
		_number(data[sid], where + "." + str(sid), 0, 1000000)

func _flags(value: Variant, where: String) -> void:
	var data: Dictionary = _object(value, where)
	for key: Variant in data:
		_id(key, where)
		if not data[key] is bool:
			_error(where + "." + str(key), "需要布尔值")

func _asset(value: Variant, where: String, optional: bool = false) -> void:
	if optional and value is String and value == "":
		return
	if not value is String or not value.begins_with("res://assets/") or ".." in value or value.get_extension().to_lower() not in ["png", "jpg", "webp"]:
		_error(where, "需要 assets 内的图像资源")
	elif not ResourceLoader.exists(value, "Texture2D"):
		_error(where, "找不到图像资源 " + value)

func _object(value: Variant, where: String) -> Dictionary:
	if value is Dictionary:
		return value
	_error(where, "需要对象")
	return {}

func _array(value: Variant, where: String) -> Array:
	if value is Array:
		return value
	_error(where, "需要列表")
	return []

func _string(value: Variant, where: String, nonempty: bool = false) -> void:
	if not value is String or (nonempty and value.strip_edges().is_empty()):
		_error(where, "需要" + ("非空" if nonempty else "") + "文字")

func _id(value: Variant, where: String, max_length: int = 64) -> void:
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-z][a-z0-9_]{0," + str(max_length - 1) + "}$")
	if not value is String or regex.search(value) == null:
		_error(where, "标识仅使用小写字母、数字与下划线")

func _ref(value: Variant, registry: Dictionary, where: String, optional: bool = false) -> void:
	if optional and value is String and value == "":
		return
	if not value is String or not registry.has(value):
		_error(where, "未知标识 " + str(value))

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value)

func _number(value: Variant, where: String, minimum: int, maximum: int) -> void:
	if not _integer(value) or float(value) < minimum or float(value) > maximum:
		_error(where, "整数须在 " + str(minimum) + "–" + str(maximum) + " 之间")

func _color(value: Variant, where: String) -> void:
	if not value is String or not Color.html_is_valid(value):
		_error(where, "需要有效颜色")

func _read_json_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		_error(path, "文件缺失")
		return "{}"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		_error(path, "无法读取或文件超过 1 MiB")
		return "{}"
	return file.get_as_text()

func _parse_object(text: String, path: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		_error(path, "JSON 格式错误，行 " + str(parser.get_error_line()))
		return {}
	return parser.data

func _error(where: String, message: String) -> void:
	_errors.append(where + "：" + message)
