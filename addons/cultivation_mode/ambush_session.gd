extends "res://addons/cultivation_mode/session.gd"
## Slice adapter: the existing Session remains the only persistent authority.
## The live encounter never enters a checkpoint. Only a verified terminal rule
## state can submit one normal registered action through the original ledger.

const AmbushRulesScript = preload("res://addons/cultivation_mode/ambush_rules.gd")
const AMBUSH_PHASE := "ambush"
const START_ACTION := "begin_ambush"
const SETTLEMENT_ACTIONS := ["ambush_win", "ambush_loss"]
var _encounter: Dictionary = {}
var _battle: RefCounted
var _ambush_context: Dictionary = {}


func configure(data: Dictionary) -> Dictionary:
	var actions := _dict_or_empty(data.get("actions"))
	for action_id: String in [START_ACTION, "ambush_win", "ambush_loss"]:
		var action := _dict_or_empty(actions.get(action_id))
		if action.is_empty() or action.get("menu", false) != true or not str(action.get("event", "")).is_empty() or not str(action.get("target_scene", "")).is_empty():
			return _failure("山道战斗缺少合法的宿主行动", "invalid_encounter")
	var config: Dictionary = _dict_or_empty(data.get("ambush"))
	var path := str(config.get("encounter_path", ""))
	if path != "res://games/shu_mountain_ambush/encounter.json":
		return _failure("山道战斗内容入口无效", "invalid_encounter")
	if not FileAccess.file_exists(path):
		return _failure("山道战斗内容缺失", "invalid_encounter")
	var raw := FileAccess.get_file_as_string(path)
	if raw.sha256_text() != str(config.get("encounter_sha256", "")):
		return _failure("山道战斗内容与版本校验不符", "invalid_encounter")
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _failure("山道战斗内容格式无效", "invalid_encounter")
	var candidate: RefCounted = AmbushRulesScript.new()
	var checked: Dictionary = candidate.call("configure", parsed)
	if not bool(checked.get("ok", false)):
		return _failure(str(checked.get("reason", "山道战斗规则无效")), "invalid_encounter")
	_encounter = parsed.duplicate(true)
	return super.configure(data)


func start_new() -> Dictionary:
	var result := super.start_new()
	if bool(result.get("ok", false)):
		_battle = null
		_ambush_context.clear()
	return result


func restore(candidate: Dictionary) -> Dictionary:
	if state.get("phase", "") == AMBUSH_PHASE:
		return _failure("请先完成战斗或撤离，再读取存档", "busy")
	var result := super.restore(candidate)
	if bool(result.get("ok", false)):
		_battle = null
		_ambush_context.clear()
	return result


func available_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in super.available_actions():
		if not SETTLEMENT_ACTIONS.has(str(action.get("id", ""))):
			result.append(action)
	return result


func select_action(action_id: String, operation_id: String = "") -> Dictionary:
	if SETTLEMENT_ACTIONS.has(action_id):
		return _failure("战斗结果只能由当前对局提交", "reserved_action")
	if action_id == START_ACTION:
		return begin_ambush(str(state.get("run_id", "")), operation_id, int(state.get("revision", 0)))
	return super.select_action(action_id, operation_id)


func begin_ambush(expected_run_id: String, operation_id: String = "", expected_revision: int = -1) -> Dictionary:
	if expected_run_id != str(state.get("run_id", "")):
		return _failure("这场山道请求已过期", "stale_run")
	if not _ambush_context.is_empty() and not bool(_ambush_context.get("settled", false)) and not operation_id.is_empty() and _ambush_context.get("operation_id", "") == operation_id:
		return {"ok": true, "duplicate": true, "context": ambush_context()}
	if state.get("phase", "") != PHASE_READY or not _ambush_context.is_empty():
		return _failure("请先收起当前结果再进入山道", "wrong_phase")
	if expected_revision >= 0 and expected_revision != int(state.get("revision", 0)):
		return _failure("山道请求已更新，请重新选择", "stale_revision")
	if not operation_id.is_empty() and _dict_or_empty(state.get("receipts")).has(operation_id):
		return _failure("这个操作已经完成，请重新进入山道", "operation_mismatch")
	var action: Dictionary = _dict_or_empty(_dict_or_empty(pack.get("actions")).get(START_ACTION))
	var available := _check_action(START_ACTION, action, true, PHASE_READY)
	if not bool(available.get("ok", false)):
		return _failure(str(available.get("reason", "暂时不能进入山道")), str(available.get("code", "not_available")))
	var candidate: RefCounted = AmbushRulesScript.new()
	var configured: Dictionary = candidate.call("configure", _encounter.duplicate(true))
	if not bool(configured.get("ok", false)):
		return _failure(str(configured.get("reason", "山道战斗未能准备")), "invalid_encounter")
	var op := operation_id
	if op.is_empty():
		op = "%s:ambush:%s" % [expected_run_id, _new_run_id()]
	_battle = candidate
	_ambush_context = {"run_id": expected_run_id, "operation_id": op, "return_scene": str(state.get("scene", "")), "settled": false, "outcome": "", "receipt": {}}
	state["phase"] = AMBUSH_PHASE
	state["revision"] = int(state.get("revision", 0)) + 1
	last_error = ""
	return {"ok": true, "context": ambush_context()}


func battle() -> RefCounted:
	return _battle


func ambush_context() -> Dictionary:
	return _ambush_context.duplicate(true)


func finish_ambush(expected_run_id: String, operation_id: String) -> Dictionary:
	if expected_run_id != str(state.get("run_id", "")):
		return _failure("这场战斗已经不属于当前开局", "stale_run")
	var receipts := _dict_or_empty(state.get("receipts"))
	if receipts.has(operation_id):
		var prior := _dict_or_empty(receipts[operation_id])
		if str(prior.get("kind", "")) == "action" and SETTLEMENT_ACTIONS.has(str(prior.get("action_id", ""))):
			return _duplicate_result(prior)
		return _failure("操作编号已用于其他行动", "operation_mismatch")
	if _battle == null or _ambush_context.is_empty() or operation_id != _ambush_context.get("operation_id", "") or expected_run_id != _ambush_context.get("run_id", ""):
		return _failure("战斗回报已过期", "stale_operation")
	if state.get("phase", "") != AMBUSH_PHASE:
		return _failure("当前没有等待结算的战斗", "wrong_phase")
	var combat: Dictionary = _battle.call("snapshot")
	var phase := str(combat.get("phase", ""))
	var outcome := str(combat.get("outcome", ""))
	if not ((phase == "won" and outcome == "victory") or (phase == "lost" and outcome in ["defeat", "abandoned"])):
		return _failure("战斗尚未结束", "not_terminal")
	var action_id := "ambush_win" if outcome == "victory" else "ambush_loss"
	# _prepare_action reads the host state but stages all changes. Restore the
	# busy phase on a rejection, so a failed settlement never releases the match.
	state["phase"] = PHASE_READY
	var prepared := _prepare_action(action_id, pack.actions[action_id], operation_id, "action", {})
	state["phase"] = AMBUSH_PHASE
	if not bool(prepared.get("ok", false)):
		return _failure(str(prepared.get("reason", "战斗结果未能保存")), str(prepared.get("code", "settlement_failed")))
	state = _dict_or_empty(prepared.get("state")).duplicate(true)
	_ambush_context["settled"] = true
	_ambush_context["outcome"] = outcome
	_ambush_context["receipt"] = _dict_or_empty(prepared.get("result")).duplicate(true)
	last_error = ""
	return _dict_or_empty(prepared.get("result")).duplicate(true)


func abandon_ambush(expected_run_id: String, operation_id: String) -> Dictionary:
	if expected_run_id != str(state.get("run_id", "")) or _ambush_context.get("operation_id", "") != operation_id or _battle == null:
		return _failure("撤离请求已过期", "stale_operation")
	if not bool(_ambush_context.get("settled", false)):
		var combat: Dictionary = _battle.call("snapshot")
		if str(combat.get("phase", "")) not in ["won", "lost"]:
			var abandoned: Dictionary = _battle.call("abandon")
			if not bool(abandoned.get("ok", false)):
				return abandoned
	return finish_ambush(expected_run_id, operation_id)


func close_ambush(expected_run_id: String, operation_id: String) -> Dictionary:
	if expected_run_id != str(state.get("run_id", "")) or _ambush_context.get("operation_id", "") != operation_id:
		return _failure("战斗页面已过期", "stale_operation")
	if not bool(_ambush_context.get("settled", false)):
		return _failure("请先结束战斗或撤离", "busy")
	_battle = null
	_ambush_context.clear()
	return {"ok": true}
