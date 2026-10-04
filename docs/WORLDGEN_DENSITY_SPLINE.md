# Pinned 26.3 density splines

`minecraft:spline` decodes through the actual loaded density codec into
`worldgen_density_spline.Tree<json.Value>`. Compilation substitutes actual
DAG indices for coordinates and retains nested spline values and point order.
The density evaluator shares one decreasing caller-depth traversal across
node work and spline work, reads the coordinate through the same seeded state,
and evaluates only the selected endpoint or two adjacent child values.
The complete program and ordered sampler pool cross those reads unchanged;
cache writes and rollback follow the density evaluator's existing transaction.

## Observed numeric contract

The authoritative 26.3 `CubicSpline.apply`, `Constant.value`, point location,
point derivative, and density sampler return types are Java `float`. This is
an actual binary32 boundary. Coordinate density nodes may contain binary64
noise intermediates, whose representation belongs to the noise subsystem.
Spline values, locations, and derivatives use unrestricted `Codec.FLOAT`.
The ordinary density constant codec's +/-1,000,000 limit does not apply here.
The retained Java cases include signed zero, subnormals, overflow to infinity,
and decimal strings immediately around a binary32 midpoint. Spline lexical
validation adds no 128-character or 16,384-character numeric-token cap; the
caller JSON parser retains its explicit input budget.

The official constructor requires nonempty points and corresponding array
sizes. It accepts duplicate and unsorted locations. Production preserves
that behavior and reproduces `Mth.binarySearch` with the strict predicate
`x < location[i]`; it does not sort or deduplicate. A NaN coordinate therefore
selects the last endpoint. A zero endpoint derivative returns its child value
without computing zero times an infinite displacement.

For a selected segment, operations run in the observed float order:

```
width = l1 - l0
alpha = (x - l0) / width
a = d0 * width - (v1 - v0)
b = (-d1) * width + (v1 - v0)
value = lerp(alpha, v0, v1)
      + (alpha * (1 - alpha)) * lerp(alpha, a, b)
lerp(t, first, second) = first + t * (second - first)
```

Negation toggles the sign bit. The source uses separate float operations;
there is no introduced fused multiply-add or binary64 interpolation.

Range analysis consumes actual earlier-node ranges from the compiled DAG
analysis table. It reproduces endpoint extension, inclusion of every child
range, the official quarter-scaled conservative derivative envelope, Java
`Math.min`/`Math.max` NaN and signed-zero behavior, and the early coordinate
NaI return. This is the official conservative range algorithm, not a proof
that the mathematically tight range has been found. Missing coordinate ranges
and invalid final intervals remain precise production refusals.

## Production interfaces

`worldgen_density_spline_compile.tree` and `.points` are actual one-layer
compiler functions. Their callback services take and return an arbitrary
complete affine owner; constants and empty lists bypass callback reads.
`worldgen_density_spline_eval.step` takes one coordinate-reader and three
spline-reader services. Only the selected reader services are invoked, in
left-before-right order, with each returned state threaded into the next read.
The parent compiler/evaluator provide structural recursive work dispatchers,
so the subsystem has no forward dependency or density import cycle.

`worldgen_density_spline_range.range` takes generic Data coordinate/context
types and a closed coordinate-range lookup. The actual compiled consumer
uses its ordered prior-node range table. The decoder and range walker derive
their internal work allowance from the complete input tree; traversing point
list tails does not create an arbitrary point-count limit or consume the
caller's semantic nesting allowance.

## Evidence and reproduction

- `reference/worldgen_density_spline.json` retains 40 actual official-runtime
  cases, 337 raw-word samples, 40 ranges, and four codec refusals. It includes
  nested splines, unsorted/duplicate points, gradients, FLOAT tokens, and the
  shipped overworld offset/factor/jaggedness DAGs at four unsigned seeds.
- `evidence/worldgen-density-spline-reference.json` records the official class
  hashes, executed Java helper, classpath checkpoint, and bounded processes.
- The 11 laws in `worldgen_density_spline_laws.bend` quantify over arbitrary
  complete affine owners and arbitrary callback services. They establish
  constant/empty bypass, exact refusal propagation, cancellation of unread
  children after failure, successful point order, and early NaI cancellation.
  `evidence/worldgen-density-spline-proof.json` retains exact checked roots
  admitted by the independent BendTT kernel with no exclusions or term edits.
- The parent density proof composes actual callback ownership witnesses with
  induction on the actual `Density.work` caller depth. Its 19 actual runtime
  ownership/cache/Column contracts are independently kernel certified in
  `evidence/worldgen-density-runtime-proof.json`, with unchanged checked
  types/bodies and no export exclusions. Layer laws do not by themselves
  assert that arbitrary callback implementations preserve owners.
- All 34 parent density laws pass ordinary source checking. The independent
  kernel rejects the full compiler closure at the exact size traversal's
  reconstructed `Multi(coordinate, point-list tail)` descent; the JSON size
  helper has analogous array/object-tail reconstruction. The attempted
  closed-template fold hits the ordinary checker's unfilled-definition
  restriction. Exact behavior and caller bounds were retained.
  `evidence/worldgen-density-proof-size-descent-limitation.json` records the
  complete rejected attempt; the 15 compiler obligations remain explicitly
  outside the 19-root kernel claim.
- `tests/worldgen_density_spline.bend` calls the production unblended loader,
  compiled DAG evaluator, and range analyzer. The native suite compares the
  supported 36 cases and 289 samples plus 36 ranges. Four reference cases
  needing the still unsupported Divide coordinate are retained and checked
  as explicit production refusals, alongside the four official codec refusals
  and three caller-budget refusals. A separate long-token regression checks
  removal of inherited numeric lexeme caps; its expected binary32 word comes
  from the representable value 1.0 and its negligible positive decimal tail.
  The native comparison passed all those checks in 88 bounded calls;
  their retained execution time totals 8.130 seconds and all owned process
  groups are absent. `evidence/worldgen-density-spline-native.json` records
  counts, failures, source identity, binary/report hashes, and the fingerprint
  of the complete retained raw receipt under `build/`.
- The first native attempt matched every spline sample and range but exposed
  a Python assertion that expected runtime-depth failure at the top level.
  The existing harness reports that failure separately for each sampled
  point. The expectation was corrected; production Bend and the native
  artifact were unchanged. The initial failure remains in
  `evidence/worldgen-density-spline-native-initial-failure.json` with its own
  full-receipt fingerprint.

Commands, coordinated under the repository's two-heavy-job limit:

```
python3 tools/reference_worldgen_density_spline.py --observe
python3 tools/test_worldgen_density_spline_proof.py --check
python3 tools/test_worldgen_density_proof.py --runtime-owned
python3 tools/test_worldgen_density_spline.py --source-check
python3 tools/test_worldgen_density_spline.py --build
python3 tools/test_worldgen_density_spline.py --compare
```

The completed comparison used the parent's frozen combined native artifact
for the spline, router, and interval suites. Its 49 original source files,
117 loaded/native input pins, emitted C, and native binary were validated.
After the ordinary build's process-cleanup error produced no artifact, the
reviewed diagnostic-012 CPU emission route compiled the same frozen closure.
The report retains that private build provenance; it was not promoted into
the product cache. The complete comparison receipts remain under ignored
`build/` paths, while committed evidence carries their hashes and summaries.
These scopes do not establish complete chunk generation or visible world
acceptance. Numeric parity claims are limited to the actual compared cases.
