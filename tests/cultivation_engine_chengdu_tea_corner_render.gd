extends "res://tests/cultivation_engine_chengdu_scale_render.gd"
## Actual native clicks exercise the small focus and its existing host.
func _run() -> void:
 output_dir="res://.local/qa/chengdu-tea-corner/native"
 _parse_user_args()
 root.mode=Window.MODE_WINDOWED
 root.size=qa_size
 Engine.max_fps=60
 DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
 check(DisplayServer.get_name()!="headless","tea corner uses an actual native display")
 if DisplayServer.get_name()=="headless":
  _finish()
  return
 # Layout/obstacles are the compact version, with identical landmark positions.
 large_layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/chengdu-compact-street-layout.json")).scenes.chengdu_city
 test_store_dir="user://tea_corner_render_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 app=load("res://scenes/demos/cultivation_engine_chengdu_tea_corner.tscn").instantiate()
 app.set("save_base_dir",test_store_dir)
 root.add_child(app)
 await process_frame
 await process_frame
 _trace_start=Time.get_ticks_msec()
 check(_pack_id()=="shu_chengdu_tea_corner" and _state().scene=="chengdu_city" and _state().phase=="ready","independent slice starts immediately at the playable corner")
 initial_camera=_large_audit().get("camera_center",Vector2.ZERO)
 await _flow()
 _finish()

func _flow() -> bool:
 var initial:=_state()
 await _check_large_view()
 await _capture("00_corner_arrival.png","direct playable street arrival with clear route controls")
 var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/chengdu-tea-corner-layout.json"))
 for stop: Dictionary in config.stops:
  var started:=Time.get_ticks_usec()
  if not await _click("CornerStop_"+str(stop.id)) or not await _wait_walk(Vector2(stop.point[0],stop.point[1]),started):
   return false
  var state:=_state()
  check(state.scene==initial.scene and state.stats==initial.stats and state.slot==initial.slot and state.flags==initial.flags,"route buttons use actual free walking without changing action state")
  await _check_large_view()
  var finish: Dictionary=_large_audit().get("layered_street",{})
  var corner: Dictionary=finish.get("tea_corner",{})
  check(corner.get("focus_houses",[]).size()==4 and corner.get("weathered_aprons",0)==8,"four focus houses have eight weathered foundation edges")
  check(corner.get("extra_plant_cards",0)==8 and corner.get("landing_stones",0)==4,"authored plant groups and low landing stones are present")
  check(finish.get("solid_footprint_errors",["missing"]).is_empty(),"all solid planters remain inside existing blocked lots")
  await _capture("01_"+str(stop.id)+".png","actual route button walks to "+str(stop.id))
  if stop.id=="lane":
   await _corner_pixel_check()
 var saved:=_state()
 if not await _click("CityMenuButton") or not await _click("SaveButton") or not await _click("CityMenuCloseButton"):
  return false
 if not await _click("CornerStop_tea") or not await _wait_walk(Vector2(8060,7300),Time.get_ticks_usec()):
  return false
 if not await _click("CityMenuButton") or not await _click("LoadButton"):
  return false
 if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
  return false
 check(_state()==saved,"actual save and load restores every field and the chosen corner position")
 await _capture("02_corner_restored.png","full save restoration in the direct-start package")
 if not await _large_interact("gate_mountain_exit") or not await _close_event():
  return false
 check(_state().scene=="tingyu_corridor","original return action reaches the same mentor scene")
 if not await _click("ActionButton_talk_mentor"):
  return false
 for i in range(4):
  if not await _click("DialogContinueButton"):
   return false
 if not await _click("ChoiceButton_take_lesson") or not await _close_event():
  return false
 check(_state().stats.energy==92,"mentor choice retains the original actual cost")
 await _capture("03_retained_mentor.png","same-scene mentor remains on the original host")
 if not await _click("ActionButton_go_to_town") or not await _close_event():
  return false
 check(_state().scene=="chengdu_city" and _state().exploration.positions.chengdu_city==[7960,7395],"ordinary return to town uses the authored corner entry")
 if not await _click("CityMenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
  return false
 check(_state().scene=="chengdu_city" and _state().stats.energy==100 and _state().slot==0 and not _state().flags.mentor_lesson_accepted,"explicit reset starts a clean playable corner")
 await _capture("04_corner_reset.png","reset retains direct entry and clears played mentor progress")
 return true

func _corner_pixel_check() -> void:
 var stage: Node=(app.call("ui_control","TownWalker") as Control).get("_stage")
 var helper: Node=stage.get("_layered_street")
 paused=true
 await process_frame
 await RenderingServer.frame_post_draw
 var current: Image=stage.texture().get_image()
 current.save_png(_absolute_output_dir().path_join("corner-refined.png"))
 helper.set_corner_enabled(false)
 await process_frame
 await RenderingServer.frame_post_draw
 var previous: Image=stage.texture().get_image()
 previous.save_png(_absolute_output_dir().path_join("corner-previous.png"))
 current.convert(Image.FORMAT_RGBA8)
 previous.convert(Image.FORMAT_RGBA8)
 var a:=current.get_data()
 var b:=previous.get_data()
 var changed:=0
 for i: int in range(0,mini(a.size(),b.size()),4):
  if maxi(maxi(absi(a[i]-b[i]),absi(a[i+1]-b[i+1])),absi(a[i+2]-b[i+2]))>=8:
   changed+=1
 check(changed>300,"four-house refinement has visible same-state pixel contribution")
 var file:=FileAccess.open(_absolute_output_dir().path_join("corner-pixel-proof.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"changed_pixels":changed,"minimum_channel_change":8,"same_camera_and_state":true,"scope":"local refinement off returns baseline0.8.4 composition on the exact same geometry"},"  "))
 file.close()
 helper.set_corner_enabled(true)
 paused=false
