extends Node
## Two offline-authored models. The old lot/body/fade/navigation remain the host.

const LAYOUT := "res://assets/data/chengdu-blender-kit-layout.json"
const SURFACE := """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float bake_strength = 0.65;
uniform float fade = 0.0;
uniform vec2 player_uv = vec2(0.5);
void fragment() {
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(44.0,92.0,length(delta));
    float pattern=fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern<local*fade*0.88) { discard; }
    ALBEDO=texture(painted_atlas,UV).rgb*mix(vec3(1.0),COLOR.rgb,bake_strength);
    ROUGHNESS=0.98;
    SPECULAR=0.0;
}
"""

var _stage: Node
var _data: Dictionary = {}
var _seen: Dictionary = {}
var _roots: Array[Node3D] = []
var _hidden: Array[Dictionary] = []
var _bindings: Array[Dictionary] = []
var _models: Array[Dictionary] = []
var _errors: Array[String] = []
var _bounds_errors: Array[Dictionary] = []
var _atlas: Texture2D
var _shader: Shader
var _enabled := true
var _retained_vertices := 0
var _removed_tree_vertices := 0


func setup(stage: Node) -> void:
	_stage=stage
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not data is Dictionary:
		_errors.append("Blender kit layout missing")
		return
	_data=data
	_atlas=load(str(_data.atlas)) as Texture2D
	if _atlas==null:
		_errors.append("Krita atlas unavailable")
		return
	_shader=Shader.new()
	_shader.code=SURFACE
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func attach_house(body: Node) -> void:
	if _shader==null or _seen.has(body.get_instance_id()):
		return
	var id:=str(body.get_meta("art_street_id",""))
	if not _data.get("models",{}).has(id):
		return
	var item: Dictionary=_data.models[id]
	var front:=body.get_node_or_null("StreetFacingStructure") as Node3D
	var packed:=load(str(item.scene)) as PackedScene
	if front==null or packed==null:
		_errors.append(id+": model or original local frame unavailable")
		return
	var row: Dictionary={}
	for entry: Dictionary in _stage.get("roof_rows"):
		if entry.get("body")==body:
			row=entry
			break
	if row.is_empty():
		_errors.append(id+": original fade row unavailable")
		return
	var root:=Node3D.new()
	root.name="BlenderAuthoredKit"
	_preserve(root)
	front.add_child(root)
	_roots.append(root)
	var instance:=packed.instantiate() as Node3D
	root.add_child(instance)
	var profile: Dictionary=_stage.get("_art_profiles")[id]
	var meshes:=instance.find_children("*","MeshInstance3D",true,false)
	if meshes.is_empty():
		_errors.append(id+": imported model has no visible meshes")
		root.queue_free()
		return
	var triangles:=0
	for node: MeshInstance3D in meshes:
		_preserve(node)
		node.material_overlay=null
		var material:=ShaderMaterial.new()
		material.shader=_shader
		material.set_shader_parameter("painted_atlas",_atlas)
		material.set_shader_parameter("bake_strength",float(_data.get("bake_strength",0.65)))
		material.set_shader_parameter("fade",float(row.fade))
		var point: Vector2=_stage.call("logical_to_screen",_stage.get("_player"),0.95)
		material.set_shader_parameter("player_uv",point/Vector2(1280,720))
		node.material_override=material
		# Keep the previous crown policy: foliage stays whole while roofs fade.
		if "leaf" not in str(node.name).to_lower():
			(row.materials as Array).append(material)
			_bindings.append({"row":row,"material":material})
		for surface: int in range(node.mesh.get_surface_count()):
			var arrays:=node.mesh.surface_get_arrays(surface)
			var indices:=PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices=arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			triangles+=(indices.size() if not indices.is_empty() else vertices.size())/3
		_check_bounds(node,front,id,profile.bounds,float(item.maximum_height))
	if str(item.kind)=="tea_shop":
		for node: Node in front.get_children():
			if str(node.name).begins_with("ArtSurface_") or str(node.name)=="ConceptFinish":
				_hide(node)
	else:
		if not _retain_courtyard_structure(front,root):
			_errors.append(id+": courtyard tree batch contract differs; refusing replacement")
			root.queue_free()
			return
		var old:=front.get_node_or_null("TeaPolish/TeaNaturalCrown")
		if old==null:
			_errors.append(id+": old illustrated crown missing")
		else:
			_hide(old)
	_seen[body.get_instance_id()]=true
	_models.append({"house_id":id,"kind":item.kind,"mesh_count":meshes.size(),"triangles":triangles,"scene":item.scene})
	root.visible=_enabled


func _preserve(node: Node) -> void:
	node.set_meta("art_street_preserve",true)
	node.set_meta("painted_city_preserve",true)
	node.set_meta("blender_kit",true)


func _hide(node: Node) -> void:
	_hidden.append({"node":node,"visible":node.visible})
	if _enabled:
		node.visible=false


func _chain(node: Node3D,ancestor: Node3D) -> Transform3D:
	var result:=Transform3D.IDENTITY
	var cursor: Node=node
	while cursor!=ancestor and cursor!=null:
		if cursor is Node3D:
			result=(cursor as Node3D).transform*result
		cursor=cursor.get_parent()
	return result


func _check_bounds(node: MeshInstance3D,front: Node3D,id: String,bounds: Array,maximum: float) -> void:
	var transform:=_chain(node,front)
	var half_x:=float(bounds[3])/160.0
	var half_z:=float(bounds[2])/160.0
	var outside:=0
	for surface: int in range(node.mesh.get_surface_count()):
		for vertex: Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var p:=transform*vertex
			if absf(p.x)>half_x+.001 or absf(p.z)>half_z+.001 or p.y<-.001 or p.y>maximum+.001:
				outside+=1
	if outside>0:
		_bounds_errors.append({"house_id":id,"mesh":str(node.name),"outside_vertices":outside})


func _expanded(mesh: Mesh,transform: Transform3D) -> PackedVector3Array:
	var arrays:=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices:=PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices=arrays[Mesh.ARRAY_INDEX]
	var result:=PackedVector3Array()
	for i: int in range(indices.size() if not indices.is_empty() else vertices.size()):
		result.append(transform*vertices[indices[i] if not indices.is_empty() else i])
	return result


func _retain_courtyard_structure(front: Node3D,root: Node3D) -> bool:
	# The frozen original batch appends one trunk and three branches last.
	# Match those exact vertices before retaining its earlier roof/door prefix.
	var old:=front.get_node_or_null("ArtSurface_wood") as MeshInstance3D
	if old==null or old.mesh.get_surface_count()!=1:
		return false
	var expected:=PackedVector3Array()
	var trunk:=CylinderMesh.new()
	trunk.bottom_radius=.075
	trunk.top_radius=.075*.65
	trunk.height=2.65
	trunk.radial_segments=12
	expected.append_array(_expanded(trunk,Transform3D(Basis.IDENTITY,Vector3(0,1.44,.15))))
	var first:=Vector3(0,1.90,.15)
	for tip: Vector3 in [Vector3(-.40,3.12,.12),Vector3(.35,3.13,.40),Vector3(0,3.23,-.10)]:
		var beam:=BoxMesh.new()
		beam.size=Vector3(.055,first.distance_to(tip),.055)
		var basis:=Basis(Quaternion(Vector3.UP,(tip-first).normalized()))
		expected.append_array(_expanded(beam,Transform3D(basis,(first+tip)*.5)))
	var arrays:=old.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var count:=vertices.size()-expected.size()
	if count<=0 or (arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty()):
		return false
	for i: int in range(expected.size()):
		if not vertices[count+i].is_equal_approx(expected[i]):
			return false
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var kept:=SurfaceTool.new()
	kept.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(count):
		kept.set_normal(normals[i])
		kept.set_uv(uvs[i])
		kept.add_vertex(vertices[i])
	var retained:=MeshInstance3D.new()
	retained.name="RetainedCourtyardDoorAndBeams"
	retained.mesh=kept.commit()
	retained.material_override=old.material_override
	retained.transform=old.transform
	_preserve(retained)
	root.add_child(retained)
	_retained_vertices=count
	_removed_tree_vertices=expected.size()
	_hide(old)
	return true


func set_models_enabled(enabled: bool) -> void:
	_enabled=enabled
	for root: Node3D in _roots:
		if is_instance_valid(root):
			root.visible=enabled
	for row: Dictionary in _hidden:
		if is_instance_valid(row.node):
			row.node.visible=false if enabled else row.visible


func audit() -> Dictionary:
	return {"layout":LAYOUT,"models":_models.duplicate(true),"errors":_errors.duplicate(),"bounds_errors":_bounds_errors.duplicate(true),
		"retained_courtyard_vertices":_retained_vertices,"replaced_tree_vertices":_removed_tree_vertices,"hidden_original_nodes":_hidden.size(),
		"fade_materials":_bindings.size(),"original_navigation_unchanged":true,"original_mesh_resources_unchanged":true,"new_ground":false,
		"authored_in":"Blender","texture_composited_in":"Krita","enabled":_enabled}


func _exit_tree() -> void:
	for row: Dictionary in _hidden:
		if is_instance_valid(row.node):
			row.node.visible=row.visible
	for binding: Dictionary in _bindings:
		(binding.row.materials as Array).erase(binding.material)
	for root: Node3D in _roots:
		if is_instance_valid(root):
			root.queue_free()
