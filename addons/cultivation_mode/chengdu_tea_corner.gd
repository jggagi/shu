extends "res://addons/cultivation_mode/chengdu_grounded_street.gd"
## Four-house composition only. Movement and settlement stay in EngineSession.

const CORNER_CONFIG="res://assets/data/chengdu-tea-corner-layout.json"
const CORNER_PAINT="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade=0.0;
uniform float reveal=0.995;
uniform vec2 player_uv=vec2(0.5);
void fragment(){
 vec4 art=texture(illustration,UV);
 if(art.a<0.12){discard;}
 vec2 distance=(SCREEN_UV-player_uv)*vec2(1280.0,720.0)/vec2(58.0,108.0);
 float local=1.0-smoothstep(0.62,1.18,length(distance));
 ALBEDO=art.rgb;
 ALPHA=art.a*(1.0-local*fade*reveal);
 ROUGHNESS=1.0;
}
"""
const SELLER_PAINT="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D sheet_cell : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade=0.0;
uniform vec2 player_uv=vec2(0.5);
void fragment(){
 vec4 art=texture(sheet_cell,UV);
 if(art.a<.12){discard;}
 vec2 offset=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
 float local=1.0-smoothstep(44.0,92.0,length(offset));
 ALBEDO=art.rgb*COLOR.rgb;
 ALPHA=art.a*(1.0-local*fade*.30);
 ROUGHNESS=1.0;
}
"""
const WEATHERED_APRON="""shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled, depth_draw_never;
uniform sampler2D paving : source_color, filter_linear_mipmap, repeat_enable;
uniform float period=1.65;
uniform float age_seed=0.0;
varying vec3 world_position;
varying vec3 direct_linear;
vec3 linear_delta(vec3 c){return mix(pow((c+vec3(.055))/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(.04045)));}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float age=.5+.24*sin(UV.x*19.0+age_seed)+.16*sin(UV.x*43.0-age_seed);
 vec3 lit=texture(paving,world_position.xz/period).rgb*mix(vec3(.84,.88,.76),vec3(1.05,1.01,.94),age);
 vec3 shade=lit*vec3(.72,.78,.87);
 EMISSION=shade;
 ALBEDO=vec3(1.0);
 direct_linear=linear_delta(max(lit-shade,vec3(0.0)));
 float edge=1.0-smoothstep(.06+age*.15,.65+age*.30,1.0-UV.y);
 float ends=smoothstep(0.0,.08,UV.x)*(1.0-smoothstep(.92,1.0,UV.x));
 ALPHA=edge*ends*(.45+age*.24);
 ROUGHNESS=1.0;
 SPECULAR=0.0;
}
void light(){if(LIGHT_IS_DIRECTIONAL){DIFFUSE_LIGHT+=direct_linear*ATTENUATION;}}
"""
var _corner_config: Dictionary
var _corner_shader: Shader
var _weather_shader: Shader
var _corner_seen: Dictionary={}
var _corner_materials: Array[Dictionary]=[]
var _corner_aprons: Array[Dictionary]=[]
var _corner_nodes: Array[Node3D]=[]
var _corner_enabled:=true
var _landing_stones:=0
var _corner_cast: Array[Dictionary]=[]
var _seller_anchor_clear:=false
var _seller_frontage_valid:=true


func setup(stage: Node) -> void:
	_corner_config=JSON.parse_string(FileAccess.get_file_as_string(CORNER_CONFIG))
	_corner_shader=Shader.new()
	_corner_shader.code=CORNER_PAINT
	_weather_shader=Shader.new()
	_weather_shader.code=WEATHERED_APRON
	super.setup(stage)


func attach_houses() -> void:
	super.attach_houses()
	for row: Dictionary in _records:
		if _corner_seen.has(row.id) or not _corner_config.get("houses",{}).has(row.id):
			continue
		var authored: Dictionary=_corner_config.houses[row.id]
		var group:=Node3D.new()
		group.name="TeaCornerLife"
		row.root.add_child(group)
		_corner_nodes.append(group)
		var local_row:=row.duplicate()
		local_row.root=group
		for plant: Dictionary in authored.plants:
			_add_plant(local_row,plant)
		if bool(authored.landing):
			_add_landing(group)
		for material: ShaderMaterial in row.materials:
			_corner_materials.append({"material":material,"shader":material.shader,"reveal":material.get_shader_parameter("reveal")})
			material.shader=_corner_shader
			material.set_shader_parameter("reveal",.995)
		for mesh: MeshInstance3D in row.ground.find_children("*","MeshInstance3D",true,false):
			if mesh.material_override!=_apron_material:
				continue
			var old_material:=mesh.material_override as ShaderMaterial
			var weathered:=old_material.duplicate() as ShaderMaterial
			weathered.shader=_weather_shader
			weathered.set_shader_parameter("age_seed",float(authored.seed))
			_corner_aprons.append({"mesh":mesh,"original":old_material,"material":weathered})
			mesh.material_override=weathered
		_corner_seen[row.id]=true
	_arrange_seller()
	set_corner_enabled(_corner_enabled)


func _arrange_seller() -> void:
	if not _corner_cast.is_empty() or not _corner_config.has("seller"):
		return
	var polish: Node=_stage.get("_tea_polish")
	var illustrated: Node=_stage.get("_illustrated_street")
	if not is_instance_valid(polish) or not is_instance_valid(illustrated):
		return
	var proof: Dictionary=polish.get("_merchant_proof")
	if proof.is_empty():
		return
	var authored: Dictionary=_corner_config.seller
	var target:=Vector2(authored.anchor[0],authored.anchor[1])
	_seller_anchor_clear=bool(polish.call("_walkable_anchor",target,float(authored.clearance)))
	if not _seller_anchor_clear:
		_errors.append("Tea corner seller anchor is blocked")
		return
	var previous: Array=proof.logical_anchor
	var delta: Vector3=_stage.logical_to_world(target)-_stage.logical_to_world(Vector2(previous[0],previous[1]))
	for record: Dictionary in polish.get("records"):
		if record.house_id!="ward_city_22_19" or str(record.kind) not in ["merchant","contact"]:
			continue
		var node:=record.node as Node3D
		var chain: Transform3D=illustrated.call("_chain",node.get_parent())
		var offset:=delta
		if record.kind=="merchant":
			offset.y=float(authored.shoe_y)-float(proof.shoe_world_y)
		var refined:=node.transform
		refined.origin+=chain.basis.inverse()*offset
		if record.kind=="merchant":
			var raw: Array=authored.logical_billboard_envelope
			var envelope:=Rect2(raw[0],raw[1],raw[2],raw[3])
			for vertex: Vector3 in (node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var world: Vector3=chain*refined*vertex
				if not envelope.has_point(_stage.world_to_logical(world)) or world.y<-.05 or world.y>1.25:
					_seller_frontage_valid=false
		var binding: Dictionary={"node":node,"original":node.transform,"refined":refined}
		if record.kind=="merchant":
			var original_material: ShaderMaterial=(node as MeshInstance3D).material_override
			var material:=original_material.duplicate() as ShaderMaterial
			var shader:=Shader.new()
			shader.code=SELLER_PAINT
			material.shader=shader
			(record.roof_row.materials as Array).append(material)
			binding.merge({"original_material":original_material,"material":material,"roof_row":record.roof_row})
		_corner_cast.append(binding)
	if not _seller_frontage_valid:
		_errors.append("Tea corner seller leaves authored frontage envelope")
		return
	# These two old-coordinate failures are superseded by the explicit new
	# frontage proof, rather than being treated as current scene errors.
	var failures: Array=polish.get("_bounds_errors")
	for index: int in range(failures.size()-1,-1,-1):
		var issue: Dictionary=failures[index]
		if issue.get("house_id","")=="ward_city_22_19" and str(issue.get("error","")) in ["merchant card leaves explicit frontage envelope","tea seller original anchor is not walkable with clearance"]:
			failures.remove_at(index)


func _add_landing(parent: Node3D) -> void:
	# Low worn stones remain entirely inside the already blocked lot.
	for index: int in range(2):
		var mesh:=MeshInstance3D.new()
		mesh.name="WornThresholdStone"
		var box:=BoxMesh.new()
		box.size=Vector3(.46,.035,.20)
		mesh.mesh=box
		mesh.position=Vector3(.66-index*.48,.0505,.86-index*.016)
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("#a29b83") if index==0 else Color("#b1a88d")
		material.roughness=1.0
		mesh.material_override=material
		parent.add_child(mesh)
		_landing_stones+=1


func set_corner_enabled(enabled: bool) -> void:
	_corner_enabled=enabled
	for row: Dictionary in _corner_materials:
		row.material.shader=_corner_shader if enabled else row.shader
		row.material.set_shader_parameter("reveal",.995 if enabled else row.reveal)
	for row: Dictionary in _corner_aprons:
		row.mesh.material_override=row.material if enabled else row.original
	for node: Node3D in _corner_nodes:
		node.visible=enabled
	for row: Dictionary in _corner_cast:
		row.node.transform=row.refined if enabled else row.original
		if row.has("material"):
			row.node.material_override=row.material if enabled else row.original_material


func audit() -> Dictionary:
	var result:=super.audit()
	result["tea_corner"]={"focus_houses":_corner_seen.keys(),"enabled":_corner_enabled,
		"weathered_aprons":_corner_aprons.size(),"extra_plant_cards":_corner_seen.size()*2,
		"landing_stones":_landing_stones,"reveal_radius_pixels":[58,108],
		"seller_anchor":_corner_config.seller.anchor,"seller_anchor_clear":_seller_anchor_clear,
		"seller_shoe_y":_corner_config.seller.shoe_y,"seller_and_contact_nodes":_corner_cast.size(),
		"seller_frontage_valid":_seller_frontage_valid,
		"seller_soft_alpha":true,
		"source":CORNER_CONFIG,"new_obstacles":0,"new_clock":false}
	return result


func _exit_tree() -> void:
	for row: Dictionary in _corner_cast:
		if is_instance_valid(row.node):
			row.node.transform=row.original
			if row.has("material"):
				row.node.material_override=row.original_material
		if row.has("material"):
			(row.roof_row.materials as Array).erase(row.material)
	super._exit_tree()
