extends SceneTree

const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const JourneyScript = preload("res://addons/cultivation_mode/journey_session.gd")
const StoreScript = preload("res://addons/cultivation_mode/save_store.gd")
const MANIFEST := "res://games/shu_first_journey/game.json"
var checks := 0
var failures := 0
var pack: Dictionary
var base_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = LoaderScript.new().load_pack(MANIFEST)
	check(bool(loaded.get("ok", false)), "complete chapter loads: " + str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	pack = loaded.pack
	base_dir = "user://test_runs/first-journey-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_gates_and_forgery()
	_test_complete_journey(true, 1, false)
	_test_complete_journey(false, 2, true)
	_test_withdrawal_and_reset()
	_finish()


func _new() -> RefCounted:
	var session: RefCounted = JourneyScript.new()
	var result: Dictionary = session.call("configure", pack)
	check(bool(result.get("ok", false)), "chapter Session configures: " + str(result.get("reason", "")))
	return session


func _test_gates_and_forgery() -> void:
	var session := _new()
	var initial: Dictionary = session.call("snapshot")
	check(initial.size() == 15 and initial.scene == "tingyu_corridor" and initial.stats.sword == 0, "chapter begins in corridor on existing strict host state")
	check(session.call("journey_ending").is_empty(), "new run has no fabricated ending")
	_rejected(session, session.call("select_action", "go_to_town", "skip-training"), initial, "cannot skip heard lesson and sword practice")
	_rejected(session, session.call("select_action", "journey_report", "skip-chapter"), initial, "cannot complete chapter before encounter and return")
	_rejected(session, session.call("begin_ambush", initial.run_id, "skip-commission", initial.revision), initial, "cannot start encounter in corridor")
	for action_id: String in ["ambush_win", "ambush_loss", "greet_tea_seller"]:
		_rejected(session, session.call("select_action", action_id, "forge-" + action_id), initial, "menu cannot forge " + action_id)
	var forged: Dictionary = initial.duplicate(true)
	forged.flags.journey_complete = true
	_rejected(session, session.call("restore", forged), initial, "restore rejects completion without receipt")
	forged = initial.duplicate(true)
	forged.flags.journey_victory = true
	_rejected(session, session.call("restore", forged), initial, "restore rejects outcome without actual battle receipt")
	_listen(session, false)
	var heard: Dictionary = session.call("snapshot")
	check(heard.flags.mentor_lesson_heard and not heard.flags.mentor_practice_finished, "free lesson choice records hearing without fabricated practice")
	_rejected(session, session.call("select_action", "go_to_town", "skip-sword"), heard, "heard lesson alone cannot skip practice")


func _prepare_town(session: RefCounted, practices: int, paid_lesson: bool) -> void:
	_listen(session, paid_lesson)
	_act(session, "go_to_mountain")
	for index: int in range(practices):
		var action_id := "pine_wind" if index == 0 else "swift_swallow"
		var before: Dictionary = session.call("snapshot")
		var trained: Dictionary = session.call("select_action", action_id, "practice-%d" % index)
		check(bool(trained.get("ok", false)), "registered sword action preflights before settlement")
		if not bool(trained.get("ok", false)):
			return
		var pending: Dictionary = session.call("pending_presentation")
		var after: Dictionary = session.call("snapshot")
		check(after.phase == "performing" and after.stats.energy == before.stats.energy - 22 and after.stats.sword == before.stats.sword + 10, "practice keeps original energy22/sword10 rules")
		check(int(trained.delta.slots) == 1 and int(trained.delta.stats.get("cultivation", 0)) == (6 if paid_lesson and index == 0 else 0), "practice uses one slot and consumes mentor bonus only once")
		check(bool(session.call("finish_presentation", pending.run_id, pending.operation_id).get("ok", false)), "real pending sword presentation closes")
		check(bool(session.call("acknowledge_result").get("ok", false)), "sword receipt returns to ready")
	_act(session, "return_to_corridor")
	_act(session, "go_to_town")
	var town: Dictionary = session.call("snapshot")
	_rejected(session, session.call("begin_ambush", town.run_id, "before-commission", town.revision), town, "town arrival still requires commission")
	_rejected(session, session.call("execute_walk_interaction", "tea_seller", "distant-commission", town.run_id, town.revision), town, "commission requires walking near merchant")
	_walk(session, [[1010, 560], [1010, 350]])
	var near: Dictionary = session.call("snapshot")
	var commission: Dictionary = session.call("execute_walk_interaction", "tea_seller", "commission", near.run_id, near.revision)
	check(bool(commission.get("ok", false)), "nearby merchant grants commission through existing walk interaction")
	var commissioned: Dictionary = session.call("snapshot")
	check(commissioned.flags.journey_commission and commissioned.counts.get("greet_tea_seller", 0) == 1 and commission.delta.slots == 0 and commission.delta.stats.is_empty(), "commission is free and recorded once")
	check(bool(session.call("execute_walk_interaction", "tea_seller", "commission", near.run_id, near.revision).get("duplicate", false)) and session.call("snapshot") == commissioned, "duplicate commission cannot grant again")
	check(bool(session.call("acknowledge_result").get("ok", false)), "commission receipt returns to town")


func _test_complete_journey(victory: bool, practices: int, paid_lesson: bool) -> void:
	var session := _new()
	_prepare_town(session, practices, paid_lesson)
	var before: Dictionary = session.call("snapshot")
	var store: RefCounted = StoreScript.new()
	store.set("base_dir", base_dir + ("-win" if victory else "-loss"))
	check(bool(store.call("save_session", session).get("ok", false)), "prebattle chapter checkpoint saves")
	_rejected(session, session.call("begin_ambush", before.run_id, "stale-revision", before.revision + 1), before, "stale encounter revision cannot begin")
	var started: Dictionary = session.call("begin_ambush", before.run_id, "chapter-battle", before.revision)
	check(bool(started.get("ok", false)), "commission starts actual pinned encounter")
	if not bool(started.get("ok", false)):
		return
	var battle: RefCounted = session.call("battle")
	var bonus := 4 if practices >= 2 else 0
	var player: Dictionary = battle.call("unit", "player")
	check(player.hp == 22 + bonus and player.max_hp == 22 + bonus and int(session.call("journey_training_bonus")) == bonus, "training affects actual rules-owned player HP before encounter")
	check(battle.call("unit", "tinglan").hp == 18 and int(started.context.training_hp_bonus) == bonus, "training affects only player and reports precise host bonus")
	check(FileAccess.get_file_as_string(str(pack.ambush.encounter_path)).sha256_text() == str(pack.ambush.encounter_sha256), "training leaves original pinned encounter bytes intact")
	var fighting: Dictionary = session.call("snapshot")
	check(fighting.stats == before.stats and fighting.slot == before.slot and fighting.sequence == before.sequence, "beginning encounter does not charge or modify cultivation stats")
	check(not bool(store.call("save_session", session).get("ok", true)), "live encounter cannot save")
	_rejected(session, session.call("restore", before), fighting, "loading cannot interrupt live encounter")
	_rejected(session, session.call("finish_ambush", before.run_id, "chapter-battle"), fighting, "UI cannot fabricate terminal combat state")
	_rejected(session, session.call("select_action", "ambush_win", "forged-live-win"), fighting, "UI cannot submit reserved victory action")
	check(bool(session.call("begin_ambush", before.run_id, "chapter-battle", before.revision).get("duplicate", false)) and session.call("snapshot") == fighting, "duplicate live encounter request is idempotent")
	if victory:
		_play_victory(battle)
	else:
		for index: int in range(6):
			if battle.call("snapshot").phase == "lost":
				break
			check(bool(battle.call("end_round").get("ok", false)), "unprotected medicine encounter progresses through real enemy actions")
	var combat: Dictionary = battle.call("snapshot")
	check(combat.phase == ("won" if victory else "lost") and combat.outcome == ("victory" if victory else "defeat"), "unmodified encounter reaches actual intended outcome")
	var settled: Dictionary = session.call("finish_ambush", before.run_id, "chapter-battle")
	check(bool(settled.get("ok", false)), "rules terminal settles one chapter fact")
	if not bool(settled.get("ok", false)):
		return
	var after: Dictionary = session.call("snapshot")
	check(after.flags.ambush_resolved and after.flags.journey_victory == victory and after.flags.journey_defeat != victory and not after.flags.journey_complete, "combat locks outcome while chapter awaits return and report")
	check(settled.delta.slots == 1 and after.stats == before.stats and after.scene == "shanxia_town", "battle costs exactly one slot and returns to town without invented reward")
	check(bool(session.call("finish_ambush", before.run_id, "chapter-battle").get("duplicate", false)) and session.call("snapshot") == after, "terminal callback is applied once")
	check(bool(store.call("save_session", session).get("ok", false)), "terminal battle result saves without live match")
	var resumed := _new()
	check(bool(store.call("load_session", resumed).get("ok", false)) and resumed.call("snapshot") == after and resumed.call("battle") == null, "postbattle save restores exact chapter fact without replay")
	check(bool(session.call("close_ambush", before.run_id, "chapter-battle").get("ok", false)), "settled encounter view closes")
	check(bool(session.call("acknowledge_result").get("ok", false)), "battle receipt returns to safe town")
	var ready: Dictionary = session.call("snapshot")
	_rejected(session, session.call("begin_ambush", ready.run_id, "rewrite-outcome", ready.revision), ready, "cannot retry settled chapter to rewrite outcome")
	_rejected(session, session.call("select_action", "journey_report", "report-in-town"), ready, "chapter requires physical return to corridor")
	_walk(session, [[1010, 560], [160, 560], [160, 260]])
	var at_exit: Dictionary = session.call("snapshot")
	check(bool(session.call("execute_walk_interaction", "mountain_exit", "return-home", at_exit.run_id, at_exit.revision).get("ok", false)), "town exit returns through normal travel action")
	check(bool(session.call("acknowledge_result").get("ok", false)), "return receipt closes")
	var report_before: Dictionary = session.call("snapshot")
	var report: Dictionary = session.call("select_action", "journey_report", "finish-chapter")
	check(bool(report.get("ok", false)), "both outcomes can report and finish chapter")
	var ending: Dictionary = session.call("journey_ending")
	check(session.call("snapshot").flags.journey_complete and ending.get("outcome", "") == ("victory" if victory else "defeat"), "ending matches actual single encounter outcome")
	check(report.get("message", "").contains(str(ending.get("title", ""))) and report.delta.slots == 0 and session.call("snapshot").stats == report_before.stats, "outcome-specific ending is a free authoritative system receipt")
	var completed: Dictionary = session.call("snapshot")
	check(bool(session.call("select_action", "journey_report", "finish-chapter").get("duplicate", false)) and session.call("snapshot") == completed, "same final operation cannot complete twice")
	check(bool(store.call("save_session", session).get("ok", false)), "chapter ending checkpoint saves")
	check(bool(store.call("load_session", resumed).get("ok", false)) and resumed.call("snapshot") == completed and resumed.call("journey_ending") == ending, "reading final checkpoint preserves exact ending")
	var forged: Dictionary = completed.duplicate(true)
	forged.flags.journey_victory = not victory
	forged.flags.journey_defeat = victory
	_rejected(resumed, resumed.call("restore", forged), completed, "restoring cannot switch ending independently of battle receipt")
	check(bool(session.call("acknowledge_result").get("ok", false)), "final receipt releases cultivation")
	var completed_ready: Dictionary = session.call("snapshot")
	_rejected(session, session.call("select_action", "journey_report", "second-report"), completed_ready, "chapter report is once per new run")
	_act(session, "rest_practice")
	check(session.call("journey_ending") == ending, "continued cultivation leaves completed ending unchanged")
	_act(session, "go_to_town")
	_walk(session, [[150, 260]])
	var revisit: Dictionary = session.call("snapshot")
	check(bool(session.call("execute_walk_interaction", "mountain_exit", "later-return-home", revisit.run_id, revisit.revision).get("ok", false)), "completed chapter may later visit town and return")
	check(bool(session.call("acknowledge_result").get("ok", false)), "later return receipt closes")
	var continuing: Dictionary = session.call("snapshot")
	check(bool(store.call("save_session", session).get("ok", false)), "continued town round trip remains saveable after chapter ending")
	check(bool(store.call("load_session", resumed).get("ok", false)) and resumed.call("snapshot") == continuing and resumed.call("journey_ending") == ending, "continued travel restores while preserving original chapter ending")
	check(bool(session.call("start_new").get("ok", false)), "explicit new game resets chapter")
	var reset: Dictionary = session.call("snapshot")
	check(reset.run_id != before.run_id and reset.scene == "tingyu_corridor" and reset.counts.is_empty() and not reset.flags.journey_commission and not reset.flags.journey_complete and not reset.flags.ambush_resolved and session.call("journey_ending").is_empty(), "new game clears outcome and restores complete playable route")
	_rejected(session, session.call("finish_ambush", before.run_id, "chapter-battle"), reset, "old encounter callback cannot affect new chapter")


func _test_withdrawal_and_reset() -> void:
	var session := _new()
	_prepare_town(session, 1, false)
	var before: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", before.run_id, "withdraw", before.revision).get("ok", false)), "withdrawal starts a legitimate encounter")
	check(bool(session.call("abandon_ambush", before.run_id, "withdraw").get("ok", false)), "withdrawal settles real abandoned terminal state")
	check(session.call("snapshot").flags.journey_defeat and session.call("snapshot").counts.get("ambush_loss", 0) == 1, "withdrawal locks the complete defeat route")
	var after: Dictionary = session.call("snapshot")
	_rejected(session, session.call("begin_ambush", before.run_id, "retry-withdrawal", after.revision), after, "withdrawal cannot retry this chapter")
	check(bool(session.call("start_new").get("ok", false)), "new game can restart after withdrawal")
	_prepare_town(session, 2, false)
	var next: Dictionary = session.call("snapshot")
	check(bool(session.call("begin_ambush", next.run_id, "fresh-encounter", next.revision).get("ok", false)) and session.call("battle").call("unit", "player").hp == 26, "new chapter may train again and create its own fresh encounter")


func _listen(session: RefCounted, paid: bool) -> void:
	var opened: Dictionary = session.call("select_action", "talk_mentor")
	check(bool(opened.get("ok", false)), "existing mentor dialogue opens")
	for index: int in range(4):
		check(not str(session.call("event_view").get("voice", "")).is_empty(), "mentor opening retains authored voice binding")
		check(bool(session.call("continue_event").get("ok", false)), "mentor dialogue advances")
	check(bool(session.call("choose", "take_lesson" if paid else "return_to_practice").get("ok", false)), "existing mentor choice resolves")
	for index: int in range(3):
		check(bool(session.call("continue_event").get("ok", false)), "chosen mentor branch reaches heard ending")
	check(bool(session.call("acknowledge_result").get("ok", false)), "mentor result closes")


func _act(session: RefCounted, action_id: String) -> void:
	var result: Dictionary = session.call("select_action", action_id)
	check(bool(result.get("ok", false)), "registered action settles: " + action_id + ": " + str(result.get("reason", "")))
	if bool(result.get("ok", false)):
		check(bool(session.call("acknowledge_result").get("ok", false)), "action receipt closes: " + action_id)


func _walk(session: RefCounted, points: Array) -> void:
	for point: Array in points:
		var before: Dictionary = session.call("snapshot")
		var moved: Dictionary = session.call("commit_walk_position", "shanxia_town", point, before.run_id, before.revision)
		check(bool(moved.get("ok", false)), "walk follows valid open street segment: " + str(point))


func _play_victory(battle: RefCounted) -> void:
	# The original public-rules victory path; no combat-state fixture or hp edits.
	for command: Array in [
		["use_skill", "player", "push", [4, 3]], ["move_unit", "player", [4, 3]],
		["use_skill", "tinglan", "interrupt", [5, 4]], ["end_round"],
		["use_skill", "player", "push", [5, 3]], ["move_unit", "player", [6, 3]],
		["use_skill", "tinglan", "interrupt", [5, 4]], ["end_round"],
		["use_skill", "player", "push", [7, 3]], ["move_unit", "player", [7, 3]],
		["use_skill", "tinglan", "strike", [5, 4]], ["end_round"],
		["use_skill", "player", "strike", [8, 3]], ["end_round"]
	]:
		var args := command.duplicate()
		var method := str(args.pop_front())
		var result: Dictionary = battle.callv(method, args)
		check(bool(result.get("ok", false)), "authored encounter victory command: " + str(command))


func _rejected(session: RefCounted, result: Dictionary, before: Dictionary, label: String) -> void:
	check(not bool(result.get("ok", false)) and session.call("snapshot") == before, label + " without mutation")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _finish() -> void:
	print("FIRST_JOURNEY_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
