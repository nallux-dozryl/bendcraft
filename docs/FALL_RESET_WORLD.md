# Checked neutral fall-reset ray supplier (26.3)

`fall_reset_world.bend` supplies a checked `H.Miss` observation for an explicit
ray through the currently supported air/stone/dirt/oak-planks world. It owns no
player movement or history. The caller retains the single `W.State`/Engine/Core;
every return preserves the complete prior View, including body, velocity, flags,
camera, palette, region and immutable snapshot cache. Core reads retain cells,
section trie, clocks, revision, queued mutations and events.

Current preparation status: production and standalone harness ordinary type and
termination checks pass. The frozen fresh Java corpus contains 127 rays:
107 admitted complete MISS returns, six Hits, seven watchdog interruptions and
seven other completed exclusions. The admitted rays retain 492 visits and 984
ordered block reads; the full corpus retains 1,310 visits and 2,620 reads.
All seven required rays copied from earlier actual movement observations are
admitted. Fresh independent execution matched every observation and the entire
4,368-class official loaded tree. Eleven integrity mutations were rejected.
Native and independent kernel validation have not been attempted. Confidence is
high for these actual Java observations; Bend/native behavioral comparison is
not yet established.

## Affine API and admission

```text
clip_checked(W.State, Request)
 -> W.State & Result<&2, &2, Error, Observation>

Request Data {
 from: M.Vec3, to: M.Vec3,
 interior: exact binary64 AABB,
 work: Nat,
 profile: DefaultClientOverworldFourState | UnresolvedTags,
 tail: List<&2, Request>
}
Observation Data {
 clip: H.Miss,
 from: M.Vec3, to: M.Vec3,
 expanded_from: M.Vec3, expanded_to: M.Vec3,
 reads: List<&2, Read { position: C.Position,
                      phase: BlockSample | FluidSource, state: U32 }>,
 tail: []
}
```

There is no independently authoritative Body/history in Request. The profile is
an explicit conditional assertion of pinned default tag semantics, client Player
selector context and overworld dimension. Runtime data-pack tag resolution and
other dimensions are outside this projection. `UnresolvedTags` rejects.
This block/fluid ray does not query entity collisions or world-border collisions.
The declared interior bounds the complete visited cells and the supplied world
service domain; it is not inferred from body position or the supported block map.

All input endpoint and interior coordinates must be finite. Interior must be
ordered. Both expanded endpoints must remain within the explicit conservative
coordinate range `[-2147483000,2147483000]`. Each actual cursor coordinate is also
checked against this margin before its first Core read, preventing wrapped
coordinates from reaching a read even in an unordered-timing pathological loop.
Every visited full cell must fit inside the supplied interior before its first Core read.
Missing sections, unsupported states, invalid admission, and exhausted work
return errors. No absent state becomes air.

Each cell reserves two work units before executing its two checked Core reads:
the direct block sample and the block lookup from which this fixture's actual
fluid lookup is derived. Both returned states must belong to the dynamically
resolved four-state palette. The cached View palette must exactly match current
registry lookups; absent/stale palettes reject. All four default states have empty
fluids and empty selected fall-reset shapes, established by the actual selectors
and tag reload. Unsupported water, resetting blocks and portal states reject on
the actual traversal read instead of producing an assumed MISS or approximated
hit. Work does not create a partial success; a successful MISS requires every
required read. Request tail must be empty; noncanonical requests return the same
original world owner.

Exact equal endpoints take the actual no-read MISS branch, including identical
negative-zero endpoints. They still require finite/domain/interior/profile and
current palette admission. A zero work budget is sufficient for this branch.
This is a policy guard around the actual method, not a claim that Java validates
the same admission conditions.

## Production traversal details

The untouched `BlockGetter.traverseBlocks` first uses `Vec3.equals`, which applies
`Double.compare` per component. Positive and negative zero are distinct. For
unequal endpoints, its exact endpoint expansion is:

```text
expanded_to   = Mth.lerp(-1e-7, to, from)     // x, then y, then z
expanded_from = Mth.lerp(-1e-7, from, to)     // x, then y, then z
lerp(t,a,b)   = a + t * (b - a)              // each Java double operation rounds
```

It floors expanded_from and visits that cell before any step. Per-axis delta is
`sign(direction)/direction`, or `Double.MAX_VALUE` for a zero direction. The next
crossing time uses `delta * (1-frac(start))` for a positive direction and
`delta * frac(start)` otherwise. Pinned `Mth.frac` uses `Math.floor` narrowed to a
Java long and widened back to double. Within this module's safe coordinate range,
the exact i32 floor conversion has the same value, without saturation.

The loop advances exactly one axis when any crossing time is `<= 1`. Strict
comparisons break finite ties in **Z, then Y, then X** order. Stationary axes at
integer coordinates initially have crossing time zero. They can perform sign-zero
steps and revisit the same cell. They must not be discarded or deduplicated.
Direct actual method checks found `(0,0,0) -> (0,1.5,0)` visits `(0,-1,0)` three
times before `(0,0,0),(0,1,0)`. Opposite signed-zero vectors visit `(0,0,0)` four
times; identical vectors visit no cells. Exact diagonal ties preserve the
intermediate corner cells. Finite subnormal directions can overflow the reciprocal
and create NaN internal timing through `infinity*zero`; the exact unordered
comparison behavior remains part of traversal rather than being silently rejected
because a private timing field is nonfinite. Some negative-subnormal rays do not
finish: an unordered Y crossing can force repeated sign-zero Z steps while another
axis remains active. Actual watchdog interruptions retain partial traces as
interruptions, never complete clip returns. The checked supplier then refuses
through explicit work/cursor/interior/Core admission and retains the owner; it
cannot issue MISS for an interrupted traversal.

The pathology also occurs in rays whose actual length and squared length both
equal one. For `(0,0,0) -> (1,-5e-324,0)` and the corresponding `-1e-320` Y case,
actual normalization and scaling retain the tiny negative Y value and produce
the supplied endpoint. The expanded start X is `-1e-7`. Both untouched clip
calls record 128 visits to `(-1,0,0)` and 256 returned reads, then the external
watchdog interrupts attempt 257. Neither observation supplies MISS. Planned
checked work-error cases include these two rays, two pure negative-Y rays, and
one deliberately bounded ordinary-progress ray; all five recover using the same
world owner after refusal. Total movement length alone cannot rule out this
pathology.

At each actual callback, `BlockGetter.clip` reads block state, then fluid state,
then obtains/clips the selected block shape, then the selected fluid shape. An
exact distance tie chooses the block hit. The frozen real finite fixture's
`getFluidState` calls `getBlockState(...).getFluidState()`, producing a second
ordered block lookup. The adapter therefore preserves two reads per visit,
including all repeated visits. Admitted selectors are both empty, so there are
no selected-shape neighbor reads or hits. Unknown/contextual selectors reject;
the module implements no general shape hit algorithm.

## Required movement-ray phase

The actual `Entity.move` ray is inside its position application branch, with
`fallDistance != 0` and `resolved.lengthSqr() >= 1`. It executes **before**
position application and the later support/minor/fall check. Its endpoints use
the old position and these exact original operations:

```text
limit = Math.min(resolved.length(), 8.0)
to = oldPosition.add(resolved.normalize().scale(limit))
from = oldPosition
```

Normalizing then scaling preserves two separately rounded sets of operations.
It is not interchangeable with dividing once by length or scaling by
`min(length,8)/length`. No post-position subtraction, delta-movement velocity,
support cache or camera substitutes for the resolved vector or old position.
The supplier accepts explicit endpoints only; it does not derive the required
predicate or stage movement/history callbacks. A future owned consumer must bind
these observations at this exact phase and supply `H.NotRequired` only when no
actual ray is required. Existing TH/MH/LM consumers remain unchanged.

## Default tags and actual receiver boundary

Official `fall_damage_resetting` contains `#climbable`, sweet berry bush and cobweb.
The default closure has eleven block members and excludes all four supported
states. The official water tag contains water and flowing water. Bootstrap tag
holders begin empty; that state is not used to establish default tag truth.
The new normal receiver parses the original tag entries through `TagEntry.CODEC`,
builds them with actual `TagLoader.build`, then invokes the real
`Registry.prepareTagReload(LoadResult).apply`. Raw official tag resource hashes,
built member lists and before/after actual holder membership are recorded.
This selected tag reload does not claim that every unrelated pack/tag is loaded.

The actual `FALLDAMAGE_RESETTING` selector also returns a full block for a Player
in END_GATEWAY or END_PORTAL, despite those states not belonging to the reset tag.
The server NETHER_PORTAL branch has its own game-rule context. These states are
explicit refusals here. Real water/cobweb hit examples and client portal selector
observations remain outside the four-state supplier admission.

The fresh oracle imports unchanged frozen LI service templates and constructs a
real normal LocalPlayer and ClientLevel. It substitutes exactly the four already
declared external LI services; no target method is replaced. The finite actual
world has a 25-stone floor, otherwise air, with explicit sequential writes.
Level clip/read observers and ClipContext selector observers call super. Plain
and observed results/body fields must agree. Direct actual helper endpoint
metadata is labeled separately from private DDA locals; decisive read/visit
expectations come from untouched actual clip calls. A declared external read
watchdog bounds unsupported giant requests, preserving its actual abort separately.

Six production laws ordinary-check complete admission rollback, outside-interior
no-read behavior, insufficient work retention, equal endpoint no-read behavior,
unsafe-cursor no-read behavior and noncanonical request owner retention. Two
standalone harness laws check signed-zero endpoint distinction and exact Z-first
tie stepping. The final ordinary preparation passed in 2.944158 seconds for
production and 3.920160 seconds for the standalone harness. These ordinary
checks are not independent proof verdicts.

The narrowed harness owns eight real Core sections covering `[-16,16)^3`, with
the measured floor and checked world edits. It compares the complete prior and
returned body, View/cache, cells/trie, clocks, queue and events. The planned native
comparison has two identical suites, each containing 107 actual admitted rays,
29 policy/recovery cases and 14 dynamically remapped cases. The 29 policies
include missing sections, absent/stale palettes, nine actual Registry-resolved
unsupported states, budgets, invalid domains, noncanonical request tails and
five observed external-interruption cases. Refusal publishes no partial MISS or
read-list success. Recovery reuses the same returned owner. Native assertions
have not yet run.

The frozen preparation has 58 Bend/Base/effect dependencies and twelve tool
pins. Production SHA-256 is
`8353ad65484f28b80ae49a3b4191bf98aad5903f6565f6d17f2d64eeec2c7948`;
harness is
`ec3c4a68507ab5975a0e52621959fd849d7a90a4099eb0178f553aecf7941cf4`;
original preparation runner is
`d17217892033b4ad52a6b8150f69d74de135392ebd606df0744db606d25a8dbb`.
The Java producer is
`c789f38f7b5f038f57c81e3fdcf4747c9a5396225ebaae02279c246d0a70a41b`;
its Java SOURCE is
`21d413db72262ea0186ca3aa7fc59014fc42bfe3f016cc4b026f38c4914049c0`.
The reference SHA-256 is
`5286ed1f9a8cfbb190d98f4ec8f67ef1e066910e7a5788aa3aef5570144a8014`.
Fresh actual observations and their independent repetition share digest
`82a5ed44b614d732b5b9c29aed67dcd8b15c289a578b5e5c6b08fb0b70f7cf1f`.
Actual Java elapsed time was 51.815 seconds, then 56.443 seconds for repetition;
both calls were capped at 120 seconds. These are oracle workload timings, not
gameplay performance measurements.

## Sealed host reporting adoption

The independent non-owner pregrant review passed the frozen gameplay/reference
preparation without running Java, Bend, native or kernel work. It verified the
fifteen original owned pins, twelve tools, 58 source/effect pins, both retained
fresh Java projections/class maps and current provenance. Native behavior and
independent proof remain unverified.

A separately authorized host-only adoption preserves the exact original runner,
document, preparation/preflight, fixtures/evidence, ordinary streams and reviewer
files: 23 originals under ignored `build/fall-reset-world-host-adoption/original/`,
linked by `original-manifest.json`. Historical preparation receipts retain their
old runner/document hashes and status. Gameplay source, harness, producer,
reference, native argument generation and expected comparisons are unchanged.
All 21 original non-host function ASTs match; only bound/native/main orchestration
changed and new host lifecycle helpers were added. Current runner SHA-256 is
`d304fd0e425d6790f316a99ce88635623584bea637e75d0b143c71318ecf72fc`.

Execution admission now reads sealed file hashes and resolved lookup paths. It
does not call the reference producer, regenerate preparation, rerun mutations,
invoke Java/javap or probe Java/compiler versions. The future installed build
helper still owns its explicitly recorded build identity recipe. Each actual
process has an exclusive planned/start/final receipt with full argv, raw pinned
stdout/stderr, status, timeout trigger and measured cleanup before parsing or
comparison assertions. Raw bytes survive decoding failures. Comparison/drift
failures retain an exclusive first-failure receipt and exit nonzero. Native
success is persisted before proof; failed/inconclusive proof exits nonzero while
preserving that native receipt.

One attempt directory is reserved exclusively. Prior attempt/receipt/stream
overwrites refuse; a future authorized replay needs a distinct explicit attempt
ID and retained artifact admission. `--prepare` refuses once this preparation is
sealed. No implicit rebuild, re-emission, replay or proof retry occurs.

The unchanged 600/120/60-second values are **timeout triggers**, followed by a
five-second process cleanup grace. The driver checks its managed PGID and
PID/PPID-observed descendants, including additional observed groups, even after
leader exit; sends TERM/KILL when needed; reaps the leader; and records remaining
members. Process-table inspections themselves have bounded two-second timeouts.
These are not exact elapsed-time ceilings. Unexpected lingering descendants are
inconclusive even when successfully removed. Cleanup is marked verified only
after observed members disappear; unobserved processes escaping/reparenting
between snapshots are not covered by a universal descendant claim.

Python-only host checks cover ordinary success, exit seven, TERM-resistant
timeout, leader exit with a lingering child, spawn failure, overwrite refusal,
CLI failure exit status, sealed preparation refusal, failed admission before
spawn, and byte-exact CRLF/NUL/invalid-UTF8 receipts. They invoke no native/Bend/
Java/kernel target. The synthetic admission stub is explicitly labeled. Complete
host receipts and executed intermediate runner bytes remain ignored and pinned
by the adoption certificate. No native build or independent proof has run after
this reporting repair. Further FR execution is deferred unless it unblocks
required resolved-motion cases in the authoritative LocalPlayer consumer.

## Reproduction

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_fall_reset_world_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_fall_reset_world_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_fall_reset_world_probe.py --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_fall_reset_world_probe.py --storage
# Historical preparation; sealed --prepare now refuses overwrite.
# PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world.py --prepare
# Deferred build/native/proof work requires a separately granted root slot.
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world.py --skip-ordinary
```

Tracked evidence consists of compact summaries linking full exact original bytes
under ignored `build/fall-reset-world-reference/` and
`build/fall-reset-world-verification/`. The planned native runner pins source,
harness, reference, tools, full import closure and native dependencies; it compares
actual ordered raw observations, complete owner retention and dynamic remaps.
It persists native success before the single independent full-harness verdict.
No host DDA implementation computes expected visits, selected shapes or MISS.
