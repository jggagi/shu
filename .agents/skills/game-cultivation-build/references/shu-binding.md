# shu project binding — checked 2026-10-06

This binding guides the cultivation-mode skill only and must be checked against current repository rules at execution time. Its scope is the fixed-background activity panel, time/energy/growth settlement, character interactions and side quests staged within fixed cultivation scenes.

- Resolve the active checkout on each host; repository-relative paths below are the contract. Detect installed capabilities rather than copying another host's paths.
- Follow `AGENTS.md`: read README → docs/SPEC → docs/DECISIONS → docs/DEVELOPMENT. They remain mandatory until the repository changes its routing rule.
- Godot 4.7.2 stable and matching export templates are currently pinned; GDScript, Compatibility. Web first, same project for Windows and potential Steam.
- Fixed painted backdrop/panels, Song aesthetics, Q-style cast, mentor interaction within cultivation presentation. Scene weather and character lighting do not tint the UI.
- Mainline authored sources: `jggagi/shu/trunk/`. New side-story authored sources: `jggagi/sub`. Missing locations are reported, not silently substituted. Historical `shu/story/sub/` remains untouched unless migration is explicitly requested.
- Stored story direction alone does not schedule implementation. The current user-selected slice determines scope.
- Tea's current authored source is `jggagi/sub/tea/full-chain.json`, pinned by `assets/data/tea-full-provenance.json` at revision `50acc08b5cdd7d8a83525f1c0c1102ca9b7d6ca5`; runtime snapshot `assets/data/tea-full-source.json` SHA256 is `8fe564cb9455c8006e2441560bbd1d64c9053b46ae79691b5797bd4f4a319afc`. Historical `story/sub/tea/README.md` remains in place; the package's illustrative adaptation plan still pins that historical source and is not the playable implementation.
- Keep art origins, exact source references and notices. Reference archetypes do not authorize copying protected dialogue or art.

| Stable ID | Display name |
| --- | --- |
| `player_yanqiu` | 江砚秋 |
| `disciple_tinglan` | 沈听岚 |
| `disciple_xiaotang` | 唐小棠 |
| `disciple_yunzhou` | 顾云舟 |
| `mentor_zhixian` | 叶知闲 |
| `mentor_tingyun` | 陆停云 |
| `mentor_jianqing` | 唐见青 |
| `elder_xuanshi` | 玄石真人 |
| `uncle_guantao` | 余观涛 |

Current D01 uses 江砚秋 and 叶知闲. The user reconfirmed 叶知闲 for tea contextual actions on 2026-10-05. Current state and presentation code are `scripts/demo_state.gd`, `scripts/main.gd`, `scripts/weather.gd`, `scripts/weather_cycle.gd`. The proposed `cultivation_mode` addon is not yet installed; detect capabilities before using it. Its current training/rest/mentor rules remain authoritative; relationship mechanics are not implicitly added by the cast roster.

For fixed-scene environment work read repository `game-painted-scene-build`; for ambient life read `game-ambient-life-build`; for raster production read `game-art`. These skills describe production methods. `EnvironmentPresenter` and `AmbientLifePresenter` are reusable shu modules consumed by Back Mountain adapters, not libraries bundled with these skills or a generic Godot runtime. Both observe presentation context without owning energy/time/quest settlement. Tingyu Corridor reuse of these modules is not implemented.

## Repository and acceptance snapshot

Recheck at every task start; this is an inspected snapshot, not a permanent claim about branch or deployment state.

- Active local branch `main`, HEAD `e7fa4207c721f78103abfb04a191a61a9bf05942`, dirty and untracked Tea/Back Mountain files. Cached `origin/main` was `07bd2ee`; the active checkout was not reset, pulled or cleaned.
- Live GitHub check: PR #3 (Back Mountain orange cat) is **MERGED**, not draft. Tea PR #4 (`codex/tea-full-past-scenes`, head `973c4b2eddfb246000ddfe47e3f0e1f3389337f2`) is also **MERGED**. Live remote main is `89e43692deaacf9ca66fb39c3a91a8ea0f437b30`. Old draft/archive-only descriptions are historical.
- The local working state is ahead of its checked-out HEAD, but inspected Tea implementation is already in remote canonical main: 44 of 45 selected Tea scripts/data/tests/art files match main Git blob hashes. The sole difference is local `tea-full-provenance.json`'s old D032 memory-description line; main names D033/D034/D037. The source snapshot is identical. Preserve the local metadata; do not infer new local-only stages from dirty/untracked status. Fourteen inspected environment/ambient/Back Mountain module and data files also match main.
- A/B and C have recorded player approval (D023–D025, D029); full implementation and past-scene direction were authorized (D031/D033/D034/D037). Full Tea experience and latest past tableaux still await player acceptance. Source merge does not establish that acceptance or a new deployment.
- Existing logs were inspected, not rerun: full host 153 checks / 0 failures, memory 619 / 0, full UI 2257 / 0, native UI 2359 / 0. `docs/TEA_PAST_ALL_VALIDATION.md` records Web/Windows export and a real browser full journey; Windows device play, mobile, audio and long-run verification remain unverified. These are prior evidence, not this skill-edit round's tests.
- README/handoffs record online root A/B 0.1.4 and Back Mountain Clouds v1; this round did not verify or change live deployed content. Local candidate identity is `0.1.9-tea-past-local / tea-past-local-1`.

Read current `docs/TEA_HANDOFF.md`, `docs/TEA_GITHUB_HANDOFF.md` and `docs/TEA_PAST_ALL_VALIDATION.md` in the host repo for continuation and evidence. Preserve older dated entries as history; do not let A/B-only statements override the inspected current implementation.

## Current tea host contract

A/B direct prop inspection, anchored contextual actions and passive journal remain. The old claim “C–I/end are not implemented” is obsolete: `demo_state.gd` implements C prerequisites, sequential story stages, guarded page reads and the final same-ID double-cup pour; `main.gd` connects these paths and returns to cultivation only after the real terminal gate. `tea-full-source.json` supplies C through the ending. There is no remaining C–I story gap identified in these inspected paths; full experiential acceptance is still pending.

Keep stage implemented, stage complete, quest complete and user approved distinct. `tea_stage_complete` means A/B cups inspected, `tea_c_complete` means household/ledger prerequisites met, and `story_stage_complete()` gates each later stage. Only the valid terminal second pour after the host's pause sets `tea_quest_complete`; `can_return_from_tea()` enforces whole-quest return. A completed intermediate stage, document close or memory close retains the accepted branch.

`scripts/tea_memory_scene.gd` exists and is instantiated by `main.gd`. It presents fixed past tableaux, dialogue/page transitions, holds and close/return intents, with tokens/session and retired-view protection. It reads `tea-memory-layout.json`, Tea object IDs, names and labels: it is story-specific presentation, not a general narrative player. Do not extract `NarrativeSequencePlayer` before a second different narrative use case actually needs picture/page sequence, dialogue, hold and close/return.

Current first-cup repair costs the host `training_cost` (22), contextual ask uses `mentor_cost` (8); those are shu bindings, not universal skill costs. Repair/ask receipts are once per object per run. Reading/inspection has no energy/time cost. `rest_tea` uses the same capped rest settlement/duration as cultivation, is repeatable, and retains the branch. Unaccepted commission can be declined before entry; accepted unfinished branch cannot cancel/return. Explicit restart starts a fresh run and clears flags/receipts; no disk save is implemented. Synthetic terminal fixtures remain test evidence only; today's implementation also contains the actual ending path.

`InteractiveSceneObject` is a reusable behavior contract with shu-specific presentation (查看/已阅, colors and inline shader). `SceneObjectPopover` shares object/action/session intent but still binds `paper-frame-v2.png`, colors and action text. Neither is fully theme-agnostic. Keep host state separate; evaluate theme/text extraction only against a second real interaction use case.
