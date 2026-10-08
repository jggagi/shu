extends SceneTree
var checks := 0
var failures: Array[String] = []
func verify(value: bool, detail: String) -> void:
 checks += 1
 if not value:failures.append(detail);push_error(detail)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var lab = load("res://scenes/demos/animation_lab.tscn").instantiate()
 root.add_child(lab)
 lab.playing = false
 var data: Dictionary = lab.data
 for polygon in lab.native_actor._skeleton.get_children():
  if polygon is Polygon2D and polygon.get_bone_count()>0:
   for bone_index in polygon.get_bone_count():
    # Godot resolves these paths from Skeleton2D, not Polygon2D.
    verify(lab.native_actor._skeleton.get_node_or_null(polygon.get_bone_path(bone_index)) is Bone2D,"skin path relative to skeleton")
   for vertex in polygon.polygon.size():
    var weight_sum := 0.0
    for bone_index in polygon.get_bone_count():weight_sum+=polygon.get_bone_weights(bone_index)[vertex]
    verify(absf(weight_sum-1)<0.00001,"normalized sleeve vertex weights")
 verify(lab.clip == "thrust","initial clip")
 verify(lab.native_actor.diagnostics().bone_count == 14,"native real skeleton")
 verify(lab.native_actor.diagnostics().weighted_polygon_count == 6,"native sleeve skinning")
 var skeletons: Array = lab._find_nodes(lab.live_model,"Skeleton3D")
 verify(skeletons.size() == 1,"live real skeleton")
 var skel: Skeleton3D = skeletons[0]
 verify(skel.get_bone_count() == 14,"live bone count")
 for clip in ["thrust","cut","staff"]:
  lab.select_clip(clip)
  verify(lab.live_animations.has(clip),"live clip "+clip)
  verify(lab.baked_frames[clip].size()==120,"120 real baked frames "+clip)
  for sample in range(0,121,4):
   var t := sample/30.0
   lab.seek_motion(t)
   await process_frame
   var joints: Dictionary = data.clips[clip][sample].joints
   for bone: Dictionary in data.bones:
    var index := skel.find_bone(bone.name)
    var actual := (skel.global_transform*skel.get_bone_global_pose(index)).origin
    var source: Array = joints[bone.head]
    var expected := Vector3(source[0],source[2],-source[1])
    verify(actual.distance_to(expected)<0.008,"live pose %s %.3f %s error %.5f"%[clip,t,bone.name,actual.distance_to(expected)])
   var contacts: Dictionary=lab.native_actor.diagnostics().contact_errors_px
   for joint in contacts:verify(float(contacts[joint])<0.1,"actual native contact "+joint)
   if clip=="staff":verify(lab.native_actor.diagnostics().staff_contact_error_px<0.1,"actual native staff grip")
   var texture := lab.baked_actor.texture as AtlasTexture
   var frame_index := mini(sample,119)
   var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/animation_lab/atlas.json"))
   var entry: Dictionary=manifest.clips[clip][frame_index]
   verify(texture.atlas.resource_path==entry.path,"baked frame mapping "+clip)
   verify(texture.region==Rect2(entry.region[0],entry.region[1],384,384),"baked frame rect")
   verify(lab.baked_actor.size==Vector2(448,448),"no per-frame sprite resizing")
 lab.select_clip("staff")
 lab.seek_motion(1.4)
 for mesh in lab._find_nodes(lab.live_model,"MeshInstance3D"):
  if str(mesh.name).contains("Sword"):verify(not mesh.visible,"staff hides sword")
  if str(mesh.name).contains("Staff"):verify(mesh.visible,"staff shows staff")
 lab.step_frame(1)
 verify(is_equal_approx(lab.seconds,43/30.0) and not lab.playing,"frame stepping pauses synchronized clock")
 lab.timeline.value=2.137
 verify(is_equal_approx(lab.seconds,2.137) and not lab.playing,"slider seeks synchronized clock")
 lab.reset_motion()
 verify(lab.seconds==0,"reset time only")
 lab._cycle_speed()
 verify(lab.speed==0.5 and lab.speed_button.text.contains("半速"),"half speed label")
 lab._cycle_speed()
 verify(lab.speed==0.25,"quarter speed")
 lab._cycle_speed()
 verify(lab.speed==1,"normal speed")
 lab._toggle_loop()
 lab.seconds=3.99;lab.playing=true;lab._process(0.1)
 verify(lab.seconds==4 and not lab.playing,"nonloop end stops")
 lab._toggle_loop()
 lab.seconds=3.99;lab.playing=true;lab._process(0.02);lab.playing=false
 verify(is_equal_approx(lab.seconds,0.01),"loop wraps shared clock")
 lab._toggle_background()
 for bg in lab.backgrounds:verify(not bg.visible,"neutral background shared")
 lab._toggle_background()
 lab.set_single_mode(2)
 verify(not lab.cards[0].visible and not lab.cards[1].visible and lab.cards[2].visible,"solo view")
 lab.set_single_mode(-1)
 for card in lab.cards:verify(card.visible and card.scale==Vector2.ONE,"restore side by side")
 verify(not FileAccess.file_exists("res://scripts/demo_state.gd"),"isolated staged lab does not include gameplay authority")
 print("ANIMATION_LAB_TEST: %d checks, %d failures"%[checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
