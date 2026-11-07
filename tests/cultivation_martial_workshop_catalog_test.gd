extends SceneTree
## Public catalog contract and protected authority boundaries; no graphics context.
const Catalog := preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const CATALOG_PATH := "res://assets/data/martial_workshop/catalog.json"
const IDS := ["pierce", "sweep", "palm_gale", "sword_cleave", "palm_cloud", "palm_brace"]
const EXPECTED := {
	"pierce": ["CloudPierce", "pierce", "player", "jiang22"],
	"sweep": ["ReturningSweep", "sweep", "player", "jiang22"],
	"palm_gale": ["TinglanPalm", "pressure", "tinglan", "tinglan22"],
	"sword_cleave": ["SwordCleave", "cleave", "player", "jiang22"],
	"palm_cloud": ["PalmCloud", "curve", "tinglan", "tinglan22"],
	"palm_brace": ["PalmBrace", "brace", "tinglan", "tinglan22"],
}
# The approved sword/palm combat slice updates only encounter data and its
# gamepack pin; workshop presentation still cannot modify these authorities.
const PROTECTED := {
	"res://addons/cultivation_mode/ambush_rules.gd": "0253ca749018ed2bb38f1730616c9dc26aee86c644a6a02e55cb2589dee73d6e",
	"res://addons/cultivation_mode/ambush_session.gd": "fb8fc2312e2fcb6f68d5422a958410c19150a2a774a4fcd3dc4b99895b4fbcfa",
	"res://addons/cultivation_mode/session.gd": "e10a907af0128ca3ff4b8901278faabed64309232dae67b19d44a40128bebbcf",
	"res://addons/cultivation_mode/save_store.gd": "b674803a87ca6aea656119d3674e8af74fe9f45984a038ca715a1c22be00653a",
	"res://games/shu_mountain_ambush/encounter.json": "2bd455f9676073d377021cc6e8c6e8e4455dd72a1f182d1a188dfc5edad1c7d2",
	"res://games/shu_mountain_ambush/game.json": "e690a0c9a0cbfbccb338be34bf45ded8d12d7d491e73debce80b33a39c1a86f8",
	"res://games/shu_mountain_ambush/rules.json": "e3dfc6d886d7e39873be31fb22c50a4f7f873148c3f13cdd7eccf1c2b4339a37",
}
var checks := 0
var failures: Array[String] = []
var base: Dictionary = {}
var rejected: Array[Dictionary] = []
var output := "res://.local/qa/martial-workshop/catalog"
var _fixture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	base = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var before := base.duplicate(true)
	var loaded: Dictionary = Catalog.load_catalog(CATALOG_PATH)
	_check(bool(loaded.get("ok", false)), "The authored six-move catalog loads with real resource checks: " + str(loaded.get("reason", "")))
	_check(base == before, "Loading cannot mutate the parsed recipe input")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_check(bool(Catalog.validate_catalog(base, true).get("ok", false)), "The public validator accepts the authored catalog independently of loading")
	_check_authored()
	_check_invalid_catalogs()
	_check_resource_rejections()
	_check_hash_revision(loaded.catalog)
	for path: String in PROTECTED:
		_check(FileAccess.get_sha256(path) == PROTECTED[path], "Workshop preserves the frozen authoritative file " + path.get_file())
	_check(base == before, "All valid and invalid validation calls leave the source recipe unchanged")
	_finish()


func _check_authored() -> void:
	var actual_ids: Array = []
	var clips: Array[String] = []
	var patterns: Array[String] = []
	for move: Dictionary in base.moves:
		var id := str(move.id)
		actual_ids.append(id)
		_check(EXPECTED.has(id), "Catalog contains a planned stable move ID " + id)
		if not EXPECTED.has(id):
			continue
		var expected: Array = EXPECTED[id]
		_check([move.animation.clip, move.visual.pattern, move.actor, move.profile] == expected, id + " binds its own clip, shape and matching actor profile")
		_check(bool(move.preview_only) == (id not in ["pierce", "sweep"]) and str(move.combat_skill) == (id if id in ["pierce", "sweep"] else ""), id + " carries only the approved existing combat binding")
		_check(bool(Catalog.validate_move(move, base.profiles, true).get("ok", false)), id + " passes the standalone public move validation")
		clips.append(str(move.animation.asset) + "::" + str(move.animation.clip))
		patterns.append(str(move.visual.pattern))
	_check(actual_ids == IDS, "Exactly three migrated and three new moves retain their stable ordering")
	_check(_unique(clips).size() == 6 and _unique(patterns).size() == 6, "Six moves have six actual clip bindings and six effect patterns, not six renamed IDs")
	_check((base.profiles as Dictionary).keys().size() == 2, "v0.1 admits only the two tested actor profiles")
	for profile: Dictionary in base.profiles.values():
		_check((profile.bone_names as Array).size() == 22 and _unique(profile.bone_names).size() == 22, "Each tested profile declares 22 unique original bone names")
		_check(int(profile["import"].fps) == 100 and not bool(profile["import"].optimizer) and not bool(profile["import"].remove_immutable_tracks), "Profile preserves dense animation import and required rest tracks")


func _check_invalid_catalogs() -> void:
	_reject_path(["schema_version"], 999, "Unknown catalog schema")
	_reject_path(["moves"], [], "Empty catalog")
	var duplicated := base.duplicate(true)
	duplicated.moves.append(duplicated.moves[0].duplicate(true))
	_reject(duplicated, "Duplicate stable move ID")
	_reject_path(["moves", 0, "id"], "", "Empty stable ID")
	_reject_path(["moves", 0, "category"], "staff", "Unsupported weapon category")
	_reject_path(["moves", 0, "style"], "unknown", "Unsupported style")
	_reject_path(["moves", 0, "profile"], "missing_rig", "Unknown rig profile")
	_reject_path(["moves", 0, "actor"], "tinglan", "Actor and rig profile mismatch")
	_reject_path(["moves", 0, "animation", "hand"], "missing_hand", "Undeclared hand variant")
	_reject_path(["moves", 3, "combat_skill"], "sword_cleave", "Preview-only new move cannot register new combat damage")
	_reject_path(["moves", 2, "preview_only"], false, "Pure presentation cannot become a new playable palm rule")
	_reject_path(["moves", 0, "timing", "duration"], 0.0, "Zero body duration")
	_reject_path(["moves", 0, "timing", "release"], -0.1, "Negative release event")
	_reject_path(["moves", 0, "timing", "release"], 0.0, "Release cannot bypass the authored windup")
	_reject_path(["moves", 0, "timing", "impact"], float(base.moves[0].timing.release), "Impact cannot collapse onto release")
	_reject_path(["moves", 0, "timing", "impact"], 0.1, "Impact before release")
	_reject_path(["moves", 0, "timing", "total"], 0.2, "Effect total ends before impact or body recovery")
	_reject_path(["moves", 0, "timing", "duration"], INF, "Infinite body duration")
	_reject_path(["moves", 0, "timing", "release"], NAN, "NaN event time")
	_reject_path(["moves", 0, "timing", "source_map"], [[0.0, 0.0], [0.5, 0.2], [0.4, 0.25], [0.85, 0.32]], "Time map runs backwards in presentation seconds")
	_reject_path(["moves", 0, "timing", "source_map"], [[0.0, 0.0], [0.4, 0.25], [0.5, 0.2], [0.85, 0.32]], "Time map runs backwards in authored clip seconds")
	_reject_path(["moves", 0, "timing", "source_map"], [[0.1, 0.0], [0.85, 0.32]], "Time map omits the initial presentation endpoint")
	_reject_path(["moves", 0, "timing", "source_map"], [[0.0, 0.0], [0.85, 0.2]], "Time map omits full authored recovery")
	_reject_path(["moves", 0, "visual", "type"], "unknown", "Unknown renderer family")
	_reject_path(["moves", 0, "visual", "pattern"], "unknown", "Unknown effect pattern")
	_reject_path(["moves", 0, "visual", "type"], "palm", "Sword motion cannot use a palm renderer contract")
	_reject_path(["moves", 0, "visual", "config"], {}, "Missing required renderer parameters")
	_reject_path(["moves", 0, "visual", "config", "life_seconds"], 0.0, "Zero blade lifetime cannot reach renderer division")
	_reject_path(["moves", 0, "visual", "config", "streak_count"], 1000000, "Unbounded streak budget cannot reach mesh generation")
	_reject_path(["moves", 2, "visual", "config", "impact_seconds"], 0.0, "Zero atlas duration cannot reach frame division")
	_reject_path(["moves", 0, "camera", "zoom"], 0.0, "Nonpositive camera scale")


func _check_resource_rejections() -> void:
	_reject_path(["profiles", "jiang22", "source_asset"], "res://assets/%s.glb" % "missing-character", "Missing source character")
	_reject_path(["profiles", "jiang22", "source_sha256"], "0".repeat(64), "Changed source rig fingerprint")
	_reject_path(["moves", 0, "animation", "asset"], "res://assets/%s.glb" % "missing-motion", "Missing baked motion resource")
	_reject_path(["moves", 0, "animation", "sha256"], "0".repeat(64), "Changed baked motion fingerprint")
	_reject_path(["moves", 0, "audio", "release"], "res://assets/%s.wav" % "missing-release", "Missing release sound")
	_reject_path(["moves", 0, "audio", "impact"], "res://assets/data/martial_workshop/catalog.json", "Non-WAV impact sound")
	var cue_path := str(base.moves[0].audio.release)
	_reject_path(["moves", 0, "resource_sha256", cue_path], "0".repeat(64), "Changed sound resource fingerprint")
	# Real bone rest/clip lookup is ActorBinding's responsibility. The UI suite
	# plays the real six clips; this catalog test does not fake that proof.


func _check_hash_revision(loaded: Dictionary) -> void:
	var original_hash := str(loaded.get("catalog_sha256", ""))
	_check(original_hash.length() == 64, "Loaded catalog exposes its complete review/cache revision fingerprint")
	_fixture_dir = "user://martial-workshop-catalog-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_fixture_dir)) == OK, "Catalog hash fixture gets an isolated temporary directory")
	var path := _fixture_dir.path_join("catalog.json")
	var revised := base.duplicate(true)
	revised.moves[0].description = str(revised.moves[0].description) + " QA revision"
	_write_json(path, revised)
	var result: Dictionary = Catalog.load_catalog(path)
	_check(bool(result.get("ok", false)) and str(result.get("catalog", {}).get("catalog_sha256", "")) != original_hash, "A recipe revision cannot reuse a prior catalog review fingerprint")
	var first_hash := str(result.get("catalog", {}).get("catalog_sha256", ""))
	var repeated: Dictionary = Catalog.load_catalog(path)
	_check(bool(repeated.get("ok", false)) and str(repeated.get("catalog", {}).get("catalog_sha256", "")) == first_hash, "The identical recipe/resources produce the identical catalog fingerprint")
	var invalid: Dictionary = Catalog.load_catalog(_fixture_dir.path_join("missing.json"))
	_check(not bool(invalid.get("ok", true)) and not str(invalid.get("reason", "")).is_empty(), "Missing catalog is a reported rejection, not an empty successful workshop")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_dir))


func _reject_path(path: Array, value: Variant, label: String) -> void:
	var data := base.duplicate(true)
	var cursor: Variant = data
	for i: int in range(path.size() - 1):
		cursor = cursor[path[i]]
	cursor[path[-1]] = value
	_reject(data, label)


func _reject(data: Dictionary, label: String) -> void:
	# NaN is deliberately not compared with itself; its rejection is checked.
	var result: Dictionary = Catalog.validate_catalog(data, true)
	_check(not bool(result.get("ok", true)) and not str(result.get("reason", "")).is_empty(), label + " is rejected with a usable reason")
	rejected.append({"case": label, "rejected": not bool(result.get("ok", true)), "reason": result.get("reason", "")})


func _unique(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if value not in result:
			result.append(value)
	return result


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "The isolated catalog fixture is writable")
	if file != null:
		file.store_string(JSON.stringify(data, "\t") + "\n")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)


func _finish() -> void:
	var report := {"test": "martial_workshop_catalog", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "catalog": CATALOG_PATH, "catalog_file_sha256": FileAccess.get_sha256(CATALOG_PATH), "rejections": rejected, "boundary": "CPU catalog/schema/resource/authority checks. Runtime ActorBinding skeleton/clip and rendered UI have separate evidence."}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("MARTIAL WORKSHOP CATALOG: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
