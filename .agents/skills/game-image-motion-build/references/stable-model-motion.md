# Stable-model offline motion reference

Use this path when an approved, reusable 3D character already exists and the deliverable is a set of offline-rendered transparent frames for a real game scene. Keep AI-generated video and other motion-source workflows separate: they have different inputs, controls, and acceptance evidence. This reference describes a way to preserve a stable character while authoring motion; it does not imply mocap, historical technique reconstruction, or complete production acceptance.

Visual acceptance of a reconstructed or high-density model does not certify production topology, a complete finger rig, deformation robustness, or real-time 3D performance. Offline rendered frames and production-ready meshes are different deliverables.

## When the model is not ready yet

Use static views before spending effort on motion: establish a head/bust quality target when the first full-body result is too crude, then inspect front, side and back from the same saved model. Density alone does not fix face, hands, clothing joins, feet or silhouette. Verify usable local export and Blender import before choosing an online preview as the production source. Recheck the provider's current export/subscription/free-quota conditions when that choice is needed; old quotes and an online asset are not proof of a downloadable model. Use the selected provider and the authorized input/destination/cost scope, retaining originals and receipts. Route new raster references through the project's art workflow. Once the look is approved, hold it stable for the motion task instead of regenerating the identity for each move.

## 1. Lock the approved source before animating

Start from the saved approved model and record its identity and source hash. Establish what must stay fixed: face and body identity, mesh and UVs, textures and materials, rig and weights, clothing, weapon-hand assignment and grip, camera, framing, scale, lighting, and the foot anchor. Compare the working model with the approved source using structural fingerprints for rest geometry, UVs, weights, textures, rig, camera, and materials. Animate the rig while keeping those approved inputs stable; investigate any changed fingerprint before rendering a set.

Record weapon grip and blade-axis targets explicitly. A sword that looks attached in a neutral pose can still slip, roll through the hand, or point away from its intended path during a strike. Keep the authored left-hand shape and role within the source model's actual capabilities; do not imply finger articulation when the model has none.

## 2. Prototype the silhouette, then produce the agreed set

Make a short diagnostic first when a motion or render issue is uncertain. Use it to inspect identity stability, silhouette, held weapon, feet, clothing edges, and frame-to-frame flicker. Mark it as a prototype or diagnostic. A small sample does not establish that every production clip is authored or reviewed.

Define the production count before authoring. When the agreed count includes a baseline move, count that baseline among the N routines. Each routine needs its own readable body and weapon path: changing only palette, playback speed, or name does not create a distinct motion. Compare sampled wrist and blade trajectories, along with body and foot movement, to check that authored paths differ in substance. Preserve a catalog ID for every clip and make those IDs unique.

## 3. Author force through the whole body

Build force through anticipation, weight transfer, a committed step where appropriate, a short decisive strike, follow-through or a held finish, and recovery. Speed by itself usually reads as hurried motion rather than weight. Coordinate the hips, torso, shoulders, weapon arm, free arm, head, and feet so the strike has a clear cause and a stable finish. Avoid exaggerated turns or arm poses that break the character silhouette or strain the clothing.

Check wrist target residual, wrist bend, blade-axis error, and foot or leg targets through the action. These numbers catch mechanical problems; they cannot decide whether a weapon path looks natural. Review representative key poses and the continuous clip at normal and half speed. Pay particular attention to preparation, contact or cut, follow-through, and recovery. Revise an action when the blade path, wrist, footwork, or body timing looks wrong even if a numeric report passes.

## 4. Make action and idle boundaries explicit

Author a complete neutral idle and define the action's start, held or striking phases, recovery, and return. The neutral action pose should connect to the idle pose, and the action should finish in its declared return pose. If the game blends or settles back into idle, author and inspect that transition as part of the player-visible sequence. Do not call a one-shot action a loop merely because its first and last poses match.

Compare saved and evaluated boundary poses across the full skeleton, then inspect the rendered endpoint images. Report the actual numerical residual and tolerance: a tiny floating-point difference is not literally zero. For RGBA comparisons, distinguish exact alpha or pixel matches from small channel rounding at shared poses; keep file hashes for integrity and compare decoded pixels for visual equivalence.

## 5. Render and package reproducibly

Render the frames offline from the approved model with alpha transparency. Direct RGBA output avoids unnecessary background matting or color-key removal. Keep timing, frame order, dimensions, color and alpha expectations, anchors, and source dependencies in manifests. The clip catalog should map each stable ID to its label, timing, ordered phase intervals, frame or atlas records, and source/resized anchor values. Make phase boundaries explicit and ordered so a player or reviewer can identify which interval each label covers.

Resume a render from cached frames only when the complete dependency fingerprint matches: model, materials and textures, camera, lighting, renderer/tool versions and settings, evaluated pose inputs, and any simulated cloth/hair state. File presence, timestamps, or a visually similar pose alone are insufficient. Hash completed outputs for integrity, and distinguish reused frames from newly rendered frames in the receipt. A change confined to runtime grading or compositing may reuse immutable source RGBA only when its render dependencies still match; rebuild the affected composites, atlases or scene outputs and inspect the actual scene. A baked character-material change invalidates the affected source renders.

## 6. Bind frames to the real scene and report evidence precisely

Exercise the actual scene from idle through clip selection and playback back to idle. Confirm that the selected ID uses the expected frames and phases, the foot anchor stays stable, and the previous action's atlas references are released when switching clips. A limited set of active atlas references describes runtime resource use; it does not prove that the exported package downloads only those pages or measure actual process memory or VRAM.

Keep evidence categories separate: source/model checks, numeric motion checks, decoded RGBA and media checks, synthetic-clock or logic checks, live real-time behavior, target display sizes, visual review, and user acceptance. A synthetic 30 fps clock is not a real-time performance measurement. A few reviewed key poses or scene captures do not mean every rendered frame was viewed. State exactly which clips, frames, sizes, and runtime paths were observed, and leave unobserved targets or acceptance gates marked unverified.

For the Jiang Yanqiu implementation details and case-specific timing, page counts, names, and acceptance status, see the [five-set record](../../../../docs/image-motion/jiang-five-sword-sets-20261023.md), [sword-reference revision record](../../../../docs/image-motion/jiang-sword-jianshu-20261023.md), and [formal practice slice](../../../../docs/FORMAL_FIVE_SWORD_CYCLE_SLICE.md). Those values describe that case, not defaults for a new character or project.
