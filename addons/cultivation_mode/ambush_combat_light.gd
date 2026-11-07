extends Node3D
## Presentation only. The stage owns hit timing and all battle settlement.
## Modes 1 and 2 share one envelope; their only difference is Omni shadows.
## One local clock, no Tween/Timer, and no modifications to actor materials.

const CONFIG_PATH := "res://assets/art/mountain_ambush/environment/combat-lighting.json"
const ARC_RETREAT: float = 0.18
const ENVIRONMENT_PROPERTIES: Array[StringName] = [
	&"tonemap_exposure", &"glow_enabled", &"glow_intensity", &"glow_bloom",
	&"glow_hdr_threshold", &"glow_hdr_scale", &"glow_hdr_luminance_cap",
]
const ARC_SHADER_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 arc_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	ALBEDO = arc_color.rgb;
	ALPHA = opacity * sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
}
"""

var _environment: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _config: Dictionary = {}
var _configured := false
var _mode: int = 2
var _active := false
var _phase := "idle"
var _phase_time := 0.0
var _skill_id := ""
var _skill: Dictionary = {}
var _saved: Dictionary = {}
var _recovery: Dictionary = {}
var _fx: Node3D
var _point: OmniLight3D
var _arc_root: Node3D
var _arcs: Array[MeshInstance3D] = []
var _arc_materials: Array[ShaderMaterial] = []
var _arc_shader: Shader
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _forward := Vector3.FORWARD
var _side := Vector3.RIGHT
var _yaw := 0.0
var _arc_alpha := 0.0
## Matches the stage's attack/recoil clock; config durations stay source seconds.
var action_playback_speed: float = 1.0
var windup_wall_seconds: float = 0.0
var recovery_wall_seconds: float = 0.0
var _impact_hold_seconds: float = -1.0
var _impact_wall_elapsed: float = 0.0
var _draw_arc := true


func setup(environment: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D) -> void:
	cancel()
	_environment = environment
	_sun = sun
	_fill = fill
	_configured = false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_error("Combat lighting configuration is missing or invalid")
		return
	_config = parsed
	for section: String in ["timing", "sun", "exposure", "light", "glow", "arc", "skills"]:
		if not _config.get(section) is Dictionary:
			push_error("Combat lighting configuration lacks " + section)
			return
	if _environment == null or not is_instance_valid(_sun) or not is_instance_valid(_fill):
		push_error("Combat lighting requires the stage environment, sun and fill")
		return
	_mode = clampi(int(_config.get("default_mode", 2)), 0, 2)
	_configured = true


func set_mode(mode: int) -> bool:
	if _active or mode < 0 or mode > 2:
		return false
	_mode = mode
	return true


func begin_attack(skill_id: String, from: Vector3, to: Vector3, impact_hold_seconds: float = -1.0, draw_arc: bool = true) -> void:
	# Repeated presentation requests cannot accumulate lights or stale baselines.
	cancel()
	if not _configured or not from.is_finite() or not to.is_finite():
		return
	_capture_baseline()
	_skill_id = skill_id
	_draw_arc = draw_arc
	_skill = (_config.skills as Dictionary).get(skill_id, {})
	_from = from
	_to = to
	_forward = Vector3(to.x - from.x, 0.0, to.z - from.z)
	if _forward.length_squared() < 0.000001:
		_forward = Vector3(0.0, 0.0, 1.0)
	else:
		_forward = _forward.normalized()
	_side = Vector3.UP.cross(_forward).normalized()
	_yaw = atan2(_forward.x, _forward.z)
	_active = true
	_phase = "windup"
	_phase_time = 0.0
	_impact_hold_seconds = impact_hold_seconds
	_impact_wall_elapsed = 0.0
	if _mode != 0:
		_build_fx()
		_apply_envelope(0.0, false)
	set_process(true)


func impact() -> void:
	if not _active or _phase == "recovery":
		return
	_phase = "impact"
	_phase_time = 0.0
	_impact_wall_elapsed = 0.0
	if _mode != 0:
		_apply_envelope(1.0, true)
	# A comparison preview holds this peak until recover(); a real attack uses
	# the same peak and an authored hold before the automatic recovery.


func recover() -> void:
	if not _active or _phase == "recovery":
		return
	_phase = "recovery"
	_phase_time = 0.0
	_recovery = {
		"sun_energy": _sun.light_energy if is_instance_valid(_sun) else 0.0,
		"exposure": _environment.tonemap_exposure if _environment != null else 1.0,
		"glow_intensity": _environment.glow_intensity if _environment != null else 0.0,
		"light_energy": _point.light_energy if is_instance_valid(_point) else 0.0,
		"arc_alpha": _arc_alpha,
	}


func cancel() -> void:
	set_process(false)
	_restore_baseline()
	_clear_fx()
	_active = false
	_phase = "idle"
	_phase_time = 0.0
	_arc_alpha = 0.0
	_saved.clear()
	_recovery.clear()
	_impact_hold_seconds = -1.0
	_impact_wall_elapsed = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	var step_rate: float = action_playback_speed
	if _phase == "windup" and windup_wall_seconds > 0.0:
		step_rate = float(_config.timing.windup_seconds) / windup_wall_seconds
	elif _phase == "recovery" and recovery_wall_seconds > 0.0:
		step_rate = float(_config.timing.recovery_seconds) / recovery_wall_seconds
	_phase_time += maxf(delta, 0.0) * step_rate
	if _phase == "impact" and _impact_hold_seconds >= 0.0:
		_impact_wall_elapsed += maxf(delta, 0.0)
		if _impact_wall_elapsed >= _impact_hold_seconds:
			recover()
		return
	if _phase == "recovery":
		var duration: float = clampf(float(_config.timing.recovery_seconds), 0.01, 0.20)
		var progress: float = clampf(_phase_time / duration, 0.0, 1.0)
		if progress >= 1.0:
			cancel()
		elif _mode != 0:
			_apply_recovery(smoothstep(0.0, 1.0, progress))
	elif _phase == "windup" and _mode != 0:
		var duration: float = maxf(0.01, float(_config.timing.windup_seconds))
		_apply_envelope(smoothstep(0.0, 1.0, clampf(_phase_time / duration, 0.0, 1.0)), false)


func _capture_baseline() -> void:
	var properties: Dictionary = {}
	for property: StringName in ENVIRONMENT_PROPERTIES:
		properties[property] = _environment.get(property)
	_saved = {"environment": properties,
		"sun_energy": _sun.light_energy, "sun_visible": _sun.visible,
		"fill_energy": _fill.light_energy, "fill_visible": _fill.visible}


func _restore_baseline() -> void:
	if _saved.is_empty():
		return
	if _environment != null:
		var properties: Dictionary = _saved.environment
		for property: StringName in ENVIRONMENT_PROPERTIES:
			_environment.set(property, properties[property])
	if is_instance_valid(_sun):
		_sun.light_energy = float(_saved.sun_energy)
		_sun.visible = bool(_saved.sun_visible)
	if is_instance_valid(_fill):
		_fill.light_energy = float(_saved.fill_energy)
		_fill.visible = bool(_saved.fill_visible)


func _build_fx() -> void:
	_fx = Node3D.new()
	_fx.name = "TransientCombatLight"
	add_child(_fx)
	_point = OmniLight3D.new()
	_point.name = "SkillPointLight"
	_point.light_color = Color(str(_skill.get("light_color", _config.light.color)))
	_point.light_energy = 0.0
	_point.light_specular = float(_config.light.specular)
	_point.light_bake_mode = Light3D.BAKE_DISABLED
	_point.omni_range = float(_config.light.range)
	_point.omni_attenuation = float(_config.light.attenuation)
	_point.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	_point.shadow_bias = float(_config.light.shadow_bias)
	_point.shadow_normal_bias = float(_config.light.shadow_normal_bias)
	_point.shadow_enabled = _mode == 2
	_fx.add_child(_point)
	_arc_root = Node3D.new()
	_arc_root.name = "SkillLightArc"
	_fx.add_child(_arc_root)
	var radius: float = float(_config.arc.radius) * float(_skill.get("radius_multiplier", 1.0))
	if _draw_arc:
		_make_arc("WarmArc", radius, float(_config.arc.width), Color(str(_skill.get("arc_color", _config.arc.color))), 0.0)
		_make_arc("CoolCore", radius, float(_config.arc.core_width), Color(str(_skill.get("core_color", _config.arc.core_color))), 0.004)


func _make_arc(node_name: String, radius: float, width: float, color: Color, lift: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = clampi(int(_config.arc.segments), 8, 48)
	var span: float = deg_to_rad(float(_config.arc.span_degrees))
	# Read the current camera only. Width lies across its sightline rather than
	# along the flat arc's radius, which can collapse to a subpixel edge.
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var view_direction := Vector3(4.1, 11.8, 15.6).normalized()
	if camera != null:
		var camera_in_helper: Vector3 = global_transform.affine_inverse() * camera.global_position
		view_direction = (camera_in_helper - (_from + Vector3.UP * float(_config.arc.height))).normalized()
	var hit_basis := Basis.from_euler(Vector3(deg_to_rad(float(_config.arc.tilt_degrees)), _yaw + 0.16, 0.0))
	var local_view: Vector3 = hit_basis.inverse() * view_direction
	for index: int in range(segments):
		var u0: float = float(index) / float(segments)
		var u1: float = float(index + 1) / float(segments)
		var angle0: float = lerpf(-span * 0.5, span * 0.5, u0)
		var angle1: float = lerpf(-span * 0.5, span * 0.5, u1)
		var taper0: float = sin(u0 * PI)
		var taper1: float = sin(u1 * PI)
		var centre0 := Vector3(sin(angle0) * radius, lift, cos(angle0) * radius)
		var centre1 := Vector3(sin(angle1) * radius, lift, cos(angle1) * radius)
		var across0: Vector3 = Vector3(cos(angle0), 0.0, -sin(angle0)).cross(local_view).normalized()
		var across1: Vector3 = Vector3(cos(angle1), 0.0, -sin(angle1)).cross(local_view).normalized()
		var a: Vector3 = centre0 - across0 * width * taper0
		var b: Vector3 = centre0 + across0 * width * taper0
		var c: Vector3 = centre1 + across1 * width * taper1
		var d: Vector3 = centre1 - across1 * width * taper1
		for corner: int in range(6):
			var position_in_arc: Vector3 = [a, b, c, a, c, d][corner]
			# The shader derives taper once from UV, independently of the
			# StandardMaterial vertex-color/alpha chain. Keep RGB and opacity
			# separate so a bright, narrow edge survives the LDR render path.
			var u: float = u0 if corner in [0, 1, 3] else u1
			surface.set_uv(Vector2(u, 1.0 if corner in [1, 2, 4] else 0.0))
			surface.set_normal(Vector3.UP)
			surface.add_vertex(position_in_arc)
	if _arc_shader == null:
		_arc_shader = Shader.new()
		_arc_shader.code = ARC_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _arc_shader
	material.set_shader_parameter("arc_color", color)
	material.set_shader_parameter("opacity", 0.0)
	# Both thin surfaces retain normal depth testing against actors. The cool
	# core blends after its warm edge; neither can draw through a figure.
	material.render_priority = 1 if node_name == "CoolCore" else 0
	var arc := MeshInstance3D.new()
	arc.name = node_name
	arc.mesh = surface.commit()
	arc.custom_aabb = arc.mesh.get_aabb().grow(0.03)
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_root.add_child(arc)
	_arcs.append(arc)
	_arc_materials.append(material)


func _apply_envelope(progress: float, is_hit: bool) -> void:
	if not is_instance_valid(_point) or _saved.is_empty():
		return
	var sun_multiplier: float = float(_config.sun.impact_multiplier) if is_hit else lerpf(1.0, float(_config.sun.windup_multiplier), progress)
	var exposure_multiplier: float = float(_config.exposure.impact_multiplier) if is_hit else lerpf(1.0, float(_config.exposure.windup_multiplier), progress)
	if is_instance_valid(_sun):
		_sun.light_energy = float(_saved.sun_energy) * sun_multiplier
	_environment.tonemap_exposure = float(_saved.environment[&"tonemap_exposure"]) * exposure_multiplier
	_point.light_energy = (float(_config.light.impact_energy) if is_hit else lerpf(0.04, float(_config.light.windup_energy), progress)) * float(_skill.get("energy_multiplier", 1.0))
	_point.visible = true
	var forward_offset: float = float(_config.light.impact_forward_offset) if is_hit else lerpf(float(_config.light.forward_offset), float(_config.light.impact_forward_offset), progress)
	_point.position = _from + _forward * forward_offset + _side * float(_config.light.side_offset) + Vector3.UP * float(_config.light.height)
	# Keep the arc in the sword's approach space, clear of the adjacent victim's
	# chest. Retain ordinary depth testing instead of drawing over its body.
	_arc_root.position = _from - _forward * ARC_RETREAT + Vector3.UP * float(_config.arc.height)
	_arc_root.rotation = Vector3(deg_to_rad(float(_config.arc.tilt_degrees)), _yaw + (0.16 if is_hit else lerpf(-0.52, 0.16, progress)), 0.0)
	_set_arc_alpha(float(_config.arc.impact_alpha) if is_hit else float(_config.arc.windup_alpha) * progress)
	_apply_glow(float(_config.glow.impact_intensity) if is_hit else float(_config.glow.windup_intensity) * progress)


func _apply_glow(intensity: float) -> void:
	if not bool(_config.glow.enabled):
		return
	# Compatibility uses screen blending and ignores glow_strength/levels.
	# Keep threshold near the LDR ceiling and bloom zero: no scene-wide haze.
	_environment.glow_enabled = true
	_environment.glow_intensity = intensity
	_environment.glow_bloom = float(_config.glow.bloom)
	_environment.glow_hdr_threshold = float(_config.glow.threshold)
	_environment.glow_hdr_scale = float(_config.glow.scale)
	_environment.glow_hdr_luminance_cap = float(_config.glow.luminance_cap)


func _apply_recovery(progress: float) -> void:
	if is_instance_valid(_sun):
		_sun.light_energy = lerpf(float(_recovery.sun_energy), float(_saved.sun_energy), progress)
	_environment.tonemap_exposure = lerpf(float(_recovery.exposure), float(_saved.environment[&"tonemap_exposure"]), progress)
	if is_instance_valid(_point):
		_point.light_energy = lerpf(float(_recovery.light_energy), 0.0, progress)
	_set_arc_alpha(lerpf(float(_recovery.arc_alpha), 0.0, progress))
	if bool(_config.glow.enabled):
		var baseline_glow: float = float(_saved.environment[&"glow_intensity"]) if bool(_saved.environment[&"glow_enabled"]) else 0.0
		_environment.glow_intensity = lerpf(float(_recovery.glow_intensity), baseline_glow, progress)


func _set_arc_alpha(alpha: float) -> void:
	_arc_alpha = alpha
	for material: ShaderMaterial in _arc_materials:
		material.set_shader_parameter("opacity", alpha)
	for arc: MeshInstance3D in _arcs:
		arc.visible = alpha > 0.001


func _clear_fx() -> void:
	if is_instance_valid(_fx):
		# Immediate destruction avoids a one-frame duplicate light on repeated
		# cancel/begin requests and releases meshes/materials with their nodes.
		_fx.free()
	_fx = null
	_point = null
	_arc_root = null
	_arcs.clear()
	_arc_materials.clear()
	_arc_shader = null


func audit() -> Dictionary:
	var has_light: bool = is_instance_valid(_point)
	var count: int = 0
	if is_instance_valid(_fx):
		for child: Node in _fx.get_children():
			if child is OmniLight3D:
				count += 1
	return {"mode": _mode, "active": _active, "phase": _phase, "phase_seconds": _phase_time, "action_playback_speed": action_playback_speed, "windup_wall_seconds": windup_wall_seconds, "recovery_wall_seconds": recovery_wall_seconds, "impact_hold_seconds": _impact_hold_seconds,
		"skill_id": _skill_id, "configured": _configured, "config": CONFIG_PATH,
		"shadow_enabled": _point.shadow_enabled if has_light else false,
		"light_visible": _point.visible if has_light else false,
		"energy": _point.light_energy if has_light else 0.0,
		"light_position": _point.position if has_light else Vector3.ZERO,
		"light_color": _point.light_color.to_html() if has_light else "",
		"light_range": _point.omni_range if has_light else 0.0,
		"light_count": count,
		"point_light_path": str(_point.get_path()) if has_light and _point.is_inside_tree() else "",
		"sun_energy": _sun.light_energy if is_instance_valid(_sun) else 0.0,
		"sun_visible": _sun.visible if is_instance_valid(_sun) else false,
		"fill_energy": _fill.light_energy if is_instance_valid(_fill) else 0.0,
		"glow_enabled": _environment.glow_enabled if _environment != null else false,
		"glow_intensity": _environment.glow_intensity if _environment != null else 0.0,
		"exposure": _environment.tonemap_exposure if _environment != null else 1.0,
		"arc_visible": _arc_alpha > 0.001 and not _arcs.is_empty(),
		"arc_alpha": _arc_alpha, "arc_mesh_count": _arcs.size(),
		"from": _from, "to": _to}


func _exit_tree() -> void:
	cancel()

func sample_timeline(seconds: float, hit: float, total: float) -> void:
	# Workshop/player absolute sampling; the automatic legacy clock is disabled.
	set_process(false)
	if not _active or _mode == 0:
		return
	if seconds < hit:
		_phase = "windup"
		_phase_time = seconds
		_apply_envelope(smoothstep(0.0, 1.0, clampf(seconds / maxf(hit, 0.01), 0.0, 1.0)), false)
	else:
		_apply_envelope(1.0, true)
		_phase = "impact"
		_phase_time = seconds - hit
		if seconds > hit + 0.08:
			_recovery.clear()
			recover()
			_phase_time = seconds - hit - 0.08
			_apply_recovery(smoothstep(0.0, 1.0, clampf(_phase_time / minf(0.3, maxf(0.01, total - hit - 0.08)), 0.0, 1.0)))
