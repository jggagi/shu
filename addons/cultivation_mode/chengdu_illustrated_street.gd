extends Node
## Painted silhouettes replace colour rendering of the selected street models.
## Original lots, actors, occlusion rows and shadow-only geometry remain hosts.

const LAYOUT := "res://assets/data/chengdu-illustrated-street-layout.json"
const LAYERS := "res://assets/art/chengdu_illustrated_street_20261112/layers.json"
const SURFACE := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade = 0.0;
uniform vec2 player_uv = vec2(0.5);
void fragment() {
    vec4 painted=texture(illustration,UV);
    if (painted.a<0.12) { discard; }
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(40.0,90.0,length(delta));
    ALBEDO=painted.rgb;
    ALPHA=painted.a*(1.0-local*fade*0.94);
    ROUGHNESS=1.0;
}
"""

var _stage: Node
var _config: Dictionary = {}
var _layers: Dictionary = {}
var _seen: Dictionary = {}
var _changed: Array[Dictionary] = []
var _bindings: Array[Dictionary] = []
var _roots: Array[Node3D] = []
var _actor_transforms: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _kept: Dictionary = {}
var _errors: Array[String] = []
var _enabled := true
var _shader: Shader
var _right := Vector3.ZERO
var _up := Vector3.ZERO


func setup(stage: Node) -> void:
	_stage=stage
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var layers: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAYERS))
	if not config is Dictionary or not layers is Dictionary:
		_errors.append("Illustrated street layout or layers missing")
		return
	_config=config
	_layers=layers.layers
	_shader=Shader.new()
	_shader.code=SURFACE
	var basis:=Basis.from_euler(Vector3(deg_to_rad(-52.0),deg_to_rad(45.0),0.0))
	_right=basis.x
	_up=basis.y
	_prepare_cast()
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func _prepare_cast() -> void:
	# Keep the original living cast and its contacts. Painted props are in the art.
	for helper_name: String in ["_market_life","_tea_polish"]:
		var helper: Node=_stage.get(helper_name)
		for row: Dictionary in helper.get("records"):
			if str(row.kind) not in ["vendor","merchant","contact"] or _kept.has(row.node.get_instance_id()):
				continue
			_kept[row.node.get_instance_id()]=true
			if str(row.kind)!="contact":
				_face_cast(row.node)


func _chain(node: Node) -> Transform3D:
	var result:=Transform3D.IDENTITY
	var cursor:=node
	while cursor!=null and cursor!=_stage.get("world_root"):
		if cursor is Node3D:
			result=(cursor as Node3D).transform*result
		cursor=cursor.get_parent()
	return result


func _face_cast(node: MeshInstance3D) -> void:
	var original:=node.transform
	var parent:=_chain(node.get_parent())
	var box:=node.mesh.get_aabb()
	var foot:=parent*original*(box.position+Vector3(box.size.x*.5,0,box.size.z*.5))
	var rotation:=Basis(Vector3.UP,deg_to_rad(45.0))
	var around:=Transform3D(rotation,foot-rotation*foot)
	node.transform=parent.affine_inverse()*around*parent*original
	_actor_transforms.append({"node":node,"transform":original})


func _relative_visible(node: Node,body: Node) -> bool:
	var cursor:=node
	while cursor!=body and cursor!=null:
		if cursor is Node3D and not cursor.visible:
			return false
		cursor=cursor.get_parent()
	return true


func attach_house(body: Node) -> void:
	if _shader==null or _seen.has(body.get_instance_id()):
		return
	_prepare_cast()
	var id:=str(body.get_meta("art_street_id",""))
	if not _config.get("houses",{}).has(id):
		return
	var item: Dictionary=_config.houses[id]
	var layer: Dictionary=_layers[str(item.layer)]
	var texture:=load(str(layer.path)) as Texture2D
	if texture==null:
		_errors.append(id+": painted layer missing")
		return
	var row: Dictionary={}
	for candidate: Dictionary in _stage.get("roof_rows"):
		if candidate.get("body")==body:
			row=candidate
			break
	if row.is_empty():
		_errors.append(id+": original occlusion row missing")
		return
	for node: Node in body.find_children("*","MeshInstance3D",true,false):
		if _kept.has(node.get_instance_id()) or not _relative_visible(node,body):
			continue
		var shadow_material: Material=node.material_override
		if shadow_material is ShaderMaterial:
			shadow_material=shadow_material.duplicate() as ShaderMaterial
			# A retained proxy should cast a complete, stable shadow while its
			# colour painting softly reveals the player. Do not copy screen-space
			# dither from the old camera materials into the shadow map.
			for uniform: Dictionary in (shadow_material as ShaderMaterial).shader.get_shader_uniform_list():
				if str(uniform.name)=="fade":
					(shadow_material as ShaderMaterial).set_shader_parameter("fade",0.0)
			shadow_material.next_pass=null
		_changed.append({"node":node,"cast_shadow":node.cast_shadow,"visible":node.visible,"material":node.material_override,"overlay":node.material_overlay,"shadow_material":shadow_material})
		if _enabled:
			if node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				node.visible=false
			else:
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				node.material_override=shadow_material
				node.material_overlay=null
	var old_signs: Array[Label3D]=[]
	for node: Label3D in body.find_children("*","Label3D",true,false):
		if _relative_visible(node,body):
			old_signs.append(node)
			_labels.append({"node":node,"visible":node.visible})
			node.visible=not _enabled
	var root:=Node3D.new()
	root.name="IllustratedStreetLayer"
	root.set_meta("art_street_preserve",true)
	root.set_meta("painted_city_preserve",true)
	body.add_child(root)
	_roots.append(root)
	var profile: Dictionary=_stage.get("_art_profiles")[id]
	var bounds: Array=profile.bounds
	# At this fixed isometric angle the nearest foundation corner is southeast.
	var foot: Vector3=_stage.call("logical_to_world",Vector2(float(bounds[0])+float(bounds[2]),float(bounds[1])+float(bounds[3])))
	foot.y=0.025
	var size:=Vector2(float(layer.size[0]),float(layer.size[1]))
	var anchor:=Vector2(float(layer.anchor_px[0]),float(layer.anchor_px[1]))
	var pixels_per_meter:=size.x/float(item.width_meters)
	# Body transforms are authored local to world_root, including setup off-tree.
	var inverse: Transform3D=(body as Node3D).transform.affine_inverse()
	var corners: Array[Vector3]=[]
	for uv: Vector2 in [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]:
		var pixel:=uv*size
		var point:=foot+_right*((pixel.x-anchor.x)/pixels_per_meter)+_up*((anchor.y-pixel.y)/pixels_per_meter)
		corners.append(inverse*point)
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0,1,2,0,2,3]:
		surface.set_normal(_right.cross(_up))
		surface.set_uv([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][index])
		surface.add_vertex(corners[index])
	var mesh:=MeshInstance3D.new()
	mesh.name="Painted_"+str(item.layer)
	mesh.mesh=surface.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new()
	material.shader=_shader
	material.set_shader_parameter("illustration",texture)
	material.set_shader_parameter("fade",float(row.fade))
	material.set_shader_parameter("player_uv",Vector2(.5,.5))
	mesh.material_override=material
	root.add_child(mesh)
	for old: Label3D in old_signs:
		var label:=Label3D.new()
		label.name="PaintedSign"
		label.text=old.text
		label.font=old.font
		label.font_size=40
		label.pixel_size=.0048
		label.outline_size=10
		label.modulate=Color("#e6d9a7")
		label.outline_modulate=Color("#3b3022")
		label.basis=Basis.from_euler(Vector3(deg_to_rad(-52.0),deg_to_rad(45.0),0.0))
		label.position=inverse*(foot+_up*1.37+_right*.12+_right.cross(_up)*.035)
		root.add_child(label)
	(row.materials as Array).append(material)
	_bindings.append({"material":material,"row":row,"house_id":id,"layer":item.layer,"anchor_world":foot,"width_meters":item.width_meters})
	_seen[body.get_instance_id()]=true
	root.visible=_enabled


func set_enabled(enabled: bool) -> void:
	_enabled=enabled
	for row: Dictionary in _changed:
		if is_instance_valid(row.node):
			row.node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled and int(row.cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else row.cast_shadow
			row.node.visible=bool(row.visible) and (not enabled or int(row.cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			row.node.material_override=row.shadow_material if enabled and int(row.cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else row.material
			row.node.material_overlay=null if enabled and int(row.cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else row.overlay
	for row: Dictionary in _labels:
		if is_instance_valid(row.node):
			row.node.visible=bool(row.visible) and not enabled
	for root: Node3D in _roots:
		if is_instance_valid(root):
			root.visible=enabled


func audit() -> Dictionary:
	var casters:=0
	for row: Dictionary in _changed:
		if int(row.cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters+=1
	return {"layout_source":LAYOUT,"layer_source":LAYERS,"painted_houses":_seen.size(),"layer_count":_layers.size(),"source_colour_meshes_replaced":_changed.size(),"shadow_only_meshes":casters,"hidden_decor_cards":_changed.size()-casters,"kept_cast_records":_kept.size(),"reoriented_cast_cards":_actor_transforms.size(),"painted_signs":_labels.size(),"new_obstacles":0,"fixed_yaw_degrees":45.0,"continuous_follow":true,"occlusion":"soft local alpha; retained shadow proxies use private non-fading materials","enabled":_enabled,"new_state":false,"errors":_errors.duplicate()}


func _exit_tree() -> void:
	set_enabled(false)
	for row: Dictionary in _actor_transforms:
		if is_instance_valid(row.node):
			row.node.transform=row.transform
	for row: Dictionary in _bindings:
		(row.row.materials as Array).erase(row.material)
	for root: Node3D in _roots:
		if is_instance_valid(root):
			root.queue_free()
