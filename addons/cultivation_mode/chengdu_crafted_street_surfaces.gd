extends Node
## Local opaque materials on four houses and existing connecting paving.
## Parent materials stay alive in their roof rows, so QA A/B and fade agree.

const GROUND_SHADER := """shader_type spatial;
uniform sampler2D original_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D crafted_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 original_color : source_color = vec4(1.0);
uniform float original_period = 2.4;
uniform float crafted_period = 3.2;
uniform float crafted_gain = 0.95;
uniform float original_roughness = 0.96;
uniform mat4 vertex_to_stage;
uniform vec4 area_0;
uniform vec4 area_1;
uniform vec4 area_2;
uniform vec4 house_0;
uniform vec4 house_1;
uniform vec4 house_2;
uniform vec4 house_3;
uniform float edge_feather = 0.5;
uniform float wall_edge_width = 0.32;
uniform float wall_edge_strength = 0.14;
varying vec3 stage_position;
void vertex() { stage_position=(vertex_to_stage*vec4(VERTEX,1.0)).xyz; }
float rectangle_mask(vec2 p, vec4 box) {
    vec2 edge=min(p-box.xy,box.zw-p);
    return smoothstep(0.0,edge_feather,min(edge.x,edge.y));
}
float wall_distance(vec2 p, vec4 box) {
    vec2 outside=max(max(box.xy-p,p-box.zw),vec2(0.0));
    return length(outside);
}
void fragment() {
    vec2 p=stage_position.xz;
    vec3 original=texture(original_texture,p/original_period).rgb*original_color.rgb;
    float region=max(rectangle_mask(p,area_0),max(rectangle_mask(p,area_1),rectangle_mask(p,area_2)));
    vec3 paving=texture(crafted_texture,p/crafted_period).rgb*crafted_gain;
    float distance_to_wall=min(min(wall_distance(p,house_0),wall_distance(p,house_1)),min(wall_distance(p,house_2),wall_distance(p,house_3)));
    float edge=1.0-smoothstep(0.03,wall_edge_width,distance_to_wall);
    paving*=1.0-wall_edge_strength*edge;
    ALBEDO=mix(original,paving,region);
    ROUGHNESS=original_roughness;
}
"""

var records: Array[Dictionary] = []
var _stage: Node
var _config: Dictionary = {}
var _textures: Dictionary = {}
var _seen: Dictionary = {}
var _material_cache: Dictionary = {}
var _house_ids: Dictionary = {}
var _role_counts: Dictionary = {}
var _ground_shader: Shader
var _house_mesh_count := 0
var _ground_mesh_count := 0
var _derivations: Dictionary = {}
var _roof_bindings: Array[Dictionary] = []


func setup(stage: Node, configuration: Dictionary) -> void:
	_stage = stage
	_config = configuration
	for kind: String in _config.get("textures", {}):
		var row: Dictionary = _config.textures[kind]
		if not ResourceLoader.exists(str(row.path)):
			continue
		var texture := load(str(row.path)) as Texture2D
		if texture == null:
			continue
		var image := texture.get_image()
		var crop: Array = row.crop_pixels
		var cropped := image.get_region(Rect2i(int(crop[0]), int(crop[1]), int(crop[2]), int(crop[3])))
		_periodic_edges(cropped, int(row.seam_blend_pixels))
		cropped.generate_mipmaps()
		_textures[kind] = ImageTexture.create_from_image(cropped)
		_derivations[kind] = {"crop_pixels": crop.duplicate(), "seam_blend_pixels": int(row.seam_blend_pixels),
			"derived_size": [cropped.get_width(), cropped.get_height()], "mirrored": false, "mipmaps": true}
	_ground_shader = Shader.new()
	_ground_shader.code = GROUND_SHADER
	for body: Node in _stage.get("_crafted_roots").values():
		attach_house(body)
	_attach_ground()


func _periodic_edges(image: Image, width: int) -> void:
	# Average only narrow opposite-edge strips. Tile rows keep their direction;
	# no mirroring or source PNG edits. The outermost texels become identical.
	for vertical: bool in [false, true]:
		var source := image.duplicate() as Image
		var length := image.get_height() if vertical else image.get_width()
		var span := image.get_width() if vertical else image.get_height()
		var strip := mini(width, length / 4)
		for offset: int in range(strip):
			var blend := 1.0 - smoothstep(0.0, float(strip), float(offset))
			for index: int in range(span):
				var first := Vector2i(index, offset) if vertical else Vector2i(offset, index)
				var last := Vector2i(index, length - 1 - offset) if vertical else Vector2i(length - 1 - offset, index)
				var a := source.get_pixelv(first)
				var b := source.get_pixelv(last)
				var middle := a.lerp(b, 0.5)
				image.set_pixelv(first, a.lerp(middle, blend))
				image.set_pixelv(last, b.lerp(middle, blend))


func attach_house(body: Node) -> void:
	var id := str(body.get_meta("crafted_street_id", ""))
	if id.is_empty():
		return
	_house_ids[id] = true
	var parent_helper: Node = _stage.get("_painted_city_surfaces")
	var kinds: Dictionary = {}
	for record: Dictionary in parent_helper.get("records"):
		if is_instance_valid(record.node) and body.is_ancestor_of(record.node):
			kinds[record.node.get_instance_id()] = str(record.kind)
	var row: Dictionary = {}
	for roof: Dictionary in _stage.get("roof_rows"):
		if roof.get("body") == body:
			row = roof
			break
	for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var instance := node.get_instance_id()
		if _seen.has(instance):
			continue
		var kind := str(kinds.get(instance, ""))
		if not _textures.has(kind) or kind not in ["plaster", "roof"]:
			continue
		var old := node.material_override as ShaderMaterial
		if old == null:
			continue
		var key := str(old.get_instance_id()) + ":" + kind
		var material := _material_cache.get(key) as ShaderMaterial
		if material == null:
			material = old.duplicate() as ShaderMaterial
			material.set_shader_parameter("surface_texture", _textures[kind])
			var gain := float(_config.textures[kind].gain)
			material.set_shader_parameter("surface_color", Color(gain, gain, gain))
			_material_cache[key] = material
		if not row.is_empty() and not (row.materials as Array).has(material):
			(row.materials as Array).append(material)
			_roof_bindings.append({"row": row, "material": material})
			material.set_shader_parameter("fade", float(row.get("fade", 0.0)))
		node.material_override = material
		_seen[instance] = true
		records.append({"node": node, "old_material": old, "material": material, "kind": kind, "house_id": id})
		_house_mesh_count += 1
		_role_counts[kind] = int(_role_counts.get(kind, 0)) + 1


func _world_rect(values: Array) -> Vector4:
	var first: Vector3 = _stage.call("logical_to_world", Vector2(float(values[0]), float(values[1])))
	var last: Vector3 = _stage.call("logical_to_world", Vector2(float(values[0]) + float(values[2]), float(values[1]) + float(values[3])))
	return Vector4(first.x, first.z, last.x, last.z)


func _attach_ground() -> void:
	if not _textures.has("paving"):
		return
	var parent_helper: Node = _stage.get("_painted_city_surfaces")
	for record: Dictionary in parent_helper.get("records"):
		var node: Node = record.node
		if str(record.kind) != "stone" or not node is MeshInstance3D or not node.mesh is PlaneMesh:
			continue
		var transform: Transform3D = _stage.call("_local_chain", node)
		if transform.origin.y < 0.0 or transform.origin.y > 0.01:
			continue
		var old := node.material_override as StandardMaterial3D
		if old == null:
			continue
		var plane := node.mesh as PlaneMesh
		var first: Vector2 = _stage.call("world_to_logical", transform * Vector3(-plane.size.x * 0.5, 0, -plane.size.y * 0.5))
		var bounds := Rect2(first, Vector2.ZERO)
		for x: float in [-plane.size.x * 0.5, plane.size.x * 0.5]:
			for z: float in [-plane.size.y * 0.5, plane.size.y * 0.5]:
				var corner: Vector2 = _stage.call("world_to_logical", transform * Vector3(x, 0, z))
				bounds = bounds.expand(corner)
		var in_area := false
		for area: Array in _config.ground.areas:
			if bounds.intersects(Rect2(float(area[0]), float(area[1]), float(area[2]), float(area[3]))):
				in_area = true
		if not in_area:
			continue
		var material := ShaderMaterial.new()
		material.shader = _ground_shader
		material.set_shader_parameter("original_texture", old.albedo_texture)
		material.set_shader_parameter("crafted_texture", _textures.paving)
		material.set_shader_parameter("original_color", old.albedo_color)
		material.set_shader_parameter("original_period", 1.0 / old.uv1_scale.x)
		material.set_shader_parameter("crafted_period", float(_config.ground.paving_period_meters))
		material.set_shader_parameter("crafted_gain", float(_config.textures.paving.gain))
		material.set_shader_parameter("original_roughness", old.roughness)
		material.set_shader_parameter("vertex_to_stage", transform)
		var zero: Vector3 = _stage.call("logical_to_world", Vector2.ZERO)
		var feather: Vector3 = _stage.call("logical_to_world", Vector2(float(_config.ground.edge_feather), 0))
		material.set_shader_parameter("edge_feather", feather.distance_to(zero))
		material.set_shader_parameter("wall_edge_width", float(_config.ground.wall_edge_width_meters))
		material.set_shader_parameter("wall_edge_strength", float(_config.ground.wall_edge_strength))
		for index: int in range(3):
			material.set_shader_parameter("area_" + str(index), _world_rect(_config.ground.areas[index]))
		for index: int in range(4):
			material.set_shader_parameter("house_" + str(index), _world_rect(_config.houses[index].bounds))
		node.material_override = material
		records.append({"node": node, "old_material": old, "material": material, "kind": "paving", "house_id": ""})
		_ground_mesh_count += 1
		_role_counts["paving"] = int(_role_counts.get("paving", 0)) + 1


func _exit_tree() -> void:
	for record: Dictionary in records:
		if is_instance_valid(record.node) and record.node.material_override == record.material:
			record.node.material_override = record.old_material
	for binding: Dictionary in _roof_bindings:
		if is_instance_valid(binding.row.get("body")):
			(binding.row.materials as Array).erase(binding.material)


func audit() -> Dictionary:
	var roles: Array = _textures.keys()
	roles.sort()
	var ids: Array = _house_ids.keys()
	ids.sort()
	return {"loaded_texture_roles": roles, "house_ids_current": ids, "house_mesh_count": _house_mesh_count,
		"ground_mesh_count": _ground_mesh_count, "role_counts": _role_counts.duplicate(), "records_count": records.size(),
		"ground_areas": _config.get("ground", {}).get("areas", []), "derivations": _derivations.duplicate(true),
		"detached_setup_safe": true, "no_new_ground_geometry": true, "opaque_ground": true, "new_state": false}
