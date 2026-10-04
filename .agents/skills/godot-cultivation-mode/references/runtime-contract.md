# Cultivation-mode runtime contract — design only

The following GDScript signatures describe the planned API. They are not drop-in classes or an implemented addon. Runtime code belongs in the host repository; this skill points to its versioned interface.

## CultivationModeController and state ownership

```gdscript
signal activity_options_changed(options: Array[Dictionary])
signal activity_result(result: Dictionary)
signal mode_view_changed(view: Dictionary)

func configure(profile: Dictionary, activities: Dictionary, host_state_port: RefCounted) -> Dictionary
func select_activity(activity_id: String) -> Dictionary
func cancel_interaction() -> void
func reset_run() -> void
func snapshot() -> Dictionary
```

This controller owns the fixed-scene activity panel and phases `ready`, `interaction`, `settling`, `showing_result`. It allocates operation IDs, checks current host eligibility, invokes registered actions or an attached event, displays actual deltas and returns to `ready`. The host state port remains the sole authority for day/time, energy, growth and existing relationship state; profile data never duplicates numeric rules.

The activity catalog references host rules for duration, cost/recovery and growth. Invalid/ineligible selections show the reason without changing state. While an interaction is open, only its allowed actions can run. Rejected event actions retain occupancy and follow their failure branch. Finish/cancel/unrecoverable event exit releases occupancy and refreshes the panel. Reset invalidates old callbacks and starts a new run. Staged side quests use host prerequisite flags and fixed-scene hotspots routed through activity selection; calendar/random scheduling and new relationship mechanics still require a concrete selected feature.

## InteractionRunner — an event within cultivation mode

```gdscript
signal view_changed(view: Dictionary)
signal action_requested(request: Dictionary)
signal presentation_requested(cue: Dictionary)
signal episode_finished(reason: String)

func load_episode(data: Dictionary, registries: Dictionary) -> Dictionary
func start(session_id: String) -> Dictionary
func continue_line() -> Dictionary
func choose(option_id: String) -> Dictionary
func resolve_action(operation_id: String, result: Dictionary) -> Dictionary
func acknowledge_cue(session_id: String, node_id: String, cue_instance_id: String) -> Dictionary
func cancel() -> void
func snapshot() -> Dictionary
```

`load_episode` returns `{ok, errors}`; validates the cultivation event contract before replacing active content. `view_changed` carries resolved speaker/text/options and interaction phase. The runner emits requests, not direct UI mutations or numeric state changes. It freezes choice input while a request is pending and advances once for an accepted response. An unexpected or obsolete operation result cannot advance a different event. Its completion/cancellation is consumed by CultivationModeController to return to the same activity panel.

Phases: `idle`, `line`, `choice`, `pending_action`, `awaiting_cue_ack`, `finished`. An awaited cue advances only after acknowledgement matching its current session/node/instance, at most once. Cancel/reset invalidates that instance; old or duplicate acknowledgements have no effect. No next-node or milestone action runs before confirmation. Rejected actions enter their failure node while retaining occupancy. A host locks unrelated actions for the whole interaction and explicitly permits the registered mentor-choice actions during the dialogue. This avoids retaining independent `dialogue_open`, `busy` and `awaiting_continue` truths in different controllers.

`operation_id` identifies the selection occurrence, not just the option name. Include save/run identity, session ID and selection sequence. Reset creates a new run/session; retry retains the old ID. Restore uses saved identity and sequence.

## ActionGateway

```gdscript
func execute(request: Dictionary) -> Dictionary
```

Request: `{operation_id, activity_id, action_id, args}`. Only actions within an event add `episode_id` and `node_id`; side-quest actions may also carry registered `quest_id` and `stage_id`. Direct training/rest require no invented dialogue context. Success: `{ok: true, operation_id, delta, state_revision, message}`. Failure: `{ok: false, operation_id, code, reason}`. `delta` reflects actual changes, including time, energy and cultivation, for result display.

The host owns the action registry, valid argument schemas, preconditions, current game state and receipts. Validate the entire request against current state, stage all changes, then commit changes and receipt atomically. Identical retries return the receipt; the same operation ID with different action/arguments is rejected. A rejected request cannot partially consume time or energy. One local mutex/input phase is sufficient for the initial synchronous single-player host; no network/event-bus framework is implied.

For shu, registered mentor selection calls must accommodate existing `begin_dialogue`/`choose` rules. Do not route the selection through a generic “dialogue blocks all actions” check. Capture before/after state to form actual deltas, and preserve its one-use training bonus behavior.

Persist game state, interaction progress and receipts together when save support is introduced. Until then, guarantee duplicate handling within the active run and accurately describe the limitation.

For a quest milestone, recheck prerequisites and completion flags at commit. Enforce a save/run + quest + stage completion key independently of the operation ID, so a fresh session cannot award/advance the same milestone again. Partial clue flags are only committed by their explicit registered actions. Cancellation retains committed clues but does not finish an uncompleted stage.

## SceneProfile and presentation adapter

Profile owns logical canvas size, texture/actor slots, hotspot bounds, rain regions, anchored wind layers, foreground masks, lighting targets and quality presets. Asset IDs resolve through the game's asset index. Coordinates refer to the named logical canvas, never a guessed browser size.

Adapter interface:

```gdscript
func configure(profile: Dictionary) -> Dictionary
func present(view: Dictionary) -> void
func apply_cue(cue: Dictionary) -> Dictionary
func set_motion(enabled: bool) -> void
func set_quality(preset: String) -> Dictionary
```

The adapter maps coordinates/input to the host's scene model, updates UI, displays action results and routes cues. Presentation is unable to directly change gameplay state. Invalid cue parameters leave the last valid presentation intact. Fixed-scene visits, document panels and short memories retain the initiating profile/panel as return context. Continue/close acknowledges or cancels according to the cue registry. End/cancel/unrecoverable event exit clears temporary presentation, restores that context and releases occupancy; an in-event action rejection keeps the current interaction locked. Restore/save captures this context; replay must not leave the player in a memory scene.

### Existing code reuse

| Source | Available boundary | Extraction requirement |
| --- | --- | --- |
| shu `scripts/demo_state.gd` | `train`, `rest`, `begin_dialogue`, `choose`, `reset` | Wrap actual host rules; unify interaction ownership and add transactional receipts |
| shu `scripts/weather.gd` | `setup`, `add_lit_art`, dynamic toggle and audit seek | Externalize scene rects/paths; fixed vs moving lighting assumptions must be explicit |
| shu `scripts/weather_cycle.gd` | time-based weather sample | Keep presentation clock separate from game clock |
| `painted-scene` `surface.gd` | `configure`, `set_presentation`, `set_actors`, coordinate mapping, hit targets, depth/tint | Use for matching Node2D scenes; retain separate shu Control adapter |

`painted-scene` host callbacks own actor drawing and the host owns movement/interaction/state. Its current projection is separable monotone axis mapping, not a general 3D camera. Its template is not a complete licensed art library. Check its installed manifest and integration reference before importing it.

## First extraction checks

Existing D01 cultivation loop before/after; training spends the host-defined time/energy and grants actual growth; rest restores capped energy and advances time; mentor event completes/cancels then allows another activity. Check invalid graph/action rejection, insufficient energy without partial changes, selection/reply applying once, reset creating a fresh run, actual result text matching deltas, scaled hotspot alignment and static weather leaving gameplay unchanged. For side quests, check locked later evidence, repeated stage entry without duplicate settlement, object rereading under current flags, interrupted reading/memory returning to cultivation, and persisted checkpoints only when save support exists.
