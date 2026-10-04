# Loaded normal-generation density consumers

The new density path evaluates actual loaded 26.3 expressions against the
durable normal Overworld plan. The flat path and Scene routing remain usable;
normal chunk population still returns its existing explicit refusal. This
component is a dependency of normal generation, not a completed generator.
Confidence is high for the checked ownership contracts and observed supported
scalar inputs; unimplemented final-density stages have no parity claim.

`worldgen_density_loader.initialize(plan, loaded, expression, limits, fuel)`
decodes the selected resource-keyed density/noise definitions, resolves density
references into a finite DAG, retains the complete plan, original expression
and loaded registry, and initializes each distinct seeded sampler once.
`worldgen_density.evaluate(depth, owner, node, point)` returns the affine owner
beside either the float result or a diagnostic. The original cache is restored
on refusal; sampler lookup reconstructs every owner at its original position.
The per-coordinate cache shares repeated DAG nodes and is reset when the exact
signed block coordinate changes. Graph, reference/depth, registry and random
budgets are caller-supplied resource policies.

`worldgen_density_column.sample(owner, request, sample_budget, depth)` consumes
that actual loaded graph at each signed coordinate of the existing Overworld
column request. It returns the original expression and ordered float samples,
retains the complete Program and ordered sampler pool, and rolls back the
entire column's initial cache if any sample refuses. Invalid coordinates or
sample budgets retain the exact input State. It publishes no sections: a
density column is an input to the remaining generation stages.

The admitted expression subset includes constants, registry references,
absolute value, square, cube, negate, half/quarter-negative, squeeze, add,
subtract, multiply, clamp, default clamped axis gradients, lerp, range choice,
cache, loaded old blended noise, normal noise with optional shifts and the
actual shift-A/shift-B producers. The compiler retains Java's direct constant
specialization and noise shift specialization. It preserves operation order,
selected-branch behavior and binary64 coordinate/scale operations; expression
results use the release's binary32 density boundary.

The binary64 decoder reads the original decimal token as an exact integer
ratio and rounds at the binary64 boundary. It admits at most 64 mantissa digits,
an explicit exponent magnitude of 384 and a bounded JSON token; larger input
fails explicitly. Constants and thresholds use the actual float codec range
of −1,000,000 through 1,000,000. Noncanonical integer coercions and explicit
gradient tiling modes are currently refused. These are stated loader/resource
limits, not Minecraft world bounds.

Compiled `min` and `max` now use the actual interval-based disjoint selection,
literal-constant and inclusive right-bound short circuits. Loaded spline trees
and their compiled ranges also join the actual finite DAG. The explicit
`initialize_unblended` route admits the release's no-blending scalar defaults:
alpha samples one, offset samples zero, and blend-density samples its input.
The ordinary initializer still refuses a required blending context. `divide`
remains an explicit unsupported operator. Every other unimplemented density
function is an explicit unsupported node. The shipped final-density closure
still requires interpolation, interval selection and structure beardification;
normal population additionally requires material, aquifer, surface and feature
stages. Missing noise resources,
cycles and exhausted budgets are errors; none become an air cell or zero
density.

The compiler builds child nodes before their parents, resolves named roots
once and detects reference cycles. Public State/Program constructors also
permit manually assembled values; the evaluator does not certify a forged
Program as a valid compiled DAG. An absent node or exhausted evaluation depth
returns an explicit error and preserves the original cache.

The actual `worldgen_density_router` consumer compiles the retained router
expressions from `worldgen_noise_settings.Router` into one Program and shares
their seeded sampler owners and cache. Its six climate outputs feed the actual
loaded nearest-point search through `worldgen_biome_resolver`; its selected
final root feeds the existing density-column consumer. The shipped final root
still refuses its unsupported functions. Final density must pass through
aquifer/material/surface/structure/feature producers before complete chunk
sections can be published. See [router and biome contracts](WORLDGEN_DENSITY_ROUTER.md),
[spline contracts](WORLDGEN_DENSITY_SPLINE.md), and
[compiled interval and numerical boundaries](WORLDGEN_DENSITY_INTERVALS.md).
Chunk publication must preserve already resident sections/edits and saved
generation identity through the existing demand facade. No normal-population
switch is justified before these joins are implemented and verified.

Verification commands:

```sh
python3 tools/test_worldgen_density.py --source-check
python3 tools/test_worldgen_density.py --build
python3 tools/reference_worldgen_density_probe.py --observe
python3 tools/test_worldgen_density.py --compare-cached
python3 tools/test_worldgen_density_proof.py --check
```

The reference helper reuses the pinned official classpath and process receiver.
Actual Java codecs/compiled samplers/NormalNoise constructors produce expected
values; Python selects inputs and compares returned raw words. Structural
proofs and native numerical evidence have separate scopes. The initial native
build completed in 519.55 seconds; the substantive signed-zero admission
refresh completed in 335.24 seconds, both with zero retries. Actual Java
observations contain 28 binary64 conversions, 69 compiled graphs with 828 float
samples, and 88 NormalNoise boundary/construction cases. The refreshed native
comparison passed all 28 double words, 828 density words and eight graph
refusals. It also passed 68 actual NormalNoise constructors, all 180,224
permutation words, 544 getter words, 544 public-constructor getter words and 20
codec, fuel or unsupported-initializer boundaries. All 263 native calls were
reaped; their combined execution time was 9.04 seconds.

The density artifact was built with Core SHA256 `48d63c4a…`; Core subsequently
changed for the independent section-map update join. The comparison verifies
the retained Core bytes, artifact manifest, emitted C and every other current
dependency, and records that distinct source generation. The default comparison
still rejects any changed source. The NormalNoise artifact's dependencies are
all current. The current-source 34-law column/evaluator proof is a separate
verdict; no old-Core numerical receipt is relabeled as a current-Core build.
To reproduce the retained-generation comparison locally:

```sh
python3 tools/test_worldgen_density.py --compare-cached --retained-core \
  build/superflat-world/reference/density-source-1791133701218628000/snapshots/12-core.bend
```

An initial refusal fixture selected the whole offset graph and incorrectly
expected its spline diagnostic; `blend_alpha` is encountered first. The final
fixture selects the actual loaded inner spline node directly. The failed
attempt remains retained, and no Java numeric observation changed.

At the previous density checkpoint, the 34 laws in `worldgen_density_laws.bend`, proved by
`worldgen_density_proof.bend`, independently establish arbitrary evaluator and
column complete Program/ordered-pool retention, scalar and whole-column cache
rollback, cache-hit and invalid-request behavior, registry refusal and actual
loader/compiler/factory composition. The final exact export admitted all 34
roots with zero exclusions in 14.28 seconds for source checking/export and
2.25 seconds in the independent kernel. Six separate NormalNoise producer
contracts are recorded in `evidence/worldgen-density-noise-owner-proof.json`.
Neither these structural contracts nor finite raw-word observations establish
all density operators or complete normal-world generation. On the extended
spline runtime, the exact full 34-root export passes ordinary checking, but
the independent kernel rejects the actual spline JSON-size helper's wrapper
tail descent. This is recorded in
`evidence/worldgen-density-proof-size-descent-limitation.json`; it is an open
compiler/admission obligation. The current exact 19-root evaluator/column
ownership scope independently passes the kernel, with all declaration maps and
checked types/bodies retained unchanged, in
`evidence/worldgen-density-runtime-proof.json`. No unchanged checkpoint proof
or finite numerical receipt is relabeled as a full current-generation verdict.
