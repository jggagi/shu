extends RefCounted
## Scene-local presentation state survives view rebuilds; never holds EngineSession.
const Presenter = preload("res://scripts/ambient_life_presenter.gd")
const CONFIG = "res://assets/data/dock-corner-life.json"
const SOURCE = "res://assets/data/dock-corner-life-source.json"
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
var people: Dictionary = {}
var cat: Dictionary = {}
var scheduler := Presenter.new()
var rng := RandomNumberGenerator.new()
var moving := true
var busy := false
var elapsed := 0.0

func _init() -> void:
	reset()

func _curve(points: Array) -> Curve2D:
	var curve := Curve2D.new()
	for point: Array in points:
		curve.add_point(Vector2(point[0],point[1]))
	return curve

func reset() -> void:
	elapsed = 0.0
	rng.seed = int(config.seed)
	scheduler.configure(config.schedule)
	people.clear()
	for profile: Dictionary in config.people:
		var curve := _curve(profile.path)
		var distance := float(profile.start_distance)
		people[str(profile.id)] = {"curve":curve,"distance":distance,"direction":1.0,"stride":0.0,"wait":rng.randf_range(3.0,4.5),"point":curve.sample_baked(distance),"walking":false,"yaw":0.0,"phase":0.0,"profile":profile,"quiet":false,"rest_age":0.0,"idle_index":0,"idle_action":str(profile.idle_actions[0])}
	var cat_curve := _curve(config.cat.path)
	cat = {"curve":cat_curve,"distance":0.0,"stride":0.0,"point":cat_curve.sample_baked(0.0),"phase":"home","wait":0.0,"facing":1.0,"pose":12}

func advance(delta: float, dynamic: bool, foreground_busy: bool, player: Vector2, profile: String) -> void:
	moving = dynamic
	busy = foreground_busy
	var step := minf(maxf(delta,0.0),0.05) if dynamic and not busy else 0.0
	elapsed += step
	var habitat_available: bool = (cat.curve as Curve2D).get_baked_length()>1.0 and config.cat.path.size()>=2
	scheduler.observe({"dynamic_enabled":dynamic,"weather_id":"clear","night_preview":profile=="moonlight","time_profile_id":"you" if profile=="dusk" else "wu"},{"cat":habitat_available,"cat_sheltered":bool(config.cat.sheltered),"cat_night_allowed":true})
	# The same boundary gates both opportunity and travel clocks during foreground work.
	var requests := scheduler.advance(step,busy)
	for request: Dictionary in requests:
		if request.kind=="cat" and cat.phase=="home":
			cat.phase = "outbound"
	for resident: Dictionary in people.values():
		resident.walking = false
		resident.quiet = step<=0.0 or resident.point.distance_to(player)<55.0
		if bool(resident.quiet):
			continue
		resident.phase += step
		if float(resident.wait)>0.0:
			resident.wait = maxf(0.0,float(resident.wait)-step)
			resident.rest_age += step
			continue
		var curve: Curve2D = resident.curve
		var direction := float(resident.direction)
		var goal := curve.get_baked_length() if direction>0 else 0.0
		var travel := minf(absf(goal-float(resident.distance)),float(resident.profile.speed)*step*(0.65 if profile=="moonlight" else 1.0))
		var before: Vector2 = resident.point
		resident.distance += direction*travel
		resident.stride += travel
		resident.point = curve.sample_baked(resident.distance)
		var heading: Vector2 = resident.point-before
		if heading.length_squared()>0.000001:
			resident.yaw = rotate_toward(float(resident.yaw),atan2(heading.x,heading.y),step*3.8)
		resident.walking = travel>0.0
		if absf(goal-float(resident.distance))<0.001:
			resident.direction = -direction
			resident.wait = rng.randf_range(8.0,11.0)
			resident.rest_age = 0.0
			resident.idle_index += 1
			var actions: Array = resident.profile.idle_actions
			resident.idle_action = str(actions[int(resident.idle_index)%actions.size()])
	var cat_walking := false
	if step>0.0 and cat.point.distance_to(player)>=32.0:
		if cat.phase=="outbound" or cat.phase=="return":
			var curve: Curve2D = cat.curve
			var goal := curve.get_baked_length() if cat.phase=="outbound" else 0.0
			cat.facing = 1.0 if cat.phase=="outbound" else -1.0
			var travel := minf(absf(goal-float(cat.distance)),float(config.cat.speed)*step)
			cat.distance = move_toward(float(cat.distance),goal,travel)
			cat.stride += travel
			cat.point = curve.sample_baked(cat.distance)
			cat_walking = travel>0.0
			if absf(goal-float(cat.distance))<0.001:
				cat.phase = "look" if cat.phase=="outbound" else "home"
				cat.wait = 6.0
		elif cat.phase=="look":
			cat.wait = maxf(0.0,float(cat.wait)-step)
			if float(cat.wait)<=0.0:
				cat.phase = "return"
	cat.pose = 8+posmod(int(float(cat.stride)/2.2),4) if cat_walking else 12

func audit() -> Dictionary:
	var residents := {}
	for id: String in people:
		var state: Dictionary = people[id]
		residents[id] = {"point":state.point,"walking":state.walking,"stride":state.stride,"wait":state.wait,"rest_age":state.rest_age,"idle_action":state.idle_action,"quiet":state.quiet}
	return {"people":residents,"cat":{"point":cat.point,"pose":cat.pose,"phase":cat.phase,"facing":cat.facing,"distance":cat.distance},"elapsed":elapsed,"schedule_elapsed":scheduler.elapsed,"busy":busy,"dynamic":moving}
