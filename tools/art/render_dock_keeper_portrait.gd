extends SceneTree
## Offline bust from the exact in-scene original keeper, no generative service.
const Actor = preload("res://addons/cultivation_mode/chengdu_actor.gd")
class PortraitStage extends Node:
 func logical_to_world(_point: Vector2) -> Vector3:return Vector3.ZERO
func _initialize() -> void:call_deferred("render_portrait")
func render_portrait() -> void:
 var output="res://art/source/dock-dialogue/keeper-model.png"
 var args=OS.get_cmdline_user_args()
 if args.size()>0:output=args[0]
 var viewport=SubViewport.new()
 viewport.size=Vector2i(512,640)
 viewport.transparent_bg=true
 viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 var world=Node3D.new()
 viewport.add_child(world)
 var environment=WorldEnvironment.new()
 environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_CLEAR_COLOR
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color("#e2ddd0")
 environment.environment.ambient_light_energy=.65
 world.add_child(environment)
 var sun=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-32,-28,0)
 sun.light_color=Color("#fff0d9")
 sun.light_energy=.85
 world.add_child(sun)
 var stage=PortraitStage.new()
 world.add_child(stage)
 var actor=Actor.new()
 world.add_child(actor)
 actor.setup(stage,"keeper",{"model":"res://assets/art/town_volume_cast/tea-seller.glb","idle":"SellerCupWork","scale":.76,"anchor":[0,.000335355,.09],"yaw":-.12},Vector2.ZERO)
 actor.sync(Vector2.ZERO,0,false,0)
 for contact in actor.contacts:contact.visible=false
 var camera=Camera3D.new()
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=.86
 world.add_child(camera)
 camera.position=Vector3(.03,1.33,3.2)
 camera.look_at(Vector3(0,1.21,0))
 camera.current=true
 for i in range(8):await process_frame
 await RenderingServer.frame_post_draw
 var result=viewport.get_texture().get_image()
 DirAccess.make_dir_recursive_absolute(output.get_base_dir())
 var error=result.save_png(output)
 print("DOCK_KEEPER_PORTRAIT: ",error)
 quit(0 if error==OK else 1)
