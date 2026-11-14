extends Node2D
## Soft skeleton-based cast silhouettes, clipped to the authored stone shore.
const SHADER = preload("res://addons/cultivation_mode/dock_corner_shadow.gdshader")
const MASK = preload("res://assets/masks/dock_shadows/ground.png")
const MASK_SOURCE = "res://assets/masks/dock_shadows/source.json"
const CONFIG = "res://assets/data/dock-corner-shadows.json"
var _config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
var _patches: Dictionary = {}
var records: Dictionary = {}

func _project(point: Vector3) -> Vector2:
	return Vector2(640.0+point.x*80.0,360.0+point.z*sin(PI/4)*80.0)

func _floor_point(point: Vector3, ray: Vector3, foot: Vector2) -> Vector2:
	var grounded := point-ray*(maxf(point.y,0.0)/minf(ray.y,-0.12))
	var delta := _project(grounded)-foot
	return foot+delta.limit_length(float(_config.max_length))

func present(stage: Node, profile: String) -> void:
	for id: String in stage.get("actors"):
		var actor: Node3D = stage.get("actors")[id]
		if not bool(actor.get("available")):
			continue
		if not _patches.has(id):
			var patch := ColorRect.new()
			patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var material := ShaderMaterial.new()
			material.shader = SHADER
			material.set_shader_parameter("ground_mask",MASK)
			material.set_shader_parameter("softness",float(_config.softness))
			patch.material = material
			add_child(patch)
			_patches[id] = patch
		var foot := _project(actor.position)
		var ray: Vector3 = -(stage.get("sun") as DirectionalLight3D).transform.basis.z
		var opacity: float = float(_config.opacity.get(profile,0.28))
		var source := "sun"
		var lamp: OmniLight3D
		var distance := INF
		var lamp_weight := 0.0
		if bool(stage.get("lighting_enabled")) and float(stage.get("lamp_strength"))>0.0:
			for candidate: OmniLight3D in stage.get("lamps"):
				var flat := Vector2(actor.position.x-candidate.position.x,actor.position.z-candidate.position.z).length()
				if flat<distance and flat<candidate.omni_range*0.85:
					lamp = candidate
					distance = flat
		if lamp!=null:
			source = str(lamp.name)
			lamp_weight = (1.0-smoothstep(lamp.omni_range*0.35,lamp.omni_range*0.85,distance))*clampf(float(stage.get("lamp_strength")),0.0,1.0)
			opacity = lerpf(opacity,maxf(opacity,0.30*(1.0-distance/(lamp.omni_range*1.1))),lamp_weight)
		var skeleton := actor.get("skeleton") as Skeleton3D
		var points := PackedVector4Array()
		var radii := PackedFloat32Array()
		var bounds := Rect2(foot,Vector2.ONE)
		for part: Array in _config.parts:
			var pair: Array[Vector2] = []
			for name: String in [str(part[0]),str(part[1])]:
				var bone := skeleton.find_bone(name)
				if bone<0:
					break
				var point: Vector3 = actor.transform*actor.call("_bone_position",bone)
				if name=="head":
					point.y += 0.12
				var projected := _floor_point(point,ray,foot)
				if lamp!=null:
					projected = projected.lerp(_floor_point(point,point-lamp.position,foot),lamp_weight)
				pair.append(projected)
				bounds = bounds.expand(projected)
			if pair.size()!=2:
				continue
			points.append(Vector4(pair[0].x,pair[0].y,pair[1].x,pair[1].y))
			radii.append(float(part[2]))
		bounds = bounds.grow(13.0)
		var count := points.size()
		points.resize(16)
		radii.resize(16)
		var patch: ColorRect = _patches[id]
		patch.position = bounds.position
		patch.size = bounds.size
		patch.material.set_shader_parameter("origin",bounds.position)
		patch.material.set_shader_parameter("extent",bounds.size)
		patch.material.set_shader_parameter("segments",points)
		patch.material.set_shader_parameter("radii",radii)
		patch.material.set_shader_parameter("count",count)
		patch.material.set_shader_parameter("opacity",opacity*(0.82 if id=="keeper" else 1.0))
		records[id] = {"foot":foot,"bounds":bounds,"source":source,"lamp_weight":lamp_weight,"opacity":opacity,"segments":count}
