# Cultivation event contract — proposed version 1

This contract is a design, not today's shu loader schema. `assets/mode.example.json` demonstrates the activity catalog; `assets/episode.example.json` demonstrates a mentor event inside cultivation mode. The event graph is an internal interaction, not an independent game/story mode.

## Envelope and origin

- `schema_version`: integer, initially 1.
- `id`, `scene_id`: stable lowercase identifiers. Content `revision` is separate from schema version and runtime version.
- `mode`: exactly `cultivation`.
- `activity_id`: registered activity that opens this event; `participant_ids`: registered cast IDs.
- `trigger`: initially `{type: activity_selected, activity_id}`; the ID must match `activity_id`. Scheduled/random triggers require a concrete later use case.
- `allowed_action_ids`: exact host actions available inside the event; the initiating activity and its selected branch must not charge the same cost twice.
- `return_to`: exactly `activity_panel` in v1. The event cannot silently switch to exploration/combat or a separate story screen.
- `source`: status plus repository, path, pinned revision and used sections. Implemented content additionally stores the source SHA256 and adaptation notes in its source manifest.
- `entry`: node ID in `nodes`. All node IDs and option IDs are unique within their respective scopes.
- `nodes`: dictionary of nodes.
- Optional `quest_context`: `{quest_id, stage_id}` for a registered cultivation side quest. Optional `when`: array of `{flag, equals}` prerequisites using registered boolean flags; all must hold. Activity availability and event prerequisites are checked again on entry/settlement.

An illustrative sample uses `status: illustrative` and null origin values; it cannot be packaged as approved production content. Implemented episodes require a resolvable pinned source or explicitly recorded user-provided source. Do not invent commits or hashes.

## Nodes

| Type | Required fields | Optional fields |
| --- | --- | --- |
| `say` | `speaker`, `text`, `next` | registered `expression` |
| `choice` | nonempty `options` | `prompt` |
| `cue` | `cue_id`, `next` | parameters permitted by that cue's registry |
| `end` | `reason` | human-readable handoff note |

Each choice option has `id`, `text`, `next`. An option may have `when: {flag, equals}` with a registered flag and boolean value. An action option also has `action: {id, args}`, `failure_next`; arguments must match its registry. Success advances to `next`; failure displays the returned reason and advances to `failure_next`. Non-action options only change narrative position.

All identifiers resolve against the project's versioned registries. All edges resolve to node IDs. All nodes are reachable from entry and have a path to an end; unknown fields are errors unless added by a newer supported schema. No implicit code evaluation. No loops in v1 content; a later design may support guarded loops if a real story requires them.

An option's action must also belong to `allowed_action_ids`. Entry obtains the mode's interaction occupancy, without charging a deferred mentor-choice cost. A rejected action retains occupancy and follows `failure_next` with no resource change. End, cancellation or an unrecoverable event exit release occupancy and return to the activity panel. Already-committed results are retained; cancellation does not invent a refund.

If all options are hidden by conditions, show a recoverable error and allow returning; do not trap the player. A content-load error retains the previous valid episode. Validate the full graph and registry bindings before exposing it to the player.

## Staged cultivation side quests

The [side-quest reference](side-quests.md) defines the bounded extension for tea: separate event graphs for stages; manual activities, character interactions or fixed-scene hotspots route through registered activity selection. A hotspot is not a new unrestricted trigger language.

Fixed-profile transitions, object descriptions, document reading and short memories use registered `cue` handlers. Their declared parameters may include `profile_id`, `object_id`, `document_id`, `memory_id` and `await_ack`; validate each ID and type against the cue registry. With `await_ack`, enter `awaiting_cue_ack`; a matching session/node/cue-instance acknowledgement advances once. Cancel/reset invalidates pending instances. The cue registry declares whether panel close means acknowledgement or cancellation. Before confirmation, do not advance or submit a milestone. Presentation callbacks do not set quest flags.

Advance a milestone through a whitelisted host action only after its required interaction is completed. Gate later evidence by committed host flags; no automatic advancement at load or cancel. A stage/quest completion has a one-time key scoped to the save/run, quest and stage, in addition to ordinary operation receipts. Rereading is available under the current knowledge state and does not reapply completion/reward/cost actions.

Remember the initiating activity panel/profile as return context. A fixed scene or memory transition restores that context on end/cancel/error. The same prop keeps one stable object ID across early/late appearances; descriptions and available interactions depend on current flags. Save integration must include quest flags, event checkpoint and return context along with host state and receipts.

## Three forms of truth

1. Authored source governs story meaning and approved constraints.
2. Episode data governs node order, text and branches for this revision.
3. Host action registry and state govern gameplay costs, gains and flags.

The activity catalog binds display label, authoritative host action/rule ID, availability check, and optional event ID. Training/rest can settle directly; mentor/companion activities may open an event. Rule references supply time duration, energy cost/recovery and actual growth deltas; do not copy numeric values into this event schema. A completed or cancelled event must permit the next valid cultivation activity.

Do not encode gameplay costs twice in dialogue and actions. Where text shows actual effects, interpolate only declared result fields returned by the host; unrestricted string templates or expressions are outside v1.

## Packaging and versioning

Build from local pinned content. Do not fetch story repositories during play. For shu, mainline and side-story authoring locations follow `shu-binding.md`; playable data can reference those originals without relocating them.

Version content schema, runtime API, game content revision and save schema separately. Reject unsupported versions with a clear diagnostic; save migrations need explicit implementation and verification. Preserve stable IDs across dialogue wording changes.
