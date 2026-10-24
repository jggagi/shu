# Isolated dialogue-tool evaluation sources

These official fixed-version MIT plugins are used only by the standalone
`tools/build_dialogue_tools_lab.py` stage. The parent `.gdignore` prevents the
formal Godot project from scanning or activating these vendored script classes.
The builder copies each addon's contents into the new stage's normal `addons/`
path; it does not copy this parent ignore marker.

- Dialogue Manager: `v4.1.0`; source archive and SHA256 in
  `dialogue_manager/source.json`, original license in
  `dialogue_manager/addons/dialogue_manager/LICENSE`.
- Dialogic: `2.0-alpha-20`; source archive and SHA256 in
  `dialogic/source.json`, original license in `dialogic/LICENSE`.

No global plugin installation, automatic updating, or formal tool selection is
implied. Native teardown limitations and actual Web observations are recorded in
`docs/DIALOGUE_TOOLS_LAB.md` at the repository root.
