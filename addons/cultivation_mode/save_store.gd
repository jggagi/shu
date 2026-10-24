extends RefCounted
## Two rotating local checkpoints. The newest valid file survives a failed write.

var base_dir: String = "user://cultivation_engine_v01"
const FORMAT: int = 1
const MAX_BYTES: int = 4194304

func save_session(session: RefCounted) -> Dictionary:
	if not session.can_save():
		return _fail("请先结束当前对话，再保存。")
	var pack: Dictionary = session.pack
	if not _safe_identity(pack):
		return _fail("内容包标识或版本不完整。")
	var folder: String = base_dir.path_join(pack.id)
	var err: Error = DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		return _fail("无法建立存档目录（" + str(err) + "）。")
	var current: Array[Dictionary] = _scan(pack)
	var generation: int = 1
	for item: Dictionary in current:
		if item.ok:
			generation = maxi(generation, int(item.generation) + 1)
	var index: int = 0
	if current[0].ok and (not current[1].ok or int(current[0].generation) > int(current[1].generation)):
		index = 1
	var payload: Dictionary = {
		"game_id": pack.id,
		"content_version": pack.version,
		"content_fingerprint": pack._fingerprint,
		"state": session.snapshot(),
	}
	var text: String = JSON.stringify(payload, "", true, true)
	var envelope: Dictionary = {"format": FORMAT, "generation": generation, "payload_json": text, "checksum": text.sha256_text()}
	var bytes: String = JSON.stringify(envelope, "", true, true)
	if bytes.to_utf8_buffer().size() > MAX_BYTES:
		return _fail("存档超过当前版本的容量限制；原存档保留。")
	var target: String = _slot_path(pack, index)
	var pending: String = target + ".pending"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return _fail("存档无法写入；原存档保留。")
	file.store_string(bytes)
	file.flush()
	var written: bool = file.get_error() == OK and file.get_position() == bytes.to_utf8_buffer().size()
	file.close()
	if not written:
		return _fail("写入未完成；原存档保留。")
	var checked: Dictionary = _read(pending)
	if not checked.ok or checked.generation != generation or not _matches(checked, pack):
		return _fail("新存档读回校验失败；原存档保留。")
	# Only the older slot is replaced. The other, newest checkpoint remains valid.
	if FileAccess.file_exists(target):
		err = DirAccess.remove_absolute(target)
		if err != OK:
			return _fail("旧轮换槽无法替换；最近的存档保留。")
	err = DirAccess.rename_absolute(pending, target)
	if err != OK:
		return _fail("存档发布失败；最近的存档保留。")
	var final: Dictionary = _read(target)
	if not final.ok or final.generation != generation:
		return _fail("存档发布校验失败；可尝试恢复前一存档。")
	return {"ok": true, "generation": generation, "message": "已保存至本机 · 第 " + str(generation) + " 次存档", "persistent": OS.is_userfs_persistent()}

func load_session(session: RefCounted) -> Dictionary:
	var pack: Dictionary = session.pack
	if not _safe_identity(pack):
		return _fail("内容包标识或版本不完整。")
	var candidates: Array[Dictionary] = _scan(pack)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("generation", -1)) > int(b.get("generation", -1)))
	var had_problem: bool = false
	var problem: String = "还没有这个内容包的本机存档。"
	for item: Dictionary in candidates:
		if not item.ok:
			if item.get("exists", false):
				had_problem = true
				problem = "存档损坏或读取失败。"
			continue
		if not _matches(item, pack):
			had_problem = true
			problem = "存档与当前内容版本不兼容，请新开一局。"
			continue
		var result: Dictionary = session.restore(item.payload.state)
		if not result.ok:
			had_problem = true
			problem = "存档状态无效：" + str(result.get("reason", "未知原因"))
			continue
		# A corrupt file can have no readable generation, so check both slots for recovery notice.
		for other: Dictionary in candidates:
			if other.get("exists", false) and not other.ok:
				had_problem = true
		var message: String = "已读取本机存档 · 第 " + str(item.generation) + " 次"
		if had_problem:
			message += "（另一槽不可用，已恢复有效副本）"
		return {"ok": true, "generation": item.generation, "recovered": had_problem, "message": message}
	return _fail(problem)

func has_save(pack: Dictionary) -> bool:
	return bool(describe(pack).get("available", false))

func describe(pack: Dictionary) -> Dictionary:
	if not _safe_identity(pack):
		return {"available": false, "message": "内容包标识无效"}
	var newest: int = 0
	var exists: bool = false
	for item: Dictionary in _scan(pack):
		exists = exists or bool(item.get("exists", false))
		if item.ok and _matches(item, pack):
			newest = maxi(newest, int(item.generation))
	return {"available": newest > 0, "generation": newest, "message": ("已有本机存档" if newest > 0 else ("存档不兼容或已损坏" if exists else "尚无本机存档"))}

func _scan(pack: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for index: int in range(2):
		results.append(_read(_slot_path(pack, index)))
	return results

func _slot_path(pack: Dictionary, index: int) -> String:
	return base_dir.path_join(str(pack.id)).path_join("checkpoint_" + str(index) + ".json")

func _read(path: String) -> Dictionary:
	var bad: Dictionary = {"ok": false, "exists": FileAccess.file_exists(path), "generation": -1}
	if not bad.exists:
		return bad
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return bad
	var raw: String = file.get_as_text()
	var parsed: JSON = JSON.new()
	if parsed.parse(raw) != OK or not parsed.data is Dictionary:
		return bad
	var data: Dictionary = parsed.data
	if not _integer(data.get("format")) or int(data.format) != FORMAT or not _integer(data.get("generation")) or data.generation < 1:
		return bad
	if not data.get("payload_json") is String or not data.get("checksum") is String:
		return bad
	if data.payload_json.sha256_text() != data.checksum:
		return bad
	var payload_json: JSON = JSON.new()
	if payload_json.parse(data.payload_json) != OK or not payload_json.data is Dictionary:
		return bad
	var payload: Dictionary = payload_json.data
	for key: String in ["game_id", "content_version", "content_fingerprint"]:
		if not payload.get(key) is String:
			return bad
	if not payload.get("state") is Dictionary:
		return bad
	return {"ok": true, "exists": true, "generation": int(data.generation), "payload": payload}

func _matches(item: Dictionary, pack: Dictionary) -> bool:
	return item.payload.game_id == pack.id and item.payload.content_version == pack.version and item.payload.content_fingerprint == pack._fingerprint

func _safe_identity(pack: Dictionary) -> bool:
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-z][a-z0-9_]{0,47}$")
	return pack.get("id") is String and regex.search(pack.id) != null and pack.get("version") is String and pack.get("_fingerprint") is String

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value)

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": reason}
