# shu project binding — verified 2026-10-04

This binding guides the cultivation-mode skill only and must be checked against current repository rules at execution time. Its scope is the fixed-background activity panel, time/energy/growth settlement, character interactions and side quests staged within fixed cultivation scenes.

- Canonical Windows host: `C:/Users/guoqi/GameDev/projects/shu`; future hosts resolve their own checkout.
- Follow `AGENTS.md`: read README → docs/SPEC → docs/DECISIONS → docs/DEVELOPMENT. They remain mandatory until the repository changes its routing rule.
- Godot 4.7.2 stable and matching export templates are currently pinned; GDScript, Compatibility. Web first, same project for Windows and potential Steam.
- Fixed painted backdrop/panels, Song aesthetics, Q-style cast, mentor interaction within cultivation presentation. Scene weather and character lighting do not tint the UI.
- Mainline authored sources: `jggagi/shu/trunk/`. New side-story authored sources: `jggagi/sub`. Missing locations are reported, not silently substituted. Historical `shu/story/sub/` remains untouched unless migration is explicitly requested.
- Stored story direction alone does not schedule implementation. The current user-selected slice determines scope.
- tea's approved source currently remains at historical `story/sub/tea/README.md`; use that origin until an explicitly requested migration changes it. Supporting tea in the skill does not move the original or activate the entire quest.
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

Current D01 uses 江砚秋 and 叶知闲. Current state and presentation code are `scripts/demo_state.gd`, `scripts/main.gd`, `scripts/weather.gd`, `scripts/weather_cycle.gd`. The proposed `cultivation_mode` addon is not yet installed; detect capabilities before using it. Its current training/rest/mentor rules remain authoritative; relationship mechanics are not implicitly added by the cast roster.

For weather/depth/occlusion work, inspect the installed `painted-scene` integration reference and choose only compatible pieces. Do not import its complete sample project over shu or treat its placeholder actor as approved character art.
