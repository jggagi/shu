extends SceneTree

const VoicePlayer = preload("res://scripts/dialogue_tools_lab/voice_player.gd")

var checks := 0
var failures := 0
var temp_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := VoicePlayer.new()
	root.add_child(player)
	await process_frame

	var missing_manifest := player.configure_manifest("res://assets/audio/mentor_pause/__missing_manifest__.json")
	_check(not bool(missing_manifest.get("ok", true)), "missing manifest reports a configuration error")
	_check(not (missing_manifest.get("errors", []) as Array).is_empty(), "missing manifest includes a diagnostic")

	var malformed_path := _write_file("{ malformed")
	var malformed_result := player.configure_manifest(malformed_path)
	_check(not bool(malformed_result.get("ok", true)), "malformed manifest JSON is rejected")

	var duplicate_id_path := _write_manifest([
		_clip("same_id", "叶知闲", "第一句", "first.wav"),
		_clip("same_id", "江砚秋", "第二句", "second.wav"),
	])
	var duplicate_id_result := player.configure_manifest(duplicate_id_path)
	_check(not bool(duplicate_id_result.get("ok", true)), "duplicate clip ids are rejected")
	_check(_errors_contain(duplicate_id_result, "duplicate clip id"), "duplicate id diagnostic identifies the conflict")

	var duplicate_line_path := _write_manifest([
		_clip("line_a", "叶知闲", "同一句话", "line_a.wav"),
		_clip("line_b", "叶知闲", "同一句话", "line_b.wav"),
	])
	var duplicate_line_result := player.configure_manifest(duplicate_line_path)
	_check(not bool(duplicate_line_result.get("ok", true)), "duplicate speaker/text pairs are rejected")
	_check(_errors_contain(duplicate_line_result, "duplicate speaker/text pair"), "duplicate line diagnostic identifies the conflict")

	var invalid_path_result := player.configure_manifest(_write_manifest([
		{"id": "outside", "speaker": "叶知闲", "text": "不应加载", "file": "res://outside.wav", "sha256": ""},
	]))
	_check(not bool(invalid_path_result.get("ok", true)), "audio paths outside the local clip folder are rejected")

	var missing_audio_result := player.configure_manifest(_write_manifest([
		_clip("missing_audio", "叶知闲", "缺少音频", "__mentor_voice_test_missing__.wav"),
	]))
	_check(not bool(missing_audio_result.get("ok", true)), "unavailable audio resource fails configuration without crashing")
	_check(_errors_contain(missing_audio_result, "audio resource unavailable"), "missing audio resource includes a diagnostic")
	_check(not bool(player.audit().get("playing", true)), "failed configuration leaves voice stopped")

	player.set_enabled(false)
	_check(not bool(player.audit().get("enabled", true)), "voice can be muted")
	_check(not bool(player.play_line("叶知闲", "缺少音频").get("ok", true)), "muted voice refuses playback")
	player.set_enabled(true)
	_check(bool(player.audit().get("enabled", false)), "voice can be enabled again")

	for path in temp_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	player.queue_free()
	print("mentor_voice_player_test: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _clip(clip_id: String, speaker: String, spoken_text: String, filename: String) -> Dictionary:
	return {
		"id": clip_id,
		"speaker": speaker,
		"text": spoken_text,
		"file": "res://assets/audio/mentor_pause/" + filename,
		"sha256": "",
	}


func _write_manifest(clips: Array) -> String:
	return _write_file(JSON.stringify({"schema_version": 1, "clips": clips}))


func _write_file(contents: String) -> String:
	var path := OS.get_temp_dir().path_join("mentor_voice_player_test_%d_%d.json" % [Time.get_ticks_usec(), temp_paths.size()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "test manifest file can be written")
		return ""
	file.store_string(contents)
	file.close()
	temp_paths.append(path)
	return path


func _errors_contain(result: Dictionary, fragment: String) -> bool:
	for error in result.get("errors", []):
		if str(error).contains(fragment):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error(message)
