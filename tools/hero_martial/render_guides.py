"""Render reviewable grey motion inputs in Blender 4.5.9, never final hero art.

CMU input uses the existing ASF/AMC FK reader and unchanged timing. The staff
input reads the existing original study as-is. A fixed camera fits ALL sampled
body and prop points, without per-frame recentering, foot pinning or zoom.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

VERSION = "1.0.0"
FPS = 15
SIZE = 512


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(args):
    if args.kind == "staff":
        source = args.repo / "assets/data/animation_lab/motion.json"
        data = json.loads(source.read_text())
        if data["fps"] != 30:
            raise ValueError("Staff source timing changed")
        frames = data["clips"]["staff"][::2]
        # Keep the 4-second authored interval; endpoint is separately retained
        # in the original source, rather than extending the video by 1 frame.
        if len(frames) != 61:
            raise ValueError("Staff source sample count changed")
        result = []
        for frame in frames[:-1]:
            j = frame["joints"]
            bones = {
                b["name"]: {"head": j[b["head"]], "tail": j[b["tail"]]}
                for b in data["bones"] if b["name"] != "weapon"
            }
            result.append({"bones": bones, "head": list((Vector(j["neck"])+Vector(j["crown"]))/2),
                           "face_q": Quaternion((0, 0, 1), math.radians(j["yaw"])),
                           "prop": [j["butt"], j["tip"]], "source_sample": len(result)*2})
        errors = []
        for f in frames:
            j = f["joints"]
            direction = (Vector(j["tip"])-Vector(j["butt"])).normalized()
            errors.append((Vector(j["hand_L"])-Vector(j["hand_R"])-direction*.34).length)
        evidence = {"kind": "original_procedural_staff", "source": str(source.relative_to(args.repo)),
                    "sha256": sha(source), "source_fps": 30,
                    "max_two_hand_axis_error_m": max(errors),
                    "limitations": ["Original constrained research motion, not human capture",
                                    "Naturalness and Jiang-specific grip require visual review"]}
        return result, evidence
    reader = module("hero_cmu_reader", args.repo / "tools/sword_mocap/cmu_motion.py")
    asf = args.repo / "assets/data/sword_mocap/source/02.asf"
    data = reader.sample_file(asf, args.amc, stride=8)
    start = args.start
    count = args.count if args.count is not None else len(data["samples"])-start
    selected = data["samples"][start:start+count]
    if not selected or len(selected) != count:
        raise ValueError("Selected source interval is unavailable")
    result = []
    for sample in selected:
        bones = sample["bones"]
        head = Vector(bones["head"]["head"])
        q = Quaternion(bones["head"]["rotation"])
        prop = None
        if args.kind == "sword":
            hand = (Vector(bones["rhand"]["head"])+Vector(bones["rhand"]["tail"]))/2
            axis = Quaternion(bones["rhand"]["rotation"]) @ Vector((0, -1, 0))
            prop = [list(hand-axis*.075), list(hand+axis*.93)]
        result.append({"bones": bones, "head": list(head+q @ Vector((0, 0, .025))),
                       "face_q": q, "prop": prop, "source_sample": sample["source_frame"]})
    evidence = {"kind": "CMU_full_body_capture", "source_basename": args.amc.name,
                "sha256": sha(args.amc), "skeleton_sha256": sha(asf), "source_fps": 120,
                "sample_stride": 8, "selected_source_frames": [selected[0]["source_frame"], selected[-1]["source_frame"]],
                "limitations": ["Adult body proportions, not final Jiang artwork",
                                "No captured weapon markers or verified Chinese technique",
                                "Rigid right-hand prop for sword only; no added prop for fist"]}
    return result, evidence


def make_ellipsoid(name, radii, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radii
    obj.color = (*color, 1)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def make_segment(name, radius, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8)
    obj = bpy.context.object
    obj.name = name
    obj.color = (*color, 1)
    obj["radius"] = radius
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def update_segment(obj, a, b):
    a, b = Vector(a), Vector(b)
    delta = b-a
    obj.location = (a+b)/2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y") if delta.length else Quaternion()
    radius = obj["radius"]
    obj.scale = (radius, radius, max(.002, delta.length/2+radius*.25))


def setup(frames, kind):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = False
    scene.display.shading.show_specular_highlight = False
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (.80, .80, .78)
    scene.view_settings.view_transform = "Standard"
    scene.display.render_aa = "8"
    radii = {"lowerback": .12, "upperback": .14, "thorax": .145,
             "hips": .12, "chest": .13, "upper_R": .043, "upper_L": .043}
    objects = {}
    for name, bone in frames[0]["bones"].items():
        if name in {"root", "head", "lfingers", "rfingers", "lthumb", "rthumb"}:
            continue
        if (Vector(bone["tail"])-Vector(bone["head"])).length < .001:
            continue
        radius = radii.get(name, .052 if "femur" in name or "thigh" in name else .035)
        objects[name] = make_segment(name, radius, (.32, .36, .40))
    head = make_ellipsoid("head-mass", (.081, .075, .108), (.39, .42, .44))
    nose = make_ellipsoid("front-marker", (.018, .021, .018), (.23, .25, .27))
    prop = make_segment("staff" if kind == "staff" else "sword", .014, (.34,.20,.10) if kind=="staff" else (.64,.67,.69)) if kind != "fist" else None
    # The original authored study has a Q-scale head/torso, keep a readable
    # mannequin guide at that actual scale rather than silently retargeting it.
    if kind == "staff":
        head.scale = (.27, .23, .33)
    points = []
    for frame in frames:
        for bone in frame["bones"].values():
            points.extend([Vector(bone["head"]), Vector(bone["tail"])])
        points.append(Vector(frame["head"])+Vector((0,0,.22)))
        if frame["prop"]:
            points.extend(Vector(v) for v in frame["prop"])
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    target = (lo+hi)/2
    direction = Vector((4, -7, 2.8)) if kind=="staff" else Vector((-4,-6,2.4))
    q = (-direction).to_track_quat("-Z", "Y")
    coords = [q.inverted() @ (p-target) for p in points]
    xmin,xmax = min(p.x for p in coords),max(p.x for p in coords)
    ymin,ymax = min(p.y for p in coords),max(p.y for p in coords)
    # Center in projected space once for the entire clip. 25% extra field
    # protects head volume, fists and thin prop tips at every frame.
    target += q @ Vector(((xmin+xmax)/2, (ymin+ymax)/2, 0))
    ortho = max(xmax-xmin,ymax-ymin)*1.25+.25
    camdata = bpy.data.cameras.new("FixedFullActionCamera")
    cam = bpy.data.objects.new("FixedFullActionCamera", camdata)
    bpy.context.collection.objects.link(cam)
    cam.location = target+direction
    cam.rotation_euler = q.to_euler()
    camdata.type = "ORTHO"
    camdata.ortho_scale = ortho
    scene.camera = cam
    camera = {"position": list(cam.location), "target": list(target), "ortho": ortho,
              "whole_action_projected_bbox_m": [xmin,ymin,xmax,ymax],
              "resolution": [SIZE,SIZE], "coordinate_system": "Blender Z up, metres",
              "per_frame_zoom_or_translation": False}
    return objects, head, nose, prop, camera


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--kind", choices=["sword", "staff", "fist"], required=True)
    p.add_argument("--amc", type=Path)
    p.add_argument("--start", type=int, default=0)
    p.add_argument("--count", type=int)
    p.add_argument("--hold-end", type=int, default=0)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--preview", action="store_true")
    args = p.parse_args(sys.argv[sys.argv.index("--")+1:])
    if args.output.exists():
        raise ValueError("Refusing to overwrite existing guide output")
    if args.start < 0 or (args.count is not None and args.count < 1) or args.hold_end < 0:
        raise ValueError("Invalid source interval/hold")
    if args.kind != "staff" and args.amc is None:
        raise ValueError("Sword and fist guides need an explicit AMC source")
    frames, source = collect(args)
    if args.hold_end:
        frames.extend([frames[-1]] * args.hold_end)
    source["explicit_end_hold_frames"] = args.hold_end
    source["hold_policy"] = "Optional terminal rest only; captured samples are not retimed"
    objects, head, nose, prop, camera = setup(frames, args.kind)
    indices = sorted(set(round(i*(len(frames)-1)/11) for i in range(12))) if args.preview else range(len(frames))
    args.output.mkdir(parents=True)
    for output_index, index in enumerate(indices):
        frame = frames[index]
        for name, obj in objects.items():
            bone = frame["bones"][name]
            update_segment(obj, bone["head"], bone["tail"])
        head.location = Vector(frame["head"])
        head.rotation_mode = "QUATERNION"
        head.rotation_quaternion = frame["face_q"]
        nose.location = head.location+frame["face_q"] @ Vector((0,-.075,.005))
        if prop:
            update_segment(prop, *frame["prop"])
        bpy.context.scene.render.filepath = str(args.output/f"frame-{output_index:04d}.png")
        bpy.ops.render.render(write_still=True)
    metadata = {"tool": "render_guides.py", "version": VERSION, "fps": FPS,
                "source": source, "camera": camera, "kind": args.kind,
                "preview": args.preview, "source_indices": [frames[i]["source_sample"] for i in indices],
                "blender_version": bpy.app.version_string, "final_character_art": False}
    (args.output/"guide-source.json").write_text(json.dumps(metadata,indent=2)+"\n")
    print("GUIDE_COMPLETE",args.kind,"frames",len(indices),flush=True)


if __name__ == "__main__":
    main()
