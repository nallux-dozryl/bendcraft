# Compiled density intervals and numerical boundaries

`worldgen_density_interval` implements the pinned 26.3 `Interval` operations
over binary32 endpoints, including NaI, infinities, signed zero and Java's
NaN-propagating minimum/maximum behavior. `worldgen_density_ranges` analyzes
the actual child-before-parent Program and loaded noise resources. Missing
children or definitions return an explicit error. `worldgen_density_minmax`
uses these ranges to select the actual Java disjoint, constant and bounded
sampling paths; failed reads cancel the remaining callback and retain the
complete returned affine owner.

Density function and spline scalar results in this release use binary32.
Noise coordinate scaling and shifting use binary64. The production
`worldgen_density_coordinates.shifted` function converts signed block
coordinates to binary64 before multiplying a binary64 scale, and converts
the evaluated binary32 shift before adding it. The native reference consumer
calls this same function and compares all six raw words of the three double
coordinates observed at the real Java `Noise.get` boundary. Comparing only
the resulting float density could conceal a coordinate error.

The pinned Java batch contains 82 actual interval/operator cases, 50 actual
noise coordinate cases including integer extremes and very large/small
scales, 24 compiled density graphs and 96 real column values from the loaded
`minecraft:overworld/sloped_cheese` graph across four seeds. This column graph
is a shipped predecessor of final density. It is not an invented flat or
constant replacement for the remaining generation stages. The Java source,
raw process receipts and official classpath pins are recorded in
`evidence/worldgen-density-interval-reference.json`.

One combined native entry exercises the real interval, spline, router and
column consumers. Its build helper copies the exact transitive source closure
before compiling, pins that immutable map, and records later original-source
drift separately. This permits a truthful retained-generation comparison while
other owners continue editing shared modules. No game semantics run in Python.

The first ordinary combined native attempt produced no C/binary/report and
ended with `PermissionError` in its receiver's final process-group probe. The
receiver did not finish writing its process record, so its exit code and
timeout status remain unknown. The exact 49 input files and fresh owned-group
absence are retained in
`evidence/worldgen-density-integration-ordinary-build-failure.json`. The
separate prepared private route reuses the reviewed actor012 CPU emitter on
that same immutable map, with full original ordinary checking and source pins
before/after emission. It does not edit the original compiler or promote output
to the installed content cache. The build and comparison evidence determine
its actual result.

```sh
python3 tools/reference_worldgen_density_intervals.py --observe
python3 tools/test_worldgen_density_intervals.py --source-check
python3 tools/test_worldgen_density_intervals.py --build
python3 tools/test_worldgen_density_intervals.py --compare
python3 tools/test_worldgen_density_spline.py --compare
python3 tools/test_worldgen_density_router.py --compare-cached
python3 tools/test_worldgen_density_interval_proof.py --check
python3 tools/test_worldgen_density_interval_proof.py --runtime-owned
```

The prepared private route uses the bundled workspace Python (the existing
process receiver imports its available numerical/image packages) and accepts
the retained ordinary attempt's `source-map.json` with `--build-private`.
The inherited limits are 6 GiB heap, 600 seconds total emission, 90 seconds
without producer progress and 8 GiB sampled RSS; native C compilation has its
own 300-second cap. These are explicit test/build limits, not product bounds.

The 15 laws in `worldgen_density_interval_laws` state structural NaI/refusal,
empty/missing analysis and actual MinMax control-flow contracts over arbitrary
complete owners and callbacks. They do not assert an IEEE arithmetic theorem.
Independent-kernel and native outcomes are separate evidence fields; the
presence of these commands does not imply an unrun verdict. The exact full
15-root ordinary check and export passed with zero exclusions, but independent
admission rejects `worldgen_density_spline_range.size` through the complete
range-analyzer dependency. That actual wrapper-tail descent limitation is
preserved in `evidence/worldgen-density-interval-proof-limitation.json`.
The exact remaining 14 roots independently pass the kernel in
`evidence/worldgen-density-interval-runtime-proof.json`: source/export 15.165
seconds, kernel 0.294 seconds, and 1,740,618 artifact bytes. Their original
checked types and bodies and all declaration maps remain unchanged. Only
`empty_range_analysis_retains_complete_existing_table` is outside that
admitted scope; its original statement and proof remain in the full target.

The full normal-population route remains explicitly refused. The shipped
final-density closure still contains interpolation, interval selection and
beardification; material selection, aquifers, surface rules, structures and
features must join before complete normal sections may be published. The
flat path, durable generator settings, Scene and root entry points are unchanged
by this dependency checkpoint.
