extends Node

# Scene-only playback adapter. Weather owns rain, wind, drop releases, and elapsed.
const CUE_PROFILES := {
	"train": {"clip": "cloth", "gain": 0.34, "pitch": 1.04},
	"rest": {"clip": "cloth", "gain": 0.22, "pitch": 0.88},
	"mentor": {"clip": "cloth", "gain": 0.28, "pitch": 0.96},
	"pet": {"clip": "purr", "gain": 0.34, "pitch": 1.0},
	"bird": {"clip": "bird", "gain": 0.28, "pitch": 0.96},
}

var enabled := false
var volume := 0.45
var config: Dictionary = {}
var weather: Node
var rain_player: AudioStreamPlayer
var leaf_player: AudioStreamPlayer
var drop_players: Array[AudioStreamPlayer] = []
var cue_players: Array[AudioStreamPlayer] = []
var drop_streams: Array[AudioStreamWAV] = []
var cue_streams: Dictionary = {}
var pending_drops: Array[Dictionary] = []
var rain_gain := 0.0
var leaf_gain := 0.0
var attention_gain := 1.0
var drop_motion_gain := 1.0
var _next_player := 0
var _drop_serial := 0
var _cue_serial := 0
var _reset_fade_pending := false


func setup(environment: Node, settings: Dictionary) -> void:
	weather = environment
	config = settings
	volume = clampf(float(config.get("default_volume", 0.45)), 0.0, 1.0)
	rain_player = _make_loop_player("TingyuRainAudio", "res://assets/audio/tingyu/rain-loop.wav")
	leaf_player = _make_loop_player("TingyuLeafAudio", "res://assets/audio/tingyu/leaf-rustle.wav")
	for path in ["res://assets/audio/tingyu/eave-drop-1.wav", "res://assets/audio/tingyu/eave-drop-2.wav"]:
		drop_streams.append(load(path) as AudioStreamWAV)
	for key in ["cloth", "purr", "bird"]:
		cue_streams[key] = load("res://assets/audio/tingyu/%s.wav" % key) as AudioStreamWAV
	for index in 3:
		var player := AudioStreamPlayer.new()
		player.name = "TingyuDropAudio%d" % index
		player.volume_db = -80.0
		add_child(player)
		drop_players.append(player)
	for index in 5:
		var player := AudioStreamPlayer.new()
		player.name = "TingyuCueAudio%d" % index
		player.volume_db = -80.0
		add_child(player)
		cue_players.append(player)


func _make_loop_player(player_name: String, path: String) -> AudioStreamPlayer:
	var source := load(path) as AudioStreamWAV
	if source == null:
		return null
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player


func _scene_visible() -> bool:
	return is_instance_valid(weather) and is_instance_valid(weather.scene_root) and weather.scene_root.is_visible_in_tree()


func _motion_running() -> bool:
	return is_instance_valid(weather) and weather.enabled and not weather.motion_paused


func _is_busy() -> bool:
	return is_instance_valid(weather) and weather.foreground_attention_getter.is_valid() and bool(weather.foreground_attention_getter.call())


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_clear_short_cues()
	# Enabling occurs directly in the button callback for Web audio activation.
	if enabled and volume > 0.0 and _scene_visible() and _motion_running():
		_start_rain()
		_start_leaf()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	if volume <= 0.0:
		_clear_short_cues()
	elif enabled and _scene_visible() and _motion_running():
		_start_rain()
		_start_leaf()


func queue_drop(anchor_index: int, released_at: float, fall_seconds: float) -> void:
	if not enabled or volume <= 0.0 or not _scene_visible() or not _motion_running():
		return
	pending_drops.append({
		"anchor": anchor_index,
		"due": released_at + fall_seconds * float(config.get("drop_impact_fraction", 0.88)),
	})


func play_cue(kind: String) -> void:
	if not enabled or volume <= 0.0 or not _scene_visible() or not _motion_running():
		return
	var profile: Dictionary = CUE_PROFILES.get(kind, {})
	if profile.is_empty() or cue_players.is_empty():
		return
	if kind == "bird" and _is_busy():
		return
	var clip: AudioStreamWAV = cue_streams.get(str(profile.get("clip", "")))
	if clip == null:
		return
	var player := cue_players[_cue_serial % cue_players.size()]
	_cue_serial += 1
	player.stream = clip
	player.pitch_scale = float(profile.get("pitch", 1.0))
	player.volume_db = linear_to_db(maxf(0.0001, volume * float(profile.get("gain", 0.3))))
	player.set_meta("cue_base_gain", float(profile.get("gain", 0.3)))
	player.set_meta("cue_kind", kind)
	player.stream_paused = false
	player.play()


func advance(delta: float) -> void:
	if not is_instance_valid(weather):
		_clear_short_cues()
		return
	var step := maxf(0.0, delta)
	var audible := enabled and volume > 0.0 and _scene_visible()
	var running := _motion_running()
	var busy := _is_busy()
	var attention_target := float(config.get("busy_multiplier", 0.35)) if busy else 1.0
	var attention_seconds := maxf(0.01, float(config.get("attention_seconds", 0.35)))
	attention_gain = lerpf(attention_gain, attention_target, 1.0 - exp(-step / attention_seconds))
	var environment: Dictionary = weather.presenter.get_current_environment() if is_instance_valid(weather.presenter) else {}
	var rain_amount := clampf(float(environment.get("rain_amount", 0.0)), 0.0, 1.0)
	var rain_target := rain_amount * volume * float(config.get("rain_gain", 0.62)) * attention_gain if audible and running else 0.0
	var wind_strength := 0.0
	if weather.has_method("get_current_wind_strength"):
		wind_strength = clampf(float(weather.call("get_current_wind_strength")), 0.0, 1.0)
	var leaf_target := wind_strength * volume * 0.62 * attention_gain if audible and running else 0.0
	if _reset_fade_pending:
		rain_target = 0.0
		leaf_target = 0.0
	var fade_seconds := maxf(0.01, float(config.get("fade_seconds", 0.25)))

	rain_gain = lerpf(rain_gain, rain_target, 1.0 - exp(-step / fade_seconds))
	if rain_player != null:
		if rain_gain > 0.0005:
			_start_rain()
			rain_player.volume_db = linear_to_db(rain_gain)
		elif rain_player.playing:
			rain_player.volume_db = linear_to_db(maxf(0.0001, rain_gain))
			rain_player.stop()

	leaf_gain = lerpf(leaf_gain, leaf_target, 1.0 - exp(-step / fade_seconds))
	if leaf_player != null:
		if leaf_gain > 0.0005:
			_start_leaf()
			leaf_player.volume_db = linear_to_db(leaf_gain)
		elif leaf_player.playing:
			leaf_player.volume_db = linear_to_db(maxf(0.0001, leaf_gain))
			leaf_player.stop()
	if _reset_fade_pending and rain_gain <= 0.0005 and leaf_gain <= 0.0005:
		_reset_fade_pending = false

	if not audible:
		_clear_short_cues()
		return
	drop_motion_gain = lerpf(drop_motion_gain, 1.0 if running else 0.0, 1.0 - exp(-step / fade_seconds))
	for player in drop_players:
		# Existing short tails fade to completion; future impacts stay on weather elapsed.
		player.volume_db = linear_to_db(maxf(0.0001, volume * float(config.get("drop_gain", 0.38)) * attention_gain * drop_motion_gain))
	for player in cue_players:
		if not running:
			player.stop()
		elif player.playing:
			var cue_gain := float(player.get_meta("cue_base_gain", 0.3))
			if str(player.get_meta("cue_kind", "")) == "bird": cue_gain *= attention_gain
			player.volume_db = linear_to_db(maxf(0.0001, volume * cue_gain))
	if not running:
		# D046: future impacts remain on frozen weather elapsed; current tails fade.
		return
	for index in range(pending_drops.size() - 1, -1, -1):
		var event: Dictionary = pending_drops[index]
		var age := float(weather.elapsed) - float(event.due)
		if age < 0.0:
			continue
		pending_drops.remove_at(index)
		# Large frame jumps never replay a backlog of past impacts.
		if age <= float(config.get("late_drop_limit_seconds", 0.25)):
			_play_drop(int(event.anchor))


func _start_rain() -> void:
	if rain_player == null or rain_player.playing:
		return
	var length := rain_player.stream.get_length()
	var position := fposmod(float(weather.elapsed), length) if length > 0.0 else 0.0
	rain_player.play(position)


func _start_leaf() -> void:
	if leaf_player == null or leaf_player.playing:
		return
	var length := leaf_player.stream.get_length()
	var position := fposmod(float(weather.elapsed), length) if length > 0.0 else 0.0
	leaf_player.play(position)


func _play_drop(anchor_index: int) -> void:
	var player := drop_players[_next_player]
	_next_player = (_next_player + 1) % drop_players.size()
	player.stream = drop_streams[(_drop_serial + anchor_index) % drop_streams.size()]
	player.pitch_scale = 0.98 + float(anchor_index) * 0.02
	player.stream_paused = false
	player.play()
	_drop_serial += 1


func _clear_drops() -> void:
	pending_drops.clear()
	for player in drop_players:
		player.stop()
		player.stream_paused = false


func _clear_short_cues() -> void:
	_clear_drops()
	for player in cue_players:
		player.stop()
		player.stream_paused = false


func reset() -> void:
	# User sound/volume choices survive gameplay reset; loops fade to the reset environment.
	_clear_short_cues()
	_reset_fade_pending = true
	attention_gain = 1.0
	drop_motion_gain = 1.0
	_next_player = 0
	_drop_serial = 0
	_cue_serial = 0
