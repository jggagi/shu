extends SceneTree
const Loader=preload("res://addons/cultivation_mode/pack_loader.gd")
const Session=preload("res://addons/cultivation_mode/session.gd")
const Navigation=preload("res://addons/cultivation_mode/town_navigation.gd")
const Store=preload("res://addons/cultivation_mode/save_store.gd")
var checks:=0
var failures:=0
var nav: RefCounted
var host: RefCounted
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
func _walk(id: String) -> void:
	var state: Dictionary=host.snapshot()
	var at: Array=state.exploration.positions.dock_corner
	var item: Dictionary=host.pack.walks.scenes.dock_corner.interactions[id]
	var points: Array=nav.route(Vector2(at[0],at[1]),Vector2(item.position[0],item.position[1]),float(item.radius))
	check(not points.is_empty(),"interaction has a collision-safe approach: "+id)
	for point: Vector2 in points:
		state=host.snapshot()
		check(host.commit_walk_position("dock_corner",[roundi(point.x),roundi(point.y)],state.run_id,state.revision).ok,"host accepts each real approach segment")
func _enter(id: String,op: String) -> Dictionary:
	_walk(id)
	var s: Dictionary=host.snapshot()
	return host.execute_walk_interaction(id,op,s.run_id,s.revision)
func _close() -> void:
	for i: int in range(8):
		var s: Dictionary=host.snapshot()
		if s.phase=="ready":return
		if s.phase=="result":check(host.acknowledge_result().ok,"result acknowledged")
		else:check(host.continue_event().ok,"dialogue node advances")
	check(false,"dialogue closes")
func _run() -> void:
	var loaded: Dictionary=Loader.new().load_pack("res://games/shu_dock_corner/game.json")
	check(loaded.ok,"interactive dock validates: "+str(loaded.get("errors",[])))
	if not loaded.ok:quit(1);return
	var pack: Dictionary=loaded.pack
	host=Session.new()
	check(host.configure(pack).ok,"same Session configures new interactive content")
	nav=Navigation.new();nav.configure(pack.walks.scenes.dock_corner)
	var before: Dictionary=host.snapshot()
	for id: String in ["dock_keeper","dock_steps","dock_willow"]:
		check(not host.execute_walk_interaction(id,"far-"+id,before.run_id,before.revision).ok,"cannot interact from spawn: "+id)
		check(host.snapshot()==before,"distant attempt changes no state")
	for id: String in ["talk_dock_keeper","toss_dock_pebble","rest_at_dock"]:
		check(not host.select_action(id,"forged-"+id).ok,"menu cannot bypass contextual entry")
		check(host.snapshot()==before,"forged direct selection changes no state")
	check(_enter("dock_keeper","keeper-first").ok,"walking near keeper opens conversation")
	check(host.snapshot().phase=="event" and not host.can_save(),"active conversation owns focus and cannot checkpoint mid-choice")
	check(host.choose("ask_boat","boat-question").ok,"keeper answers actual choice")
	_close()
	check(host.snapshot().flags.dock_keeper_met and host.snapshot().slot==0 and host.snapshot().stats.energy==100,"conversation remembers visit with no hidden cost")
	check(_enter("dock_keeper","keeper-again").ok and host.snapshot().event.id=="dock_keeper_revisit","keeper has a real revisit response")
	check(host.choose("leave_keeper","leave-keeper").ok,"revisit can end without other activity")
	_close()
	check(_enter("dock_steps","water-look").ok,"step context opens")
	check(host.choose("leave_water","look-only").ok,"looking at water is a real free alternative")
	_close()
	check(not host.snapshot().flags.dock_water_disturbed and int(host.snapshot().counts.get("toss_dock_pebble",0))==0,"declining does not fake a throw")
	check(_enter("dock_steps","water-throw").ok,"step context can reopen")
	check(host.choose("toss_pebble","throw-once").ok,"throw choice settles")
	var thrown: Dictionary=host.snapshot()
	check(thrown.flags.dock_water_disturbed and thrown.counts.toss_dock_pebble==1 and thrown.slot==0,"throw records exactly one free environmental action")
	check(host.choose("toss_pebble","throw-once").ok and host.snapshot()==thrown,"retried throw operation cannot settle twice")
	_close()
	check(_enter("dock_willow","willow-look").ok,"willow context opens")
	check(host.choose("leave_willow","willow-no-rest").ok,"rest can be declined")
	_close()
	check(host.snapshot().slot==0,"declining rest advances no time")
	# Use an isolated valid pack fixture to expose the existing energy cap clearly.
	var fixture: Dictionary=pack.duplicate(true)
	for stat: Dictionary in fixture.rules.stats:
		if stat.id=="energy":stat.initial=50
	fixture.id="dock_rest_cost_fixture"
	fixture._fingerprint="dock-rest-cost-fixture".sha256_text()
	var actual_host: RefCounted=host
	host=Session.new();check(host.configure(fixture).ok,"low energy fixture configures without changing production rules")
	check(_enter("dock_willow","rest-start").ok,"low energy character approaches willow")
	check(host.choose("rest_dock","rest-once").ok,"rest option uses original host settlement")
	var rested: Dictionary=host.snapshot()
	check(rested.stats.energy==84 and rested.slot==1 and rested.last_result.delta.stats.energy==34,"one rest restores 34 and advances one slot")
	check(host.choose("rest_dock","rest-once").ok and host.snapshot()==rested,"retried rest choice charges once")
	_close()
	host=actual_host
	var store:=Store.new();store.base_dir="user://dock_interaction_host_%d"%OS.get_process_id()
	check(store.save_session(host).ok,"safe interaction memories save")
	var saved: Dictionary=host.snapshot()
	check(_enter("dock_steps","throw-again-entry").ok and host.choose("toss_pebble","throw-again").ok,"next deliberate throw is a distinct operation")
	_close()
	check(host.snapshot().counts.toss_dock_pebble==2,"explicit second throw increments once")
	check(store.load_session(host).ok and host.snapshot()==saved,"load exactly restores visit, water flag, count, position and clock")
	var fresh:=Session.new();check(fresh.configure(pack).ok,"new run configures")
	check(not fresh.snapshot().flags.dock_keeper_met and not fresh.snapshot().flags.dock_water_disturbed and fresh.snapshot().counts.is_empty(),"reset clears interaction memories and counters")
	print("DOCK_INTERACTION_HOST: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)
