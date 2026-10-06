---
name: game-ambient-life-build
description: Add or revise sparse, habitat-driven animal and small life moments in an existing Godot scene, using authored scene capabilities and observed environment or attention state. Use for ambient life presentation; weather and painted composition belong to game-painted-scene-build.
metadata:
  version: "1.0.0"
---

# Game Ambient Life Build

Use this skill to make an existing scene feel quietly inhabited by a small number of scene-appropriate lives. Success means the place feels alive on a second glance, not that it contains more animals. This skill preserves a process and judgment; it does not bundle runtime code, create an addon, or establish a generic animal framework.

The experience is “玩家偶尔发现世界自己在发生事情” in a fixed or semi-fixed scene, not animal AI or an ecology simulation. Birds, squirrels, cats, fish, chickens, butterflies and insects are possible life choices only when the actual scene supports them.

`AmbientLifePresenter` is a reusable **shu module**; `BackMountainAmbientLife` is its scene-specific adapter. The presenter schedules requests from observed state, while the adapter reads habitat markers and owns paths, anchors, assets, animation, and hotspots. Inspect project code and reuse the presenter where it fits. Do not copy its GDScript into this skill or call it a bundled library. Require a second real scene adopter and actual playtest before proposing a generic addon.

## Discover what the scene can actually support

Read repository instructions and required product documents, then inspect the selected scene, its existing art and geometry, state owner, activity/attention signals, and current changes. Pick life only after identifying a real habitat capability in that scene:

- **Sky** supports distant flight only when an open lane and suitable depth are visible.
- **Tree** supports a perched or passing life when an actual branch/path can anchor it.
- **Place** supports a quiet resident such as a cat at a real tree base, windowsill, courtyard, steps, porch, eaves, corner, or rock.
- **Water** supports fish only when the scene already shows suitable nearby water with enough visible surface for the fish to read.

Sky, Tree, Place, and Water are habitat categories, not inheritance classes or required code types. Follow the host scene's existing marker conventions; Back Mountain currently uses a bird lane, a squirrel path, and `CatSpot_Rock`. That rock spot is unsheltered, there is no listening-rain-corridor cat reuse, and Back Mountain has no fish water capability, so its fish presentation is disabled. Do not claim or assume a sheltered cat location or reuse in another scene until that scene authors and validates it.

Use explicit markers or equivalent scene data for path, placement, depth, and relevant traits such as sunny or sheltered. Missing capability means the life is unavailable: do not draw new habitat, invent an invisible path, or enable an animal because its config happens to exist. Prefer sheltered cat places in rain; skip rain presentation when no suitable shelter exists. Reduce or suppress birds and squirrels in weather that would make their activity implausible. Add fish presentation only with actual Water capability.

## Preserve the host's authority and attention

- The host remains the only authority for game time, weather choice, energy, cultivation, quest/story progress, and activity occupancy. Presenters and scene adapters observe those values and return visual requests; they never mutate them.
- Suppress new attention when the host is busy with training, dialogue, object inspection, a story beat, or another clearly foregrounded interaction. Existing residents should settle into a quiet pose; define how active pass-through events yield without an abrupt distracting cut. Keep this as an input from the host, not a second copy of its state.
- Schedule occasional opportunities with a seeded random generator and elapsed-time boundaries. Never call `randf()` per frame to decide whether an animal appears. A fixed seed makes QA repeatable; ordinary output stays sparse and allowed to vary when the host supplies another seed.
- Keep one salient moving event at a time. A quiet resident may remain as a low-key second or third glance if it does not compete with the foreground. Treat intervals, chances, duration, and counts as scene-specific tuning data, not permanent shu defaults.
- If a specific slice authorizes a brief animal interaction, keep its response local to that scene presentation and preserve the same host-state boundary. Do not infer pet progression, rewards, AI, or new interaction systems from ambient-life support.

## Define motion, weather, and Static behavior

Map discrete host weather/time profiles to scene-specific opportunity rules and continuous presentation values. Prefer a sheltered cat place when raining; lower or remove bird and squirrel opportunities in rain. Let fish change presentation only when an authored Water capability exists.

Specify Dynamic/Static behavior for each life category before implementation. Fast flight or branch movement may hide while Static is on; a resting cat may stay visible at a known idle pose with its hotspot disabled. Resume from a defined state. Never freeze an animal on an arbitrary animation frame or leave an interaction hotspot active for hidden/frozen motion. Dynamic OFF must keep the scene populated according to this explicit policy while stopping the selected motion and schedule clocks.

Keep the current shu presenter choices (`birds`, `squirrel`, `cat`, `fish`) until another real scene requires a change. Habitat categories do not justify an ECS or inheritance refactor for possible future species.

Fit art to the actual scene: check scale, silhouette, value contrast, outline/edge weight, foot/perch anchors, and depth against the real background. Put distant life behind mountain/trees and place residents on the surface that grounds them. Avoid transparent-image translation that reads as a flat card crossing the painting.

## Build and review a small slice

1. Reuse one suitable authored capability and one or two lives for the first slice.
2. Connect the host's observed time/weather, Dynamic state, and foreground-busy signal to the existing presentation boundary. Keep opportunity config separate from scene paths and visual assets.
3. Render controlled base, life-present, motion, adverse-weather, busy, and Static states. Inspect real screenshots for scale, anchors, occlusion, density, and foreground focus.
4. Keep deterministic state checks, actual rendered-image review, and user playtest as separate evidence. Automated success does not prove that the life feels natural or that the user likes its density.

Record which states and screenshots were checked and what remains untested. Ask for user direction when the scene's desired life changes its meaning, gameplay role, or story; make ordinary reversible placement and timing choices within the authorized slice.

## shu implementation references

- [AmbientLifePresenter](../../../scripts/ambient_life_presenter.gd) contains deterministic opportunity scheduling, observed context, capability checks, and active-event limits.
- [BackMountainAmbientLife](../../../scripts/back_mountain_ambient_life.gd) reads actual habitat markers and owns its scene paths, cat place selection, poses, layer placement, and interaction hotspot.
- [Back Mountain habitat markers](../../../scenes/demos/back_mountain_training.tscn) show the authored `SkyBirdLane`, `SquirrelPath`, and `CatSpot_Rock` capabilities.
- [Ambient life config](../../../assets/data/back_mountain_ambient_life.json) shows example schedule and motion data; its values are not universal defaults.
- [Back Mountain slice notes](../../../docs/BACK_MOUNTAIN_SLICE.md) document capability choices, the absent fish habitat, weather/attention/static behavior, actual renders, and user-playtest status.
