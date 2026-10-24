extends RefCounted

const DATA_PATH := "res://assets/data/sword_manuals.json"
const DEFAULT_ID := "pine_wind"


static var _catalog_entries: Array = []


static func manuals() -> Array:
	return _entries().duplicate(true)


static func _entries() -> Array:
	if not _catalog_entries.is_empty():
		return _catalog_entries
	var data: Variant = _read_json(DATA_PATH)
	if not data is Dictionary:
		return []
	var entries: Variant = data.get("manuals", [])
	if not entries is Array:
		return []
	_catalog_entries = entries.duplicate(true)
	return _catalog_entries


static func manual(manual_id: String) -> Dictionary:
	for entry: Variant in _entries():
		if entry is Dictionary and str(entry.get("id", "")) == manual_id:
			return entry.duplicate(true)
	return {}


static func technique(manual_id: String, practice_count: int) -> Dictionary:
	var entry := manual(manual_id)
	if entry.is_empty():
		return {}
	var entries: Variant = entry.get("techniques", [])
	if not entries is Array or entries.is_empty():
		return {}
	var index := posmod(practice_count, entries.size())
	var selected: Variant = entries[index]
	if not selected is Dictionary:
		return {}
	return selected.duplicate(true)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
