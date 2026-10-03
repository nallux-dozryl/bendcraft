# Pinned Java 26.3 geometry reference

Confidence is high for the recorded Java calls and raw results. This is a bounded geometry oracle, not a gameplay parity claim. [The fixture](../reference/geometry.json) contains 4,522 independently executed cases. Python generates inputs and records output; the official Java classes calculate every expected result.

The oracle calls the installed launcher runtime, Microsoft OpenJDK 25.0.1+8-LTS, against the named classes in the verified official 26.3 server jar. The script verifies the bundle, nested server jar, and every library against the official bundle manifest before executing. The fixture records the actual runtime version, runtime executable hash, Java helper source hash, exact class hashes, relevant method declarations, direct bytecode references, and `javap` method-body hashes. It downloads nothing.

| Artifact | SHA-256 |
| --- | --- |
| Official server bundle | `d052f14d7a173734fba553711e5b570162e2f2a313267ee31a21b975a679be64` |
| Named server class jar | `a362163eec5d1612d520772bc16e5b39c09e3b234fdc045f56bf544284ee8ae6` |
| `net.minecraft.world.phys.AABB` class | `c3597024b2fa129fe34eb2db0ad473ec8ba408393bb2873aa5f43492d455d5fa` |
| `net.minecraft.world.phys.shapes.VoxelShape` class | `c442be4671feb17de9adf9b88962baea0e0048af293faaf3677985cc50e35062` |
| `net.minecraft.world.phys.shapes.Shapes` class | `23add505fd7570b30c9f723734471f71cbd02a84998ad002cf27f87c6b0ddb66` |
| `net.minecraft.world.phys.shapes.ArrayVoxelShape` class | `bdd411498ed442bf7030eee2e9b974c1445d773423801bf926ed1a52ce02e02d` |

Ten named classes and 74 relevant method declarations/bodies are inventoried. Additional classes cover cube and discrete voxel shapes, the filled bit-set grid, axis cycling, axis selection, and `Mth.binarySearch`. The full `javap` output stays in ignored `reference/cache/geometry-bytecode.txt`. Class bytes, rather than copied source or a third-party decompiler, are the source authority.

## Reproduction and verification

Run from `minecraft/`:

```sh
python3 tools/reference_geometry_probe.py
python3 tools/reference_geometry_probe.py --verify-existing
python3 tools/reference_geometry_probe.py --selftest
```

The first command compiles and runs a Java helper, inventories named bytecode, and writes the fixture and extraction evidence. The second checks the official artifacts/libraries/runtime, source and declaration hashes, raw-bit encodings, fixture checksum, deterministic input generation, and equality with the cached Java observations. The third performs two fresh Java runs, compares all 4,522 observations exactly with each other and with the fixture, and checks three deliberately corrupted inputs/results are rejected. Its scope is reference integrity; it does not compare Bend.

The Java helper is stored in ignored `reference/extracted/geometry_probe/ReferenceGeometryProbe.java`; compiled classes, inputs, observations, and logs also stay ignored. An unsigned helper cannot share a runtime package with the signed official jar: Java rejects the signer mismatch. The helper therefore uses reflection only to invoke the package-private `ArrayVoxelShape` constructor and protected `findIndex`. The official class bytes execute directly. There is no copied or modified Minecraft jar, no game launch, and no server tick loop.

Evidence is [extraction](../evidence/reference_geometry_probe.json), [validation](../evidence/reference_geometry_validation.json), and [two-run reproduction with corruption rejection](../evidence/reference_geometry_selftest.json). The fixture-case canonical SHA-256 is `55ac21d2134ccdb83c83768798b1bc430ba0dc62177007d7e93975189f1c344a`; the evidence also records the complete file hash.

## Fixture interface

Schema version is 1. Each case has `id`, `operation`, `tags`, `input`, `expected`, and `observation`. Every floating-point input, endpoint, and result is a lowercase 16-digit hexadecimal IEEE-754 binary64 raw bit pattern. There are no rounded decimal endpoint/result fields. Box coordinates are ordered `minX, minY, minZ, maxX, maxY, maxZ`, but an AABB input is always six constructor arguments: reversed endpoints are intentionally allowed and normalized by Java.

| Operation | Cases | Input and expected output |
| --- | ---: | --- |
| `aabb_construct` | 316 | `box`; expected `box` |
| `aabb_move` | 354 | `box`, `vector`; expected `box` |
| `aabb_inflate` | 354 | `box`, `vector`; expected `box` |
| `aabb_deflate` | 354 | `box`, `vector`; expected `box` |
| `aabb_inflate_scalar` | 354 | `box`, `scalar`; expected `box` |
| `aabb_deflate_scalar` | 354 | `box`, `scalar`; expected `box` |
| `aabb_contains` | 361 | `box`, `point`; expected `boolean` |
| `aabb_intersects` | 348 | `box`, `other`; expected `boolean` |
| `raw_array_box_collide` | 846 | `shape`, `moving_box`, `axis`, `delta`; expected `f64_bits` |
| `raw_array_boxes_collide` | 744 | ordered `shapes`, `moving_box`, `axis`, `delta`; expected `f64_bits` |
| `raw_array_find_index` | 24 | `shape`, `axis`, `value`; expected `integer` |
| `java_f64_compare` | 49 | `a`, `b`; expected Java comparisons and `Math.min/max` bits |
| `shape_construct` | 16 | `shape`; expected realized shape or error |
| `shape_collide` | 48 | constructed/union `shape`, movement inputs; expected `f64_bits` or error |

Exactly 3,600 cases use independently seeded random inputs: 300 sets of eight AABB calls and 600 sets of single/ordered raw collisions. The seed is `2637775023`. The other 922 cases target strict boundaries, both signs, signed zero, subnormals, large finite endpoints, overflow, degenerate boxes, epsilon neighbors, axis permutations, empty iterables, explicit empty shapes, order, coordinate search, construction, and union. The source is the complete specification of generation; expected answers are exclusively Java output.

`observation` records normalized AABB inputs and each actual shape's class, emptiness, coordinate lists, and ordered `toAabbs()` output. Shape definitions are:

- `{"kind":"raw_array_box","box":[six raw-bit strings]}`: a filled `BitSetDiscreteVoxelShape(1,1,1)`, with exact two-element coordinate lists per axis. Input coordinates are already ordered. The grid remains occupied even for equal endpoints. This intentionally avoids `Shapes.box` creation, snapping, or emptiness decisions.
- `{"kind":"empty"}`: `Shapes.empty()`, which has zero occupancy. It is distinct from an occupied degenerate cell.
- `{"kind":"box","box":[...]}`: actual `Shapes.box`; separate construction lane.
- `{"kind":"union","boxes":[...]}`: successive `Shapes.joinUnoptimized(..., BooleanOp.OR)` calls on actual `Shapes.box` results; separate merger lane.

The `raw_substrate` tag identifies single occupied coordinate cells or ordered lists of those cells/explicit empties. These are the independent oracle for an implementation that accepts already-realized ordered AABBs. A union's source boxes, its voxel grid, and its `toAabbs()` decomposition are distinct interfaces. Union/construction cases cannot be counted as an AABB-list substrate comparison without a separate implementation of those rules.

## Observed AABB rules

The six-double constructor applies `Math.min` and `Math.max` independently to each endpoint pair. For the signed-zero input in `aabb_construct:target-2`, every minimum is `8000000000000000` and every maximum is `0000000000000000`. NaN, infinity, signed-zero comparisons, and `Math.min/max` outputs have a separate explicit lane; those observations are tied to the recorded runtime and do not classify nonfinite geometry as valid simulation state.

`move(double,double,double)` adds each delta to both endpoints and constructs a new AABB. `inflate` subtracts the amounts from minima, adds them to maxima, and constructs a new AABB. `deflate` invokes inflation with negated amounts. Consequently, excessive deflation can cross and then renormalize endpoints: deflating the unit cube by 2 returns `[-1,-1,-1,2,2,2]` (`aabb_deflate_scalar:target-0-2`). It does not clamp to an empty box.

`contains(double,double,double)` uses minimum-inclusive, maximum-exclusive comparisons on every axis. `intersects(AABB)` uses strict `min < other.max` and `max > other.min` on every axis, without epsilon or a separate positive-volume precondition. Touching faces do not intersect. A zero-volume box strictly inside the unit cube does intersect (`aabb_intersects:target-0-7`), while its own `contains` checks fail because its minimum equals its maximum.

## Observed axis-clipping rules

The epsilon literal is the Java double `1.0E-7d`, bits `3e7ad7f29abcaf48`. `VoxelShape.collide` cycles the requested axis into `collideX`. A single shape first returns the original movement unchanged if its discrete grid is empty. For a nonempty grid, `Math.abs(delta) < epsilon` returns positive zero. Equality with epsilon does not trigger that gate: disjoint `gate-free-X-4` returns positive zero for the immediate predecessor of epsilon, and `gate-free-X-6` returns epsilon unchanged.

For finite values in an ordered coordinate list, `findIndex(axis,value)` returns the first coordinate strictly greater than `value`, minus one. This follows both the observed boundary fixtures and the actual `Mth.binarySearch` predicate bytecode. For an occupied single cell with obstacle interval `[lo,hi]`, Java's indexing reduces to the following conditions, using actual rounded binary64 sums/subtractions at every expression:

- Both transverse axes must satisfy `moving.min + epsilon < hi` and `moving.max - epsilon >= lo`.
- For positive movement, the candidate cell must satisfy `moving.max - epsilon < lo`. Java computes `gap = lo - moving.max`; if `gap >= -epsilon`, it returns `Math.min(delta,gap)`.
- For negative movement, the candidate cell must satisfy `moving.min + epsilon >= hi`. Java computes `gap = hi - moving.min`; if `gap <= epsilon`, it returns `Math.max(delta,gap)`.

These are one-cell conditions, not a description of the full multi-cell search. `collideX` searches the occupied grid by axis and transverse ranges, returning after the first occupied cell found in that direction. The fixture preserves the grid's realized coordinates and boxes rather than replacing the official algorithm with arithmetic expectations.

For positive request `+2`, a gap of `-epsilon/2` produces the negative result bits `be6ad7f29abcaf48` (`raw_array_box_collide:gap-X-1-3`). For negative request `-2`, an exact positive epsilon gap produces positive epsilon (`gap-X--1-9`); the next larger representable gap returns `-2` unchanged (`gap-X--1-10`). Therefore a sign-preserving clamp would disagree with the pinned implementation.

`Shapes.collide(axis,moving,Iterable,delta)` checks `abs(delta) < epsilon` before each visited shape. An empty list returns the original delta, including `-0.0`. A list containing an explicit empty shape converts a tiny delta or `-0.0` to positive zero because the outer gate executes first. If the last shape produces a nonzero result smaller than epsilon, the iterable returns that value; if another shape remains, the next outer gate returns positive zero. In the ordered X fixtures, `[near]` returns `epsilon/2`, while `[near,far]` returns zero. The list order and explicit empty entries are part of the interface.

## Construction observations and remaining coverage

The construction lane records that `Shapes.box` rejects reversed endpoints with `IllegalArgumentException`; four such calls are intentional. Width strictly below epsilon becomes empty, while width exactly epsilon remains a nonempty raw array shape. Nearby dyadic endpoints can snap into a cube grid: the input `[0.125+epsilon/2, 0.875-epsilon/2]` realizes `[0.125,0.875]`. Near-zero negative minima can also snap to zero. These are measured construction observations, excluded from the raw-box substrate lane.

The oracle does not establish ray tracing, swept AABB queries, shape Boolean-operation parity beyond these observed unions, every coordinate-merger edge case, lazy iterable side effects, entity/world-dependent collision gathering, movement axis priority, step-up resolution, player/entity physics, fluids, or gameplay parity. It executes the triple/scalar numeric AABB methods and the AABB-to-AABB intersection overload; recorded declarations for other overloads are source evidence rather than invocation coverage. Raw collision inputs are finite and ordered. Nonfinite collision coordinates/deltas are not claimed covered. The separate AABB/comparison special-value lane records NaN payloads for this runtime without broadening the finite geometry contract.
