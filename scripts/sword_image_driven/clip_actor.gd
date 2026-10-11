extends Node2D
# Offline transparent frames. There is no gameplay state, pose synthesis or body scaling.
const MANIFEST := "res://assets/art/sword_image_driven_v1/atlas.json"
var data: Dictionary = {}
var frames: Array[AtlasTexture] = []
var anchors: Array[Vector2] = []
var sprite := Sprite2D.new()
var seconds := 0.0
var frame_index := 0
var duration := 0.0
var fps := 25.0
var paused := true
var speed := 1.0
signal completed

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	fps = float(data.fps)
	duration = float(data.duration)
	var pages: Dictionary = {}
	for entry: Dictionary in data.frames:
		var page: String = entry.path
		if not pages.has(page):
			pages[page] = load(page)
		var frame := AtlasTexture.new()
		frame.atlas = pages[page]
		var r: Array = entry.region
		frame.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		frame.filter_clip = true
		frames.append(frame)
		var a: Array = entry.source_anchor_px
		anchors.append(Vector2(float(a[0]), float(a[1])) * 0.5)
	# A small median rejects segmentation outliers without independently changing body size.
	var raw := anchors.duplicate()
	for i in anchors.size():
		var xs: Array[float] = []
		var ys: Array[float] = []
		for j in range(maxi(0, i - 2), mini(anchors.size(), i + 3)):
			xs.append(raw[j].x)
			ys.append(raw[j].y)
		xs.sort()
		ys.sort()
		anchors[i] = Vector2(xs[xs.size() / 2], ys[ys.size() / 2])
	# Sole switching during the turn needs a continuous translation, never a scale change.
	var filtered := anchors.duplicate()
	for i in anchors.size():
		var total := Vector2.ZERO
		var total_weight := 0.0
		for j in range(maxi(0, i - 6), mini(anchors.size(), i + 7)):
			var distance := float(j - i)
			var weight := exp(-distance * distance / 18.0)
			total += filtered[j] * weight
			total_weight += weight
		anchors[i] = total / total_weight
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	seek(0.0)

func advance(delta: float) -> void:
	if paused or frames.is_empty():
		return
	seconds = minf(duration, seconds + maxf(delta, 0.0) * speed)
	_sample()
	if seconds >= duration:
		paused = true
		completed.emit()

func replay() -> void:
	seek(0.0)
	paused = false

func seek(value: float) -> void:
	seconds = clampf(value, 0.0, duration)
	_sample()

func _sample() -> void:
	if frames.is_empty():
		return
	var exact := minf(seconds * fps, float(frames.size() - 1))
	frame_index = clampi(int(floor(exact)), 0, frames.size() - 1)
	sprite.texture = frames[frame_index]
	var next := mini(frame_index + 1, anchors.size() - 1)
	sprite.position = -anchors[frame_index].lerp(anchors[next], exact - floor(exact))
