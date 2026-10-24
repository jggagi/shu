#!/usr/bin/env python3
"""Static Jiang look development, reusing a selected local painted-model builder.

Only three cameras are rendered. There are no generated per-view paintings,
animation keys, gameplay changes, or external calls. The selected base source
and unchanged textures are copied into the result for portable reconstruction.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-source", required=True, type=Path)
    parser.add_argument("--textures", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", type=int, default=1200)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if args.output.exists():
        parser.error("Refusing to overwrite existing output")
    if not args.base_source.is_file():
        parser.error("Missing selected base source")
    if not 256 <= args.size <= 2400:
        parser.error("Size must be between 256 and 2400")
    return args


def load_base(path):
    spec = importlib.util.spec_from_file_location("painted_hero_base", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def catmull(a, b, c, d, t):
    return 0.5 * ((2 * b) + (-a + c) * t +
                  (2 * a - 5 * b + 4 * c - d) * t * t +
                  (-a + 3 * b - 3 * c + d) * t * t * t)


def linear(c):
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def build(args):
    args.output.parent.mkdir(parents=True, exist_ok=True)
    base = load_base(args.base_source)
    base.RENDER_SIZE = args.size
    base.ORTHO_SCALE = 2.48
    base.CAMERA_TARGET = (0, 0, 1.10)
    base.CAMERA_ELEVATION_DEGREES = 3.0
    base.NAVY_TINT = (.18, .25, .33, 1)
    source_hashes = {"builder": sha(args.base_source), **{
        name: sha(args.textures / name) for name in base.TEXTURE_NAMES}}

    class Lookdev(base.CharacterBuilder):
        def tapered_loft(self, name, points, widths, depths, material, anchor_weights,
                         sides=12, steps_per_segment=4, back_facing=False):
            # Smooth authored curves once at construction, not at render time.
            points = [Vector(point) for point in points]
            dense, ws, ds, weights = [], [], [], []
            for span in range(len(points) - 1):
                p0, p1 = points[max(0, span - 1)], points[span]
                p2, p3 = points[span + 1], points[min(len(points) - 1, span + 2)]
                left, right = anchor_weights[span:span + 2]
                left = {left: 1.0} if isinstance(left, str) else left
                right = {right: 1.0} if isinstance(right, str) else right
                for step in range(6):
                    t = step / 6
                    dense.append(catmull(p0, p1, p2, p3, t))
                    ws.append(widths[span] * (1 - t) + widths[span + 1] * t)
                    ds.append(depths[span] * (1 - t) + depths[span + 1] * t)
                    weights.append({bone: left.get(bone, 0) * (1 - t) +
                                    right.get(bone, 0) * t for bone in set(left) | set(right)})
            dense.append(points[-1]); ws.append(widths[-1]); ds.append(depths[-1])
            weights.append(anchor_weights[-1])
            return super().tapered_loft(name, dense, ws, ds, material, weights,
                                         sides=max(sides, 16), steps_per_segment=1,
                                         back_facing=back_facing)

        def soften_materials(self):
            # Same four fixed images; blend their strong shading into a quiet
            # palette, preserving the original image bytes and facial artwork.
            palettes = {
                "hair": ((.235, .157, .109), .65),
                "ivory": ((.89, .885, .825), .50),
                "blue": ((.31, .49, .61), .72),
            }
            for key, (color, amount) in palettes.items():
                material = self.materials[key]
                nodes, links = material.node_tree.nodes, material.node_tree.links
                image_node = next(node for node in nodes if node.type == "TEX_IMAGE")
                shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
                mix = nodes.new("ShaderNodeMixRGB")
                mix.label = "Fixed painted palette; no per-view processing"
                mix.inputs[0].default_value = amount
                mix.inputs[1].default_value = tuple(linear(c) for c in color) + (1,)
                links.new(image_node.outputs["Color"], mix.inputs[2])
                links.new(mix.outputs[0], shader.inputs["Base Color"])
                links.new(mix.outputs[0], shader.inputs["Emission Color"])
                shader.inputs["Emission Strength"].default_value = .32
                shader.inputs["Roughness"].default_value = 1
                shader.inputs["Specular IOR Level"].default_value = .04
            for key in ("face", "skin"):
                shader = next(node for node in self.materials[key].node_tree.nodes
                              if node.type == "BSDF_PRINCIPLED")
                shader.inputs["Emission Strength"].default_value = .32
                shader.inputs["Specular IOR Level"].default_value = .04

        def remove_parts(self, prefixes):
            for obj in list(self.mesh_objects):
                if any(obj.name.startswith(prefix) for prefix in prefixes):
                    self.mesh_objects.remove(obj)
                    bpy.data.objects.remove(obj, do_unlink=True)

        def resting_arms(self):
            self.remove_parts(("Loose ivory sleeve", "Blue sleeve cuff", "Readable clenched fist",
                               "Fist knuckle"))
            rig = self.rig
            bpy.context.view_layer.objects.active = rig
            bpy.ops.object.select_all(action="DESELECT")
            rig.select_set(True)
            bpy.ops.object.mode_set(mode="EDIT")
            for side, sign in (("L", 1), ("R", -1)):
                shoulder = (sign * .26, 0, 1.28)
                elbow = (sign * .36, -.025, 1.08)
                wrist = (sign * .385, -.07, .895)
                tip = (sign * .39, -.075, .78)
                for name, head, tail in (("upper_arm.", shoulder, elbow),
                                          ("lower_arm.", elbow, wrist),
                                          ("hand.", wrist, tip)):
                    bone = rig.data.edit_bones[name + side]
                    bone.head, bone.tail = head, tail
            bpy.ops.object.mode_set(mode="OBJECT")
            for side, sign in (("L", 1), ("R", -1)):
                upper, lower, hand = "upper_arm." + side, "lower_arm." + side, "hand." + side
                pts = [(sign * .225, .0, 1.30), (sign * .31, -.01, 1.20),
                       (sign * .36, -.025, 1.08), (sign * .385, -.07, .91)]
                self.tapered_loft("Soft hanging sleeve " + side, pts,
                    [.09, .115, .122, .078], [.085, .10, .102, .065], "ivory",
                    [{upper: 1}, {upper: .85, lower: .15}, {upper: .45, lower: .55}, {lower: 1}],
                    sides=24)
                self.tapered_loft("Wrapped blue wrist " + side,
                    [(sign * .383, -.066, .96), (sign * .39, -.073, .885)],
                    [.079, .063], [.067, .055], "blue", [lower, hand], sides=24)
                self.ellipsoid("Relaxed palm " + side, (sign * .392, -.077, .847),
                               (.049, .035, .063), "skin", hand, 32, 20)
                for finger in range(4):
                    x = sign * (.366 + finger * .016)
                    length = [.057, .070, .065, .048][finger]
                    self.tapered_loft("Resting finger {} {}".format(side, finger),
                        [(x, -.083, .83), (x, -.088, .83 - length * .6),
                         (x, -.097, .83 - length)],
                        [.010, .0105, .006], [.012, .012, .006], "skin", [hand] * 3, sides=16)
                self.tapered_loft("Resting thumb " + side,
                    [(sign * .355, -.081, .86), (sign * .346, -.105, .837),
                     (sign * .352, -.114, .817)],
                    [.018, .016, .008], [.016, .014, .007], "skin", [hand] * 3, sides=20)

        def refined_details(self):
            self.remove_parts(("Ivory collar crossing", "Sash braided cord", "Sash side knot",
                               "Robe stitched fold", "Boot lace", "Tie loop", "Ribbon tail",
                               "Split robe panel", "Vest seam", "Ear ", "Fringe", "Temple lock"))
            # Ear pinnae have a small recessed inner surface, rather than the
            # old blank pale oval. These remain three-dimensional on both sides.
            ear_mat = self.materials["skin"].copy()
            ear_mat.name = "Quiet warm inner ear"
            ear_shader = next(node for node in ear_mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
            ear_shader.inputs["Base Color"].default_value = tuple(linear(c) for c in (.82,.61,.50))+(1,)
            ear_shader.inputs["Emission Color"].default_value = tuple(linear(c) for c in (.82,.61,.50))+(1,)
            self.materials["inner_ear"] = ear_mat
            for sign in (-1,1):
                self.ellipsoid("Sculpted ear {}".format(sign), (sign*.280,-.005,1.58),
                               (.044,.036,.063), "skin", "head", 32,24)
                self.ellipsoid("Inner ear {}".format(sign), (sign*.318,-.011,1.58),
                               (.006,.021,.036), "inner_ear", "head", 24,16)
            # Strand roots start inside the scalp. No exposed squared caps or
            # upright temple spikes; the asymmetrical fringe follows the skull.
            fringe = [
                ("Sculpted swept fringe", [(-.10,-.07,1.92),(-.055,-.19,1.84),(.045,-.24,1.72)], [.012,.083,.003]),
                ("Sculpted left fringe", [(.095,-.06,1.91),(.16,-.18,1.82),(.14,-.238,1.705)], [.014,.060,.003]),
                ("Sculpted right fringe", [(-.17,-.055,1.87),(-.20,-.18,1.76),(-.25,-.178,1.64)], [.012,.060,.003]),
            ]
            for name,pts,widths in fringe:
                self.tapered_loft(name,pts,widths,[w*.48 for w in widths],"hair",["head"]*3,sides=24)
            for sign in (-1,1):
                pts=[(sign*.20,-.025,1.82),(sign*.28,-.105,1.70),
                     (sign*.278,-.08,1.52),(sign*.245,-.065,1.40)]
                widths=[.012,.045,.033,.002]
                self.tapered_loft("Sculpted temple strand {}".format(sign),pts,widths,
                                 [w*.50 for w in widths],"hair",["head"]*4,sides=24)
            # A single wrapped crossing, with a blue undercollar. Avoid the old
            # symmetrical X-shaped tubes floating on the chest.
            vest_profile=[(1.385,.166,.122),(1.31,.195,.142),(1.23,.211,.151),
                          (1.15,.222,.157),(1.06,.233,.161),(.99,.25,.168)]
            def chest_surface(x,z):
                for high,low in zip(vest_profile,vest_profile[1:]):
                    if high[0]>=z>=low[0]:
                        t=(high[0]-z)/(high[0]-low[0])
                        rx=high[1]*(1-t)+low[1]*t
                        ry=high[2]*(1-t)+low[2]*t
                        return -ry*math.sqrt(max(.02,1-(x/rx)**2))-.009
                return -.13
            for name, pts, width, mat in (
                ("Blue inner neckline", [(-.12,-.13,1.38),(-.055,-.18,1.31),(.07,-.18,1.24)], .027, "blue"),
                ("Ivory wrapped lapel", [(-.14,-.145,1.36),(-.08,-.185,1.28),(.035,-.185,1.17),(.16,-.16,1.08)], .032, "ivory"),
                ("Ivory returning lapel", [(.14,-.145,1.36),(.095,-.182,1.30),(.035,-.185,1.245)], .029, "ivory"),
            ):
                pts=[(x,chest_surface(x,z),z) for x,_y,z in pts]
                self.tapered_loft(name, pts, [width] * len(pts), [.008] * len(pts), mat, ["spine"] * len(pts), sides=20)
            # Wrap the divided overskirt over the existing robe's elliptical
            # volume. The old flat panels hovered in front like a rigid apron.
            for sign,material in ((1,"blue"),(-1,"ivory")):
                rows,cols=23,23
                vertices,uvs,weights=[],[],[]
                for row in range(rows):
                    t=row/(rows-1)
                    z=.962-(.962-.525)*t
                    rx=.25+.047*t
                    ry=.164+.014*t
                    for col in range(cols):
                        u=col/(cols-1)
                        phi=sign*1.48*u
                        ripple=.002*math.sin(u*6*math.pi)*t
                        radius_offset=.007+ripple
                        vertices.append(((rx+radius_offset)*math.sin(phi),
                                         -(ry+radius_offset)*math.cos(phi),
                                         z+.006*math.sin(u*math.pi*2)*t*t))
                        uvs.append((u,1-t));weights.append({"hips":1})
                faces=[];face_uvs=[]
                for row in range(rows-1):
                    for col in range(cols-1):
                        a=row*cols+col
                        face=(a,a+cols,a+cols+1,a+1)
                        if sign<0:face=tuple(reversed(face))
                        faces.append(face);face_uvs.append(tuple(uvs[v] for v in face))
                obj=self.add_mesh("Curved wrapped overskirt {}".format(sign),vertices,faces,face_uvs,
                                  material,weights)
                solid=obj.modifiers.new("Soft fabric thickness","SOLIDIFY")
                solid.thickness=.004;solid.offset=0
            self.ellipsoid("Small cloth sash knot", (.19, -.137, 1.00),
                           (.033,.025,.038), "blue", "hips", 32, 20)
            for sign in (-1,1):
                pts = [(.19,-.15,1.00),(.20 + sign * .055,-.155,.95),(.19 + sign * .06,-.16,.85)]
                self.tapered_loft("Sash hanging tie {}".format(sign), pts,
                    [.013,.017,.011], [.004,.004,.003], "blue", ["hips"] * 3)
                # Narrow tied ribbons, with fabric thickness and gentle curves.
                pts = [(sign*.04,.35,1.96),(sign*.13,.48,1.73),
                       (sign*.22,.50,1.43),(sign*.20,.43,1.16)]
                self.tapered_loft("Long pale-blue hair ribbon {}".format(sign), pts,
                    [.025,.030,.024,.014], [.004,.005,.004,.003], "blue", ["head"] * 4)
                pts = [(sign*.025,.34,1.975),(sign*.10,.37,2.00),
                       (sign*.13,.35,1.965),(sign*.06,.34,1.95)]
                self.tapered_loft("Soft fabric tie fold {}".format(sign), pts,
                    [.018,.026,.023,.014], [.008,.012,.010,.007], "blue", ["head"] * 4)

        def smooth_meshes(self):
            for obj in self.mesh_objects:
                # Apply sculpting once. Cameras do not change mesh or texture.
                if any(key in obj.name for key in ("robe", "vest", "panel", "Head face", "hair cap")):
                    modifier = obj.modifiers.new("Lookdev smooth form", "SUBSURF")
                    modifier.levels = modifier.render_levels = 1
                    bpy.context.view_layer.objects.active = obj
                    bpy.ops.object.modifier_apply(modifier=modifier.name)

        def create_character(self):
            super().create_character()
            self.soften_materials()
            self.resting_arms()
            self.refined_details()
            self.smooth_meshes()

    args.output.mkdir()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    builder = Lookdev(args.textures)
    builder.create_character()
    scene = base.set_render_scene(args.output)
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.image_settings.compression = 30
    scene.view_settings.look = "AgX - Medium High Contrast"
    for obj in scene.objects:
        if obj.type == "LIGHT":
            obj.data.energy *= .72
    back_data = bpy.data.lights.new("Broad rear studio fill", "AREA")
    back_data.energy, back_data.size = 180, 5
    back = bpy.data.objects.new("Broad rear studio fill", back_data)
    scene.collection.objects.link(back)
    back.location = (0, 4, 4)
    back.rotation_euler = (Vector((0, 0, 1.1)) - back.location).to_track_quat("-Z", "Y").to_euler()
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .65
    cameras = {name: base.add_camera(name, angle) for name, angle in
               (("front", 0), ("side", 90), ("back", 180))}
    identity = base.mesh_identity(builder.mesh_objects)
    geometry = base.geometry_receipt(builder.mesh_objects)
    if geometry["vertices_with_invalid_weights"]:
        raise RuntimeError("Non-normalized mesh weights")
    if any(obj.animation_data and obj.animation_data.action for obj in scene.objects):
        raise RuntimeError("Static review unexpectedly has animation")
    scene.camera = cameras["front"]
    # Keep selected local source and textures portable without touching originals.
    source_dir = args.output / "source"
    source_dir.mkdir()
    shutil.copy2(args.base_source, source_dir / "base_builder.py")
    shutil.copy2(__file__, source_dir / "build_static_review.py")
    tex_dir = source_dir / "textures"
    tex_dir.mkdir()
    for name in base.TEXTURE_NAMES:
        shutil.copy2(args.textures / name, tex_dir / name)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / "painted-hero.blend"))
    views = {}
    for name, camera in cameras.items():
        scene.camera = camera
        scene.render.filepath = str(args.output / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        actual = base.mesh_identity(builder.mesh_objects)
        if actual != identity:
            raise RuntimeError("Mesh changed between cameras")
        views[name] = {"mesh_sha256": actual, "png_sha256": sha(args.output / (name + ".png")),
                       "camera": base.camera_receipt(camera)}
    if source_hashes != {"builder": sha(args.base_source), **{
        name: sha(args.textures / name) for name in base.TEXTURE_NAMES}}:
        raise RuntimeError("Selected source input changed")
    receipt = {"schema_version": 1, "candidate": "jiang-static-lookdev-20261022-"+args.output.name,
               "status": "STATIC_CANDIDATE_AWAITING_USER_REVIEW",
               "runtime": bpy.app.version_string, "render_engine": scene.render.engine,
               "size": [args.size,args.size], "source_input_sha256": source_hashes,
               "same_mesh_and_fixed_uv_across_views": True, "views": views,
               "textures": {name: sha(args.textures / name) for name in base.TEXTURE_NAMES},
               "animation_actions": 0, "new_external_generations": 0,
               "changes": ["smooth curved hair and sleeves", "relaxed articulated hands",
                            "surface-fitted collar and curved overskirt", "fixed matte painted material"],
               "limitations": ["Static shape approval only; no deformation or sword-grip acceptance",
                               "Face uses fixed existing front artwork on a rounded head"],
               **geometry}
    (args.output / "receipt.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"status":"DONE","output":str(args.output),"mesh_sha256":identity}))


if __name__ == "__main__":
    build(arguments())
