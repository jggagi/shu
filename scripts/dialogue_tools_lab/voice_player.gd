extends Node
## Local, manifest-backed voice playback for the dialogue tools lab.

const CLIP_PREFIX := "res://assets/audio/mentor_pause/"

var _player: AudioStreamPlayer
var _clips: Dictionary = {}
var _enabled := true
var _current_id := ""
var _stop_reason := ""
var _play_count := 0


func _ready() -> void:
	_ensure_player()


func configure_manifest(path: String) -> Dictionary:
	stop("manifest_reconfigured")
	_clips.clear()
	_ensure_player()

	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("manifest not found: %s" % path)
		return {"ok": false, "errors": errors}

	var parser := JSON.new()
	var parse_result := parser.parse(FileAccess.get_file_as_string(path))
	if parse_result != OK:
		errors.append("invalid manifest JSON: %s" % parser.get_error_message())
		return {"ok": false, "errors": errors}

	var manifest: Variant = parser.data
	if not manifest is Dictionary:
		errors.append("manifest root must be an object")
		return {"ok": false, "errors": errors}
	var schema_version: Variant = manifest.get("schema_version")
	if not (schema_version is int or schema_version is float) or float(schema_version) != 1.0:
		errors.append("schema_version must be 1")
	var raw_clips: Variant = manifest.get("clips")
	if not raw_clips is Array:
		errors.append("clips must be an array")
		return {"ok": false, "errors": errors}
	if (raw_clips as Array).is_empty():
		errors.append("clips must not be empty")

	var ids: Dictionary = {}
	var lines: Dictionary = {}
	var valid_entries: Array[Dictionary] = []
	for index in range((raw_clips as Array).size()):
		var raw_entry: Variant = (raw_clips as Array)[index]
		if not raw_entry is Dictionary:
			errors.append("clips[%d] must be an object" % index)
			continue
		var entry := raw_entry as Dictionary
		var raw_id: Variant = entry.get("id")
		var raw_speaker: Variant = entry.get("speaker")
		var raw_text: Variant = entry.get("text")
		var raw_file: Variant = entry.get("file")
		var raw_sha256: Variant = entry.get("sha256")
		var clip_id := str(raw_id) if raw_id is String else ""
		var speaker := str(raw_speaker) if raw_speaker is String else ""
		var spoken_text := str(raw_text) if raw_text is String else ""
		var file_path := str(raw_file) if raw_file is String else ""
		var entry_valid := true
		if not raw_id is String or clip_id.strip_edges().is_empty():
			errors.append("clips[%d].id must be a non-empty string" % index)
			entry_valid = false
		elif ids.has(clip_id):
			errors.append("duplicate clip id: %s" % clip_id)
			entry_valid = false
		else:
			ids[clip_id] = true
		if not raw_speaker is String or speaker.strip_edges().is_empty():
			errors.append("clips[%d].speaker must be a non-empty string" % index)
			entry_valid = false
		if not raw_text is String or spoken_text.strip_edges().is_empty():
			errors.append("clips[%d].text must be a non-empty string" % index)
			entry_valid = false
		if not raw_sha256 is String:
			errors.append("clips[%d].sha256 must be a string" % index)
			entry_valid = false
		if not speaker.is_empty() and not spoken_text.is_empty():
			var line_key := JSON.stringify([speaker, spoken_text])
			if lines.has(line_key):
				errors.append("duplicate speaker/text pair in clips[%d]" % index)
				entry_valid = false
			else:
				lines[line_key] = true
		var file_name := file_path.substr(CLIP_PREFIX.length()) if file_path.begins_with(CLIP_PREFIX) else ""
		if not raw_file is String or file_name.is_empty() or file_name.contains("/") or file_name.contains("\\") or not file_path.ends_with(".wav"):
			errors.append("clips[%d].file must be a mentor_pause WAV resource" % index)
			entry_valid = false
		if entry_valid:
			valid_entries.append({
				"id": clip_id,
				"speaker": speaker,
				"text": spoken_text,
				"file": file_path,
			})

	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var loaded_clips: Dictionary = {}
	for entry in valid_entries:
		var file_path := str(entry.get("file", ""))
		if not ResourceLoader.exists(file_path):
			errors.append("audio resource unavailable for clip %s: %s" % [str(entry.get("id", "")), file_path])
			continue
		var loaded: Resource = ResourceLoader.load(file_path)
		if not loaded is AudioStream:
			errors.append("audio resource unavailable for clip %s: %s" % [str(entry.get("id", "")), file_path])
			continue
		var stream := loaded as AudioStream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		loaded_clips[_line_key(str(entry.get("speaker", "")), str(entry.get("text", "")))] = {
			"id": str(entry.get("id", "")),
			"stream": stream,
		}

	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_clips = loaded_clips
	return {"ok": true, "errors": []}


func play_line(speaker: String, text: String) -> Dictionary:
	if not _enabled:
		stop("disabled")
		return {"ok": false, "reason": "disabled"}
	stop("replaced")
	var clip: Dictionary = _clips.get(_line_key(speaker, text), {})
	if clip.is_empty():
		_stop_reason = "clip_not_found"
		return {"ok": false, "reason": _stop_reason}
	_ensure_player()
	var stream := clip.get("stream") as AudioStream
	if stream == null:
		_stop_reason = "audio_unavailable"
		return {"ok": false, "reason": _stop_reason}
	_player.stream = stream
	_current_id = str(clip.get("id", ""))
	_player.play()
	_play_count += 1
	_stop_reason = ""
	return {"ok": true, "reason": ""}


func stop(reason: String = "") -> void:
	if is_instance_valid(_player) and _player.playing:
		_player.stop()
	_current_id = ""
	_stop_reason = reason


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		stop("disabled")


func is_voice_enabled() -> bool:
	return _enabled


func audit() -> Dictionary:
	return {
		"enabled": _enabled,
		"playing": is_instance_valid(_player) and _player.playing,
		"current_id": _current_id,
		"stop_reason": _stop_reason,
		"play_count": _play_count,
	}


func _ensure_player() -> void:
	if is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "MentorVoicePlayer"
	add_child(_player)
	_player.finished.connect(_on_player_finished)


func _on_player_finished() -> void:
	_current_id = ""
	_stop_reason = "finished"


func _line_key(speaker: String, text: String) -> String:
	return JSON.stringify([speaker, text])
