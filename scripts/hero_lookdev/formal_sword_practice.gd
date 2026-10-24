extends Node

const Catalog = preload("res://scripts/sword_manual_catalog.gd")

signal finished(action_id: int)

const IDLE_MANIFEST := "res://assets/art/jiang_sword_cycle/idle/frames.json"
const SETS_CATALOG := "res://assets/art/jiang_sword_cycle/sets.json"
const CYCLE_FPS := 30.0
const IDLE_FRAME_COUNT := 60
const ACTION_FRAME_COUNT := 180
const IDLE_ATLAS_COUNT := 3
const ACTION_ATLAS_COUNT := 8
const CELL_SIZE := Vector2i(512, 512)
const SOURCE_ANCHOR := Vector2(478.95962, 911.13357)
const RESIZED_ANCHOR := Vector2(245.22732544, 466.50038784)
const FOOT_ANCHOR := Vector2(1010.0, 565.0)
const ACTOR_SCALE := 0.62
const SETTLE_SECONDS := 0.25
const ACTION_SECONDS := float(ACTION_FRAME_COUNT) / CYCLE_FPS
const RECEIPT_SECONDS := 0.8
const REQUIRED_CLIP_IDS := ["songfeng", "chuanyun", "huilan", "tiaoyue", "xieying"]

var view: Control
var idle_ready := false
var action_ready := false
var selected_clip_id := ""
var selected_manual_id := ""
var selected_technique_id := ""
var selected_manual_title := ""
var selected_technique_title := ""
var playing := false
var elapsed := 0.0
var phase := "待机"
var current_frame_index := 0
var loaded_idle_atlas_paths: Array[String] = []
var loaded_action_atlas_paths: Array[String] = []

var _idle_frames: Array[Texture2D] = []
var _action_frames: Array[Texture2D] = []
var _set_catalog: Dictionary = {}
var _cycle_actor: Node2D
var _cycle_sprite: Sprite2D
var _contact_shadow: Sprite2D
var _actor_state := "idle"
var _idle_elapsed := 0.0
var _settle_elapsed := 0.0
var _settle_from_frame := 0
var _settle_target_frame := 0
var _action_elapsed := 0.0
var _receipt_elapsed := 0.0
var _action_id := 0
var _actual_receipt: Dictionary = {}


func setup(scene_view: Control) -> void:
	view = scene_view
	var idle_frames: Array[Texture2D] = []
	var idle_atlas_paths: Array[String] = []
	if _load_clip(IDLE_MANIFEST, IDLE_FRAME_COUNT, IDLE_ATLAS_COUNT, "", idle_frames, idle_atlas_paths):
		_idle_frames = idle_frames
		loaded_idle_atlas_paths = idle_atlas_paths
		idle_ready = true
	if not _load_set_catalog():
		return
	_build_actor()
	_apply_idle_frame(0)


func resource_ready() -> bool:
	return idle_ready and action_ready and _idle_frames.size() == IDLE_FRAME_COUNT and _action_frames.size() == ACTION_FRAME_COUNT and not selected_clip_id.is_empty()


func select_form(manual_id: String, technique_id: String) -> bool:
	if playing or not idle_ready or _cycle_sprite == null:
		return false
	var manual: Dictionary = Catalog.manual(manual_id)
	if manual.is_empty():
		push_error("Formal sword practice cannot find manual: " + manual_id)
		return false
	var clip_id := str(manual.get("clip_id", ""))
	if not REQUIRED_CLIP_IDS.has(clip_id) or not _set_catalog.has(clip_id):
		push_error("Formal sword manual has an unsupported or missing clip_id: " + manual_id + " / " + clip_id)
		return false
	var techniques: Variant = manual.get("techniques", null)
	if not techniques is Array or techniques.size() != 1:
		push_error("Formal sword manual must define exactly one technique: " + manual_id)
		return false
	var technique: Variant = techniques[0]
	if not technique is Dictionary or str(technique.get("id", "")) != technique_id:
		push_error("Formal sword technique does not match the selected manual: " + manual_id + " / " + technique_id)
		return false
	if selected_clip_id != clip_id or _action_frames.size() != ACTION_FRAME_COUNT:
		var set_entry: Dictionary = _set_catalog[clip_id]
		var new_frames: Array[Texture2D] = []
		var new_atlas_paths: Array[String] = []
		if not _load_clip(str(set_entry.get("manifest_path", "")), ACTION_FRAME_COUNT, ACTION_ATLAS_COUNT, clip_id, new_frames, new_atlas_paths):
			return false
		# The sprite holds an idle atlas frame here, so replacing this array releases
		# the previous action clip's AtlasTexture and atlas references.
		_action_frames = new_frames
		loaded_action_atlas_paths = new_atlas_paths
		selected_clip_id = clip_id
		action_ready = true
	selected_manual_id = manual_id
	selected_technique_id = technique_id
	selected_manual_title = str(manual.get("title", "剑谱"))
	selected_technique_title = str(technique.get("title", "招式"))
	phase = "待机"
	_update_hint()
	return resource_ready()


func play(id: int, actual_receipt: Dictionary) -> bool:
	if playing or not resource_ready() or actual_receipt.is_empty():
		return false
	if str(actual_receipt.get("manual_id", "")) != selected_manual_id or str(actual_receipt.get("technique_id", "")) != selected_technique_id:
		return false
	_action_id = id
	_actual_receipt = actual_receipt.duplicate(true)
	elapsed = 0.0
	_action_elapsed = 0.0
	_receipt_elapsed = 0.0
	_settle_elapsed = 0.0
	_settle_from_frame = current_frame_index
	_settle_target_frame = 0 if current_frame_index <= (IDLE_FRAME_COUNT - 1) / 2 else IDLE_FRAME_COUNT - 1
	playing = true
	if current_frame_index == 0 or current_frame_index == IDLE_FRAME_COUNT - 1:
		_begin_action()
	else:
		_actor_state = "settle"
		phase = _phase_label(0)
		_update_hint()
	return true


func _process(delta: float) -> void:
	if playing:
		_advance_practice(maxf(delta, 0.0))
	elif view != null and bool(view.dynamic_enabled) and idle_ready:
		_idle_elapsed = fposmod(_idle_elapsed + maxf(delta, 0.0), float(IDLE_FRAME_COUNT) / CYCLE_FPS)
		_apply_idle_frame(mini(int(floor(_idle_elapsed * CYCLE_FPS)), IDLE_FRAME_COUNT - 1))


func _advance_practice(delta: float) -> void:
	var remaining := delta
	elapsed += delta
	while playing and remaining > 0.0:
		if _actor_state == "settle":
			var step := minf(remaining, SETTLE_SECONDS - _settle_elapsed)
			_settle_elapsed += step
			remaining -= step
			var weight := clampf(_settle_elapsed / SETTLE_SECONDS, 0.0, 1.0)
			var eased := weight * weight * (3.0 - 2.0 * weight)
			var frame := clampi(roundi(lerpf(float(_settle_from_frame), float(_settle_target_frame), eased)), 0, IDLE_FRAME_COUNT - 1)
			_apply_idle_frame(frame)
			if _settle_elapsed >= SETTLE_SECONDS:
				_apply_idle_frame(_settle_target_frame)
				_begin_action()
		elif _actor_state == "action":
			var step := minf(remaining, ACTION_SECONDS - _action_elapsed)
			_action_elapsed += step
			remaining -= step
			if _action_elapsed >= ACTION_SECONDS:
				_complete_action()
			else:
				_apply_action_frame(mini(int(floor(_action_elapsed * CYCLE_FPS)), ACTION_FRAME_COUNT - 1))
		elif _actor_state == "receipt":
			var step := minf(remaining, RECEIPT_SECONDS - _receipt_elapsed)
			_receipt_elapsed += step
			remaining -= step
			if _receipt_elapsed >= RECEIPT_SECONDS:
				_finish_practice()
		else:
			break


func _begin_action() -> void:
	_actor_state = "action"
	_action_elapsed = 0.0
	_apply_action_frame(0)
	phase = _phase_label(0)
	_update_hint()


func _complete_action() -> void:
	_actor_state = "receipt"
	_receipt_elapsed = 0.0
	_idle_elapsed = 0.0
	_apply_idle_frame(0)
	phase = _phase_label(ACTION_FRAME_COUNT - 1)
	_update_hint()
	if view != null and view.sword_status != null:
		view.sword_status.text = "剑术 +%d · 精力 -%d · 时间 +%d 时辰" % [
			int(_actual_receipt.get("gain", 0)),
			int(_actual_receipt.get("energy_cost", 0)),
			int(_actual_receipt.get("duration", 0))
		]


func _finish_practice() -> void:
	var completed_id := _action_id
	playing = false
	_actor_state = "idle"
	_settle_elapsed = 0.0
	_action_elapsed = 0.0
	_receipt_elapsed = 0.0
	_idle_elapsed = 0.0
	_apply_idle_frame(0)
	finished.emit(completed_id)


func _apply_idle_frame(index: int) -> void:
	if _cycle_sprite == null or _idle_frames.is_empty():
		return
	current_frame_index = clampi(index, 0, IDLE_FRAME_COUNT - 1)
	_cycle_sprite.texture = _idle_frames[current_frame_index]
	_cycle_sprite.position = -RESIZED_ANCHOR


func _apply_action_frame(index: int) -> void:
	if _cycle_sprite == null or _action_frames.is_empty():
		return
	current_frame_index = clampi(index, 0, ACTION_FRAME_COUNT - 1)
	_cycle_sprite.texture = _action_frames[current_frame_index]
	_cycle_sprite.position = -RESIZED_ANCHOR
	phase = _phase_label(current_frame_index)
	_update_hint()


func _phase_label(frame_index: int) -> String:
	if selected_clip_id.is_empty() or not _set_catalog.has(selected_clip_id):
		return "待机"
	var phases: Array = _set_catalog[selected_clip_id].get("phases", [])
	var active_label := str(phases[0].get("label", "")) if not phases.is_empty() else ""
	for value: Variant in phases:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if frame_index + 1 < int(entry.get("start_frame", 1)):
			break
		active_label = str(entry.get("label", active_label))
	return active_label


func _update_hint() -> void:
	if view == null or view._hint_label == null:
		return
	if _actor_state == "idle":
		view._hint_label.text = "%s · %s" % [selected_manual_title, selected_technique_title]
	else:
		view._hint_label.text = "%s · %s" % [selected_manual_title, phase]


func _load_set_catalog() -> bool:
	var raw := FileAccess.get_file_as_string(SETS_CATALOG)
	if raw.is_empty():
		push_error("Formal sword practice is missing its set catalog: " + SETS_CATALOG)
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		push_error("Formal sword practice has an invalid set catalog: " + SETS_CATALOG)
		return false
	var entries: Variant = parsed.get("sets", null)
	if not entries is Array or entries.size() != REQUIRED_CLIP_IDS.size():
		push_error("Formal sword set catalog must contain all five approved clips: " + SETS_CATALOG)
		return false
	var found_ids: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary:
			push_error("Formal sword set catalog contains a malformed entry.")
			return false
		var entry: Dictionary = value
		var clip_id := str(entry.get("id", ""))
		var manifest_path := str(entry.get("manifest_path", ""))
		var phases: Variant = entry.get("phases", null)
		if not REQUIRED_CLIP_IDS.has(clip_id) or found_ids.has(clip_id) or not manifest_path.begins_with("res://"):
			push_error("Formal sword set catalog has an unsupported ID or manifest path: " + clip_id)
			return false
		if not phases is Array or phases.is_empty():
			push_error("Formal sword set needs phase labels: " + clip_id)
			return false
		var previous_start := 0
		for phase_value: Variant in phases:
			if not phase_value is Dictionary:
				push_error("Formal sword set has a malformed phase label: " + clip_id)
				return false
			var phase_entry: Dictionary = phase_value
			var start_frame := int(phase_entry.get("start_frame", 0))
			if start_frame < 1 or start_frame > ACTION_FRAME_COUNT or start_frame <= previous_start or str(phase_entry.get("label", "")).strip_edges().is_empty():
				push_error("Formal sword phase starts must be ordered and labeled: " + clip_id)
				return false
			previous_start = start_frame
		if int(phases[0].get("start_frame", 0)) != 1:
			push_error("Formal sword phases must start at frame 1: " + clip_id)
			return false
		found_ids[clip_id] = true
		_set_catalog[clip_id] = entry.duplicate(true)
	for clip_id: String in REQUIRED_CLIP_IDS:
		if not found_ids.has(clip_id):
			push_error("Formal sword set catalog is missing approved clip ID: " + clip_id)
			return false
	return true


func _load_clip(path: String, expected_count: int, expected_atlas_count: int, expected_id: String, destination: Array[Texture2D], atlas_paths: Array[String]) -> bool:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_error("Formal sword practice is missing frame manifest: " + path)
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_error("Formal sword practice has an invalid frame manifest: " + path)
		return false
	var manifest: Dictionary = parsed
	if int(manifest.get("frame_count", 0)) != expected_count or not is_equal_approx(float(manifest.get("fps", 0.0)), CYCLE_FPS):
		push_error("Formal sword clip must declare %d frames at 30 fps: %s" % [expected_count, path])
		return false
	var manifest_id := str(manifest.get("clip_id", manifest.get("id", "")))
	if not expected_id.is_empty() and not manifest_id.is_empty() and manifest_id != expected_id:
		push_error("Formal sword manifest ID does not match selected clip %s: %s" % [expected_id, path])
		return false
	var cell_values: Variant = manifest.get("cell_size", null)
	if not cell_values is Array or cell_values.size() != 2 or int(cell_values[0]) != CELL_SIZE.x or int(cell_values[1]) != CELL_SIZE.y:
		push_error("Formal sword atlas cells must be 512x512: " + path)
		return false
	var source_anchor_values: Variant = manifest.get("anchor_source_px", null)
	var resized_anchor_values: Variant = manifest.get("anchor_resized_px", null)
	if not source_anchor_values is Array or source_anchor_values.size() != 2 or not resized_anchor_values is Array or resized_anchor_values.size() != 2:
		push_error("Formal sword manifest must include approved source and resized anchors: " + path)
		return false
	var source_anchor := Vector2(float(source_anchor_values[0]), float(source_anchor_values[1]))
	var resized_anchor := Vector2(float(resized_anchor_values[0]), float(resized_anchor_values[1]))
	if source_anchor.distance_to(SOURCE_ANCHOR) > 0.0001 or resized_anchor.distance_to(RESIZED_ANCHOR) > 0.0001:
		push_error("Formal sword manifest does not preserve the approved foot anchor: " + path)
		return false
	var frames: Variant = manifest.get("frames", null)
	if not frames is Array or frames.size() != expected_count:
		push_error("Formal sword frame records do not match declared count: " + path)
		return false
	var atlas_cache: Dictionary = {}
	for value: Variant in frames:
		if not value is Dictionary:
			push_error("Formal sword frame manifest has a malformed frame: " + path)
			return false
		var frame_entry: Dictionary = value
		var atlas_path := str(frame_entry.get("path", ""))
		if not atlas_path.begins_with("res://"):
			push_error("Formal sword frame has an invalid atlas resource path: " + atlas_path)
			return false
		var atlas: Texture2D = atlas_cache.get(atlas_path)
		if atlas == null:
			atlas = load(atlas_path) as Texture2D
			if atlas == null:
				push_error("Formal sword practice cannot load atlas: " + atlas_path)
				return false
			atlas_cache[atlas_path] = atlas
			atlas_paths.append(atlas_path)
		var region_values: Variant = frame_entry.get("region", null)
		if not region_values is Array or region_values.size() != 4:
			push_error("Formal sword frame has an invalid atlas region: " + atlas_path)
			return false
		var region := Rect2(float(region_values[0]), float(region_values[1]), float(region_values[2]), float(region_values[3]))
		if region.position.x < 0.0 or region.position.y < 0.0 or region.size != Vector2(CELL_SIZE) or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region):
			push_error("Formal sword atlas regions must be contained 512x512 cells: " + atlas_path)
			return false
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = atlas
		atlas_frame.region = region
		atlas_frame.filter_clip = true
		destination.append(atlas_frame)
	if atlas_paths.size() != expected_atlas_count:
		push_error("Formal sword clip expected %d atlas pages but found %d: %s" % [expected_atlas_count, atlas_paths.size(), path])
		return false
	return true


func _build_actor() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.12, 0.17, 0.12, 0.34), Color(0.12, 0.17, 0.12, 0.20),
		Color(0.12, 0.17, 0.12, 0.065), Color(0.12, 0.17, 0.12, 0.0)
	])
	var shadow_texture := GradientTexture2D.new()
	shadow_texture.gradient = gradient
	shadow_texture.width = 256
	shadow_texture.height = 64
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	shadow_texture.fill_from = Vector2(0.5, 0.5)
	shadow_texture.fill_to = Vector2(1.0, 0.5)
	_contact_shadow = Sprite2D.new()
	_contact_shadow.name = "FormalSwordFootContact"
	_contact_shadow.texture = shadow_texture
	_contact_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_contact_shadow.position = FOOT_ANCHOR
	_contact_shadow.scale = Vector2(0.36, 0.28)
	view._foreground_layer.add_child(_contact_shadow)
	view._art_nodes.append(_contact_shadow)

	_cycle_actor = Node2D.new()
	_cycle_actor.name = "FormalJiangSwordActor"
	_cycle_actor.position = FOOT_ANCHOR
	_cycle_actor.scale = Vector2.ONE * ACTOR_SCALE
	view._foreground_layer.add_child(_cycle_actor)
	_cycle_sprite = Sprite2D.new()
	_cycle_sprite.name = "FormalJiangSwordFrame"
	_cycle_sprite.centered = false
	_cycle_sprite.position = -RESIZED_ANCHOR
	_cycle_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cycle_actor.add_child(_cycle_sprite)
	view._art_nodes.append(_cycle_actor)
	view._actor_sprite.hide()
	view._sword_sprite.hide()
