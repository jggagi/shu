extends "res://tests/cultivation_engine_chengdu_large_test.gd"
## Headless host acceptance. Authored positions come from the final large-city
## data; every resulting movement still commits through the original Session.

const ScaleNavigation = preload("res://addons/cultivation_mode/chengdu_scale_navigation.gd")
const SCALE_LAYOUT := "res://assets/data/chengdu-scale-layout.json"
const REFERENCE_LAYOUT := "res://assets/data/chengdu-reference-layout.json"
const OLD_MANIFESTS := {
	"shu_chengdu": "res://games/shu_chengdu/game.json",
	"shu_chengdu_large": "res://games/shu_chengdu_large/game.json",
	"shu_chengdu_reference": "res://games/shu_chengdu_reference/game.json"}
var scale_layout: Dictionary = {}
var route_waypoints: Dictionary = {}
var solids_by_id: Dictionary = {}
var navigation_cache: Dictionary = {}
var failure_messages: Array[String] = []


func _run() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_chengdu_scale/game.json")
	check(loaded.ok, "actual 622-obstacle scale package loads under the expanded bounded contract: " + str(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	pack = loaded.pack
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCALE_LAYOUT))
	check(raw is Dictionary, "scaled city composition is readable")
	if not raw is Dictionary:
		_finish()
		return
	scale_layout = raw.get("scenes", {}).get(CITY, {})
	regions = scale_layout.get("regions", [])
	route_waypoints = scale_layout.get("route_waypoints", {})
	save_dir = "user://test_runs/chengdu-scale-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	nav = _navigation_for(CITY)
	_test_scale_geometry_and_contract()
	_test_reachable_destinations()
	if failures == 0:
		_test_actual_host_walking_and_doors()
		_test_scale_umbrella_checkpoint_and_return()
	_test_preserved_packages()
	_finish()


func _navigation_for(scene_id: String) -> RefCounted:
	if navigation_cache.has(scene_id):
		return navigation_cache[scene_id]
	var value: RefCounted = ScaleNavigation.new() if scene_id == CITY else Navigation.new()
	var started := Time.get_ticks_usec()
	value.configure(pack.walks.scenes[scene_id])
	navigation_samples.append({"kind": "grid_configure", "scene": scene_id, "milliseconds": float(Time.get_ticks_usec() - started) / 1000.0})
	navigation_cache[scene_id] = value
	return value


func _walk(session: RefCounted, destination: Vector2, radius: float = 0.0) -> bool:
	var before: Dictionary = session.snapshot()
	var scene_id := str(before.scene)
	var navigation := _navigation_for(scene_id)
	var path: Array = _route(navigation, _point(before.exploration.positions[scene_id]), destination, radius)
	check(not path.is_empty(), "real cached navigation reaches the requested world destination")
	if path.is_empty():
		return false
	for point: Vector2 in path:
		var state: Dictionary = session.snapshot()
		var committed: Dictionary = session.commit_walk_position(scene_id, [roundi(point.x), roundi(point.y)], state.run_id, state.revision)
		if not committed.ok:
			check(false, "original Session accepts every independently legal scale-route segment: " + str(committed))
			return false
	var after: Dictionary = session.snapshot()
	check(after.scene == scene_id and after.day == before.day and after.slot == before.slot and after.stats == before.stats and after.flags == before.flags and after.sequence == before.sequence and after.counts == before.counts and after.receipts == before.receipts and after.journal == before.journal, "continuous city walking changes only position and revision, with no action, flag, scene or clock settlement")
	return true


func _new() -> RefCounted:
	var session = Session.new()
	check(session.configure(pack).ok, "original Session configures the scale content package")
	var initial: Dictionary = session.snapshot()
	check(initial.size() == 15 and initial.exploration.positions.size() == 2, "scale city retains strict fifteen fields and only two persisted map positions")
	check(session.select_action("talk_mentor", "scale-mentor-open").ok, "retained mentor conversation opens in the original mountain scene")
	for step: int in range(8):
		if session.event_view().get("type", "") == "choice":
			break
		check(session.continue_event().ok, "retained voiced mentor introduction advances to its actual choice")
	var before_choice: Dictionary = session.snapshot()
	check(before_choice.day == initial.day and before_choice.slot == initial.slot and before_choice.stats == initial.stats, "opening and reading the mentor scene remain free")
	check(session.choose("take_lesson", "scale-mentor-paid-choice").ok, "the actual paid mentor choice settles through its retained action")
	var paid: Dictionary = session.snapshot()
	check(int(paid.stats.energy) == int(initial.stats.energy) - 8 and int(paid.stats.understanding) == int(initial.stats.understanding) + 1 and int(paid.slot) == int(initial.slot) + 1, "mentor choice retains eight energy, one understanding and one time-slot settlement")
	check(paid.flags.mentor_lesson_accepted and paid.flags.breathing_hint, "mentor benefit remains armed for the existing sword lesson")
	check(session.choose("take_lesson", "scale-mentor-paid-choice").get("duplicate", false) and session.snapshot() == paid, "replaying the paid choice cannot charge or grant twice")
	_finish_reading(session)
	var before_travel: Dictionary = session.snapshot()
	check(session.select_action("go_to_town", "scale-outbound").ok and session.acknowledge_result().ok, "the original outbound action reaches the continuous city")
	var arrived: Dictionary = session.snapshot()
	check(arrived.scene == CITY and arrived.exploration.positions[CITY] == _coords(pack.walks.scenes[CITY].entries.from_mountain), "ordinary arrival uses the actual authored south-bridge entrance")
	check(arrived.day == before_travel.day and int(arrived.slot) == int(before_travel.slot) + 1 and arrived.stats == before_travel.stats, "outbound journey adds exactly one time slot and no energy charge")
	return session


func _box(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


func _test_scale_geometry_and_contract() -> void:
	var map: Dictionary = pack.walks.scenes[CITY]
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_LAYOUT))
	check(pack.id == "shu_chengdu_scale" and pack.version == "0.7.0", "new city has an independent content identity and version")
	check(_coords(map.size) == [15360, 11520] and float(map.size[0]) * float(map.size[1]) == float(previous.world_size[0]) * float(previous.world_size[1]) * 9.0, "outdoor area is exactly nine times the earlier reference candidate")
	check(int(map.cell_size) == 40 and int(map.actor_radius) == 12, "large-city grid retains the actor's existing radius")
	check(pack.walks.scenes.size() == 2 and pack.walks.scenes.has(TEA), "all outdoor wards remain one continuous map beside the original tea interior")
	check(map.obstacles.size() == 622 and map.obstacles.size() > 64 and map.obstacles.size() <= 1024, "actual authored city exercises the larger bounded obstacle contract")
	check(map.interactions.size() == 16 and regions.size() == 11, "the sixteen actual outdoor interactions and eleven districts remain registered")
	var drawn: Dictionary = {}
	var individual_count := 0
	for item: Dictionary in scale_layout.get("buildings", []):
		var id := str(item.id)
		check(not solids_by_id.has(id), "each visible blocking lot has a unique identity: " + id)
		solids_by_id[id] = item
		drawn[JSON.stringify(item.bounds)] = int(drawn.get(JSON.stringify(item.bounds), 0)) + 1
		check(map.obstacles.has(item.bounds), "visible lot has the exact navigation footprint: " + id)
		if bool(item.get("individual_house", false)):
			individual_count += 1
			check(float(item.bounds[2]) <= 190 and float(item.bounds[3]) <= 180, "individual house remains a normal-sized separately blocked building: " + id)
	var walked: Dictionary = {}
	for obstacle: Array in map.obstacles:
		walked[JSON.stringify(obstacle)] = int(walked.get(JSON.stringify(obstacle), 0)) + 1
	check(drawn == walked and individual_count == 592, "all 592 individual houses and all 622 visible solid footprints exactly match navigation")
	check(scale_layout.bridges.size() == 3 and scale_layout.gates.size() == 4, "three real bridges and four real gates organize the city")
	for bridge: Dictionary in scale_layout.bridges:
		var bounds := _box(bridge.bounds)
		var vertical := str(bridge.axis) == "north_south"
		var extension := Vector2(0, 40) if vertical else Vector2(40, 0)
		var start := Vector2(bounds.get_center().x, bounds.position.y) if vertical else Vector2(bounds.position.x, bounds.get_center().y)
		var finish := Vector2(bounds.get_center().x, bounds.end.y) if vertical else Vector2(bounds.end.x, bounds.get_center().y)
		check(nav.clear_segment(start - extension, finish + extension), "bridge is a genuine radius-safe crossing: " + str(bridge.id))
		var offset := Vector2(bounds.size.x * 0.5 + 52, 0) if vertical else Vector2(0, bounds.size.y * 0.5 + 52)
		check(not nav.clear_segment(start - extension - offset, finish + extension - offset), "water cannot be crossed beside the real bridge: " + str(bridge.id))
	for gate: Dictionary in scale_layout.gates:
		var bounds := _box(gate.bounds)
		var vertical := str(gate.axis) == "north_south"
		var extension := Vector2(0, 40) if vertical else Vector2(40, 0)
		var start := Vector2(bounds.get_center().x, bounds.position.y) if vertical else Vector2(bounds.position.x, bounds.get_center().y)
		var finish := Vector2(bounds.get_center().x, bounds.end.y) if vertical else Vector2(bounds.end.x, bounds.get_center().y)
		check(nav.clear_segment(start - extension, finish + extension), "wall has an actual open gate: " + str(gate.id))
	for item: Dictionary in scale_layout.buildings:
		if str(item.kind) in ["water", "city_wall"]:
			check(nav.blocked(_box(item.bounds).get_center()), "water and intact city walls retain collision: " + str(item.id))
	var loader := Loader.new()
	var limit_fixture := pack.duplicate(true)
	while limit_fixture.walks.scenes[CITY].obstacles.size() < 1024:
		limit_fixture.walks.scenes[CITY].obstacles.append(map.obstacles[0].duplicate())
	check(loader.validate(limit_fixture).is_empty(), "the explicitly supported 1024-obstacle boundary remains valid")
	limit_fixture.walks.scenes[CITY].obstacles.append(map.obstacles[0].duplicate())
	check(not loader.validate(limit_fixture).is_empty(), "1025 obstacles are rejected by the finite content contract")
	var session = Session.new()
	check(session.configure(pack).ok, "valid package configures before the over-limit atomicity check")
	var before: Dictionary = session.snapshot()
	check(not session.configure(limit_fixture).ok and session.snapshot() == before and session.pack.id == pack.id, "over-limit reconfiguration cannot replace the active valid Session or its state")


func _test_reachable_destinations() -> void:
	var map: Dictionary = pack.walks.scenes[CITY]
	var spawn := _point(map.spawn)
	var ids: Dictionary = {}
	for region: Dictionary in regions:
		var destination := _point(region.visit_point)
		check(not ids.has(region.id) and _box(region.bounds).has_point(destination), "district owns a unique actual walkable visit point: " + str(region.id))
		ids[region.id] = true
		check(not nav.blocked(destination) and not _route(nav, spawn, destination, 0).is_empty(), "ordinary arrival reaches the whole district: " + str(region.id))
	for entry: String in map.entries:
		check(not _route(nav, spawn, _point(map.entries[entry]), 0).is_empty(), "all actual arrival sides join the continuous city: " + entry)
	for id: String in map.interactions:
		var item: Dictionary = map.interactions[id]
		check(not _route(nav, spawn, _point(item.position), float(item.radius)).is_empty(), "ordinary arrival reaches the actual city interaction: " + id)
		check(str(pack.actions[item.action].get("target_scene", "")) in ["", TEA, "tingyu_corridor"], "outdoor interactions never conceal district scene transitions: " + id)
	for route_id: String in route_waypoints:
		var points: Array = route_waypoints[route_id]
		var clear := points.size() >= 2
		for index: int in range(1, points.size()):
			clear = clear and nav.clear_segment(_point(points[index - 1]), _point(points[index]))
		check(clear, "all authored street segments are genuine clear ground: " + route_id)
	for action_id: String in ["enter_teahouse", "enter_teahouse_back", "leave_teahouse", "leave_teahouse_back"]:
		var action: Dictionary = pack.actions[action_id]
		check(not bool(action.menu) and int(action.duration) == 0 and action.costs.is_empty() and action.conditions.get("flags", {}).is_empty() and action.conditions.get("stats_gte", {}).is_empty(), "both tea doors remain free spatial actions without unlock requirements: " + action_id)
	check(map.entries.from_teahouse_front != map.entries.from_teahouse_back, "two tea exits return to different actual outdoor positions")


func _test_actual_host_walking_and_doors() -> void:
	var session := _new()
	var before: Dictionary = session.snapshot()
	check(not session.select_action("enter_teahouse", "scale-menu-bypass").ok and session.snapshot() == before, "menu request cannot bypass the distant tea door")
	check(not session.execute_walk_interaction("market_teahouse_door", "scale-far-door", before.run_id, before.revision).ok and session.snapshot() == before, "distant spatial interaction rejects atomically")
	for region: Dictionary in regions:
		if not _walk(session, _point(region.visit_point)):
			return
	for route_id: String in route_waypoints:
		for point: Array in route_waypoints[route_id]:
			if not _walk(session, _point(point)):
				return
	check(session.snapshot().scene == CITY and session.snapshot().sequence == before.sequence and session.snapshot().receipts == before.receipts, "eleven districts and fourteen authored routes are traversed without settlement or a hidden scene transition")
	if not _door(session, "market_teahouse_door", TEA, "from_market") or not _door(session, "tea_lanes_exit", CITY, "from_teahouse_back"):
		return
	if not _door(session, "lanes_teahouse_door", TEA, "from_lanes") or not _door(session, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	check(int(nav.grid_build_count) == 1, "city movement and four doorway directions reuse one static outdoor navigation grid")
	check(session.snapshot().size() == 15 and session.snapshot().exploration.positions.size() == 2, "crossing the full city and shop adds no persistent fields")


func _test_scale_umbrella_checkpoint_and_return() -> void:
	var session := _new()
	check(_interact(session, "river_umbrella").get("ok", false) and session.choose("take", "scale-take").ok, "the existing umbrella is deliberately collected through its actual choice")
	var taken: Dictionary = session.snapshot()
	check(session.choose("take", "scale-take").get("duplicate", false) and session.snapshot() == taken, "duplicate pickup choice cannot grant or settle again")
	_finish_reading(session)
	var distant: Dictionary = regions[0]
	for region: Dictionary in regions:
		if str(region.id) == "dufu":
			distant = region
	if not _walk(session, _point(distant.visit_point)):
		return
	var saved: Dictionary = session.snapshot()
	var store = Store.new()
	store.base_dir = save_dir
	check(store.save_session(session).ok, "safe far-city checkpoint writes in an isolated candidate directory")
	var reader = Session.new()
	check(reader.configure(pack).ok and store.load_session(reader).ok and reader.snapshot() == saved, "JSON checkpoint restores the exact far point, full state and carried umbrella")
	for kind: String in ["fraction", "water", "wall", "outside", "missing_map", "old_district", "extra_field"]:
		var bad := saved.duplicate(true)
		match kind:
			"fraction": bad.exploration.positions[CITY][0] = float(saved.exploration.positions[CITY][0]) + 0.25
			"water": bad.exploration.positions[CITY] = _coords([_box(solids_by_id.mohe_pool.bounds).get_center().x, _box(solids_by_id.mohe_pool.bounds).get_center().y])
			"wall": bad.exploration.positions[CITY] = _coords([_box(solids_by_id.north_wall.bounds).get_center().x, _box(solids_by_id.north_wall.bounds).get_center().y])
			"outside": bad.exploration.positions[CITY] = [int(pack.walks.scenes[CITY].size[0]) + 1, int(pack.walks.scenes[CITY].size[1]) + 1]
			"missing_map": bad.exploration.positions.erase(CITY)
			"old_district": bad.exploration.positions["chengdu_market"] = pack.walks.scenes[CITY].spawn.duplicate()
			"extra_field": bad["city_camera"] = [1, 2]
		var previous: Dictionary = reader.snapshot()
		check(not reader.restore(bad).ok and reader.snapshot() == previous, "invalid coordinate/state restoration is rejected atomically: " + kind)
	if not _door(reader, "lanes_teahouse_door", TEA, "from_lanes"):
		return
	check(_interact(reader, "tea_lost_property").get("ok", false) and reader.choose("return", "scale-return").ok, "the northern tea route returns the original umbrella to its actual rack")
	var returned: Dictionary = reader.snapshot()
	check(reader.choose("return", "scale-return").get("duplicate", false) and reader.snapshot() == returned, "duplicate return choice cannot settle twice")
	_finish_reading(reader)
	check(_interact(reader, "tea_lost_property").get("ok", false) and reader.choose("revisit", "scale-rack-revisit").ok, "the returned rack supports its explicit remembered revisit")
	_finish_reading(reader)
	if not _door(reader, "tea_market_exit", CITY, "from_teahouse_front"):
		return
	check(_interact(reader, "river_umbrella").get("ok", false), "the original riverside umbrella spot remains inspectable after return")
	var take_enabled := false
	for option: Dictionary in reader.event_view().get("options", []):
		if option.id == "take" and bool(option.get("enabled", false)):
			take_enabled = true
	check(not take_enabled and reader.choose("returned", "scale-river-memory").ok, "riverside revisit remembers the consequence and disables repeated pickup")
	_finish_reading(reader)
	var final: Dictionary = reader.snapshot()
	check(final.flags.chengdu_umbrella_returned and not final.flags.chengdu_umbrella_carrying and int(final.counts.get("take_river_umbrella", 0)) == 1 and int(final.counts.get("return_river_umbrella", 0)) == 1, "all long walks preserve exactly one pickup and one return")
	check(final.day == 1 and final.slot == 2 and int(final.stats.energy) == 92, "all city walking, tea doors, readings and umbrella visits remain free after the paid lesson and outbound journey")
	check(store.load_session(reader).ok and reader.snapshot() == saved, "loading after completion restores the whole earlier carried-umbrella checkpoint exactly")
	for old_id: String in OLD_MANIFESTS:
		var old: Dictionary = Loader.new().load_pack(OLD_MANIFESTS[old_id])
		var old_session = Session.new()
		check(old.ok and old_session.configure(old.pack).ok, "old content identity configures beside the larger candidate: " + old_id)
		var old_state: Dictionary = old_session.snapshot()
		check(not store.load_session(old_session).ok and old_session.snapshot() == old_state, "new checkpoint cannot silently load into an older candidate: " + old_id)
		check(store.save_session(old_session).ok and store.load_session(reader).ok and reader.snapshot() == saved, "old and new checkpoints coexist without replacing each other: " + old_id)
	var different_version := pack.duplicate(true)
	different_version.version = "0.7.1"
	var version_reader = Session.new()
	check(version_reader.configure(different_version).ok, "independent incompatible-version fixture configures")
	var version_before: Dictionary = version_reader.snapshot()
	check(not store.load_session(version_reader).ok and version_reader.snapshot() == version_before, "same-ID incompatible version cannot silently migrate the checkpoint")
	var before_return: Dictionary = reader.snapshot()
	check(_interact(reader, "gate_mountain_exit").get("ok", false), "walking reaches the actual south-bridge return action")
	var mountain: Dictionary = reader.snapshot()
	check(mountain.scene == "tingyu_corridor" and int(mountain.slot) == int(before_return.slot) + 1 and mountain.day == before_return.day and mountain.stats == before_return.stats, "returning to the mountain adds exactly one time slot and keeps mentor/cultivation state")
	check(reader.acknowledge_result().ok and reader.snapshot().flags.breathing_hint, "original mentor benefit remains available after the city round trip")
	var prior_run := str(reader.snapshot().run_id)
	check(reader.start_new().ok, "explicit new game resets the same existing host")
	var reset: Dictionary = reader.snapshot()
	check(reset.run_id != prior_run and reset.size() == 15 and reset.scene == pack.initial_scene and reset.day == 1 and reset.slot == 0 and int(reset.stats.energy) == 100 and reset.exploration.positions[CITY] == _coords(pack.walks.scenes[CITY].spawn) and reset.counts.is_empty() and reset.receipts.is_empty() and not reset.flags.chengdu_umbrella_taken, "restart retains fifteen fields while resetting positions, flags, clock and receipts")


func _test_preserved_packages() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu_scale/source.json"))
	for old_id: String in source.protected_package_json_sha256:
		for name: String in source.protected_package_json_sha256[old_id]:
			check(FileAccess.get_sha256("res://games/" + old_id + "/" + name) == str(source.protected_package_json_sha256[old_id][name]), "protected older package data remains byte-identical: " + old_id + "/" + name)
	for path: String in source.protected_layout_sha256:
		check(FileAccess.get_sha256("res://" + path) == str(source.protected_layout_sha256[path]), "earlier presentation layout remains byte-identical: " + path)
	for name: String in source.unchanged_files:
		check(FileAccess.get_sha256("res://games/shu_chengdu_scale/" + name) == FileAccess.get_sha256("res://games/shu_chengdu_reference/" + name), "retained mentor, motion, voice and event content is unchanged: " + name)
	super._test_old_packages()


func check(ok: bool, label: String) -> void:
	if not ok:
		failure_messages.append(label)
	super.check(ok, label)


func _finish() -> void:
	var directory := "res://.local/qa/chengdu-scale/state"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			directory = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output := FileAccess.open(directory.path_join("scale-state.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"checks": checks, "failures": failures, "failure_messages": failure_messages,
			"navigation": navigation_samples, "navigation_cache": nav.navigation_audit() if nav != null else {},
			"scope": "headless original Session actions, walking segments and JSON checkpoint validation; no UI, GPU, physical input or device performance claim"}, "\t"))
	print("CULTIVATION_ENGINE_CHENGDU_SCALE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
