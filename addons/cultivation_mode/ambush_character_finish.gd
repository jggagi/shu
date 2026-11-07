extends RefCounted
## Locally authored replacement geometry, attached to the existing enemy pivots.
## One merged matte mesh per moving part; no animation or gameplay authority.
const CharacterMesh = preload("res://addons/cultivation_mode/ambush_character_mesh.gd")
var meshes: Array[MeshInstance3D] = []
var _builder: RefCounted
var _parts: Array[Node3D] = []
var _metal_parts: Array[Node3D] = []
var _cloth: String
var _dark: String
var _light: String
var _skin: String
var _hair: String = "#332c27"
var _leather: String = "#514237"
var _brute: bool
var _archer: bool
var _triangle_count: int = 0

func build(pivots: Dictionary, palette: Dictionary, brute: bool, archer: bool) -> void:
	_builder = CharacterMesh.new()
	_cloth = str(palette.robe)
	_dark = str(palette.shadow)
	_light = "#aa9676" if brute else "#a7a58a" if archer else "#a3a1aa"
	_skin = str(palette.skin)
	_brute = brute
	_archer = archer
	var torso: Node3D = _part(pivots.body, "RefinedClothing")
	_build_torso(torso)
	for side: int in [-1, 1]:
		_build_leg(_part(pivots.left_leg if side < 0 else pivots.right_leg, "RefinedLeg"), side)
		_build_arm(_part(pivots.right_arm if side < 0 else pivots.left_arm, "RefinedArm"), side)
	_build_head(_part(pivots.head, "RefinedHead"))
	_build_weapon(_part(pivots.weapon, "RefinedHeldWeapon"))
	if archer:
		_build_quiver(torso)
	elif not brute:
		_build_scabbard(torso)
	_merge_parts()

func _part(parent: Node3D, label: String, metal: bool = false) -> Node3D:
	var result := Node3D.new()
	result.name = label
	parent.add_child(result)
	_parts.append(result)
	if metal:
		_metal_parts.append(result)
	return result

func _build_torso(parent: Node3D) -> void:
	var shoulder: float = 0.294 if _brute else 0.248
	_builder.loft(parent, "TailoredJacket", [[0.73,0.19,0.14,0,0],[0.80,0.222,0.167,0,0],[0.92,0.249 if _brute else 0.231,0.178,0,0],[1.05,shoulder,0.165,0,-0.008],[1.12,shoulder*0.86,0.14,0,-0.012],[1.17,0.11,0.087,0,0]], _cloth, 32)
	_builder.loft(parent, "WarmNeck", [[1.145,0.083,0.076,0,0],[1.34,0.061,0.058,0,0]], _skin, 20)
	_build_high_inner_collar(parent)
	# A short standing collar frames the neck and joins the small head to the
	# shoulders. Its open front still leaves the crossing lapels readable.
	_builder.strand(parent, "BackStandingCollar", [Vector3(-0.087,1.215,0.018),Vector3(-0.072,1.265,-0.070),Vector3(0,1.274,-0.089),Vector3(0.072,1.265,-0.070),Vector3(0.087,1.215,0.018)], [0.026,0.029,0.032,0.029,0.026], 0.018, _light, 8)
	_builder.strand(parent, "BackShoulderYoke", [Vector3(-0.245,1.093,-0.093),Vector3(-0.14,1.135,-0.159),Vector3(0,1.139,-0.172),Vector3(0.14,1.135,-0.159),Vector3(0.245,1.093,-0.093)], [0.025,0.044,0.044,0.044,0.025], 0.021, _dark, 8)
	for side: int in [-1,1]:
		_builder.strand(parent, "BackWeightFold", [Vector3(side*0.11,1.09,-0.161),Vector3(side*0.15,0.958,-0.182),Vector3(side*0.093,0.846,-0.177)], [0.009,0.024,0.007], 0.015, _light, 6)
	# Both crossing bands have a convex section, rather than flat decals.
	_builder.strand(parent, "InnerTurnedCollar", [Vector3(-0.079,1.256,0.048),Vector3(-0.105,1.181,0.103),Vector3(-0.078,1.105,0.146),Vector3(0.055,0.990,0.180)], [0.023,0.031,0.034,0.027], 0.013, "#c2b49a", 8)
	_builder.strand(parent, "OuterTurnedCollar", [Vector3(0.080,1.256,0.048),Vector3(0.113,1.181,0.109),Vector3(0.105,1.10,0.155),Vector3(-0.038,0.948,0.190),Vector3(-0.121,0.841,0.176)], [0.027,0.036,0.038,0.035,0.027], 0.015, _light, 8)
	_builder.curved_strip(parent, "CollarFoldShadow", [Vector3(0.082,1.13,0.166),Vector3(-0.052,0.972,0.201),Vector3(-0.137,0.845,0.181)], [0.007,0.009,0.004], _dark)
	# Broad raised folds carry actual profile and catch the existing key light.
	for side: int in [-1,1]:
		_builder.strand(parent, "ChestFold", [Vector3(side*0.177,1.065,0.116),Vector3(side*0.173,0.955,0.153),Vector3(side*0.097,0.847,0.173)], [0.010,0.021,0.004], 0.012, _light, 6)
		_builder.strand(parent, "LowerJacketFold", [Vector3(side*0.13,0.75,0.145),Vector3(side*0.23,0.644,0.156),Vector3(side*0.245,0.515,0.170)], [0.007,0.025,0.010], 0.013, _dark, 6)
	# Eight closed, slightly convex panels have cloth thickness and a rolled hem.
	for index: int in range(8):
		var angle: float = (float(index)+0.5)*TAU/8.0
		var hem: float = 0.49 + (0.025 if index%2 == 0 else 0.0)
		_build_coat_panel(parent,angle,hem,_cloth if index<2 or index>5 else _dark)
		var edge:=Vector3(sin(angle)*0.298,hem,cos(angle)*0.298*0.80)
		var tangent := Vector3(cos(angle),0,-sin(angle))
		_builder.beam(parent, "TurnedCoatHem", edge-tangent*0.081, edge+tangent*0.081, 0.012, _light, 0.012, 8)
	_builder.loft(parent, "LayeredWaistSash", [[0.746,0.224,0.176,0,0],[0.759,0.232,0.181,0,0],[0.815,0.226,0.175,0,0],[0.835,0.220,0.171,0,0]], _leather, 32)
	_builder.loft(parent, "SashTopFold", [[0.820,0.227,0.176,0,0],[0.831,0.225,0.175,0,0]], "#8c8069", 32)
	_builder.loft(parent, "SashLowerFold", [[0.754,0.234,0.182,0,0],[0.767,0.234,0.182,0,0]], "#7d705b", 32)
	_builder.bevel_box(parent, "WovenBeltKnot", Vector3(-0.061,0.79,0.198), Vector3(0.108,0.070,0.051), "#918266")
	for side: int in [-1,1]:
		_builder.strand(parent, "HangingBeltEnd", [Vector3(-0.065+side*0.025,0.785,0.216),Vector3(-0.065+side*0.072,0.69,0.243),Vector3(-0.07+side*0.095,0.554,0.266)], [0.026,0.028,0.020], 0.008, "#685744", 6)
	if _brute:
		_build_brute_vest(parent)
	elif _archer:
		_builder.strand(parent, "QuiverStrap", [Vector3(0.16,1.145,-0.12),Vector3(0.205,1.125,0.096),Vector3(0.02,0.968,0.191),Vector3(-0.164,0.81,0.153)], [0.027,0.033,0.033,0.027], 0.012, "#6e5843", 8)
		_builder.bevel_box(parent, "StrapBuckle", Vector3(0.049,0.988,0.207), Vector3(0.070,0.079,0.016), "#aa9260")
		_builder.bevel_box(parent, "TravelBag", Vector3(-0.231,0.76,0.045), Vector3(0.116,0.163,0.094), "#776747")
		_builder.bevel_box(parent, "TravelBagFold", Vector3(-0.232,0.813,0.091), Vector3(0.124,0.061,0.024), "#928263")
		_builder.bevel_box(parent, "TravelBagClasp", Vector3(-0.233,0.795,0.112), Vector3(0.022,0.031,0.013), "#b29c6a")
	else:
		_build_blade_shawl(parent)

func _build_high_inner_collar(parent: Node3D) -> void:
	# The underlap flares into the chest, with a shallow V at the front. Its
	# upper edge leaves 0.055--0.080 m of the existing neck below the chin;
	# neither the head nor any original animation pivot is moved.
	var rings: Array = []
	for row: int in range(3):
		var ring: Array = []
		for index: int in range(32):
			var angle: float = TAU*float(index)/32.0
			var rx: float = [0.135,0.101,0.079][row]
			var rz: float = [0.103,0.087,0.075][row]
			var y: float = [1.13,1.195,1.269][row]
			if row==2:
				y-=0.025*pow(maxf(0.0,cos(angle)),4.0)
			ring.append(Vector3(sin(angle)*rx,y,cos(angle)*rz))
		rings.append(ring)
	var vertices: Array = []
	for row: int in range(2):
		for index: int in range(32):
			var next: int = (index+1)%32
			vertices.append_array([rings[row][index],rings[row][next],rings[row+1][next],rings[row][index],rings[row+1][next],rings[row+1][index]])
	for index: int in range(32):
		var next: int = (index+1)%32
		var a: Vector3 = rings[2][index]
		var b: Vector3 = rings[2][next]
		var inner_a := Vector3(a.x*0.91,a.y-0.008,a.z*0.91)
		var inner_b := Vector3(b.x*0.91,b.y-0.008,b.z*0.91)
		vertices.append_array([a,b,inner_b,a,inner_b,inner_a])
	_builder.make_mesh(parent,"VFrontInnerCollar",vertices,"#b8aa8f")
	_builder.strand(parent,"SoftVUnderlapEdge",[Vector3(-0.078,1.269,0.012),Vector3(-0.053,1.257,0.062),Vector3(0,1.244,0.079),Vector3(0.053,1.257,0.062),Vector3(0.078,1.269,0.012)],[0.007,0.008,0.008,0.008,0.007],0.006,"#d0c3a7",8)

func _build_coat_panel(parent: Node3D, angle: float, hem: float, color: String) -> void:
	# Concentric cloth sectors follow the hips. The outer face has a raised
	# centre fold; the inner face and four edges close its physical thickness.
	var front: Array = []
	var back: Array = []
	for row: int in range(4):
		var t: float = float(row)/3.0
		var radius: float = lerpf(0.205,0.298,t)
		for column: int in range(5):
			var fraction: float = float(column)/4.0
			var a: float = angle+lerpf(-0.355,0.355,fraction)
			var fold: float = sin(fraction*PI)*0.014*sin(t*PI*0.8)
			front.append(Vector3(sin(a)*(radius+fold),lerpf(0.78,hem,t),cos(a)*(radius+fold)*0.80))
			back.append(Vector3(sin(a)*(radius-0.013),lerpf(0.78,hem,t),cos(a)*(radius-0.013)*0.80))
	var vertices: Array = []
	for row: int in range(3):
		for column: int in range(4):
			var a: int = row*5+column
			vertices.append_array([front[a],front[a+1],front[a+6],front[a],front[a+6],front[a+5],back[a],back[a+6],back[a+1],back[a],back[a+5],back[a+6]])
	for row: int in range(3):
		for column: int in [0,4]:
			var a: int=row*5+column
			vertices.append_array([front[a],front[a+5],back[a+5],front[a],back[a+5],back[a]])
	for row: int in [0,3]:
		for column: int in range(4):
			var a: int=row*5+column
			vertices.append_array([front[a],back[a],back[a+1],front[a],back[a+1],front[a+1]])
	_builder.make_mesh(parent,"WeightedCoatPanel",vertices,color)

func _build_brute_vest(parent: Node3D) -> void:
	for side: int in [-1,1]:
		_builder.strand(parent, "ThickSleevelessVest", [Vector3(side*0.22,1.125,-0.10),Vector3(side*0.22,1.14,0.06),Vector3(side*0.20,1.02,0.14),Vector3(side*0.14,0.87,0.174)], [0.08,0.10,0.092,0.07], 0.035, "#5f5547", 8)
		_builder.strand(parent, "VestBoundEdge", [Vector3(side*0.155,1.14,0.105),Vector3(side*0.12,1.02,0.19),Vector3(side*0.071,0.867,0.196)], [0.016,0.019,0.013], 0.009, "#b19d78", 6)
	_builder.bevel_box(parent, "PatchPocket", Vector3(-0.205,0.927,0.17), Vector3(0.113,0.117,0.029), "#7a6a52")
	_builder.strand(parent, "PocketTurn", [Vector3(-0.26,0.976,0.187),Vector3(-0.21,0.982,0.194),Vector3(-0.15,0.977,0.190)], [0.008,0.009,0.008], 0.006, "#b09b78", 6)
	_builder.bevel_box(parent, "PaddedBackPanel", Vector3(0,0.97,-0.178), Vector3(0.38,0.30,0.055), "#655b4b")
	for x: float in [-0.105,0.0,0.105]:
		_builder.strand(parent, "BackQuilting", [Vector3(x,1.095,-0.212),Vector3(x,0.98,-0.22),Vector3(x,0.845,-0.201)], [0.007,0.010,0.006], 0.008, "#908064", 6)

func _build_blade_shawl(parent: Node3D) -> void:
	_builder.strand(parent, "ShoulderShawl", [Vector3(-0.10,1.17,-0.111),Vector3(-0.26,1.16,-0.03),Vector3(-0.281,1.08,0.070),Vector3(-0.20,0.98,0.157)], [0.112,0.117,0.105,0.061], 0.036, "#565868", 10)
	_builder.strand(parent, "ShawlLapel", [Vector3(-0.104,1.17,0.102),Vector3(-0.192,1.105,0.161),Vector3(-0.15,0.947,0.190),Vector3(-0.095,0.845,0.185)], [0.025,0.036,0.035,0.022], 0.015, "#92909e", 8)
	_builder.strand(parent, "BackShawlTail", [Vector3(-0.11,1.13,-0.17),Vector3(-0.16,1.01,-0.21),Vector3(-0.14,0.84,-0.22),Vector3(-0.08,0.66,-0.235)], [0.10,0.11,0.09,0.042], 0.014, "#565868", 8)
	_builder.strand(parent, "RedWaistCord", [Vector3(0.196,0.81,0.096),Vector3(0.12,0.78,0.177),Vector3(0,0.773,0.188),Vector3(-0.15,0.78,0.14)], [0.013,0.015,0.015,0.011], 0.008, "#9c7667", 6)
	_builder.bevel_box(parent, "WaistMedicinePouch", Vector3(-0.22,0.76,-0.04), Vector3(0.089,0.134,0.092), "#6a594c")

func _build_leg(parent: Node3D, side: int) -> void:
	var trouser: String = "#504940" if _brute else "#4e5144" if _archer else "#474b54"
	_builder.loft(parent, "FoldedTrousers", [[-0.50,0.064,0.067,0,0],[-0.37,0.080,0.079,0,0.006],[-0.22,0.096,0.091,side*0.008,0.013],[-0.10,0.114,0.098,0,0],[0.035,0.10,0.091,0,0]], trouser, 20)
	_builder.strand(parent, "TrouserKneeFold", [Vector3(-0.06,-0.29,0.075),Vector3(0,-0.31,0.105),Vector3(0.066,-0.30,0.071)], [0.007,0.014,0.005], 0.008, "#766f60", 6)
	_builder.loft(parent, "BootLeather", [[-0.61,0.080,0.097,0,0.035],[-0.49,0.083,0.079,0,0.015],[-0.43,0.085,0.077,0,0.016]], "#3e3730", 20)
	_builder.bevel_box(parent, "RoundedBootToe", Vector3(0,-0.592,0.067), Vector3(0.181,0.133,0.29), "#443a31")
	_builder.bevel_box(parent, "LayeredBootSole", Vector3(0,-0.646,0.067), Vector3(0.188,0.032,0.298), "#786b55")
	_builder.strand(parent, "ToeLeatherFold", [Vector3(-0.068,-0.54,0.125),Vector3(0,-0.531,0.173),Vector3(0.068,-0.54,0.125)], [0.005,0.008,0.005], 0.006, "#75614a", 6)
	if _brute or _archer:
		for band: int in range(4):
			var y: float = -0.44+float(band)*0.043
			_builder.loft(parent, "BroadLegWrap", [[y,0.086,0.086,0,0.014],[y+0.027,0.086,0.086,0,0.014]], "#a79b80" if band%2==0 else "#887c65", 20)
	else:
		_builder.loft(parent, "BootFoldedTop", [[-0.448,0.089,0.079,0,0.016],[-0.418,0.095,0.082,0,0.014]], "#77736c", 20)

func _build_arm(parent: Node3D, side: int) -> void:
	if _brute:
		_builder.strand(parent, "RolledShortSleeve", [Vector3(0,0,0),Vector3(side*0.045,-0.09,0.008),Vector3(side*0.057,-0.17,0.029)], [0.125,0.145,0.133], 0.125, _cloth, 16)
		_builder.strand(parent, "RolledSleeveHem", [Vector3(side*0.055,-0.144,0.023),Vector3(side*0.057,-0.184,0.037)], [0.142,0.139], 0.125, "#a79373", 16)
		_builder.strand(parent, "MuscularForearm", [Vector3(side*0.058,-0.172,0.035),Vector3(side*0.061,-0.24,0.067),Vector3(side*0.035,-0.332,0.123)], [0.105,0.106,0.078], 0.089, _skin, 16)
		_builder.strand(parent, "ForearmPlane", [Vector3(side*0.060,-0.20,0.116),Vector3(side*0.07,-0.25,0.15),Vector3(side*0.040,-0.31,0.175)], [0.018,0.026,0.012], 0.007, "#d1b99b", 6)
	else:
		_builder.strand(parent, "TailoredBentSleeve", [Vector3(0,0,0),Vector3(side*0.042,-0.10,0.006),Vector3(side*0.06,-0.205,0.042),Vector3(side*0.035,-0.31,0.109)], [0.112,0.131,0.116,0.088], 0.108, _cloth, 16)
		_builder.strand(parent, "SleeveGather", [Vector3(side*-0.027,-0.15,0.105),Vector3(side*0.008,-0.21,0.149),Vector3(side*0.033,-0.275,0.179)], [0.011,0.022,0.008], 0.012, _light, 6)
	_builder.strand(parent, "ThickWristCuff", [Vector3(side*0.036,-0.275,0.094),Vector3(side*0.035,-0.329,0.119)], [0.101,0.096], 0.094, _leather, 16)
	_builder.strand(parent, "CuffTurnedTop", [Vector3(side*0.036,-0.280,0.096),Vector3(side*0.036,-0.294,0.103)], [0.104,0.103], 0.098, "#a19376", 16)
	_builder.strand(parent, "CuffLowerBinding", [Vector3(side*0.035,-0.315,0.113),Vector3(side*0.035,-0.329,0.121)], [0.098,0.097], 0.094, "#8d7e61", 16)
	# A shaped knuckle plane and visible thumb replace the round mitten.
	_builder.loft(parent, "HandPalm", [[-0.397,0.041,0.034,side*0.035,0.155],[-0.375,0.059,0.047,side*0.035,0.150],[-0.335,0.049,0.043,side*0.035,0.140]], _skin, 16)
	if side > 0:
		for finger: int in range(4):
			var x: float = side*0.035-0.038+float(finger)*0.023
			_builder.strand(parent, "RelaxedFinger", [Vector3(x,-0.373,0.18),Vector3(x,-0.403,0.188),Vector3(x,-0.411,0.166)], [0.013,0.012,0.009], 0.013, _skin, 8)
		_builder.strand(parent, "RelaxedThumb", [Vector3(side*0.035-0.048,-0.355,0.151),Vector3(side*0.035-0.066,-0.384,0.176),Vector3(side*0.035-0.052,-0.40,0.184)], [0.019,0.017,0.012], 0.018, _skin, 8)

func _build_head(parent: Node3D) -> void:
	var face: MeshInstance3D = _builder.loft(parent, "SculptedFace", _builder.face_rings(), _skin, 48)
	_shade_face(face)
	for side: int in [-1,1]:
		_builder.loft(parent, "SculptedEar", [[-0.13,0.022,0.019,side*0.267,-0.007],[-0.09,0.046,0.033,side*0.277,-0.005],[-0.028,0.032,0.026,side*0.271,-0.004]], _skin, 16)
		_builder.strand(parent, "EarInnerFold", [Vector3(side*0.29,-0.05,0.016),Vector3(side*0.303,-0.088,0.020),Vector3(side*0.285,-0.115,0.019)], [0.005,0.008,0.004], 0.005, "#aa8f78", 6)
		var x: float = side*0.112
		var y: float = 0.024
		_builder.face_patch(parent, "ReadableAlmondEye", [Vector2(x-0.077,y+0.001),Vector2(x-0.045,y+0.033),Vector2(x+0.035,y+0.039),Vector2(x+0.077,y+0.006),Vector2(x+0.043,y-0.019),Vector2(x-0.031,y-0.018)], "#ece0c7", 0.007)
		_builder.face_oval(parent, "WarmBrownIris", Vector2(x,y+0.006), Vector2(0.027,0.027), "#69503a", 0.011, 24)
		_builder.face_oval(parent, "DarkPupil", Vector2(x,y+0.007), Vector2(0.014,0.024), "#292722", 0.014, 20)
		_builder.face_oval(parent, "EyeSmallLight", Vector2(x-0.009,y+0.019), Vector2(0.007,0.008), "#e9e3cb", 0.017, 10)
		_builder.face_patch(parent, "DefinedUpperLid", [Vector2(x-0.080,y),Vector2(x-0.044,y+0.041),Vector2(x+0.037,y+0.046),Vector2(x+0.082,y+0.004),Vector2(x+0.037,y+0.033),Vector2(x-0.041,y+0.030)], "#4b3a2c", 0.018)
		_builder.face_patch(parent, "BroadBrow", [Vector2(x-0.074,0.103),Vector2(x-0.036,0.124 if _brute else 0.119),Vector2(x+0.050,0.112),Vector2(x+0.071,0.092),Vector2(x+0.015,0.101),Vector2(x-0.038,0.108)], _hair, 0.014)
		_builder.face_patch(parent, "CheekPlane", [Vector2(side*0.14,-0.066),Vector2(side*0.228,-0.056),Vector2(side*0.22,-0.091),Vector2(side*0.16,-0.109)], "#baa084" if _brute else "#c4ad90", 0.002)
	# A closed wedge has a real bridge, tip and nostril plane from three views.
	_builder.make_mesh(parent, "VolumetricNose", [Vector3(0,0.035,0.244),Vector3(-0.031,-0.069,0.241),Vector3(-0.016,-0.077,0.282),Vector3(0,0.035,0.244),Vector3(-0.016,-0.077,0.282),Vector3(0.015,-0.077,0.283),Vector3(0,0.035,0.244),Vector3(0.015,-0.077,0.283),Vector3(0.031,-0.068,0.242),Vector3(-0.031,-0.069,0.241),Vector3(0.031,-0.068,0.242),Vector3(0.015,-0.077,0.283),Vector3(-0.031,-0.069,0.241),Vector3(0.015,-0.077,0.283),Vector3(-0.016,-0.077,0.282)], "#c4aa8d")
	_builder.face_patch(parent, "MouthLine", [Vector2(-0.044,-0.146),Vector2(-0.013,-0.145),Vector2(0.014,-0.148),Vector2(0.043,-0.145),Vector2(0.037,-0.154),Vector2(-0.034,-0.154)], "#81624f", 0.008)
	_builder.face_patch(parent, "LowerLipPlane", [Vector2(-0.032,-0.158),Vector2(0.031,-0.158),Vector2(0.018,-0.169),Vector2(-0.019,-0.169)], "#c6a58a", 0.008)
	if _brute:
		_builder.face_patch(parent, "ShortChinBeard", [Vector2(-0.122,-0.184),Vector2(-0.080,-0.243),Vector2(0,-0.268),Vector2(0.080,-0.243),Vector2(0.122,-0.184),Vector2(0.061,-0.214),Vector2(-0.061,-0.214)], "#76614d", 0.006)
		for side: int in [-1,1]:
			_builder.face_patch(parent, "ShortMoustache", [Vector2(side*0.009,-0.113),Vector2(side*0.056,-0.119),Vector2(side*0.070,-0.136),Vector2(side*0.014,-0.129)], "#5e4b3a", 0.006)
	_build_hair(parent)
	if _archer:
		_build_hat(parent)

func _build_hair(parent: Node3D) -> void:
	_builder.loft(parent, "FittedHairCrown", [[0.155,0.28,0.244,0,-0.009],[0.235,0.245,0.207,0,-0.015],[0.30,0.16,0.14,0,-0.018],[0.343,0.025,0.024,0,-0.018]], _hair, 32)
	if _brute:
		_builder.loft(parent, "WideClothHeadwrap", [[0.135,0.292,0.257,0,-0.009],[0.172,0.293,0.255,0,-0.010],[0.193,0.278,0.244,0,-0.013]], "#7f715a", 32)
		_builder.loft(parent, "HeadwrapRolledEdge", [[0.135,0.294,0.260,0,-0.010],[0.147,0.296,0.260,0,-0.010]], "#ad9c7a", 32)
		_builder.strand(parent, "ClothKnot", [Vector3(0.22,0.17,-0.18),Vector3(0.30,0.10,-0.21),Vector3(0.27,-0.015,-0.23)], [0.046,0.046,0.020], 0.02, "#8b7b5e", 8)
		return
	for side: int in [-1,1]:
		_builder.strand(parent, "TempleHairLock", [Vector3(side*0.21,0.235,0.12),Vector3(side*0.255,0.13,0.17),Vector3(side*0.26,-0.07,0.125),Vector3(side*0.232,-0.16,0.075)], [0.035,0.049,0.033,0.003], 0.028, _hair, 10)
		_builder.strand(parent, "BrowSweptLock", [Vector3(side*0.07,0.316,0.095),Vector3(side*0.13,0.25,0.21),Vector3(side*0.19,0.14,0.214)], [0.025,0.051,0.005], 0.022, _hair, 10)
		_builder.curved_strip(parent, "HairBroadLight", [Vector3(side*0.07,0.319,0.108),Vector3(side*0.13,0.253,0.235),Vector3(side*0.185,0.147,0.233)], [0.006,0.010,0.002], "#5d4c3b")
	_builder.loft(parent, "ShortTopknot", [[0.26,0.08,0.066,0,-0.13],[0.34,0.09,0.074,0,-0.14],[0.39,0.035,0.029,0,-0.14]], _hair, 24)
	_builder.loft(parent, "ClothHairTie", [[0.285,0.091,0.078,0,-0.14],[0.315,0.095,0.079,0,-0.14]], "#87655b", 24)
	_builder.strand(parent, "TiedBackHair", [Vector3(0,0.34,-0.14),Vector3(0.065,0.24,-0.26),Vector3(0.04,0.018,-0.30),Vector3(-0.04,-0.12,-0.26)], [0.05,0.071,0.052,0.003], 0.035, _hair, 10)

func _build_hat(parent: Node3D) -> void:
	# A raised front brim exposes eyes from the actual elevated battlefield view.
	# It retains the previous crown height; the back remains low for the silhouette.
	var vertices: Array = []
	for row: int in range(3):
		for index: int in range(48):
			var angle: float = TAU*float(index)/48.0
			var next: float = TAU*float(index+1)/48.0
			var a: Vector3 = _hat_point(row,angle)
			var b: Vector3 = _hat_point(row,next)
			var c: Vector3 = _hat_point(row+1,next)
			var d: Vector3 = _hat_point(row+1,angle)
			vertices.append_array([a,b,c,a,c,d])
	_builder.make_mesh(parent, "RaisedFrontWovenHat", vertices, "#a7946c")
	for index: int in range(24):
		var angle: float = TAU*float(index)/24.0
		_builder.strand(parent, "BambooHatRib", [_hat_point(0,angle)+Vector3.UP*0.004,_hat_point(1,angle)+Vector3.UP*0.004,_hat_point(2,angle)+Vector3.UP*0.004,_hat_point(3,angle)+Vector3.UP*0.004], [0.004,0.006,0.006,0.005], 0.004, "#c6b286" if index%2==0 else "#7f704f", 6)
	var brim: Array = []
	for index: int in range(49):
		brim.append(_hat_point(3,TAU*float(index)/48.0))
	var widths: Array = []
	widths.resize(brim.size())
	widths.fill(0.012)
	_builder.strand(parent, "BoundHatRim", brim, widths, 0.009, "#776346", 8)
	for side: int in [-1,1]:
		_builder.strand(parent, "HatCord", [Vector3(side*0.24,0.20,0.08),Vector3(side*0.22,-0.14,0.15),Vector3(side*0.065,-0.272,0.16)], [0.006,0.006,0.005], 0.005, "#796044", 6)
	_builder.bevel_box(parent, "HatCordKnot", Vector3(0,-0.27,0.167), Vector3(0.065,0.033,0.020), "#8e7852")

func _hat_point(row: int, angle: float) -> Vector3:
	var radius: float = [0.025,0.16,0.31,0.39][row]
	var height: float = [0.36,0.32,0.235,0.205][row]
	var front_raise: float = maxf(0,cos(angle))*0.125*float(row)/3.0
	return Vector3(sin(angle)*radius,height+front_raise,cos(angle)*radius*0.88-0.028)

func _build_weapon(parent: Node3D) -> void:
	var grip_radius: float = 0.036 if _brute else 0.022
	# Four closed fingers and the opposing thumb wrap the grip in weapon space.
	for finger: int in range(4):
		var y: float = -0.033+float(finger)*0.021
		_builder.strand(parent, "ClosedGripFinger", [Vector3(-0.043,y,-0.015),Vector3(-0.043,y,grip_radius*0.72),Vector3(-0.012,y,grip_radius+0.012),Vector3(0.026,y,grip_radius*0.70)], [0.014,0.015,0.014,0.010], 0.014, _skin, 8)
	_builder.strand(parent, "OpposingGripThumb", [Vector3(0.047,0.033,-0.025),Vector3(0.045,0.018,0.015),Vector3(0.013,0.009,grip_radius+0.019),Vector3(-0.010,0.004,grip_radius+0.020)], [0.020,0.019,0.016,0.012], 0.018, _skin, 8)
	if _brute:
		_builder.beam(parent, "TaperedHardwoodStaff", Vector3(0,-0.27,0), Vector3(0,0.79,0),0.033,"#765039",0.045,20)
		for index: int in range(7):
			var y: float = -0.12+float(index)*0.031
			_builder.loft(parent, "LeatherGripWrap", [[y,0.038,0.038,0,0],[y+0.019,0.039,0.039,0,0]], "#b29a70" if index%2==0 else "#8a7658",16)
		_builder.loft(parent, "HeavyStaffCap", [[0.73,0.048,0.048,0,0],[0.80,0.049,0.049,0,0],[0.815,0.041,0.041,0,0]], "#a08b60",20)
		for angle: float in [0.0,1.5,3.4,4.8]:
			_builder.strand(parent,"WoodGrainPlane",[Vector3(sin(angle)*0.034,0.16,cos(angle)*0.034),Vector3(sin(angle)*0.042,0.43,cos(angle)*0.042),Vector3(sin(angle)*0.045,0.69,cos(angle)*0.045)],[0.003,0.004,0.002],0.002,"#a37b50",6)
	elif _archer:
		_build_bow(parent)
	else:
		_build_sabre(parent)

func _build_bow(parent: Node3D) -> void:
	var points: Array = []
	var widths: Array = []
	for index: int in range(17):
		var angle: float = -PI*0.5+PI*float(index)/16.0
		points.append(Vector3(0.185*cos(angle)-0.185,0.397*sin(angle),0.016))
		widths.append(0.012+sin(PI*float(index)/16.0)*0.012)
	_builder.strand(parent,"LaminatedBambooBow",points,widths,0.019,"#917049",12)
	var inner: Array = []
	for point: Vector3 in points:
		inner.append(point+Vector3(-0.010,0,0.017))
	_builder.strand(parent,"PaleBowLamination",inner,widths,0.004,"#c0a36e",8)
	_builder.beam(parent,"TautBowString",Vector3(-0.185,-0.397,0.016),Vector3(-0.185,0.397,0.016),0.003,"#e1d1a4",-1.0,8)
	for index: int in range(5):
		var y: float = -0.037+float(index)*0.018
		_builder.bevel_box(parent,"BowHandleWrap",Vector3(0,y,0.017),Vector3(0.059,0.013,0.047),"#66503c")

func _build_sabre(parent: Node3D) -> void:
	_builder.beam(parent,"BoundSabreGrip",Vector3(0,-0.115,0),Vector3(0,0.032,0),0.025,"#55483d",-1.0,16)
	for index: int in range(6):
		var y: float=-0.105+float(index)*0.022
		_builder.loft(parent,"DiagonalGripWrap",[[y,0.026,0.026,0,0],[y+0.011,0.026,0.026,0,0]],"#9d8970",12)
	var steel: Node3D = _part(parent,"RefinedSabreSteel",true)
	_builder.loft(steel,"OvalBronzeGuard",[[0.029,0.095,0.039,0,0],[0.050,0.10,0.043,0,0],[0.066,0.085,0.035,0,0]],"#a79161",20)
	# Curved, widening single-edged profile makes the blade read as a dao.
	var edge: Array=[Vector3(-0.026,0.066,0.0),Vector3(-0.042,0.30,0.0),Vector3(-0.057,0.52,0.0),Vector3(-0.037,0.65,0.0),Vector3(0.013,0.72,0.0)]
	var back: Array=[Vector3(0.026,0.066,0.0),Vector3(0.031,0.30,0.0),Vector3(0.025,0.52,0.0),Vector3(0.024,0.65,0.0),Vector3(0.013,0.72,0.0)]
	_builder.panel(steel,"SingleEdgedSabreFace",edge,back,"#b7b8ab")
	var ridge: Array=[]
	for index: int in range(back.size()):
		ridge.append((edge[index]+back[index])*0.5+Vector3(0,0,0.012))
	_builder.panel(steel,"RaisedBladeSpine",ridge,back,"#88948e")
	_builder.panel(steel,"BevelledCuttingEdge",edge,ridge,"#d7d3bc")
	_builder.beam(parent,"GripPommel",Vector3(0,-0.132,0),Vector3(0,-0.108,0),0.034,"#a28a5e",0.031,12)
	_builder.strand(parent,"SwordKnotCord",[Vector3(0,-0.13,0),Vector3(0.052,-0.17,0.013),Vector3(0.058,-0.27,0.016)],[0.008,0.010,0.009],0.007,"#9b7562",6)

func _build_quiver(parent: Node3D) -> void:
	var quiver:=_part(parent,"RefinedBackQuiver")
	quiver.position=Vector3(0.17,0.96,-0.23)
	quiver.rotation.z=0.20
	_builder.loft(quiver,"ClosedLeatherArrowCase",[[-0.23,0.072,0.062,0,0],[-0.20,0.083,0.069,0,0],[0.17,0.091,0.072,0,0],[0.22,0.104,0.080,0,0]],"#6d513a",24)
	_builder.loft(quiver,"ArrowCaseRolledRim",[[0.18,0.105,0.082,0,0],[0.23,0.107,0.084,0,0]],"#ab9068",24)
	_builder.loft(quiver,"ArrowCaseFootBinding",[[-0.23,0.078,0.068,0,0],[-0.188,0.089,0.074,0,0]],"#ad9570",24)
	for index: int in range(5):
		var angle: float=TAU*float(index)/5.0
		var x: float=sin(angle)*0.058
		var z: float=cos(angle)*0.043
		var top: float=0.44+float(index%3)*0.025
		_builder.beam(quiver,"VisibleArrowShaft",Vector3(x,0.16,z),Vector3(x,top,z),0.006,"#c0a679",-1.0,8)
		for side: int in [-1,1]:
			_builder.polygon(quiver,"FeatherFletching",[Vector3(x,top-0.012,z),Vector3(x+side*0.032,top+0.008,z),Vector3(x+side*0.031,top-0.065,z),Vector3(x,top-0.097,z)],"#c7c3a8" if index%2==0 else "#a9ad94")
		_builder.beam(quiver,"ArrowNock",Vector3(x,top-0.012,z),Vector3(x,top+0.016,z),0.008,"#76583b",-1.0,8)

func _build_scabbard(parent: Node3D) -> void:
	var scabbard:=_part(parent,"RefinedHipScabbard")
	scabbard.position=Vector3(0.22,0.77,-0.043)
	scabbard.rotation.z=-0.45
	_builder.loft(scabbard,"CurvedSabreSheath",[[-0.55,0.020,0.018,-0.022,0],[-0.48,0.037,0.022,-0.013,0],[-0.25,0.038,0.024,0,0],[0,0.032,0.024,0,0]],"#4d4c49",16)
	for y: float in [-0.48,-0.06]:
		_builder.loft(scabbard,"SheathBrassFitting",[[y,0.040,0.027,0,0],[y+0.038,0.041,0.027,0,0]],"#a18d65",16)

func _shade_face(mesh: MeshInstance3D) -> void:
	var arrays: Array=mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	for index: int in range(vertices.size()):
		var point: Vector3=vertices[index]
		var amount: float=lerpf(0.16,0.0,clampf((point.y+0.27)/0.54,0.0,1.0))
		amount+=0.045 if point.z<0.04 else 0.0
		colors[index]=colors[index].darkened(amount)
	arrays[Mesh.ARRAY_COLOR]=colors
	var refined:=ArrayMesh.new()
	refined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.mesh=refined

func _merge_parts() -> void:
	var matte:=StandardMaterial3D.new()
	matte.vertex_color_use_as_albedo=true
	matte.vertex_color_is_srgb=true
	matte.roughness=0.91
	matte.metallic_specular=0.18
	matte.cull_mode=BaseMaterial3D.CULL_DISABLED
	var metal:=matte.duplicate() as StandardMaterial3D
	metal.roughness=0.55
	metal.metallic=0.23
	metal.metallic_specular=0.36
	# Merge only direct children. Each animation pivot and moving weapon retains
	# its exact original local transform; there is no skeleton or root remapping.
	for part: Node3D in _parts:
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sources: Array[MeshInstance3D]=[]
		for child: Node in part.get_children():
			var source:=child as MeshInstance3D
			if source==null or source.mesh==null:
				continue
			sources.append(source)
			var arrays: Array=source.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			_triangle_count+=count/3
			for cursor: int in range(count):
				var index: int=indices[cursor] if not indices.is_empty() else cursor
				surface.set_color(colors[index])
				surface.set_normal((source.basis*normals[index]).normalized())
				surface.add_vertex(source.transform*vertices[index])
		if sources.is_empty():
			continue
		surface.index()
		var merged:=MeshInstance3D.new()
		merged.name="MergedRefinedSurface"
		merged.mesh=surface.commit()
		merged.material_override=metal if part in _metal_parts else matte
		part.add_child(merged)
		meshes.append(merged)
		for source: MeshInstance3D in sources:
			source.free()
	_builder.meshes.clear()

func set_enabled(enabled: bool) -> void:
	for part: Node3D in _parts:
		part.visible=enabled

func audit() -> Dictionary:
	return {"mesh_count":meshes.size(),"triangles":_triangle_count,"part_count":_parts.size(),"authored":"local procedural geometry","pivot_contract":"original enemy body/head/limb/weapon pivots","visible_mesh_count":meshes.filter(func(mesh: MeshInstance3D) -> bool: return mesh.is_visible_in_tree()).size()}

## Opt-in shell for the articulated staff sample. The existing build path and
## old enemy pivots remain untouched; limbs and weapon are supplied by its rig.
func build_articulated_shell(pivots: Dictionary, palette: Dictionary) -> void:
	_builder = CharacterMesh.new()
	_cloth = str(palette.robe)
	_dark = str(palette.shadow)
	_light = "#aa9676"
	_skin = str(palette.skin)
	_brute = true
	_archer = false
	_build_torso(_part(pivots.body, "ArticulatedRefinedClothing"))
	_build_head(_part(pivots.head, "ArticulatedRefinedHead"))
	_merge_parts()
