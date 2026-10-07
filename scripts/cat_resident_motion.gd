extends RefCounted
class_name CatResidentMotion

enum Phase { INITIAL_REST, STAND, OUTBOUND, SNIFF, SIT, RETURN, HOME_REST }

const WALK_SPEED := 6.0
const GAIT_CADENCE := 3.6
const EPSILON := 0.000001
const PHASE_NAMES := ["initial_rest", "stand", "outbound", "sniff", "sit", "return", "home_rest"]
const DEFAULT_PHASE_DURATIONS := {
	"initial_rest": 6.0,
	"stand": 2.0,
	"sniff": 3.0,
	"sit": 8.0,
	"home_rest": 8.0,
}

var active := false
var activity_elapsed := 0.0
var walk_speed := WALK_SPEED
var gait_cadence := GAIT_CADENCE

var _phase_durations: Dictionary = DEFAULT_PHASE_DURATIONS.duplicate(true)
var _path: Path2D
var _curve: Curve2D
var _route_length := 0.0
var _home_distance := 0.0
var _target_distance := 0.0
var _distance := 0.0
var _gait_distance := 0.0
var _phase := Phase.INITIAL_REST
var _phase_elapsed := 0.0
var _facing := 1.0


func configure(options: Dictionary = {}) -> void:
	walk_speed = maxf(0.01, float(options.get("walk_speed", WALK_SPEED)))
	gait_cadence = maxf(0.01, float(options.get("gait_cadence", GAIT_CADENCE)))
	var durations: Variant = options.get("phase_durations", {})
	_phase_durations = DEFAULT_PHASE_DURATIONS.duplicate(true)
	if durations is Dictionary:
		for phase_name in _phase_durations:
			_phase_durations[phase_name] = maxf(
				0.0,
				float(durations.get(phase_name, _phase_durations[phase_name]))
			)


func start(path: Path2D, home_global_position: Vector2) -> bool:
	reset()
	if path == null or path.curve == null or path.curve.get_point_count() < 2:
		return false
	_path = path
	_curve = path.curve
	_route_length = _curve.get_baked_length()
	if _route_length <= 1.0:
		reset()
		return false

	var home_local := _path.to_local(home_global_position)
	var first_point := _curve.sample_baked(0.0)
	var last_point := _curve.sample_baked(_route_length)
	_home_distance = 0.0 if home_local.distance_to(first_point) <= home_local.distance_to(last_point) else _route_length
	_distance = _home_distance
	_target_distance = _route_length if _home_distance <= EPSILON else 0.0
	_facing = signf(_target_distance - _home_distance)
	_phase = Phase.INITIAL_REST
	active = true
	return true


func reset() -> void:
	active = false
	activity_elapsed = 0.0
	_path = null
	_curve = null
	_route_length = 0.0
	_home_distance = 0.0
	_target_distance = 0.0
	_distance = 0.0
	_gait_distance = 0.0
	_phase = Phase.INITIAL_REST
	_phase_elapsed = 0.0
	_facing = 1.0


func advance(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	var remaining := delta
	activity_elapsed += delta
	while remaining > EPSILON:
		if _phase == Phase.OUTBOUND or _phase == Phase.RETURN:
			remaining = _advance_travel(remaining)
		else:
			var phase_duration := _phase_duration()
			var phase_remaining := maxf(0.0, phase_duration - _phase_elapsed)
			if phase_remaining <= EPSILON:
				_advance_phase()
				continue
			var used := minf(remaining, phase_remaining)
			_phase_elapsed += used
			remaining -= used
			if _phase_elapsed >= phase_duration - EPSILON:
				_advance_phase()


func is_walking() -> bool:
	return _phase == Phase.OUTBOUND or _phase == Phase.RETURN


func pose_index() -> int:
	if is_walking():
		var frame_step := walk_speed / gait_cadence
		return 8 + posmod(int(floor(_gait_distance / frame_step)), 4)
	if _phase == Phase.SIT:
		return 12
	if _phase == Phase.STAND or _phase == Phase.SNIFF:
		return 13
	return -1


func facing_x() -> float:
	return _facing


func body_bob() -> float:
	if not is_walking():
		return 0.0
	var period_distance := walk_speed * 0.55
	return sin(_gait_distance * TAU / period_distance) * 0.7


func global_position() -> Vector2:
	if not active or not is_instance_valid(_path) or _curve == null:
		return Vector2.ZERO
	return _path.to_global(_curve.sample_baked(_distance))


func phase_name() -> String:
	return PHASE_NAMES[_phase]


func phase_elapsed() -> float:
	return _phase_elapsed


func route_distance() -> float:
	return _distance


func route_length() -> float:
	return _route_length


func gait_distance() -> float:
	return _gait_distance


func _advance_travel(remaining: float) -> float:
	var goal := _target_distance if _phase == Phase.OUTBOUND else _home_distance
	var distance_remaining := absf(goal - _distance)
	if distance_remaining <= EPSILON:
		_distance = goal
		_advance_phase()
		return remaining
	var travel_remaining := distance_remaining / walk_speed
	var used := minf(remaining, travel_remaining)
	var distance_step := minf(distance_remaining, used * walk_speed)
	_distance += signf(goal - _distance) * distance_step
	_gait_distance += distance_step
	remaining -= used
	if distance_step >= distance_remaining - EPSILON:
		_distance = goal
		_advance_phase()
	return remaining


func _phase_duration() -> float:
	return float(_phase_durations.get(PHASE_NAMES[_phase], 0.0))


func _advance_phase() -> void:
	_phase_elapsed = 0.0
	match _phase:
		Phase.INITIAL_REST:
			_phase = Phase.STAND
		Phase.STAND:
			_phase = Phase.OUTBOUND
			_facing = signf(_target_distance - _distance)
		Phase.OUTBOUND:
			_phase = Phase.SNIFF
		Phase.SNIFF:
			_phase = Phase.SIT
		Phase.SIT:
			_phase = Phase.RETURN
			_facing = signf(_home_distance - _distance)
		Phase.RETURN:
			_distance = _home_distance
			_phase = Phase.HOME_REST
		Phase.HOME_REST:
			_phase = Phase.INITIAL_REST
			_facing = signf(_target_distance - _home_distance)
