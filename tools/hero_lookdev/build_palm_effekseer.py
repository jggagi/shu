#!/usr/bin/env python3
"""Author an original palm-wind study; compile and record with Effekseer 1.80.7.

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
OUT = ROOT / "assets/art/mountain_ambush/palm_lab/effekseer"
QA = ROOT / ".local/qa/palm-vfx-effekseer"
DEFAULT_TOOL = ROOT / ".local/tools/martial-vfx-authoring/Effekseer/1.80.7/Effekseer1.80.7Linux/Tool"
SEED = 5482


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


def author():
    OUT.mkdir(parents=True, exist_ok=True)
    project = ET.Element("EffekseerProject")
    root = add(project, "Root")
    add(root, "Name", "Shu original palm wind")
    children = add(root, "Children")
    # Independently authored ring/crescent nodes: no sample textures or nodes.
    layers = [
        ("Contact breath", 0, 12, 0.13, 0.070, 0.04, 10, 350, (255, 244, 210, 175)),
        ("Leading wind", 1, 18, 0.20, 0.076, 0.07, 8, 352, (215, 249, 239, 205)),
        ("Trailing wind", 4, 17, 0.18, 0.067, 0.055, 32, 305, (233, 252, 243, 165)),
        ("Upper curl", 3, 15, 0.32, 0.070, 0.035, 35, 148, (255, 245, 222, 145)),
        ("Lower curl", 5, 14, 0.28, 0.066, 0.035, 205, 325, (208, 244, 230, 145)),
    ]
    for name, delay, life, radius, speed, width, start, end, color in layers:
        node = add(children, "Node")
        add(node, "Name", name)
        common = add(node, "CommonValues")
        fixed(common, "Life", life)
        generation = add(common, "Generation")
        fixed(generation, "GenerationTimeOffset", delay)
        scale = add(node, "ScalingValues")
        add(scale, "Type", 0)
        sf = add(add(scale, "Fixed"), "Scale")
        for axis, value in zip("XYZ", (1.0, 0.78, 1.0)):
            add(sf, axis, value)
        render = add(node, "RendererCommonValues")
        add(render, "AlphaBlend", 1)  # straight alpha blend, no additive burn
        add(render, "FadeInType", 1)
        add(add(render, "FadeIn"), "Frame", 2)
        add(render, "FadeOutType", 1)
        add(add(render, "FadeOut"), "Frame", min(9, life - 3))
        draw = add(node, "DrawingValues")
        add(draw, "Type", 4)
        ring = add(draw, "Ring")
        add(ring, "Billboard", 0)
        add(ring, "VertexCount", 96)
        shape = add(ring, "RingShape")
        add(shape, "Type", 1)
        crescent = add(shape, "Crescent")
        add(crescent, "StartingAngle_Fixed", start)
        add(crescent, "EndingAngle_Fixed", end)
        add(crescent, "StartingFade", 28)
        add(crescent, "EndingFade", 36)
        for part, r in (("Outer", radius + width), ("Inner", radius - width)):
            add(ring, part, 1)
            pva = add(ring, part + "_PVA")
            position = add(pva, "Location")
            fixed(position, "X", r)
            fixed(position, "Y", 0)
            velocity = add(pva, "Velocity")
            fixed(velocity, "X", speed)
            fixed(velocity, "Y", 0)
        rgba(ring, "OuterColor_Fixed", (*color[:3], 0))
        rgba(ring, "CenterColor_Fixed", color)
        rgba(ring, "InnerColor_Fixed", (*color[:3], 0))
        add(node, "Children")
    add(add(project, "Global"), "RandomSeed", SEED)
    recording = add(project, "Recording")
    for name, value in {"RecordingWidth": 256, "RecordingHeight": 256,
                        "RecordingStartingFrame": 0, "RecordingEndingFrame": 23,
                        "RecordingFrequency": 1, "RecordingHorizontalCount": 8,
                        "RecordingTransparentMethod": 1}.items():
        add(recording, name, value)
    for name, value in {"ToolVersion": "1.80.7", "Version": 3,
                        "StartFrame": 0, "EndFrame": 24, "IsLoop": "False"}.items():
        add(project, name, value)
    ET.indent(project)
    path = OUT / "palm-wind.efkproj"
    ET.ElementTree(project).write(path, encoding="utf-8", xml_declaration=True)
    return path


def compile_effect(tool):
    source = author()
    command = [str(tool / "Effekseer"), "-cui", "-in", str(source),
               "-o", str(OUT / "palm-wind.efkefc"), "-e", str(OUT / "palm-wind.efk")]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    QA.mkdir(parents=True, exist_ok=True)
    (QA / "compile.json").write_text(json.dumps({"command": command,
        "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}, indent=2))
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0
    assert (OUT / "palm-wind.efkefc").read_bytes()[:4] == b"EFKE"
    assert (OUT / "palm-wind.efk").read_bytes()[:4] == b"SKFE"


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
    raw = (OUT / "palm-wind.efk").read_bytes()
    raw_buffer = C.create_string_buffer(raw)
    effect = n.call("EffectFactory_LoadEffect", P, (P, P, I, P),
                    factory, raw_buffer, len(raw), utf16(OUT))
    assert effect, "compiled authored effect failed to load"
    camera = n.new("ViewPointController")
    n.call("ViewPointController_SetScreenSize", None, (P, I, I), camera, 256, 256)
    n.set_i("ViewPointController", "ProjectionStyle", camera, 1)
    n.call("ViewPointController_SetProjectionType", None, (P, I), camera, 1)
    n.call("ViewPointController_RateOfMagnification_set", None, (P, F), camera, 3.0)
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
    for key, value in {"RecordingMode": 1, "Count": 24, "HorizontalCount": 8,
                       "Freq": 1, "OffsetFrame": 0, "Transparence": 1, "Scale": 1}.items():
        n.set_i("RecordingParameter", key, params, value)
    output.parent.mkdir(parents=True, exist_ok=True)
    n.call("RecordingParameter_SetPath", None, (P, P), params, utf16(output.with_suffix("")))
    n.call("RecordingParameter_SetExt", None, (P, P), params, utf16(".png"))
    recorder = n.new("EffectRecorder")
    assert n.call("EffectRecorder_Begin", B, (P, I, P, P, P, P, P, P, B, P, P, P, P),
                  recorder, 2048, config, size, graphics, setting, params, size,
                  False, behavior, external, post, effect), "Recorder.Begin failed"
    for _ in range(24):
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
    parser.add_argument("--output", type=Path, default=OUT / "palm-wind-atlas.png")
    args = parser.parse_args()
    tool = args.tool.resolve()
    compile_effect(tool)
    if args.record:
        record(tool, args.output.resolve())


if __name__ == "__main__":
    main()
