extends SceneTree
## Real Session movement and saves for the direct-start art slice.
const Loader=preload("res://addons/cultivation_mode/pack_loader.gd")
const Session=preload("res://addons/cultivation_mode/session.gd")
const Store=preload("res://addons/cultivation_mode/save_store.gd")
const Navigation=preload("res://addons/cultivation_mode/chengdu_scale_navigation.gd")
var checks:=0
var failures:=0
var navigation: RefCounted
func _initialize() -> void:
 call_deferred("_run")
func check(value: bool,label: String) -> void:
 checks+=1
 if not value:
  failures+=1
  push_error(label)
func _walk(session: RefCounted,target: Vector2,radius: float=0) -> bool:
 var before: Dictionary=session.snapshot()
 var raw: Array=before.exploration.positions.chengdu_city
 var path: Array=navigation.route(Vector2(raw[0],raw[1]),target,radius)
 check(not path.is_empty(),"real route reaches "+str(target))
 for point: Vector2 in path:
  var state: Dictionary=session.snapshot()
  var result: Dictionary=session.commit_walk_position("chengdu_city",[roundi(point.x),roundi(point.y)],state.run_id,state.revision)
  check(result.ok,"original Session accepts this collision-checked segment")
  if not result.ok:return false
 var after: Dictionary=session.snapshot()
 for field: String in ["scene","phase","day","slot","stats","flags","counts","receipts","journal"]:
  check(after[field]==before[field],"free corner walking preserves "+field)
 return not path.is_empty()
func _run() -> void:
 var loaded: Dictionary=Loader.new().load_pack("res://games/shu_chengdu_tea_corner/game.json")
 check(loaded.ok,"new corner content pack loads")
 if not loaded.ok:
  quit(1)
  return
 var pack: Dictionary=loaded.pack
 var session:=Session.new()
 check(session.configure(pack).ok,"existing Session hosts corner slice")
 var first: Dictionary=session.snapshot()
 check(pack.id=="shu_chengdu_tea_corner" and first.scene=="chengdu_city" and first.phase=="ready","independent slice starts directly on playable street")
 check(first.exploration.positions.chengdu_city==[7960,7395] and first.slot==0 and first.stats.energy==100,"direct entry does not silently run a paid travel action")
 navigation=Navigation.new()
 navigation.configure(pack.walks.scenes.chengdu_city)
 var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu_compact/walks.json"))
 check(pack.walks.scenes.chengdu_city.obstacles==original.scenes.chengdu_city.obstacles,"all622 original collision rectangles stay exact")
 var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/chengdu-tea-corner-layout.json"))
 for stop: Dictionary in config.stops:
  var p:=Vector2(stop.point[0],stop.point[1])
  check(not navigation.blocked(p),"each authored stop fits the full actor radius")
  if not _walk(session,p):break
 var save_dir: String="user://test_runs/tea-corner-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var store:=Store.new()
 store.base_dir=save_dir
 check(store.save_session(session).ok,"safe corner progress saves")
 var saved: Dictionary=session.snapshot()
 _walk(session,Vector2(8340,7280))
 check(store.load_session(session).ok and session.snapshot()==saved,"read-back restores every field and actual street coordinates")
 var old: Dictionary=Loader.new().load_pack("res://games/shu_chengdu_compact/game.json").pack
 var old_session:=Session.new()
 check(old_session.configure(old).ok,"old city package remains valid")
 var old_before: Dictionary=old_session.snapshot()
 check(not store.load_session(old_session).ok and old_session.snapshot()==old_before,"corner save cannot overwrite old city identity")
 var gate: Dictionary=pack.walks.scenes.chengdu_city.interactions.gate_mountain_exit
 _walk(session,Vector2(gate.position[0],gate.position[1]),float(gate.radius))
 var at: Dictionary=session.snapshot()
 check(session.execute_walk_interaction("gate_mountain_exit","corner-return",at.run_id,at.revision).ok,"original return action runs through interaction authority")
 check(session.acknowledge_result().ok and session.snapshot().scene=="tingyu_corridor","action result returns to the original mentor scene")
 check(session.select_action("talk_mentor","corner-mentor").ok,"same-scene mentor remains available")
 for i in range(8):
  if session.event_view().get("type","")=="choice":break
  check(session.continue_event().ok,"original mentor lines advance")
 check(session.choose("take_lesson","corner-choice").ok,"mentor choice settles through original rules")
 check(session.snapshot().stats.energy==92,"mentor retains the actual energy cost")
 var fresh:=Session.new()
 check(fresh.configure(pack).ok and fresh.snapshot().exploration.positions.chengdu_city==[7960,7395] and fresh.snapshot().stats.energy==100,"new run returns to the clean street entry")
 print("TEA_CORNER_HOST: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
