extends Node
## A second scene-specific use of the town's painted/depth method. Unlike the
## fixed tea street, reference projection is frozen in WORLD coordinates. Its
## texture stays on the original surfaces while the existing camera follows.

const CONFIG := "res://assets/data/chengdu-painted-gate-layout.json"
const DISPLAY := Vector2(1280,720)
const OVERLAY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;
uniform sampler2D painting : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_mask : filter_nearest, repeat_disable;
uniform mat4 reference_vp;
uniform vec3 reference_position;
uniform vec3 source_rgb;
uniform vec2 reference_size = vec2(1280.0,720.0);
uniform float blend_strength = 1.0;
uniform float frame_feather_pixels = 24.0;
uniform float source_border_pixels = 1.0;
uniform float normal_limit = 0.08;
uniform float fade = 0.0;
uniform vec2 player_uv = vec2(0.5);
varying vec3 original_world_position;
varying vec3 original_world_normal;
void vertex() {
    original_world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    original_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float matching_source(vec2 uv) {
    vec3 value = texture(source_mask,uv).rgb;
    return 1.0-step(0.5/255.0,max(max(abs(value.r-source_rgb.r),abs(value.g-source_rgb.g)),abs(value.b-source_rgb.b)));
}
void fragment() {
    vec4 clip = reference_vp * vec4(original_world_position,1.0);
    if (clip.w <= 0.0) { discard; }
    vec2 projected = vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
    if (any(lessThanEqual(projected,vec2(0.0))) || any(greaterThanEqual(projected,vec2(1.0)))) { discard; }
    vec3 toward_reference = normalize(reference_position-original_world_position);
    if (dot(normalize(original_world_normal),toward_reference) <= normal_limit) { discard; }
    float source_ok = matching_source(projected);
    vec2 border = vec2(source_border_pixels)/reference_size;
    source_ok *= matching_source(projected+vec2(border.x,0.0));
    source_ok *= matching_source(projected-vec2(border.x,0.0));
    source_ok *= matching_source(projected+vec2(0.0,border.y));
    source_ok *= matching_source(projected-vec2(0.0,border.y));
    if (source_ok < 0.5) { discard; }
    float edge_pixels = min(min(projected.x,1.0-projected.x)*reference_size.x,min(projected.y,1.0-projected.y)*reference_size.y);
    float frame_alpha = smoothstep(0.0,frame_feather_pixels,edge_pixels);
    vec2 delta = (SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local = 1.0-smoothstep(44.0,92.0,length(delta));
    float pattern = fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern < local*fade*0.88) { discard; }
    ALBEDO = texture(painting,projected).rgb;
    ALPHA = frame_alpha*blend_strength;
}
"""

var _stage: Node
var _config: Dictionary = {}
var _reference: Dictionary = {}
var _painting: Texture2D
var _mask: Texture2D
var _shader: Shader
var _fallback_shader: Shader
var _entries: Dictionary = {}
var _installed: Array[Dictionary] = []
var _fallbacks: Array[Dictionary] = []
var _fallback_groups: Dictionary = {}
var _seen: Dictionary = {}
var _mesh_hashes: Dictionary = {}
var _reference_vp: Projection
var _reference_position := Vector3.ZERO
var _scanned_sources := 0
var _painted_unique_ids: Dictionary = {}
var _ready_for_art := false


func setup(stage: Node) -> void:
	_stage=stage
	var configuration: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not configuration is Dictionary:
		return
	_config=configuration
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(_config.reference_camera)))
	if not data is Dictionary:
		return
	_reference=data
	if ResourceLoader.exists(str(_config.painting)):
		_painting=load(str(_config.painting)) as Texture2D
	if ResourceLoader.exists(str(_config.source_mask)):
		_mask=load(str(_config.source_mask)) as Texture2D
	if _painting==null or _mask==null:
		return
	var columns: Array = _reference.view_projection_columns
	_reference_vp=Projection(_v4(columns[0]),_v4(columns[1]),_v4(columns[2]),_v4(columns[3]))
	var at: Array = _reference.camera_position
	_reference_position=Vector3(float(at[0]),float(at[1]),float(at[2]))
	var visible: Dictionary = _reference.pixel_counts
	for source: Dictionary in _reference.sources:
		if visible.has(str(int(source.id))):
			_entries[str(source.signature)]=source
	_shader=Shader.new()
	_shader.code=OVERLAY_SHADER
	_ready_for_art=true
	attach_tree(_stage.world_root)
	sync()


func attach_tree(root_node: Node) -> void:
	if not _ready_for_art:
		return
	if root_node is GeometryInstance3D:
		_attach(root_node as GeometryInstance3D)
	for node: Node in root_node.find_children("*","GeometryInstance3D",true,false):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			_attach(node as GeometryInstance3D)


func _attach(node: GeometryInstance3D) -> void:
	if not node is MeshInstance3D and not node is MultiMeshInstance3D:
		return
	if _seen.has(node.get_instance_id()) or _is_actor_geometry(node):
		return
	_seen[node.get_instance_id()]=true
	_scanned_sources+=1
	_prepare_gate_fallback(node)
	var signature := _signature(node)
	if not _entries.has(signature):
		return
	var source: Dictionary = _entries[signature]
	var material := ShaderMaterial.new()
	material.shader=_shader
	# Painted transparency follows opaque world depth, then the existing sole
	# contacts draw at their default priority. This avoids painting over feet.
	material.render_priority=-1
	material.set_shader_parameter("painting",_painting)
	material.set_shader_parameter("source_mask",_mask)
	material.set_shader_parameter("reference_vp",_reference_vp)
	material.set_shader_parameter("reference_position",_reference_position)
	var rgb: Array = source.rgb
	material.set_shader_parameter("source_rgb",Vector3(float(rgb[0])/255.0,float(rgb[1])/255.0,float(rgb[2])/255.0))
	material.set_shader_parameter("blend_strength",float(_config.blend_strength))
	material.set_shader_parameter("frame_feather_pixels",float(_config.frame_feather_pixels))
	material.set_shader_parameter("source_border_pixels",float(_config.source_border_pixels))
	material.set_shader_parameter("normal_limit",float(_config.minimum_reference_normal_dot))
	var old_overlay := node.material_overlay
	node.material_overlay=material
	_installed.append({"node":node,"material":material,"old_overlay":old_overlay,"source_id":int(source.id),"roof_row":_roof_row(node)})
	_painted_unique_ids[int(source.id)]=true


func _is_actor_geometry(node: Node) -> bool:
	for actor: Node in _stage.get("_volume_actors").values():
		if actor==node or actor.is_ancestor_of(node):
			return true
	for actor: Node in _stage.get("actor_nodes").values():
		if actor==node or actor.is_ancestor_of(node):
			return true
	for contact: Node in _stage.get("shadow_nodes").values():
		if contact==node:
			return true
	return false


func _roof_row(node: Node) -> Dictionary:
	for row: Dictionary in _stage.get("roof_rows"):
		var body: Node = row.get("body")
		if body==node or (is_instance_valid(body) and body.is_ancestor_of(node)):
			return row
	return {}


func _prepare_gate_fallback(node: GeometryInstance3D) -> void:
	# The source image cannot supply surfaces it never saw. Only the newly
	# painted gate's own return walls and upper structure receive these copies
	# of existing textured materials; other city geometry remains untouched.
	var parent: Node = node.get_parent()
	var gate_part := false
	var group := ""
	while parent!=null and parent!=_stage.world_root:
		var label := str(parent.name)
		if label.begins_with("DetailedOpenSouthGate") or bool(parent.get_meta("painted_gate_return",false)):
			gate_part=true
			group="gate" if label.begins_with("DetailedOpenSouthGate") else ("return_west" if (parent as Node3D).position.x<_stage.logical_to_world(Vector2(7800,8400)).x else "return_east")
			break
		parent=parent.get_parent()
	if not gate_part:
		return
	var old_material := node.material_override as ShaderMaterial
	if old_material==null:
		return
	var texture: Texture2D = old_material.get_shader_parameter("surface_texture")
	var palette: Dictionary = _config.gate_fallback_palette
	var tint: Color
	var matched := false
	for kind: String in ["stone","wood","roof","plaster"]:
		if texture==_stage.call("_surface_texture",kind):
			tint=Color(str(palette[kind]))
			matched=true
			break
	if not matched:
		# Pure-colour stone joints are distinct from the intentionally warm
		# copper door studs. Keep brass untouched rather than flattening it.
		var previous: Color = old_material.get_shader_parameter("surface_color")
		if previous.g<=previous.r or previous.b>=previous.g:
			return
		tint=Color(str(palette.stone_joint))
	var material := old_material.duplicate() as ShaderMaterial
	if _fallback_shader==null:
		_fallback_shader=Shader.new()
		# Keep the existing lit/dithered material contract while removing the
		# old green pigment from these few surfaces outside the painted view.
		_fallback_shader.code=old_material.shader.code.replace("texture(surface_texture, UV * repeat_uv).rgb * surface_color.rgb","vec3(dot(texture(surface_texture, UV * repeat_uv).rgb,vec3(0.2126,0.7152,0.0722))) * surface_color.rgb")
	material.shader=_fallback_shader
	material.set_shader_parameter("surface_texture",texture)
	material.set_shader_parameter("repeat_uv",old_material.get_shader_parameter("repeat_uv"))
	material.set_shader_parameter("surface_color",tint)
	node.material_override=material
	_fallbacks.append({"node":node,"material":material,"old_material":old_material,"roof_row":_roof_row(node)})
	_fallback_groups[group]=int(_fallback_groups.get(group,0))+1


func sync() -> void:
	if not _ready_for_art:
		return
	var player: Vector2 = _stage.get("_player")
	var point: Vector2 = _stage.call("logical_to_screen",player,0.95)
	for record: Dictionary in _installed:
		if not is_instance_valid(record.node):
			continue
		var material: ShaderMaterial = record.material
		material.set_shader_parameter("fade",float((record.roof_row as Dictionary).get("fade",0.0)))
		material.set_shader_parameter("player_uv",point/DISPLAY)
	for record: Dictionary in _fallbacks:
		if is_instance_valid(record.node):
			record.material.set_shader_parameter("fade",float((record.roof_row as Dictionary).get("fade",0.0)))
			record.material.set_shader_parameter("player_uv",point/DISPLAY)
	# These are the existing two sole contacts, not new actor images or a new
	# lighting system. Keep them just above the highest old .012m street/deck
	# render plane; the skinned model's feet and authoritative position stay put.
	for actor: Node3D in _stage.get("_volume_actors").values():
		for contact: MeshInstance3D in actor.get("contacts"):
			contact.position.y=float(_config.sole_contact_height)-actor.position.y


func _exit_tree() -> void:
	for record: Dictionary in _installed:
		if is_instance_valid(record.node) and record.node.material_overlay==record.material:
			record.node.material_overlay=record.old_overlay
	for record: Dictionary in _fallbacks:
		if is_instance_valid(record.node) and record.node.material_override==record.material:
			record.node.material_override=record.old_material


func audit() -> Dictionary:
	return {"enabled":_ready_for_art,"has_art":_painting!=null,"has_mask":_mask!=null,
		"reference_anchor":_reference.get("player_anchor",[]),"reference_camera":_config.get("reference_camera",""),
		"painting":_config.get("painting",""),"source_mask":_config.get("source_mask",""),
		"overlay_source_count":_painted_unique_ids.size(),"material_count":_installed.size(),"scanned_geometry_count":_scanned_sources,
		"gate_fallback_material_count":_fallbacks.size(),"gate_fallback_groups":_fallback_groups.duplicate(),"fallback_scope":"Only DetailedOpenSouthGate and explicitly marked west/east gate returns; copies of existing textures, including previously unseen faces",
		"reference_visible_source_count":_entries.size(),"reference_screen_uv":false,"world_projective":true,
		"continuous_follow_unchanged":true,"original_geometry_depth":true,"source_id_masked":true,"reject_reference_backfaces":true,
		"sole_contact_height":_config.get("sole_contact_height",0.0),"new_obstacles":false,"new_actors":false,
		"art_size":_painting.get_size() if _painting!=null else Vector2.ZERO}


func _signature(node: GeometryInstance3D) -> String:
	var mesh: Mesh = node.mesh if node is MeshInstance3D else (node as MultiMeshInstance3D).multimesh.mesh
	# Real views construct their Control subtree before it enters SceneTree.
	# Global transforms return identity there, so compose the same root-relative
	# transform locally. This also keeps streamed and prebuilt sources identical.
	var transform := Transform3D.IDENTITY
	var ancestor: Node = node
	var chain: Array[Node3D] = []
	while ancestor!=_stage.world_root:
		if ancestor is Node3D:
			chain.append(ancestor as Node3D)
		ancestor=ancestor.get_parent()
	for index: int in range(chain.size()-1,-1,-1):
		transform=transform*chain[index].transform
	var parts: Array = [node.get_class(),_transform(transform),[_vector3(mesh.get_aabb().position),_vector3(mesh.get_aabb().size)],_mesh_hash(mesh)]
	if node is MultiMeshInstance3D:
		var transforms: Array = []
		var instances: MultiMesh = (node as MultiMeshInstance3D).multimesh
		for index: int in range(instances.instance_count):
			transforms.append(_transform(instances.get_instance_transform(index)))
		parts.append(transforms)
	return JSON.stringify(parts).sha256_text()


func _mesh_hash(mesh: Mesh) -> String:
	if _mesh_hashes.has(mesh.get_instance_id()):
		return _mesh_hashes[mesh.get_instance_id()]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for index: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(index)
		if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			context.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			context.update((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	var result := context.finish().hex_encode()
	_mesh_hashes[mesh.get_instance_id()]=result
	return result


func _transform(value: Transform3D) -> Array:
	return [_vector3(value.basis.x),_vector3(value.basis.y),_vector3(value.basis.z),_vector3(value.origin)]


func _vector3(value: Vector3) -> Array:
	return [snappedf(value.x,0.00001),snappedf(value.y,0.00001),snappedf(value.z,0.00001)]


func _v4(row: Array) -> Vector4:
	return Vector4(float(row[0]),float(row[1]),float(row[2]),float(row[3]))
