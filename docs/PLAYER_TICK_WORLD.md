# Owned finite-world Player.aiStep projection

`src/player_tick_world.bend` composes the frozen checked player preparation,
travel, owned block collision query, movement and finishing operators. It reads
one existing `client_world.State`; it does not advance the game clock or create
terrain.

```text
tick_checked(world: W.State, tables: L.Tables,
             player: P.State, context: P.Context)
  -> W.State & L.Tables & P.State & Result<PW.Error, P.Transition>
```

The explicit player state and the view body must initially agree bit for bit:
position, box, velocity, dimensions and all four collision flags. The admission
check distinguishes positive and negative zero. A host can store only player
metadata and construct the explicit `P.State` using the authoritative view body
at each call. The returned player body and installed view body agree. `P.State`
is ordinary Data; the World Engine and sine Tables each retain one owner.

The operation runs `P.prepare_checked`, temporarily installs its prepared body,
runs `TW.travel_checked` with its widened input, and calls `P.finish_checked`
exactly once. Travel performs acceleration, exact owned-world block collision
queries, checked movement, then gravity and drag. Player finishing updates the
stored movement speed and head yaw as defined in the supported aiStep projection.
The world view's camera angles remain independent of the caller's travel yaw.

`PW.Error` reports `BodyMismatch`, `PreparationError`, `TravelError` or
`FinishError`. Every rejection returns the original explicit player state and
original view, including body, camera, palette, region and render cache, along
with both affine owners. Reads leave clock, daylight, pause, revision, queued
mutations and events unchanged. A caller must repair a body mismatch explicitly
before retrying; rejection does not decide which conflicting body is authoritative.

The caller supplies the complete checked `P.Context`, including actual current
resolved attributes, supporting-aware block friction and jump factor, and the
neutral-context admission facts. This module does not infer a last support block,
resolve support history or sample those values. Supporting block selection and
mid-move side effects are separate dependencies. See [PLAYER_TICK.md](PLAYER_TICK.md),
[TRAVEL_WORLD.md](TRAVEL_WORLD.md) and [CLIENT_WORLD.md](CLIENT_WORLD.md) for their
precise supported contracts.

The world bridge admits dynamically resolved air, stone, dirt and oak planks
only. Missing checked sections, unsupported block states and excessive query
bounds are explicit errors. This is a finite verification instrument for neutral
movement. Full player/server ticks, fluid movement, flight, climbing, equipment,
nonneutral block effects, nearby actors and world-border collision remain outside
its contract. Low-level trusted Core writes can bypass revision; callers must
retain `W.invalidate_cache` after direct engine/registry changes.

## Verification

Run `python3 tools/test_player_tick_world.py`. The native harness retains the same
World and Tables within each sequence, carries its own returned body and player
metadata forward, and applies only explicitly supplied input/jump controls.
Expected results come from fresh actual pinned Java `Player.aiStep` observations
in the same 39-block stone/dirt/plank fixture. Actual `Entity.move` calls supplement
the oracle for displacement, stepping and the position-application gate.

The tests compare prepared player state, widened input, accelerated request,
ordered initial/step collider lists, final complete projected player state and the
installed world body. They also compare the world clock and original view/cache
before and after calls. Rejections exercise mode admission, mismatched body
including signed zero, jump validation, missing sections, unsupported states,
phase-level finish rollback, and continued use of both owners after repair.
Fixture creation and queued block repairs occur explicitly outside the operator.
Registry remapping verifies that numeric block IDs are not assumed.

The final bounded corpus contains 52 actual aiStep calls in five sequences,
47 calls carrying the preceding native state, 104 ordered collision lists,
four jump attempts, one step and seven application-gate rejections. Fourteen
rejection/recovery cases pass; paused and running clocks and registry remapping
are checked.

The rollback header is boxed internally to keep native continuation arity below
Bend's 247-word limit. It contains only immutable view/player Data, with an empty
recursive tail; it contains neither affine owner.

Four source laws state the owner/player/view rollback contracts. Ordinary
checking validates the module and laws. The whole-module proven-kernel verdict
inherits the Game/JSON translation mismatch documented for `client_world`; it is
recorded explicitly, and this module makes no whole-kernel certification claim.
Native checks and their exact source/dependency/binary hashes are recorded in
`evidence/player-tick-world-verification.json`.
