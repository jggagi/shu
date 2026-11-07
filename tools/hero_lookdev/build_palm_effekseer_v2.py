#!/usr/bin/env python3
"""Author a directional V2 palm-gust impact; compile and record with Effekseer 1.80.7.

The XML is our authored input, not a sampled effect.  The editor's public CUI
compiles it, and its unmodified native Recorder renders the transparent atlas.
No Effekseer runtime plug-in is required by the game.
"""
from __future__ import annotations
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/art/mountain_ambush/palm_lab/v2/effekseer"
QA = ROOT / ".local/qa/palm-vfx-v2-effekseer"
DEFAULT_TOOL = ROOT / ".local/tools/martial-vfx-authoring/Effekseer/1.80.7/Effekseer1.80.7Linux/Tool"
SEED = 5483


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def add(parent, name, value=None):
    node = ET.SubElement(parent, name)
    if value is not None:
        node.text = str(value)
    return node


def fixed(parent, name, value):
    node = add(parent, name)
    for key in ("Center", "Max", "Min"):
        add(node, key, value)
    return node


def rgba(parent, name, values):
    node = add(parent, name)
    for key, value in zip("RGBA", values):
        add(node, key, value)


def located(node, position=(0, 0, 0), velocity=(0, 0, 0)):
    loc = add(node, "LocationValues")
    add(loc, "Type", 1)
    pva = add(loc, "PVA")
    for key, values in (("Location", position), ("Velocity", velocity)):
        target = add(pva, key)
        for axis, value in zip("XYZ", values):
            fixed(target, axis, value)


def node_base(children, name, delay, life, fade_in, fade_out):
    node = add(children, "Node")
    add(node, "Name", name)
    common = add(node, "CommonValues")
    fixed(common, "Life", life)
    generation = add(common, "Generation")
    fixed(generation, "GenerationTimeOffset", delay)
    render = add(node, "RendererCommonValues")
    add(render, "AlphaBlend", 1)
    add(render, "FadeInType", 1)
    add(add(render, "FadeIn"), "Frame", fade_in)
    add(render, "FadeOutType", 1)
    add(add(render, "FadeOut"), "Frame", fade_out)
    return node


def crescent(children, name, delay, life, radius, speed, width, angles,
             color, position=(0, 0, 0), velocity=(0, 0, 0), scale=(1, 1, 1),
             center_ratio=0.5, fade_in=1, fade_out=11):
    node = node_base(children, name, delay, life, fade_in, fade_out)
    located(node, position, velocity)
    scaling = add(node, "ScalingValues")
    add(scaling, "Type", 0)
    sf = add(add(scaling, "Fixed"), "Scale")
    for axis, value in zip("XYZ", scale):
        add(sf, axis, value)
    drawing = add(node, "DrawingValues")
    add(drawing, "Type", 4)
    ring = add(drawing, "Ring")
    add(ring, "Billboard", 0)
    add(ring, "VertexCount", 96)
    add(ring, "CenterRatio_Fixed", center_ratio)
    shape = add(ring, "RingShape")
    add(shape, "Type", 1)
    shape = add(shape, "Crescent")
    add(shape, "StartingAngle_Fixed", angles[0])
    add(shape, "EndingAngle_Fixed", angles[1])
    add(shape, "StartingFade", 34)
    add(shape, "EndingFade", 48)
    for part, r in (("Outer", radius + width), ("Inner", max(0, radius - width))):
        add(ring, part, 1)
        pva = add(ring, part + "_PVA")
        target = add(pva, "Location")
        fixed(target, "X", r)
        fixed(target, "Y", 0)
        target = add(pva, "Velocity")
        fixed(target, "X", speed)
        fixed(target, "Y", 0)
    rgba(ring, "OuterColor_Fixed", (*color[:3], 0))
    rgba(ring, "CenterColor_Fixed", color)
    rgba(ring, "InnerColor_Fixed", (*color[:3], 0))
    add(node, "Children")


def slash(children, name, delay, life, angle, length, width, origin, speed, color):
    import math
    node = node_base(children, name, delay, life, 1, 7)
    x, y = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    located(node, (origin[0], origin[1], 0), (speed*x, speed*y, 0))
    rotation = add(node, "RotationValues")
    add(rotation, "Type", 0)
    target = add(add(rotation, "Fixed"), "Rotation")
    add(target, "Z", angle)
    drawing = add(node, "DrawingValues")
    add(drawing, "Type", 2)
    sprite = add(drawing, "Sprite")
    add(sprite, "Billboard", 3)
    add(sprite, "Position", 1)
    add(sprite, "Color", 1)
    # Quad connectivity forms two slender triangles, a tapered speed slash.
    for corner, xy, alpha in (("LL", (-length/2, 0), 0),
                              ("LR", (0, -width), color[3]),
                              ("UL", (0, width), color[3]),
                              ("UR", (length/2, 0), 0)):
        pos = add(sprite, "Position_Fixed_" + corner)
        add(pos, "X", xy[0]); add(pos, "Y", xy[1])
        rgba(sprite, "Color_Fixed_" + corner, (*color[:3], alpha))
    add(node, "Children")


def author():
    OUT.mkdir(parents=True, exist_ok=True)
    project = ET.Element("EffekseerProject")
    root = add(project, "Root")
    add(root, "Name", "Shu directional palm gust V2 - forward +X")
    children = add(root, "Children")
    # The only near-circle is a tiny warm contact flash lasting five frames.
    crescent(children, "Five-frame warm contact", 0, 5, .07, .018, .12, (0, 360),
             (255, 235, 185, 230), center_ratio=.2, fade_out=3)
    # Effekseer angle 270 points +X. Each body curve has its own center,
    # extent, birth and width; the advancing shapes never form concentric rings.
    crescent(children, "Broad jade forward pressure", 1, 23, .18, .071, .15,
             (158, 353), (175, 236, 215, 205), position=(.15, .04, 0),
             velocity=(.009, .001, 0), scale=(1, .82, 1), fade_out=12)
    crescent(children, "Ivory leading knife edge", 2, 15, .25, .078, .036,
             (196, 334), (255, 248, 223, 235), position=(.18, -.02, 0),
             velocity=(.012, 0, 0), scale=(1, .81, 1), fade_out=8)
    crescent(children, "Upper reverse curl", 4, 20, .31, .055, .075,
             (26, 147), (198, 239, 222, 170), position=(-.27, .32, 0),
             velocity=(.011, .004, 0), scale=(1.08, .62, 1), fade_out=11)
    crescent(children, "Low sweeping jade tail", 5, 22, .33, .053, .085,
             (221, 347), (153, 217, 193, 170), position=(-.28, -.27, 0),
             velocity=(.015, -.002, 0), scale=(1.13, .76, 1), fade_out=13)
    crescent(children, "Last narrow broken wisp", 7, 21, .28, .052, .040,
             (175, 281), (210, 244, 229, 135), position=(-.32, .10, 0),
             velocity=(.010, .003, 0), scale=(1.02, .91, 1), fade_out=13)
    # Short anisotropic slashes follow forward momentum, not radial spokes.
    for row in [
        ("High speed cut", 1, 12, 18, .84, .026, (.20, .22), .065, (255, 245, 218, 210)),
        ("Mid speed cut", 2, 13, -7, 1.12, .036, (.21, -.06), .073, (235, 252, 236, 220)),
        ("Low speed cut", 3, 14, -27, .72, .026, (.18, -.25), .060, (205, 244, 222, 190)),
        ("Upper short aftercut", 6, 13, 29, .56, .020, (-.06, .29), .058, (211, 244, 225, 155)),
        ("Lower short aftercut", 7, 14, -16, .63, .023, (-.13, -.28), .055, (191, 234, 209, 150)),
    ]:
        slash(children, *row)
    add(add(project, "Global"), "RandomSeed", SEED)
    recording = add(project, "Recording")
    for name, value in {"RecordingWidth": 256, "RecordingHeight": 256,
                        "RecordingStartingFrame": 0, "RecordingEndingFrame": 31,
                        "RecordingFrequency": 1, "RecordingHorizontalCount": 8,
                        "RecordingTransparentMethod": 1}.items():
        add(recording, name, value)
    for name, value in {"ToolVersion": "1.80.7", "Version": 3,
                        "StartFrame": 0, "EndFrame": 32, "IsLoop": "False"}.items():
        add(project, name, value)
    ET.indent(project)
    path = OUT / "palm-gust-v2.efkproj"
    ET.ElementTree(project).write(path, encoding="utf-8", xml_declaration=True)
    return path


def compile_effect(tool):
    source = author()
    command = [str(tool / "Effekseer"), "-cui", "-in", str(source),
               "-o", str(OUT / "palm-gust-v2.efkefc"), "-e", str(OUT / "palm-gust-v2.efk")]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    QA.mkdir(parents=True, exist_ok=True)
    (QA / "compile.json").write_text(json.dumps({"command": command,
        "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}, indent=2))
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0
    assert (OUT / "palm-gust-v2.efkefc").read_bytes()[:4] == b"EFKE"
    assert (OUT / "palm-gust-v2.efk").read_bytes()[:4] == b"SKFE"


class Native:
    """Thin ABI bridge to the release's official SWIG entry points."""
    def __init__(self, tool):
        self.lib = C.CDLL(str(tool / "bin/libViewer.so"))

    def call(self, name, result, types, *values):
        fn = getattr(self.lib, "CSharp_Effekseerfswig_" + name + "___")
        fn.restype, fn.argtypes = result, types
        return fn(*values)

    def new(self, name, types=(), *values):
        value = self.call("new_" + name, C.c_void_p, types, *values)
        assert value, "native allocation failed: " + name
        return value

    def set_i(self, kind, key, ptr, value):
        self.call(kind + "_" + key + "_set", None, (C.c_void_p, C.c_int), ptr, value)

    def set_p(self, kind, key, ptr, value):
        self.call(kind + "_" + key + "_set", None, (C.c_void_p, C.c_void_p), ptr, value)


def utf16(value):
    return C.create_string_buffer(str(value).encode("utf-16-le") + b"\0\0")


def record(tool, output):
    n = Native(tool)
    P, I, F, B = C.c_void_p, C.c_int, C.c_float, C.c_bool
    state = n.new("MainWindowState")
    for key, value in {"PosX": -10000, "Width": 256, "Height": 256}.items():
        n.set_i("MainWindowState", key, state, value)
    assert n.call("MainWindow_Initialize", B, (P, P, B, B),
                  utf16("Shu offline Effekseer Recorder"), state, False, True)
    window = n.call("MainWindow_GetInstance", P, ())
    manager = n.new("GUIManager")
    assert n.call("GUIManager_Initialize", B, (P, P, I), manager, window, 1)
    handle = n.call("GUIManager_GetNativeHandle", P, (P,), manager)
    graphics = n.call("GraphicsDevice_Create", P, (P, I, I, B, I), handle, 256, 256, False, 1)
    assert graphics, "OpenGL graphics initialization failed"
    setting = n.call("EffectSetting_Create", P, (P, P), graphics, None)
    assert setting
    factory = n.new("EffectFactory", (P,), setting)
    raw = (OUT / "palm-gust-v2.efk").read_bytes()
    raw_buffer = C.create_string_buffer(raw)
    effect = n.call("EffectFactory_LoadEffect", P, (P, P, I, P),
                    factory, raw_buffer, len(raw), utf16(OUT))
    assert effect, "compiled authored effect failed to load"
    camera = n.new("ViewPointController")
    n.call("ViewPointController_SetScreenSize", None, (P, I, I), camera, 256, 256)
    n.set_i("ViewPointController", "ProjectionStyle", camera, 1)
    n.call("ViewPointController_SetProjectionType", None, (P, I), camera, 1)
    n.call("ViewPointController_RateOfMagnification_set", None, (P, F), camera, 3.2)
    n.call("ViewPointController_SetAngleX", None, (P, F), camera, 0)
    n.call("ViewPointController_SetAngleY", None, (P, F), camera, 0)
    n.call("ViewPointController_Update", None, (P,), camera)
    config = n.new("EffectRendererParameter")
    for field, getter in (("CameraMatrix", "GetCameraMatrix"), ("ProjectionMatrix", "GetProjectionMatrix")):
        value = n.call("ViewPointController_" + getter, P, (P,), camera)
        n.set_p("EffectRendererParameter", field, config, value)
    for field, values in (("CameraPosition", (0, 0, 15)), ("CameraFrontDirection", (0, 0, -1))):
        vector = n.new("Vector3F__SWIG_1", (F, F, F), *values)
        n.set_p("EffectRendererParameter", field, config, vector)
    clear = n.new("Color__SWIG_1", (C.c_ubyte,) * 4, 0, 0, 0, 0)
    n.set_p("EffectRendererParameter", "BackgroundColor", config, clear)
    behavior = n.new("ViewerEffectBehavior")
    external = n.new("ViewerExternalModelVector__SWIG_0")
    post = n.new("PostEffectParameter")
    size = n.new("Vector2I__SWIG_1", (I, I), 256, 256)
    params = n.new("RecordingParameter")
    for key, value in {"RecordingMode": 1, "Count": 32, "HorizontalCount": 8,
                       "Freq": 1, "OffsetFrame": 0, "Transparence": 1, "Scale": 1}.items():
        n.set_i("RecordingParameter", key, params, value)
    output.parent.mkdir(parents=True, exist_ok=True)
    n.call("RecordingParameter_SetPath", None, (P, P), params, utf16(output.with_suffix("")))
    n.call("RecordingParameter_SetExt", None, (P, P), params, utf16(".png"))
    recorder = n.new("EffectRecorder")
    assert n.call("EffectRecorder_Begin", B, (P, I, P, P, P, P, P, P, B, P, P, P, P),
                  recorder, 2048, config, size, graphics, setting, params, size,
                  False, behavior, external, post, effect), "Recorder.Begin failed"
    for _ in range(32):
        n.call("EffectRecorder_Step", B, (P, I), recorder, 1)
    assert n.call("EffectRecorder_IsCompleted", B, (P,), recorder)
    assert n.call("EffectRecorder_End", B, (P,), recorder)
    print("Effekseer native Recorder completed:", output, flush=True)
    # The process owns all native objects. Avoid dangling shared_ptr teardown
    # through hand-written bindings; the OS releases this isolated batch job.
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", type=Path, default=DEFAULT_TOOL)
    parser.add_argument("--record", action="store_true", help="OpenGL offline render; requires DISPLAY")
    parser.add_argument("--output", type=Path, default=OUT / "palm-gust-v2-atlas.png")
    args = parser.parse_args()
    tool = args.tool.resolve()
    compile_effect(tool)
    if args.record:
        record(tool, args.output.resolve())


if __name__ == "__main__":
    main()
