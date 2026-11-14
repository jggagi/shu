extends SceneTree
## Route behavior across a sub-cell wall, in both directions and after map
## changes. These assertions exercise navigation, not cache representation.

const Navigation = preload("res://addons/cultivation_mode/town_navigation.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := {"floor": [0, 0, 200, 140], "cell_size": 20, "actor_radius": 0, "obstacles": [[79, 0, 2, 100]]}
	var nav = Navigation.new()
	nav.configure(map)
	var origin := Vector2(30, 30)
	var destination := Vector2(150, 30)
	var cold: Array = nav.route(origin, destination)
	check(_legal(nav, origin, cold) and _max_y(cold) >= 110, "cold route goes around the 2px wall between free grid centers")
	var warm: Array = nav.route(origin, destination)
	check(warm == cold and _legal(nav, origin, warm), "repeated route retains the exact original path and wall detour")
	var reverse: Array = nav.route(destination, origin)
	check(_legal(nav, destination, reverse) and _max_y(reverse) >= 110, "reverse route cannot cross the thin wall after earlier forward searches")
	var approach: Array = nav.route(Vector2(70, 30), Vector2(100, 30), 40)
	check(_legal(nav, Vector2(70, 30), approach) and _max_y(approach) >= 110 and approach[-1].x > 81, "near interaction radius still requires walking around the separating wall")
	var open := map.duplicate(true)
	open.obstacles = []
	nav.configure(open)
	var direct: Array = nav.route(origin, destination)
	check(_legal(nav, origin, direct) and _max_y(direct) <= 31 and direct.size() < cold.size(), "reconfiguring without the wall clears former blocked-edge results")
	nav.configure(map)
	var blocked_again: Array = nav.route(origin, destination)
	check(blocked_again == cold and _legal(nav, origin, blocked_again), "reconfiguring with the wall discards earlier clear-edge results")
	var inflated := map.duplicate(true)
	inflated.actor_radius = 8
	nav.configure(inflated)
	var wide_actor: Array = nav.route(origin, destination)
	check(_legal(nav, origin, wide_actor) and _max_y(wide_actor) >= 110, "changed actor radius retains exact expanded collision checks")
	var shifted := {"floor": [500, 500, 320, 160], "cell_size": 20, "actor_radius": 0, "obstacles": [[579, 500, 2, 120]]}
	nav.configure(shifted)
	var shifted_route: Array = nav.route(Vector2(530, 530), Vector2(650, 530))
	check(_legal(nav, Vector2(530, 530), shifted_route) and _max_y(shifted_route) >= 630, "resized and translated grid computes fresh thin-wall crossings")
	nav.configure(map, false)
	check(nav.route(origin, destination).is_empty(), "geometry-only configuration does not reuse the previous pathfinding grid")
	nav.configure(map)
	check(nav.route(origin, destination) == cold, "a fresh grid after geometry-only configuration preserves the original route")
	print("CULTIVATION_ENGINE_TOWN_NAVIGATION_CACHE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _legal(nav: RefCounted, origin: Vector2, path: Array) -> bool:
	if path.is_empty():
		return false
	var previous := origin
	for point: Vector2 in path:
		if not nav.clear_segment(previous, point):
			return false
		previous = point
	return true

func _max_y(path: Array) -> float:
	var maximum := -INF
	for point: Vector2 in path:
		maximum = maxf(maximum, point.y)
	return maximum

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
