extends "res://addons/cultivation_mode/town_navigation.gd"
## Large-city presentation navigation. Geometry and movement are still checked
## by EngineSession; this helper holds only rebuildable spatial caches.

const ParentNavigation = preload("res://addons/cultivation_mode/town_navigation.gd")
const BUCKET_SIZE := 256.0

class SpatialGrid extends ParentNavigation.CollisionGrid:
	var owner_ref: WeakRef

	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var distance := absi(to_id.x - from_id.x) + absi(to_id.y - from_id.y)
		var index := -1
		if distance == 1 and is_in_boundsv(from_id) and is_in_boundsv(to_id):
			var cell := Vector2i(mini(from_id.x, to_id.x), mini(from_id.y, to_id.y)) - region.position
			index = (cell.y * region.size.x + cell.x) * 2 + (0 if from_id.y == to_id.y else 1)
			if _edge_states[index] != 0:
				return float(distance) if _edge_states[index] == 1 else INF
		var owner: RefCounted = owner_ref.get_ref() if owner_ref != null else null
		var clear: bool = owner != null and bool(owner.call("_segment_clear", get_point_position(from_id), get_point_position(to_id)))
		if index >= 0:
			_edge_states[index] = 1 if clear else 2
		return float(distance) if clear else INF


var _geometry_signature := ""
var _cached_grid_ready := false
var _buckets: Dictionary = {}
var grid_build_count := 0
var configure_cache_hits := 0
var route_search_count := 0
var last_route_searches := 0


func configure(definition: Dictionary, build_grid: bool = true) -> void:
	var geometry := {"floor": definition.get("floor", []), "cell_size": definition.get("cell_size", 20),
		"actor_radius": definition.get("actor_radius", 12), "obstacles": definition.get("obstacles", definition.get("buildings", []))}
	var signature := JSON.stringify(geometry).sha256_text()
	if _configured and signature == _geometry_signature:
		configure_cache_hits += 1
		_grid_ready = build_grid and _cached_grid_ready
		if not build_grid or _cached_grid_ready:
			return
	else:
		super.configure(definition, false)
		_cached_grid_ready = false
		_geometry_signature = signature
		_buckets.clear()
		if not _configured:
			return
		for index: int in range(buildings.size()):
			var box: Rect2 = buildings[index]
			var first := _bucket(box.position)
			var last := _bucket(box.end)
			for x: int in range(first.x, last.x + 1):
				for y: int in range(first.y, last.y + 1):
					var key := Vector2i(x, y)
					if not _buckets.has(key):
						_buckets[key] = PackedInt32Array()
					var indices: PackedInt32Array = _buckets[key]
					indices.append(index)
					_buckets[key] = indices
	if not build_grid:
		return
	var next := SpatialGrid.new()
	next.owner_ref = weakref(self)
	grid = next
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(floor_rect.size.x / cell_size), ceili(floor_rect.size.y / cell_size)))
	grid.cell_size = Vector2.ONE * cell_size
	grid.offset = floor_rect.position + Vector2.ONE * cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	grid.prepare_edge_cache()
	# The former per-cell scan was O(cells * obstacle_count). These inclusive
	# ranges mark exactly the same expanded rectangles at grid centers.
	for box: Rect2 in buildings:
		var first := Vector2i(ceili((box.position.x - grid.offset.x) / cell_size), ceili((box.position.y - grid.offset.y) / cell_size))
		var last := Vector2i(floori((box.end.x - grid.offset.x) / cell_size), floori((box.end.y - grid.offset.y) / cell_size))
		var covered := Rect2i(first, last - first + Vector2i.ONE).intersection(grid.region)
		if covered.has_area():
			grid.fill_solid_region(covered, true)
	# Rect2.has_point uses a half-open floor. A partial final cell's center may
	# exceed that floor even though ceil(size / step) allocated the cell.
	for x: int in range(grid.region.size.x):
		if center(Vector2i(x, 0)).x >= floor_rect.end.x:
			grid.fill_solid_region(Rect2i(x, 0, 1, grid.region.size.y), true)
	for y: int in range(grid.region.size.y):
		if center(Vector2i(0, y)).y >= floor_rect.end.y:
			grid.fill_solid_region(Rect2i(0, y, grid.region.size.x, 1), true)
	_cached_grid_ready = true
	_grid_ready = true
	grid_build_count += 1


func _bucket(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / BUCKET_SIZE), floori(point.y / BUCKET_SIZE))


func blocked(point: Vector2) -> bool:
	if not _configured or not _finite_point(point) or not floor_rect.has_point(point):
		return true
	for index: int in _buckets.get(_bucket(point), PackedInt32Array()):
		if _contains_closed(buildings[index], point):
			return true
	return false


func _segment_candidates(from: Vector2, to: Vector2) -> PackedInt32Array:
	var first := _bucket(Vector2(minf(from.x, to.x), minf(from.y, to.y)))
	var last := _bucket(Vector2(maxf(from.x, to.x), maxf(from.y, to.y)))
	var unique: Dictionary = {}
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			for index: int in _buckets.get(Vector2i(x, y), PackedInt32Array()):
				unique[index] = true
	return PackedInt32Array(unique.keys())


func _segment_clear(from: Vector2, to: Vector2) -> bool:
	for index: int in _segment_candidates(from, to):
		if ParentNavigation.CollisionGrid.segment_hits_rect(from, to, buildings[index]):
			return false
	return true


func clear_segment(from: Vector2, to: Vector2) -> bool:
	return not blocked(from) and not blocked(to) and _segment_clear(from, to)


func _interaction_clear(from: Vector2, target: Vector2) -> bool:
	for index: int in _segment_candidates(from, target):
		var box: Rect2 = buildings[index]
		if not _contains_closed(box, target) and ParentNavigation.CollisionGrid.segment_hits_rect(from, target, box):
			return false
	return true


func route(from: Vector2, target: Vector2, interaction_radius: float = 0.0) -> Array[Vector2]:
	last_route_searches = 0
	var empty: Array[Vector2] = []
	if not _grid_ready or blocked(from) or not _finite_point(target) or not is_finite(interaction_radius) or interaction_radius < 0:
		return empty
	if interaction_radius <= 0 and blocked(target):
		return empty
	if interaction_radius > 0:
		if from.distance_to(target) <= interaction_radius and _interaction_clear(from, target):
			return [from]
		var approach := (target + (from - target).normalized() * maxf(0.0, interaction_radius - 1.0)).round()
		if approach.distance_to(target) <= interaction_radius and clear_segment(from, approach) and _interaction_clear(approach, target):
			return [approach]
	elif clear_segment(from, target):
		return [target]
	var start := cell_near(from)
	if start.x < 0:
		return empty
	var approximate := _cell_for(target)
	var reach := ceili(interaction_radius / cell_size) + 1
	var candidates: Array[Dictionary] = []
	for x: int in range(approximate.x - reach, approximate.x + reach + 1):
		for y: int in range(approximate.y - reach, approximate.y + reach + 1):
			var id := Vector2i(x, y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
				continue
			var point := center(id)
			if interaction_radius > 0:
				if point.distance_to(target) > interaction_radius or not _interaction_clear(point, target):
					continue
			elif not clear_segment(point, target):
				continue
			var estimate := absf(point.x - from.x) + absf(point.y - from.y) + point.distance_to(target)
			candidates.append({"id": id, "estimate": estimate})
	if candidates.is_empty():
		return empty
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.estimate) < float(b.estimate))
	# Candidates joined by exact local grid edges are globally equivalent for
	# reachability. Try only one representative per local component, rather
	# than running the same whole-city search once for every nearby goal.
	var components := _local_components(approximate, reach + 1)
	var attempted: Dictionary = {}
	for candidate: Dictionary in candidates:
		var goal: Vector2i = candidate.id
		var component: Vector2i = components.get(goal, goal)
		if attempted.has(component):
			continue
		attempted[component] = true
		last_route_searches += 1
		route_search_count += 1
		var path := grid.get_point_path(start, goal)
		if path.is_empty() or not _path_clear(from, path):
			continue
		var result := _compress_path(from, path)
		if interaction_radius <= 0:
			result.append(target)
		return result
	return empty


func _local_components(near: Vector2i, reach: int) -> Dictionary:
	var window := Rect2i(near - Vector2i.ONE * reach, Vector2i.ONE * (reach * 2 + 1)).intersection(grid.region)
	var groups: Dictionary = {}
	for x: int in range(window.position.x, window.end.x):
		for y: int in range(window.position.y, window.end.y):
			var initial := Vector2i(x, y)
			if groups.has(initial) or grid.is_point_solid(initial):
				continue
			var pending: Array[Vector2i] = [initial]
			groups[initial] = initial
			var cursor := 0
			while cursor < pending.size():
				var current := pending[cursor]
				cursor += 1
				for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next := current + direction
					if not window.has_point(next) or groups.has(next) or grid.is_point_solid(next):
						continue
					if grid._compute_cost(current, next) == INF:
						continue
					groups[next] = initial
					pending.append(next)
	return groups


func _compress_path(from: Vector2, path: PackedVector2Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var previous := from
	for index: int in range(path.size()):
		var point := path[index]
		if index < path.size() - 1 and (point - previous).cross(path[index + 1] - point) == 0 and clear_segment(previous, path[index + 1]):
			continue
		result.append(point)
		previous = point
	return result


func navigation_audit() -> Dictionary:
	return {"grid_build_count": grid_build_count, "configure_cache_hits": configure_cache_hits,
		"route_search_count": route_search_count, "last_route_searches": last_route_searches,
		"obstacle_count": buildings.size(), "bucket_count": _buckets.size(),
		"cell_count": grid.region.size.x * grid.region.size.y if _cached_grid_ready else 0,
		"edge_cache_bytes": grid._edge_states.size() if _cached_grid_ready else 0}
