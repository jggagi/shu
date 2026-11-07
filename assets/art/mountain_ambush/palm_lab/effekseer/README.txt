蜀 · 掌风工具试验 / Effekseer

Original five-layer wind-ring study authored for this project. No sample
effects, textures, models or sounds are used. This is a presentation study,
not a playable palm skill or a replacement for the character's sword motion.

Editable sources:
  palm-wind.efkproj : authored XML input
  palm-wind.efkefc : official editor's compiled editable project
  palm-wind.efk    : official runtime binary, authoring/reproduction only

Runtime asset:
  palm-wind-atlas.png : untouched official Recorder output
  8 columns x 3 rows, 256 x 256 per tile, 24 samples, 60 fps, 0.4 seconds
  RGB IS PREMULTIPLIED. Use blend_premul_alpha when sampling in Godot.
  Frames 0 and 21–23 are empty; every frame has a transparent border.
  Camera is front-facing orthographic. The ring is camera-facing in source.

Reproduction from repository root, with an OpenGL-capable DISPLAY:
  python3 tools/hero_lookdev/build_palm_effekseer.py --record

The pinned official Linux 1.80.7 release can be supplied using --tool.
Default isolated location:
  .local/tools/martial-vfx-authoring/Effekseer/1.80.7/Effekseer1.80.7Linux/Tool

The official CLI compiles the authored XML. Python ctypes calls the unchanged
release libViewer.so SWIG Recorder API to render the image. Python does not
draw, resynthesize or postprocess the atlas. No runtime plug-in is installed.

Core.LoadFromXml in official 1.80.7 sets the editor preview IsLoop to true.
The native Recorder calls PlayEffect once. All emitters are finite and have
finished by frame 21. This editor preview behavior does not loop the atlas.

See source-effekseer.json for release URL, tool/input/output SHA256,
source API links, source ownership, recording parameters and verification.
LICENSE_EFFEKSEER_TOOL.txt retains the complete upstream tool notice. The
tool binaries and packaged samples are isolated under .local and are not
included in the game build.
