extends RefCounted
## Pure sampling of the seated patron's three original poses.
## The host freezes its existing ambient_elapsed during Static/Busy. Flags
## report whether the sampled gesture can advance; they never replace its pose.

const Sheet: Texture2D = preload("res://assets/art/shanxia_polish/tea-patron.svg")
const SOURCE_PATH: String = "res://assets/art/shanxia_polish/tea-patron-source.json"
const FRAME_SIZE: Vector2 = Vector2(64, 96)
const FOOT_ANCHOR: Vector2 = Vector2(32, 80)
const SEAT_ANCHOR: Vector2 = Vector2(31, 58)
const HEAD_ANCHOR: Vector2 = Vector2(33, 20)
# Host calibrates fixed-Y billboard height against the actual bench/platform.
const WORLD_HEIGHT: float = 1.10
const PERIOD: float = 12.0
const GESTURE_START: float = 7.0
const GESTURE_DURATION: float = 2.2
const POSES: Array[String] = ["cup_rest", "cup_raise", "cup_sip"]

var _frames: Array[Texture2D] = []


func _init() -> void:
	for index: int in range(3):
		var frame := AtlasTexture.new()
		frame.atlas = Sheet
		frame.region = Rect2(index * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y)
		frame.filter_clip = true
		_frames.append(frame)


func frame_at(elapsed: float, _motion_enabled: bool = true, _active: bool = true) -> Texture2D:
	return _frames[frame_index_at(elapsed)]


func frame_index_at(elapsed: float) -> int:
	var phase: float = fposmod(maxf(elapsed, 0.0), PERIOD) - GESTURE_START
	if phase < 0.0 or phase >= GESTURE_DURATION:
		return 0
	if phase < 0.45:
		return 1
	if phase < 1.65:
		return 2
	return 1


func audit_at(elapsed: float, motion_enabled: bool = true, active: bool = true) -> Dictionary:
	var index: int = frame_index_at(elapsed)
	return {"frame_index": index, "pose": POSES[index], "gesture_visible": index != 0,
		"gesture_advancing": index != 0 and motion_enabled and active,
		"phase": fposmod(maxf(elapsed, 0.0), PERIOD), "period": PERIOD,
		"gesture_duration": GESTURE_DURATION, "frame_size": FRAME_SIZE,
		"foot_anchor": FOOT_ANCHOR, "seat_anchor": SEAT_ANCHOR, "head_anchor": HEAD_ANCHOR,
		"world_height_hint": WORLD_HEIGHT, "time_authority": "stage ambient_elapsed"}
