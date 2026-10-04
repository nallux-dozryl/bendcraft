# Normal Overworld generation in 26.3

The new normal-generation route begins at the actual durable `WG.normal(seed)`
request. `worldgen_overworld.prepare` joins that request to the loaded noise-settings
definition, checks its identity and dimension geometry, and retains both complete
inputs. It derives the root random factory from all 64 saved seed bits and the
definition's `legacy_random_source` flag. This is a producer dependency of the
normal generator; it does not authorize filling chunks with a surrogate terrain.

The current saved-world demand path still refuses noise generation. Joining the
remaining density graph, climate/preset search, aquifers, material rules, surface,
carvers, structures and features is required before that path can populate normal
Minecraft terrain. Existing flat demand and durable saved-owner behavior are
unchanged. The renderer's current resource/view budget and resident-region
persistence are separate remaining product dependencies. The current collision
driver/reset admission box `[-64,64]^3` and neutral dry/loaded environment also
remain explicit unfinished world/runtime joins; they do not define normal
Minecraft's world bounds or environmental simulation.

## Actual loaded definitions and seed binding

`worldgen_noise_settings` retains the eight current router expressions:
`chunk_surface_level`, `continents`, `depth`, `erosion`, `final_density`, `ridges`,
`temperature`, and `vegetation`. It also retains geometry, sea level, random
algorithm, default block/fluid IDs, material rule, optional aquifers, spawn targets,
debug functions, and mob-generation policy. Expressions remain their original JSON
values for the corresponding compiler. They are never replaced with zero or a
fabricated registry reference. The decoder admits the actual installed Overworld
definition, preserves absent aquifers, and uses the actual empty default for omitted
debug functions. Its current numerical metadata boundary accepts canonical signed32
integer tokens; general vanilla numeric coercion, arbitrary block-state object
definitions and binary64 configuration JSON decoding remain explicit unfinished
resource-decoder work. This is not a claim of complete vanilla codec equivalence.

`worldgen_seed` implements the actual `RandomState` binding. The nonlegacy path is
xoroshiro128++ seeded from the saved long, followed by `forkPositional`; named
streams xor the factory words with the two big-endian64 words of Java's UTF-8 MD5.
`worldgen_md5` computes the [RFC 1321](https://www.rfc-editor.org/rfc/rfc1321.html)
digest in pure Bend. Current world-generation resource
and octave names are ASCII; non-ASCII names and names exceeding the caller's byte
budget fail explicitly. The legacy terrain stream uses the original saved long,
matching `CompileContext.createRandom(minecraft:terrain)`'s legacy exception.
The existing generic RNG hash refusal is unchanged.

## Real base-density consumer

The current production consumer is `worldgen_overworld.compile_base` followed by
`sample_column`. It creates the actual 16/16/8 smeared-Perlin stacks for the retained
plan's `minecraft:terrain` stream, then samples `minecraft:overworld/base_3d_noise`
at ordered signed block coordinates. The installed configuration is xz scale 0.25,
y scale 0.125, xz factor 80, y factor 160 and smear multiplier 8. The type also admits
other configurations in the actual finite codec ranges, without pretending their
JSON doubles have already been decoded. Count and signed-coordinate admission
precede reads; invalid requests return the complete sampler owner unchanged.
The sample budget is a caller resource policy, not a Minecraft world bound.

The release's scalar path differs from older Minecraft formulations. The actual
classes are `GradientNoise`, `PerlinNoise`, `SmearedPerlinNoise`, `NoiseStack` and
`BlendedNoise`; there is no `ImprovedNoise` class in the pinned jar. Coordinate and
frequency operations use binary64 while gradient interpolation, layer amplitudes,
accumulation, clamp and blending use the actual binary32 opcode order.
Each sampler owns its complete 256-entry permutation and threads that owner through
reads. Construction uses three offset doubles followed by 256 Fisher–Yates bounded
draws, including the final bound 1 draw. A bounded-draw failure rolls back the
complete original random source. Configuration refusal occurs before draws.

`worldgen_biome` names the actual six climate density inputs and quart-coordinate
boundary. Humidity comes from vegetation, continentalness from continents and
weirdness from ridges. Java's signed-word quart→block shift and its float-times-10000
then saturating-long quantization are explicit. Fixed-biome requests can resolve
without climate sampling. Multi-noise requests retain their definition and fail
explicitly until the actual compiled climate density graph and loaded preset
parameter search join. Loaded preset identity includes its registry key separately
from the definition's built-in preset name, so an alias can retain its actual key
and original JSON. The recorded Java biome results are future independent
expectations; Bend biome-search parity has not been established.

## Independent observations and checks

`reference/normal_overworld_noise.json` contains observations from the actual
official 26.3 registry lookup and untouched production Java classes. Thirteen loaded
class byte hashes match the previously verified official nested server jar. Four
small installed data members pin the noise settings, base3D definition, its
sloped-cheese consumer and the Overworld multi-noise preset definition. Existing
classpath provenance is reused; no full class inventory was rehashed.

Both focused native harnesses compiled on the ordinary content-keyed builder on
their first attempt: seed 4.84s and noise 14.38s. The first native comparison passed
in 1.83s total across 200 bounded calls, all process groups absent/reaped:

- Seventeen actual Java MD5 names, including padding boundaries and a 4097-byte name.
- 136 named random streams across seeds 0, 1, the high signed bit and all 64 bits set,
  under both retained random algorithms.
- Eight full 256-permutation constructors, all offset words and post-source words,
  plus 40 actual Perlin/smeared scalar float words.
- 588 actual `RandomState.sampleBlockValueUncached` base3D values across 12 columns.
- 96 climate quantized words from the actual Java sampler's float outputs.
- Eleven explicit source-fuel, name-budget and unsupported-name refusals.

After correcting the legacy named-stream byte-budget bypass and making numeric
lexeme validation use the actual JSON automaton, fresh artifacts passed on their
first ordinary build attempt: seed 4.50s and noise 21.92s. All exact comparisons
passed again in 1.67s across 203 calls. The fourteen refusals include the same name
budget/unsupported-character checks under both algorithms. The current native
evidence pins this corrected generation; the first artifacts and receipts remain
preserved separately.

These observations establish exact bits for the retained cases, not whole-game,
final-density, generic floating-point, biome-search or chunk-filling parity.
`evidence/normal-overworld-noise-native.json` records the comparison and actual
native source/artifact pins; raw compiler/process receipts stay in ignored build.

Reproduce the actual Java observations with
`python3 tools/reference_normal_noise_probe.py --observe`. Build
`tests/worldgen_seed.bend` and `tests/worldgen_noise.bend` using the existing
`tools/build_native.py` route, then compare their retained current artifact pointers
with `python3 tools/test_normal_worldgen.py --compare-cached`. The standalone
`suite(executor)` helper can instead compare the same expectations through another
coherent artifact exposing those actual harness operations.

Twenty-three actual laws are independently admitted: nine noise-owner/admission roots
in `evidence/worldgen-noise-owner-proof.json`, and thirteen complete metadata,
admission and biome-interface roots in `evidence/normal-overworld-interface-proof.json`.
The separate whole-column owner root is recorded in
`evidence/worldgen-overworld-column-owner-proof.json`. Their checked types/bodies
and entire declaration maps were retained during exact root selection; all three
scopes exported with zero exclusions. The metadata scope
reuses the actual JSON number automaton directly for bounded numeric lexemes, so
it does not depend on the parser's irrelevant formatted-error recursion.

The complete Array, corner-hash, Perlin, stack and blended-getter owner laws now
pass the independent kernel. An initial generic witness bridge failed on a Data
continuation quantity/eta mismatch; direct witnesses for the fourteen actual
returned read pairs repaired that proof plumbing. Production scalar code and law
statements remained unchanged, and the failed inputs/verdicts remain retained.
The column consumer's owner composition passes through the actual recursive
`sample_loop` and both `sample_column` admission branches. The complete retained
plan and all three BlendedNoise stacks are unchanged for every admitted loop count
and for refused requests. `worldgen_overworld_column_laws` states that contract;
`worldgen_overworld_column_proof` composes the actual returned-pair witnesses from
the noise proof. No numerical equivalence theorem or complete normal-generation
proof is implied. The earlier
49 flat/settings laws and their recorded verdicts were not rerun for this work.
