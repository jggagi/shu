extends SceneTree
## Large-map host tests use only ordinary walking/action/restore APIs. No UI claim.

const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const Session = preload("res://addons/cultivation_mode/session.gd")
const Store = preload("res://addons/cultivation_mode/save_store.gd")
const Navigation = preload("res://addons/cultivation_mode/town_navigation.gd")
const CITY := "chengdu_city"
const TEA := "chengdu_teahouse"
const LAYOUT := "res://assets/data/chengdu-large-layout.json"
var checks := 0
var failures := 0
var pack: Dictionary = {}
var regions: Array = []
var operation := 0
var save_dir := ""
var nav: RefCounted
var navigation_samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_chengdu_large/game.json")
	check(loaded.ok, "actual large-map content package loads: " + str(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	pack = loaded.pack
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	check(layout is Dictionary, "large-map presentation layout is readable")
	if not layout is Dictionary:
		_finish()
		return
	regions = layout.get("regions", [])
	# Layout may group presentation under scenes while the logical map stays flat.
	if regions.is_empty():
		regions = layout.get("scenes", {}).get(CITY, {}).get("regions", [])
	save_dir = "user://test_runs/chengdu-large-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	nav = Navigation.new()
	var configure_started := Time.get_ticks_usec()
	nav.configure(pack.walks.scenes[CITY])
	navigation_samples.append({"kind": "large_grid_configure", "milliseconds": float(Time.get_ticks_usec() - configure_started) / 1000.0})
	_test_authored_map()
	if failures == 0:
		_test_continuous_walking_and_doorways()
		_test_optional_umbrella_and_checkpoint()
	_test_old_packages()
	_finish()

func _new() -> RefCounted:
	var session = Session.new()
	check(session.configure(pack).ok, "existing Session configures the large content package")
	check(session.select_action("go_to_town").ok and session.acknowledge_result().ok, "ordinary paid journey reaches the large city")
	check(session.snapshot().scene == CITY, "all outdoor regions share one actual scene")
	return session

func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _coords(value: Array) -> Array:
	return [int(value[0]), int(value[1])]

func _test_authored_map() -> void:
	check(pack.id == "shu_chengdu_large" and pack.version == "0.5.0", "large candidate has explicit isolated content identity")
	check(pack.walks.scenes.size() == 2 and pack.walks.scenes.has(CITY) and pack.walks.scenes.has(TEA), "five outdoor regions use one map plus the existing tea interior")
	var map: Dictionary = pack.walks.scenes[CITY]
	check(int(map.size[0]) >= 3840 and int(map.size[1]) >= 2160, "world area exceeds the fixed rendering window in both dimensions")
	check(regions.size() == 5, "five authored outdoor regions exist inside the same scene")
	var ids := {}
	var origins: Array = [map.spawn]
	for entry: String in map.entries:
		origins.append(map.entries[entry])
	for region: Dictionary in regions:
		var id := str(region.get("id", ""))
		check(not id.is_empty() and not ids.has(id), "outdoor region identifiers are unique")
		ids[id] = true
		var at: Array = region.get("visit_point", [])
		check(at.size() == 2, "region has an independently reachable walk-test landmark: " + id)
		if at.size() != 2:
			continue
		var bounds: Array = region.get("bounds", [])
		check(bounds.size() == 4 and Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])).has_point(_point(at)), "region landmark lies in its own spatial district: " + id)
		check(not nav.blocked(_point(at)), "region landmark is real walkable ground: " + id)
		origins.append(at)
	# Check every authored destination without a redundant all-pairs path matrix.
	for origin: Array in origins:
		check(not _route(nav, _point(map.spawn), _point(origin), 0.0).is_empty(), "default arrival can reach every authored entrance/region")
	for iid: String in map.interactions:
		var item: Dictionary = map.interactions[iid]
		check(not _route(nav, _point(map.spawn), _point(item.position), float(item.radius)).is_empty(), "large-map arrival can reach actual interaction: " + iid)
	for iid: String in map.interactions:
		var action: Dictionary = pack.actions[map.interactions[iid].action]
		check(str(action.get("target_scene", "")) in ["", TEA, "tingyu_corridor"], "walking outdoors never uses hidden district scene transitions: " + iid)
	for aid: String in ["enter_teahouse", "enter_teahouse_back", "leave_teahouse", "leave_teahouse_back"]:
		var action: Dictionary = pack.actions[aid]
		check(not bool(action.menu) and int(action.duration) == 0 and action.costs.is_empty(), "both tea doors are free spatial actions: " + aid)
		check(action.conditions.get("flags", {}).is_empty() and action.conditions.get("stats_gte", {}).is_empty(), "neither tea doorway is gated by tasks or cultivation: " + aid)
	check(pack.actions.leave_teahouse.target_entry == "from_teahouse_front" and pack.actions.leave_teahouse_back.target_entry == "from_teahouse_back", "two interior exits name different outdoor arrivals")
	check(map.entries.from_teahouse_front != map.entries.from_teahouse_back, "front and back doors actually return to different world positions")

func _walk(session: RefCounted, destination: Vector2, radius: float = 0.0) -> bool:
	var before: Dictionary = session.snapshot()
	var sid := str(before.scene)
	var map: Dictionary = pack.walks.scenes[sid]
	var navigation = Navigation.new()
	var configure_started := Time.get_ticks_usec()
	navigation.configure(map)
	navigation_samples.append({"kind": "grid_configure", "scene": sid, "milliseconds": float(Time.get_ticks_usec() - configure_started) / 1000.0})
	var path: Array = _route(navigation, _point(before.exploration.positions[sid]), destination, radius)
	check(not path.is_empty(), "far world destination is reachable through real navigation")
	for next: Vector2 in path:
		var state: Dictionary = session.snapshot()
		var result: Dictionary = session.commit_walk_position(sid, [roundi(next.x), roundi(next.y)], state.run_id, state.revision)
		if not result.ok:
			check(false, "every far walk commits a legal integer segment")
			return false
	var after: Dictionary = session.snapshot()
	check(after.scene == sid and after.day == before.day and after.slot == before.slot and after.stats == before.stats and after.flags == before.flags and after.sequence == before.sequence and after.counts == before.counts and after.receipts == before.receipts and after.journal == before.journal, "long outdoor walking changes only position and revision, with no scene, action or clock settlement")
	return not path.is_empty()

func _route(navigation: RefCounted, from: Vector2, to: Vector2, radius: float) -> Array:
	var started := Time.get_ticks_usec()
	var path: Array = navigation.route(from, to, radius)
	navigation_samples.append({"kind": "route", "from": [from.x, from.y], "to": [to.x, to.y], "radius": radius,
		"waypoints": path.size(), "milliseconds": float(Time.get_ticks_usec() - started) / 1000.0})
	return path

func _interact(session: RefCounted, id: String) -> Dictionary:
	var map: Dictionary = pack.walks.scenes[session.snapshot().scene]
	var item: Dictionary = map.interactions[id]
	if not _walk(session, _point(item.position), float(item.radius)):
		return {"ok": false}
	operation += 1
	var state: Dictionary = session.snapshot()
	return session.execute_walk_interaction(id, "large-test-%d" % operation, state.run_id, state.revision)

func _door(session: RefCounted, id: String, target: String, entry: String) -> bool:
	var before: Dictionary = session.snapshot()
	var result := _interact(session, id)
	check(result.get("ok", false), "ordinary spatial doorway enters correctly: " + id)
	if not result.get("ok", false):
		return false
	var after: Dictionary = session.snapshot()
	check(after.scene == target and after.exploration.positions[target] == _coords(pack.walks.scenes[target].entries[entry]), "door preserves the exact designed return side: " + id)
	check(after.day == before.day and after.slot == before.slot and after.stats == before.stats and after.flags == before.flags, "doorway never adds travel fees or changes task flags: " + id)
	check(session.execute_walk_interaction(id, str(result.operation_id), after.run_id, -1).get("duplicate", false) and session.snapshot() == after, "duplicate doorway callback cannot settle or teleport again")
	check(session.acknowledge_result().ok, "host doorway result releases safe walking")
	return true

func _test_continuous_walking_and_doorways() -> void:
	var session := _new()
	var before: Dictionary = session.snapshot()
	var rejected: Dictionary = session.select_action("enter_teahouse", "menu-bypass")
	check(not rejected.ok and session.snapshot() == before, "ordinary menu cannot bypass a distant spatial doorway")
	rejected = session.execute_walk_interaction("market_teahouse_door", "far-door", before.run_id, before.revision)
	check(not rejected.ok and session.snapshot() == before, "large-map distance gate rejects a far door atomically")
	for region: Dictionary in regions:
		if not _walk(session, _point(region.visit_point)):
			return
	check(session.snapshot().scene == CITY and session.snapshot().sequence == before.sequence, "all five outdoor regions are traversed without an action or scene transition")
	# Both real routes cross the world using different north/south corridors.
	var route_paths: Array = []
	for route: Array in [
		[[440, 1760], [440, 1700], [3280, 1700]],
		[[440, 1760], [260, 1760], [260, 1020], [1020, 1020], [1940, 1020], [2720, 1020], [3280, 1020]]]:
		var touched: Array = []
		for raw: Array in route:
			check(_walk(session, _point(raw)), "authored alternate corridor is traversable")
			touched.append(_coords(session.snapshot().exploration.positions[CITY]))
		route_paths.append(touched)
	check(route_paths.size() == 2 and route_paths[0] != route_paths[1], "north lane/square route and south market route are distinct real world walks")
	if not _door(session, "market_teahouse_door", TEA, "from_market") or not _door(session, "tea_lanes_exit", CITY, "from_teahouse_back"):
		return
	if not _door(session, "lanes_teahouse_door", TEA, "from_lanes") or not _door(session, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	check(session.snapshot().size() == 15 and session.snapshot().exploration.positions.size() == 2, "large map keeps strict fifteen fields and only two persisted map positions")

func _finish_reading(session: RefCounted) -> void:
	for _step: int in range(12):
		var state: Dictionary = session.snapshot()
		if state.phase == "ready":
			return
		if state.phase == "result":
			check(session.acknowledge_result().ok, "explicit reading result ends safely")
		elif state.phase == "event" and session.event_view().get("type", "") in ["say", "end"]:
			check(session.continue_event().ok, "authored read/end continuation succeeds")
		else:
			check(false, "event choices require an explicit chosen option")
			return
	check(false, "reading finishes within its authored finite event graph")

func _test_optional_umbrella_and_checkpoint() -> void:
	var session := _new()
	check(_interact(session, "river_umbrella").get("ok", false) and session.choose("take", "take-once").ok, "large-map umbrella is deliberately collected through its registered choice")
	_finish_reading(session)
	for raw: Array in [[3280, 1020], [2720, 1020], [1940, 1020]]:
		if not _walk(session, _point(raw)):
			return
	var saved: Dictionary = session.snapshot()
	var store = Store.new()
	store.base_dir = save_dir
	check(store.save_session(session).ok, "safe large-world checkpoint writes in an isolated store")
	var reader = Session.new()
	check(reader.configure(pack).ok and store.load_session(reader).ok and reader.snapshot() == saved, "JSON reload restores exact far coordinates, flags, clock, counts and receipts")
	for kind: String in ["fraction", "outside", "obstacle", "missing_map", "old_region_map"]:
		var bad := saved.duplicate(true)
		match kind:
			"fraction": bad.exploration.positions[CITY][0] = 1940.25
			"outside": bad.exploration.positions[CITY] = [100000, 100000]
			"obstacle":
				var box: Array = pack.walks.scenes[CITY].obstacles[0]
				bad.exploration.positions[CITY] = [int(box[0]) + int(box[2]) / 2, int(box[1]) + int(box[3]) / 2]
			"missing_map": bad.exploration.positions.erase(CITY)
			"old_region_map": bad.exploration.positions["chengdu_market"] = [180, 480]
		var previous: Dictionary = reader.snapshot()
		check(not reader.restore(bad).ok and reader.snapshot() == previous, "strict restoration rejects invalid large-world position atomically: " + kind)
	if not _door(reader, "lanes_teahouse_door", TEA, "from_lanes"):
		return
	check(_interact(reader, "tea_lost_property").get("ok", false) and reader.choose("return", "return-once").ok, "alternate north route returns the original umbrella at the existing stand")
	_finish_reading(reader)
	if not _door(reader, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	check(_interact(reader, "river_umbrella").get("ok", false), "far revisit keeps the world interaction available")
	var available_take := false
	for option: Dictionary in reader.event_view().get("options", []):
		if option.id == "take" and bool(option.get("enabled", false)):
			available_take = true
	check(not available_take and reader.choose("returned", "remember").ok, "return consequence is remembered and pickup cannot repeat")
	_finish_reading(reader)
	var final: Dictionary = reader.snapshot()
	check(final.flags.chengdu_umbrella_returned and not final.flags.chengdu_umbrella_carrying and int(final.counts.get("take_river_umbrella", 0)) == 1 and int(final.counts.get("return_river_umbrella", 0)) == 1, "large-world alternate route preserves unique umbrella pickup/return")
	check(final.slot == 1 and final.day == 1 and int(final.stats.energy) == 100, "all large-world walking and the optional task remain free")

func _test_old_packages() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu/source.json"))
	if source is Dictionary:
		for name: String in source.get("inherited_json_sha256", {}):
			check(FileAccess.get_sha256("res://games/shu_town_walk/" + name) == str(source.inherited_json_sha256[name]), "original town data remains byte-identical: " + name)
	for manifest: String in ["res://games/shu_chengdu/game.json", "res://games/shu_mentor_loop/game.json", "res://games/stream_study/game.json"]:
		var loaded: Dictionary = Loader.new().load_pack(manifest)
		check(loaded.ok, "retained earlier package still loads: " + manifest)
		if loaded.ok:
			var session = Session.new()
			check(session.configure(loaded.pack).ok, "retained package configures under the same runtime")
			var state: Dictionary = session.snapshot()
			if loaded.pack.id == "shu_chengdu":
				check(state.exploration.positions.size() == 6 and not state.exploration.positions.has(CITY), "six-map candidate retains its own exact map identity")
			else:
				check(state.size() == 14 and not state.has("exploration"), "non-walking package remains strict fourteen-field state")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	var path := "res://.local/qa/chengdu-large/state/navigation-timing.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": navigation_samples,
			"scope": "headless CPU navigation timings on this host; not UI frame rate or cross-device performance"}, "\t") + "\n")
		file.close()
	print("CULTIVATION_ENGINE_CHENGDU_LARGE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
