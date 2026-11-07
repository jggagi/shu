extends RefCounted
## Small compiled recipe catalog. Production stays offline; runtime validates inputs.
const DEFAULT_PATH := "res://assets/data/martial_workshop/catalog.json"
const DEFAULT_VARIANTS_PATH := "res://assets/data/martial_workshop/control_variants.json"
const PATTERNS := {"sword": ["pierce", "sweep", "cleave"], "palm": ["pressure", "curve", "brace"]}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func load_catalog(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("武学目录不存在：" + path)
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _fail("武学目录不是 JSON 对象")
	var result := validate_catalog(parsed)
	if not result.ok:
		return result
	var catalog: Dictionary = parsed.duplicate(true)
	catalog["base_catalog_sha256"] = raw.sha256_text()
	catalog["catalog_sha256"] = raw.sha256_text()
	catalog["variant_catalog_sha256"] = ""
	if path == DEFAULT_PATH and FileAccess.file_exists(DEFAULT_VARIANTS_PATH):
		var variant_raw := FileAccess.get_file_as_string(DEFAULT_VARIANTS_PATH)
		var variant_data: Variant = JSON.parse_string(variant_raw)
		if not variant_data is Dictionary:
			return _fail("动作对照目录不是 JSON 对象")
		result = validate_variants(catalog, variant_data)
		if not result.ok:
			return result
		for entry: Dictionary in variant_data.variants:
			for move: Dictionary in catalog.moves:
				if str(move.id) == str(entry.move_id):
					if not move.has("variants"):
						move["variants"] = {}
					var variant: Dictionary = entry.move.duplicate(true)
					variant["variant_id"] = str(entry.variant_id)
					variant["variant_label"] = str(entry.variant_label)
					variant["description"] = str(entry.get("description", variant.get("description", "")))
					move.variants[str(entry.variant_id)] = variant
		catalog["variant_catalog_sha256"] = variant_raw.sha256_text()
		catalog["catalog_sha256"] = (raw + "\n" + variant_raw).sha256_text()
	return {"ok": true, "reason": "", "catalog": catalog}

static func validate_catalog(data: Dictionary, check_resources: bool = true) -> Dictionary:
	if int(data.get("schema_version", 0)) != 1:
		return _fail("不支持的武学目录版本")
	if not _finite_tree(data):
		return _fail("配方包含非有限数值")
	var profiles: Variant = data.get("profiles", {})
	var moves: Variant = data.get("moves", [])
	if not profiles is Dictionary or profiles.is_empty() or not moves is Array or moves.is_empty():
		return _fail("目录缺少角色骨架或招式")
	for profile_id: String in profiles:
		var profile: Variant = profiles[profile_id]
		if not profile is Dictionary or str(profile.get("actor", "")) not in ["player", "tinglan"]:
			return _fail("角色骨架定义不完整：" + profile_id)
		if profile.get("bone_names", []).size() != 22 or float(profile.get("rest_tolerance", 0.0)) <= 0.0 or float(profile.get("rest_tolerance", 1.0)) > 0.0001:
			return _fail("角色骨架必须声明现有 22 骨与严格 rest 容差")
		if check_resources:
			var resource_check := _resource(str(profile.get("source_asset", "")), str(profile.get("source_sha256", "")))
			if not resource_check.ok:
				return resource_check
	var seen := {}
	for move: Variant in moves:
		if not move is Dictionary:
			return _fail("招式必须是对象")
		var result := validate_move(move, profiles, check_resources)
		if not result.ok:
			return result
		var id := str(move.id)
		if seen.has(id):
			return _fail("重复招式 ID：" + id)
		seen[id] = true
		var variants: Variant = move.get("variants", {})
		if not variants is Dictionary:
			return _fail(id + "：动作版本必须是对象")
		for variant_id: String in variants:
			var checked := _validate_variant(move, variant_id, variants[variant_id], profiles, check_resources)
			if not checked.ok:
				return checked
	return {"ok": true, "reason": ""}

static func validate_move(move: Dictionary, profiles: Dictionary = {}, check_resources: bool = true) -> Dictionary:
	if not _finite_tree(move):
		return _fail("招式包含非有限数值")
	var id := str(move.get("id", ""))
	if id.is_empty() or not id.is_valid_identifier() or str(move.get("label", "")).is_empty():
		return _fail("招式缺少有效 ID 或名称")
	var category := str(move.get("category", ""))
	if not PATTERNS.has(category) or str(move.get("style", "")) not in ["light", "strong"]:
		return _fail(id + "：未知武学种类或劲路")
	var profile_id := str(move.get("profile", ""))
	if not profiles.has(profile_id):
		return _fail(id + "：未知角色骨架")
	var profile: Dictionary = profiles[profile_id]
	if str(move.get("actor", "")) != str(profile.get("actor", "")):
		return _fail(id + "：演员与骨架不匹配")
	var animation: Variant = move.get("animation", {})
	var timing: Variant = move.get("timing", {})
	var visual: Variant = move.get("visual", {})
	if not animation is Dictionary or not timing is Dictionary or not visual is Dictionary:
		return _fail(id + "：缺少动作、时间线或特效")
	var source := float(animation.get("source_seconds", 0.0))
	var duration := float(timing.get("duration", 0.0))
	var total := float(timing.get("total", 0.0))
	var release := float(timing.get("release", -1.0))
	var impact := float(timing.get("impact", -1.0))
	if source <= 0.0 or duration <= 0.0 or total < duration or total > 12.0 or release <= 0.0 or impact <= release or impact > duration:
		return _fail(id + "：时间线顺序或时长无效")
	var mapping: Variant = timing.get("source_map", [])
	if not mapping is Array or mapping.size() < 2:
		return _fail(id + "：缺少源动作时间映射")
	var previous := Vector2(-1.0, -1.0)
	for pair: Variant in mapping:
		if not pair is Array or pair.size() != 2:
			return _fail(id + "：时间映射必须是数值对")
		var point := Vector2(float(pair[0]), float(pair[1]))
		if point.x <= previous.x or point.y < previous.y or point.x > duration + 0.00001 or point.y > source + 0.00001 or point.y < 0.0:
			return _fail(id + "：时间映射必须单调且在动作范围内")
		previous = point
	if absf(float(mapping[0][0])) > 0.00001 or absf(float(mapping[0][1])) > 0.00001 or absf(previous.x - duration) > 0.00001 or absf(previous.y - source) > 0.00001:
		return _fail(id + "：时间映射端点不完整")
	var hand := str(animation.get("hand", "default"))
	if hand not in ["default", "palm"] or (hand == "palm" and not profile.get("hand_variants", {}).has(hand)):
		return _fail(id + "：骨架不支持该手型")
	if category == "palm" and (hand != "palm" or not profile.get("anchors", {}).has("palm")):
		return _fail(id + "：掌法需要开放掌与真实手部锚点")
	if str(visual.get("type", "")) != ("blade" if category == "sword" else "palm") or str(visual.get("pattern", "")) not in PATTERNS[category]:
		return _fail(id + "：特效与武学种类不匹配")
	var config: Variant = visual.get("config", {})
	if not config is Dictionary:
		return _fail(id + "：特效配置缺失")
	if not config.get("assets", {}) is Dictionary:
		return _fail(id + "：特效资源必须是对象")
	if category == "sword":
		for key: String in ["color", "core_color", "dust_color"]:
			if not Color.html_is_valid(str(config.get(key, ""))):
				return _fail(id + "：剑光颜色无效")
		for key: String in ["life_seconds", "width", "core_width"]:
			if float(config.get(key, 0.0)) <= 0.001 or float(config.get(key, 99.0)) > 3.0:
				return _fail(id + "：剑光尺寸或时长无效")
		if int(config.get("streak_count", 0)) < 1 or int(config.get("streak_count", 0)) > 32:
			return _fail(id + "：剑光尘线超出预算")
		if str(visual.pattern) in ["sweep", "cleave"] and (float(config.get("radius", 0.0)) <= 0.0 or float(config.get("radius", 9.0)) > 4.0 or float(config.get("span_degrees", 0.0)) <= 0.0 or float(config.get("span_degrees", 999.0)) > 180.0):
			return _fail(id + "：剑弧半径或角度无效")
	else:
		if not config.get("assets", {}) is Dictionary:
			return _fail(id + "：掌劲纹理必须是对象")
		for key: String in ["impact_seconds", "dust_seconds", "impact_size"]:
			if float(config.get(key, 0.0)) <= 0.0 or float(config.get(key, 99.0)) > 4.0:
				return _fail(id + "：掌劲尺寸或时长无效")
		for key: String in ["wind", "dust", "impact"]:
			if str(config.get("assets", {}).get(key, "")).is_empty():
				return _fail(id + "：掌劲缺少纹理 " + key)
		if absf(float(config.get("curve_amount", 0.0))) > 1.0 or float(config.get("hold_seconds", 0.0)) < 0.0 or float(config.get("hold_seconds", 0.0)) > 3.0:
			return _fail(id + "：掌劲曲率或持守时长超出预算")
	if str(animation.get("clip", "")).is_empty():
		return _fail(id + "：缺少动画片段名")
	var combat := str(move.get("combat_skill", ""))
	if (combat != "" and (combat not in ["pierce", "sweep"] or id != combat or bool(move.get("preview_only", true)))) or (combat == "" and not bool(move.get("preview_only", true))):
		return _fail(id + "：未接入结算的招式只能演武预览")
	if not move.get("camera", {}) is Dictionary or not move.get("audio", {}) is Dictionary or not move.get("resource_sha256", {}) is Dictionary:
		return _fail(id + "：镜头、声音或资源指纹必须是对象")
	var zoom := float(move.get("camera", {}).get("zoom", 0.0))
	if zoom < 0.4 or zoom > 1.5:
		return _fail(id + "：镜头缩放超出支持范围")
	if check_resources:
		for path: String in move.get("resource_sha256", {}):
			var resource_check := _resource(path, str(move.resource_sha256[path]))
			if not resource_check.ok:
				return resource_check
		var result := _resource(str(animation.get("asset", "")), str(animation.get("sha256", "")))
		if not result.ok:
			return result
		for texture_key: String in config.get("assets", {}):
			var path := str(config.assets[texture_key])
			result = _resource(path)
			if not result.ok:
				return result
			var texture := load(path) as Texture2D
			if texture == null or (category == "palm" and texture_key == "impact" and (texture.get_width() != 2048 or texture.get_height() != 1024)):
				return _fail(id + "：特效纹理格式或图集尺寸无效")
		for kind: String in ["release", "impact"]:
			var path := str(move.get("audio", {}).get(kind, ""))
			result = _resource(path)
			if not result.ok:
				return result
			var stream := load(path) as AudioStreamWAV
			if stream == null or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				return _fail(id + "：音效必须是无循环 WAV")
	return {"ok": true, "reason": ""}

static func _resource(path: String, sha: String = "") -> Dictionary:
	if (not path.begins_with("res://assets/") and not path.begins_with("res://generated/")) or path.contains("..") or not ResourceLoader.exists(path):
		return _fail("资源不存在或路径无效：" + path)
	# Exported imports are remapped resources. Raw source SHA is checked before export.
	if not sha.is_empty() and FileAccess.file_exists(path) and FileAccess.get_sha256(path) != sha:
		return _fail("资源 SHA256 不符：" + path)
	return {"ok": true, "reason": ""}

static func _finite_tree(value: Variant) -> bool:
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not _finite_tree(item):
				return false
	if value is Dictionary:
		for item: Variant in value.values():
			if not _finite_tree(item):
				return false
	return true

static func find_move(catalog: Dictionary, id: String, variant_id: String = "original") -> Dictionary:
	for move: Dictionary in catalog.get("moves", []):
		if str(move.id) != id:
			continue
		var result: Dictionary
		if variant_id == "original":
			result = move.duplicate(true)
			result.erase("variants")
			result["variant_id"] = "original"
			result["variant_label"] = "原版"
		elif move.get("variants", {}).has(variant_id):
			result = move.variants[variant_id].duplicate(true)
			result["variant_id"] = variant_id
		else:
			return {}
		return result
	return {}

static func validate_variants(base: Dictionary, data: Dictionary, check_resources: bool = true) -> Dictionary:
	var checked := validate_catalog(base, check_resources)
	if not checked.ok:
		return checked
	if int(data.get("schema_version", 0)) != 1 or not data.get("variants", []) is Array or not _finite_tree(data):
		return _fail("动作对照目录版本或格式无效")
	var base_sha := str(base.get("base_catalog_sha256", base.get("catalog_sha256", "")))
	if base_sha.is_empty() and FileAccess.file_exists(DEFAULT_PATH):
		base_sha = FileAccess.get_file_as_string(DEFAULT_PATH).sha256_text()
	if base_sha.length() != 64 or str(data.get("base_catalog_sha256", "")) != base_sha:
		return _fail("动作对照与原版目录指纹不匹配")
	var seen := {}
	for entry: Variant in data.variants:
		if not entry is Dictionary or not entry.get("move", {}) is Dictionary:
			return _fail("动作对照条目必须包含招式对象")
		var original := find_move(base, str(entry.get("move_id", "")))
		if original.is_empty():
			return _fail("动作对照引用了未知招式")
		var variant_id := str(entry.get("variant_id", ""))
		var key := str(original.id) + "@" + variant_id
		if seen.has(key) or str(entry.get("variant_label", "")).is_empty():
			return _fail("动作对照重复或缺少版本名称")
		seen[key] = true
		checked = _validate_variant(original, variant_id, entry.move, base.profiles, check_resources)
		if not checked.ok:
			return checked
	return {"ok": true, "reason": ""}

static func _validate_variant(original: Dictionary, variant_id: String, value: Variant, profiles: Dictionary, check_resources: bool) -> Dictionary:
	if variant_id == "original" or not variant_id.is_valid_identifier() or not value is Dictionary:
		return _fail("动作版本 ID 或对象无效")
	var variant: Dictionary = value
	if variant.has("variants"):
		return _fail("动作版本不能再次嵌套版本")
	var checked := validate_move(variant, profiles, check_resources)
	if not checked.ok:
		return checked
	for field: String in ["id", "label", "category", "style", "actor", "profile", "timing", "visual", "audio", "camera"]:
		if variant.get(field) != original.get(field):
			return _fail(str(original.id) + "：同刻动作对照必须保持 " + field)
	if not bool(variant.get("preview_only", false)) or not str(variant.get("combat_skill", "")).is_empty() or not str(original.get("combat_skill", "")).is_empty():
		return _fail("动作增强仅供试演，不能改变战斗映射")
	if float(variant.animation.source_seconds) != float(original.animation.source_seconds) or str(variant.animation.get("hand", "default")) != str(original.animation.get("hand", "default")):
		return _fail("动作版本必须保持原始时长与手型")
	if str(variant.animation.asset) == str(original.animation.asset) and str(variant.animation.clip) == str(original.animation.clip):
		return _fail("动作增强必须有独立片段")
	return {"ok": true, "reason": ""}
