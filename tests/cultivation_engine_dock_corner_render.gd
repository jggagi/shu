extends "res://tests/cultivation_engine_mentor_loop_render.gd"
const DockScene = preload("res://scenes/demos/cultivation_engine_dock_corner.tscn")
var input_trace: Array = []

func _run() -> void:
	output_dir = "res://.local/qa/dock-corner/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "actual native rendering")
	test_store_dir = "user://dock_render_%d" % Time.get_ticks_usec()
	app = DockScene.instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	for i: int in range(15):
		await process_frame
	check(_pack_id() == "shu_dock_corner" and _state().scene == "dock_corner", "standalone dock opens directly, without city travel")
	check(_walker()!=null,"dock presentation actually initializes")
	if _walker()==null:
		_finish()
		return
	await _life_flow()
	await _cast_flow()
	await _time_light_flow()
	await _lamp_flow()
	await _shadow_flow()
	await _flow()
	if failures==0:
		await _interaction_flow()
	_finish()

func _walker() -> Control:
	return app.call("ui_control", "TownWalker") as Control

func _life_flow() -> void:
	var life: RefCounted = app.get("_dock_life")
	var before := _state()
	check(life.people.size()==2 and _walker().get("_stage").actors.size()==4,"two ambient residents coexist with player and keeper")
	var fixture: RefCounted = load("res://addons/cultivation_mode/dock_corner_life.gd").new()
	var duplicate: RefCounted = load("res://addons/cultivation_mode/dock_corner_life.gd").new()
	var paths_clear := true
	for actor: Dictionary in fixture.people.values():
		var curve: Curve2D = actor.curve
		for i: int in range(101):
			paths_clear = paths_clear and not _walker().navigation.blocked(curve.sample_baked(curve.get_baked_length()*i/100.0))
	var cat_curve: Curve2D = fixture.cat.curve
	for i: int in range(101):
		paths_clear = paths_clear and not _walker().navigation.blocked(cat_curve.sample_baked(cat_curve.get_baked_length()*i/100.0))
	check(paths_clear,"authored people and cat routes remain on navigable dry shore")
	var cat_walked := false
	var returned := false
	for i: int in range(1800):
		fixture.advance(0.05,true,false,Vector2(100,600),"afternoon")
		duplicate.advance(0.05,true,false,Vector2(100,600),"afternoon")
		cat_walked = cat_walked or int(fixture.cat.pose) in [8,9,10,11]
		returned = returned or (i>200 and fixture.cat.phase=="return")
	check(fixture.audit()==duplicate.audit(),"seeded routes, pauses and cat opportunities reproduce at elapsed boundaries")
	check(cat_walked and returned,"resident cat has articulated outward and return travel")
	var frozen: Dictionary = fixture.audit()
	fixture.advance(0.05,false,false,Vector2(100,600),"afternoon")
	check(fixture.cat.pose==12 and fixture.cat.point==frozen.cat.point and fixture.elapsed==frozen.elapsed,"Static settles the cat at the same foot point without advancing its clock")
	frozen = fixture.audit()
	for i: int in range(30):
		fixture.advance(0.05,true,true,Vector2(100,600),"afternoon")
	check(fixture.elapsed==frozen.elapsed and fixture.cat.point==frozen.cat.point,"foreground attention pauses resident and opportunity clocks")
	var resident: Dictionary = fixture.people.quay_worker
	var held: Vector2 = resident.point
	for i: int in range(20):
		fixture.advance(0.05,true,false,held,"afternoon")
	check(resident.point==held and not resident.walking,"nearby walker yields to player instead of crossing the player")
	var initial: Dictionary = life.audit()
	for i: int in range(420):
		await process_frame
		if float(life.elapsed)-float(initial.elapsed)>6.0:
			break
	check(life.people.quay_worker.point!=initial.people.quay_worker.point,"actual frame loop advances quay resident position")
	check(life.people.tea_walker.point!=initial.people.tea_walker.point,"second walker also moves without yielding permanently at the player spawn")
	await _capture("life-moving.png","two small quay walkers and resident cat under original afternoon light")
	var actors: Dictionary = _walker().get("_stage").actors
	check(actors.quay_worker.animator.has_animation("resident/Walk") and actors.tea_walker.available,"both independent workers load compatible full-rig daily clips")
	if not await _click("DockMotionButton"):
		return
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	var map := _map_pixels()
	for i: int in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
		check(_map_pixels()==map,"populated Static view is pixel identical frame "+str(i))
	check(_walker().get("life")==life and not life.people.quay_worker.walking and life.cat.pose==12,"view reconstruction preserves resident positions and uses standing/sitting poses")
	await _capture("life-static.png","residents settle at their current ground points in Static")
	if not await _click("DockMotionButton"):
		return
	check(_state()==before,"ambient people, cat and controls never change host time, energy, revision or position")

func _cast_flow() -> void:
	var walker := _walker()
	var stage: Node = walker.get("_stage")
	var life: RefCounted = app.get("_dock_life")
	var fixture: RefCounted = load("res://addons/cultivation_mode/dock_corner_life.gd").new()
	var state := _state()
	app.set_process(false)
	walker.set_process(false)
	walker.set("life",fixture)
	var error := 0.0
	var foot_drift := 0.0
	for id: String in fixture.people:
		var actor: Node3D = stage.get("actors")[id]
		var resident: Dictionary = fixture.people[id]
		check(str(actor.get("archetype"))==str(resident.profile.archetype),"resident keeps its distinct authored archetype: "+id)
		check(actor.find_children("*","MeshInstance3D",true,false).size()<30,"costume bamboo strips are batched into bounded runtime meshes: "+id)
		for i: int in range(64):
			var phase := float(i)/64.0
			resident.walking = true
			resident.quiet = false
			resident.stride = phase*float(actor.get("cycle_distance"))
			var animator := actor.get("animator") as AnimationPlayer
			actor.call("_sample",actor.get("walk_clip"),phase*animator.get_animation(actor.get("walk_clip")).length)
			var skeleton := actor.get("skeleton") as Skeleton3D
			var foot := skeleton.find_bone("foot.L")
			var original: Vector3 = actor.call("_bone_position",foot)
			actor.call("present",resident)
			foot_drift = maxf(foot_drift,original.distance_to(actor.call("_bone_position",foot)))
			error = maxf(error,float(actor.get("arm_residual")))
	check(error<0.005,"both upper-body walk poses reach authored hand targets through the full gait")
	check(foot_drift<0.000001,"new upper-body poses retain actual sampled gait foot contacts")
	var first := PackedByteArray()
	for label: String in ["read-adjust","look-wipe","side","quiet"]:
		for id: String in fixture.people:
			var resident: Dictionary = fixture.people[id]
			resident.walking = false
			resident.quiet = label=="quiet"
			resident.rest_age = 2.0
			resident.wait = 6.0
			resident.yaw = 1.6 if label=="side" else 0.5
			resident.idle_action = ("read" if label=="read-adjust" else "look") if id=="quay_worker" else ("adjust" if label=="read-adjust" else "wipe")
		walker.call("present",2.0)
		for i: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var pixels := _map_pixels()
		if label=="read-adjust":
			first = pixels
		else:
			check(pixels!=first,"distinct small-window posture makes a visible map-region contribution: "+label)
		for id: String in fixture.people:
			check(float(stage.get("actors")[id].get("arm_residual"))<0.005,"idle hand targets remain reachable: "+label+" "+id)
		await _capture("cast-"+label+".png","distinct silhouettes, hand poses and belongings: "+label)
	walker.set("life",life)
	walker.call("present",float(app.get("_dock_elapsed")))
	walker.set_process(true)
	app.set_process(true)
	check(_state()==state,"costume and pose review never mutates the exact host state")

func _time_light_flow() -> void:
	await _check_layout("time light controls",["DockTime_morning","DockTime_afternoon","DockTime_dusk","DockTime_moonlight","DockLightButton"])
	check(str(_walker().get("time_light_id"))=="afternoon","liked afternoon remains the opening light")
	if not await _click("DockMotionButton"):
		return
	app.set("_dock_elapsed",2.0)
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	var state := _state()
	var afternoon := root.get_texture().get_image().get_data()
	for id: String in ["morning","dusk","moonlight","afternoon"]:
		if not await _click("DockTime_"+id):
			return
		await _neutral_pointer()
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image().get_data()
		check(_state()==state,"light preview preserves exact host clock, position, energy and revision: "+id)
		check(pixels!=afternoon if id!="afternoon" else pixels==afternoon,"distinct light or exact afternoon roundtrip: "+id)
		var stable := true
		for i: int in range(6):
			await process_frame
			await RenderingServer.frame_post_draw
			stable = stable and root.get_texture().get_image().get_data()==pixels
		check(stable,"static preset stays pixel identical: "+id)
		await _capture("time-"+id+".png","same frozen painting, actors and host under "+id)
		if not await _click("DockLightButton") or not await _click("DockLightButton"):
			return
		await _neutral_pointer()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_data()==pixels,"original light comparison restores selected preset: "+id)
	# Rebuilding the view for motion/menu/dialogue must retain the light selection.
	if not await _click("DockTime_moonlight") or not await _click("DockMotionButton"):
		return
	check(str(_walker().get("time_light_id"))=="moonlight","view rebuild retains selected moonlight")
	if not await _click("CityMenuButton") or not await _click("CityMenuCloseButton"):
		return
	check(str(_walker().get("time_light_id"))=="moonlight" and _state()==state,"menu rebuild retains preview without mutating host")
	if not await _click("DockTime_afternoon"):
		return

func _lamp_flow() -> void:
	if not await _click("DockMotionButton") or not await _click("DockTime_moonlight"):
		return
	app.set("_dock_elapsed",2.0)
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	var state := _state()
	var pixels := root.get_texture().get_image().get_data()
	await _capture("lamps-on.png","same frozen moonlight with eave and boat lanterns, bounce and water reflection")
	_walker().call("set_lamp_effects",false)
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data()!=pixels,"local lamplight makes a visible GPU contribution")
	check(_state()==state,"lamp comparison does not mutate host state")
	await _capture("lamps-off.png","same moonlight and pose with lanterns and their illumination hidden")
	_walker().call("set_lamp_effects",true)
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data()==pixels,"lamp roundtrip restores identical static GPU pixels")
	# Inspect illumination on actual loaded 3D characters, not just a painted halo.
	var stage: Node = _walker().get("_stage")
	var lamps: Array = stage.get("lamps")
	check(lamps.size()==2 and lamps[0].light_energy>0.0 and lamps[1].light_energy>0.0,"two warm actor lights are active at night")
	for lamp: OmniLight3D in lamps:
		var target := Vector2(391,169) if lamp.name=="DockLamp_tea" else Vector2(794,514)
		check((stage.get("camera") as Camera3D).unproject_position(lamp.position).distance_to(target)<0.02,"actor light projects to its visible lantern: "+str(lamp.name))
	if not await _click("CityMenuButton"):
		return
	var phase := float(app.get("_dock_elapsed"))
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	var menu_pixels := root.get_texture().get_image().get_data()
	for i: int in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_data()==menu_pixels,"night menu freezes flame and reflection frame "+str(i))
	check(float(app.get("_dock_elapsed"))==phase,"night menu preserves controlled flame phase")
	if not await _click("CityMenuCloseButton") or not await _click("DockTime_afternoon"):
		return
	check(not bool(_walker().get("_lamps").visible),"daytime has no added lantern overlay")
	if not await _click("DockMotionButton"):
		return

func _map_pixels() -> PackedByteArray:
	var walker := _walker()
	var transform := root.get_final_transform()*walker.get_global_transform_with_canvas()
	var start: Vector2 = transform*walker.call("logical_to_local",Vector2.ZERO)
	var end: Vector2 = transform*walker.call("logical_to_local",Vector2(1280,720))
	return root.get_texture().get_image().get_region(Rect2i(Rect2(start,end-start))).get_data()

func _shadow_flow() -> void:
	await _check_layout("cast shadow control",["DockShadowButton"])
	if not await _click("DockMotionButton"):
		return
	app.set("_dock_elapsed",2.0)
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	var state := _state()
	var pixels := _map_pixels()
	await _capture("shadow-afternoon-on.png","soft posture-based character cast shadows on stone")
	var records: Dictionary = _walker().get("_shadows").get("records")
	check(int(records.player.segments)>=12 and int(records.keeper.segments)>=10,"both actual rigs provide full body shadow segments")
	if not await _click("DockShadowButton"):
		return
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	check(_map_pixels()!=pixels,"cast shadows change painting-region pixels beyond control labels")
	await _capture("shadow-afternoon-off.png","same pose and light with only pre-existing foot contacts")
	if not await _click("DockShadowButton"):
		return
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	check(_map_pixels()==pixels and _state()==state,"cast shadow roundtrip restores identical pixels without host mutation")
	if not await _click("DockTime_moonlight"):
		return
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	records = _walker().get("_shadows").get("records")
	check(str(records.keeper.source)=="DockLamp_tea","nearby night keeper shadow responds to real tea lamp location")
	await _capture("shadow-night-on.png","moonlight and nearby tea lamp produce local character shadows")
	if not await _click("DockShadowButton"):
		return
	await _neutral_pointer()
	await _capture("shadow-night-off.png","same moonlight and lamp pool without added cast silhouettes")
	if not await _click("DockShadowButton") or not await _click("DockTime_afternoon") or not await _click("DockMotionButton"):
		return
	check(_state()==state,"lighting, shadow and static previews preserve deep host state")

func _flow() -> void:
	await _capture("00_dock.png", "independent painted dock with live original characters")
	await _check_layout("dock", ["HeaderPanel","ScenePanel","DockStop_tea","DockMotionButton"])
	if not await _click("DockMotionButton"):
		return
	app.set("_dock_elapsed",2.0)
	await process_frame
	await _neutral_pointer()
	var environment_state := _state()
	await _capture("00c_environment_on.png","same phase with willow, cloth and boat ripple effects")
	_walker().call("set_environment_effects",false)
	await _capture("00d_environment_off.png","same phase with new ambient effects hidden")
	check(_state()==environment_state,"ambient effect comparison changes no host state")
	_walker().call("set_environment_effects",true)
	var light_state := _state()
	await _neutral_pointer()
	await _capture("00a_light_on.png", "frozen afternoon light comparison")
	await RenderingServer.frame_post_draw
	var lit_pixels := root.get_texture().get_image().get_data()
	if not await _click("DockLightButton"):
		return
	check(_state()==light_state and not bool(_walker().get("_stage").get("lighting_enabled")), "lighting comparison changes no host state and restores original actor light")
	await _neutral_pointer()
	await _capture("00b_light_off.png", "same painting and actor pose with original lighting")
	if not await _click("DockLightButton"):
		return
	await RenderingServer.frame_post_draw
	await _neutral_pointer()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data()==lit_pixels, "lighting toggle returns to identical frozen GPU pixels")
	if not await _click("DockMotionButton"):
		return
	if not await _click("CityMenuButton"):
		return
	var menu_phase := float(app.get("_dock_elapsed"))
	for i: int in range(12):
		await process_frame
	check(float(app.get("_dock_elapsed"))==menu_phase,"open menu freezes water, leaves, cloth and lighting phase")
	if not await _click("CityMenuCloseButton"):
		return
	var walker := _walker()
	var navigation: RefCounted = walker.get("navigation")
	var stage: Node = walker.get("_stage")
	var actor_audit: Dictionary = stage.call("audit")
	check(bool(actor_audit.actors.player.available) and bool(actor_audit.actors.keeper.available), "original skinned player and keeper actually load")
	var camera: Camera3D = stage.get("camera")
	for point: Vector2 in [Vector2(420,420),Vector2(440,270),Vector2(555,350),Vector2(778,373),Vector2(145,565)]:
		var world: Vector3 = stage.call("logical_to_world", point)
		check(camera.unproject_position(world).distance_to(point)<0.02, "3D ground projects onto authored image point " + str(point))
		check(not bool(navigation.call("blocked", point)), "authored stop is on safe ground " + str(point))
		var path: Array = navigation.call("route", Vector2(420,420), point, 0.0)
		check(not path.is_empty(), "authored stop is reachable " + str(point))
	var session: RefCounted = app.get("_session")
	for point: Array in [[1100,560],[900,600],[600,550],[100,100],[350,310]]:
		var state := _state()
		check(not bool(session.call("commit_walk_position","dock_corner",point,str(state.run_id),int(state.revision)).get("ok",true)), "water, house and keeper reject direct host movement " + str(point))
		check(_state()==state, "rejected movement leaves state unchanged")
	for id: String in ["tea","mooring","steps"]:
		if not await _click("DockStop_"+id):
			return
		await _wait_walk()
		await _capture("01_"+id+".png", "real route to " + id)
		var target: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dock-corner-layout.json")).waypoints[id]
		check((_walker().get("player_position") as Vector2).distance_to(Vector2(target[0],target[1])) < 1.0, "real position arrives at " + id)
	# Native pointer events into water must leave position unchanged.
	var before := _state()
	await _ground(Vector2(1100,600))
	for i: int in range(12):
		await process_frame
	check(_state()==before, "real click in water cannot move character")
	# Freeze all presentation and ensure actual GPU output stays identical.
	if not await _click("DockMotionButton"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image().get_data()
	var stable := true
	for i: int in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
		stable = stable and first == root.get_texture().get_image().get_data()
	check(stable, "static presentation is pixel-identical for 12 GPU frames")
	await _capture("02_static.png", "frozen dock presentation")
	# Separate light motion from actor animation for GPU phase diagnostics.
	_walker().get("_actors").visible = false
	app.set("_dock_elapsed",0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_absolute_output_dir().path_join("light-phase-0.png"))
	app.set("_dock_elapsed",2.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_absolute_output_dir().path_join("light-phase-2.png"))
	if not await _click("DockLightButton"):
		return
	_walker().call("set_environment_effects",false)
	var water_material: ShaderMaterial = _walker().get("_background").material
	_walker().get("_actors").visible = false
	app.set("_dock_elapsed",0.0)
	water_material.set_shader_parameter("elapsed", 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_absolute_output_dir().path_join("water-phase-0.png"))
	water_material.set_shader_parameter("elapsed", 2.0)
	# Use view-owned phase, so regular presentation cannot overwrite it.
	app.set("_dock_elapsed",2.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_absolute_output_dir().path_join("water-phase-2.png"))
	_walker().call("set_environment_effects",true)
	_walker().get("_actors").visible = true
	if not await _click("DockLightButton"):
		return
	if not await _click("CityMenuButton") or not await _click("SaveButton"):
		return
	var saved := _state()
	if not await _click("CityMenuCloseButton") or not await _click("DockStop_tea"):
		return
	await _wait_walk()
	check(_state()!=saved, "walking after save changes dock position")
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return
	check(_state()==saved, "load restores exact dock position, clock and run identity")
	if _has_control("CityMenuCloseButton") and not await _click("CityMenuCloseButton"):
		return
	await _ground(Vector2(145,565))
	for i: int in range(900):
		await process_frame
		if _state().scene != "dock_corner":
			break
	check(_state().scene == "tingyu_corridor" and _state().phase=="result", "walking to willow exit reaches original mentor corridor")
	if not await _click("ResultContinueButton") or not await _click("ActionButton_talk_mentor"):
		return
	await _check_dialogue("player_yanqiu")
	await _capture("dialogue-mentor-player.png","bottom speaker avatar and exact player line in mentor conversation")
	for i: int in range(4):
		if not await _click("DialogContinueButton"):
			return
		await _check_dialogue(["mentor_zhixian","player_yanqiu","mentor_zhixian","mentor_zhixian"][i])
		if i==0:
			await _capture("dialogue-mentor.png","portrait and name switch to the mentor on his own line")
	if not await _click("ChoiceButton_take_lesson"):
		return
	check(int(_state().stats.energy)==92 and int(_state().slot)==2, "same-scene mentor choice preserves original eight energy and one slot cost")
	await _capture("03_mentor.png", "original mentor interaction retained")
	for i: int in range(4):
		if _state().phase=="ready":
			break
		if not await _click("ResultContinueButton" if _state().phase=="result" else "DialogContinueButton"):
			return
	if not await _click("ActionButton_go_to_dock") or not await _click("ResultContinueButton"):
		return
	check(_state().scene=="dock_corner", "ordinary host travel returns to standalone dock")
	if not await _click("CityMenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return
	check(_state().scene=="dock_corner" and _state().exploration.positions.dock_corner==[420,420] and int(_state().slot)==0, "confirmed restart resets directly to dock spawn")
	await _capture("04_restart.png", "fresh independent dock sample")
	var trace := FileAccess.open(_absolute_output_dir().path_join("dock-input-trace.json"),FileAccess.WRITE)
	trace.store_string(JSON.stringify(input_trace,"\t"))

func _wait_walk() -> void:
	for i: int in range(900):
		await process_frame
		var walker := _walker()
		if walker==null or (walker.get("route") as Array).is_empty():
			return
	check(false,"route completes within real-time bound")

func _ground(point: Vector2) -> void:
	var walker := _walker()
	var local: Vector2 = walker.call("logical_to_local",point)
	var actual := root.get_final_transform() * (walker.get_global_transform_with_canvas()*local)
	input_trace.append({"logical":[point.x,point.y],"actual":[actual.x,actual.y]})
	var motion := InputEventMouseMotion.new()
	motion.position = actual
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = actual
		event.global_position = actual
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func _neutral_pointer() -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(8,8)
	root.push_input(event)
	await process_frame
	await process_frame

func _open_dock_object(id: String) -> bool:
	if not await _click("DockObject_"+id):
		return false
	for i: int in range(900):
		await process_frame
		if _state().phase!="ready":
			await process_frame
			await process_frame
			return true
	check(false,"walking to object opens its actual context: "+id)
	return false

func _read_dock_event() -> bool:
	for frame: int in range(240):
		if not bool(app.call("_throw_busy")):
			break
		await process_frame
	for i: int in range(8):
		if _state().phase=="ready":return true
		if not await _click("ResultContinueButton" if _state().phase=="result" else "DialogContinueButton"):
			return false
	return false

func _wait_throw(age: float) -> void:
	for frame: int in range(300):
		if float(app.get("_dock_throw_age"))>=age:
			return
		await process_frame
	check(false,"throw reaches authored phase "+str(age))

func _check_dialogue(speaker_id: String) -> void:
	var event: Dictionary = app.get("_session").call("event_view")
	var state := _state()
	await _check_layout("bottom dialogue",["DockDialoguePanel","DockDialogueSpeaker","DockDialogueText"])
	var panel := app.call("ui_control","DockDialoguePanel") as Control
	var name := app.call("ui_control","DockDialogueSpeaker") as Label
	var line := app.call("ui_control","DockDialogueText") as Label
	check(name!=null and name.text==(str(event.speaker_name) if not speaker_id.is_empty() else "旁白"),"bottom dialogue names the actual current speaker")
	check(line!=null and line.text==str(event.text),"bottom dialogue shows the exact current host line")
	check(panel!=null and panel.get_global_rect().position.y>root.get_visible_rect().size.y*0.5,"conversation stays in the lower screen bar")
	var avatar := app.call("ui_control","DockDialoguePortrait") as TextureRect
	if speaker_id.is_empty():
		check(avatar==null and _has_control("DockDialogueNarration"),"narration clears the previous person's portrait")
	else:
		check(avatar!=null and avatar.texture!=null and str(avatar.get_meta("speaker",""))==speaker_id,"avatar follows the stable speaker ID: "+speaker_id)
		if speaker_id=="dock_tea_keeper":
			check((avatar.texture as AtlasTexture).region.end.y<=820,"keeper avatar excludes the generated bottom caption")
	check(_state()==state,"dialogue presentation inspection does not mutate host state")

func _interaction_flow() -> void:
	if not bool(app.get("_dock_dynamic")) and not await _click("DockMotionButton"):
		return
	await _check_layout("object markers",["DockObject_dock_keeper","DockObject_dock_steps","DockObject_dock_willow"])
	if not await _open_dock_object("dock_keeper"):
		return
	check(_state().phase=="event","approaching keeper opens real dialogue choices")
	await _check_dialogue("dock_tea_keeper")
	var dialogue_state := _state()
	if not await _click("CityMenuButton"):
		return
	check((app.call("ui_control","CityMenuCover") as Control).get_index()>(app.call("ui_control","DockDialoguePanel") as Control).get_index(),"menu modal remains above the dialogue bar")
	if not await _click("CityMenuCloseButton"):
		return
	check(_state()==dialogue_state,"opening and closing menu preserves the current speaker and node")
	await _check_dialogue("dock_tea_keeper")
	var actors: Dictionary = _walker().get("_stage").get("actors")
	var player_actor: Node3D = actors.player
	var keeper_actor: Node3D = actors.keeper
	var toward_keeper := (keeper_actor.global_position-player_actor.global_position).normalized()
	check(player_actor.global_basis.z.dot(toward_keeper)>0.98 and keeper_actor.global_basis.z.dot(-toward_keeper)>0.98,"both visible actors actually face each other in conversation")
	await _capture("05_keeper_choice.png","same-scene keeper interaction")
	if not await _click("ChoiceButton_ask_boat"):
		return
	await _check_dialogue("dock_tea_keeper")
	await _capture("dialogue-keeper-line.png","painted current keeper portrait, name, line and continue button")
	if not await _click("DialogContinueButton"):
		return
	await _check_dialogue("")
	await _capture("dialogue-narration.png","narration is distinct from the previous character's speech")
	if not await _read_dock_event():
		return
	check(not _has_control("DockDialoguePanel"),"closing the conversation removes the bottom dialogue bar")
	check(bool(_state().flags.dock_keeper_met) and int(_state().slot)==0,"keeper visit is remembered without time charge")
	if not await _open_dock_object("dock_keeper"):
		return
	check(_state().event.id=="dock_keeper_revisit","keeper recognizes returning player")
	if not await _click("ChoiceButton_leave_keeper") or not await _read_dock_event():
		return
	if not await _open_dock_object("dock_steps"):
		return
	await _check_dialogue("player_yanqiu")
	await _capture("dialogue-player-choice.png","player avatar, inner observation and existing water choices")
	if not await _click("ChoiceButton_leave_water") or not await _read_dock_event():
		return
	check(not bool(_state().flags.dock_water_disturbed),"looking at water does not trigger throw")
	if not await _click("DockMotionButton"):
		return
	var environment_phase := float(app.get("_dock_elapsed"))
	var sound_count := int(app.get("_dock_sound_count"))
	if not await _open_dock_object("dock_steps") or not await _click("ChoiceButton_toss_pebble"):
		return
	check(int(_state().counts.toss_dock_pebble)==1 and bool(_state().flags.dock_water_disturbed),"throw settles once through real choice")
	check(bool(app.call("_throw_busy")) and (app.call("ui_control","DialogContinueButton") as Button).disabled,"settled throw owns presentation until neutral recovery")
	var throwing := _state()
	app.call("_continue_event")
	app.call("_cancel_event")
	check(_state()==throwing,"early continue and cancellation cannot cut off settled throw")
	await _wait_throw(0.52)
	await _capture("06a_throw_prepare.png","planted character turns to water and raises the throwing arm")
	check(str(_walker().get("_stage").get("actors").player.get("sampled_clip"))=="dock/Throw","real loaded rig samples authored throw clip")
	if not await _click("CityMenuButton"):
		return
	var paused_age := float(app.get("_dock_throw_age"))
	for frame: int in range(12):
		await process_frame
	check(float(app.get("_dock_throw_age"))==paused_age and int(app.get("_dock_sound_count"))==sound_count,"menu pauses throw before impact without a premature sound")
	if not await _click("CityMenuCloseButton"):
		return
	await _wait_throw(0.83)
	await _capture("06b_throw_release.png","pebble starts from projected real right hand")
	var throw_stage: Node = _walker().get("_stage")
	throw_stage.call("present_throw",0.82,Vector2(1040,480))
	var throw_actor: Node3D = throw_stage.get("actors").player
	var skeleton := throw_actor.get("skeleton") as Skeleton3D
	var hand: Vector3 = throw_actor.transform*throw_actor.call("_bone_position",skeleton.find_bone("hand.R"))
	check((throw_stage.get("camera") as Camera3D).unproject_position(hand).distance_to(throw_stage.get("release_point"))<0.02,"flight origin agrees with actual camera projection of release hand")
	await _wait_throw(1.53)
	await _capture("06_pebble_ripples.png","authored empty-water target receives player-caused ripple")
	check(int(app.get("_dock_sound_count"))==sound_count+1,"one impact sound plays at landing after release and flight")
	check(float(app.get("_dock_elapsed"))==environment_phase,"static environment stays frozen while chosen throw completes")
	if not await _read_dock_event():
		return
	check(not bool(app.call("_throw_busy")),"body recovers before dialogue can return")
	if not await _click("DockMotionButton") or not await _click("DockSoundButton"):
		return
	if not await _click("CityMenuButton") or not await _click("SaveButton"):
		return
	var saved := _state()
	if not await _click("CityMenuCloseButton") or not await _open_dock_object("dock_steps") or not await _click("ChoiceButton_toss_pebble") or not await _read_dock_event():
		return
	check(int(_state().counts.toss_dock_pebble)==2,"second deliberate throw gets its own receipt")
	check(int(app.get("_dock_sound_count"))==sound_count+1,"muted repeated throw consumes cue without playing it")
	if not await _click("CityMenuButton") or not await _click("LoadButton"):
		return
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return
	check(_state()==saved,"load restores exact interaction memories and counts")
	check(float(app.get("_dock_throw_age"))<0.0,"load restores game memory without replaying transient action")
	if _has_control("CityMenuCloseButton") and not await _click("CityMenuCloseButton"):
		return
	if not await _open_dock_object("dock_willow"):
		return
	if not await _click("ChoiceButton_leave_willow") or not await _read_dock_event():
		return
	check(int(_state().slot)==0,"declining willow rest is free")
	if not await _open_dock_object("dock_willow") or not await _click("ChoiceButton_rest_dock"):
		return
	check(int(_state().slot)==1 and int(_state().stats.energy)==100 and int(_state().last_result.delta.stats.energy)==0,"rest respects maximum energy and advances one slot")
	await _capture("07_willow_rest.png","visible priced rest choice and actual receipt")
	if not await _read_dock_event():
		return
	if not await _click("CityMenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return
	check(not bool(_state().flags.dock_keeper_met) and not bool(_state().flags.dock_water_disturbed) and _state().counts.is_empty(),"restart clears all new interaction progress")
	await _capture("08_interactions_reset.png","fresh dock with three discoverable interactions")
