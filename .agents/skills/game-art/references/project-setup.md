# Install into a game repository

Copy the complete `game-art` folder from this catalog into the target game's `.agents/skills/game-art`. An existing `.codex/skills/game-art` layout is also supported. Install only one copy per game, preserving the game's existing rules and assets. Publishing this catalog does not automatically install the skill into other repositories, machines or cloud tasks.

Before production, inspect that game's art directories and provenance. Copy the included `assets/project/art/config.json` to the game's `art/config.json` only if it does not already exist; otherwise review and adapt the existing file. Keep all seven fields, keep the two model names, and set relative directories to the game's actual layout. The scripts and configuration contain no credentials or regional endpoint.

For Godot games, copy `assets/project/art/.gdignore` to `art/.gdignore`; this empty marker is functional and prevents import of candidate material. Add `/art/work/` and Python `__pycache__/` folders to the game's existing `.gitignore`. Keep prompts and provenance versioned when their associated approved assets need reproducibility; exclude unwanted test candidates. Do not overwrite another game's ignore rules or provenance.

## Optional setup helper

Copy `assets/project/Setup-Game-Art.cmd` to the game root and `assets/project/tools/setup_game_art.py` to `tools/setup_game_art.py`, reviewing any existing files before replacing them. On Windows double-click the CMD launcher. It probes a Python 3.12+ runtime, skips the Microsoft Store alias, and supports `GAME_ART_PYTHON` pointing to a working executable. An optional `.local/game-art-python.txt` interpreter cache is host-specific and must stay Git-ignored. Do not commit machine paths.

On macOS/Linux, run the copied helper with the available Python 3.12+ command, for example `python3 tools/setup_game_art.py`. Hidden key entry needs an interactive terminal; do not pipe credentials through stdin or command arguments. The helper stores newly entered settings in its own process environment only. Menu 1 previews offline, menu 2 requires `GENERATE` before one potentially billable request, and menu 0 exits. `--no-input` checks configuration offline without prompts.

For agent-driven Qwen generation, configure `DASHSCOPE_API_KEY` and the complete HTTPS `QWEN_IMAGE_ENDPOINT` ending in `/images/generations` in the agent's host environment. Select a compatible endpoint, key and model region from the provider documentation. Settings entered in the helper do not transfer back to the parent terminal or an already-running Codex process. Host-level changes require restarting the affected application; SSH configuration applies to the remote host, not the SSH client's Mac. Never put the key or a personal endpoint into a committed file.

## Default use

The included `agents/openai.yaml` enables implicit invocation. To establish this workflow in that game's repository rules, add a scoped instruction like:

```text
For raster game-art generation and editing, read and use .agents/skills/game-art/SKILL.md by default, without requiring an explicit trigger. Follow its backend, candidate review and provenance rules. Ordinary code, existing SVG edits and procedural geometry do not trigger paid generation. Keep production inside the current user's authorized scope.
```

Adapt the reference for a `.codex` install. Preserve all unrelated AGENTS instructions. If native discovery does not expose the skill, the agent can read this repository file directly.

## Verify before production

Run the installed `scripts/doctor.py --no-network`, the provided unittest suite, and a Qwen `--dry-run` from a different working directory. These checks use no network. `READY` proves configuration format and local file readiness; it does not prove account credits, authorization, region access or image quality. Only an explicitly requested real online test verifies generation. Do not retry an uncertain billable call automatically.
