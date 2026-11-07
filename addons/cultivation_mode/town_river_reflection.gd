extends Node
## One low-resolution real planar view of the existing town World3D.
## The host calls sync_camera() after presentation changes; UPDATE_ALWAYS also
## renders lighting changes while Static. No clock, game state or duplicate world.
## Water and selected underwater bank bodies use a reserved exclusion layer.
## This does not provide an oblique clip plane: exclude below-water occluders
## deliberately, leaving above-water caps, trees, buildings and boats visible.
## Verified Compatibility sampling: clip = reflection_view_projection * world;
## uv = clip.xy / clip.w * 0.5 + 0.5; uv.y = 1.0 - uv.y before texture().

const DEFAULT_SIZE: Vector2i = Vector2i(512, 288)
const DEFAULT_EXCLUSION_LAYER: int = 20

var reflection_viewport: SubViewport
var reflection_camera: Camera3D
var reflection_texture: ViewportTexture
var _source_viewport: SubViewport
var _source_camera: Camera3D
var _plane_y: float = -0.28
var _excluded_bit: int = 1 << (DEFAULT_EXCLUSION_LAYER - 1)
var _excluded_geometry: Array[Dictionary] = []


func setup(source_viewport: SubViewport, source_camera: Camera3D, plane_y: float = -0.28,
		resolution: Vector2i = DEFAULT_SIZE, exclusion_layer: int = DEFAULT_EXCLUSION_LAYER) -> bool:
	if not is_inside_tree() or not is_instance_valid(source_viewport) or not is_instance_valid(source_camera):
		return false
	if is_instance_valid(reflection_viewport) or exclusion_layer < 1 or exclusion_layer > 20:
		return false
	if resolution.x < 2 or resolution.y < 2:
		return false
	var world: World3D = source_viewport.find_world_3d()
	if world == null:
		return false
	_source_viewport = source_viewport
	_source_camera = source_camera
	_plane_y = plane_y
	_excluded_bit = 1 << (exclusion_layer - 1)
	# The main view must still display the reserved water layer. Do not silently
	# change its cull mask or attach the reflected camera to its viewport.
	if (_source_camera.cull_mask & _excluded_bit) == 0:
		return false
	reflection_viewport = SubViewport.new()
	reflection_viewport.name = "RiverReflectionViewport"
	reflection_viewport.size = resolution
	reflection_viewport.own_world_3d = false
	reflection_viewport.world_3d = world
	reflection_viewport.gui_disable_input = true
	reflection_viewport.audio_listener_enable_2d = false
	reflection_viewport.audio_listener_enable_3d = false
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	reflection_viewport.msaa_3d = Viewport.MSAA_DISABLED
	reflection_viewport.positional_shadow_atlas_size = 512
	add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.name = "RiverMirrorCamera"
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.current = true
	reflection_texture = reflection_viewport.get_texture()
	sync_camera()
	return true


func exclude_geometry(geometry: GeometryInstance3D) -> bool:
	if not is_instance_valid(geometry) or not is_instance_valid(reflection_camera):
		return false
	for row: Dictionary in _excluded_geometry:
		if row.node == geometry:
			return true
	_excluded_geometry.append({"node": geometry, "original_layers": geometry.layers})
	# Keeping an old visible layer as well would allow recursive water rendering.
	geometry.layers = _excluded_bit
	return true


func sync_camera() -> void:
	if not is_instance_valid(reflection_camera) or not is_instance_valid(_source_camera):
		return
	# get_camera_transform already includes h/v offsets. Avoid applying them twice.
	var source: Transform3D = _source_camera.get_camera_transform()
	var basis: Basis = source.basis.orthonormalized()
	var right: Vector3 = Vector3(basis.x.x, -basis.x.y, basis.x.z)
	var up: Vector3 = -Vector3(basis.y.x, -basis.y.y, basis.y.z)
	var backward: Vector3 = Vector3(basis.z.x, -basis.z.y, basis.z.z)
	var at: Vector3 = source.origin
	at.y = 2.0 * _plane_y - at.y
	# Reflecting a basis reverses handedness. Negating its up axis restores a
	# valid camera basis and keeps left/right unchanged. Projective texture UVs
	# therefore use the reflected camera matrix, not a guessed flipped image.
	reflection_camera.global_transform = Transform3D(Basis(right, up, backward), at)
	reflection_camera.projection = _source_camera.projection
	reflection_camera.keep_aspect = _source_camera.keep_aspect
	reflection_camera.fov = _source_camera.fov
	reflection_camera.size = _source_camera.size
	reflection_camera.near = _source_camera.near
	reflection_camera.far = _source_camera.far
	reflection_camera.frustum_offset = Vector2(_source_camera.frustum_offset.x, -_source_camera.frustum_offset.y)
	reflection_camera.h_offset = 0.0
	reflection_camera.v_offset = 0.0
	reflection_camera.cull_mask = _source_camera.cull_mask & ~_excluded_bit
	reflection_camera.environment = _source_camera.environment
	reflection_camera.attributes = _source_camera.attributes


func get_reflection_view_projection() -> Projection:
	if not is_instance_valid(reflection_camera):
		return Projection()
	return reflection_camera.get_camera_projection() * Projection(reflection_camera.get_camera_transform().affine_inverse())


func bind_water_material(material: ShaderMaterial, texture_uniform: StringName = &"reflection_texture",
		matrix_uniform: StringName = &"reflection_view_projection") -> void:
	if material == null or not is_instance_valid(reflection_camera):
		return
	material.set_shader_parameter(texture_uniform, reflection_texture)
	material.set_shader_parameter(matrix_uniform, get_reflection_view_projection())


func audit() -> Dictionary:
	return {
		"ready": is_instance_valid(reflection_camera),
		"resolution": reflection_viewport.size if is_instance_valid(reflection_viewport) else Vector2i.ZERO,
		"shared_world": is_instance_valid(reflection_viewport) and is_instance_valid(_source_viewport)
			and reflection_viewport.find_world_3d() == _source_viewport.find_world_3d(),
		"update_mode": reflection_viewport.render_target_update_mode if is_instance_valid(reflection_viewport) else -1,
		"plane_y": _plane_y,
		"excluded_bit": _excluded_bit,
		"excluded_count": _excluded_geometry.size(),
		"camera_transform": reflection_camera.global_transform if is_instance_valid(reflection_camera) else Transform3D.IDENTITY,
		"clock": "none; host presentation phase remains authoritative"
	}


func _exit_tree() -> void:
	for row: Dictionary in _excluded_geometry:
		if not is_instance_valid(row.node):
			continue
		var geometry: GeometryInstance3D = row.node
		if geometry.layers == _excluded_bit:
			geometry.layers = int(row.original_layers)
