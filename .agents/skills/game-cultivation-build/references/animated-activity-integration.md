# Animated cultivation activity integration

Use this workflow when a host activity has a visible character performance. Treat animation as a presentation of an existing game action: it must not create a second availability or settlement authority. This note records the integration lessons from shu's formal sword cycle; it does not prescribe that game's IDs, costs, timing, or scene layout to other projects.

## Find the actual host before deciding what is missing

Inspect the active checkout, branch, HEAD, dirty files, untracked files, and relevant worktrees before concluding that an activity or host path does not exist. A useful implementation may live in an uncommitted worktree or in local changes absent from the current branch. Compare the relevant files by diff and hash, then inspect their dependencies and call sites. Preserve the source worktree. When an integration needs code from another checkout, identify a reviewed allowlist and port only what the target requires; importing an entire worktree is not a general rule. Do not reset, clean, overwrite, or silently replace dirty host work.

## Keep one authority for rules and results

The host owns whether the activity is available and all numerical game state: resources, time, growth, counters, and existing interaction flags. The scene/controller connects real controls, applies occupancy gates, and routes entry and return. The presenter owns the selected clip, its playback clock and frames, and any immediate result display; it emits a completion notification such as finished(action_id). It does not charge resources, advance gameplay time, choose rewards, increment progress, or decide that the activity is available.

Resolve stable content identifiers through the host's approved catalog. Preserve identifiers used for selection, save state, or per-activity counts, even if display names or clips change. Map each display choice to an approved clip explicitly. Make the counter describe the host's actual counted activity: do not label a shared combination as several independently practiced moves just because it contains several visible strikes.

## Prepare, settle, perform, return

Before settlement, validate the selected host entry and preflight every resource required for its performance. Load and verify the chosen clip and needed neutral pose so a missing manifest or texture cannot charge the player and then fail to animate. Eligibility should include current host flags, scene occupancy, available resources, and the actor's readiness to enter or return from the pose. Closing dialogue alone is not proof that the character is ready.

Ask the host to validate and settle exactly once at the charge point already defined by that host. The shu sword integration commits immediately before presentation, but that ordering is a case decision, not a universal transaction rule. Pass the returned receipt to presentation as a copied snapshot. It should freeze the selected stable identifiers and the actual costs, gains, duration, and count/result needed for display; never recompute a receipt from current rules or infer values from clip metadata. A rejected action leaves host state unchanged and presents the host's reason.

Once active, gate every path that could change the action's context: repeated starts, selection changes, route changes, return, and conflicting character interactions. Associate completion with an action identifier. Ignore stale callbacks from earlier actions or scenes, and ignore a same-identifier completion while that presenter is still playing. The presenter should finish its recovery to an eligible neutral pose, clear its playing state, and only then notify the host. The host validates the identifier, releases occupancy, returns through its existing route, and presents the actual result. Preserve the host's established interruption, cancellation, and refund behavior; do not invent a new policy while connecting animation.

Follow the host's pause/static contract. In the formal sword case, Static freezes environmental motion and idle breathing while an already-settled active sword action continues to its result and return. An isolated review player may pause the whole timeline, but that behavior must not override the formal host contract.

## Verify the consumer path

Exercise the actual scene controls and loaded resources from the real entry point. Observe one complete action, one settlement, the result, return, and a different subsequent host activity. Check repeated input and stale notifications, insufficient-resource rejection with no partial state change or playback, and the host's reset behavior. Verify existing mentor bonuses, side-quest/Tea state, weather and dynamic preference, and scene state across the round trip where those systems exist. Check that the actor is ready before another action can begin.

Separate synthetic-clock logic checks from rendered-frame behavior, an exported Web consumer, other platform checks, and human playtest approval. A synthetic clock can verify phase transitions and action-ID gates; it is not evidence of real frame rate or visual quality. Record which actual UI, renderer, export, platform, and user outcomes were observed.

Check package closure through the actual engine and exported consumer. Include resources whose paths are assembled dynamically, generated output directories, fonts and required glyphs, parsed JSON value types, GDScript dynamic inference, and floating-point clock boundaries. Godot JSON numeric values can arrive as floats: validate finite integral values rather than requiring an integer storage type. Use explicit GDScript types for values read from dynamic objects when inference fails, and a floating-point tolerance at clock boundaries. Prepare encoder/render output parents before invoking tools. A text or regex scan can help find references, but cannot prove that the runtime can load and use them. Investigate diagnostics in the changed consumer path and keep pre-existing baseline issues separate from new failures. Do not count an engine exit code alone as a clean consumer check.

For the inspected five-sword host, receipt, resource, static-mode, return, and acceptance details are in the [formal five-sword cycle slice](../../../../docs/FORMAL_FIVE_SWORD_CYCLE_SLICE.md).
