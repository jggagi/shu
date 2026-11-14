extends Node3D
## Painted resident in the actors' depth pass: people can occlude it naturally.
const ATLAS = preload("res://assets/art/ambient_life/tingyu-cat-desk-v1.png")
const LAYOUT = "res://assets/art/ambient_life/tingyu-cat-desk-layout-v1.json"
var frames: Array = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)).frames
var sprite: Sprite3D
var contact: MeshInstance3D
var point := Vector2.ZERO
var pose := 12
var facing := 1.0
var textures: Array[AtlasTexture] = []

func setup() -> void:
	for frame: Dictionary in frames:
		var region: Array = frame.region
		var atlas := AtlasTexture.new()
		atlas.atlas = ATLAS
		atlas.region = Rect2(region[0],region[1],region[2],region[3])
		textures.append(atlas)
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = true
	sprite.modulate = Color(0.88,0.86,0.79)
	add_child(sprite)
	contact = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.43,0.24)
	contact.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5,0.5)
	fade.fill_to = Vector2(0.5,1.0)
	material.albedo_texture = fade
	material.albedo_color = Color(0.19,0.21,0.16,0.28)
	contact.material_override = material
	contact.position = Vector3(0,0.005,0.02)
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)

func present(stage: Node, state: Dictionary, logical_width: float) -> void:
	point = state.point
	pose = int(state.pose)
	facing = float(state.facing)
	position = stage.logical_to_world(point)
	var frame: Dictionary = frames[pose-8]
	var bounds: Array = frame.opaque_bounds
	var amount := logical_width/float(bounds[2])
	var region: Array = frame.region
	var pivot: Array = frame.pivot
	sprite.texture = textures[pose-8]
	sprite.pixel_size = amount/80.0
	sprite.offset = Vector2(float(region[2])*0.5-float(pivot[0]),float(pivot[1])-float(region[3])*0.5)
	sprite.flip_h = facing<0.0
