# Complete tick recovery inside cooking format 5

`local_player_cooking_tick_storage.Stored` is the single Data image carried by
`local_player_cooking_storage.TickRecovery`. It contains:

- `recovery:local_player_effect_tick_recovery.Recovery`: one complete entity
  `View`, explicit runtime availability and the separate actual sound source.
- `clock_inputs:List<Random.Bits64>`: the remaining ordered constructor clock
  inputs, including duplicates and every raw high/low word.
- `membership:Maybe<EntitySectionMembershipModel.View>`: the complete five-list
  manager image, or explicit unavailability.

There is no second entity `View` or affine entity owner. `inspect` obtains the
image from the actual `Tick.State` and returns that same owner. `restore`
requires available runtimes and returns `Restored{tick,clock_inputs,membership}`.
The manager remains Data. Restoring an actual manager requires the loader's
current loaded/visibility authority; persisted flags cannot grant that authority.

`None` runtimes cannot become `Some[]`. `None` sound cannot borrow the LEVEL
random source. `None` membership differs from a known empty five-list manager.
`legacy(view,clocks)` explicitly records missing runtime, sound and manager data.
No constructor, fresh runtime, RNG allocation, seed normalization or clock debit
runs during encoding or decoding. The runtime codec requires the actual
canonical empty recursive tail; nonempty tails refuse encoding and decoding.

## Physical component

The `entities` ByteArray in the outer format 5 wrapper contains this ordered NBT
root, named `bendex:local-player-cooking-tick-storage`:

| Member | Physical type | Meaning |
| --- | --- | --- |
| `format` | Int, exactly 1 | Component version |
| `recovery` | ByteArray | Complete strict tick-recovery codec payload |
| `membership` | List of ByteArray | Zero entries for unavailable; exactly one complete manager payload for available |

Missing, duplicate, reordered, unexpected, wrongly typed or truncated component
members refuse. A present empty ByteArray is invalid, rather than unavailable.
Both nested codecs validate their full payload. The containing NBT encoding
also applies its aggregate byte/depth/container-element budget, so individually
fitting nested snapshots cannot bypass the enclosing limit. The outer wrapper
then applies its complete 16 MiB byte limit, depth 512 and 1,048,576 elements per
container, including the real `clock_inputs` LongArray and every other field.

The `Saved` and `Projection` constructors retain five fields. Format 5 retains
the format 4 seven-member topology: `format`, `player`, `bodies`, `effects`,
`entities`, `clock_inputs`, `publication`. Its `entities` member holds this
component instead of the older entity-only payload. Empty publication bytes
mean unavailable publication only when no `OwnedDirty` effect is pending.
An owned notification without publication recovery refuses. Formats 1–4 retain
their existing encoder branches and physical byte contracts.

## Verification

`python3 tools/test_local_player_cooking_tick_storage.py --native` passed 15
guards and 47 independent physical NBT cases in attempt 004: six accepted
complete-byte round trips and 41 strict refusals. This includes the full raw
tick recovery, all remaining clock words, explicit legacy unavailability,
known-empty manager and the complete manager fixture with five members, three
sections, four chunks, four tracked registrations and two ticked registrations.
Every accepted output equals its input bytes. The 9,784-byte golden component
has SHA-256 `753229bbd5184fa90b94cc52926da983c8faf8c9002a2e1c51c3053e36d961db`.
Attempt 004 reused the unchanged attempt 003 native binary; the new complete
manager case did not require another C emission. Attempt 001 retains the test
fixture's computed-destructure parser failure; attempt 002 checked its repair.
See `evidence/local-player-cooking-tick-storage-004.json`.

The actual outer wrapper passed all 30 native guards in attempt 009, including
the complete `CS.Saved` player/body/pending/publication/tick encode, decode and
re-encode path. Its build took 209.674 seconds and the native guards 0.769
seconds. Run it with the bundled Python, which provides the existing runner's
NumPy dependency:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_local_player_cooking_storage.py --native
```

See `evidence/local-player-cooking-storage-009.json`. Both native workflows
retain exact source/binary pins, raw outputs, one-attempt process bounds and
confirmed owned-group cleanup.

Five laws against the production helper independently passed the cached
BendTT kernel with zero exclusions. They establish complete tick-owner and
sidecar retention during inspect, complete restoration, restore/inspect
composition, missing-runtime refusal and exact ordered constructor-word
conversion. They reuse the complete entity/runtime recovery proofs, rather
than projecting selected fields into a separate model. See
`evidence/local-player-cooking-tick-storage-proof-001.json`.

To reproduce the checked unchanged-term export, pass a new output directory to
`tools/local_player_cooking_tick_storage_proof.mjs` using Node's
`--stack-size=4096 --experimental-transform-types` options, then run
`/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt` on its `recovery.bendtt` with
`LEAN_STACK_SIZE_KB=4194304`. The exporter checks the complete original book
before selecting the five roots, preserves every checked type/body and rejects
source drift or exclusions.

These are physical codec and pure ownership results. They do not establish
vanilla's persistence of these transient fields, fresh sound/bootstrap ordering,
manager loader revalidation, live entity section migration, or format 5 atomic
save/interruption/cold-restart acceptance. Motion owns the sole live carrier
and capture/restore join; the coherent actor consumer establishes durable IO.
