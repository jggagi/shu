extends RefCounted
## Stateless phase sampling for the tea seller's small cup-work gesture.
## The caller supplies its existing ambient_elapsed and freezes that phase while
## Static or Busy. This helper never advances a clock, settles actions or saves state.

const Sheet: Texture2D = preload("res://assets/art/shanxia_polish/tea-seller-life.svg")
const SOURCE_PATH: String = "res://assets/art/shanxia_polish/tea-seller-life-source.json"
const FRAME_SIZE: Vector2 = Vector2(80, 112)
const FOOT_ANCHOR: Vector2 = Vector2(40, 104)
const WORLD_HEIGHT: float = 1.55
const PERIOD: float = 14.0
const GESTURE_START: float = 2.0
const GESTURE_DURATION: float = 3.0
const POSES: Array[String] = ["hold_rest", "hold_lift", "hold_ready", "wipe_right", "wipe_across", "wipe_return"]

var _frames: Array[Texture2D] = []


func _init() -> void:
	for index: int in range(6):
		var cropped: AtlasTexture = AtlasTexture.new()
		cropped.atlas = Sheet
		cropped.region = Rect2(index * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y)
		cropped.filter_clip = true
		_frames.append(cropped)


func frame_at(elapsed: float, _motion_enabled: bool = true, _active: bool = true) -> Texture2D:
	# Flags deliberately do not replace the sampled pose with idle. The frozen
	# caller phase must preserve hands and cup exactly through Static/Busy and a
	# view rebuild. Advancing elapsed belongs exclusively to the caller.
	return _frames[frame_index_at(elapsed)]


func frame_index_at(elapsed: float) -> int:
	var phase: float = fposmod(maxf(elapsed, 0.0), PERIOD) - GESTURE_START
	if phase < 0.0 or phase >= GESTURE_DURATION:
		return 0
	if phase < 0.45:
		return 1
	if phase < 0.80:
		return 2
	if phase < 1.15:
		return 3
	if phase < 1.55:
		return 4
	if phase < 1.90:
		return 3
	if phase < 2.25:
		return 5
	if phase < 2.60:
		return 2
	return 1


func audit_at(elapsed: float, motion_enabled: bool = true, active: bool = true) -> Dictionary:
	var index: int = frame_index_at(elapsed)
	return {
		"frame_index": index,
		"pose": POSES[index],
		"gesture_visible": index != 0,
		"gesture_advancing": index != 0 and motion_enabled and active,
		"phase": fposmod(maxf(elapsed, 0.0), PERIOD),
		"period": PERIOD,
		"gesture_duration": GESTURE_DURATION,
		"frame_size": FRAME_SIZE,
		"foot_anchor": FOOT_ANCHOR,
		"time_authority": "stage ambient_elapsed"
	}
