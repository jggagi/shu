extends "res://tests/cultivation_engine_chengdu_large_test.gd"
## Reference-map acceptance uses the existing Session and actual navigation.
## The directional expectations below come from the supplied drawing, not from
## a historical survey. Shared walking/save helpers stay in the large-map test.

const ReferenceLayout := "res://assets/data/chengdu-reference-layout.json"
const OldDigests := {
	"shu_chengdu": "fe71edf17d39583512b1bfdb7d3766bdfd5527e5f52baa324801e67f30ace92b",
	"shu_chengdu_large": "4c27e416e44b059873db4fe0a83b1cfba0cc14a323f619bffa78cbba49e902c4"}
var reference_layout: Dictionary = {}
var authored_routes: Dictionary = {}
var solids: Dictionary = {}

func _run() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_chengdu_reference/game.json")
	check(loaded.ok, "actual reference-map package loads: " + str(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	pack = loaded.pack
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(ReferenceLayout))
	check(raw is Dictionary, "reference composition is readable")
	if not raw is Dictionary:
		_finish()
		return
	reference_layout = raw.get("scenes", {}).get(CITY, {})
	regions = reference_layout.get("regions", [])
	authored_routes = reference_layout.get("route_waypoints", {})
	save_dir = "user://test_runs/chengdu-reference-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	nav = Navigation.new()
	var started := Time.get_ticks_usec()
	nav.configure(pack.walks.scenes[CITY])
	navigation_samples.append({"kind": "reference_grid_configure", "milliseconds": float(Time.get_ticks_usec() - started) / 1000.0})
	_test_reference_geometry()
	_test_authored_destinations()
	_test_planning_extremes()
	if failures == 0:
		_test_reference_routes_and_doors()
		_test_reference_umbrella_checkpoint()
	_test_old_packages()
	_finish()

func _box(raw: Array) -> Rect2:
	return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))

func _center(id: String) -> Vector2:
	return _box(solids[id].bounds).get_center()

func _test_reference_geometry() -> void:
	check(pack.id == "shu_chengdu_reference" and pack.version == "0.6.0", "reference city has an independent content identity")
	check(pack.walks.scenes.size() == 2 and pack.walks.scenes.has(CITY) and pack.walks.scenes.has(TEA), "reference city remains one continuous outdoor map plus the original tea room")
	var map: Dictionary = pack.walks.scenes[CITY]
	check(_coords(map.size) == [5120, 3840], "reference world has the agreed larger dimensions")
	check(map.obstacles.size() <= 64 and map.interactions.size() <= 16, "larger composition fits existing spatial-contract limits")
	for item: Dictionary in reference_layout.get("buildings", []):
		solids[str(item.id)] = item
		check(map.obstacles.has(item.bounds), "drawn solid has the same blocking footprint: " + str(item.id))
	check(solids.size() == map.obstacles.size(), "every authored obstacle has visible geometry")
	for id: String in ["mohe_pool", "inner_palace", "xinxiang_temple", "sanhua_tower", "wenweng_academy", "daci_temple", "dufu_cottage", "qingyang_palace", "wuhou_shrine", "hejiang_pavilion", "weaving_workshops", "teahouse"]:
		check(solids.has(id), "reference landmark exists: " + id)
	if failures > 0:
		return
	check(_center("mohe_pool").x < _center("inner_palace").x and _center("mohe_pool").y > _center("inner_palace").y, "Mohe pond lies southwest of the northern inner precinct")
	check(_center("xinxiang_temple").y < _center("inner_palace").y, "Xinxiang temple lies north of the inner precinct")
	check(_center("sanhua_tower").x > _center("mohe_pool").x and _center("daci_temple").x > _center("inner_palace").x, "Sanhua stands east of the pond and Daci occupies the eastern city")
	var school := _center("wenweng_academy")
	check(school.x > 1160 and school.x < 2460 and school.y > _center("mohe_pool").y and school.y < 2780, "Wenweng school sits southwest inside the outer walls")
	check(_center("dufu_cottage").x < 1100 and _center("qingyang_palace").x < 1100 and _center("wuhou_shrine").x < 1100, "cottage, Qingyang and Wuhou remain outside the western wall")
	check(_center("dufu_cottage").y < _center("qingyang_palace").y and _center("wuhou_shrine").y > 3270, "western landmarks retain their north/south order and Wuhou lies across the southern river")
	check(_center("hejiang_pavilion").x > 4060 and _center("hejiang_pavilion").y > 2780 and _center("weaving_workshops").y > 3270, "Hejiang marks the southeast riverside and weaving workshops occupy the southern bank")
	check(_point(map.spawn).x == 2600 and _point(map.spawn).y > 3270, "ordinary arrival starts south of Wanli bridge")
	# These independent crossing samples detect decorative bridges accidentally
	# left over a solid river/wall rectangle, and accidental unrestricted water.
	for crossing: Array in [
		["Wanli bridge", Vector2(2600, 3360), Vector2(2600, 2920)],
		["south gate", Vector2(2600, 2920), Vector2(2600, 2700)],
		["east gate and Qingyuan bridge", Vector2(4260, 1900), Vector2(4900, 1900)],
		["Huanhua footbridge", Vector2(700, 1460), Vector2(960, 1460)],
		["west gate", Vector2(980, 2150), Vector2(1240, 2150)],
		["southeast water gate", Vector2(4180, 2700), Vector2(4180, 2980)]]:
		check(nav.clear_segment(crossing[1], crossing[2]), "bridge/gate has a real radius-safe walk corridor: " + str(crossing[0]))
	for point: Vector2 in [Vector2(2400, 3150), Vector2(4640, 1700), Vector2(830, 1200), Vector2(1900, 1800), Vector2(2300, 2810), Vector2(1130, 1700)]:
		check(nav.blocked(point), "water, pond and wall remain solid away from their designed crossings")
	check(not nav.clear_segment(Vector2(2400, 3360), Vector2(2400, 2920)), "southern river cannot be crossed alongside the bridge")
	check(nav.clear_segment(Vector2(2600, 3360), Vector2(2600, 1510)), "Wanli bridge and south gate align with the continuous northbound city avenue")

func _test_authored_destinations() -> void:
	var map: Dictionary = pack.walks.scenes[CITY]
	check(regions.size() == 11, "eleven visible districts cover the reference city and western outskirts")
	var ids := {}
	for region: Dictionary in regions:
		var id := str(region.id)
		var destination := _point(region.visit_point)
		check(not ids.has(id) and _box(region.bounds).has_point(destination), "district has a unique walkable visit point inside its own bounds: " + id)
		ids[id] = true
		check(not nav.blocked(destination) and not _route(nav, _point(map.spawn), destination, 0).is_empty(), "ordinary arrival reaches the real district: " + id)
	for entry: String in map.entries:
		check(not _route(nav, _point(map.spawn), _point(map.entries[entry]), 0).is_empty(), "named reference arrival joins the same navigation network: " + entry)
	for iid: String in map.interactions:
		var item: Dictionary = map.interactions[iid]
		check(not _route(nav, _point(map.spawn), _point(item.position), float(item.radius)).is_empty(), "ordinary arrival reaches actual landmark/door interaction: " + iid)
		var action: Dictionary = pack.actions[item.action]
		check(str(action.get("target_scene", "")) in ["", TEA, "tingyu_corridor"], "outdoor landmarks do not secretly transition between city scenes: " + iid)
	for route_id: String in authored_routes:
		var points: Array = authored_routes[route_id]
		var clear := points.size() >= 2
		for index: int in range(1, points.size()):
			clear = clear and nav.clear_segment(_point(points[index - 1]), _point(points[index]))
		check(clear, "authored street route consists of genuinely clear connected ground: " + route_id)
	for aid: String in ["enter_teahouse", "enter_teahouse_back", "leave_teahouse", "leave_teahouse_back"]:
		var action: Dictionary = pack.actions[aid]
		check(not bool(action.menu) and int(action.duration) == 0 and action.costs.is_empty() and action.conditions.get("flags", {}).is_empty() and action.conditions.get("stats_gte", {}).is_empty(), "both tea doors stay free spatial actions without cultivation or task unlocks: " + aid)
	check(pack.actions.leave_teahouse.target_entry == "from_teahouse_front" and pack.actions.leave_teahouse_back.target_entry == "from_teahouse_back", "tea exits retain different outdoor arrival identities")
	check(map.entries.from_teahouse_front != map.entries.from_teahouse_back, "tea exits lead to genuinely different outdoor coordinates")

func _test_planning_extremes() -> void:
	# Record distant ordinary and interaction targets separately. Timing is
	# evidence for this host, never a device-independent performance assertion.
	for sample: Array in [
		[Vector2(520, 1390), Vector2(4900, 2700), 0.0],
		[Vector2(660, 3650), Vector2(3830, 2110), 58.0],
		[Vector2(3440, 3670), Vector2(520, 1390), 58.0]]:
		check(not _route(nav, sample[0], sample[1], sample[2]).is_empty(), "far opposite-side point/landmark planning remains reachable")

func _test_reference_routes_and_doors() -> void:
	var session := _new()
	var before: Dictionary = session.snapshot()
	check(not session.select_action("enter_teahouse", "reference-menu-bypass").ok and session.snapshot() == before, "menu action cannot bypass the distant spatial front door")
	check(not session.execute_walk_interaction("market_teahouse_door", "reference-far-door", before.run_id, before.revision).ok and session.snapshot() == before, "distant doorway callback is rejected atomically")
	for id: String in ["south_axis", "pool_north_detour", "southern_city_loop", "east_temple_route", "east_bridge_route", "west_cottage_route", "south_outer_route", "weaving_route"]:
		for raw: Array in authored_routes[id]:
			if not _walk(session, _point(raw)):
				return
	check(session.snapshot().scene == CITY and session.snapshot().sequence == before.sequence and session.snapshot().receipts == before.receipts, "city loops and outer districts are actual walking in one scene without travel actions")
	if not _door(session, "market_teahouse_door", TEA, "from_market") or not _door(session, "tea_lanes_exit", CITY, "from_teahouse_back"):
		return
	if not _door(session, "lanes_teahouse_door", TEA, "from_lanes") or not _door(session, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	check(session.snapshot().size() == 15 and session.snapshot().exploration.positions.size() == 2, "reference world retains the same strict fifteen fields and two scene positions")

func _test_reference_umbrella_checkpoint() -> void:
	var session := _new()
	check(_interact(session, "river_umbrella").get("ok", false) and session.choose("take", "reference-take").ok, "the existing optional umbrella is collected through its actual registered choice")
	_finish_reading(session)
	if not _walk(session, Vector2(4220, 2350)):
		return
	var saved: Dictionary = session.snapshot()
	var store = Store.new()
	store.base_dir = save_dir
	check(store.save_session(session).ok, "isolated reference checkpoint writes successfully")
	var reader = Session.new()
	check(reader.configure(pack).ok and store.load_session(reader).ok and reader.snapshot() == saved, "JSON checkpoint restores exact position, flags, clock, counts, journal and receipts")
	for kind: String in ["fraction", "water", "wall", "outside", "missing_map", "old_district", "extra_field"]:
		var bad := saved.duplicate(true)
		match kind:
			"fraction": bad.exploration.positions[CITY][0] = 4220.25
			"water": bad.exploration.positions[CITY] = [2400, 3150]
			"wall": bad.exploration.positions[CITY] = [2300, 2810]
			"outside": bad.exploration.positions[CITY] = [5121, 3841]
			"missing_map": bad.exploration.positions.erase(CITY)
			"old_district": bad.exploration.positions["chengdu_market"] = [180, 480]
			"extra_field": bad["city_camera"] = [1, 2]
		var previous: Dictionary = reader.snapshot()
		check(not reader.restore(bad).ok and reader.snapshot() == previous, "invalid reference save is rejected atomically: " + kind)
	# Take the northern temple/pond route rather than retracing the southern
	# market route, then cross the same shop from back to front.
	for point: Vector2 in [Vector2(4220, 2070), Vector2(3350, 2070), Vector2(2600, 2070), Vector2(2600, 1510), Vector2(2140, 1510), Vector2(1510, 1510), Vector2(1510, 2050), Vector2(1700, 2040)]:
		if not _walk(reader, point):
			return
	if not _door(reader, "lanes_teahouse_door", TEA, "from_lanes"):
		return
	check(_interact(reader, "tea_lost_property").get("ok", false) and reader.choose("return", "reference-return").ok, "alternate reference route returns the umbrella at the existing stand")
	_finish_reading(reader)
	check(_interact(reader, "tea_lost_property").get("ok", false) and reader.choose("revisit", "reference-revisit").ok, "returned umbrella supports an explicit revisit without a new settlement")
	_finish_reading(reader)
	if not _door(reader, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	var final: Dictionary = reader.snapshot()
	check(final.flags.chengdu_umbrella_returned and not final.flags.chengdu_umbrella_carrying and int(final.counts.get("take_river_umbrella", 0)) == 1 and int(final.counts.get("return_river_umbrella", 0)) == 1, "larger reference route preserves exactly one pickup and one return")
	check(final.day == 1 and final.slot == 1 and int(final.stats.energy) == 100, "all city walking and umbrella visits remain free")
	check(store.load_session(reader).ok and reader.snapshot() == saved, "loading after distant walking and completion restores the whole earlier carried-umbrella state")
	for old_id: String in OldDigests:
		var loaded: Dictionary = Loader.new().load_pack("res://games/" + old_id + "/game.json")
		var old_session = Session.new()
		check(loaded.ok and old_session.configure(loaded.pack).ok, "old content identity still configures beside reference save: " + old_id)
		var old_state: Dictionary = old_session.snapshot()
		check(not store.load_session(old_session).ok and old_session.snapshot() == old_state, "reference save cannot load into an old package: " + old_id)
		check(store.save_session(old_session).ok and store.load_session(reader).ok and reader.snapshot() == saved, "old and reference saves coexist without replacing one another: " + old_id)
	var different_version := pack.duplicate(true)
	different_version.version = "0.6.1"
	var version_reader = Session.new()
	check(version_reader.configure(different_version).ok, "version mismatch fixture configures independently")
	var version_before: Dictionary = version_reader.snapshot()
	check(not store.load_session(version_reader).ok and version_reader.snapshot() == version_before, "same-ID incompatible version cannot silently migrate the reference checkpoint")

func _test_old_packages() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu_reference/source.json"))
	for id: String in OldDigests:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		var names := DirAccess.get_files_at("res://games/" + id)
		names.sort()
		for name: String in names:
			if name.ends_with(".json"):
				context.update((name + "\n").to_utf8_buffer())
				context.update(FileAccess.get_file_as_bytes("res://games/" + id + "/" + name))
		check(context.finish().hex_encode() == str(OldDigests[id]), "old package remains byte-identical to the pre-reference snapshot: " + id)
		for name: String in source.get("protected_package_json_sha256", {}).get(id, {}):
			check(FileAccess.get_sha256("res://games/" + id + "/" + name) == str(source.protected_package_json_sha256[id][name]), "protected old file remains unchanged: " + id + "/" + name)
	for path: String in source.get("protected_layout_sha256", {}):
		check(FileAccess.get_sha256("res://" + path) == str(source.protected_layout_sha256[path]), "earlier presentation layout remains byte-identical: " + path)
	super._test_old_packages()

func _finish() -> void:
	var path := "res://.local/qa/chengdu-reference/state/navigation-timing.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": navigation_samples,
			"scope": "headless CPU configure and route timings on this host; not native or browser frame rate"}, "\t") + "\n")
		file.close()
	print("CULTIVATION_ENGINE_CHENGDU_REFERENCE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
