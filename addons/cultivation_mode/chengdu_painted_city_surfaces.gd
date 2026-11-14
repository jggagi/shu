extends Node
## Six isolated painted cells replace the old environment surface resources.
## Each original Material keeps an independent replacement; roof fade never
## leaks from one building into another. No geometry or gameplay is authored.

const CONFIG := "res://assets/data/chengdu-painted-city-layout.json"
const UV_DECLARATIONS := """
uniform bool painted_world_mapping = false;
uniform float painted_world_meters = 2.4;
varying vec3 painted_world_position;
varying vec3 painted_world_normal;
void vertex() {
    painted_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    painted_world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec2 painted_surface_uv(vec2 local_uv) {
    if (!painted_world_mapping) { return local_uv; }
    vec3 normal=abs(painted_world_normal);
    vec2 coordinates=painted_world_position.xz;
    if (normal.x>normal.y && normal.x>normal.z) { coordinates=painted_world_position.zy; }
    else if (normal.z>normal.y) { coordinates=painted_world_position.xy; }
    return coordinates/painted_world_meters;
}
"""

# QA can toggle only these overrides for a fair old/new material comparison.
var records: Array[Dictionary] = []
var _stage: Node
var _config: Dictionary = {}
var _atlas: Texture2D
var _tiles: Dictionary = {}
var _original_textures: Dictionary = {}
var _materials: Dictionary = {}
var _seen: Dictionary = {}
var _role_counts: Dictionary = {}
var _preserved_counts: Dictionary = {}
var _roof_by_body: Dictionary = {}
var _roof_originals: Dictionary = {}
var _indexed_roofs := 0
var _shader: Shader
var _house_roots: Dictionary = {}
var _enabled := false


func setup(stage: Node) -> void:
	_stage=stage
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not data is Dictionary:
		return
	_config=data
	if not ResourceLoader.exists(str(_config.atlas)):
		return
	_atlas=load(str(_config.atlas)) as Texture2D
	if _atlas==null:
		return
	var image := _atlas.get_image()
	var columns := int(_config.columns)
	var rows := int(_config.rows)
	for kind: String in _config.tiles:
		var cell: Array = _config.tiles[kind]
		var from := Vector2i(int(cell[0])*image.get_width()/columns,int(cell[1])*image.get_height()/rows)
		var to := Vector2i((int(cell[0])+1)*image.get_width()/columns,(int(cell[1])+1)*image.get_height()/rows)
		# Isolating before mip generation prevents neighbouring atlas colours
		# from bleeding into roof, wall or water at smaller display sizes.
		var tile := image.get_region(Rect2i(from,to-from))
		if kind in _config.get("mirrored_repeat",[]):
			tile=_mirrored_tile(tile)
		tile.generate_mipmaps()
		_tiles[kind]=ImageTexture.create_from_image(tile)
	for kind: String in ["roof","stone","plaster","wood"]:
		_original_textures[(_stage.call("_surface_texture",kind) as Texture2D).get_instance_id()]=kind
	_shader=Shader.new()
	var original: Shader = _stage.get("_roof_shader")
	_shader.code=original.code.replace("void fragment() {",UV_DECLARATIONS+"\nvoid fragment() {").replace("texture(surface_texture, UV * repeat_uv)","texture(surface_texture, painted_surface_uv(UV * repeat_uv))")
	_enabled=true
	attach_tree(_stage.world_root)


func _mirrored_tile(tile: Image) -> Image:
	# Four mirrored quadrants meet on identical edge texels. This removes the
	# generated water cell's repeat seam without editing the authored atlas.
	var size := tile.get_size()
	var result := Image.create(size.x*2,size.y*2,false,tile.get_format())
	for y: int in range(2):
		for x: int in range(2):
			var quadrant := tile.duplicate() as Image
			if x==1:
				quadrant.flip_x()
			if y==1:
				quadrant.flip_y()
			result.blit_rect(quadrant,Rect2i(Vector2i.ZERO,size),Vector2i(x,y)*size)
	return result


func attach_tree(root_node: Node) -> void:
	if not _enabled:
		return
	_index_roofs()
	if root_node is GeometryInstance3D:
		_attach(root_node as GeometryInstance3D)
	for node: Node in root_node.find_children("*","GeometryInstance3D",true,false):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			_attach(node as GeometryInstance3D)


func _index_roofs() -> void:
	var rows: Array = _stage.get("roof_rows")
	while _indexed_roofs<rows.size():
		var row: Dictionary = rows[_indexed_roofs]
		var body: Node = row.get("body")
		if is_instance_valid(body):
			_roof_by_body[body.get_instance_id()]=row
		_indexed_roofs+=1


func _attach(node: GeometryInstance3D) -> void:
	if _seen.has(node.get_instance_id()):
		return
	_seen[node.get_instance_id()]=true
	var excluded := _preserve_reason(node)
	if not excluded.is_empty():
		_preserved_counts[excluded]=int(_preserved_counts.get(excluded,0))+1
		return
	var old := node.material_override
	if old==null or (not old is StandardMaterial3D and not old is ShaderMaterial):
		return
	var kind := _kind(node,old)
	var key := str(old.get_instance_id())+":"+kind
	var material: Material = _materials.get(key)
	if material==null:
		material=_replace_material(old,kind)
		if material==null:
			return
		_materials[key]=material
	node.material_override=material
	var row := _roof_row(node)
	if material is ShaderMaterial and not row.is_empty():
		_bind_roof(row,old,material as ShaderMaterial)
	records.append({"node":node,"old_material":old,"material":material,"kind":kind,"roof_row":row})
	_role_counts[kind]=int(_role_counts.get(kind,0))+1
	var parent: Node = node
	while parent!=null and parent!=_stage.world_root:
		if bool(parent.get_meta("painted_city_house",false)):
			_house_roots[parent.get_instance_id()]=true
		parent=parent.get_parent()


func _preserve_reason(node: Node) -> String:
	var ancestor := node
	while ancestor!=null and ancestor!=_stage.world_root:
		if bool(ancestor.get_meta("painted_city_preserve",false)):
			return "authored_tree"
		ancestor=ancestor.get_parent()
	for actor: Node in _stage.get("_volume_actors").values():
		if actor==node or actor.is_ancestor_of(node):
			return "real_actor_and_contacts"
	for contact: Node in _stage.get("shadow_nodes").values():
		if node==contact:
			return "legacy_actor_contact"
	for property: String in ["_river_umbrella","_returned_umbrella"]:
		var prop: Node = _stage.get(property)
		if is_instance_valid(prop) and (prop==node or prop.is_ancestor_of(node)):
			return "task_umbrella"
	for glint: Node in _stage.get("_large_water_glints"):
		if glint==node:
			return "existing_water_glint"
	if node is MeshInstance3D and node.mesh is SphereMesh:
		return "authored_foliage"
	return ""


func _kind(node: GeometryInstance3D, material: Material) -> String:
	var texture: Texture2D
	if material is ShaderMaterial:
		texture=(material as ShaderMaterial).get_shader_parameter("surface_texture")
	else:
		texture=(material as StandardMaterial3D).albedo_texture
	if texture!=null and _original_textures.has(texture.get_instance_id()):
		return str(_original_textures[texture.get_instance_id()])
	if node is MeshInstance3D and node.mesh is PlaneMesh:
		var transform := _relative_transform(node)
		var plane := node.mesh as PlaneMesh
		if absf(transform.origin.y+0.08)<0.002:
			var point: Vector2 = _stage.call("world_to_logical",transform.origin)
			for water: Dictionary in _stage.get("_reference_water"):
				if (water.bounds as Rect2).has_point(point):
					return "water"
		if plane.size.x>0.18 and plane.size.y>0.18 and transform.origin.y<=0.004:
			return "earth"
	# Flat cloth, copper studs and window colours retain their original tint.
	return "accent"


func _replace_material(old: Material, kind: String) -> Material:
	var tile: Texture2D = _tiles["plaster" if kind=="accent" else kind]
	var mapped: bool = _config.world_tile_meters.has(kind)
	var gain := float(_config.get("surface_gain",{}).get(kind,1.0))
	var neutral := Color(gain,gain,gain,1)
	var period := float(_config.world_tile_meters.get(kind,1.0))*(2.0 if kind in _config.get("mirrored_repeat",[]) else 1.0)
	if old is ShaderMaterial:
		var original := old as ShaderMaterial
		var material := original.duplicate() as ShaderMaterial
		material.shader=_shader
		material.set_shader_parameter("surface_texture",tile)
		material.set_shader_parameter("surface_color",original.get_shader_parameter("surface_color") if kind=="accent" else neutral)
		material.set_shader_parameter("repeat_uv",original.get_shader_parameter("repeat_uv"))
		material.set_shader_parameter("fade",original.get_shader_parameter("fade"))
		material.set_shader_parameter("player_uv",original.get_shader_parameter("player_uv"))
		material.set_shader_parameter("painted_world_mapping",mapped)
		if mapped:
			material.set_shader_parameter("painted_world_meters",period)
		return material
	var original := old as StandardMaterial3D
	var material := original.duplicate() as StandardMaterial3D
	material.albedo_texture=tile
	material.albedo_color=original.albedo_color if kind=="accent" else Color(gain,gain,gain,original.albedo_color.a)
	if mapped:
		material.uv1_triplanar=true
		material.uv1_world_triplanar=true
		material.uv1_scale=Vector3.ONE/period
		material.uv1_offset=Vector3.ZERO
	return material


func _roof_row(node: Node) -> Dictionary:
	var ancestor := node
	while ancestor!=null and ancestor!=_stage.world_root:
		if _roof_by_body.has(ancestor.get_instance_id()):
			return _roof_by_body[ancestor.get_instance_id()]
		ancestor=ancestor.get_parent()
	return {}


func _bind_roof(row: Dictionary, old: Material, material: ShaderMaterial) -> void:
	var body: Node = row.body
	var id := body.get_instance_id()
	if not _roof_originals.has(id):
		_roof_originals[id]={"row":row,"materials":(row.materials as Array).duplicate()}
	var index: int = (row.materials as Array).find(old)
	if index>=0:
		row.materials[index]=material
	elif not (row.materials as Array).has(material):
		# The retained gate helper made separate fallback copies. Register their
		# replacements with the same roof group instead of creating a new clock.
		(row.materials as Array).append(material)
	material.set_shader_parameter("fade",float(row.get("fade",0.0)))


func _relative_transform(node: Node3D) -> Transform3D:
	# Real UI setup is detached; never query global_transform before tree entry.
	var chain: Array[Node3D] = []
	var ancestor: Node = node
	while ancestor!=_stage.world_root:
		if ancestor is Node3D:
			chain.append(ancestor as Node3D)
		ancestor=ancestor.get_parent()
	var result := Transform3D.IDENTITY
	for index: int in range(chain.size()-1,-1,-1):
		result=result*chain[index].transform
	return result


func _exit_tree() -> void:
	for record: Dictionary in records:
		if is_instance_valid(record.node) and record.node.material_override==record.material:
			record.node.material_override=record.old_material
	for original: Dictionary in _roof_originals.values():
		if is_instance_valid(original.row.get("body")):
			original.row.materials=original.materials


func audit() -> Dictionary:
	return {"enabled":_enabled,"atlas_loaded":_atlas!=null,"atlas":_config.get("atlas",""),"tile_count":_tiles.size(),
		"mesh_count":records.size(),"house_roots_current":_house_roots.size(),"role_counts":_role_counts.duplicate(),
		"preserved_counts":_preserved_counts.duplicate(),"replacement_material_count":_materials.size(),
		"old_material_count":_materials.size(),"independent_roof_bindings":_roof_originals.size(),
		"world_mapping_roles":_config.get("world_tile_meters",{}).keys(),"isolated_tile_mipmaps":true,
		"surface_gain":_config.get("surface_gain",{}).duplicate(),"mirrored_repeat":_config.get("mirrored_repeat",[]).duplicate(),
		"detached_setup_safe":true,"gate_overlay_retained":true,"new_geometry":false,"new_actors":false,"new_state":false}
