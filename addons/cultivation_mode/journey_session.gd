extends "res://addons/cultivation_mode/ambush_session.gd"
## One complete chapter on the existing host. Persistent progress remains in the
## original flags/counts/receipts; the live encounter is still never a checkpoint.

const REPORT_ACTION := "journey_report"
const SWORD_THRESHOLD := 20
const TRAINING_HP_BONUS := 4
const SWORD_ACTIONS := ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]


func configure(data: Dictionary) -> Dictionary:
	var chapter := _dict_or_empty(data.get("journey"))
	var endings := _dict_or_empty(chapter.get("endings"))
	if data.get("id", "") != "shu_first_journey" or data.get("initial_scene", "") != "tingyu_corridor":
		return _failure("初次下山内容入口无效", "invalid_journey")
	if chapter.get("training_sword_threshold") != SWORD_THRESHOLD or chapter.get("training_hp_bonus") != TRAINING_HP_BONUS:
		return _failure("初次下山修习规则无效", "invalid_journey")
	for outcome: String in ["victory", "defeat"]:
		var ending := _dict_or_empty(endings.get(outcome))
		if str(ending.get("title", "")).is_empty() or str(ending.get("text", "")).is_empty():
			return _failure("初次下山结尾内容缺失", "invalid_journey")
	var report := _dict_or_empty(_dict_or_empty(data.get("actions")).get(REPORT_ACTION))
	if report.is_empty() or report.get("menu", false) != true or not str(report.get("event", "")).is_empty():
		return _failure("初次下山复命行动无效", "invalid_journey")
	return super.configure(data)


func journey_training_bonus() -> int:
	return TRAINING_HP_BONUS if int(_dict_or_empty(state.get("stats")).get("sword", 0)) >= SWORD_THRESHOLD else 0


func begin_ambush(expected_run_id: String, operation_id: String = "", expected_revision: int = -1) -> Dictionary:
	# A completed encounter is a chapter fact, including a withdrawal. The base
	# adapter still owns stale identities, busy checks and verified settlement.
	if expected_run_id != str(state.get("run_id", "")):
		return _failure("这场山道请求已过期", "stale_run")
	if bool(_dict_or_empty(state.get("flags")).get("ambush_resolved", false)):
		return _failure("此行山道的经历已经记下；返山复命，或重新开始体验另一段经历", "journey_resolved")
	var original := _encounter
	var prepared := original.duplicate(true)
	var bonus := journey_training_bonus()
	if bonus > 0:
		for member: Dictionary in prepared.get("units", []):
			if member.get("id", "") == "player":
				member["hp"] = int(member.get("hp", 0)) + bonus
				member["max_hp"] = int(member.get("max_hp", member.hp - bonus)) + bonus
	# Derive only this live match before the rules object is configured. Neither
	# the original pinned encounter file nor the pack fingerprint is changed.
	_encounter = prepared
	var result := super.begin_ambush(expected_run_id, operation_id, expected_revision)
	_encounter = original
	if bool(result.get("ok", false)):
		_ambush_context["training_hp_bonus"] = bonus
		result["context"] = ambush_context()
	return result


func journey_ending() -> Dictionary:
	if not bool(_dict_or_empty(state.get("flags")).get("journey_complete", false)):
		return {}
	return _ending_for_flags(_dict_or_empty(state.get("flags")))


func _ending_for_flags(flags: Dictionary) -> Dictionary:
	var victory := bool(flags.get("journey_victory", false))
	var defeat := bool(flags.get("journey_defeat", false))
	if victory == defeat:
		return {}
	var outcome := "victory" if victory else "defeat"
	var endings := _dict_or_empty(_dict_or_empty(pack.get("journey")).get("endings"))
	var ending := _dict_or_empty(endings.get(outcome)).duplicate(true)
	ending["outcome"] = outcome
	return ending


func _prepare_action(action_id: String, action: Dictionary, operation_id: String, kind: String, source: Dictionary) -> Dictionary:
	var effective := action
	if action_id == REPORT_ACTION:
		var ending := _ending_for_flags(_dict_or_empty(state.get("flags")))
		if ending.is_empty():
			return {"ok": false, "reason": "请先走完护药山道，再如实复命", "code": "conditions_failed"}
		effective = action.duplicate(true)
		effective["result"] = str(ending.get("title", "")) + "\n\n" + str(ending.get("text", ""))
	return super._prepare_action(action_id, effective, operation_id, kind, source)


func _snapshot_error(candidate: Dictionary) -> String:
	var base_error := super._snapshot_error(candidate)
	if not base_error.is_empty():
		return base_error
	var flags := _dict_or_empty(candidate.get("flags"))
	var counts := _dict_or_empty(candidate.get("counts"))
	var wins := int(counts.get("ambush_win", 0))
	var losses := int(counts.get("ambush_loss", 0))
	var commissioned := int(counts.get("greet_tea_seller", 0))
	var reported := int(counts.get(REPORT_ACTION, 0))
	if commissioned > 1 or reported > 1 or wins + losses > 1:
		return "本章委托、山道经历与复命只能各记一次"
	if bool(flags.get("journey_commission", false)) != (commissioned == 1):
		return "护药委托与领取回执不一致"
	if bool(flags.get("ambush_resolved", false)) != (wins + losses == 1):
		return "山道经过与战斗回执不一致"
	if bool(flags.get("ambush_victory", false)) != (wins == 1) or bool(flags.get("journey_victory", false)) != (wins == 1):
		return "本章胜利经历与回执不一致"
	if bool(flags.get("ambush_defeat", false)) != (losses == 1) or bool(flags.get("journey_defeat", false)) != (losses == 1):
		return "本章撤回经历与回执不一致"
	if bool(flags.get("journey_complete", false)) != (reported == 1):
		return "本章结尾与复命回执不一致"
	if wins + losses > 0 and commissioned != 1:
		return "山道经过缺少护药委托"
	if commissioned == 1:
		var practices := 0
		for action_id: String in SWORD_ACTIONS:
			practices += int(counts.get(action_id, 0))
		if not bool(flags.get("mentor_lesson_heard", false)) or not bool(flags.get("mentor_practice_finished", false)) or practices < 1:
			return "本章委托缺少听教与练剑经历"
	if reported == 1:
		if wins + losses != 1 or not bool(flags.get("town_returned", false)):
			return "本章复命缺少山道与返山经历"
		var battle_sequence := 0
		var report_sequence := 0
		var returns: Array[int] = []
		for receipt: Dictionary in _dict_or_empty(candidate.get("receipts")).values():
			var action_id := str(receipt.get("action_id", ""))
			var sequence := int(receipt.get("sequence", 0))
			if action_id in SETTLEMENT_ACTIONS:
				battle_sequence = sequence
			elif action_id == "return_from_town":
				returns.append(sequence)
			elif action_id == REPORT_ACTION:
				report_sequence = sequence
		var returned_before_report := false
		for sequence: int in returns:
			if battle_sequence < sequence and sequence < report_sequence:
				returned_before_report = true
				break
		if not returned_before_report:
			return "本章复命顺序须为护药、返山、复命"
	return ""
