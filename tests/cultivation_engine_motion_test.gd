extends SceneTree

const LoaderScript := preload("res://addons/cultivation_mode/pack_loader.gd")
const SessionScript := preload("res://addons/cultivation_mode/session.gd")
const StoreScript := preload("res://addons/cultivation_mode/save_store.gd")
const SHU_MANIFEST := "res://games/shu_entry/game.json"
const STREAM_MANIFEST := "res://games/stream_study/game.json"
const SOURCE_MANUALS := "res://assets/data/sword_manuals.json"
const SOURCE_SETS := "res://assets/art/jiang_sword_cycle/sets.json"
const REPORT_PATH := "res://.local/qa/cultivation-engine-v02/state-report.json"

const EXPECTED_CLIPS := {
	"pine_wind": "songfeng",
	"listening_rain": "chuanyun",
	"returning_tide": "huilan",
	"rising_peak": "tiaoyue",
	"swift_swallow": "xieying",
}
const EXPECTED_LABELS := {
	"pine_wind": "松风剑",
	"listening_rain": "穿云剑",
	"returning_tide": "回澜剑",
	"rising_peak": "挑月剑",
	"swift_swallow": "斜影剑",
}
const EXPECTED_ACTION_IDS := ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]

var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var loader: Variant
var shu_pack: Dictionary = {}
var stream_pack: Dictionary = {}
var test_base: String = ""
var _bad_manifest_path: String = ""
var _bad_manifest_dir: String = ""
var _owns_bad_manifest_dir: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	loader = LoaderScript.new()
	var shu_result: Dictionary = loader.load_pack(SHU_MANIFEST)
	var stream_result: Dictionary = loader.load_pack(STREAM_MANIFEST)
	check(bool(shu_result.get("ok", false)), "the v0.2 authored shu_entry pack loads through PackLoader")
	check(bool(stream_result.get("ok", false)), "the unchanged stream_study pack still loads through PackLoader")
	if not bool(shu_result.get("ok", false)) or not bool(stream_result.get("ok", false)):
		_finish()
		return
	shu_pack = shu_result.get("pack", {})
	stream_pack = stream_result.get("pack", {})
	test_base = _allocate_test_base()
	if test_base.is_empty():
		check(false, "an unused isolated user-data directory is available for the state test")
		_finish()
		return

	_check_five_content_mappings()
	_check_preflight_rejections()
	_check_insufficient_resource_atomicity()
	_check_performing_guards_and_completion()
	_check_reset_invalidates_old_completion()
	_check_result_save_restore_and_next_motion()
	_check_renamed_content_ids()
	_check_stream_stays_static_and_saves_independently()
	_finish()


func _check_five_content_mappings() -> void:
	var motion_registry: Dictionary = shu_pack.get("motions", {})
	var motion: Dictionary = motion_registry.get("jiang_sword", {})
	var clips: Dictionary = motion.get("clips", {})
	var actions: Dictionary = shu_pack.get("actions", {})
	var action_ids: Array[String] = []
	for action_value: Variant in actions.keys():
		var action: Dictionary = actions[action_value]
		if action.has("presentation"):
			action_ids.append(str(action_value))
	action_ids.sort()
	var expected_ids: Array[String] = []
	for key: Variant in EXPECTED_CLIPS.keys():
		expected_ids.append(str(key))
	expected_ids.sort()
	check(action_ids == expected_ids, "the only motion actions are the five stable formal manual IDs")
	var expected_clip_ids: Array[String] = []
	for action_id: String in EXPECTED_ACTION_IDS:
		expected_clip_ids.append(str(EXPECTED_CLIPS[action_id]))
	var actual_clip_ids: Array[String] = []
	for clip_key: Variant in clips.keys():
		actual_clip_ids.append(str(clip_key))
	expected_clip_ids.sort()
	actual_clip_ids.sort()
	check(actual_clip_ids == expected_clip_ids, "the selected motion registry exposes exactly the five approved clip IDs")
	check(motion.get("character", "") == "player_yanqiu", "the sword motion binds to its declared scene character")
	check(str(motion.get("idle", "")) == "res://assets/art/jiang_sword_cycle/idle/frames.json", "the content registry uses the accepted Jiang idle manifest")
	check(is_equal_approx(float(motion.get("settle_seconds", -1.0)), 0.25), "the content registry keeps the approved 0.25 second settle")
	check(is_equal_approx(float(motion.get("hold_seconds", -1.0)), 0.8), "the content registry keeps the approved 0.8 second result hold")
	var sword_stat_count: int = 0
	var stat_rules: Array = shu_pack.get("rules", {}).get("stats", [])
	for stat_value: Variant in stat_rules:
		if stat_value is Dictionary and str(stat_value.get("id", "")) == "sword":
			sword_stat_count += 1
	check(sword_stat_count == 1, "the Shu pack declares one generic sword stat")

	var manuals_data: Variant = _read_json(SOURCE_MANUALS)
	var sets_data: Variant = _read_json(SOURCE_SETS)
	check(manuals_data is Dictionary and sets_data is Dictionary, "the source manual and clip catalogs are readable JSON")
	if not (manuals_data is Dictionary and sets_data is Dictionary):
		return
	var manuals: Array = manuals_data.get("manuals", [])
	var source_sets: Array = sets_data.get("sets", [])
	var manual_by_id: Dictionary = {}
	for manual_value: Variant in manuals:
		if manual_value is Dictionary:
			manual_by_id[str(manual_value.get("id", ""))] = manual_value
	var set_by_id: Dictionary = {}
	for set_value: Variant in source_sets:
		if set_value is Dictionary:
			set_by_id[str(set_value.get("id", ""))] = set_value
	check(manuals.size() == 5 and source_sets.size() == 5, "the accepted source catalogs each define exactly five swords")

	for action_id: String in expected_ids:
		var clip_id: String = str(EXPECTED_CLIPS[action_id])
		var action: Dictionary = actions.get(action_id, {})
		var presentation: Dictionary = action.get("presentation", {})
		var clip: Dictionary = clips.get(clip_id, {})
		var manual: Dictionary = manual_by_id.get(action_id, {})
		var source_set: Dictionary = set_by_id.get(clip_id, {})
		check(str(action.get("label", "")) == str(EXPECTED_LABELS[action_id]), "%s preserves its approved display name" % action_id)
		check(bool(action.get("show_count", false)), "%s opts into the generic cumulative action count" % action_id)
		check(str(presentation.get("motion", "")) == "jiang_sword" and str(presentation.get("clip", "")) == clip_id, "%s maps to the correct motion and clip ID" % action_id)
		check(str(manual.get("clip_id", "")) == clip_id and str(manual.get("title", "")) == str(EXPECTED_LABELS[action_id]), "%s matches the existing formal manual catalog" % action_id)
		check(str(clip.get("manifest", "")) == str(source_set.get("manifest_path", "")), "%s resolves to the accepted atlas frame manifest" % action_id)
		check(clip.get("phases", []) == source_set.get("phases", []), "%s keeps the accepted phase labels and boundaries" % action_id)
		check(action.get("costs", {}).get("energy", -1) == 22 and action.get("gains", {}).get("sword", -1) == 10 and action.get("duration", -1) == 1, "%s keeps the authored 22 energy / 10 sword / one-slot settlement" % action_id)
		check(manual.get("techniques", []).size() == 1, "%s retains exactly one approved technique" % action_id)
		check(FileAccess.file_exists(str(clip.get("manifest", ""))), "%s frame manifest exists in the runtime closure" % action_id)

	var mountain: Dictionary = shu_pack.get("scenes", {}).get("back_mountain", {})
	var matching_actor: bool = false
	for actor_value: Variant in mountain.get("actors", []):
		if actor_value is Dictionary and str(actor_value.get("character", "")) == "player_yanqiu" and str(actor_value.get("motion", "")) == "jiang_sword":
			matching_actor = true
	check(matching_actor, "back_mountain declares a player actor with the generic sword motion")


func _check_preflight_rejections() -> void:
	var invalid_clip_pack: Dictionary = shu_pack.duplicate(true)
	invalid_clip_pack["actions"]["pine_wind"]["presentation"]["clip"] = "missing_clip"
	_expect_preflight_rejection(invalid_clip_pack, "pine_wind", "invalid-clip", "an unknown clip is rejected before settlement")

	var missing_manifest_pack: Dictionary = shu_pack.duplicate(true)
	missing_manifest_pack["motions"]["jiang_sword"]["clips"]["songfeng"]["manifest"] = "res://assets/.engine_motion_missing_%d.json" % Time.get_ticks_usec()
	_expect_preflight_rejection(missing_manifest_pack, "pine_wind", "missing-manifest", "a missing clip manifest is rejected before settlement")

	var created_bad_region_fixture: bool = _create_bad_region_fixture()
	check(created_bad_region_fixture, "the test creates an isolated malformed-region manifest under assets")
	if created_bad_region_fixture:
		var bad_region_pack: Dictionary = shu_pack.duplicate(true)
		bad_region_pack["motions"]["jiang_sword"]["clips"]["songfeng"]["manifest"] = _bad_manifest_path
		_expect_preflight_rejection(bad_region_pack, "pine_wind", "bad-region", "an out-of-bounds atlas cell is rejected before settlement")


func _expect_preflight_rejection(candidate: Dictionary, action_id: String, operation_id: String, label: String) -> void:
	var session: Variant = _session_at_mountain(candidate)
	if session == null:
		return
	var before: Dictionary = session.snapshot()
	var result: Dictionary = session.select_action(action_id, operation_id)
	check(not bool(result.get("ok", false)) and str(result.get("code", "")) == "presentation_unavailable", label)
	check(session.snapshot() == before, "%s leaves the complete state snapshot unchanged" % label)
	check(session.pending_presentation().is_empty(), "%s creates no pending presentation" % label)


func _check_insufficient_resource_atomicity() -> void:
	var session: Variant = _session_at_mountain(shu_pack, 21)
	if session == null:
		return
	var before: Dictionary = session.snapshot()
	var result: Dictionary = session.select_action("pine_wind", "motion-insufficient-energy")
	check(not bool(result.get("ok", false)) and str(result.get("code", "")) == "insufficient_resource", "a fully preflighted sword motion still respects insufficient energy")
	check(session.snapshot() == before, "insufficient energy leaves stats, time, flags, counts, receipts and journal unchanged")
	check(session.pending_presentation().is_empty(), "insufficient energy creates no pending animation")


func _check_performing_guards_and_completion() -> void:
	var session: Variant = _session_at_mountain(shu_pack)
	if session == null:
		return
	var operation_id: String = "motion-perform-once"
	var result: Dictionary = session.select_action("pine_wind", operation_id)
	check(bool(result.get("ok", false)) and str(result.get("operation_id", "")) == operation_id, "an accepted animated action commits one stable operation ID")
	if not bool(result.get("ok", false)):
		return
	var performing: Dictionary = session.snapshot()
	check(str(performing.get("phase", "")) == "performing", "an animated action enters the performing phase")
	check(performing.get("counts", {}).get("pine_wind", 0) == 1, "the action count settles once before animation completion")
	check(performing.get("stats", {}).get("energy", -1) == 78 and performing.get("stats", {}).get("sword", -1) == 10, "the actual action settlement applies its configured cost and gain once")
	check(performing.get("slot", -1) == 1 and performing.get("sequence", -1) == 1, "time and sequence settle once before the player starts")
	check(not bool(session.can_save()), "the session refuses a performing save boundary")
	var save_store: Variant = _new_store(test_base.path_join("busy_guard"))
	check(not bool(save_store.save_session(session).get("ok", false)), "SaveStore refuses to write while an action is performing")
	var before_blocked_inputs: Dictionary = session.snapshot()
	var ready_candidate: Dictionary = before_blocked_inputs.duplicate(true)
	ready_candidate["phase"] = "ready"
	check(not bool(session.restore(ready_candidate).get("ok", false)), "restore refuses to replace a performing session")
	check(session.snapshot() == before_blocked_inputs, "refused performing restore preserves the active transaction")
	check(not bool(session.acknowledge_result().get("ok", false)), "result acknowledgement is unavailable during performing")
	check(not bool(session.continue_event().get("ok", false)), "event continuation is unavailable during performing")
	check(not bool(session.cancel_event().get("ok", false)), "event cancellation is unavailable during performing")
	var available: Array[Dictionary] = session.available_actions()
	var all_actions_disabled: bool = true
	for action: Dictionary in available:
		all_actions_disabled = all_actions_disabled and not bool(action.get("enabled", false))
	check(all_actions_disabled, "the performing phase disables every menu action")
	check(session.snapshot() == before_blocked_inputs, "blocked menu and phase paths preserve the transaction")

	var pending: Dictionary = session.pending_presentation()
	check(str(pending.get("run_id", "")) == str(performing.get("run_id", "")) and str(pending.get("operation_id", "")) == operation_id, "pending presentation binds to the current run and operation")
	check(str(pending.get("action_id", "")) == "pine_wind" and str(pending.get("motion_id", "")) == "jiang_sword" and str(pending.get("clip_id", "")) == "songfeng", "pending presentation carries content-selected action, motion and clip IDs")
	check(pending.get("receipt", {}) == result, "pending presentation carries a copied actual settlement receipt")
	var assets: Dictionary = pending.get("assets", {})
	for key: String in ["idle_frames", "action_frames", "idle_fps", "action_fps", "anchor", "cell_size", "phases", "settle_seconds", "hold_seconds", "motion_id", "clip_id"]:
		check(assets.has(key), "preflight assets expose %s to the generic presenter" % key)
	var exposed_pending: Dictionary = session.pending_presentation()
	exposed_pending["motion_id"] = "mutated-copy"
	check(str(session.pending_presentation().get("motion_id", "")) == "jiang_sword", "pending_presentation returns a defensive copy")

	var before_duplicate: Dictionary = session.snapshot()
	var duplicate: Dictionary = session.select_action("pine_wind", operation_id)
	check(bool(duplicate.get("ok", false)) and bool(duplicate.get("duplicate", false)), "a repeated operation ID returns its prior settlement while performing")
	check(session.snapshot() == before_duplicate, "repeating an operation ID cannot settle a second time")
	check(str(session.pending_presentation().get("operation_id", "")) == operation_id, "duplicate input does not replace or restart the pending player")

	var before_stale: Dictionary = session.snapshot()
	check(not bool(session.finish_presentation("stale-run", operation_id).get("ok", false)), "a completion from another run is rejected")
	check(not bool(session.finish_presentation(str(performing.get("run_id", "")), "stale-operation").get("ok", false)), "a completion from another operation is rejected")
	check(session.snapshot() == before_stale and not session.pending_presentation().is_empty(), "stale completion leaves the live action and pending assets intact")

	var receipt_before: Dictionary = performing.get("last_result", {}).duplicate(true)
	var counts_before: Dictionary = performing.get("counts", {}).duplicate(true)
	var receipts_before: Dictionary = performing.get("receipts", {}).duplicate(true)
	var journal_before: Array = performing.get("journal", []).duplicate(true)
	var stats_before: Dictionary = performing.get("stats", {}).duplicate(true)
	var revision_before: int = int(performing.get("revision", 0))
	var completion: Dictionary = session.finish_presentation(str(performing.get("run_id", "")), operation_id)
	check(bool(completion.get("ok", false)) and str(completion.get("phase", "")) == "result", "synthetic session completion advances to result")
	var completed: Dictionary = session.snapshot()
	check(completed.get("counts", {}) == counts_before and completed.get("receipts", {}) == receipts_before and completed.get("journal", []) == journal_before, "synthetic completion does not change counts, receipts or journal")
	check(completed.get("last_result", {}) == receipt_before and completed.get("stats", {}) == stats_before, "synthetic completion does not mutate the committed receipt or resource settlement")
	check(int(completed.get("revision", 0)) == revision_before + 1 and int(completed.get("sequence", 0)) == int(performing.get("sequence", 0)), "completion advances only the presentation revision, not the action sequence")
	check(session.pending_presentation().is_empty(), "completion clears its transient presentation bundle")
	var before_duplicate_finish: Dictionary = session.snapshot()
	check(not bool(session.finish_presentation(str(performing.get("run_id", "")), operation_id).get("ok", false)), "a second completion callback is rejected")
	check(session.snapshot() == before_duplicate_finish, "duplicate completion cannot mutate the result")


func _check_reset_invalidates_old_completion() -> void:
	var session: Variant = _session_at_mountain(shu_pack)
	if session == null:
		return
	var accepted: Dictionary = session.select_action("listening_rain", "motion-reset-old")
	if not bool(accepted.get("ok", false)):
		check(false, "the reset fixture starts an accepted pending motion")
		return
	var old_run_id: String = str(session.snapshot().get("run_id", ""))
	check(not session.pending_presentation().is_empty(), "the reset fixture has a live presentation")
	check(bool(session.start_new().get("ok", false)), "a new run is explicitly allowed to clear a pending action")
	var new_run_state: Dictionary = session.snapshot()
	check(str(new_run_state.get("run_id", "")) != old_run_id and new_run_state.get("sequence", -1) == 0, "reset changes run identity and clears the sequence")
	check(session.pending_presentation().is_empty(), "reset discards the old transient presentation")
	check(not bool(session.finish_presentation(old_run_id, "motion-reset-old").get("ok", false)), "a delayed callback from before reset is rejected")
	check(session.snapshot() == new_run_state, "the stale pre-reset callback leaves the new run unchanged")


func _check_result_save_restore_and_next_motion() -> void:
	var session: Variant = _session_at_mountain(shu_pack)
	if session == null:
		return
	var operation_id: String = "motion-result-save"
	var accepted: Dictionary = session.select_action("pine_wind", operation_id)
	if not bool(accepted.get("ok", false)):
		check(false, "the result-save fixture starts its first motion")
		return
	check(_finish_synthetically(session), "synthetic session completion creates the first saved result")
	var saved_state: Dictionary = session.snapshot()
	var store: Variant = _new_store(test_base.path_join("result_restore"))
	check(bool(store.save_session(session).get("ok", false)), "SaveStore accepts the completed motion result")
	check(bool(session.acknowledge_result().get("ok", false)), "the saved result can be acknowledged before a later action")
	var rest: Dictionary = session.select_action("rest_practice", "motion-result-mutate")
	check(bool(rest.get("ok", false)) and session.snapshot() != saved_state, "a later ordinary action mutates the active run after the checkpoint")
	check(bool(store.load_session(session).get("ok", false)), "loading restores the saved completed-motion result")
	check(session.snapshot() == saved_state, "load restores exact counts, last_result, receipts, resources and run metadata")
	check(session.pending_presentation().is_empty(), "result load contains no pending animation to replay")
	var before_duplicate: Dictionary = session.snapshot()
	var replay: Dictionary = session.select_action("pine_wind", operation_id)
	check(bool(replay.get("ok", false)) and bool(replay.get("duplicate", false)), "the saved operation remains idempotent after restore")
	check(session.snapshot() == before_duplicate and session.pending_presentation().is_empty(), "re-reading a result never replays or re-settles its animation")
	check(bool(session.acknowledge_result().get("ok", false)), "the restored result can continue into the next choice")
	var next_motion: Dictionary = session.select_action("listening_rain", "motion-after-restore")
	check(bool(next_motion.get("ok", false)) and str(session.snapshot().get("phase", "")) == "performing", "the next selected motion works after save continuation")
	if bool(next_motion.get("ok", false)):
		check(session.snapshot().get("counts", {}).get("pine_wind", 0) == 1 and session.snapshot().get("counts", {}).get("listening_rain", 0) == 1, "continuation keeps the old count and settles the next sword once")
		check(_finish_synthetically(session), "synthetic completion closes the post-restore motion")
	var previous_run: String = str(session.snapshot().get("run_id", ""))
	check(bool(session.start_new().get("ok", false)) and str(session.snapshot().get("run_id", "")) != previous_run, "new run starts with a fresh run identity after continuation")
	check(session.snapshot().get("counts", {}).is_empty() and session.pending_presentation().is_empty(), "new run clears prior counts and transient presentation")


func _check_renamed_content_ids() -> void:
	var renamed: Dictionary = shu_pack.duplicate(true)
	var old_character_id: String = "player_yanqiu"
	var new_character_id: String = "actor_alpha"
	var old_motion_id: String = "jiang_sword"
	var new_motion_id: String = "motion_alpha"
	var character_catalog: Dictionary = renamed.get("characters", {})
	var character: Dictionary = character_catalog.get(old_character_id, {}).duplicate(true)
	character_catalog.erase(old_character_id)
	character_catalog[new_character_id] = character
	renamed["characters"] = character_catalog
	var clip_remap: Dictionary = {}
	var motion_registry: Dictionary = renamed.get("motions", {})
	var motion: Dictionary = motion_registry.get(old_motion_id, {}).duplicate(true)
	var old_clips: Dictionary = motion.get("clips", {})
	var new_clips: Dictionary = {}
	var old_clip_ids: Array[String] = []
	for action_id: String in EXPECTED_ACTION_IDS:
		old_clip_ids.append(str(EXPECTED_CLIPS[action_id]))
	for index: int in range(old_clip_ids.size()):
		var old_clip_id: String = old_clip_ids[index]
		var new_clip_id: String = "clip_%02d" % index
		new_clips[new_clip_id] = old_clips.get(old_clip_id, {}).duplicate(true)
		clip_remap[old_clip_id] = new_clip_id
	motion["character"] = new_character_id
	motion["clips"] = new_clips
	motion_registry.erase(old_motion_id)
	motion_registry[new_motion_id] = motion
	renamed["motions"] = motion_registry
	for scene_key: Variant in renamed.get("scenes", {}).keys():
		var scene: Dictionary = renamed["scenes"][scene_key]
		var present: Array = scene.get("present", [])
		for index: int in range(present.size()):
			if str(present[index]) == old_character_id:
				present[index] = new_character_id
		scene["present"] = present
		var actors: Array = scene.get("actors", [])
		for actor_index: int in range(actors.size()):
			var actor: Dictionary = actors[actor_index]
			if str(actor.get("character", "")) == old_character_id:
				actor["character"] = new_character_id
			if str(actor.get("motion", "")) == old_motion_id:
				actor["motion"] = new_motion_id
			actors[actor_index] = actor
		scene["actors"] = actors
		renamed["scenes"][scene_key] = scene
	for event_key: Variant in renamed.get("events", {}).keys():
		var event: Dictionary = renamed["events"][event_key]
		var nodes: Dictionary = event.get("nodes", {})
		for node_key: Variant in nodes:
			var node: Dictionary = nodes[node_key]
			if str(node.get("speaker", "")) == old_character_id:
				node["speaker"] = new_character_id
	for action_id: String in EXPECTED_CLIPS.keys():
		var action: Dictionary = renamed["actions"][action_id]
		var presentation: Dictionary = action.get("presentation", {}).duplicate(true)
		presentation["motion"] = new_motion_id
		presentation["clip"] = clip_remap[str(EXPECTED_CLIPS[action_id])]
		action["presentation"] = presentation
		renamed["actions"][action_id] = action
	check(loader.validate(renamed).is_empty(), "renamed generic motion, clip and character IDs remain a valid pack")
	var session: Variant = _session_at_mountain(renamed)
	if session == null:
		return
	var result: Dictionary = session.select_action("pine_wind", "renamed-content-action")
	check(bool(result.get("ok", false)), "session preflight has no Shu, character or clip-name branch")
	if not bool(result.get("ok", false)):
		return
	var pending: Dictionary = session.pending_presentation()
	check(str(pending.get("motion_id", "")) == new_motion_id and str(pending.get("clip_id", "")) == "clip_00", "preflight resolves renamed IDs through pack data")
	check(_finish_synthetically(session), "synthetic completion accepts renamed generic IDs")


func _check_stream_stays_static_and_saves_independently() -> void:
	var shu_session: Variant = _session_at_mountain(shu_pack)
	if shu_session == null:
		return
	var shu_action: Dictionary = shu_session.select_action("pine_wind", "pack-isolation-shu")
	if not bool(shu_action.get("ok", false)):
		check(false, "pack-isolation fixture performs a Shu sword action")
		return
	check(_finish_synthetically(shu_session), "synthetic Shu completion settles before the independent-save probe")
	var store: Variant = _new_store(test_base.path_join("pack_isolation"))
	var shu_saved: Dictionary = shu_session.snapshot()
	check(bool(store.save_session(shu_session).get("ok", false)), "the Shu v0.2 result saves in its own pack slot")

	var stream_session: Variant = _new_session(stream_pack)
	check(stream_session.pack.get("motions", {}).is_empty(), "stream_study remains a static text-only pack")
	var stream_actions: Dictionary = stream_session.pack.get("actions", {})
	var has_motion_action: bool = false
	for action_value: Variant in stream_actions.values():
		if action_value is Dictionary and action_value.has("presentation"):
			has_motion_action = true
	check(not has_motion_action, "stream_study has no motion presentation actions")
	var walk: Dictionary = stream_session.select_action("walk_to_river", "pack-isolation-stream-walk")
	check(bool(walk.get("ok", false)) and str(stream_session.snapshot().get("phase", "")) == "result", "stream travel keeps the ordinary immediate result flow")
	check(stream_session.pending_presentation().is_empty(), "stream actions never create a sword playback bundle")
	check(not stream_session.snapshot().get("stats", {}).has("sword"), "stream state contains no Shu sword stat")
	var stream_saved: Dictionary = stream_session.snapshot()
	check(bool(store.save_session(stream_session).get("ok", false)), "stream result saves in its independent pack slot")
	check(store.has_save(shu_pack) and store.has_save(stream_pack), "the same local store discovers both independent pack saves")
	check(bool(stream_session.acknowledge_result().get("ok", false)), "stream result acknowledges without animation")
	var read: Dictionary = stream_session.select_action("read_by_river", "pack-isolation-stream-mutate")
	check(bool(read.get("ok", false)) and stream_session.snapshot() != stream_saved, "a later stream action mutates only stream state")
	check(bool(store.load_session(stream_session).get("ok", false)), "stream load restores its own saved result")
	check(stream_session.snapshot() == stream_saved and stream_session.pending_presentation().is_empty(), "stream restore preserves its exact result without a player or pending motion")

	check(bool(shu_session.acknowledge_result().get("ok", false)), "the saved Shu result can be acknowledged before a later change")
	var shu_rest: Dictionary = shu_session.select_action("rest_practice", "pack-isolation-shu-mutate")
	check(bool(shu_rest.get("ok", false)), "the Shu mutation fixture changes the active state after its save")
	check(bool(store.load_session(shu_session).get("ok", false)), "Shu load selects the Shu checkpoint, not the stream checkpoint")
	check(shu_session.snapshot() == shu_saved and shu_session.snapshot().get("counts", {}).get("pine_wind", 0) == 1, "Shu load restores its exact sword count and receipt independently")
	check(stream_session.snapshot() == stream_saved, "loading Shu leaves the stream session untouched")


func _session_at_mountain(data: Dictionary, energy: int = -1) -> Variant:
	var session: Variant = _new_session(data)
	if session == null:
		return null
	var fixture: Dictionary = session.snapshot()
	fixture["scene"] = "back_mountain"
	if energy >= 0:
		fixture["stats"]["energy"] = energy
	var restored: Dictionary = session.restore(fixture)
	check(bool(restored.get("ok", false)), "synthetic state fixture enters the authored mountain scene")
	return session if bool(restored.get("ok", false)) else null


func _new_session(data: Dictionary) -> Variant:
	var session: Variant = SessionScript.new()
	var configured: Dictionary = session.configure(data)
	check(bool(configured.get("ok", false)), "EngineSession configures pack %s" % str(data.get("id", "?")))
	return session if bool(configured.get("ok", false)) else null


func _new_store(folder: String) -> Variant:
	var store: Variant = StoreScript.new()
	store.base_dir = folder
	return store


func _allocate_test_base() -> String:
	for attempt: int in range(20):
		var candidate: String = "user://cultivation_engine_motion_test_%d_%d" % [Time.get_ticks_usec(), attempt]
		var absolute_path: String = ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute_path) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func _finish_synthetically(session: Variant) -> bool:
	var pending: Dictionary = session.pending_presentation()
	if pending.is_empty():
		check(false, "synthetic completion fixture has a pending bundle")
		return false
	var result: Dictionary = session.finish_presentation(str(pending.get("run_id", "")), str(pending.get("operation_id", "")))
	var ok: bool = bool(result.get("ok", false))
	check(ok, "synthetic session completion accepts its matching run and operation IDs")
	return ok


func _create_bad_region_fixture() -> bool:
	var source: Variant = _read_json("res://assets/art/jiang_sword_cycle/action/frames.json")
	if not source is Dictionary:
		return false
	var manifest: Dictionary = source.duplicate(true)
	var frames: Array = manifest.get("frames", [])
	if frames.is_empty() or not frames[0] is Dictionary:
		return false
	var first_frame: Dictionary = frames[0].duplicate(true)
	var region: Array = first_frame.get("region", []).duplicate()
	if region.size() != 4:
		return false
	# Stay within the manifest's integer limit so preflight reaches the real
	# AtlasTexture bounds check against the existing legal PNG page.
	region[0] = 65536
	first_frame["region"] = region
	frames[0] = first_frame
	manifest["frames"] = frames
	for attempt: int in range(100):
		var suffix: String = "%d_%d" % [Time.get_ticks_usec(), attempt]
		var directory: String = "res://assets/.engine_motion_test_" + suffix
		var absolute_directory: String = ProjectSettings.globalize_path(directory)
		var path: String = directory.path_join("frames.json")
		if DirAccess.dir_exists_absolute(absolute_directory) or FileAccess.file_exists(path):
			continue
		if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
			return false
		_bad_manifest_dir = directory
		_bad_manifest_path = path
		_owns_bad_manifest_dir = true
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_cleanup_bad_region_fixture()
			return false
		file.store_string(JSON.stringify(manifest, "\t", true, true) + "\n")
		file.flush()
		var written: bool = file.get_error() == OK
		file.close()
		return written and FileAccess.file_exists(path)
	return false


func _cleanup_bad_region_fixture() -> void:
	if not _owns_bad_manifest_dir:
		return
	var absolute_file: String = ProjectSettings.globalize_path(_bad_manifest_path)
	var absolute_directory: String = ProjectSettings.globalize_path(_bad_manifest_dir)
	if FileAccess.file_exists(_bad_manifest_path):
		DirAccess.remove_absolute(absolute_file)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)
	check(not FileAccess.file_exists(_bad_manifest_path) and not DirAccess.dir_exists_absolute(absolute_directory), "the test removes only its owned temporary malformed manifest")
	_owns_bad_manifest_dir = false


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: JSON = JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parsed.data


func _cleanup_test_tree(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(filename))
	for dirname: String in directory.get_directories():
		_cleanup_test_tree(path.path_join(dirname))
		DirAccess.remove_absolute(absolute_path.path_join(dirname))
	DirAccess.remove_absolute(absolute_path)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	failure_messages.append(message)
	push_error("FAIL: " + message)


func _finish() -> void:
	_cleanup_bad_region_fixture()
	if not test_base.is_empty():
		_cleanup_test_tree(test_base)
	var report: Dictionary = {
		"test": "cultivation_engine_motion_test",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"synthetic_session_completion": true,
		"result": ("PASS" if failures == 0 else "FAIL")
	}
	var report_parent: String = REPORT_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_parent))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write test report: " + REPORT_PATH)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Test report write failed: " + REPORT_PATH)
		file.close()
	print("CULTIVATION_ENGINE_MOTION_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)
