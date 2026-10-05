# Scene objects inside cultivation side quests

Use this for fixed-scene investigation with contextual actions. It complements the [side-quest lifecycle](side-quests.md); it is not a new inventory, modal framework or story engine.

## Presentation and host boundary

Compose each object from a stable `id`, `label`, `description`, scene-local `position/anchor`, inspected state and applicable actions. An action supplies an ID, display label, host rule reference, enabled/reason state and an intent callback. Content does not contain executable scripts. The [data example](../assets/scene-objects.example.json) is illustrative, not a new production loader schema.

- The scene controller owns one `selectedObjectId`; the host owns `inspectedObjectIds` and action/milestone receipts. Do not copy numeric state into widgets.
- A hovered object uses a small hint, hand cursor and restrained ink/warm contour. Selected feedback remains subtle; avoid persistent large prop labels or a blue web focus ring. Inspection status remains distinct from selection.
- Click immediately calls the registered host inspect action, marks inspection on success and opens one anchored popover. Selecting another object replaces it. Outside/Escape closes only the popover, not the whole side quest.
- Show object-specific actions near their object with a readable cost before execution. Clamp the popover to the scene, keep the cup/prop body and HUD clear, and use the host logical canvas and its actual viewport transform. Test both object anchors at common window sizes, including aspect-ratio letterboxing.
- A passive journal strip shows recent text from content/result feedback keys, with no primary actions or acknowledgement button. Recoverable action failure stays here and keeps the branch available.

## Settlement and narrative

Validate current session, object/action registration, prerequisites, eligibility and energy before committing. The host returns actual deltas and a narrative key; the controller resolves text from content. Presentation components never mutate story flags or resources.

Distinguish repeatable actions (such as rest) from one-time actions (such as repairing this cup) and one-time quest milestones. Retrying the same request cannot double-settle; rereading cannot repeat rewards. Do not make every action globally one-time just because the current tea actions are. Clue/reveal and cost policies belong to the selected host contract.

Ordinary view/flip/ask/repair and clear light-energy actions have no second confirmation. An explicitly paced dialogue or document may have navigation/continue, but that is not an extra confirmation of a prop inspection. Only genuinely irreversible/high-risk actions use confirmation when their actual semantics require it. Where `await_ack` is explicitly selected for a narrative cue, retain matching-session/node/instance guards; do not apply that requirement to all object clicks.

A stage completion is not whole-quest completion. For a completion-gated branch, only the terminal quest flag permits return to cultivation's main panel. Until then, event ends transition within the branch, scene-local rest remains available, and an unavailable next stage is identified as unfinished content in the branch. Do not silently treat the end of a demo slice as the story ending or implement later chapters without authorization.

## Existing shu implementation, 2026-10-05

- `scripts/interactive_scene_object.gd`: id/label/texture, hover/selected/inspected visuals and selection signal.
- `scripts/scene_object_popover.gd`: object data, action display, scene-local anchor and action-intent signal.
- `scripts/main.gd`: selected object, context routing and passive journal; it is the adapter, not a generic installed addon.
- `scripts/demo_state.gd`: `view_tea`, `execute_tea_action`, `rest_tea`, stage progress, full-quest return gate and receipts. `tea_seen` is the inspected-ID source.
- `assets/data/tea.json` and `tea-layout.json`: descriptions/action definitions and positions. Names come from the cast; game-specific costs stay in host rules/[shu binding](shu-binding.md).

Reuse these two components with different prop data for swords/books/NPCs/herbs when a real selected feature needs them. Supply the corresponding host action whitelist and content; the reusable components do not imply these new gameplay objects already exist.

## Acceptance evidence

Direct inspect 0→1→2, hover/select/inspected states, only one popover, anchored switch/outside/Escape, direct action and actual cost, insufficient/duplicate/stale rejection, passive journal, whole-quest return gate, in-branch rest/reset and affected old cultivation behavior. Record automated state/UI checks, native render, Web build and actual browser input separately. Inspect full visible frames for both objects and size variants; a screenshot omitting letterbox margins is not a full-window screenshot. User approval and other platforms remain separate evidence.

Shortcut labels must reflect the current return gate. In shu, Escape closes an open object popover; without one, an unfinished branch stays open and can report the host reason in the journal. Do not advertise “Esc 返回” while return is unavailable. Page-reopen position remains presentation-local unless the approved host contract says otherwise; it must not silently add a new clue gate.
