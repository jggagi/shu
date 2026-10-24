extends SceneTree

const VoicePlayerScript := preload("res://addons/cultivation_mode/voice_player.gd")
const VALID_CLIP_PATH := "res://assets/audio/mentor_pause/opening.wav"
const MISSING_CLIP_PATH := "res://assets/audio/__missing_cultivation_voice_test__.wav"
const VALID_SPEAKER := "江砚秋"
const VALID_TEXT := "师父，刚才那一剑，我明明已经快了，怎么还是收不住？"

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player: Node = VoicePlayerScript.new()
	root.add_child(player)
	await process_frame

	var empty_result: Dictionary = player.call("configure", {})
	_check(bool(empty_result.get("ok", false)), "an empty clip registry configures successfully")
	_check((empty_result.get("errors", []) as Array).is_empty(), "an empty clip registry has no errors")
	_check(int(_audit(player).get("clip_count", -1)) == 0, "an empty clip registry contains no clips")
	_check(is_instance_valid(player.get_node_or_null("CultivationVoicePlayer")), "the component owns one reusable AudioStreamPlayer")

	var invalid_clips := {
		"outside": _clip("res://other/audio.wav"),
		"traversal": _clip("res://assets/audio/../outside.wav"),
		"nested_traversal": _clip("res://assets/audio/mentor_pause/../opening.wav"),
		"backslash": _clip("res://assets/audio\\mentor_pause\\opening.wav"),
		"extension": _clip("res://assets/audio/mentor_pause/opening.ogg"),
		"missing_fields": {},
		"not_an_object": "invalid",
		17: _clip(VALID_CLIP_PATH),
	}
	var invalid_result: Dictionary = player.call("configure", invalid_clips)
	_check(not bool(invalid_result.get("ok", true)), "malformed and unsafe clip entries report a configuration error")
	_check(not (invalid_result.get("errors", []) as Array).is_empty(), "malformed entries include diagnostics")
	_check(int(_audit(player).get("clip_count", -1)) == 0, "unsafe and malformed entries are not retained")

	var missing_result: Dictionary = player.call("configure", {"missing": _clip(MISSING_CLIP_PATH)})
	_check(not bool(missing_result.get("ok", true)), "a missing local WAV reports a configuration error")
	_check(_errors_contain(missing_result, "audio resource unavailable"), "a missing WAV includes a useful diagnostic")
	_check(int(_audit(player).get("clip_count", -1)) == 0, "a missing clip is skipped while text remains caller-owned")
	var missing_play: Dictionary = player.call("play_clip", "missing", VALID_SPEAKER, VALID_TEXT)
	_check(not bool(missing_play.get("ok", true)) and str(missing_play.get("reason", "")) == "clip_not_found", "an unavailable clip leaves playback unavailable for text fallback")

	var loaded_clip: Resource = ResourceLoader.load(VALID_CLIP_PATH) if ResourceLoader.exists(VALID_CLIP_PATH) else null
	if loaded_clip is AudioStream:
		var partial_result: Dictionary = player.call("configure", {
			"opening": _clip(VALID_CLIP_PATH),
			"missing": _clip(MISSING_CLIP_PATH),
		})
		_check(not bool(partial_result.get("ok", true)), "a partial registry reports its missing member")
		_check(int(_audit(player).get("clip_count", -1)) == 1, "a partial registry retains its valid clip")

		var wrong_speaker: Dictionary = player.call("play_clip", "opening", "another_character", VALID_TEXT)
		_check(not bool(wrong_speaker.get("ok", true)) and str(wrong_speaker.get("reason", "")) == "speaker_mismatch", "playback checks the exact character id")
		var wrong_text: Dictionary = player.call("play_clip", "opening", VALID_SPEAKER, "different text")
		_check(not bool(wrong_text.get("ok", true)) and str(wrong_text.get("reason", "")) == "text_mismatch", "playback checks the exact dialogue text")
		_check(not bool(_audit(player).get("playing", true)), "mismatched calls stop earlier playback first")

		var play_result: Dictionary = player.call("play_clip", "opening", VALID_SPEAKER, VALID_TEXT)
		_check(bool(play_result.get("ok", false)), "a registered matching clip starts playback")
		var playing_audit := _audit(player)
		_check(str(playing_audit.get("current_id", "")) == "opening", "the audit identifies the active clip")
		_check(int(playing_audit.get("play_count", -1)) == 1, "the audit counts successful explicit play calls")
		var replay_result: Dictionary = player.call("play_clip", "opening", VALID_SPEAKER, VALID_TEXT)
		_check(bool(replay_result.get("ok", false)) and int(_audit(player).get("play_count", -1)) == 2, "an explicit repeated play call replays the registered line")
		player.call("stop", "test_stop")
		var stopped_audit := _audit(player)
		_check(not bool(stopped_audit.get("playing", true)) and str(stopped_audit.get("current_id", "")) == "", "stop clears active playback")
		_check(str(stopped_audit.get("stop_reason", "")) == "test_stop", "stop records its supplied reason")

		player.call("play_clip", "opening", VALID_SPEAKER, VALID_TEXT)
		player.call("set_enabled", false)
		_check(not bool(_audit(player).get("playing", true)), "muting stops active playback")
		var muted_result: Dictionary = player.call("play_clip", "opening", VALID_SPEAKER, VALID_TEXT)
		_check(not bool(muted_result.get("ok", true)) and str(muted_result.get("reason", "")) == "disabled", "muted playback is refused")
		_check(not bool(player.call("is_voice_enabled")), "the enabled query reports the muted state")
		player.call("set_enabled", true)
		_check(bool(player.call("is_voice_enabled")), "voice can be enabled again")

		var cleared_result: Dictionary = player.call("configure", {})
		_check(bool(cleared_result.get("ok", false)) and int(_audit(player).get("clip_count", -1)) == 0, "reconfiguration to an empty registry clears old clips")
		_check(player.get_node("CultivationVoicePlayer").get("stream") == null, "empty reconfiguration releases the previous stream")
	else:
		print("SKIP: valid WAV playback checks require the root agent's imported resource run")

	player.queue_free()
	await process_frame
	print("cultivation_engine_voice_player_test: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _clip(file_path: String) -> Dictionary:
	return {"speaker": VALID_SPEAKER, "text": VALID_TEXT, "file": file_path}


func _audit(player: Node) -> Dictionary:
	var value: Variant = player.call("audit")
	return value as Dictionary if value is Dictionary else {}


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
	push_error("FAIL: " + message)
