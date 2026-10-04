---
name: game-cultivation-build
description: "Build and iterate fixed-scene cultivation/life-sim mode in an existing Godot GDScript game: time/energy, activities, growth, character events and side quests such as tea through staged fixed scenes, object inspection, documents and short memories. Use for cultivation-mode implementation and playtest feedback; not free-roaming exploration, combat, standalone story engines or game initialization."
metadata:
  version: "0.1.0"
---

# Game Cultivation Build

Build the cultivation loop: select activity → validate availability → perform activity or character interaction → settle time/energy and actual gains → return to the activity panel. Keep the interactive method: user direction → playable mode slice → user playtest decision → revision → next acceptance point.

This skill specializes in fixed-background/panel cultivation mode. Training, rest, study, character interactions and staged side quests are registered activities/events; include only those requested or already present. A side quest may use several fixed scene profiles, inspectable objects, document panels and a short memory sequence, returning to cultivation after each segment. Free-roaming exploration, combat, standalone story engines and unrelated modes require their own workflow.

## Start with the active project and authorized slice

1. Read the effective repository rules, branch/HEAD and worktree status. Follow required kickoff reads; this skill does not replace them with a summary.
2. Identify approved mode rules, the selected activity/event and the runtime actually installed. Distinguish approved decisions, proposals, implemented behavior and observed verification.
3. For shu, read [project binding](references/shu-binding.md). For another project, use its actual IDs, routing and capabilities; do not copy shu's cast or story locations.
4. A design-only request produces a proposal. It does not install this skill, extract runtime modules or start a game. An implementation request covers its selected cultivation activity/event; commits, remote saves and releases follow existing authorization.

## Specify the cultivation activity or event

For a small wording or layout correction, reuse the active slice card and source references. Change the affected content/layout, check the changed branch or view, and record the feedback delta. Do not create a new episode, extract a framework or expand into full-platform regression unless the change affects those behaviors. Mandatory project reads still apply.

Create or update a [mode slice card](assets/slice-card.template.md): selected activity, authoritative time/energy/growth rules, availability, entry/return behavior, source constraints for any attached event, reused capabilities and player-visible acceptance points. Do not invent costs or relationship systems to fill a template.

Do not silently invent replacements for named characters, rewrite the ending or schedule a stored draft for implementation. Label connective dialogue and new details as adaptations. Ask only for missing details that materially affect the story or execution boundary; make reversible layout choices and continue independent work.

Keep authored event sources at their designated location and pin their origin. See the [cultivation event contract](references/content-contract.md), [activity catalog example](assets/mode.example.json) and [event example](assets/episode.example.json). A larger story may supply one selected cultivation event; its other gameplay is outside this skill.

For a multi-stage side quest, read [side-quest integration](references/side-quests.md); for tea also read its linked adaptation plan and selected original sections. Preserve reveal order and recurring object IDs. Track prerequisites, completed milestones and return context in host state; viewing again must not repeat settlement or reveal later-stage information. Supporting a quest in this skill does not schedule its full implementation.

## Read and reuse selectively

- After mandatory project reads, inspect the selected source, affected characters/scenes/actions, their interface definitions and relevant tests. Use indexes to choose dependencies; invalidate cached summaries when source hashes or contract versions change.
- Record the affected file list and contract versions in the slice card. If a story is too large, split at a meaningful narrative boundary and keep ending constraints in every applicable card.
- Prefer a scene/profile or content change when existing capabilities suffice. Extend a shared module only for a concrete missing capability; use a second real use case before making a general abstraction.
- Keep one runtime authority in the repository. Do not duplicate addon code into the skill or editor plugin. If `painted-scene` is available and fits the scene, reuse it; otherwise retain the host adapter without making an uninstalled skill a dependency.

## Implement the cultivation loop

Use the project's installed runtime. The [runtime contract](references/runtime-contract.md) describes the proposed toolkit, not an assumption that these classes already exist. With today's shu, adapt current `main.gd`, `demo_state.gd` and weather interfaces only as required by the authorized slice.

Keep stable character, scene and action IDs. Resolve display names from the cast. Use whitelisted host actions; validate before committing state, return actual cost/gain and guard retried selections. Separate narrative progress and game time from presentation weather time. Keep UI independent of scene lighting.

The host rules/state own day/time, energy, growth and any existing relationship values. The mode controller owns activity availability display, interaction occupancy and return to the panel; do not create a second numeric state authority. Check eligibility against current state before settlement. A rejected event action changes no resources, retains occupancy and follows `failure_next`. End, cancellation or an unrecoverable event exit releases occupancy. Reading acknowledgement is tied to the active session/node/cue instance; cancelled or reset sessions cannot advance through an old callback.

A cast ID does not guarantee an available portrait. Check the asset index; use an appropriate text-only entrance or authorized new art when needed. Do not relabel another character's image as the new character. A new dialogue branch does not automatically add an unrelated activity.

If the toolkit is installed, use `say`, `choice`, `cue`, `end` nodes and its declared contract version. Validate references before activation. Never execute script text from narrative data. Preserve source art, provenance and notices when adapting assets.

## Verify, then present for playtest

Run checks proportionate to the change. Observe activity → actual time/energy/growth result → another activity, character/side-quest event → return, insufficient resources, cancellation/retry and reset. For a side quest, also check stage gates, interruption/resume, spoiler-free rereading and one-time milestone settlement. Check affected layout; record build, launch, automated checks, actual UI interaction and user approval separately.

For extraction, compare the existing playable loop before and after. For weather/presentation changes, check UI readability, scaling, pause/static mode and independence from game state. Record untested platforms accurately; producing a Web build does not verify Windows or Steam Deck.

Deliver a usable preview/build when authorized and available, with concise acceptance points. After feedback, update the current card and required decision/development records; add approved product changes to the spec. Keep unresolved proposals visible. Continue authorized revisions without asking for already-given permission.

## Keep the next round inexpensive

For package edits, run `scripts/validate_package.py --repo <project-root>` to check examples, local references and pinned tea source. This checks the skill package, not Godot runtime behavior. Read only the detailed references relevant to the selected activity or quest.

Update only the current state, relevant indexes/contracts and decision delta. Prefer short deterministic success reports; include file/node details on failures. Measure comparable slices by context size, repeated reads, runtime changes and revision count. Do not claim a token-saving percentage without comparable measurements.

Finish with the playable outcome, key change, observed verification and next decision. A design deliverable instead states which parts are drafts and which interfaces remain to be implemented.
