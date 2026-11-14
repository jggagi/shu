extends SceneTree
## Exact collision and large-city request costs, independent of GPU rendering.

const Navigation = preload("res://addons/cultivation_mode/chengdu_scale_navigation.gd")
const Baseline = preload("res://addons/cultivation_mode/town_navigation.gd")
var checks := 0
var failures := 0
var timings: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_thin_wall_and_cache()
	_test_exact_grid_and_buckets()
	_test_narrow_street()
	_test_dense_city()
	_test_authored_city_if_present()
	var directory := "res://.local/qa/chengdu-scale"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			directory = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var receipt := FileAccess.open(directory.path_join("navigation-cpu.json"), FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": timings,
			"scope": "single X1 headless CPU measurements; routes independently rechecked with the unchanged navigation geometry used by Session; no GPU, browser or physical-device performance claim"}, "\t"))
	print("CULTIVATION_ENGINE_CHENGDU_SCALE_NAVIGATION_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_thin_wall_and_cache() -> void:
	var definition := {"floor": [0, 0, 200, 140], "cell_size": 20, "actor_radius": 0, "obstacles": [[79, 0, 2, 100]]}
	var nav := Navigation.new()
	nav.configure(definition)
	var from := Vector2(30, 30)
	var target := Vector2(150, 30)
	var path: Array = nav.route(from, target)
	check(_legal(definition, from, path) and _max_y(path) >= 110, "cold route detours around a 2px wall between free grid centers")
	check(nav.last_route_searches == 1, "connected goal candidates require one city-wide A* search")
	var warm: Array = nav.route(from, target)
	check(warm == path and _legal(definition, from, warm), "warm edge cache retains the same legal thin-wall route")
	var reverse: Array = nav.route(target, from)
	check(_legal(definition, target, reverse) and _max_y(reverse) >= 110, "cached edges are safe in reverse")
	var approach: Array = nav.route(Vector2(70, 30), Vector2(100, 30), 40)
	check(_legal(definition, Vector2(70, 30), approach) and _max_y(approach) >= 110 and approach[-1].distance_to(Vector2(100, 30)) <= 40, "being within interaction radius never bypasses a thin wall")
	var count := nav.grid_build_count
	nav.configure(definition.duplicate(true))
	check(nav.grid_build_count == count and nav.configure_cache_hits == 1, "an identical geometry signature reuses the existing grid")
	var metadata_only := definition.duplicate(true)
	metadata_only["interactions"] = {"a": {"position": [150, 30]}}
	nav.configure(metadata_only)
	check(nav.grid_build_count == count, "presentation and hotspot metadata do not rebuild static geometry")
	nav.configure(definition, false)
	check(nav.route(from, target).is_empty() and not nav.clear_segment(from, target), "geometry-only mode retains collision but disables route requests")
	nav.configure(definition)
	check(nav.grid_build_count == count and nav.route(from, target) == path, "returning to grid mode reuses the same unmodified geometry safely")
	var open := definition.duplicate(true)
	open.obstacles = []
	nav.configure(open)
	check(nav.grid_build_count == count + 1 and nav.route(from, target) == [target], "removed walls invalidate grid and edge caches; legal direct requests skip A*")
	nav.configure(definition)
	check(nav.grid_build_count == count + 2 and _max_y(nav.route(from, target)) >= 110, "restored walls invalidate previously clear cached edges")
	var inflated := definition.duplicate(true)
	inflated.actor_radius = 8
	nav.configure(inflated)
	check(_legal(inflated, from, nav.route(from, target)), "changed actor radius is part of the geometry signature")
	var changed_step := definition.duplicate(true)
	changed_step.cell_size = 40
	nav.configure(changed_step)
	check(nav.cell_size == 40 and nav.route(from, target).is_empty(), "changed grid spacing never reuses a finer route through an insufficient end gap")
	changed_step.floor[3] = 180
	nav.configure(changed_step)
	check(_legal(changed_step, from, nav.route(from, target)), "changing the floor rebuilds the grid and permits a sufficiently wide end passage")
	check(nav.route(Vector2(-1, 30), target).is_empty() and nav.route(from, Vector2(NAN, 0)).is_empty() and nav.route(from, target, -1).is_empty(), "invalid starts, non-finite targets and negative radii cannot request movement")


func _test_exact_grid_and_buckets() -> void:
	var definition := {"floor": [-17, -29, 615, 477], "cell_size": 40, "actor_radius": 12,
		"obstacles": [[-10, 0, 30, 85], [64, 64, 66, 31], [243, 255, 2, 112], [510, 10, 30, 370]]}
	var nav := Navigation.new()
	nav.configure(definition)
	var original := Baseline.new()
	original.configure(definition, false)
	var equal := true
	for x: int in range(nav.grid.region.size.x):
		for y: int in range(nav.grid.region.size.y):
			var id := Vector2i(x, y)
			equal = equal and nav.grid.is_point_solid(id) == original.blocked(nav.center(id))
	check(equal, "inclusive obstacle rasterization matches every old collision center, including partial floor cells")
	var random := RandomNumberGenerator.new()
	random.seed = 14471
	var points_equal := true
	var segments_equal := true
	for index: int in range(1200):
		var a := Vector2(random.randf_range(-30, 650), random.randf_range(-40, 500))
		var b := Vector2(random.randf_range(-30, 650), random.randf_range(-40, 500))
		points_equal = points_equal and nav.blocked(a) == original.blocked(a)
		segments_equal = segments_equal and nav.clear_segment(a, b) == original.clear_segment(a, b)
	check(points_equal, "spatial buckets preserve 1200 independent exact point queries")
	check(segments_equal, "spatial buckets preserve 1200 independent slab segment queries")
	for boundary: Vector2 in [Vector2(256, 256), Vector2(512, 0), Vector2(0, 0), Vector2(598, 448)]:
		check(nav.blocked(boundary) == original.blocked(boundary), "bucket/floor boundaries retain closed obstacle and half-open floor semantics: " + str(boundary))
	var shifted := {"floor": [500, 500, 320, 160], "cell_size": 20, "actor_radius": 0, "obstacles": [[579, 500, 2, 120]]}
	nav.configure(shifted)
	var shifted_route: Array = nav.route(Vector2(530, 530), Vector2(650, 530))
	check(_legal(shifted, Vector2(530, 530), shifted_route) and _max_y(shifted_route) >= 630, "translated geometry and floor rebuild exact spatial buckets")
	var sealed := {"floor": [0, 0, 400, 400], "cell_size": 40, "actor_radius": 0,
		"obstacles": [[200, 0, 20, 400]]}
	nav.configure(sealed)
	check(nav.route(Vector2(60, 60), Vector2(300, 300)).is_empty(), "disconnected destinations return no route rather than crossing a sealed wall")


func _test_narrow_street() -> void:
	var definition := {"floor": [0, 0, 800, 480], "cell_size": 40, "actor_radius": 12,
		"obstacles": [[0, 160, 320, 160], [400, 160, 400, 160]]}
	var nav := Navigation.new()
	nav.configure(definition)
	var from := Vector2(120, 80)
	var target := Vector2(680, 400)
	check(not nav.clear_segment(from, target), "narrow-street test genuinely requires a route around building corners")
	var path: Array = nav.route(from, target)
	check(_legal(definition, from, path) and path[-1] == target, "40px grid reaches the destination through an 80px street with a 12px actor radius")
	check(nav.last_route_searches == 1, "narrow-street request searches one connected goal component")
	check(_legal(definition, target, nav.route(target, from)), "80px street remains passable in reverse")
	var interaction: Array = nav.route(from, target, 58)
	check(_legal(definition, from, interaction) and interaction[-1].distance_to(target) <= 58, "an interaction beyond the same narrow street has an accessible legal approach")


func _test_dense_city() -> void:
	var definition := {"floor": [80, 120, 15200, 11280], "size": [15360, 11520], "actor_radius": 12, "cell_size": 40, "obstacles": []}
	for index: int in range(600):
		var column := index % 30
		var row := floori(float(index) / 30.0)
		definition.obstacles.append([400 + column * 400, 600 + row * 400, 220, 220])
	var nav := Navigation.new()
	var start := Time.get_ticks_usec()
	nav.configure(definition)
	var configured := Time.get_ticks_usec()
	var from := Vector2(180, 300)
	var target := Vector2(14900, 10800)
	var path: Array = nav.route(from, target)
	var cold := Time.get_ticks_usec()
	var searches := nav.last_route_searches
	var warm: Array = nav.route(from, target)
	var hot := Time.get_ticks_usec()
	check(_legal(definition, from, path) and path[-1] == target, "600-building 15360x11520 synthetic city has an independently legal cross-city route")
	check(path == warm and searches == 1 and nav.last_route_searches == 1, "dense-city cold/hot requests use one global A* and retain a legal stable route")
	var original := Baseline.new()
	original.configure(definition, false)
	var commit_started := Time.get_ticks_usec()
	for index: int in range(2000):
		original.blocked(Vector2(184, 300))
		original.clear_segment(Vector2(180, 300), Vector2(184, 300))
	var commit_ended := Time.get_ticks_usec()
	var cache_started := Time.get_ticks_usec()
	nav.configure(definition.duplicate(true))
	var cache_ended := Time.get_ticks_usec()
	check(nav.grid_build_count == 1 and nav.configure_cache_hits == 1, "the same dense map reuses its complete grid on a second scene surface")
	var row := {"kind": "synthetic_600_building_city", "size": definition.size, "obstacles": 600,
		"configure_ms": float(configured - start) / 1000.0, "cold_route_ms": float(cold - configured) / 1000.0,
		"hot_route_ms": float(hot - cold) / 1000.0, "same_geometry_configure_ms": float(cache_ended - cache_started) / 1000.0,
		"route_points": path.size(), "global_searches": searches,
		"unchanged_session_collision_ms_per_step": float(commit_ended - commit_started) / 2000000.0,
		"session_collision_samples": 2000, "audit": nav.navigation_audit()}
	timings.append(row)
	print(JSON.stringify(row))


func _test_authored_city_if_present() -> void:
	var path := "res://games/shu_chengdu_scale/walks.json"
	if not FileAccess.file_exists(path):
		return
	var walks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var definition: Dictionary = walks.scenes.chengdu_city
	var nav := Navigation.new()
	var start := Time.get_ticks_usec()
	nav.configure(definition)
	var finish := Time.get_ticks_usec()
	var from := _point(definition.spawn)
	var samples: Array = []
	for id: String in definition.interactions:
		var interaction: Dictionary = definition.interactions[id]
		var target := _point(interaction.position)
		var before := Time.get_ticks_usec()
		var route: Array = nav.route(from, target, float(interaction.radius))
		var after := Time.get_ticks_usec()
		check(_legal(definition, from, route) and route[-1].distance_to(target) <= float(interaction.radius), "authored city arrival reaches actual interaction: " + id)
		samples.append({"interaction": id, "milliseconds": float(after - before) / 1000.0, "searches": nav.last_route_searches, "waypoints": route.size()})
	var all_pairs: Array = [
		["reference_dufu_cottage", "reference_daci_temple"],
		["reference_wuhou_shrine", "reference_north_precinct"],
		["reference_qingyang_palace", "reference_hejiang_pavilion"]]
	for pair: Array in all_pairs:
		if not definition.interactions.has(pair[0]) or not definition.interactions.has(pair[1]):
			continue
		var a := _point(definition.interactions[pair[0]].position)
		var b := _point(definition.interactions[pair[1]].position)
		var before := Time.get_ticks_usec()
		var route: Array = nav.route(a, b)
		var after := Time.get_ticks_usec()
		check(_legal(definition, a, route) and route[-1] == b, "authored opposite city districts remain connected: " + str(pair))
		samples.append({"pair": pair, "milliseconds": float(after - before) / 1000.0, "searches": nav.last_route_searches, "waypoints": route.size()})
	timings.append({"kind": "authored_city", "size": definition.size, "configure_ms": float(finish - start) / 1000.0, "audit": nav.navigation_audit(), "routes": samples})


func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _legal(definition: Dictionary, from: Vector2, path: Array) -> bool:
	if path.is_empty():
		return false
	var authority := Baseline.new()
	authority.configure(definition, false)
	var previous := from
	for point: Vector2 in path:
		if not authority.clear_segment(previous, point):
			return false
		previous = point
	return true


func _max_y(path: Array) -> float:
	var value := -INF
	for point: Vector2 in path:
		value = maxf(value, point.y)
	return value


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
