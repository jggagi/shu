extends SceneTree

const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript = preload("res://addons/cultivation_mode/session.gd")
const StoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const MANIFEST := "res://games/shu_town_walk/game.json"
var checks: int = 0
var failures: int = 0
var messages: Array[String] = []
var town: Dictionary = {}
var stream: Dictionary = {}
var base_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loaded: Dictionary = LoaderScript.new().load_pack(MANIFEST)
	check(loaded.ok, "P1b independent walk pack loads: " + str(loaded.get("errors", [])))
	var other: Dictionary = LoaderScript.new().load_pack("res://games/stream_study/game.json")
	check(other.ok, "retained Stream pack loads")
	if not loaded.ok or not other.ok:
		_finish()
		return
	town = loaded.pack
	stream = other.pack
	base_dir = "user://test_runs/p1b-walk-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	_test_contract()
	_test_movement_and_interaction()
	_test_save_and_compatibility()
	_test_original_mentor_five_and_isolation()
	_finish()

func _new(data: Dictionary) -> RefCounted:
	var session = SessionScript.new()
	check(session.configure(data).ok, "Session configures content")
	return session

func _town_ready(session: RefCounted) -> void:
	check(session.select_action("go_to_town").ok, "one registered outbound travel enters town")
	check(session.acknowledge_result().ok, "arrival result is acknowledged before walking")

func _move(session: RefCounted, position: Array) -> Dictionary:
	var before: Dictionary = session.snapshot()
	return session.commit_walk_position("shanxia_town", position, before.run_id, before.revision)

func _interact(session: RefCounted, id: String, operation: String) -> Dictionary:
	var before: Dictionary = session.snapshot()
	return session.execute_walk_interaction(id, operation, before.run_id, before.revision)

func _rejected(session: RefCounted, result: Dictionary, before: Dictionary, text: String) -> void:
	check(not result.get("ok", false) and session.snapshot() == before, text + " leaves full state unchanged")

func _test_contract() -> void:
	var loader = LoaderScript.new()
	for kind: String in ["version", "blocked_spawn", "bad_position", "menu_bypass", "repeat_flag", "bad_floor", "duplicate_action", "choice_bypass", "odd_cell", "blocked_target"]:
		var bad: Dictionary = town.duplicate(true)
		match kind:
			"version": bad.walks.schema_version = 2
			"blocked_spawn": bad.walks.scenes.shanxia_town.spawn = [550, 400]
			"bad_position": bad.walks.scenes.shanxia_town.interactions.tea_seller.position = [1.25, 4]
			"menu_bypass": bad.actions.greet_tea_seller.menu = true
			"repeat_flag": bad.walks.scenes.shanxia_town.interactions.tea_seller.seen_flag = "unregistered"
			"bad_floor": bad.walks.scenes.shanxia_town.floor = [0, 0, 9000, 9000]
			"duplicate_action": bad.walks.scenes.shanxia_town.interactions.street_sign.action = "greet_tea_seller"
			"odd_cell": bad.walks.scenes.shanxia_town.cell_size = 21
			"blocked_target": bad.walks.scenes.shanxia_town.interactions.tea_seller.position = [480, 400]
			"choice_bypass":
				bad.events.mentor_tip.nodes.choice.options[0].action = "greet_tea_seller"
		check(not loader.validate(bad).is_empty(), "loader rejects malformed spatial contract " + kind)
	var old: Dictionary = loader.load_pack("res://games/shu_town_return/game.json")
	check(old.ok, "retained P1a pack loads through extended loader")
	if old.ok:
		var previous: RefCounted = _new(old.pack)
		check(previous.snapshot().size() == 14 and not previous.snapshot().has("exploration"), "P1a retains exact fourteen-field snapshot")
	var session: RefCounted = _new(town)
	check(session.snapshot().size() == 15 and session.snapshot().exploration.schema_version == 1, "walk capability declares strict fifteenth exploration field")
	check(session.snapshot().exploration.positions == {"shanxia_town": [150, 560]}, "new spatial state registers the single declared spawn")

func _test_movement_and_interaction() -> void:
	var session: RefCounted = _new(town)
	var before: Dictionary = session.snapshot()
	_rejected(session, _interact(session, "tea_seller", "wrong-scene"), before, "town interactions cannot execute from corridor")
	_town_ready(session)
	before = session.snapshot()
	var outbound_operation: String = str(before.last_result.operation_id)
	_rejected(session, _interact(session, "tea_seller", "too-far"), before, "distant interaction waits for walking")
	_rejected(session, session.select_action("return_from_town", "menu-return"), before, "menu API cannot bypass exit proximity")
	_rejected(session, session.select_action("greet_tea_seller", "menu-greet"), before, "menu API cannot bypass NPC proximity")
	_rejected(session, _move(session, [550, 400]), before, "movement cannot enter expanded stall obstacle")
	_rejected(session, _move(session, [900, 300]), before, "direct movement cannot cross obstacle")
	_rejected(session, _move(session, [50, 560]), before, "movement cannot leave safe floor")
	_rejected(session, _move(session, [800.5, 560]), before, "persistent position requires integer coordinates")
	_rejected(session, session.commit_walk_position("shanxia_town", [200, 560], "old-run", before.revision), before, "obsolete run cannot move")
	_rejected(session, session.commit_walk_position("shanxia_town", [200, 560], before.run_id, before.revision - 1), before, "obsolete revision cannot move")
	check(_move(session, [900, 560]).ok and _move(session, [1010, 350]).ok, "walking follows two clear segments around the stall")
	var arrived: Dictionary = session.snapshot()
	check(arrived.day == before.day and arrived.slot == before.slot and arrived.stats == before.stats and arrived.flags == before.flags and arrived.counts == before.counts and arrived.receipts == before.receipts and arrived.journal == before.journal and arrived.sequence == before.sequence, "ordinary walking changes only position and revision")
	_rejected(session, session.execute_walk_interaction("tea_seller", "old-revision", arrived.run_id, before.revision), arrived, "same-run old revision cannot initiate a new interaction")
	var greet: Dictionary = _interact(session, "tea_seller", "first-greeting")
	check(greet.ok and session.snapshot().flags.town_tea_greeted and greet.action_id == "greet_tea_seller", "near NPC first response registers one persistent consequence")
	var first: Dictionary = session.snapshot()
	check(first.stats == arrived.stats and first.day == arrived.day and first.slot == arrived.slot and greet.delta.slots == 0, "NPC reading gives no resource reward or clock cost")
	check(session.execute_walk_interaction("tea_seller", "first-greeting", first.run_id, -1).get("duplicate", false) and session.snapshot() == first, "duplicate NPC callback returns same receipt despite later revision")
	_rejected(session, session.execute_walk_interaction("street_sign", "first-greeting", first.run_id, first.revision), first, "an operation cannot change its target identity")
	_rejected(session, _move(session, [1010, 400]), first, "reading result occupies walking")
	_rejected(session, _interact(session, "tea_seller", "busy-greeting"), first, "busy reading cannot accept another interaction")
	check(session.acknowledge_result().ok, "NPC result releases ready state")
	var again: Dictionary = _interact(session, "tea_seller", "second-greeting")
	check(again.ok and again.action_id == "greet_tea_seller_again" and again.message != greet.message, "NPC visibly remembers the prior greeting")
	check(session.acknowledge_result().ok and _move(session, [1010, 560]).ok and _move(session, [710, 560]).ok, "walk from NPC to street sign stays on clear ground")
	var sign: Dictionary = _interact(session, "street_sign", "read-sign")
	check(sign.ok and session.snapshot().flags.town_sign_read and sign.delta.slots == 0, "near street sign read persists and is free")
	check(session.acknowledge_result().ok and _move(session, [160, 560]).ok and _move(session, [160, 260]).ok, "walk to actual mountain exit")
	var at_exit: Dictionary = session.snapshot()
	var home: Dictionary = _interact(session, "mountain_exit", "exit-home")
	check(home.ok and session.snapshot().scene == "tingyu_corridor" and home.delta.slots == 1 and session.snapshot().stats == at_exit.stats, "exit commits exactly one host travel cost and returns to cultivation")
	var returned: Dictionary = session.snapshot()
	check(session.execute_walk_interaction("mountain_exit", "exit-home", returned.run_id, -1).get("duplicate", false) and session.snapshot() == returned, "duplicate exit arrival cannot double-charge or return twice")
	check(session.acknowledge_result().ok, "return result releases cultivation")
	_town_ready(session)
	check(session.snapshot().exploration.positions.shanxia_town == [150, 560], "a new explicit town trip resets the town entrance spawn")
	check(session.snapshot().flags.town_tea_greeted and session.snapshot().flags.town_sign_read, "re-entry keeps remembered town consequences")
	check(_move(session, [200, 560]).ok, "the new trip can leave its entry position")
	var second_trip: Dictionary = session.snapshot()
	check(session.select_action("go_to_town", outbound_operation).get("duplicate", false) and session.snapshot() == second_trip, "replaying an old outbound receipt neither resets position nor charges again")
	var stale: Dictionary = session.snapshot()
	check(session.start_new().ok, "restart replaces current run")
	before = session.snapshot()
	_rejected(session, session.execute_walk_interaction("mountain_exit", "exit-home", stale.run_id, stale.revision), before, "old arrival callback cannot affect a new run")
	var wall_pack: Dictionary = town.duplicate(true)
	wall_pack.walks.scenes.shanxia_town.obstacles.append([1020, 300, 2, 100])
	wall_pack.walks.scenes.shanxia_town.interactions.tea_seller.position = [1060, 350]
	var wall_session: RefCounted = _new(wall_pack)
	_town_ready(wall_session)
	check(_move(wall_session, [1000, 560]).ok and _move(wall_session, [1000, 350]).ok, "thin-wall fixture approaches within interaction radius on its accessible side")
	var separated: Dictionary = wall_session.snapshot()
	_rejected(wall_session, _interact(wall_session, "tea_seller", "through-wall"), separated, "being inside the radius never permits interaction through a wall")

func _test_save_and_compatibility() -> void:
	var session: RefCounted = _new(town)
	_town_ready(session)
	check(_move(session, [710, 560]).ok and _interact(session, "street_sign", "saved-sign").ok, "saved fixture includes moved position and object flag")
	var expected: Dictionary = session.snapshot()
	var store = StoreScript.new()
	store.base_dir = base_dir
	check(session.can_save() and store.save_session(session).ok, "settled spatial result saves in isolated two-slot store")
	var reader: RefCounted = _new(town)
	check(store.load_session(reader).ok and reader.snapshot() == expected, "JSON save restores exact location position date attributes flags counts and receipts")
	check(reader.acknowledge_result().ok and reader.walk_view().position == [710, 560], "restoring the result does not reset town position")
	for kind: String in ["missing", "unknown_field", "schema", "extra_map", "fraction", "blocked", "outside"]:
		var bad: Dictionary = expected.duplicate(true)
		match kind:
			"missing": bad.erase("exploration")
			"unknown_field": bad.exploration["temporary_path"] = []
			"schema": bad.exploration.schema_version = 2
			"extra_map": bad.exploration.positions["unknown_town"] = [150, 560]
			"fraction": bad.exploration.positions.shanxia_town = [710.5, 560]
			"blocked": bad.exploration.positions.shanxia_town = [550, 400]
			"outside": bad.exploration.positions.shanxia_town = [-1, 20]
		var before: Dictionary = reader.snapshot()
		_rejected(reader, reader.restore(bad), before, "restore rejects malformed spatial snapshot " + kind)
	var forged: Dictionary = expected.duplicate(true)
	forged.receipts["saved-sign"].interaction_id = "mountain_exit"
	var before: Dictionary = reader.snapshot()
	_rejected(reader, reader.restore(forged), before, "restore rejects mismatched spatial receipt identity")
	var fixture: Dictionary = _new(town).snapshot()
	fixture.stats.energy = 0
	fixture.day = 3
	fixture.slot = 5
	check(reader.restore(fixture).ok, "boundary fixture restores zero energy on last slot")
	_town_ready(reader)
	check(reader.snapshot().day == 4 and reader.snapshot().slot == 0 and reader.snapshot().stats.energy == 0, "one outbound host settlement crosses day with zero energy")
	check(_move(reader, [160, 260]).ok and _interact(reader, "mountain_exit", "zero-energy-exit").ok and reader.snapshot().slot == 1, "zero energy still permits walked-to return exactly once")

func _test_original_mentor_five_and_isolation() -> void:
	var session: RefCounted = _new(town)
	check(session.select_action("talk_mentor", "mentor-open").ok, "original mentor event starts")
	var guard: int = 0
	while session.snapshot().phase == "event" and guard < 20:
		guard += 1
		var view: Dictionary = session.event_view()
		if view.get("type", "") == "choice":
			check(session.choose("take_lesson", "mentor-choice").ok, "original breathing choice settles")
		else:
			check(session.continue_event().ok, "original mentor dialogue advances")
	check(session.snapshot().flags.mentor_lesson_heard and session.snapshot().flags.breathing_hint, "lesson and one-use training hint survive as original host flags")
	check(session.acknowledge_result().ok, "mentor result closes")
	_town_ready(session)
	check(_move(session, [160, 260]).ok and _interact(session, "mountain_exit", "mentor-trip-home").ok and session.acknowledge_result().ok, "return from town keeps same mentor run")
	check(session.select_action("go_to_mountain").ok and session.acknowledge_result().ok, "original mountain entrance remains available")
	for aid: String in ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]:
		if session.snapshot().stats.energy < 22:
			check(session.select_action("rest_practice").ok and session.acknowledge_result().ok, "original rest recovers energy")
		var result: Dictionary = session.select_action(aid)
		check(result.ok and session.snapshot().phase == "performing", "original five-sword presentation preflight " + aid)
		var pending: Dictionary = session.pending_presentation()
		check(session.finish_presentation(str(pending.get("run_id", "")), str(pending.get("operation_id", ""))).ok and session.acknowledge_result().ok, "trusted completion retains original unique settlement " + aid)
	check(session.snapshot().stats.sword == 50 and session.snapshot().stats.cultivation == 6 and not session.snapshot().flags.breathing_hint, "five sword outcomes remain continuous and breathing bonus consumes once")
	check(session.select_action("return_to_corridor").ok and session.acknowledge_result().ok and session.select_action("report_practice").ok, "original return and mentor report remain available")
	guard = 0
	while session.snapshot().phase == "event" and guard < 20:
		guard += 1
		if session.event_view().get("type", "") == "choice":
			check(session.choose("with_lesson", "report-choice").ok, "original report response remains available")
		else:
			check(session.continue_event().ok, "original report dialogue completes")
	check(session.snapshot().flags.mentor_reported, "original report completion persists")
	var stream_session: RefCounted = _new(stream)
	var stream_initial: Dictionary = stream_session.snapshot()
	check(stream_initial.size() == 14 and not stream_initial.has("exploration") and stream_session.walk_view().is_empty(), "same runtime leaves Stream fourteen-field content and presentation isolated")
	var store = StoreScript.new()
	store.base_dir = base_dir
	check(store.save_session(stream_session).ok, "Stream saves in its own content directory")
	var stream_reader: RefCounted = _new(stream)
	check(store.load_session(stream_reader).ok and stream_reader.snapshot() == stream_initial, "Stream save round trip is unchanged")
	var town_reader: RefCounted = _new(town)
	check(store.load_session(town_reader).ok and town_reader.snapshot().flags.town_sign_read, "town checkpoint remains independent of Stream save")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		messages.append(text)
		push_error("FAIL: " + text)

func _finish() -> void:
	var report: Dictionary = {"checks": checks, "failures": failures, "messages": messages, "save_directory": base_dir, "scope": "host state tests; motion completion simulated, no browser/physical input claim"}
	var path: String = "res://.local/qa/cultivation-engine-town-walk/state-report.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("CULTIVATION_ENGINE_TOWN_WALK_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
