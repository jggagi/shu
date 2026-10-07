---
name: game-ambient-life-build
description: Add or revise habitat-driven animal and small life moments in an existing Godot scene, using authored scene capabilities and observed environment or attention state. Use for ambient life presentation; weather and painted composition belong to game-painted-scene-build.
metadata:
  version: "1.1.0"
---

# Game Ambient Life Build

Use this skill to make an existing scene feel quietly inhabited by a small number of scene-appropriate lives. Success means the place feels alive on a second glance, not that it contains more animals. This skill preserves a process and judgment; it does not bundle runtime code, create an addon, or establish a generic animal framework.

The experience is “玩家偶尔发现世界自己在发生事情” in a fixed or semi-fixed scene, not animal AI or an ecology simulation. Birds, squirrels, cats, fish, chickens, butterflies and insects are possible life choices only when the actual scene supports them.

`AmbientLifePresenter` is a reusable **shu module**, used by Back Mountain and the local Tingyu adapter. It schedules requests from observed state; adapters own habitat geometry, poses, interaction and scene event coordination. Inspect project code and reuse the presenter where it fits. For resident motion, moving hotspots or interaction feedback, read the [Tingyu case](../game-painted-scene-build/references/tingyu-corridor.md). Keep runtime code in the project; extracting an addon still requires demonstrated common needs and actual playtest.

## Discover what the scene can actually support

Read repository instructions and required product documents, then inspect the selected scene, its existing art and geometry, state owner, activity/attention signals, and current changes. Pick life only after identifying a real habitat capability in that scene:

- **Sky** supports distant flight only when an open lane and suitable depth are visible.
- **Tree** supports a perched or passing life when an actual branch/path can anchor it.
- **Place** supports a quiet resident such as a cat at a real tree base, windowsill, courtyard, steps, porch, eaves, corner, or rock.
- **Water** supports fish only when the scene already shows suitable nearby water with enough visible surface for the fish to read.

Sky, Tree, Place, and Water are habitat categories, not inheritance classes or required code types. Follow the host scene's existing marker conventions; Back Mountain currently uses a bird lane, a squirrel path, and `CatSpot_Rock`. That rock spot is unsheltered and Back Mountain has no fish water capability. Tingyu now authors its own sheltered desk spots and short path, with a local cat adapter. Those capabilities come from its actual roof and tabletop; author and inspect them again in any new scene.

Use explicit markers or equivalent scene data for path, placement, depth, and relevant traits such as sunny or sheltered. Missing capability means the life is unavailable: do not draw new habitat, invent an invisible path, or enable an animal because its config happens to exist. Prefer sheltered cat places in rain; skip rain presentation when no suitable shelter exists. Reduce or suppress birds and squirrels in weather that would make their activity implausible. Add fish presentation only with actual Water capability.

## Preserve the host's authority and attention

- The host remains the only authority for game time, weather choice, energy, cultivation, quest/story progress, and activity occupancy. Presenters and scene adapters observe those values and return visual requests; they never mutate them.
- Suppress new attention when the host is busy with training, dialogue, object inspection, a story beat, or another clearly foregrounded interaction. Existing residents should settle into a quiet pose; define how active pass-through events yield without an abrupt distracting cut. Keep this as an input from the host, not a second copy of its state.
- Schedule occasional opportunities with a seeded random generator and elapsed-time boundaries. Never call `randf()` per frame to decide whether an animal appears. A fixed seed makes QA repeatable. Tune encounter density to the requested experience: a frequent quiet resident and a rare distant flight can have different schedules. First-arrival opportunities, repeat intervals and residence time are separate parameters; Busy/weather gates can defer an opportunity, so it is not an arrival deadline. Record actual waiting separately from accelerated previews.
- Coordinate salient events with the scene host. A quiet resident can remain while another event passes, with its movement paused where needed. A moving animal may defer a new gust or bird opportunity, but do not feed its own salience back into a gate that prevents that same animal from advancing. Treat intervals, chances, duration and counts as scene-specific tuning data.
- If a specific slice authorizes a brief animal interaction, keep its response local to that scene presentation and preserve the same host-state boundary. Do not infer pet progression, rewards, AI, or new interaction systems from ambient-life support.

## Define motion, weather, and Static behavior

Map discrete host weather/time profiles to scene-specific opportunity rules and continuous presentation values. Prefer a sheltered cat place when raining; lower or remove bird and squirrel opportunities in rain. Let fish change presentation only when an authored Water capability exists.

Specify Dynamic/Static behavior for each life category before implementation. Fast flight or branch movement may hide while Static is on; a resting cat may stay visible at a known idle pose with its hotspot disabled. Resume from a defined state. Never freeze an animal on an arbitrary animation frame or leave an interaction hotspot active for hidden/frozen motion. Dynamic OFF must keep the scene populated according to this explicit policy while stopping the selected motion and schedule clocks.

Keep the current shu presenter choices (`birds`, `squirrel`, `cat`, `fish`) until another real scene requires a change. Habitat categories do not justify an ECS or inheritance refactor for possible future species.

Fit art to the actual scene: check scale, silhouette, value contrast, outline/edge weight, foot/perch anchors, and depth against the real background. Put distant life behind mountain/trees and place residents on the surface that grounds them. Avoid transparent-image translation that reads as a flat card crossing the painting.

## Resident poses, travel and interaction

When the user requests more resident activity, choose a short authored route on a real supporting surface. Let rest, stand, travel, sniff/sit and return phases vary the encounter; several articulated gait poses can convey steps better than moving one unchanged PNG. Travel and body motion should follow the permitted presentation delta and preserve their local phase across pauses. They do not advance gameplay time.

- Record each pose's atlas region, contact pivot and intended scale. Different image dimensions or crops need per-frame scaling; changing pose or facing must keep feet on the same surface and preserve apparent size. Check both directions and the pause/interaction pose in actual renders.
- Convert anchors and paths through the correct parent transform, including host scaling. A texture's source pixels, logical scene coordinates and displayed viewport pixels are different spaces. Validate contact in more than one window size.
- During Busy/Static, choose a readable resting, sitting or standing pose at the current position, and preserve the underlying travel phase. Resume from that position rather than returning to the original spot. Freeze encounter fades as well as motion.
- Derive a moving hotspot from the current pose bounds, pivot, scale and facing. Gate it on actual visible scene and interaction availability; disabled or hidden hotspots should pass input through. Check overlap with nearby objects and whether the visual response preserves facing/contact.
- If a custom interaction cursor is requested, its gesture should communicate the action at small display size: petting suggests a palm-down touch rather than a raised stop hand. Align its click hotspot with the contact fingertip, keep other controls' cursors distinct, and release the custom mapping when its owning scene is freed. A material import or cursor registration log does not establish real hover/click usability.

See the [Tingyu resident example](../game-painted-scene-build/references/tingyu-corridor.md#resident-motion-and-interaction) for current paths, pose metadata, pause gates and the cursor feedback history. The specific animal, route and frequency remain the new scene's decisions.

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
- [Tingyu adapter](../../../scripts/tingyu_ambient_life.gd), [desk motion helper](../../../scripts/tingyu_cat_desk_motion.gd), [scene markers](../../../scenes/main.tscn) and [schedule](../../../assets/data/tingyu_ambient_life.json) are current scene-specific examples.
- [Back Mountain slice notes](../../../docs/BACK_MOUNTAIN_SLICE.md) document capability choices, the absent fish habitat, weather/attention/static behavior, actual renders, and user-playtest status.

New-scene application: [Mountain Gate Courtyard](../game-painted-scene-build/references/mountain-gate-courtyard.md) records the independent three-system slice, new masks/stone landing and the actual cat-path helper boundary; its validation remains scene-specific.
