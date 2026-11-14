extends "res://addons/cultivation_mode/chengdu_layered_street.gd"
## Second actual use of the accepted composition: all eighteen original lots.
## Density and shop identity are authored data; settlement stays in the host.

const FINISHED_CONFIG="res://assets/data/chengdu-finished-street-layout.json"
var _dressed: Dictionary={}
var _zone_counts: Dictionary={}
var _plants: Array[Dictionary]=[]
var _planters:=0
var _solid_errors: Array[String]=[]


func setup(stage: Node) -> void:
	_stage=stage
	_config=JSON.parse_string(FileAccess.get_file_as_string(FINISHED_CONFIG))
	_paint_shader=Shader.new()
	_paint_shader.code=PAINT
	attach_houses()


func attach_houses() -> void:
	super.attach_houses()
	for row: Dictionary in _records:
		if _dressed.has(row.id):
			continue
		var dressing: Dictionary=_config.dressing[row.id]
		var zone:=str(dressing.zone)
		_zone_counts[zone]=int(_zone_counts.get(zone,0))+1
		for plant: Dictionary in dressing.plants:
			_add_plant(row,plant)
		_dressed[row.id]=true


func _add_motion(root: Node3D, context: Dictionary, _profile: Dictionary) -> void:
	# Identical painted corner houses need not all become fruit sellers.
	var id:=str(root.get_parent().get_meta("art_street_id",""))
	if _config.house_motion.has(id):
		super._add_motion(root,context,_config.house_motion[id])


func _add_plant(row: Dictionary, config: Dictionary) -> void:
	var market: Node=_stage.get("_market_life")
	# Reuse the established, cached original atlas packaging and alpha anchors.
	var cell:=int(config.cell)
	var texture:=market.call("_cell","plants",cell) as Texture2D
	if texture==null:
		_errors.append(str(row.id)+": existing plant cell unavailable")
		return
	var size:=Vector2(config.size[0],config.size[1])
	var foot:=Vector3(config.foot_local[0],.045,config.foot_local[1])
	var world: Vector3=row.body.transform*foot
	var inverse: Transform3D=row.body.transform.affine_inverse()
	var potted:=bool(config.potted)
	if potted:
		_add_planter(row,foot)
		world.y+=.15
	var meta: Dictionary=market.get("_texture_audit")["plants"+str(cell)]
	world-=_basis.y*(float(meta.shoe_uv_from_bottom)*size.y)
	var mesh:=_quad([inverse*(world-_basis.x*size.x*.5),inverse*(world+_basis.x*size.x*.5),inverse*(world+_basis.x*size.x*.5+_basis.y*size.y),inverse*(world-_basis.x*size.x*.5+_basis.y*size.y)])
	mesh.name="StreetPlant_"+str(cell)
	var material:=ShaderMaterial.new()
	material.shader=_paint_shader
	material.set_shader_parameter("illustration",texture)
	material.set_shader_parameter("reveal",.96)
	material.set_shader_parameter("fade",float(row.row.fade))
	material.set_shader_parameter("player_uv",Vector2(.5,.5))
	mesh.material_override=material
	row.root.add_child(mesh)
	(row.row.materials as Array).append(material)
	(row.materials as Array).append(material)
	_plants.append({"house_id":row.id,"cell":cell,"node":mesh,"material":material,"potted":potted,"foot_local":foot,"height":size.y})


func _add_planter(row: Dictionary, foot: Vector3) -> void:
	# Only this small solid part needs a ground footprint; leaves may overhang.
	var bounds: Array=_stage.get("_art_profiles")[row.id].bounds
	var allowed:=Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3]))
	for x: float in [-.10,.10]:
		for z: float in [-.10,.10]:
			var world: Vector3=row.body.transform*(foot+Vector3(x,0,z))
			if not allowed.has_point(_stage.call("world_to_logical",world)):
				_solid_errors.append(str(row.id)+": planter outside original blocked lot")
	var pot:=MeshInstance3D.new()
	pot.name="SmallEarthenPlanter"
	var cylinder:=CylinderMesh.new()
	cylinder.radial_segments=10
	cylinder.rings=1
	cylinder.top_radius=.10
	cylinder.bottom_radius=.072
	cylinder.height=.15
	pot.mesh=cylinder
	pot.position=foot+Vector3.UP*.075
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("#82745c")
	material.roughness=1.0
	pot.material_override=material
	pot.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	row.root.add_child(pot)
	var soil:=MeshInstance3D.new()
	soil.name="PlanterSoil"
	var top:=CylinderMesh.new()
	top.radial_segments=10
	top.height=.006
	top.top_radius=.085
	top.bottom_radius=.085
	soil.mesh=top
	soil.position=foot+Vector3.UP*.151
	var dark:=StandardMaterial3D.new()
	dark.albedo_color=Color("#494b39")
	dark.roughness=1.0
	soil.material_override=dark
	soil.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	row.root.add_child(soil)
	_planters+=1


func audit() -> Dictionary:
	var result:=super.audit()
	result.layout_source=FINISHED_CONFIG
	result["zones"]=_zone_counts.duplicate()
	result["plant_cards"]=_plants.size()
	result["planters"]=_planters
	result["solid_footprint_errors"]=_solid_errors.duplicate()
	result["dressing_source"]="Existing original market-life atlas, cached alpha/crop anchors; authored per-lot density"
	return result
