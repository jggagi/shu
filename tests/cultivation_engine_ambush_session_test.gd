extends SceneTree

const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const AmbushSessionScript = preload("res://addons/cultivation_mode/ambush_session.gd")
const SessionScript = preload("res://addons/cultivation_mode/session.gd")
const StoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const MANIFEST := "res://games/shu_mountain_ambush/game.json"
var checks := 0
var failures := 0
var pack: Dictionary
var base_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = LoaderScript.new().load_pack(MANIFEST)
	check(bool(loaded.get("ok", false)), "isolated ambush content loads " + str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	pack = loaded.pack
	base_dir = "user://test_runs/ambush-session-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_checkpoint_and_terminal()
	_test_authored_victory()
	_test_live_restart_protocol()
	_test_identity_and_bypass()
	_test_pack_isolation()
	_finish()


func _new() -> RefCounted:
	var session: RefCounted = AmbushSessionScript.new()
	check(bool(session.call("configure", pack).get("ok", false)), "ambush Session configures pinned encounter")
	return session


func _test_checkpoint_and_terminal() -> void:
	var session := _new()
	var store: RefCounted = StoreScript.new()
	store.set("base_dir", base_dir)
	var before: Dictionary = session.call("snapshot")
	check(before.size() == 15 and before.scene == "shanxia_town" and before.phase == "ready", "new safe state retains exact fifteen-field host contract")
	check(bool(session.call("can_save")), "prebattle state can save")
	check(bool(store.call("save_session", session).get("ok", false)), "prebattle checkpoint writes")
	var started: Dictionary = session.call("begin_ambush", before.run_id, "first-ambush", before.revision)
	check(bool(started.get("ok", false)), "start prepares live rules without settling")
	var fighting: Dictionary = session.call("snapshot")
	check(fighting.phase == "ambush" and fighting.sequence == before.sequence and fighting.stats == before.stats and fighting.slot == before.slot and fighting.receipts == before.receipts, "battle start only occupies phase and revision")
	check(not bool(session.call("can_save")) and not bool(store.call("save_session", session).get("ok", true)), "battle cannot be checkpointed")
	_rejected(session, session.call("restore", before), fighting, "restore cannot interrupt live battle")
	_rejected(session, session.call("finish_ambush", before.run_id, "first-ambush"), fighting, "UI completion cannot fabricate a nonterminal victory")
	_rejected(session, session.call("select_action", "rest_practice", "busy-rest"), fighting, "cultivation actions cannot settle during battle")
	var duplicate_start: Dictionary = session.call("begin_ambush", before.run_id, "first-ambush", before.revision)
	check(bool(duplicate_start.get("duplicate", false)) and session.call("snapshot") == fighting, "same live start is idempotent despite prior revision")
	var abandoned: Dictionary = session.call("abandon_ambush", before.run_id, "first-ambush")
	check(bool(abandoned.get("ok", false)), "withdrawal reaches one real lost rule state and host settlement")
	var after: Dictionary = session.call("snapshot")
	check(after.phase == "result" and after.sequence == before.sequence + 1 and after.slot == before.slot + 1 and after.stats == before.stats, "withdrawal charges exactly one time unit and no stat reward")
	check(after.scene == before.scene and after.exploration == before.exploration and after.flags.ambush_defeat and after.flags.ambush_resolved and not after.flags.ambush_victory, "loss retains original location and writes correct flags")
	check(after.counts.get("ambush_loss", 0) == 1 and after.journal.size() == 1 and after.receipts.size() == 1, "one withdrawal creates one action count, journal entry and receipt")
	check(bool(session.call("finish_ambush", before.run_id, "first-ambush").get("duplicate", false)) and session.call("snapshot") == after, "duplicate completed callback never charges or awards twice")
	check(bool(session.call("can_save")) and bool(store.call("save_session", session).get("ok", false)), "postbattle result is a safe checkpoint")
	var resumed := _new()
	check(bool(store.call("load_session", resumed).get("ok", false)) and resumed.call("snapshot") == after, "fresh Session restores exact terminal checkpoint")
	check(resumed.call("battle") == null and resumed.call("ambush_context").is_empty(), "restored result neither replays nor resurrects encounter")
	check(bool(resumed.call("finish_ambush", before.run_id, "first-ambush").get("duplicate", false)) and resumed.call("snapshot") == after, "late callback after checkpoint restore remains duplicate only")
	check(bool(session.call("close_ambush", before.run_id, "first-ambush").get("ok", false)) and bool(session.call("acknowledge_result").get("ok", false)), "terminal view closes back into original town")
	var ready: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", ready.run_id, "second-ambush", ready.revision).get("ok", false)), "retry starts a separate live encounter")
	var retry: Dictionary = session.call("snapshot")
	check(bool(session.call("finish_ambush", before.run_id, "first-ambush").get("duplicate", false)) and session.call("snapshot") == retry, "previous battle callback cannot settle current retry")
	check(bool(session.call("abandon_ambush", before.run_id, "second-ambush").get("ok", false)), "second withdrawal settles its own identity")
	var twice: Dictionary = session.call("snapshot")
	check(twice.slot == before.slot + 2 and twice.counts.get("ambush_loss", 0) == 2 and twice.receipts.size() == 2, "each retry is charged once as a new encounter")
	var bad: Dictionary = twice.duplicate(true)
	bad["combat"] = {"phase": "won"}
	_rejected(resumed, resumed.call("restore", bad), after, "strict restore rejects extra combat state")


func _test_identity_and_bypass() -> void:
	var session := _new()
	var before: Dictionary = session.call("snapshot")
	_rejected(session, session.call("begin_ambush", "obsolete-run", "stale", before.revision), before, "stale run cannot start")
	_rejected(session, session.call("begin_ambush", before.run_id, "stale-revision", before.revision + 1), before, "stale revision cannot start")
	for action_id: String in ["ambush_win", "ambush_loss"]:
		_rejected(session, session.call("select_action", action_id, "forged-" + action_id), before, "menu cannot forge " + action_id)
	for action: Dictionary in session.call("available_actions"):
		check(str(action.id) not in ["ambush_win", "ambush_loss"], "settlement actions are absent from displayed actions")
	check(bool(session.call("begin_ambush", before.run_id, "reset-old", before.revision).get("ok", false)), "start reset candidate")
	check(bool(session.call("start_new").get("ok", false)), "explicit new run invalidates encounter")
	var reset: Dictionary = session.call("snapshot")
	check(reset.run_id != before.run_id and session.call("battle") == null and session.call("ambush_context").is_empty(), "new run drops all temporary encounter identity")
	_rejected(session, session.call("finish_ambush", before.run_id, "reset-old"), reset, "completion from old run cannot settle after reset")
	_rejected(session, session.call("abandon_ambush", before.run_id, "reset-old"), reset, "withdrawal from old run cannot settle after reset")
	var bad: Dictionary = pack.duplicate(true)
	bad.ambush.encounter_sha256 = "wrong"
	_rejected(session, session.call("configure", bad), reset, "encounter bytes must match content version pin")


func _test_authored_victory() -> void:
	var session := _new()
	var before: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", before.run_id, "real-victory", before.revision).get("ok", false)), "authored victory starts through normal Session API")
	var battle: RefCounted = session.call("battle")
	# Play the unmodified authored encounter through public rules only. Repeated
	# pushes move the brute's announced strike away from the medicine basket;
	# interrupting the blade buys time, then a normal strike finishes that enemy.
	check(bool(battle.call("use_skill", "player", "push", [4, 3]).get("ok", false)), "round one pushes brute into the north barricade")
	var collision_state: Dictionary = battle.call("snapshot")
	check(battle.call("unit", "brute").pos == [5, 3] and int(battle.call("unit", "brute").hp) == 9 and int(collision_state.barricades[0].hp) == 0, "real authored collision breaks the barricade without carrying the enemy through it")
	check(bool(battle.call("move_unit", "player", [4, 3]).get("ok", false)), "round one follows to the near side of the broken gate")
	check(bool(battle.call("use_skill", "tinglan", "interrupt", [5, 4]).get("ok", false)), "round one interrupts blade")
	check(bool(battle.call("end_round").get("ok", false)), "round one resolves")
	check(bool(battle.call("use_skill", "player", "push", [5, 3]).get("ok", false)), "round two pushes brute freely through the opened route")
	check(bool(battle.call("move_unit", "player", [6, 3]).get("ok", false)), "round two walks through the destroyed barricade cell")
	check(bool(battle.call("use_skill", "tinglan", "interrupt", [5, 4]).get("ok", false)), "round two keeps blade interrupted")
	check(bool(battle.call("end_round").get("ok", false)), "round two resolves")
	check(bool(battle.call("use_skill", "player", "push", [7, 3]).get("ok", false)), "round three tests boundary collision and breaks brute attack")
	check(bool(battle.call("move_unit", "player", [7, 3]).get("ok", false)), "round three follows to the mountain edge")
	check(bool(battle.call("use_skill", "tinglan", "strike", [5, 4]).get("ok", false)), "round three blade is defeated by direct strike")
	check(bool(battle.call("end_round").get("ok", false)), "round three resolves")
	check(bool(battle.call("use_skill", "player", "strike", [8, 3]).get("ok", false)), "round four finishes displaced brute")
	check(bool(battle.call("end_round").get("ok", false)), "round four resolves")
	var terminal: Dictionary = battle.call("snapshot")
	check(terminal.phase == "won" and terminal.outcome == "victory" and int(terminal.objective.hp) > 0, "real authored encounter reaches survival victory with protected objective")
	check(bool(session.call("finish_ambush", before.run_id, "real-victory").get("ok", false)), "rules-owned victory submits host action")
	var after: Dictionary = session.call("snapshot")
	check(after.phase == "result" and after.flags.ambush_victory and not after.flags.ambush_defeat and after.counts.get("ambush_win", 0) == 1 and after.slot == before.slot + 1, "verified victory persists once with correct time and flags")
	var store: RefCounted = StoreScript.new()
	store.set("base_dir", base_dir + "-victory")
	check(bool(store.call("save_session", session).get("ok", false)), "victory is a safe checkpoint")
	var resumed := _new()
	check(bool(store.call("load_session", resumed).get("ok", false)) and resumed.call("snapshot") == after and resumed.call("battle") == null, "victory restores through strict checkpoint without replay")


func _test_pack_isolation() -> void:
	for path: String in ["res://games/shu_town_walk/game.json", "res://games/shu_mentor_loop/game.json", "res://games/stream_study/game.json"]:
		var loaded: Dictionary = LoaderScript.new().load_pack(path)
		check(bool(loaded.get("ok", false)), "original content loads: " + path)
		if not bool(loaded.get("ok", false)):
			continue
		var original: RefCounted = SessionScript.new()
		check(bool(original.call("configure", loaded.pack).get("ok", false)), "original Session configures original pack")
		var prior: Dictionary = original.call("snapshot")
		check(prior.size() == (15 if path.contains("town_walk") else 14) and not original.has_method("begin_ambush"), "old strict state and runtime APIs are unchanged")
		check(not prior.flags.has("ambush_resolved"), "new battle flags never appear in old packs")


func _test_live_restart_protocol() -> void:
	var session := _new()
	var before: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", before.run_id, "restart-original", before.revision).get("ok", false)), "live restart begins original encounter")
	check(bool(session.call("abandon_ambush", before.run_id, "restart-original").get("ok", false)), "restarting a live encounter first settles withdrawal")
	var settled: Dictionary = session.call("snapshot")
	check(settled.slot == before.slot + 1 and settled.counts.get("ambush_loss", 0) == 1, "live restart charges original encounter one time unit")
	check(bool(session.call("abandon_ambush", before.run_id, "restart-original").get("duplicate", false)) and bool(session.call("finish_ambush", before.run_id, "restart-original").get("duplicate", false)) and session.call("snapshot") == settled, "repeated abandon and finish during restart do not charge time twice")
	check(bool(session.call("close_ambush", before.run_id, "restart-original").get("ok", false)) and bool(session.call("acknowledge_result").get("ok", false)), "restart releases the settled encounter before beginning another")
	var ready: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", ready.run_id, "restart-new", ready.revision).get("ok", false)), "restart uses a new operation identity")
	var restarted: Dictionary = session.call("snapshot")
	check(restarted.phase == "ambush" and restarted.slot == settled.slot and restarted.sequence == settled.sequence and session.call("ambush_context").get("operation_id", "") == "restart-new", "new encounter starts without another settlement or time charge")
	_rejected(session, session.call("abandon_ambush", before.run_id, "restart-original"), restarted, "obsolete restart callback cannot abandon the new encounter")
	_rejected(session, session.call("close_ambush", before.run_id, "restart-original"), restarted, "obsolete restart close cannot release the new encounter")
	check(bool(session.call("finish_ambush", before.run_id, "restart-original").get("duplicate", false)) and session.call("snapshot") == restarted, "original completion remains a duplicate while replacement battle is active")


func _rejected(session: RefCounted, result: Dictionary, before: Dictionary, label: String) -> void:
	check(not bool(result.get("ok", false)) and session.call("snapshot") == before, label + " without state mutation")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _finish() -> void:
	print("AMBUSH_SESSION_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
