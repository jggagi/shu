extends SceneTree
# Keep production resource-closure scanners from treating the authoring addon as
# a runtime dependency. The plugin exists only in the isolated authoring project.
const AUTHORING_ROOT := "res://" + "addons/proton_scatter/"
var Scatter: Script
var Shape: Script
var PathShape: Script
var BoxShape: Script
var Stack: Script
var CreateRandom: Script
var EditScale: Script
var RandomTransforms: Script
const SEED_VALUE = 20261024

func _initialize() -> void:
	if not bool(ProjectSettings.get_setting("songfeng_authoring/only", false)) or not FileAccess.file_exists(AUTHORING_ROOT + "src/scatter.gd"):
		printerr("ProtonScatter bake requires the isolated authoring project metadata and its local addon. Run bake_ambush_scatter.py; no production data was written.")
		quit(1)
		return
	Scatter = load(AUTHORING_ROOT + "src/scatter.gd")
	Shape = load(AUTHORING_ROOT + "src/scatter_shape.gd")
	PathShape = load(AUTHORING_ROOT + "src/shapes/path_shape.gd")
	BoxShape = load(AUTHORING_ROOT + "src/shapes/box_shape.gd")
	Stack = load(AUTHORING_ROOT + "src/stack/modifier_stack.gd")
	CreateRandom = load(AUTHORING_ROOT + "src/modifiers/create_inside_random.gd")
	EditScale = load(AUTHORING_ROOT + "src/modifiers/offset_scale.gd")
	RandomTransforms = load(AUTHORING_ROOT + "src/modifiers/randomize_transforms.gd")
	call_deferred("_run")

func _path(side: float):
	var node = Shape.new()
	var shape = PathShape.new()
	shape.closed = false
	shape.thickness = 1.4
	var curve = Curve3D.new()
	for point: Vector3 in [Vector3(side * 6.6, 0, -6.2), Vector3(side * 7.3, 0, -3.5), Vector3(side * 6.7, 0, 0.3), Vector3(side * 7.0, 0, 4.7)]:
		curve.add_point(point)
	shape.curve = curve
	node.shape = shape
	return node

func _generate(kind: String, amount: int, seed_offset: int, minimum_scale: float, maximum_scale: float) -> Array:
	var scatter = Scatter.new()
	scatter.name = "Roadside_" + kind
	scatter.enabled = false # Bake transforms only; never render ScatterItems.
	scatter.force_rebuild_on_load = false
	scatter.global_seed = SEED_VALUE + seed_offset
	scatter.add_child(_path(-1.0))
	scatter.add_child(_path(1.0))
	var exclusion = Shape.new()
	exclusion.name = "BattleBoardExclusion"
	exclusion.negative = true
	var box = BoxShape.new()
	box.size = Vector3(11.2, 2.0, 8.8)
	exclusion.shape = box
	scatter.add_child(exclusion)
	root.add_child(scatter)
	scatter.domain.discover_shapes(scatter)
	assert(scatter.domain.positive_shapes.size() == 2)
	assert(scatter.domain.negative_shapes.size() == 1)
	assert(scatter.domain.is_point_excluded(Vector3.ZERO))
	assert(not scatter.domain.is_point_inside(Vector3.ZERO))
	# Exercise exclusion precedence on a point genuinely inside the positive path.
	var domain_probe = Vector3(6.7, 0, 0.3)
	assert(scatter.domain.is_point_inside(domain_probe))
	exclusion.position = domain_probe
	assert(scatter.domain.is_point_excluded(domain_probe))
	assert(not scatter.domain.is_point_inside(domain_probe))
	exclusion.position = Vector3.ZERO
	assert(scatter.domain.is_point_inside(domain_probe))
	# This is the original plugin's public modifier pipeline, not a replacement RNG.
	# A local stack avoids connecting the renderer, which requires ScatterItems.
	var stack = Stack.new()
	var create = CreateRandom.new()
	create.amount = amount
	create.restrict_height = true
	stack.add(create)
	var edit_scale = EditScale.new()
	edit_scale.scale = Vector3.ONE * minimum_scale
	stack.add(edit_scale)
	var random = RandomTransforms.new()
	random.rotation = Vector3(0, 180, 0)
	random.scale = Vector3.ONE * (maximum_scale / minimum_scale - 1.0)
	stack.add(random)
	var transforms = await stack.start_update(scatter, scatter.domain)
	assert(transforms.size() == amount)
	var result: Array = []
	for transform: Transform3D in transforms.list:
		var at = transform.origin
		assert(scatter.domain.is_point_inside(at))
		assert(not (absf(at.x) < 5.6 and absf(at.z) < 4.4))
		var scale_vector = transform.basis.get_scale()
		assert(absf(scale_vector.x - scale_vector.y) < 0.00001)
		assert(absf(scale_vector.x - scale_vector.z) < 0.00001)
		result.append({"at": [at.x, at.y, at.z], "yaw": transform.basis.orthonormalized().get_euler().y, "scale": scale_vector.x, "kind": kind})
	scatter.queue_free()
	await process_frame
	return result

func _run() -> void:
	var output = OS.get_cmdline_user_args()[0]
	var instances: Array = await _generate("grass", 36, 0, 0.25, 0.45)
	instances.append_array(await _generate("rock", 16, 997, 0.15, 0.35))
	var file = FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema": 1, "seed": SEED_VALUE, "instances": instances}, "\t") + "\n")
	file.close()
	print("PROTON_SCATTER_BAKE ", instances.size(), " instances using original Path/Box domain + modifier stack")
	quit(0)
