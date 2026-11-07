extends RefCounted
## Samples authored poses from the host's real travelled distance / ambient
## phase. No clock, movement, Session state, Tween or settlement lives here.

const PLAYER_SHEET := "res://assets/art/town_natural_characters/player-motion.svg"
const MERCHANT_SHEET := "res://assets/art/town_natural_characters/tea-seller-life.svg"
const PATRON_SHEET := "res://assets/art/town_natural_characters/tea-patron.svg"
const SOURCE := "res://assets/art/town_natural_characters/source.json"
const CYCLE_DISTANCE: float = 90.0
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]

var _player_frames: Dictionary = {}
var _merchant_frames: Array[Texture2D] = []
var _patron_frames: Array[Texture2D] = []
var _player_pose: Dictionary = {}
var _merchant_index: int = -1
var _patron_index: int = -1


func _init() -> void:
	var player := _load_sheet(PLAYER_SHEET)
	if player != null:
		for row: int in range(4):
			var frames: Array[Texture2D] = []
			for column: int in range(12):
				frames.append(_crop(player, Rect2(column * 80, row * 112, 80, 112)))
			_player_frames[DIRECTIONS[row]] = frames
	var merchant := _load_sheet(MERCHANT_SHEET)
	if merchant != null:
		for index: int in range(6):
			_merchant_frames.append(_crop(merchant, Rect2(index * 80, 0, 80, 112)))
	var patron := _load_sheet(PATRON_SHEET)
	if patron != null:
		for index: int in range(3):
			_patron_frames.append(_crop(patron, Rect2(index * 64, 0, 64, 96)))


func available() -> bool:
	return _player_frames.size() == 4 and _merchant_frames.size() == 6 and _patron_frames.size() == 3


func apply(stage: Node) -> void:
	if not available():
		return
	var actors: Dictionary = stage.get("actor_nodes")
	var player := actors.get("player") as Sprite3D
	var direction: String = str(stage.get("_facing"))
	if not _player_frames.has(direction):
		direction = "down"
	var walking: bool = bool(stage.get("_walking")) and bool(stage.get("_active"))
	var stride: float = float(stage.get("_stride"))
	var elapsed: float = float(stage.get("ambient_elapsed"))
	var phase: float = fposmod(stride, CYCLE_DISTANCE) / CYCLE_DISTANCE
	var column: int = floori(phase * 8.0) if walking else _idle_column(elapsed)
	if is_instance_valid(player):
		player.texture = (_player_frames[direction] as Array)[column] as Texture2D
		_player_pose = {"direction": direction, "column": column, "walking": walking,
			"stride": stride, "phase": phase, "foot_anchor": Vector2(40, 104),
			"frame_size": Vector2(80, 112), "position": player.position,
			"ambient_elapsed": elapsed, "sheet": PLAYER_SHEET}
	var merchant := actors.get("tea_seller") as Sprite3D
	var seller_life := stage.get("_seller_life") as RefCounted
	if is_instance_valid(merchant) and is_instance_valid(seller_life):
		_merchant_index = int(seller_life.call("frame_index_at", elapsed))
		merchant.texture = _merchant_frames[_merchant_index]
	var patron := stage.get("_tea_patron") as Sprite3D
	var patron_life := stage.get("_patron_life") as RefCounted
	if is_instance_valid(patron) and is_instance_valid(patron_life):
		_patron_index = int(patron_life.call("frame_index_at", elapsed))
		patron.texture = _patron_frames[_patron_index]


func restore(stage: Node) -> void:
	# The host still owns the original art and phase. Restore it immediately on
	# A selection, including a selection between two ordinary walking ticks.
	stage.call("_update_actor", "player", stage.get("_player"), stage.get("_facing"),
		bool(stage.get("_walking")) and bool(stage.get("_active")), stage.get("_stride"))
	stage.call("_update_ambient")


func audit() -> Dictionary:
	return {"available": available(), "player": _player_pose.duplicate(true),
		"cycle_distance": CYCLE_DISTANCE, "walk_frames": 8, "idle_frames": 4,
		"merchant_frame": _merchant_index, "patron_frame": _patron_index,
		"source": SOURCE, "player_sheet": PLAYER_SHEET, "merchant_sheet": MERCHANT_SHEET,
		"patron_sheet": PATRON_SHEET,
		"time_authority": "host travelled distance for walking; existing ambient_elapsed for idle",
		"contact": "authored foot / seat anchors; no whole-actor bob or scale animation"}


func _idle_column(elapsed: float) -> int:
	# One brief blink per 5.8 seconds; breathing changes only the authored upper
	# body. Sampling this same phase also reproduces a frozen view after saving.
	var phase: float = fposmod(maxf(elapsed, 0.0), 5.8)
	if phase > 5.60 and phase < 5.74:
		return 11
	var breath: float = (sin(elapsed * TAU / 4.6 - PI * 0.5) + 1.0) * 0.5
	return 8 if breath < 0.25 else 9 if breath < 0.75 else 10


func _load_sheet(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _crop(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = sheet
	frame.region = region
	frame.filter_clip = true
	return frame
