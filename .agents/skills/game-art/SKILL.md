---
name: game-art
description: Generate or edit raster game art, scene references, characters, NPCs, props, backgrounds, sprites, raster UI icons and reference-driven variants. Use for image production or art-direction exploration; exclude ordinary programming, CSS, SVG edits and procedural geometry without requested image generation.
---

# Game art

Keep user art direction and the repository's active rules. Read [prompt-contract.md](references/prompt-contract.md) to prepare the generation brief. Distinguish reference images from edit targets; use only images selected for this request. Read [provider-policy.md](references/provider-policy.md) for routing and Qwen protocol details.

Install this repo-scoped skill into the target game's `.agents/skills/game-art` (or `.codex/skills/game-art`). Before first use, follow [project-setup.md](references/project-setup.md) to adapt the included configuration to that game's existing art directories. The scripts locate the game repository from their installed path; do not install this package globally and expect it to select a game from the caller's working directory.

## Reference-to-production division

Default to a cost-conscious workflow: **Codex establishes references; Qwen produces assets in quantity.** Use Codex built-in image generation for a small set of scene, character and style references that establish the visual direction. Reuse selected references when they already exist. Pass those references to Qwen, inspect a small production sample for style, identity and usability, then expand the successful approach into the requested batch. A small batch or an important character alone does not move routine production back to Codex. Follow the user's explicit backend choice when supplied.

For Codex references or an explicitly requested Codex image/edit, use the available `$imagegen` skill / `image_gen` tool at agent level, following its tool instructions. No `OPENAI_API_KEY` is needed for this route; do not wrap it in Python or silently use the paid OpenAI Image API. If unavailable, continue with configured Qwen and state the backend switch.

Use the repo CLI for bulk, many candidates, routine props/backgrounds/sprites/NPCs and explicit Qwen requests. Default to `qwen-image-3.0`. Pass `--model qwen-image-3.0-pro` only on explicit user request. A missing Qwen configuration requires its two environment variables; do not choose a paid OpenAI fallback. Real generations cost money: run them only within the user's requested scope. Validation stays offline unless the user explicitly requests a real online generation test. Do not retry failed/uncertain billable calls automatically.

## Scene-calibrated game assets

素材本身好看 ≠ 放进游戏场景后成立。Inspect the actual game scene and existing cast/style first; establish or select a reference before producing transparent character, animal or prop poses. Review a small sample in the real scene before expanding a batch.

Check intended display scale, silhouette, value/color, edge quality and visual weight against the scene, including nearby actors and the dominant composition. Inspect alpha and crop, then check contact with the actual ground, branch or furniture; approval on a transparent checkerboard alone is insufficient. Back Mountain's orange-cat revision is a concrete example: the flat SVG was technically usable but felt foreign; scene-referenced watercolor poses and per-pose anchors addressed the mismatch.

For multi-pose assets, record pose identity, crop/atlas region, foot or contact anchor (with coordinate origin/units) and intended display scale. Preserve exact prompts, references, author/provider, usage/permission notes and SHA256 alongside selected assets. Pose changes should preserve contact and apparent body size when placed in the scene.

This skill delivers raster assets, pose sheets, inspected alpha, crop/contact metadata and art provenance. Final Godot clickable rects, Area2D/Control hitboxes, input gating and coordinate transforms belong to the implementation skill / scene adapter; an art crop is not an interaction contract.

## Repository workflow

- Inspect `art/config.json` and existing provenance before selecting destinations. Reuse the target game's existing reference and approved-asset directories; preserve existing `source.json` records. The starter configuration uses `docs/concepts` for references and `assets/art` for approved assets, `art/work` for candidates, `art/prompts` for exact prompts and `art/manifest.jsonl` for provenance. Empty working directories are created on demand. For Godot projects, `art/.gdignore` excludes this production workspace from import.
- Save the exact UTF-8 prompt to a repo file. Preserve project-bound built-in output in the configured work directory (copy selected tool output using portable file operations) and record it with `art_manifest.py --provider codex-imagegen --purpose "scene reference" --prompt-file art/prompts/scene.txt --output art/work/scene.png` (adapt paths to config). Add repeatable `--reference` paths as used. Leave the hidden Codex model unset.
- Run Qwen with `qwen_image.py`. It saves images atomically and automatically records successful provenance and exact prompts; do not append a duplicate record. `--reference` accepts up to three repo-local raster files or explicitly selected HTTPS URLs. All filesystem arguments resolve from the script's repository, even when invoked from another cwd. Use repo-relative paths across hosts.
- Review images before approval: framing, style, identity, legibility, alpha when needed, and unwanted text/watermarks. Qwen 3.0 does not document a transparent-background switch: do not invent one or claim true alpha without inspection. Copy only selected assets into the configured approved directory; record that output with `--status approved`. Never replace existing game art or modify scenes without the requested scope.
- Store no credentials, endpoint, personal absolute paths or unrelated system data in config/provenance. Signed URL queries are omitted from provenance; exact URLs are used only in the selected request. Prompt/reference files remain project material, not general logs. Manifest writes must run serially, including bulk jobs.

## Portable commands

Use a working Python 3.12+ command; no shell-specific core logic or external packages. On Windows detect `py -3.12` or `python`; on macOS/Linux use the available Python 3.12+ command. Commands below use the `.agents` installation and assume repo cwd; scripts themselves do not. For a `.codex` installation, replace `.agents` in these paths.

```powershell
python .agents/skills/game-art/scripts/doctor.py --no-network
python .agents/skills/game-art/scripts/qwen_image.py --prompt "painterly mountain courtyard environment concept" --out art/work/courtyard.png --dry-run
python .agents/skills/game-art/scripts/qwen_image.py --prompt-file art/prompts/courtyard.txt --out art/work/courtyard.png --reference docs/concepts/selected-reference.png --purpose "courtyard candidate"
python -m unittest discover -s .agents/skills/game-art/tests -v
```

Real Qwen requests require process environment `DASHSCOPE_API_KEY` and the complete `QWEN_IMAGE_ENDPOINT`, with model/key/endpoint in a matching provider region. Doctor never calls the network; READY means local configuration only. Dry-run validates arguments, redacts prompt/reference/credentials and makes no network calls or writes. One CLI invocation produces one PNG; invoke serially for batches. Outputs are preserved on failed downloads; existing files require explicit `--overwrite`.
