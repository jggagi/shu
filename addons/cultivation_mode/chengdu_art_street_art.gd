extends Node
## Three calibrated environment paintings remain attached to original WORLD
## surfaces while the retained camera follows. This helper owns no game state,
## collision, camera, actors, lights, geometry or fallback base materials.

const CONFIG := "res://assets/art/chengdu_art_street/calibration.json"
const VIEW_IDS: Array[String] = ["south", "middle", "lane"]
const DISPLAY := Vector2(1280, 720)
const MAX_GROUND_SOURCES := 8
const GROUND_DEPTH_BIAS := 0.01
const GateArt = preload("res://addons/cultivation_mode/chengdu_painted_gate_art.gd")
const OVERLAY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;
uniform sampler2D painting_0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D painting_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D painting_2 : source_color, filter_linear_mipmap, repeat_disable;
// Encoded ID/geometry data are RAW, nearest, without sRGB conversion/mipmaps.
uniform sampler2D source_mask_0 : filter_nearest, repeat_disable;
uniform sampler2D source_mask_1 : filter_nearest, repeat_disable;
uniform sampler2D source_mask_2 : filter_nearest, repeat_disable;
uniform sampler2D geometry_map_0 : filter_nearest, repeat_disable;
uniform sampler2D geometry_map_1 : filter_nearest, repeat_disable;
uniform sampler2D geometry_map_2 : filter_nearest, repeat_disable;
uniform mat4 reference_vp_0;
uniform mat4 reference_vp_1;
uniform mat4 reference_vp_2;
uniform vec3 reference_position_0;
uniform vec3 reference_position_1;
uniform vec3 reference_position_2;
uniform vec3 reference_forward_0;
uniform vec3 reference_forward_1;
uniform vec3 reference_forward_2;
uniform vec3 source_rgb_0;
uniform vec3 source_rgb_1;
uniform vec3 source_rgb_2;
uniform vec2 depth_range_0;
uniform vec2 depth_range_1;
uniform vec2 depth_range_2;
uniform vec2 reference_size_0 = vec2(1280.0,720.0);
uniform vec2 reference_size_1 = vec2(1280.0,720.0);
uniform vec2 reference_size_2 = vec2(1280.0,720.0);
uniform vec3 source_enabled = vec3(0.0);
uniform vec3 reference_available = vec3(0.0);
uniform vec3 allowed_ground_sources_0[8];
uniform vec3 allowed_ground_sources_1[8];
uniform vec3 allowed_ground_sources_2[8];
uniform ivec3 allowed_ground_counts = ivec3(0);
uniform float ground_depth_bias = 0.0;
uniform vec4 world_bounds;
uniform float world_feather = 1.25;
uniform float protected_south = 98.125;
uniform float blend_strength = 1.0;
uniform float frame_feather_pixels = 32.0;
uniform float minimum_reference_normal_dot = 0.08;
uniform float minimum_captured_normal_dot = 0.94;
uniform float depth_tolerance = 0.04;
uniform float relative_depth_tolerance = 0.0005;
uniform float source_edge_pixels = 0.0;
uniform vec3 reference_priority = vec3(1.0);
uniform bool fragment_reference_priority = false;
uniform vec3 reference_anchor_0;
uniform vec3 reference_anchor_1;
uniform vec3 reference_anchor_2;
uniform float fade = 0.0;
uniform vec2 player_uv = vec2(0.5);
varying vec3 original_world_position;
varying vec3 original_world_normal;
void vertex() {
    original_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    original_world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec3 decode_normal(vec2 oct) {
    vec2 f=oct*2.0-1.0;
    vec3 n=vec3(f,1.0-abs(f.x)-abs(f.y));
    float t=clamp(-n.z,0.0,1.0);
    n.xy+=vec2(n.x>=0.0?-t:t,n.y>=0.0?-t:t);
    return normalize(n);
}
float world_coverage(vec2 p) {
    vec2 edge=min(p-world_bounds.xy,world_bounds.zw-p);
    return smoothstep(0.0,max(world_feather,0.001),min(edge.x,edge.y));
}
float same_source(sampler2D id_tex, vec2 uv, vec3 source_rgb) {
    vec3 delta=abs(texture(id_tex,uv).rgb-source_rgb);
    return max(max(delta.r,delta.g),delta.b)<0.5/255.0?1.0:0.0;
}
float source_edge_coverage(sampler2D id_tex, vec2 uv, vec3 source_rgb, vec2 size) {
    if (source_edge_pixels<=0.0) { return 1.0; }
    vec2 r=vec2(source_edge_pixels)/size;
    // A fixed eight-point ring retreats from real window/eave boundaries.
    // This is a bounded inward feather approximation, not an exact distance
    // field; no RGB-ID interpolation or weaker center-ID match is permitted.
    // Ground bypasses this function's texture reads; no extra sampler is used.
    float outer=same_source(id_tex,uv+vec2(r.x,0.0),source_rgb)
        +same_source(id_tex,uv-vec2(r.x,0.0),source_rgb)
        +same_source(id_tex,uv+vec2(0.0,r.y),source_rgb)
        +same_source(id_tex,uv-vec2(0.0,r.y),source_rgb)
        +same_source(id_tex,uv+r*0.70710678,source_rgb)
        +same_source(id_tex,uv-r*0.70710678,source_rgb)
        +same_source(id_tex,uv+vec2(r.x,-r.y)*0.70710678,source_rgb)
        +same_source(id_tex,uv+vec2(-r.x,r.y)*0.70710678,source_rgb);
    return smoothstep(0.75,1.0,outer/8.0);
}
vec4 candidate(sampler2D paint_tex, sampler2D id_tex, sampler2D geometry_tex,
        mat4 vp, vec3 at, vec3 forward, vec3 source_rgb, vec2 depth_range,
        vec2 size, float enabled, vec3 normal) {
    if (enabled<0.5) { return vec4(0.0); }
    vec4 clip=vp*vec4(original_world_position,1.0);
    if (clip.w<=0.0) { return vec4(0.0); }
    vec2 uv=vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
    if (any(lessThanEqual(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) { return vec4(0.0); }
    vec3 id=texture(id_tex,uv).rgb;
    vec3 id_delta=abs(id-source_rgb);
    if (max(max(id_delta.r,id_delta.g),id_delta.b)>=0.5/255.0) { return vec4(0.0); }
    vec3 toward_reference=normalize(at-original_world_position);
    float reference_facing=dot(normal,toward_reference);
    if (reference_facing<=minimum_reference_normal_dot) { return vec4(0.0); }
    vec4 geometry=texture(geometry_tex,uv);
    float normal_match=dot(normal,decode_normal(geometry.rg));
    if (normal_match<minimum_captured_normal_dot) { return vec4(0.0); }
    float stored_depth=depth_range.x+((floor(geometry.b*255.0+0.5)*256.0+floor(geometry.a*255.0+0.5))/65535.0)*(depth_range.y-depth_range.x);
    float actual_depth=dot(original_world_position-at,forward);
    float tolerance=depth_tolerance+abs(actual_depth)*relative_depth_tolerance;
    float depth_error=abs(stored_depth-actual_depth);
    if (actual_depth<=0.0 || depth_error>tolerance) { return vec4(0.0); }
    float depth_confidence=1.0-smoothstep(tolerance*0.55,tolerance,depth_error);
    float edge_pixels=min(min(uv.x,1.0-uv.x)*size.x,min(uv.y,1.0-uv.y)*size.y);
    float frame_coverage=smoothstep(0.0,max(frame_feather_pixels,1.0),edge_pixels);
    float confidence=frame_coverage*depth_confidence*source_edge_coverage(id_tex,uv,source_rgb,size);
    return vec4(texture(paint_tex,uv).rgb,confidence);
}
bool ground_source_allowed(int view, vec3 captured_id) {
    int count=allowed_ground_counts[view];
    for (int index=0;index<8;index++) {
        if (index>=count) { break; }
        vec3 allowed=allowed_ground_sources_0[index];
        if (view==1) { allowed=allowed_ground_sources_1[index]; }
        if (view==2) { allowed=allowed_ground_sources_2[index]; }
        vec3 delta=abs(captured_id-allowed);
        if (max(max(delta.r,delta.g),delta.b)<0.5/255.0) { return true; }
    }
    return false;
}
vec4 ground_reference_candidate(sampler2D id_tex, sampler2D geometry_tex,
        int view, mat4 vp, vec3 at, vec3 forward, vec2 depth_range, vec2 size,
        float available, vec3 normal) {
    // All coplanar ground meshes evaluate the same candidates before asking
    // which original source ID owns this point. Mesh visibility/ID must not
    // change the winning reference, or overlapping planes can draw two images.
    if (available<0.5) { return vec4(0.0); }
    vec4 clip=vp*vec4(original_world_position,1.0);
    if (clip.w<=0.0) { return vec4(0.0); }
    vec2 uv=vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
    if (any(lessThanEqual(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) { return vec4(0.0); }
    if (!ground_source_allowed(view,texture(id_tex,uv).rgb)) { return vec4(0.0); }
    if (dot(normal,normalize(at-original_world_position))<=minimum_reference_normal_dot) { return vec4(0.0); }
    vec4 geometry=texture(geometry_tex,uv);
    if (dot(normal,decode_normal(geometry.rg))<minimum_captured_normal_dot) { return vec4(0.0); }
    float stored_depth=depth_range.x+((floor(geometry.b*255.0+0.5)*256.0+floor(geometry.a*255.0+0.5))/65535.0)*(depth_range.y-depth_range.x);
    float actual_depth=dot(original_world_position-at,forward);
    float tolerance=depth_tolerance+abs(actual_depth)*relative_depth_tolerance;
    float depth_error=abs(stored_depth-actual_depth);
    if (actual_depth<=0.0 || depth_error>tolerance) { return vec4(0.0); }
    float depth_confidence=1.0-smoothstep(tolerance*0.55,tolerance,depth_error);
    float edge_pixels=min(min(uv.x,1.0-uv.x)*size.x,min(uv.y,1.0-uv.y)*size.y);
    float frame_coverage=smoothstep(0.0,max(frame_feather_pixels,1.0),edge_pixels);
    return vec4(uv,0.0,frame_coverage*depth_confidence);
}
void fragment() {
    float coverage=world_coverage(original_world_position.xz);
    if (coverage<=0.0 || original_world_position.z>=protected_south) { discard; }
    vec3 normal=normalize(original_world_normal);
    vec4 a;
    vec4 b;
    vec4 c;
    if (fragment_reference_priority) {
        a=ground_reference_candidate(source_mask_0,geometry_map_0,0,reference_vp_0,reference_position_0,reference_forward_0,depth_range_0,reference_size_0,reference_available.x,normal);
        b=ground_reference_candidate(source_mask_1,geometry_map_1,1,reference_vp_1,reference_position_1,reference_forward_1,depth_range_1,reference_size_1,reference_available.y,normal);
        c=ground_reference_candidate(source_mask_2,geometry_map_2,2,reference_vp_2,reference_position_2,reference_forward_2,depth_range_2,reference_size_2,reference_available.z,normal);
    } else {
        a=candidate(painting_0,source_mask_0,geometry_map_0,reference_vp_0,reference_position_0,reference_forward_0,source_rgb_0,depth_range_0,reference_size_0,source_enabled.x,normal);
        b=candidate(painting_1,source_mask_1,geometry_map_1,reference_vp_1,reference_position_1,reference_forward_1,source_rgb_1,depth_range_1,reference_size_1,source_enabled.y,normal);
        c=candidate(painting_2,source_mask_2,geometry_map_2,reference_vp_2,reference_position_2,reference_forward_2,source_rgb_2,depth_range_2,reference_size_2,source_enabled.z,normal);
    }
    // House priorities are cached once for the entire original lot/body.
    // A large ground plane uses world-space anchor distances per fragment.
    // Neither rule depends on the current follow camera.
    vec3 priority=reference_priority;
    if (fragment_reference_priority) {
        vec2 p=original_world_position.xz;
        vec2 d0=p-reference_anchor_0.xz;
        vec2 d1=p-reference_anchor_1.xz;
        vec2 d2=p-reference_anchor_2.xz;
        priority=1.0/(vec3(1.0)+vec3(dot(d0,d0),dot(d1,d1),dot(d2,d2)));
    }
    vec4 selected=vec4(0.0);
    float selected_priority=-1.0;
    int selected_view=-1;
    if (a.a>0.0001) { selected=a; selected_priority=priority.x; selected_view=0; }
    if (b.a>0.0001 && priority.y>selected_priority) { selected=b; selected_priority=priority.y; selected_view=1; }
    if (c.a>0.0001 && priority.z>selected_priority) { selected=c; selected_view=2; }
    if (selected.a<=0.0001) { discard; }
    if (fragment_reference_priority) {
        // A rejected/excluded winner returns to the existing base. Trying a
        // second mesh-specific view here would reintroduce double ownership.
        vec2 uv=selected.xy;
        if (selected_view==0) {
            if (source_enabled.x<0.5 || same_source(source_mask_0,uv,source_rgb_0)<0.5) { discard; }
            selected.rgb=texture(painting_0,uv).rgb;
        } else if (selected_view==1) {
            if (source_enabled.y<0.5 || same_source(source_mask_1,uv,source_rgb_1)<0.5) { discard; }
            selected.rgb=texture(painting_1,uv).rgb;
        } else {
            if (source_enabled.z<0.5 || same_source(source_mask_2,uv,source_rgb_2)<0.5) { discard; }
            selected.rgb=texture(painting_2,uv).rgb;
        }
    }
    // Only roof reveal uses SCREEN_UV, exactly matching the retained base shader.
    // Painting/ID/depth/normal UVs above are frozen referenceVP*WORLD coordinates.
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(44.0,92.0,length(delta));
    float pattern=fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern<local*fade*0.88) { discard; }
    ALBEDO=selected.rgb;
    ALPHA=coverage*blend_strength*selected.a;
}
"""

# Public records allow actual-app old/new overlay A/B without touching actors,
# base materials, geometry, camera, lighting or state.
var records: Array[Dictionary] = []
var _installed: Array[Dictionary] = []
var _stage: Node
var _config: Dictionary = {}
var _views: Array[Dictionary] = []
var _shader: Shader
var _ground_shader: Shader
var _seen: Dictionary = {}
var _mesh_hashes: Dictionary = {}
var _roof_by_body: Dictionary = {}
var _indexed_roofs := 0
var _body_priorities: Dictionary = {}
var _surface_roles: Dictionary = {}
var _indexed_surface_records := 0
var _ground_signatures: Dictionary = {}
var _duplicate_ground_count := 0
var _gate_ground_bias_shader: Shader
var _gate_ground_bias_bindings: Array[Dictionary] = []
var _world_rect := Rect2()
var _world_feather := 1.25
var _enabled := false
var _scanned_geometry := 0
var _rejected_actor_count := 0
var _rejected_protected_count := 0
var _rejected_scope_count := 0
var _unmatched_count := 0
var _rejected_structure_count := 0
var _setup_errors: Array[String] = []


func setup(stage: Node, configuration: Dictionary = {}) -> void:
	if _stage!=null:
		return
	_stage=stage
	if configuration.is_empty():
		if not FileAccess.file_exists(CONFIG):
			return
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if not data is Dictionary:
			return
		_config=data
	else:
		_config=configuration.duplicate(true)
	var bounds: Array = _config.get("world_bounds",[6600,6300,2300,1900])
	if bounds.size()!=4:
		_setup_errors.append("world_bounds requires four logical coordinates")
		return
	_world_rect=_logical_rect(bounds)
	_world_feather=float(_config.get("world_feather",100.0))/80.0
	var input_views: Variant = _config.get("views",[])
	if not input_views is Array:
		_setup_errors.append("views must be an array")
		return
	for id: String in VIEW_IDS:
		for definition: Variant in input_views:
			if definition is Dictionary and str(definition.get("id",""))==id:
				var view := _load_view(definition)
				if not view.is_empty():
					_views.append(view)
				break
	if _views.is_empty():
		return
	_shader=Shader.new()
	_shader.code=OVERLAY_SHADER
	# A VERTEX write changes the renderer's compiled position path even when a
	# uniform branch is false. Preserve the accepted house vertex verbatim and
	# compile the lifted ground pass separately.
	var marker := "    original_world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);"
	_ground_shader=Shader.new()
	_ground_shader.code=OVERLAY_SHADER.replace(marker,marker+"\n    VERTEX+=(inverse(MODEL_MATRIX)*vec4(original_world_normal*ground_depth_bias,0.0)).xyz;")
	_prepare_ground_sources()
	_bias_gate_ground_passes()
	_enabled=true
	attach_tree(_stage.get("world_root"))
	sync()


func _load_view(definition: Dictionary) -> Dictionary:
	var id := str(definition.id)
	var reference: Dictionary = definition
	if definition.has("reference_camera"):
		var path := str(definition.reference_camera)
		if not FileAccess.file_exists(path):
			_setup_errors.append(id+": missing reference camera")
			return {}
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary:
			_setup_errors.append(id+": invalid reference camera")
			return {}
		reference=value
	var paths: Dictionary = {}
	for kind: String in ["painting","source_mask","geometry_map"]:
		paths[kind]=str(definition.get(kind,reference.get(kind,"")))
		if not ResourceLoader.exists(paths[kind]):
			_setup_errors.append(id+": missing "+kind)
			return {}
	var painting := load(paths.painting) as Texture2D
	var mask := load(paths.source_mask) as Texture2D
	var geometry_map := load(paths.geometry_map) as Texture2D
	if painting==null or mask==null or geometry_map==null:
		_setup_errors.append(id+": invalid textures")
		return {}
	var size: Array = reference.get("image_size",reference.get("viewport",[1280,720]))
	if size.size()!=2 or int(size[0])<=0 or int(size[1])<=0:
		_setup_errors.append(id+": invalid reference viewport")
		return {}
	var expected_size := Vector2i(int(size[0]),int(size[1]))
	if mask.get_size()!=Vector2(expected_size) or geometry_map.get_size()!=Vector2(expected_size):
		_setup_errors.append(id+": ID/geometry dimensions differ from calibration")
		return {}
	if absf(float(painting.get_width())/float(painting.get_height())-float(size[0])/float(size[1]))>0.005:
		_setup_errors.append(id+": painting aspect differs from reference")
		return {}
	var columns: Array = reference.get("view_projection_columns",[])
	if columns.size()!=4:
		_setup_errors.append(id+": invalid reference projection")
		return {}
	for column: Variant in columns:
		if not column is Array or column.size()!=4:
			_setup_errors.append(id+": invalid reference projection column")
			return {}
	var position: Array = reference.get("camera_position",[])
	var forward: Array = reference.get("camera_forward",[])
	if forward.is_empty() and reference.has("camera_transform"):
		var basis_z: Array = reference.camera_transform[2]
		forward=[-float(basis_z[0]),-float(basis_z[1]),-float(basis_z[2])]
	if position.size()!=3 or forward.size()!=3:
		_setup_errors.append(id+": invalid camera vectors")
		return {}
	var near_depth := float(reference.get("depth_near",reference.get("near",0.1)))
	var far_depth := float(reference.get("depth_far",reference.get("far",150.0)))
	if Vector3(float(forward[0]),float(forward[1]),float(forward[2])).length_squared()<0.5:
		_setup_errors.append(id+": zero reference forward vector")
		return {}
	if near_depth<0.0 or far_depth<=near_depth:
		_setup_errors.append(id+": invalid linear depth range")
		return {}
	var entries: Dictionary = {}
	var visible: Dictionary = reference.get("pixel_counts",{})
	var excluded: Dictionary = {}
	for signature: Variant in definition.get("excluded_source_signatures",[]):
		excluded[str(signature)]=true
	for source: Dictionary in reference.get("sources",[]):
		if visible.has(str(int(source.id))) and source.has("signature") and not excluded.has(str(source.signature)) and source.get("rgb",[]).size()==3:
			entries[str(source.signature)]=source
	var anchor := Vector3(float(position[0]),0.0,float(position[2]))
	var anchor_row: Array = reference.get("player_anchor",[])
	if anchor_row.size()==2:
		anchor=_stage.call("logical_to_world",Vector2(float(anchor_row[0]),float(anchor_row[1])))
	return {"id":id,"painting":painting,"source_mask":mask,"geometry_map":geometry_map,
		"anchor":anchor,"pixel_counts":visible,"excluded_source_signatures":excluded.keys(),
		"paths":paths,"entries":entries,"size":Vector2(float(size[0]),float(size[1])),
		"projection":Projection(_v4(columns[0]),_v4(columns[1]),_v4(columns[2]),_v4(columns[3])),
		"position":Vector3(float(position[0]),float(position[1]),float(position[2])),
		"forward":Vector3(float(forward[0]),float(forward[1]),float(forward[2])).normalized(),
		"depth_range":Vector2(near_depth,far_depth)}


func _prepare_ground_sources() -> void:
	# The entire floor exists before this helper is installed. Derive one small
	# per-view allowlist from actual ground receivers and filtered calibration;
	# every coplanar mesh must use this identical list before choosing a view.
	var ground: Dictionary = {}
	for node: MeshInstance3D in _stage.get("world_root").find_children("*","MeshInstance3D",true,false):
		if _is_ground_plane(node) and not _is_actor_geometry(node) and not _is_protected(node) and _intersects_scope(node):
			ground[_signature(node)]=true
	for view: Dictionary in _views:
		var sources: Array[Dictionary] = []
		for signature: String in ground:
			var source: Dictionary = view.entries.get(signature,{})
			if not source.is_empty():
				sources.append(source)
		sources.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.id)<int(b.id))
		if sources.size()>MAX_GROUND_SOURCES:
			_setup_errors.append(str(view.id)+": ground source count exceeds supported eight")
			sources.clear()
		view["ground_sources"]=sources


func _bias_gate_ground_passes() -> void:
	# Preserve the accepted gate helper's original source and material objects.
	# Only ground materials in this ArtStreet instance receive a private shader
	# copy, so the parent helper's normal sync and QA still own those materials.
	var code: String = GateArt.OVERLAY_SHADER
	var marker := "    original_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);"
	if code.count(marker)!=1 or code.count("void vertex() {")!=1:
		_setup_errors.append("retained gate vertex contract differs; ground bias not installed")
		return
	_gate_ground_bias_shader=Shader.new()
	_gate_ground_bias_shader.code=code.replace("void vertex() {","uniform float ground_depth_bias = 0.0;\nvoid vertex() {").replace(marker,
		marker+"\n    VERTEX += (inverse(MODEL_MATRIX) * vec4(original_world_normal * ground_depth_bias,0.0)).xyz;")
	var gate: Node = _stage.get("_painted_gate")
	for record: Dictionary in gate.get("_installed"):
		if not is_instance_valid(record.node) or not _is_ground_plane(record.node):
			continue
		var material := record.material as ShaderMaterial
		_gate_ground_bias_bindings.append({"material":material,"old_shader":material.shader})
		material.shader=_gate_ground_bias_shader
		material.set_shader_parameter("ground_depth_bias",GROUND_DEPTH_BIAS)


func attach_tree(root_node: Node) -> void:
	if not _enabled or not is_instance_valid(root_node):
		return
	_index_roofs()
	_index_surface_roles()
	if root_node is GeometryInstance3D:
		_attach(root_node as GeometryInstance3D)
	for node: Node in root_node.find_children("*","GeometryInstance3D",true,false):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			_attach(node as GeometryInstance3D)


func _attach(node: GeometryInstance3D) -> void:
	if not node is MeshInstance3D and not node is MultiMeshInstance3D:
		return
	var instance := node.get_instance_id()
	if _seen.has(instance):
		return
	_seen[instance]=true
	_scanned_geometry+=1
	if _is_actor_geometry(node):
		_rejected_actor_count+=1
		return
	if _is_protected(node):
		_rejected_protected_count+=1
		return
	if not _intersects_scope(node):
		_rejected_scope_count+=1
		return
	var row := _roof_row(node)
	var role := str(node.get_meta("art_surface_role",_surface_roles.get(instance,"")))
	if not row.is_empty() and role in ["plaster","wood","dark"]:
		_rejected_structure_count+=1
		return
	var signature := _signature(node)
	var sources: Array = []
	var enabled := Vector3.ZERO
	for index: int in range(_views.size()):
		var source: Dictionary = _views[index].entries.get(signature,{})
		sources.append(source)
		if not source.is_empty():
			enabled[index]=1.0
	if enabled==Vector3.ZERO:
		_unmatched_count+=1
		return
	var ground := _is_ground_plane(node)
	if ground and _ground_signatures.has(signature):
		_duplicate_ground_count+=1
		return
	if ground:
		_ground_signatures[signature]=true
	var priority := _fixed_priorities(node,row)
	var material := ShaderMaterial.new()
	material.shader=_ground_shader if ground else _shader
	material.render_priority=-2
	material.set_shader_parameter("source_enabled",enabled)
	var available := Vector3.ZERO
	for index: int in range(_views.size()):
		available[index]=1.0
	material.set_shader_parameter("reference_available",available)
	var ground_counts := Vector3i.ZERO
	for index: int in range(3):
		var colors := PackedVector3Array()
		colors.resize(MAX_GROUND_SOURCES)
		if index<_views.size():
			var allowed: Array = _views[index].ground_sources
			ground_counts[index]=allowed.size()
			for source_index: int in range(allowed.size()):
				var rgb: Array = allowed[source_index].rgb
				colors[source_index]=Vector3(float(rgb[0]),float(rgb[1]),float(rgb[2]))/255.0
		material.set_shader_parameter("allowed_ground_sources_"+str(index),colors)
	material.set_shader_parameter("allowed_ground_counts",ground_counts)
	material.set_shader_parameter("reference_priority",priority)
	material.set_shader_parameter("fragment_reference_priority",ground)
	material.set_shader_parameter("ground_depth_bias",GROUND_DEPTH_BIAS if ground else 0.0)
	var edge_pixels := 0.0
	if not row.is_empty() and not ground:
		edge_pixels=3.0 if role=="roof" else 0.0
	material.set_shader_parameter("source_edge_pixels",edge_pixels)
	material.set_shader_parameter("world_bounds",Vector4(_world_rect.position.x,_world_rect.position.y,_world_rect.end.x,_world_rect.end.y))
	material.set_shader_parameter("world_feather",_world_feather)
	material.set_shader_parameter("protected_south",_stage.call("logical_to_world",Vector2(7800,8250)).z)
	for uniform: String in ["blend_strength","frame_feather_pixels","minimum_reference_normal_dot","minimum_captured_normal_dot","depth_tolerance","relative_depth_tolerance"]:
		if _config.has(uniform):
			material.set_shader_parameter(uniform,float(_config[uniform]))
	var ids: Dictionary = {}
	for index: int in range(3):
		var view: Dictionary = _views[mini(index,_views.size()-1)]
		var suffix := "_"+str(index)
		for kind: String in ["painting","source_mask","geometry_map"]:
			material.set_shader_parameter(kind+suffix,view[kind])
		material.set_shader_parameter("reference_vp"+suffix,view.projection)
		material.set_shader_parameter("reference_position"+suffix,view.position)
		material.set_shader_parameter("reference_anchor"+suffix,view.anchor)
		material.set_shader_parameter("reference_forward"+suffix,view.forward)
		material.set_shader_parameter("depth_range"+suffix,view.depth_range)
		material.set_shader_parameter("reference_size"+suffix,view.size)
		var source: Dictionary = sources[index] if index<sources.size() else {}
		var rgb: Array = source.get("rgb",[0,0,0])
		material.set_shader_parameter("source_rgb"+suffix,Vector3(float(rgb[0]),float(rgb[1]),float(rgb[2]))/255.0)
		if not source.is_empty():
			ids[str(view.id)]=int(source.id)
	var old_overlay := node.material_overlay
	# A large original ground plane also carries the accepted gate projection.
	# Keep it as a later pass rather than replacing the original gate helper.
	material.next_pass=old_overlay
	node.material_overlay=material
	if not row.is_empty():
		(row.materials as Array).append(material)
	var record := {"node":node,"material":material,"old_overlay":old_overlay,"roof_row":row,"source_ids":ids,"signature":signature,"fixed_priority":priority,"world_fragment_priority":ground,
		"preferred_view":str(_views[_preferred_index(priority)].id),"surface_role":role,"source_edge_pixels":edge_pixels}
	records.append(record)
	_installed.append(record)


func _is_ground_plane(node: GeometryInstance3D) -> bool:
	if not node is MeshInstance3D or not node.mesh is PlaneMesh:
		return false
	var transform := _local_chain(node)
	return absf(transform.basis.y.normalized().dot(Vector3.UP))>0.999 and transform.origin.y>=0.0 and transform.origin.y<=0.02


func _fixed_priorities(node: GeometryInstance3D, row: Dictionary) -> Vector3:
	var body: Node3D = row.get("body")
	if is_instance_valid(body) and _body_priorities.has(body.get_instance_id()):
		return _body_priorities[body.get_instance_id()]
	var center: Vector3 = _local_chain(body).origin if is_instance_valid(body) else _local_chain(node)*_mesh(node).get_aabb().get_center()
	var counts := Vector3.ZERO
	if is_instance_valid(body):
		# One reliability measure for the whole original roof/lot: all wall,
		# timber, leaf and roof batches share the exact same preferred image.
		for geometry: Node in body.find_children("*","GeometryInstance3D",true,false):
			if not geometry is MeshInstance3D and not geometry is MultiMeshInstance3D:
				continue
			var signature := _signature(geometry)
			for index: int in range(_views.size()):
				var source: Dictionary = _views[index].entries.get(signature,{})
				if not source.is_empty():
					counts[index]+=float(_views[index].pixel_counts.get(str(int(source.id)),0))
	var maximum := maxf(counts.x,maxf(counts.y,counts.z))
	var priority := Vector3.ZERO
	for index: int in range(_views.size()):
		var anchor: Vector3 = _views[index].anchor
		var distance_squared := Vector2(center.x,center.z).distance_squared_to(Vector2(anchor.x,anchor.z))
		var reliability := 0.5+0.5*sqrt(counts[index]/maximum) if maximum>0.0 else 1.0
		priority[index]=reliability/(1.0+distance_squared/36.0)
	if is_instance_valid(body):
		_body_priorities[body.get_instance_id()]=priority
	return priority


func _preferred_index(priority: Vector3) -> int:
	var best := 0
	for index: int in range(1,_views.size()):
		if priority[index]>priority[best]:
			best=index
	return best


func _index_roofs() -> void:
	var rows: Array = _stage.get("roof_rows")
	while _indexed_roofs<rows.size():
		var row: Dictionary = rows[_indexed_roofs]
		var body: Node = row.get("body")
		if is_instance_valid(body):
			_roof_by_body[body.get_instance_id()]=row
		_indexed_roofs+=1


func _index_surface_roles() -> void:
	# Parent conversion records provide exact roles for older houses surrounding
	# the eighteen authored lots. Index only new records as wards stream in.
	var surfaces: Node = _stage.get("_painted_city_surfaces")
	if not is_instance_valid(surfaces):
		return
	var existing: Array = surfaces.get("records")
	while _indexed_surface_records<existing.size():
		var record: Dictionary = existing[_indexed_surface_records]
		if is_instance_valid(record.node):
			_surface_roles[record.node.get_instance_id()]=str(record.kind)
		_indexed_surface_records+=1


func _roof_row(node: Node) -> Dictionary:
	var ancestor := node
	while ancestor!=null and ancestor!=_stage.get("world_root"):
		if _roof_by_body.has(ancestor.get_instance_id()):
			return _roof_by_body[ancestor.get_instance_id()]
		ancestor=ancestor.get_parent()
	return {}


func _is_actor_geometry(node: Node) -> bool:
	for property: String in ["_volume_actors","actor_nodes","shadow_nodes"]:
		var collection: Variant = _stage.get(property)
		if not collection is Dictionary:
			continue
		for actor: Node in collection.values():
			if is_instance_valid(actor) and (actor==node or actor.is_ancestor_of(node)):
				return true
	return false


func _is_protected(node: Node) -> bool:
	var ancestor := node
	while ancestor!=null and ancestor!=_stage.get("world_root"):
		if bool(ancestor.get_meta("art_street_preserve",false)) or bool(ancestor.get_meta("painted_gate_return",false)) or str(ancestor.name).begins_with("DetailedOpenSouthGate"):
			return true
		ancestor=ancestor.get_parent()
	for property: String in ["_river_umbrella","_returned_umbrella"]:
		var prop: Node = _stage.get(property)
		if is_instance_valid(prop) and (prop==node or prop.is_ancestor_of(node)):
			return true
	for glint: Node in _stage.get("_large_water_glints"):
		if glint==node:
			return true
	return false


func _intersects_scope(node: GeometryInstance3D) -> bool:
	var mesh := _mesh(node)
	if mesh==null:
		return false
	var box := node.get_aabb() if node is MultiMeshInstance3D else mesh.get_aabb()
	var transform := _local_chain(node)
	var bounds := Rect2(Vector2((transform*box.position).x,(transform*box.position).z),Vector2.ZERO)
	for x: float in [box.position.x,box.end.x]:
		for y: float in [box.position.y,box.end.y]:
			for z: float in [box.position.z,box.end.z]:
				var point := transform*Vector3(x,y,z)
				bounds=bounds.expand(Vector2(point.x,point.z))
	return bounds.intersects(_world_rect)


func sync() -> void:
	if not _enabled:
		return
	_index_roofs()
	var player: Vector2 = _stage.get("_player")
	var point: Vector2 = _stage.call("logical_to_screen",player,0.95)
	for record: Dictionary in records:
		if not is_instance_valid(record.node):
			continue
		if (record.roof_row as Dictionary).is_empty():
			record.roof_row=_roof_row(record.node)
			if not (record.roof_row as Dictionary).is_empty() and not record.roof_row.materials.has(record.material):
				(record.roof_row.materials as Array).append(record.material)
		record.material.set_shader_parameter("fade",float((record.roof_row as Dictionary).get("fade",0.0)))
		record.material.set_shader_parameter("player_uv",point/DISPLAY)


func _exit_tree() -> void:
	for record: Dictionary in records:
		if is_instance_valid(record.node) and record.node.material_overlay==record.material:
			record.node.material_overlay=record.old_overlay
		if is_instance_valid(record.roof_row.get("body")):
			(record.roof_row.materials as Array).erase(record.material)
		record.material.next_pass=null
	for binding: Dictionary in _gate_ground_bias_bindings:
		if binding.material.shader==_gate_ground_bias_shader:
			binding.material.shader=binding.old_shader


func audit() -> Dictionary:
	var ids: Array[String] = []
	var textures: Array = []
	for view: Dictionary in _views:
		ids.append(str(view.id))
		var ground_ids: Array[int] = []
		for source: Dictionary in view.ground_sources:
			ground_ids.append(int(source.id))
		textures.append({"id":view.id,"painting":view.paths.painting,"source_mask":view.paths.source_mask,"geometry_map":view.paths.geometry_map,
			"reference_size":[view.size.x,view.size.y],"painting_size":[view.painting.get_width(),view.painting.get_height()],"visible_source_count":view.entries.size(),
			"excluded_source_signatures":view.excluded_source_signatures,"allowed_ground_source_ids":ground_ids})
	return {"enabled":_enabled,"view_count":_views.size(),"loaded_view_ids":ids,"installed_mesh_count":records.size(),"material_count":records.size(),
		"scanned_geometry_count":_scanned_geometry,"rejected_actor_count":_rejected_actor_count,"rejected_protected_count":_rejected_protected_count,
		"rejected_scope_count":_rejected_scope_count,"unmatched_source_count":_unmatched_count,"setup_errors":_setup_errors.duplicate(),
		"rejected_structure_count":_rejected_structure_count,"retained_structure_roles":["plaster","wood","dark"],"house_source_edge_pixels":{"roof":3,"leaf":0},"ground_source_edge_pixels":0,
		"world_bounds":_config.get("world_bounds",[6600,6300,2300,1900]),"world_feather":_config.get("world_feather",100),"views":textures,
		"current_camera":{"fov":_stage.camera.fov,"local_transform":_transform(_local_chain(_stage.camera))} if _stage!=null and _stage.camera!=null else {},
		"no_screen_locked_art":true,"world_projective":true,"source_id_masked":true,"captured_depth_normal_gated":true,
		"reference_selection":"fixed per original roof body/lot; ground uses fixed world-fragment anchor distances; highest valid single image",
		"painting_rgb_blended":false,"current_camera_affects_art_selection":false,"fixed_house_priority_count":_body_priorities.size(),
		"ground_reference_selection":"one shared world-position reference with global allowed-ground IDs before mesh source-ID ownership",
		"ground_reference_uses_mesh_visibility":false,"duplicate_ground_signatures_skipped":_duplicate_ground_count,
		"ground_depth_bias_m":GROUND_DEPTH_BIAS,"biased_retained_gate_ground_count":_gate_ground_bias_bindings.size(),
		"retained_gate_bias_is_instance_private":true,"projection_coordinates_before_depth_bias":true,
		"ground_shader_separate_from_house_shader":true,
		"fallback":"unchanged inherited base materials outside valid calibrated surfaces or image/world feather",
		"detached_setup_safe":true,"retained_gate_overlay_chained":true,"opaque_world_depth_retained":true,
		"new_camera":false,"new_geometry":false,"new_actors":false,"new_state":false,"sampler_count":9}


func _logical_rect(values: Array) -> Rect2:
	var first: Vector3 = _stage.call("logical_to_world",Vector2(float(values[0]),float(values[1])))
	var last: Vector3 = _stage.call("logical_to_world",Vector2(float(values[0])+float(values[2]),float(values[1])+float(values[3])))
	return Rect2(Vector2(first.x,first.z),Vector2(last.x-first.x,last.z-first.z))


func _local_chain(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var chain: Array[Node3D] = []
	var ancestor: Node = node
	while ancestor!=_stage.get("world_root") and ancestor!=null:
		if ancestor is Node3D:
			chain.append(ancestor as Node3D)
		ancestor=ancestor.get_parent()
	for index: int in range(chain.size()-1,-1,-1):
		result=result*chain[index].transform
	return result


func _signature(node: GeometryInstance3D) -> String:
	# Exact same signature schema as the accepted gate/capture pipeline.
	var mesh := _mesh(node)
	var parts: Array = [node.get_class(),_transform(_local_chain(node)),[_vector3(mesh.get_aabb().position),_vector3(mesh.get_aabb().size)],_mesh_hash(mesh)]
	if node is MultiMeshInstance3D:
		var transforms: Array = []
		var instances: MultiMesh = (node as MultiMeshInstance3D).multimesh
		for index: int in range(instances.instance_count):
			transforms.append(_transform(instances.get_instance_transform(index)))
		parts.append(transforms)
	return JSON.stringify(parts).sha256_text()


func _mesh(node: GeometryInstance3D) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	if node is MultiMeshInstance3D and node.multimesh!=null:
		return node.multimesh.mesh
	return null


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
