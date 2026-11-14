extends SceneTree
## Headless host boundary checks. These do not claim rendering or real UI play.

const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const Session = preload("res://addons/cultivation_mode/session.gd")
const Store = preload("res://addons/cultivation_mode/save_store.gd")
const MAPS := ["chengdu_gate", "chengdu_market", "chengdu_teahouse", "chengdu_river", "chengdu_lanes", "chengdu_square"]
var checks := 0
var failures := 0
var fixture: Dictionary = {}
var old_pack: Dictionary = {}
var save_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_town_walk/game.json")
	check(loaded.ok, "retained town package loads")
	if not loaded.ok:
		_finish()
		return
	old_pack = loaded.pack
	fixture = _fixture(old_pack)
	var issues: Array[String] = Loader.new().validate(fixture)
	check(issues.is_empty(), "six-map fixture validates: " + str(issues))
	if not issues.is_empty():
		_finish()
		return
	save_dir = "user://test_runs/chengdu-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	_test_invalid_content()
	_test_spatial_events()
	_test_entries_and_atomicity()
	_test_saves_and_old_packages()
	_test_real_package_if_present()
	_finish()

func _action(scene: String, menu: bool = false, target: String = "", event: String = "") -> Dictionary:
	return {"label": "test action", "description": "test fixture", "result": "recorded",
		"scenes": [scene], "menu": menu, "duration": 0, "costs": {}, "gains": {},
		"conditions": {"stats_gte": {}, "flags": {}}, "set_flags": {}, "once_key": "",
		"bonuses": [], "event": event, "target_scene": target, "character": ""}

func _fixture(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data.id = "chengdu_contract_fixture"
	data.version = "1.0.0"
	data._fingerprint = "chengdu-independent-contract-fixture".sha256_text()
	data.initial_scene = "chengdu_gate"
	data.initial_flags = {"conversation_done": false, "choice_paid": false}
	data.rules.goals = []
	data.scenes = {}
	data.actions = {}
	data.events = {}
	data.motions = {}
	data.voices = {}
	data.walks = {"schema_version": 1, "scenes": {}}
	for sid: String in MAPS:
		data.scenes[sid] = source.scenes.shanxia_town.duplicate(true)
		var aid := sid + "_read"
		data.actions[aid] = _action(sid)
		data.walks.scenes[sid] = {"size": [400, 300], "floor": [0, 0, 400, 300],
			"spawn": [50, 200], "entries": {"west": [30, 200], "east": [370, 200]},
			"actor_radius": 8, "cell_size": 20, "obstacles": [[150, 80, 100, 60]],
			"interactions": {sid + "_sign": {"label": "sign", "position": [60, 200], "radius": 32, "action": aid}}}
	data.actions["gate_to_market"] = _action("chengdu_gate", false, "chengdu_market")
	data.actions.gate_to_market["target_entry"] = "west"
	data.actions.gate_to_market.duration = 1
	data.actions.gate_to_market.costs = {"energy": 2}
	data.walks.scenes.chengdu_gate.interactions["east_exit"] = {"label": "market", "position": [370, 200], "radius": 32, "action": "gate_to_market"}
	data.actions["market_to_gate"] = _action("chengdu_market", false, "chengdu_gate")
	data.actions.market_to_gate["target_entry"] = "east"
	data.walks.scenes.chengdu_market.interactions["west_exit"] = {"label": "gate", "position": [30, 200], "radius": 32, "action": "market_to_gate"}
	data.actions["default_market"] = _action("chengdu_gate", true, "chengdu_market")
	data.actions["talk_local"] = _action("chengdu_gate", false, "", "local_conversation")
	data.walks.scenes.chengdu_gate.interactions["local_person"] = {"label": "person", "position": [60, 200], "radius": 32, "action": "talk_local"}
	data.actions["pay_local"] = _action("chengdu_gate")
	data.actions.pay_local.duration = 1
	data.actions.pay_local.costs = {"energy": 3}
	data.actions.pay_local.set_flags = {"choice_paid": true}
	data.events["local_conversation"] = {"title": "fixture conversation", "start": "hello", "nodes": {
		"hello": {"type": "say", "speaker": "mentor_zhixian", "text": "Hello.", "next": "choice"},
		"choice": {"type": "choice", "speaker": "player_yanqiu", "text": "Choose.", "options": [
			{"id": "pay", "label": "pay", "action": "pay_local", "next": "reply", "conditions": {"stats_gte": {}, "flags": {}}},
			{"id": "leave", "label": "leave", "action": "", "next": "done", "conditions": {"stats_gte": {}, "flags": {}}}]},
		"reply": {"type": "say", "speaker": "mentor_zhixian", "text": "Recorded.", "next": "done"},
		"done": {"type": "end", "text": "Done.", "set_flags": {"conversation_done": true}}}}
	return data

func _new(data: Dictionary = {}) -> RefCounted:
	var session = Session.new()
	check(session.configure(fixture if data.is_empty() else data).ok, "session configures")
	return session

func _move(session: RefCounted, point: Array) -> Dictionary:
	var state: Dictionary = session.snapshot()
	return session.commit_walk_position(state.scene, point, state.run_id, state.revision)

func _interact(session: RefCounted, id: String, op: String) -> Dictionary:
	var state: Dictionary = session.snapshot()
	return session.execute_walk_interaction(id, op, state.run_id, state.revision)

func _reject(session: RefCounted, result: Dictionary, before: Dictionary, label: String) -> void:
	check(not result.get("ok", false) and session.snapshot() == before, label + " rejects atomically")

func _test_invalid_content() -> void:
	for kind: String in ["unknown", "blocked", "fraction", "outside", "bad_id", "not_map", "missing_target", "entry_table", "choice_bypass"]:
		var bad := fixture.duplicate(true)
		match kind:
			"unknown": bad.actions.gate_to_market.target_entry = "missing"
			"blocked": bad.walks.scenes.chengdu_market.entries.west = [200, 100]
			"fraction": bad.walks.scenes.chengdu_market.entries.west = [30.5, 200]
			"outside": bad.walks.scenes.chengdu_market.entries.west = [410, 200]
			"bad_id": bad.actions.gate_to_market.target_entry = 5
			"not_map": bad.walks.scenes.erase("chengdu_market")
			"missing_target": bad.actions.gate_to_market.target_scene = ""
			"entry_table": bad.walks.scenes.chengdu_market.entries = []
			"choice_bypass": bad.events.local_conversation.nodes.choice.options[0].action = "talk_local"
		check(not Loader.new().validate(bad).is_empty(), "loader rejects " + kind)
		check(not Session.new().configure(bad).ok, "session rejects malformed contract " + kind)
	var plain := fixture.duplicate(true)
	plain.walks = {}
	check(not Loader.new().validate(plain).is_empty(), "target_entry cannot hide in a non-walking package")

func _test_spatial_events() -> void:
	var session := _new()
	var before: Dictionary = session.snapshot()
	_reject(session, session.select_action("talk_local", "menu-bypass"), before, "menu cannot enter spatial conversation")
	_reject(session, session.select_action("pay_local", "effect-bypass"), before, "menu cannot execute choice effect")
	check(_move(session, [300, 200]).ok, "walk away from local person")
	before = session.snapshot()
	_reject(session, _interact(session, "local_person", "distant"), before, "far conversation")
	check(_move(session, [60, 200]).ok, "walk close to local person")
	var arrived: Dictionary = session.snapshot()
	check(_interact(session, "local_person", "conversation-1").ok, "near person opens registered event")
	var talking: Dictionary = session.snapshot()
	check(talking.phase == "event" and talking.day == arrived.day and talking.slot == arrived.slot and talking.stats == arrived.stats, "opening conversation is free")
	check(not session.can_save(), "event phase cannot be saved")
	_reject(session, _move(session, [80, 200]), talking, "conversation blocks walking")
	check(session.execute_walk_interaction("local_person", "conversation-1", talking.run_id, -1).get("duplicate", false) and session.snapshot() == talking, "duplicate arrival does not reopen or advance event")
	check(session.cancel_event().ok and session.snapshot().phase == "ready" and not session.snapshot().flags.conversation_done, "cancel before end does not mark complete")
	check(_interact(session, "local_person", "conversation-2").ok and session.continue_event().ok, "re-enter reaches a choice")
	check(session.choose("pay", "paid-choice").ok, "registered choice effect executes")
	var paid: Dictionary = session.snapshot()
	check(paid.stats.energy == 97 and paid.slot == 1 and paid.flags.choice_paid and not paid.flags.conversation_done, "choice commits exactly its cost and consequence")
	check(session.choose("pay", "paid-choice").get("duplicate", false) and session.snapshot() == paid, "duplicate choice cannot charge twice")
	check(session.cancel_event().ok and session.snapshot().stats.energy == 97 and session.snapshot().flags.choice_paid, "cancel after choice preserves committed effect")
	check(_interact(session, "local_person", "conversation-3").ok and session.continue_event().ok and session.choose("leave", "free-leave").ok, "free leave path reaches end")
	check(not session.snapshot().flags.conversation_done, "displaying end does not commit completion")
	check(session.continue_event().ok and session.snapshot().flags.conversation_done and session.can_save(), "continuing end commits completion and releases safe save")
	check(session.snapshot().stats.energy == 97 and session.snapshot().slot == 1, "free leave and reading do not add costs")

func _test_entries_and_atomicity() -> void:
	var session := _new()
	check(_move(session, [370, 200]).ok, "reach east exit")
	var before: Dictionary = session.snapshot()
	check(_interact(session, "east_exit", "gate-market").ok, "directional exit commits travel")
	var market: Dictionary = session.snapshot()
	check(market.scene == "chengdu_market" and market.exploration.positions.chengdu_market == [30, 200], "east exit arrives at market west entrance")
	check(market.stats.energy == before.stats.energy - 2 and market.slot == before.slot + 1, "travel cost occurs in same transaction")
	check(session.execute_walk_interaction("east_exit", "gate-market", market.run_id, -1).get("duplicate", false) and session.snapshot() == market, "duplicate cross-scene arrival neither charges nor moves again")
	check(session.acknowledge_result().ok and _interact(session, "west_exit", "market-gate").ok, "return through matching west exit")
	check(session.snapshot().scene == "chengdu_gate" and session.snapshot().exploration.positions.chengdu_gate == [370, 200], "return arrives at gate east entrance")
	var defaults := _new()
	check(defaults.select_action("default_market", "default-spawn").ok and defaults.snapshot().exploration.positions.chengdu_market == [50, 200], "action without target_entry retains old spawn behavior")
	for kind: String in ["unknown", "blocked", "fraction", "wrong_type", "not_map"]:
		var changed := _new()
		check(_move(changed, [370, 200]).ok, "reach exit before runtime rejection " + kind)
		match kind:
			"unknown": changed.pack.actions.gate_to_market.target_entry = "missing"
			"blocked": changed.pack.walks.scenes.chengdu_market.entries.west = [200, 100]
			"fraction": changed.pack.walks.scenes.chengdu_market.entries.west = [30.5, 200]
			"wrong_type": changed.pack.actions.gate_to_market.target_entry = []
			"not_map": changed.pack.walks.scenes.erase("chengdu_market")
		before = changed.snapshot()
		_reject(changed, _interact(changed, "east_exit", "invalid-" + kind), before, "runtime bad entry " + kind)

func _test_saves_and_old_packages() -> void:
	var session := _new()
	check(_move(session, [370, 200]).ok and _interact(session, "east_exit", "saved-travel").ok, "saved fixture crosses district boundary")
	var saved: Dictionary = session.snapshot()
	check(saved.size() == 15 and saved.exploration.schema_version == 1 and saved.exploration.size() == 2, "named arrivals add no persistent fields")
	var store = Store.new()
	store.base_dir = save_dir
	check(store.save_session(session).ok, "safe travel result saves")
	var reader := _new()
	check(store.load_session(reader).ok and reader.snapshot() == saved, "JSON save restores exact map entry, time, resources and receipts")
	check(reader.acknowledge_result().ok and reader.walk_view().position == [30, 200], "restored travel does not reset arrival to spawn")
	var retained := _new(old_pack)
	check(retained.snapshot().size() == 15 and retained.snapshot().exploration.positions == {"shanxia_town": [150, 560]}, "old walk package retains its original state shape and spawn")
	for manifest: String in ["res://games/shu_mentor_loop/game.json", "res://games/stream_study/game.json"]:
		var loaded: Dictionary = Loader.new().load_pack(manifest)
		check(loaded.ok, "old non-walking package loads " + manifest)
		if loaded.ok:
			var old := _new(loaded.pack)
			check(old.snapshot().size() == 14 and not old.snapshot().has("exploration"), "old package retains strict fourteen-field state")
			var snapshot: Dictionary = old.snapshot()
			check(store.save_session(old).ok, "old package still saves")
			var old_reader := _new(loaded.pack)
			check(store.load_session(old_reader).ok and old_reader.snapshot() == snapshot, "old package checkpoint remains isolated")

func _test_real_package_if_present() -> void:
	if not FileAccess.file_exists("res://games/shu_chengdu/game.json"):
		return
	var loaded: Dictionary = Loader.new().load_pack("res://games/shu_chengdu/game.json")
	check(loaded.ok, "actual Chengdu content package loads: " + str(loaded.get("errors", [])))
	if loaded.ok:
		for sid: String in MAPS:
			check(loaded.pack.walks.scenes.has(sid), "actual package registers district " + sid)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	print("CULTIVATION_ENGINE_CHENGDU_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
