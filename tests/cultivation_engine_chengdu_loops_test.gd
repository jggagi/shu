extends SceneTree
## Real content/Session checks for the city loops; no state injection or UI claim.

const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const Session = preload("res://addons/cultivation_mode/session.gd")
const Store = preload("res://addons/cultivation_mode/save_store.gd")
const Navigation = preload("res://addons/cultivation_mode/town_navigation.gd")
const DISTRICTS := ["chengdu_gate", "chengdu_market", "chengdu_river", "chengdu_lanes", "chengdu_square", "chengdu_teahouse"]
# Expected doorway identities come from the route design, independently of the
# implementation's generic target_entry resolver. Positions remain authored data.
const ARRIVALS := {
	"gate_to_market": "from_west", "market_to_gate": "from_east",
	"market_to_river": "from_west", "river_to_market": "from_east",
	"gate_to_lanes": "from_gate", "lanes_to_gate": "from_lanes",
	"lanes_to_square": "from_lanes", "square_to_lanes": "from_square",
	"square_to_market": "from_square", "market_to_square": "from_market",
	"square_to_river": "from_square", "river_to_square": "from_river",
	"enter_teahouse": "from_market", "leave_teahouse": "from_teahouse",
	"enter_teahouse_back": "from_lanes", "leave_teahouse_back": "from_teahouse"}
var checks := 0
var failures := 0
var messages: Array[String] = []
var pack: Dictionary = {}
var graph: Dictionary = {}
var edges: Dictionary = {}
var operation := 0
var save_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_chengdu/game.json")
	check(loaded.ok, "actual six-district package loads: " + str(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	pack = loaded.pack
	save_dir = "user://test_runs/chengdu-loops-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_topology_and_routes()
	if failures == 0:
		_test_all_directional_edges()
		_test_alternate_route_umbrella_and_saves()
	_test_old_package_integrity()
	_finish()

func _test_topology_and_routes() -> void:
	check(pack.walks.scenes.size() == 6, "exactly six authored playable districts")
	for sid: String in DISTRICTS:
		check(pack.walks.scenes.has(sid), "district exists: " + sid)
		graph[sid] = []
	if failures > 0:
		return
	var undirected := {}
	for sid: String in DISTRICTS:
		var map: Dictionary = pack.walks.scenes[sid]
		for iid: String in map.interactions:
			var item: Dictionary = map.interactions[iid]
			var aid := str(item.action)
			var action: Dictionary = pack.actions[aid]
			var target := str(action.get("target_scene", ""))
			if not graph.has(target):
				continue
			edges[aid] = {"from": sid, "to": target, "interaction": iid}
			if not graph[sid].has(target):
				graph[sid].append(target)
			var pair: Array = [sid, target]
			pair.sort()
			undirected["|".join(pair)] = true
			check(not bool(action.menu) and str(action.get("event", "")).is_empty(), "district travel uses its actual spatial exit: " + aid)
			check(int(action.duration) == 0 and action.costs.is_empty() and action.gains.is_empty(), "district travel is free: " + aid)
			var conditions: Dictionary = action.get("conditions", {})
			check(conditions.get("flags", {}).is_empty() and conditions.get("stats_gte", {}).is_empty() and str(action.once_key).is_empty(), "no quest or cultivation gate on city edge: " + aid)
	for sid: String in DISTRICTS:
		check(graph[sid].size() >= 2, "each district has at least two distinct neighboring choices: " + sid)
		for target: String in graph[sid]:
			check(graph[target].has(sid), "route has an independently authored reverse exit: " + sid + " -> " + target)
	check(_reachable("chengdu_gate").size() == DISTRICTS.size(), "all districts are reachable from the west gate")
	var cycle_rank := undirected.size() - DISTRICTS.size() + 1
	check(cycle_rank >= 2, "connected city has at least two independent loops (rank=%d)" % cycle_rank)
	check(graph.chengdu_gate.has("chengdu_market") and graph.chengdu_gate.has("chengdu_lanes"), "gate offers market-first or lane-first routes immediately")
	check(graph.chengdu_teahouse.has("chengdu_market") and graph.chengdu_teahouse.has("chengdu_lanes"), "teahouse front and back doors connect different streets")
	var paths: Array = []
	_collect_paths("chengdu_gate", "chengdu_river", ["chengdu_gate"], paths)
	var first_steps := {}
	for path: Array in paths:
		if path.size() >= 2:
			first_steps[path[1]] = true
	check(paths.size() >= 2 and first_steps.has("chengdu_market") and first_steps.has("chengdu_lanes"), "river can be reached by two simple routes with different first streets")
	for aid: String in ARRIVALS:
		check(edges.has(aid), "specified city connection exists: " + aid)
		if not edges.has(aid):
			continue
		var target: String = edges[aid].to
		var entry := str(ARRIVALS[aid])
		check(str(pack.actions[aid].get("target_entry", "")) == entry and pack.walks.scenes[target].entries.has(entry), "correct arrival side is authored for " + aid)
	_test_all_anchor_reachability()

func _reachable(start: String) -> Array:
	var found: Array = [start]
	var cursor := 0
	while cursor < found.size():
		for target: String in graph[found[cursor]]:
			if not found.has(target):
				found.append(target)
		cursor += 1
	return found

func _collect_paths(at: String, goal: String, visited: Array, paths: Array) -> void:
	if at == goal:
		paths.append(visited.duplicate())
		return
	for target: String in graph[at]:
		if not visited.has(target):
			var next := visited.duplicate()
			next.append(target)
			_collect_paths(target, goal, next, paths)

func _test_all_anchor_reachability() -> void:
	for sid: String in DISTRICTS:
		var map: Dictionary = pack.walks.scenes[sid]
		var nav = Navigation.new()
		nav.configure(map)
		var arrivals: Dictionary = map.entries.duplicate(true)
		arrivals["default_spawn"] = map.spawn
		for entrance: String in arrivals:
			var point: Array = arrivals[entrance]
			var origin := Vector2(float(point[0]), float(point[1]))
			for iid: String in map.interactions:
				var item: Dictionary = map.interactions[iid]
				var target := Vector2(float(item.position[0]), float(item.position[1]))
				var path: Array = nav.route(origin, target, float(item.radius))
				check(not path.is_empty(), "each entrance can reach each real interaction: %s/%s -> %s" % [sid, entrance, iid])

func _new() -> RefCounted:
	var session = Session.new()
	check(session.configure(pack).ok, "same existing Session configures real city data")
	check(session.select_action("go_to_town").ok and session.acknowledge_result().ok, "explicit one-slot trip reaches the gate")
	return session

func _approach(session: RefCounted, iid: String) -> bool:
	var state: Dictionary = session.snapshot()
	var sid := str(state.scene)
	var map: Dictionary = pack.walks.scenes[sid]
	var item: Dictionary = map.interactions[iid]
	var at: Array = state.exploration.positions[sid]
	var nav = Navigation.new()
	nav.configure(map)
	var path: Array = nav.route(Vector2(float(at[0]), float(at[1])), Vector2(float(item.position[0]), float(item.position[1])), float(item.radius))
	check(not path.is_empty(), "route to real anchor exists: " + iid)
	for point: Vector2 in path:
		state = session.snapshot()
		var moved: Dictionary = session.commit_walk_position(sid, [roundi(point.x), roundi(point.y)], state.run_id, state.revision)
		if not moved.ok:
			check(false, "each real route segment commits without teleporting: " + iid)
			return false
	return not path.is_empty()

func _interact(session: RefCounted, iid: String) -> Dictionary:
	if not _approach(session, iid):
		return {"ok": false}
	operation += 1
	var state: Dictionary = session.snapshot()
	return session.execute_walk_interaction(iid, "loop-test-%d" % operation, state.run_id, state.revision)

func _travel(session: RefCounted, aid: String) -> bool:
	if not edges.has(aid):
		check(false, "route edge is registered: " + aid)
		return false
	var before: Dictionary = session.snapshot()
	check(str(before.scene) == str(edges[aid].from), "current district matches the chosen exit: " + aid)
	var result: Dictionary = _interact(session, str(edges[aid].interaction))
	check(result.get("ok", false), "actual spatial exit succeeds: " + aid)
	if not result.get("ok", false):
		return false
	var arrived: Dictionary = session.snapshot()
	var target := str(edges[aid].to)
	var authored: Array = pack.walks.scenes[target].entries[ARRIVALS[aid]]
	var expected: Array = [int(authored[0]), int(authored[1])]
	check(arrived.scene == target and arrived.exploration.positions[target] == expected, "Session arrives at the correct doorway side: " + aid)
	check(arrived.day == before.day and arrived.slot == before.slot and arrived.stats == before.stats and arrived.flags == before.flags, "city edge preserves game time, resources and task flags: " + aid)
	check(session.execute_walk_interaction(str(edges[aid].interaction), str(result.operation_id), arrived.run_id, -1).get("duplicate", false) and session.snapshot() == arrived, "repeated arrival callback cannot re-enter or settle again: " + aid)
	check(session.acknowledge_result().ok, "travel result returns to safe walking")
	return true

func _test_all_directional_edges() -> void:
	# Navigate through actual exits, rather than assigning the test Session.scene.
	var session := _new()
	for aid: String in ["gate_to_lanes", "lanes_to_square", "square_to_river", "river_to_market", "market_to_gate",
		"gate_to_market", "market_to_square", "square_to_lanes", "enter_teahouse_back", "leave_teahouse",
		"enter_teahouse", "leave_teahouse_back", "lanes_to_gate", "gate_to_market", "market_to_river",
		"river_to_square", "square_to_market"]:
		if not _travel(session, aid):
			return
	var state: Dictionary = session.snapshot()
	check(state.scene == "chengdu_market", "two loops and both teahouse doors complete without a main-route reset")
	var blocked: Dictionary = session.select_action("market_to_square", "menu-skip")
	check(not blocked.ok and session.snapshot() == state, "ordinary menu cannot bypass spatial route proximity")
	check(state.size() == 15 and state.exploration.positions.size() == 6, "six districts remain one strict fifteen-field Session")

func _finish_reading(session: RefCounted) -> void:
	for _step: int in range(12):
		var state: Dictionary = session.snapshot()
		if state.phase == "ready":
			return
		if state.phase == "result":
			check(session.acknowledge_result().ok, "completed reading returns to walking")
		elif state.phase == "event" and session.event_view().get("type", "") in ["say", "end"]:
			check(session.continue_event().ok, "explicit reading continuation completes")
		else:
			check(false, "test must explicitly choose any encountered choice")
			return
	check(false, "reading terminates in the existing finite event graph")

func _test_alternate_route_umbrella_and_saves() -> void:
	var session := _new()
	if not _travel(session, "gate_to_market") or not _travel(session, "market_to_river"):
		return
	check(_interact(session, "river_umbrella").ok and session.choose("take", "take-once").ok, "the original river route can pick up the optional umbrella")
	_finish_reading(session)
	check(session.snapshot().flags.chengdu_umbrella_carrying and int(session.snapshot().counts.get("take_river_umbrella", 0)) == 1, "umbrella ownership is committed exactly once")
	for aid: String in ["river_to_square", "square_to_lanes", "enter_teahouse_back"]:
		if not _travel(session, aid):
			return
	var expected: Dictionary = session.snapshot()
	var store = Store.new()
	store.base_dir = save_dir
	check(store.save_session(session).ok, "safe checkpoint saves after the alternate square/lane/back-door route")
	var restored = Session.new()
	check(restored.configure(pack).ok and store.load_session(restored).ok and restored.snapshot() == expected, "reload restores exact district, foot position, umbrella flags and all receipts")
	check(_interact(restored, "tea_lost_property").ok and restored.choose("return", "return-once").ok, "the alternate route reaches the same loss-property action")
	_finish_reading(restored)
	for aid: String in ["leave_teahouse", "market_to_gate", "gate_to_lanes", "lanes_to_square", "square_to_river"]:
		if not _travel(restored, aid):
			return
	var final: Dictionary = restored.snapshot()
	check(final.flags.chengdu_umbrella_returned and not final.flags.chengdu_umbrella_carrying and int(final.counts.get("take_river_umbrella", 0)) == 1 and int(final.counts.get("return_river_umbrella", 0)) == 1, "task consequences survive both loops without repeating pickup or return")
	check(_interact(restored, "river_umbrella").ok, "returned umbrella location remains inspectable")
	var take_enabled := false
	for option: Dictionary in restored.event_view().get("options", []):
		if option.id == "take" and bool(option.get("enabled", false)):
			take_enabled = true
	check(not take_enabled, "long alternate revisit cannot make the umbrella collectible again")
	check(restored.choose("returned", "remember-returned").ok, "revisit offers the actual remembered consequence")
	_finish_reading(restored)
	check(int(restored.snapshot().slot) == 1 and int(restored.snapshot().stats.energy) == 100, "both alternate loops and the umbrella task consume no extra game time or resources")
	var old: Dictionary = Loader.new().load_pack("res://games/shu_town_walk/game.json")
	if old.ok:
		var old_session = Session.new()
		check(old_session.configure(old.pack).ok and store.save_session(old_session).ok, "old town checkpoint uses a separate package directory")
		var city_reader = Session.new()
		check(city_reader.configure(pack).ok and store.load_session(city_reader).ok and city_reader.snapshot() == expected, "saving the old town cannot overwrite the city checkpoint")

func _test_old_package_integrity() -> void:
	var provenance: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu/source.json"))
	if provenance is Dictionary:
		for name: String in provenance.get("inherited_json_sha256", {}):
			check(FileAccess.get_sha256("res://games/shu_town_walk/" + name) == str(provenance.inherited_json_sha256[name]), "original town JSON remains byte-for-byte intact: " + name)
	for manifest: String in ["res://games/shu_mentor_loop/game.json", "res://games/stream_study/game.json"]:
		var old: Dictionary = Loader.new().load_pack(manifest)
		check(old.ok, "original non-walking package still loads: " + manifest)
		if old.ok:
			var session = Session.new()
			check(session.configure(old.pack).ok and session.snapshot().size() == 14 and not session.snapshot().has("exploration"), "original package keeps strict fourteen-field state")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		messages.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("CULTIVATION_ENGINE_CHENGDU_LOOPS_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
