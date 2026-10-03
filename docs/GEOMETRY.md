# Exact AABB and occupied box collision substrate

Confidence: **high for the recorded pinned Java 26.3 fixtures**. This module is an exact box substrate; complete voxel shape construction/merging and player motion remain unimplemented here. Formal laws and Java behavior observations are separate evidence.

`src/geometry.bend` imports the pure binary64 implementation in `src/f64.bend`. Every coordinate, displacement, gap, and epsilon arithmetic result retains a `F.F64{hi: U32, lo: U32}` payload. There is no F32 conversion, fixed-point approximation, foreign arithmetic, compiler change, or host collision implementation.

## API and ownership

```bend
import ./geometry.bend as G
import ./f64.bend as F

type AABB is Data:
  AABB{min_x: F.F64, min_y: F.F64, min_z: F.F64,
       max_x: F.F64, max_y: F.F64, max_z: F.F64}

type Axis is Data:
  AxisX{}
  AxisY{}
  AxisZ{}

type Collider is Data:
  EmptyCollider{}
  BoxCollider{box: AABB}
```

All boxes, axes, and colliders are immutable Data. Functions consume their arguments according to their signatures; explicit `+` parameters permit reuse of immutable data. No function accepts, duplicates, or replaces a world or section array owner. Axis arithmetic uses the F64 public operations directly; clipping structurally traverses its input list and stops at Java's early-zero gate.

| Function | Result | Behavior |
| --- | --- | --- |
| `AABB.new(x1,y1,z1,x2,y2,z2)` | `AABB` | Java `Math.min` / `Math.max` endpoint normalization, including `-0` for a zero minimum and `+0` for a mixed-zero maximum. |
| `AABB.move(box,x,y,z)` | `AABB` | Adds each displacement to both endpoints, then calls normalized construction. |
| `AABB.inflate(box,x,y,z)` | `AABB` | Subtracts from each minimum and adds to each maximum, then normalizes. |
| `AABB.deflate(box,x,y,z)` | `AABB` | Inflates with bitwise-negated displacements. Over-deflation can cross endpoints and produce another nonempty normalized box. |
| `AABB.intersects(a,b)` | `Bool` | Strict endpoint comparisons on all three axes, without an epsilon or separate zero-volume rejection. |
| `AABB.contains(box,x,y,z)` | `Bool` | Minimum inclusive, maximum exclusive on each axis. |
| `AABB.axis(box,axis)` | `F.F64 & F.F64` | Returns the selected endpoints. |
| `clip_box(axis,moving,obstacle,delta)` | `F.F64` | Direct collision against one occupied raw-coordinate `ArrayVoxelShape` cell. |
| `clip(axis,moving,boxes,delta)` | `F.F64` | Java ordered iterable clipping, with each `List<&2,AABB>` element treated as one occupied cell. |
| `clip_collider(axis,moving,collider,delta)` | `F.F64` | Direct empty/nonempty shape call; an explicit empty collider preserves the input bits. |
| `clip_colliders(axis,moving,colliders,delta)` | `F.F64` | Ordered `List<&2,Collider>` iterable, preserving explicit empty entries and outer epsilon checks. |
| `AABB.checked_new(...)` | `Result<&2,&2,Error,AABB>` | Rejects nonfinite original constructor arguments in argument order. |
| `AABB.invalid_field(box)` | `Maybe<&2,U32>` | First nonfinite stored endpoint, field order minimum XYZ then maximum XYZ. |
| `clip_checked(axis,moving,boxes,delta)` | `Result<&2,&2,Error,F.F64>` | Validates moving endpoints, then delta, then all obstacle endpoints before clipping. |

The public raw `AABB{...}` constructor does not enforce normalized or finite coordinates. Use `AABB.new` for moving/query boxes. For occupied cell obstacles, use the already-realized, numerically nondecreasing coordinate endpoints; preserve their exact bits. Calling `AABB.new` on those obstacle coordinates can change mixed signed-zero endpoint order. This representation does not construct a voxel shape and does not infer whether a cell is empty from its extent. `BoxCollider` means occupied even when its endpoints are degenerate; `EmptyCollider` represents explicit zero occupancy.

Checked errors are `NonFiniteCoordinate{field}`, `NonFiniteMoving{field}`, `NonFiniteObstacle{index,field}`, and `NonFiniteDelta`. Zero-based field indices run from 0 to 5; obstacle indices follow input order. Checked rejection is an explicit simulation validation policy. Java's AABB constructor accepts nonfinite values. Raw AABB methods preserve the F64 module's documented arithmetic NaN policy; only the nonfinite observations actually present in the fixture corpus establish Java payload agreement.

## Collision rules and scope

The collision epsilon is the Java literal `1.0E-7`, raw bits `0x3e7ad7f29abcaf48`. Direct nonempty collision returns positive zero when `abs(delta) < epsilon`. An empty direct collider preserves tiny delta and negative zero. Ordered iterable collision checks that threshold before each element: an empty list preserves delta, while a list containing an empty collider can return positive zero. Early zero stops traversal.

For each transverse axis, an occupied cell participates when both comparisons hold:

```text
moving.min + epsilon < obstacle.max
moving.max - epsilon >= obstacle.min
```

For positive movement, the cell is a candidate if `moving.max - epsilon < obstacle.min`. Its gap is `obstacle.min - moving.max`; a gap at least `-epsilon` clips with Java `Math.min(delta,gap)`. For negative movement, a candidate satisfies `moving.min + epsilon >= obstacle.max`; its gap is `obstacle.max - moving.min`, and a gap at most `epsilon` clips with `Math.max(delta,gap)`. These predicates retain the individual rounded arithmetic operations from Java's `VoxelShape.collideX` and its strict `findIndex` search. Algebraic rearrangement would change boundary results. A tolerated penetration can produce a clipped delta of the opposite sign, exactly as the Java method does.

The contract covers an ordered collection of independent, occupied one-cell `ArrayVoxelShape` boxes with exact realized coordinates. It does not implement `Shapes.box` dyadic snapping, its empty-shape policy, `Shapes.create`, unions, index mergers, multi-cell shape searches, or a player movement integrator. Flattening a merged shape into an arbitrary box sequence is not asserted equivalent. The oracle's construction and union lanes remain explicitly excluded.

## Verification

Reproduce the independent Java fixtures with the reference owner's extractor and validator described in [GEOMETRY_REFERENCE.md](GEOMETRY_REFERENCE.md), then run:

```sh
python3 tools/test_geometry.py
```

The extractor calls the actual pinned server classes and stores each input/output double as sixteen raw hexadecimal digits. The Bend test executable parses only the test transport, calls the production Bend methods, and emits the observed word pairs. Python encodes requests, compares raw outputs, checks explicit validation errors, and records evidence; it does not calculate a collision result at runtime.

`reference/geometry.json` contains 4,522 independent Java observations. The supported lanes cover AABB construction, movement, inflation/deflation (vector and scalar), containment, intersection, raw occupied cells, explicit empty shapes, and ordered raw-cell lists. Cases include signed zeros, touching faces, minimum/maximum containment boundaries, reversed constructor arguments, degenerate AABBs and occupied cells, over-deflation, underflow/overflow neighborhoods, random finite coordinate inputs, exact epsilon and adjacent representable values, negative-origin gaps, order-dependent early zero, and transverse overlaps. Separate Java comparison, coordinate-search, shape creation, and union observations document dependencies or unimplemented behavior.

`evidence/geometry-verification.json` records the exact supported case counts, fixture and source hashes, commands, native CPU execution, explicit validation checks, excluded lanes, and independent kernel results. It is the authority for current verification counts and status.

Seven implementation laws live beside the implementation: an empty box list and a direct empty collider each preserve any delta payload; a nonempty iterable and a direct occupied cell each return positive zero for a tiny delta; a disjoint transverse projection preserves a non-tiny delta; mixed signed-zero construction produces the stated endpoints; and checked construction rejects a nonfinite first coordinate before inspecting later coordinates. Both the compiler and the independent BendTT kernel check these laws. They are not a theorem of all IEEE geometry or Java equivalence.

## Compiler behavior

The initial test dispatcher matched operation strings together with box and field patterns; the pinned compiler expanded these overlapping patterns into approximately 42–46 MB of C. Parsing the operation once into a test-only typed enum reduced emission to approximately 1 MB. The production geometry retains direct scalar F64 calls; attempts to change numeric traversal did not resolve that test pattern expansion and were removed. Final C size, build time, and emitted-code inspection are recorded in the evidence. No compiler or runtime change was required. No Minecraft performance claim follows from this implementation milestone.
