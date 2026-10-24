extends RefCounted
## Local walking geometry adapted from Chengping navigation.gd at
## a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6. See
## docs/CHENGPING_P1B_SOURCE_AUDIT.md for scope and permission provenance.
## Coordinates are logical foot positions; this module owns no game state.

class CollisionGrid extends AStarGrid2D:
	var solid_boxes: Array[Rect2] = []

	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		for box: Rect2 in solid_boxes:
			if segment_hits_rect(get_point_position(from_id), get_point_position(to_id), box):
				return INF
		return float(absi(to_id.x - from_id.x) + absi(to_id.y - from_id.y))

	static func segment_hits_rect(from: Vector2, to: Vector2, box: Rect2) -> bool:
		# Exact slab intersection avoids the source's 5 px sampling gaps.
		var direction: Vector2 = to - from
		var first: float = 0.0
		var last: float = 1.0
		for axis: int in range(2):
			if direction[axis] == 0.0:
				if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
					return false
				continue
			var a: float = (box.position[axis] - from[axis]) / direction[axis]
			var b: float = (box.end[axis] - from[axis]) / direction[axis]
			first = maxf(first, minf(a, b))
			last = minf(last, maxf(a, b))
			if first > last:
				return false
		return true


var floor_rect: Rect2 = Rect2(60, 160, 1160, 490)
var cell_size: float = 20.0
var actor_radius: float = 12.0
var buildings: Array[Rect2] = []
var grid: CollisionGrid = CollisionGrid.new()
var _configured: bool = false
var _grid_ready: bool = false


func configure(definition: Dictionary, build_grid: bool = true) -> void:
	_configured = false
	_grid_ready = false
	buildings.clear()
	grid = CollisionGrid.new()
	floor_rect = _rect_from(definition.get("floor", [60, 160, 1160, 490]))
	var step_value: Variant = definition.get("cell_size", 20.0)
	var radius_value: Variant = definition.get("actor_radius", 12.0)
	if (not step_value is int and not step_value is float) or (not radius_value is int and not radius_value is float):
		return
	cell_size = float(step_value)
	actor_radius = float(radius_value)
	if not floor_rect.has_area() or not _finite_point(floor_rect.position) or not _finite_point(floor_rect.size):
		return
	if not is_finite(cell_size) or cell_size <= 0.0 or not is_finite(actor_radius) or actor_radius < 0.0:
		return
	var box_values: Variant = definition.get("obstacles", definition.get("buildings", []))
	if not box_values is Array:
		return
	var boxes: Array = box_values
	for value: Variant in boxes:
		var box: Rect2 = _rect_from(value)
		if not box.has_area() or not _finite_point(box.position) or not _finite_point(box.size):
			return
		buildings.append(box.grow(actor_radius))
	_configured = true
	if not build_grid:
		return
	grid.solid_boxes = buildings.duplicate()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(floor_rect.size.x / cell_size), ceili(floor_rect.size.y / cell_size)))
	grid.cell_size = Vector2.ONE * cell_size
	grid.offset = floor_rect.position + Vector2.ONE * cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for x: int in range(grid.region.size.x):
		for y: int in range(grid.region.size.y):
			var id: Vector2i = Vector2i(x, y)
			grid.set_point_solid(id, blocked(center(id)))
	_grid_ready = true


func center(id: Vector2i) -> Vector2:
	return grid.offset + Vector2(id) * cell_size


func blocked(point: Vector2) -> bool:
	if not _configured or not _finite_point(point) or not floor_rect.has_point(point):
		return true
	for box: Rect2 in buildings:
		if _contains_closed(box, point):
			return true
	return false


func clear_segment(from: Vector2, to: Vector2) -> bool:
	if blocked(from) or blocked(to):
		return false
	for box: Rect2 in buildings:
		if CollisionGrid.segment_hits_rect(from, to, box):
			return false
	return true


func cell_near(point: Vector2) -> Vector2i:
	if not _grid_ready or blocked(point):
		return Vector2i(-1, -1)
	var approximate: Vector2i = _cell_for(point)
	var best: Vector2i = Vector2i(-1, -1)
	var score: float = INF
	for x: int in range(approximate.x - 2, approximate.x + 3):
		for y: int in range(approximate.y - 2, approximate.y + 3):
			var id: Vector2i = Vector2i(x, y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
				continue
			var candidate: Vector2 = center(id)
			var distance: float = point.distance_squared_to(candidate)
			if distance < score and clear_segment(point, candidate):
				score = distance
				best = id
	return best


func route(from: Vector2, target: Vector2, interaction_radius: float = 0.0) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not _grid_ready or blocked(from) or not _finite_point(target) or not is_finite(interaction_radius):
		return result
	if interaction_radius < 0.0 or (interaction_radius <= 0.0 and blocked(target)):
		return result
	if interaction_radius > 0.0 and from.distance_to(target) <= interaction_radius and _interaction_clear(from, target):
		result.append(from)
		return result
	var start: Vector2i = cell_near(from)
	if start.x < 0:
		return result
	var approximate: Vector2i = _cell_for(target)
	var reach: int = ceili(interaction_radius / cell_size) + 1
	var best: PackedVector2Array = PackedVector2Array()
	var cost: float = INF
	for x: int in range(approximate.x - reach, approximate.x + reach + 1):
		for y: int in range(approximate.y - reach, approximate.y + reach + 1):
			var id: Vector2i = Vector2i(x, y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
				continue
			var point: Vector2 = center(id)
			if interaction_radius > 0.0:
				if point.distance_to(target) > interaction_radius or not _interaction_clear(point, target):
					continue
			elif not clear_segment(point, target):
				continue
			var path: PackedVector2Array = grid.get_point_path(start, id)
			if path.is_empty() or not _path_clear(from, path):
				continue
			var score: float = float(path.size() - 1) * cell_size + from.distance_to(path[0]) + point.distance_to(target) * 0.15
			if interaction_radius <= 0.0:
				score += point.distance_to(target)
			if score < cost:
				cost = score
				best = path
	for point: Vector2 in best:
		result.append(point)
	if not result.is_empty() and interaction_radius <= 0.0:
		result.append(target)
	return result


func _cell_for(point: Vector2) -> Vector2i:
	var relative: Vector2 = (point - grid.offset) / cell_size
	return Vector2i(floori(relative.x), floori(relative.y))


func _path_clear(from: Vector2, path: PackedVector2Array) -> bool:
	var previous: Vector2 = from
	for point: Vector2 in path:
		if not clear_segment(previous, point):
			return false
		previous = point
	return true


func _interaction_clear(from: Vector2, target: Vector2) -> bool:
	# A prop may itself occupy a blocking footprint. Approach its accessible side,
	# while still rejecting another building between the player and that prop.
	for box: Rect2 in buildings:
		if not _contains_closed(box, target) and CollisionGrid.segment_hits_rect(from, target, box):
			return false
	return true


func _contains_closed(box: Rect2, point: Vector2) -> bool:
	return point.x >= box.position.x and point.x <= box.end.x and point.y >= box.position.y and point.y <= box.end.y


func _finite_point(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)


func _rect_from(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if not value is Array or value.size() != 4:
		return Rect2()
	for coordinate: Variant in value:
		if not coordinate is int and not coordinate is float:
			return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
