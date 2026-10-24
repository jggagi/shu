---
name: game-image-motion-build
description: Produce or revise offline illustrated character-motion clips for fixed-scene Godot games using character references, generated sequences or fixed 3D models, transparent-frame packaging and scene-based review. Use for image-driven sword, staff or narrative motion; excludes gameplay settlement, general video editing and standalone raster art generation.
metadata:
  version: "1.1.0"
---

# Game Image Motion Build

Make a coherent illustrated action in its real scene. A generated image sequence and a fixed-model transparent render are separate production routes; use the approved route and reuse its valid inputs. Preserve the approved character, body scale, motion and source assets. This skill records production methods; it does not install a generator, bundle a runtime/addon, or imply batch-generation or exact 3D-to-image matching.

Read repository instructions and required product documents first. Inspect the requested shot, actual tools, provenance and current changes. Use [the production method](../../../docs/IMAGE_MOTION_PRODUCTION_METHOD.md) as the tool/case index; read the selected source route and affected tool sections instead of loading unrelated historical processing detail. Copy the [shot brief](references/shot-brief-template.md) into the project's appropriate production area for each new move or meaningful variant; retain sources, versions and evidence.

## Choose the source route

- For an approved 3D character rendered into offline RGBA, read [stable-model motion](references/stable-model-motion.md). Keep identity, grip, camera and accepted look stable while authoring the motion; direct transparency need not go through video matting.
- For generated image/video sequences, keep the source review and local-alpha workflow below. A precise motion guide does not guarantee faithful generated poses.
- For formal gameplay integration, route to `game-cultivation-build` and its animated-activity reference. An isolated review controller and its pause/buttons are not the formal host.

## Make one complete action

1. Define identity, costume, weapon/grip, scene, camera, body direction, start—effort—finish and single-shot/loop intent. Review the authored 3D or human motion before full rendering or image generation; include full hair, cloth and weapon travel within the frame. Different moves need different body/weapon motion, not just palette or speed changes.
2. Keep character identity and motion input separately traceable. For local fixed-model rendering, retain source/model/render fingerprints and avoid unnecessary external generation. For generated sequences, keep character art and motion input separate. Use the user's chosen provider and existing authorized inputs/destination/budget. Save task/model/parameters, original result and hashes; mark unknown lineage or fees as unknown. Do not infer perfect pose tracking from an accurate guide. Existing permissions remain valid within their scope.
3. Review source animation at normal/slow speed before full rendering or matting: identity, shoulders/elbows/wrists, hips/knees, hands, weapon count/length/grip, feet and turns. Source crop, lost hands/weapons or wrong movement go back to the source model, motion or generation inputs; shaders cannot repair them.
4. For generated footage, treat alpha as a separate stage. For native RGBA renders, inspect transparency and thin features without automatically re-matting valid source alpha. Compare RGB, original alpha, candidate alpha and real scene. Protect thin weapons, fingers, hair/ribbons and closed clothing. Constrain corrections to reviewed areas/time ranges, preserve out-of-region pixels and retain original packages. Re-author regions/palettes for new shots; current Back Mountain masks are not defaults.
5. Package fixed-size frames with explicit native timing, coordinate systems, atlas regions and contact anchors. Keep apparent body scale stable. Distinguish stable-foot motion from movement, crouching and airborne motion; do not pin every frame's lowest pixel to the ground. Preserve source RGB when the task only changes alpha.
6. Calibrate in the target scene: contact/edge first, world color next, then restrained material. Protect faces, hands, ink and weapons. Read host time/weather and Static; keep UI outside world grading. A/B choices retain the same clock, frame, geometry and state.
7. Verify meaningful asset invariants, deep state preservation and actual target-size renders. View corrected frame sequences, normal/slow play, Static/Resume and source/composited comparisons. Record platform checks and user acceptance separately. Keep unresolved source limits visible in the shot record.

## Reuse without copying the whole demo

Current inputs, media contract, paths and scene profiles are partly hardcoded. Check the method's tool table before running a helper on another shot; do not claim arbitrary videos or new characters already work. Runtime playback reads a frame package; it does not generate poses or own gameplay state. Formal activity settlement and Tea/busy gates belong to the host and `game-cultivation-build`; painted-scene bindings belong to `game-painted-scene-build`; new raster references/assets belong to `game-art`.

Cache immutable source and intermediate results under clear version/hash dependencies. Change only the relevant stage for matte, material or scene feedback. Keep per-shot write sets separate under the repository's delegation rules; one integrator checks character consistency and references. Charged/uncertain generation requests must not silently retry.

Define the agreed count and unit before expanding (for example, whether the approved baseline is included). Each routine needs distinct body/weapon paths and complete recovery. Generalize only the media selection or contact policies demonstrated by actual use cases; a tested sword catalog does not establish two-handed staff, new-camera or multi-character support. Use the real differences to choose the smallest parameterization; do not create a world engine or universal animation framework. Measure package size, loading, resident textures, frame cost, generation success and manual cleanup time before expanding many clips or costumes.

For the historical generated single-shot case and its remaining crop/blur/outro limits, read [Back Mountain v4](../../../docs/SWORD_IMAGE_BACK_MOUNTAIN_SLICE.md). Its 61 frames/25fps, alpha coordinates, anchor filter and mountain material are case data. User acceptance of that clip does not establish arbitrary views, all sword manuals, staff grips, Windows or production performance.

The model-derived five-combination and formal-host cases are indexed in the stable-model reference. Their timing, anchors, page counts, costs and current acceptance are case facts, not defaults.

Deliver the shot/artifact paths, reusable choices, per-shot adaptations, actual checks, user feedback and remaining scaling gates. Keep build, real rendering, browser play, user acceptance and Git/publication status distinct.
