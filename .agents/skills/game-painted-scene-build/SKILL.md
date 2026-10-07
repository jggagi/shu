---
name: game-painted-scene-build
description: Design or revise fixed illustrated Godot scenes through painted composition, flexible depth layers, time and weather grading, and restrained environmental motion. Use for visual scene slices; habitat-driven animal moments belong to game-ambient-life-build.
metadata:
  version: "1.1.0"
---

# Game Painted Scene Build

Use this skill when the fixed illustrated scene is the main experience and the task is to make its composition or motion clearer, more atmospheric, or more pleasant to inhabit. Save visual judgment and a repeatable review process; this skill does not bundle runtime code, create an addon, or replace a game's scene and asset pipeline.

It is for fixed painted / 中国画 / painterly scenes, not a general game-development, 3D environment, free-roaming map, combat or shader-library skill.

`EnvironmentPresenter` is a reusable **shu module**, used by Back Mountain and Tingyu Corridor. Their adapters bind different artwork, masks and effect nodes. Inspect that project code and reuse the presenter where it fits; its current time/weather IDs follow shu. Keep new geometry and effect bindings in the target scene adapter. Read the [Tingyu case](references/tingyu-corridor.md) when coordinating weather, indoor life, character presentation or event-driven sound. The case records local implementation and evidence limits. An addon requires demonstrated shared needs and actual playtest; these skills contain methods and references rather than runtime code.

## Start from the scene and the visible goal

1. Read repository instructions and the required product documents. Inspect the active scene tree, its controller, art, layout/profile data, state authority, and current changes before editing.
2. State one player-visible goal for the authorized slice. Keep proposals distinct from decisions and from verified results.
3. Improve art and composition first. Establish the focal point, silhouette, depth, and readable space for characters and UI before adding effects. Use far, middle, near, and actor layers when useful; their number and order follow the actual artwork rather than a fixed layer contract.
4. Add only a few high-value motions after the still composition works. Prefer clearly readable cloud or shadow drift, mist, wind, water, a simple time-of-day grade, or action feedback. Avoid defaulting to many lights, occluders, contact shadows, normal maps, or 2.5D structure. Consider them only when a small comparison shows a clear visible gain.

D028 is a useful counterexample: the lighting experiment was technically sound and its checks passed, but the player saw too little benefit for its complexity. Treat real player-visible value as its own acceptance gate; a passing compile or render test does not justify adding more technique.

先做出玩家肉眼能感知的变化，再考虑技术复杂度。If realtime lighting, occlusion or shadows add substantial complexity while the visible difference remains small, stop investing in that route; use it when a clear visible benefit justifies it.

## Clouds, depth, wind and rain

Use a far cloud in the actual sky space and valley clouds where they can partly veil mountain waists. Inspect the artwork's opaque sky and transparent mountain edges before choosing layer order; a cloud hidden behind opaque painted sky has no visual value. Keep near rocks, actors and UI readable in front. Different coherent speeds and phases can make distance perceptible without increasing layer count; cloud shadows should visibly affect broad world areas with soft, low-frequency variation.

Avoid the feeling of a transparent PNG simply sliding sideways: use soft irregular edges, restrained deformation/variation and meaningful mountain occlusion, then inspect successive real frames. Wind and rain stay small and do not steal the subject. Rain in a Chinese painting has low visual presence, but at the actual play window it must still distinguish a rainy moment from cloudiness. Tune cloud amount, mist and large-scale grading with rain rather than escalating particles or lights.

## Coordinate effects through the place

Choose effects supported by the artwork: moving leaves or a hanging ornament for wind, a real roof edge for drips, a lamp for local warmth, a hot vessel for steam, and an incense burner for smoke. Author their masks and contact/emission points from the actual scene. A useful still composition can need only one effect; a requested complete scene can contain several with coordinated attention.

- Let one wind phase influence related leaves, cloth, vapour and a leaf-sound opportunity. Independent loops can make the same gust feel unrelated across objects.
- Preserve useful weather history: continuous rain can collect water and wet surfaces; after rain stops, bounded residual drips and drying can outlast the rain lines. Put accumulation, release and clear-on-reset behaviour in the adapter rather than inferring them independently in each shader.
- Calibrate local dusk warmth against the actual lamp and nearby surfaces. Keep faces, ink and dark frames legible; use bounded masks instead of raising brightness over the whole picture.
- Give steam and smoke an actual vessel origin and a thin, fading rise. Check the prop itself before adding vapour: stretching a desk image can flatten its baked-in vessel. A separate source crop and local restoration mask may correct it, but source coordinates and masks must be authored again for a new painting.
- For approved character micro-motion, read host action/dialogue state. Keep faces, hands and furniture contact stable while animating a local breathing region. Route new raster poses through `game-art`; action rules and settlement remain with the cultivation skill/host.
- When sound is in scope, drive cues from the same real gust, drip, animal or action event as the visual. Define Busy ducking, Static fade/pause, mute and scene-leave behaviour together; drop obsolete queued cues on reset or departure. Hearing on the target device remains a separate review from engine mixing.

For the concrete bindings and a new-scene handoff, read only the relevant sections of the [Tingyu case](references/tingyu-corridor.md). Its coordinates, effect selection and numerical tuning are examples, not scene defaults.

## Keep presentation attached to real scene state

- Read the host's actual time and weather state. A presentation profile can map those discrete states to continuous visual values such as brightness, tint, sky strength, cloud amount, or mist, then blend between profiles smoothly.
- Keep a weather choice separate from continuous motion such as wind, cloud drift, water flow, or rain. Do not create a second game clock, random weather authority, or gameplay effect for a visual transition.
- Profile values and transition speeds are scene-specific production parameters. Do not copy Back Mountain's numbers as universal shu defaults.
- Keep status panels, dialogue, buttons, and other UI outside world lighting or scene grading unless the requested design explicitly includes them.
- Define Static behavior before implementing it: keep the populated scene visible and freeze the intended motion, fades and local motion phases. Feed shaders the controlled presentation elapsed value when they must freeze, rather than allowing independent shader time to continue. State whether a requested time/weather change still transitions while motion is frozen. Preserve the freeze/resume contract through reset and scene departure.
- Separate host foreground Busy from the salience of ambient events. An active event can defer new competitors; its own salience must not block its own progress. Review the coordination between environment, actors and ambient life when adding another effect.

## Make a small, comparable slice

Use the existing scene → composition → one to three high-value motions → small implementation slice → Static/Dynamic comparison → rendered-image review → user playtest sequence. Tune the first idea against actual screenshots before adding another effect. Do not generalize a scene-specific implementation until another real scene needs it.

For review, render the real scene at useful window sizes and inspect the result: focal hierarchy, layer occlusion, silhouette, edge/alpha behavior, motion that reads as art rather than a translated transparent image, and UI/face readability. Compare Static and Dynamic at the same host state. Record compile/import checks, automated checks, actual render review, and user playtest separately. Only a user playtest establishes the user's visual acceptance.

When new raster artwork is requested, follow the repository's [game-art workflow](../game-art/SKILL.md). Keep selected art, source records, and scene changes within the authorized slice.

## shu implementation references

- [EnvironmentPresenter](../../../scripts/environment_presenter.gd) reads profile data, composes values, and blends time and weather independently.
- [BackMountainEnvironment](../../../scripts/back_mountain_environment.gd) applies those values to the painted world layers and shaders while leaving UI presentation outside that world treatment.
- [Back Mountain scene controller](../../../scripts/back_mountain_training.gd) shows how the current host time, weather preview, Static/Dynamic choice, and environment modules meet.
- [Environment profile data](../../../assets/data/back_mountain_environment.json) is a scene-specific example, not a default parameter set.
- [Tingyu adapter](../../../scripts/weather.gd) and [profile](../../../assets/data/tingyu_environment.json) show coordinated scene effects; artwork masks and indoor anchors stay specific to Tingyu.
- [Back Mountain slice notes](../../../docs/BACK_MOUNTAIN_SLICE.md) record the Lighting v1 / D028 feedback, the simpler environment work, screenshots, and validation boundaries.

New-scene application: [Mountain Gate Courtyard](references/mountain-gate-courtyard.md) records the independent three-system slice, new masks/stone landing and the actual cat-path helper boundary; its validation remains scene-specific.
