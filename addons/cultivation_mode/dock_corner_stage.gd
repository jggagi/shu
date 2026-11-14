extends Node
## Actor-only depth pass. The dock is an authored painting, with no city geometry.
const Actor = preload("res://addons/cultivation_mode/chengdu_actor.gd")
const Resident = preload("res://addons/cultivation_mode/dock_corner_resident.gd")
const Cat = preload("res://addons/cultivation_mode/dock_corner_cat.gd")
const LIFE = "res://assets/data/dock-corner-life.json"
const Lamps = preload("res://addons/cultivation_mode/dock_corner_lamps.gd")
const THROW_CLIP = preload("res://assets/motion/dock_pebble/throw.tres")
const THROW_CONFIG = "res://assets/data/dock-corner-pebble-motion.json"
const PIXELS := 80.0
var viewport: SubViewport
var camera: Camera3D
var actors: Dictionary = {}
var environment: Environment
var sun: DirectionalLight3D
var lighting_enabled := false
var time_light: Dictionary = {}
var lamp_strength := 0.0
var lamps: Array[OmniLight3D] = []
var throw_profile: Dictionary = {}
var release_point := Vector2.ZERO
var throw_age := -1.0
var cat: Node3D

func logical_to_world(point: Vector2) -> Vector3:
	return Vector3((point.x - 640.0) / PIXELS, 0, (point.y - 360.0) / (PIXELS * sin(PI / 4)))

func setup(point: Vector2) -> void:
	viewport = SubViewport.new()
	viewport.name = "DockActorsViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#dbd5bb")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	environment = env.environment
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#ffe7c5")
	sun.light_energy = 0.6
	sun.rotation_degrees = Vector3(-60, -35, 0)
	world.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.0
	world.add_child(camera)
	camera.position = Vector3(0, 12, 12)
	camera.rotation_degrees = Vector3(-45,0,0)
	camera.current = true
	var scale := 1.55 / 2.096427
	_add(world, "player", {"model":"res://assets/art/town_volume_character/jiang-town.glb", "idle":"TownIdle", "walk":"TownWalk", "scale":scale, "anchor":[0,0.000216,0], "cycle_distance":1.4 * scale * PIXELS}, point)
	_add(world, "keeper", {"model":"res://assets/art/town_volume_cast/tea-seller.glb", "idle":"SellerCupWork", "scale":0.76, "anchor":[0,0.000335355,0.09], "yaw":0.4}, Vector2(350,310))
	var life: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LIFE))
	for profile: Dictionary in life.people:
		var resident := Resident.new()
		world.add_child(resident)
		var point_at: Array = profile.path[0]
		resident.setup(self,str(profile.id),{"model":life.person_model,"idle":"SellerCupWork","scale":profile.scale,"anchor":[0,0.000335355,0.09],"cycle_distance":1.4*float(profile.scale)*PIXELS},Vector2(point_at[0],point_at[1]))
		resident.install_daily_clips(actors.player,profile)
		actors[str(profile.id)] = resident
	cat = Cat.new()
	world.add_child(cat)
	cat.setup()
	throw_profile = JSON.parse_string(FileAccess.get_file_as_string(THROW_CONFIG))
	var library := AnimationLibrary.new()
	library.add_animation("Throw",THROW_CLIP)
	actors.player.animator.add_animation_library("dock",library)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Lamps.LAYOUT))
	for fixture: Dictionary in layout.fixtures:
		var lamp := OmniLight3D.new()
		lamp.name = "DockLamp_"+str(fixture.id)
		lamp.light_color = Color("#ffd092")
		lamp.light_energy = 0.0
		lamp.omni_range = float(fixture.range)
		lamp.omni_attenuation = 1.4
		var ground_point := Vector2(fixture.ground[0],fixture.ground[1])
		lamp.position = logical_to_world(ground_point)+Vector3.UP*((ground_point.y-float(fixture.center[1]))/(PIXELS*sin(PI/4)))
		lamp.set_meta("energy",float(fixture.energy))
		world.add_child(lamp)
		lamps.append(lamp)

func _add(world: Node3D, id: String, profile: Dictionary, point: Vector2) -> void:
	var actor := Actor.new()
	world.add_child(actor)
	actor.setup(self, id, profile, point)
	actors[id] = actor

func sync(point: Vector2, stride: float, walking: bool, elapsed: float) -> void:
	for id: String in actors:
		actors[id].sync(point, stride, walking, elapsed)
	for lamp: OmniLight3D in lamps:
		lamp.light_energy = float(lamp.get_meta("energy"))*lamp_strength*Lamps.flame_level(elapsed) if lighting_enabled else 0.0

func present_life(life: RefCounted) -> void:
	for id: String in life.people:
		actors[id].present(life.people[id])
	cat.present(self,life.cat,float(life.config.cat.width))

func audit() -> Dictionary:
	var result := {}
	for id: String in actors:
		result[id] = actors[id].audit()
	return {"actors":result, "projection_origin":camera.unproject_position(logical_to_world(Vector2(640,360))), "viewport_size":viewport.size}

func set_lighting(enabled: bool) -> void:
	lighting_enabled = enabled
	environment.ambient_light_color = Color("#c9d3d5") if enabled else Color("#dbd5bb")
	environment.ambient_light_energy = 0.53 if enabled else 0.65
	sun.light_color = Color("#ffe4ba") if enabled else Color("#ffe7c5")
	sun.light_energy = 0.76 if enabled else 0.6
	sun.rotation_degrees = Vector3(-60,-35,0)
	if enabled and not time_light.is_empty():
		environment.ambient_light_color = Color(time_light.ambient_color)
		environment.ambient_light_energy = float(time_light.ambient_energy)
		sun.light_color = Color(time_light.sun_color)
		sun.light_energy = float(time_light.sun_energy)
		var rotation: Array = time_light.sun_rotation
		sun.rotation_degrees = Vector3(rotation[0],rotation[1],rotation[2])

func set_time_light(profile: Dictionary) -> void:
	time_light = profile.duplicate(true)
	set_lighting(lighting_enabled)

func set_lamp_strength(amount: float) -> void:
	lamp_strength = amount
	for lamp: OmniLight3D in lamps:
		lamp.light_energy = float(lamp.get_meta("energy"))*amount if lighting_enabled else 0.0

func face_keeper() -> void:
	# Keep the existing original clips; only orient the two present actors.
	var player: Node3D = actors.player
	var keeper: Node3D = actors.keeper
	var direction := keeper.position-player.position
	if direction.length_squared()<0.001:
		return
	var heading := atan2(direction.x,direction.z)
	player.set("yaw",heading)
	player.rotation.y = heading
	keeper.rotation.y = heading+PI

func can_throw() -> bool:
	return bool(actors.player.available) and actors.player.animator.has_animation("dock/Throw")

func present_throw(age: float, landing: Vector2) -> Vector2:
	throw_age = age
	if age<0.0 or age>=float(throw_profile.duration) or not can_throw():
		return release_point
	var player: Node3D = actors.player
	var target := logical_to_world(landing)-player.position
	var heading := atan2(target.x,target.z)
	player.set("yaw",heading)
	player.rotation.y = heading
	player.call("_sample","dock/Throw",float(throw_profile.release))
	var skeleton := player.get("skeleton") as Skeleton3D
	var bone: int = skeleton.find_bone("hand.R")
	var hand: Vector3 = player.transform*player.call("_bone_position",bone)
	# UI rebuilds construct the viewport before it enters SceneTree. This is
	# the same fixed orthographic projection, valid during detached setup too.
	release_point = Vector2(640.0+hand.x*PIXELS,360.0+(hand.z*sin(PI/4)-hand.y*cos(PI/4))*PIXELS)
	player.call("_sample","dock/Throw",minf(age,float(throw_profile.duration)))
	player.call("_sync_contacts")
	return release_point
