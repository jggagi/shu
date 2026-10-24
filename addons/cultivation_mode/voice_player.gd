extends Node
## Local WAV playback for content-pack dialogue voice clips.

const AUDIO_ROOT := "res://assets/audio/"

var _player: AudioStreamPlayer
var _clips: Dictionary = {}
var _enabled := true
var _current_id := ""
var _stop_reason := ""
var _play_count := 0


func _ready() -> void:
	_ensure_player()


func configure(clips: Dictionary) -> Dictionary:
	stop("reconfigured")
	_clips.clear()
	_ensure_player()

	var errors: Array[String] = []
	for raw_id: Variant in clips:
		if not raw_id is String or str(raw_id).strip_edges().is_empty():
			errors.append("clip key must be a non-empty string")
			continue
		var voice_id := str(raw_id)
		var raw_clip: Variant = clips[raw_id]
		if not raw_clip is Dictionary:
			errors.append("clip %s must be an object" % voice_id)
			continue
		var clip: Dictionary = raw_clip
		var speaker_value: Variant = clip.get("speaker", null)
		var text_value: Variant = clip.get("text", null)
		var file_value: Variant = clip.get("file", null)
		if not speaker_value is String or str(speaker_value).strip_edges().is_empty():
			errors.append("clip %s speaker must be a non-empty character id" % voice_id)
			continue
		if not text_value is String or str(text_value).strip_edges().is_empty():
			errors.append("clip %s text must be a non-empty string" % voice_id)
			continue
		if not file_value is String or not _is_safe_audio_path(str(file_value)):
			errors.append("clip %s file must be a local WAV under %s" % [voice_id, AUDIO_ROOT])
			continue

		var file_path := str(file_value)
		if not ResourceLoader.exists(file_path):
			errors.append("audio resource unavailable for clip %s: %s" % [voice_id, file_path])
			continue
		var loaded: Resource = ResourceLoader.load(file_path)
		if not loaded is AudioStream:
			errors.append("audio resource unavailable for clip %s: %s" % [voice_id, file_path])
			continue
		var stream := loaded as AudioStream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		_clips[voice_id] = {
			"speaker": str(speaker_value),
			"text": str(text_value),
			"stream": stream,
		}

	return {"ok": errors.is_empty(), "errors": errors}


func play_clip(voice_id: String, speaker: String, text: String) -> Dictionary:
	stop("replaced")
	if not _enabled:
		_stop_reason = "disabled"
		return {"ok": false, "reason": _stop_reason}
	if not _clips.has(voice_id):
		_stop_reason = "clip_not_found"
		return {"ok": false, "reason": _stop_reason}
	var clip_value: Variant = _clips.get(voice_id, {})
	if not clip_value is Dictionary:
		_stop_reason = "clip_not_found"
		return {"ok": false, "reason": _stop_reason}
	var clip: Dictionary = clip_value
	if str(clip.get("speaker", "")) != speaker:
		_stop_reason = "speaker_mismatch"
		return {"ok": false, "reason": _stop_reason}
	if str(clip.get("text", "")) != text:
		_stop_reason = "text_mismatch"
		return {"ok": false, "reason": _stop_reason}
	var stream: AudioStream = clip.get("stream") as AudioStream
	if stream == null:
		_stop_reason = "audio_unavailable"
		return {"ok": false, "reason": _stop_reason}
	_ensure_player()
	_player.stream = stream
	_current_id = voice_id
	_player.play()
	_play_count += 1
	_stop_reason = ""
	return {"ok": true, "reason": ""}


func stop(reason: String = "") -> void:
	if is_instance_valid(_player):
		if _player.playing:
			_player.stop()
		_player.stream = null
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
		"clip_count": _clips.size(),
	}


func _ensure_player() -> void:
	if is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "CultivationVoicePlayer"
	add_child(_player)
	_player.finished.connect(_on_player_finished)


func _on_player_finished() -> void:
	_current_id = ""
	_stop_reason = "finished"


func _is_safe_audio_path(path: String) -> bool:
	if not path.begins_with(AUDIO_ROOT) or path.contains("\\") or not path.ends_with(".wav"):
		return false
	var relative_path := path.substr(AUDIO_ROOT.length())
	if relative_path.is_empty():
		return false
	for segment in relative_path.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true
