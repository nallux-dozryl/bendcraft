# Loaded 26.3 density router and biome join

`src/worldgen_density_router.bend` compiles the actual expressions retained by
an `O.Plan` into one finite density DAG. Its eight outputs preserve the pinned
names and order: `chunk_surface_level`, `continents`, `depth`, `erosion`,
`final_density`, `ridges`, `temperature`, `vegetation`. Compilation threads one
`C.Build` across all roots, so loaded reference identities share one memo and
node index. Initialization constructs one seeded producer pool and one point
cache through the actual production density state factory.

`compile(plan, registry, limits)` and `initialize_loaded(plan, resources,
limits, fuel)` require all eight expressions to compile. Their primary
`A.Program` expression/root is the actual selected `final_density`.
`column(owner, request, budget, depth)` delegates to the existing production
`worldgen_density_column.sample` facade. No scalar threshold publishes blocks
or sections.

`compile_climate` and `initialize_climate_loaded` compile only the six actual
climate dependencies while retaining the complete original router. They use
`ClimateRoots`, which has no final-density or surface index. Requests for
those absent channels, eight-output sampling, and final-density columns fail
explicitly. No unsupported expression receives a zero or identity substitute.

`compile_climate_unblended`, `load_climate_unblended` and
`initialize_climate_unblended` use the density compiler's explicit
`C.lower_unblended` boundary. Both the resulting Program and affine State retain
`UnblendedRoots{roots}`, and `policy` reports `NoBlending`. This invokes the
actual absent-context defaults for blend alpha/offset/density; a real world
Blender/context producer remains a separate dependency. The general compiler
continues to refuse context-dependent blending expressions.

`compile_unblended`, `load_unblended` and `initialize_unblended` provide the same
explicit policy for all eight requested inputs. This enables a production
column through the actual loaded `minecraft:overworld/sloped_cheese`
final-density predecessor while keeping the original selected expression and
the existing Column facade.

`evaluate`, `sample` and `climate` thread the same actual density owner.
`climate` samples `[temperature, vegetation, continents, erosion, depth,
ridges]`, corresponding to temperature, humidity, continentalness, erosion,
depth, and weirdness. Pinned26.3 `DensityFunction`/`DensitySampler` outputs are
binary32. The existing evaluator retains binary64 noise scales, coordinates
and producer intermediates; this facade does not widen a float and label it
an original double.

`src/worldgen_biome_resolver.bend` joins that sampler to the actual loaded
`worldgen_climate.Loaded` parameter table and tree. `attach` derives the biome
plan from the retained generation plan, verifies that all original router
bindings match, and delegates to `worldgen_climate.prepare`. A refused attach
returns the entire affine density owner. `initialize` is the convenience
factory for the explicit unblended six-axis path. It requires a caller-supplied
loaded parameter table; preset identity alone is insufficient.

`sample(owner, depth, quart)` uses the existing wrapping
`worldgen_biome.to_block` conversion, then the actual router climate sampler,
float quantizer and cached parameter-tree search. It returns the selected
biome identifier, exact table index and signed-Java-long fitness words. Fixed
biomes preserve the complete router owner and require no density evaluation.
Any refused composed sample restores the previous density point cache and
climate leaf history while retaining the full program, ordered seeded pool,
preset definition, complete parameter table and tree.

## Verification

The paired router/join LAWS and PROOF files state contracts against the actual
implementation, including arbitrary full affine owner retention for a list of
root reads by induction composed with the existing density evaluator proof,
precise admission/compile/factory diagnostics, actual root/axis binding,
absent-root refusal, Column delegation, loaded-table preparation, fixed-source
bypass, quantized lookup composition and cache/history rollback. The independent
kernel receipt is separate from IEEE and Java parity observations.

All 34 router/join laws pass the ordinary compiler check and exact checked-term
export in 31.744 seconds, with zero export exclusions. The full 14,237,941-byte
export is rejected by the independent kernel at the existing
`worldgen_density_spline_range.size` traversal: the production function
reconstructs a smaller `Multi` wrapper that the kernel does not recognize as a
structural descent. The exact rejected artifact and receiver are recorded in
`evidence/worldgen-density-router-proof-limitation.json`. Production traversal
and compiler behavior remain intact. The separate `--runtime-owned` selection
contains 24 runtime/factory-result/lookup ownership laws and explicitly records
the ten compiler/admission obligations outside that selection. Those 24 exact
roots pass the independent kernel: ordinary check/export 17.229 seconds,
kernel admission 0.234 seconds, 1,346,711 bytes, and zero exclusions. The receipt
is `evidence/worldgen-density-router-runtime-proof.json`. The selection retains
all original declaration maps and unchanged checked types, proof bodies and
runtime definitions; it does not turn the ten separate obligations into
kernel-certified compilation claims.

The combined `tests/worldgen_density_integration.bend` harness passes the
ordinary compiler API check in 27.535 seconds. Its recorded source generation
contains the final full-eight unblended SlopedCheese extension and the actual
router/resolver/harness bytes. The receipt is recorded in
`evidence/worldgen-density-router-source.json`; the earlier 11.169-second
checkpoint and repaired attempts remain identified separately. The native
verification route uses the parent's
combined `tests/worldgen_density_integration.bend` artifact and its `router`
argument prefix when the current pointer names that build.

`reference/worldgen_density_router.json` records actual pinned Java observation
through `VanillaRegistries`, `DensityFunction.CODEC`, `RandomState`, the actual
uncached climate sampler and actual `Climate.ParameterList`. The observation
uses four seed bit patterns, repeated points, negative/world-boundary coordinates
and quart-to-block signed overflow. Nine supported eight-root scenarios provide
720 float words, including 320 words through the actual loaded SlopedCheese
predecessor. Four shipped six-axis scenarios provide 168 float words and
168 quantized Java-long axis values, plus 28 actual selected biome/index/fitness
observations. The shared-reference case
uses the same actual loaded temperature reference in all eight explicit inputs.
The supported eight-root fixtures explicitly select the actual loaded base3d
dependency or SlopedCheese predecessor as final input, and a supported custom
surface gradient. The SlopedCheese case retains all six original climate
expressions. These fixtures do not claim the shipped final-density graph.

The native harness consumes the production loader/compiler/sampler/Column and
loaded-preset join. Python decodes requests, checks source/artifact identity and
compares independently emitted Java answers; it implements no density or biome
search algorithm. The ordinary `tools/build_native.py` route supplies the
content-keyed frozen source closure. Reference and native executions use the
existing bounded process receiver and verified official classpath.

The first coordinated ordinary combined build produced no generated C,
executable or final build report. Its receiver raised `PermissionError` during
process-group cleanup, leaving exit/timeout status unknown; the parent verified
that its owned group was absent and preserved the exact attempt in
`evidence/worldgen-density-integration-ordinary-build-failure.json`. A reviewed
alternative emission route uses the same frozen runtime closure. No native
pointer has been published at this checkpoint, so the router numerical
comparison has not executed. `evidence/worldgen-density-router-native-prepared.json`
records the prepared matrix: 720 eight-root float words, 168 six-axis float
words, 168 quantized axis longs, 28 biome selections, 18 Column words
(including eight through SlopedCheese), the shared-reference budget scenario,
and eight refusal boundaries. These are intended comparison counts, not
passing native results.

Commands:

```sh
python3 tools/reference_worldgen_density_router.py --observe
python3 tools/test_worldgen_density_router.py --source-check
python3 tools/test_worldgen_density_router.py --build
python3 tools/test_worldgen_density_router.py --compare-cached
python3 tools/test_worldgen_density_router_proof.py --check
python3 tools/test_worldgen_density_router_proof.py --runtime-owned
```

The whole shipped eight-root router still has explicit unsupported production
dependencies. Successful climate and loaded-preset resolution do not establish
final density, surface search/interpolation, aquifers, materials, carvers,
structures, features, entities, or complete normal chunk population.

## Remaining shipped inputs and consumer joins

File-only inspection verifies all 55 retained density definitions against their
existing pinned26.3 installed resource bytes. Expanding each reachable named
definition once, the shipped `final_density` closure contains 20 definitions
and 179 typed JSON objects. Nine objects have decoder-unsupported types:

| Type | Objects | Retained location |
| --- | ---: | --- |
| `minecraft:interpolated` | 5 | One outer final-density interpolator and four within `overworld/caves/noodle` |
| `minecraft:interval_select` | 3 | Two within `overworld/caves/entrances`, one within `overworld/caves/spaghetti_2d` |
| `minecraft:beardifier` | 1 | The final-density root's right child |

The surface root additionally contains one `interpolated` object and one
`find_top_surface` object. Across the shared eight-root resource closure,
there are six `interpolated`, three `interval_select`, one `beardifier`, and
one `find_top_surface` objects outside the current decoder. These counts
describe typed resource objects, including children of unsupported parents;
they are neither compiled DAG-node counts nor dynamic sample counts. Exact
paths, per-root type counts, resource pins, and retained official signature
receipts are in `evidence/worldgen-density-router-boundaries.json`.

The next named joins are proposals, with no implementation or population claim:

1. A density interpolation consumer should retain the loaded `cell_size_xz`
   and `cell_size_y`, consume the same seeded density owner, and expose both a
   scalar sample and an explicit volume request. The retained official
   `InterpolatedFunction.Sampler.sampleValue` computes Java `floorMod`, samples
   a `2×2×2` lattice through `sampleVolume`, divides fractions in binary32, and
   invokes binary32 `Mth.lerp3`. An aligned lattice point delegates directly to
   its input. A Bend `Interpolation.sample`/`sample_volume` join must preserve
   that geometry, operation order, and affine producer ownership; scalar child
   evaluation alone does not establish the volume path or its buffer/cache
   behavior.
2. An interval-selection operation should decode the actual `input`,
   `thresholds`, and `functions` lists into the shared compiler work dispatcher.
   The retained official scalar sampler selects the first threshold for which
   the input is strictly less, then evaluates only that selected function at
   the same point; equality advances to the next interval. This is a separate
   operator from the implemented two-branch `range_choice`. Its volume path
   and boundary cases require their own observations and contracts.
3. A world-context owner should join real blend providers and the structure
   `Beardifier.CONTEXT_KEY` provider to the density sampler. The retained
   official context-bound defaults are alpha one, offset zero, and absent
   beardifier zero; the current explicit no-blending compiler admits only the
   blend defaults and still refuses `beardifier`. A structure contribution
   cannot be inferred from the existing climate sampler or seeded noise pool.
   Surface search must additionally implement the retained
   `find_top_surface` definition and its coordinate/step behavior.
4. A proposed `NormalPopulation.demand` should consume the retained `O.Plan`,
   complete router/interpolation/context owner, actual loaded biome resolver,
   `NS.Settings.aquifers`, `material_rule`, default block/fluid and sea level.
   Its aquifer, material and surface-rule producers must yield block states
   before section publication through the existing
   `superflat_world.demand_current` world-demand boundary. Publication must
   preserve resident sections, edits, generation identity and interrupted
   work; structures, carvers, features, entities and spawn remain additional
   required phases. The current scalar Column and six-axis biome consumer
   justify no normal-population switch.

The resource inventory is reproducible without starting Java or a native build:

```sh
python3 tools/inspect_worldgen_density_router_boundaries.py --inspect
```
