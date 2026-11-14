extends RefCounted
## Small authored cloth/bamboo props; geometry follows the original head/chest rig.
const CLOTH = preload("res://addons/cultivation_mode/dock_corner_cloth.gdshader")
var head: Node3D
var chest: Node3D
var book: Node3D
var parts := 0
var archetype := ""

func material(color: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 0.93
	return result

func piece(parent: Node3D, mesh: Mesh, at: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material(color)
	parent.add_child(node)
	parts += 1
	return node

func box(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return piece(parent,shape,at,color)

func cone(parent: Node3D, at: Vector3, bottom: float, top: float, height: float, color: String) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = 32
	return piece(parent,shape,at,color)

func line(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: String) -> void:
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius
	shape.height = from.distance_to(to)
	shape.radial_segments = 6
	var node := piece(parent,shape,(from+to)*0.5,color)
	node.quaternion = Quaternion(Vector3.UP,(to-from).normalized())

func recolor(mesh: MeshInstance3D, color: Color) -> void:
	for surface: int in range(mesh.mesh.get_surface_count()):
		var old := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		var shader := ShaderMaterial.new()
		shader.shader = CLOTH
		shader.set_shader_parameter("cloth_color",color)
		if old!=null and old.albedo_texture!=null:
			shader.set_shader_parameter("fabric",old.albedo_texture)
			shader.set_shader_parameter("has_fabric",true)
		if old!=null and old.normal_texture!=null:
			shader.set_shader_parameter("fabric_normal",old.normal_texture)
			shader.set_shader_parameter("has_normal",true)
		mesh.mesh.surface_set_material(surface,shader)

func setup(skeleton: Skeleton3D, profile: Dictionary, meshes: Array) -> void:
	archetype = str(profile.archetype)
	head = Node3D.new()
	head.name = "ResidentHeadwear"
	skeleton.add_child(head)
	chest = Node3D.new()
	chest.name = "ResidentBelongings"
	skeleton.add_child(chest)
	for mesh: MeshInstance3D in meshes:
		if str(mesh.name) in ["SellerCeladonCup","SellerWipingCloth","SellerApronAndTies","SellerWorkingHeadwrap"]:
			mesh.visible = false
		if str(mesh.name)=="TeaSellerBrownClothing":
			recolor(mesh,Color(profile.tint))
		if str(mesh.name)=="SellerTailoredCollar":
			recolor(mesh,Color("#c6c5ae") if archetype=="scholar" else Color("#6a6650"))
	if archetype=="scholar":
		cone(head,Vector3(0,0.25,-0.025),0.205,0.16,0.17,"#333f40")
		cone(head,Vector3(0,0.155,-0.025),0.21,0.21,0.055,"#263333")
		box(head,Vector3(-0.075,0.065,-0.18),Vector3(0.075,0.22,0.025),"#344343").rotation.x = -0.13
		box(head,Vector3(0.075,0.055,-0.18),Vector3(0.075,0.24,0.025),"#344343").rotation.x = -0.17
		book = Node3D.new()
		book.name = "FoldedBook"
		chest.add_child(book)
		book.position = Vector3(0,-0.05,0.30)
		book.rotation.x = -0.38
		box(book,Vector3.ZERO,Vector3(0.36,0.04,0.23),"#ddd4b3")
		box(book,Vector3(0,-0.026,0),Vector3(0.38,0.012,0.25),"#404f5b")
		box(book,Vector3(-0.17,0.025,0),Vector3(0.025,0.008,0.23),"#777e79")
		for i: int in range(4):
			box(book,Vector3(0.03,0.022,-0.07+float(i)*0.045),Vector3(0.23,0.004,0.003),"#7c7b68")
	else:
		cone(head,Vector3(0,0.24,-0.025),0.43,0.065,0.16,"#b59b64")
		cone(head,Vector3(0,0.155,-0.025),0.43,0.42,0.018,"#8c754e")
		for i: int in range(16):
			var angle := TAU*float(i)/16.0
			line(head,Vector3(cos(angle)*0.075,0.325,sin(angle)*0.075-0.025),Vector3(cos(angle)*0.42,0.165,sin(angle)*0.42-0.025),0.004,"#d1b681")
		# Back basket: continuous tapered shell, raised hoops and vertical ribs.
		cone(chest,Vector3(0,-0.22,-0.47),0.23,0.29,0.63,"#8e754e")
		for level: int in range(7):
			var y := -0.53+float(level)*0.10
			var radius := lerpf(0.235,0.29,float(level)/6.0)
			for i: int in range(20):
				var a := TAU*float(i)/20.0
				var b := TAU*float(i+1)/20.0
				line(chest,Vector3(cos(a)*radius,y,sin(a)*radius-0.47),Vector3(cos(b)*radius,y,sin(b)*radius-0.47),0.009,"#b69b6a")
		for i: int in range(12):
			var angle := TAU*float(i)/12.0
			line(chest,Vector3(cos(angle)*0.235,-0.53,sin(angle)*0.235-0.47),Vector3(cos(angle)*0.29,0.095,sin(angle)*0.29-0.47),0.009,"#c0a06b")
		# Rolled cloth protrudes above the basket, clearly separate from the head.
		var cloth := cone(chest,Vector3(0,0.12,-0.47),0.13,0.13,0.48,"#727d71")
		cloth.rotation.z = PI/2
		for side: float in [-1.0,1.0]:
			line(chest,Vector3(side*0.23,0.19,-0.11),Vector3(side*0.23,0.02,0.26),0.023,"#665a43")
			line(chest,Vector3(side*0.23,0.02,0.26),Vector3(side*0.23,-0.30,0.20),0.023,"#665a43")
			line(chest,Vector3(side*0.23,0.19,-0.11),Vector3(side*0.23,-0.25,-0.47),0.023,"#665a43")
	_batch(head)
	_batch(chest)

func _batch(parent: Node3D) -> void:
	# Bamboo ribs are authoring pieces, not a separate runtime draw per strip.
	var groups := {}
	for node: Node in parent.get_children():
		if node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			var key := str((mesh.material_override as StandardMaterial3D).albedo_color)
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool":tool,"material":mesh.material_override}
			groups[key].tool.append_from(mesh.mesh,0,mesh.transform)
			mesh.free()
	for group: Dictionary in groups.values():
		var mesh := MeshInstance3D.new()
		mesh.mesh = group.tool.commit()
		mesh.material_override = group.material
		parent.add_child(mesh)

func present(skeleton: Skeleton3D, action: String) -> void:
	head.transform = skeleton.get_bone_global_pose(skeleton.find_bone("head"))
	chest.transform = skeleton.get_bone_global_pose(skeleton.find_bone("chest"))
	if book!=null:
		book.visible = action=="read"
