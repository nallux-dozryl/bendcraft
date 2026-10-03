# Owned client world bridge

`src/client_world.bend` is the finite scene integration bridge between the
owned simulation, binary64 collision/movement code, and immutable render
snapshots. `State` retains one `Game.Engine`; neither rendering nor the
window receives an owned copy of its world. The shared server actor uses the
same `step` and `dispatch` functions as its remote live requests.

This is a verification instrument, not terrain generation or complete player
travel. `new(engine)` initializes a declared body and camera but creates no
sections or blocks. Missing sections remain errors. Only the explicit
`fixture(engine)` populates a fresh empty world.

## Interface

- `new(engine)` and `fixture(engine)` return
  `State & Result<&2,&2,String,Unit>`, retaining ownership on failure.
- `step(state)` calls `Game.realtime_step` once; a paused engine stays paused.
- `dispatch(state,session,token,request)` calls `Game.dispatch` and retains the
  current body, camera angles, palette, and snapshot region.
- `snapshot(state,width,height)` returns
  `State & Result<&2,&2,String,ClientRender.Snapshot>`. Resolution does not
  influence the world sample. Width and height remain in the stable client
  call interface.
- `move(state,delta,max_step)` returns
  `State & Result<&2,&2,String,Movement.Transition>`. It updates the body only
  after a successful checked transition.
- `look(state,yaw,pitch)` accepts finite binary32 radians, with pitch between
  binary32 ±π/2. Failure preserves the old angles.
- `set_region(state,bounds)` sets an explicit integer region. Each positive
  side is at most 16 cells, for at most 4,096 checked reads. Signed integer
  coordinates use the existing two's-complement U32 encoding. Padding or
  region ends outside signed I32 are rejected.
- `body(state)` returns `State & Movement.Body`, retaining the sole owned
  engine and returning immutable body data.
- `invalidate_cache(state)` discards the internal immutable block cache.

`State` contains `engine`, `body`, `yaw`, `pitch`, `palette`, `region`, and
an optional immutable `cache`.
The palette is resolved by the names `minecraft:air`, `minecraft:stone`,
`minecraft:dirt`, and `minecraft:oak_planks` from the loaded registry. Each
must have exactly one state and no properties. Air is omitted. The remaining
materials are 0 = stone, 1 = dirt, and 2 = oak planks, matching the renderer's
official texture list. Unknown states are errors, including glass, fluids,
and context-dependent shapes. Registry state IDs are not hardcoded.

Successful samples cache their immutable block list by exact world revision,
all six region fields, and all four palette state IDs. Every snapshot still
reads the current tick and computes the camera from the current body and
angles. Failed samples are never inserted. Ordinary checked `Game.dispatch`
mutations advance the core revision when applied, so those edits naturally
invalidate a cached list. Trusted compiled code can also call low-level
`Core.write_block` or `Core.apply`, which can change blocks without changing
revision. Such direct engine writes must call `invalidate_cache` before
requesting a snapshot. Direct registry/palette changes require a correct
palette and explicit invalidation; revision is not a universal change
detector for arbitrary Bend mods.

## Exact bounded block queries

For the supported static shapes, the bridge follows the pinned 26.3
`BlockCollisions` iterator: bounds start at `floor(min − 1e−7) − 1` and end
at `floor(max + 1e−7) + 1`; the cursor advances X first, then Y, then Z.
Corners are skipped before reads. The four supported states lack large
collision shapes and are not moving pistons, so face and edge entries yield
no colliders after their state lookup. Interior full cubes are returned only
when they strictly intersect the query AABB. Air contributes no list entry.

The initial block query uses `Movement.initial_block_query`. The second
query is issued only when the vanilla stepping branch is eligible and uses
`Movement.step_query` with the exact initial clipped displacement. Stationary
requests whose binary64 length squared is zero bypass block enumeration.
Movement scalars and candidate calculations stay in pure Bend binary64;
snapshot coordinates and the eye camera narrow through verified
`F64.to_f32` only at the render boundary.

Queries reject nonfinite or reversed boxes, I32 padding overflow, and any
side exceeding 16 cells. Missing or unsupported cells fail explicitly; there
is no unloaded-air approximation. The finite instrument has no other
entities or world border. Consequently these lists cover supported block
collisions only, not all vanilla collision sources.

## Fixture and verification

The fixture requires tick 0, revision 0, no pending actions, no events, and
an empty section map. It admits 47 developer actions for tick 1 and executes
that actual tick: eight air sections, 36 floor blocks at X/Z −3 through 2,
one dirt block, and two raised planks blocks. Its render region is X/Z −4
through 3 and Y −1 through 4. The result is tick 1, revision 47, and 39
rendered blocks. Its body feet are `(0.5,1,−2.5)`, with dimensions
`(0.6f,1.8f)`, a declared `1.62f` eye offset, yaw 0, and pitch 0.2 radians.
These are explicit instrument parameters; no full pose or locomotion claim
is attached to them.

`tools/test_client_world.py` executes the original Java 26.3
`BlockCollisions` against a finite block getter containing exactly that
fixture and compares 124 ordered collider lists and 124 query bounds. Its 87
movement cases compare composed private-method observations and untouched
`Entity.move` observations from a real `Level` containing the same 39 blocks.
The initial and step collider lists must also agree exactly. The entity is a
generic locally authoritative fixture using the player type's dimensions,
suppressed bounce, an overridden maximum step height, no other entities, and
disabled movement emission. That is observed bounded runtime equivalence;
general player/entity movement parity remains unknown.

Fourteen integration groups check repeated owner-preserving snapshots, live
dispatch edits followed by simulation steps, unsupported-state repair,
invalid-input preservation, terrain-free construction, camera positions
after movement, paused/unpaused realtime pulses, rejection of a repeated
fixture initialization, and a different valid registry order. Cached samples
must equal independently recomputed samples after admitted edits, error
repair, region selection, palette replacement, look, movement, and tick
changes. A direct unrevisioned write followed by explicit invalidation must
also agree. Two conditional implementation laws check exact block recovery
on a matching key and rejection on a nonmatching key; the ordinary checker
accepts them, while whole-module kernel validity remains unverified.

A separate 10,000-snapshot loop consumes all block lists to measure this
specific cached sampling cost, with startup/registry/fixture cost subtracted
using three process samples. The original 100-snapshot uncached measurement
is retained in `evidence/client-world-snapshot-baseline.json`; its median
estimate was 2.28 ms per 384-cell sample. Timing occurs on a concurrently
loaded host and is not a Minecraft performance comparison.

The module passes Bend's ordinary affine/type checker. Whole-module kernel
verification inherits the known JSON encoder checker/kernel mismatch from
`Game`, and no kernel validity claim is made for this bridge. Native evidence
is recorded in `evidence/client-world-verification.json`.
