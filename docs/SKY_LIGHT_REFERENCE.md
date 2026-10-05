# Pinned Java 26.3 sky-light reference

`tools/reference_sky_light.py` executes the installed, unmodified official
`SkyLightEngine`, `SkyLightSectionStorage`, and `ChunkSkyLightSources` classes.
The observations are retained in `reference/sky_light.json`; the reproducible
execution receipt is `evidence/sky-light-reference.json`. Confidence in the
observed method behavior is **high**. This reference is independent of the Bend
implementation and does not establish complete client parity.

Run from the Minecraft repository:

```sh
python3 tools/reference_sky_light.py extract
python3 tools/reference_sky_light.py check
```

`extract` writes the retained reference. `check` executes the Java harness again
and requires exact equality with the retained inputs, observations, class hashes,
harness hash, bytecode dump hash, and verified installation provenance. The
receipt records timing and the actual Java command. Java source and diagnostic
output remain in ignored `build/sky-light-reference/`; proprietary class bytes
are not copied into the repository.

The installed client SHA-256 is
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
The official classes used to establish the principal contracts are:

| Class | SHA-256 |
| --- | --- |
| `SkyLightEngine` | `d51d0e1e8471df52fe1332b4277cdd94f20f239ea17cfc0accd872b0cf4675ba` |
| `SkyLightSectionStorage` | `65673a1e5696e44dfa9606e6243653b244c076a5a156aee0794401dd7f4b3090` |
| `ChunkSkyLightSources` | `864a79485e08cf347286f81cf12a05fdf9f64a579afe140e7cd854cfecc37229` |

All three are in `net.minecraft.world.level.lighting`. The reference includes
16 official class fingerprints and the verified official library classpath.

## Source columns and ordinary transfer

`ChunkSkyLightSources.fillFrom(ChunkAccess)` scans downward through actual
official block palettes. A downward edge is blocked when the **lower** block's
light dampening is nonzero, or when the upper block's DOWN face and lower block's
UP face jointly cover the face. The stored source threshold is the upper cell's
Y. An opaque or attenuating block at Y=8 therefore normally makes Y=9 the lowest
direct sky source. Source heights are not a heightmap of only fully opaque blocks.

The internal minimum is `worldMinY - 1`. An entirely unobstructed column exposes
`Integer.MIN_VALUE` (`-2147483648`), extending source status below build height.
Incremental `update(BlockGetter,x,y,z)` checks the edited cell's upper and lower
edges and rescans downward only when an old highest obstruction is removed.
Each edited receiver phase compares the incremental map against a fresh actual
`fillFrom` scan of all 256 columns in every declared chunk.

`SkyLightEngine` directly assigns level 15 to every stored cell at or above an
enabled column's source threshold. This creates lossless vertical sky columns.
Its ordinary `propagateIncrease` method subtracts
`max(1, receivingBlock.getLightDampening())` in **every** direction. It contains no
special DOWN / level-15 zero-loss branch. Directional face occlusion also applies.

The auxiliary `ordinary_downward` probe queues a level-15 storage seed in a
blocked source column and invokes the actual protected propagation method with
an official DOWN-only queue entry. At Y=8,7,6,0, the result is `15,14,13,7`.
The declared storage seed isolates transfer; it is not presented as a valid
fresh natural sky source.

The pinned actual representative water state is 89 with dampening **1**. Ice
state 8597 and waterlogged bottom oak slab state 15179 also have dampening 1.
Dry bottom oak slab state 15180 and top oak slab state 15178 have dampening 0.
Actual water in a closed vertical duct therefore gives Y=9,8,7,6 levels
`15,14,13,12`. Glass restores direct source status and level 15 down the column.

Dry bottom slab at Y=8 has a full DOWN face and makes Y=8 the lowest direct
source; the slab receives 15 while the duct below is dark. A top slab's full UP
face makes Y=9 the lowest direct source, and the slab is dark. Adjacent horizontal
bottom/top slabs jointly close their shared face; matching bottom slabs admit
ordinary attenuating light. These observations use actual registered states and
actual Java shape tests.

## Sections, enablement, and publication

`updateSectionStatus(section,false)` declares a section nonempty. Its 26 neighbors
acquire storage through neighbor counts, including sections in absent chunks.
Allocated light storage therefore does not imply block-chunk residency.

`setLightEnabled(chunk,false)` removes source admission and preserves stored
levels. Enabling may fill empty upper layers. For all-air source maps,
`Integer.MIN_VALUE - 1` wraps to `Integer.MAX_VALUE`, so enable-only ordinarily
does not perform that fill. `propagateLightSources(chunk)` explicitly enables
and assigns direct sources. It does not clear old values below the new source
height.

Direct source assignment can modify updating layers while `hasLightWork()` is
false. The harness always executes `runLightUpdates()` at least once after a
phase so that those changes reach visible storage. That method checks nodes,
drains decreases, drains increases, clears the chunk cache, applies queued layer
changes/removals, then publishes visible storage. The returned work count counts
queue entries, not checked cells or changed blocks.

The `lighting_enablement` fixture uses an all-air chunk with min Y=-16 and height
32. Its sample at Y=32 is above the column top; the other eleven samples are in
allocated sections.

| Phase | Stored sample levels | Public Y=32 | Updating Y=32 |
| --- | --- | --- | --- |
| Initially disabled | 0 | 15 | 0 |
| Enable only | 0 | 15 | 15 |
| Propagate sources | 15 | 15 | 15 |
| Disable | Retained 15 | 15 | 0 |
| Insert full stone roof at Y=8 while disabled | Roof 0; retained 15 below and above | 15 | 0 |
| Enable only after edit | Same retained field | 15 | 15 |
| Propagate after reenable | Same retained field | 15 | 15 |

Consequently, enabling and propagating again is not a repair operation for that
disabled-edit history. A fresh recomputation after reenable would describe a
different lifecycle from these observed retained Java layers.

The additional `lighting_enablement_low_roof` fixture starts disabled with a
full stone roof at Y=-8, whose source threshold is -7. Enable-only fills empty
resident section 0 (Y=0..15) with 15 while section -1 (Y=-16..-1) stays 0.
Explicit propagation then injects direct sources above the roof within section
-1, making Y=-1 level 15. The roof at -8 and sample below it at -16 remain 0.
This isolates the upper-section fill performed by enabling from source injection.

## Sparse lookup and missing chunks

The public visible `getLightValue` returns 15 at or above a column's top section,
or when the column has no top entry, regardless of enablement. The updating
lookup returns 0 in that early branch when the column is disabled. Within an
existing layer, both lookups return the stored nibble regardless of enablement.

Below the top, an absent layer walks upward to the first present layer and reads
that upper layer's **bottom plane**, preserving X/Z. The sparse fixture allocates
active sections 0 and 4, leaving section 2 without a layer. A queued section-3
layer has bottom sample 11, interior default 7, and top sample 3. Reads in missing
section 2 return 11 at both Y=32 and Y=47; actual section-3 reads at Y=48,49,63
return 11,7,3. Its top section is 6 and storage bottom is -1.

`LightEngine.getState` returns BEDROCK when the chunk getter returns null.
`SkyLightEngine.getChunkSources` returns null. Source-height fallback depends on
the caller: checked-node source admission uses `Integer.MAX_VALUE`, neighboring
source comparisons use `Integer.MIN_VALUE`, and explicit chunk source propagation
substitutes an empty source map. The missing-chunk probe records these interfaces
separately. Explicitly enabling and propagating an absent chunk can assign 15 in
its allocated halo layer even though its block-state fallback is bedrock.
Neither public light lookup nor allocated storage is a chunk-residency oracle.

## Fixture boundary

Eight receiver scenarios contain 36 settled phases and 450 sampled levels. There
are three auxiliary probes for sparse storage, missing chunks, and isolated
ordinary downward transfer. Nine representative states supply 486 directed
shape edges and 81 downward source edges. These are actual Java observations;
there is no exhaustive-registry parity claim.

Controlled chunks are actual `ProtoChunk` instances with actual
`LevelChunkSection` / `PalettedContainer` block storage. Geometry is declared by
the reference's default state, fills, writes, chunk coordinates, and bounds.
Unused biome, tick, factory, and blending fields are null; none are queried.
Outside-build-height state reads use actual `ProtoChunk` behavior. Python only
orchestrates execution, checks invariants/provenance, and serializes results.

This reference does not launch the game, establish renderer/lightmap behavior,
validate save/packet persistence, define chunk scheduling or dimension policy,
or claim complete client acceptance. The Bend consumer must state how its own
resident sections, declared known-empty sections, missing chunks, enablement,
and publication lifecycle map onto these observed interfaces.

## Native Bend comparison

`tools/test_sky_light.py` builds `tests/sky_light_receiver.bend` and runs the
actual `sky_light_world.bend` bridge over real Core section arrays. The executable
receives only declared geometry, actual Java block dampening, and actual Java
directional face-closure observations. Expected Java levels and source heights
remain in Python's comparator; source thresholds are scanned from actual Core
blocks by Bend.

```sh
python3 tools/test_sky_light.py
python3 tools/test_sky_light.py --reuse-native
```

The second command reuses a native binary only when its binary hash and complete
project Bend import closure match the cached successful build. It reruns the
comparisons. Neither command reruns Java.

`evidence/sky-light-native.json` records the successful C emission and native
build, 47 phase comparisons, 509 resident Java block/light sample pairs, and
409,600 actual Core array-cell comparisons. All eight Java receiver scenarios
are exercised incrementally. Additional work budgets 1 and 256 reproduce the
shape-union and water fixtures. Full resident Core arrays are serialized as
lossless scalar-ID runs and compared exactly against declared geometry after
every phase, alongside all six Core clock fields.

The bounded refusal guard corrects invalid bounds, retries UnknownSection with
KnownEmpty, then retries a missing descriptor. Sampling refuses while loading.
The successful result retains the Core clock with a future pending mutation,
keeps the actual resident AIR array, and reports missing Core positions as
`None/None` even when the sidecar has declared known-empty geometry. A separate
native guard retains a resident AIR section immediately below the build minimum
and samples its direct sky sources. That halo guard is a native contract
regression, separately identified from the retained Java sample comparisons.

These tests establish the stated receiver and ownership observations. They do
not replace the production kernel proofs, actor/frame integration, actual
rendered brightness, long-session behavior, or client acceptance evidence.
