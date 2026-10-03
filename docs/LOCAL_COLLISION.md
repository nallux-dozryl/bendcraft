# Local collision hooks — Java 26.3

The new pure module implements the observed LocalPlayer minor-collision
arithmetic and Player sneak edge-backoff query flow. Production and the narrow
harness pass ordinary type/termination checking and the independent BendTT
kernel. Native results match the direct actual Java fixtures within the checked
admission boundary. Confidence is high within that boundary, with exact query
order and raw finite/signed-zero numerical outputs checked independently.
These hooks do not establish a complete Entity.move or LocalPlayer tick.

## Checked contracts

`minor_checked(Tables, Body, MinorInput, resolved, Mode)` returns the sole
Tables owner and a checked `MinorObservation`. `MinorInput` contains current
Java F32 degree yaw and current prepared xxa/zza. `resolved` is the actual
collision-resolved displacement. Entity.move invokes the minor hook only when
horizontalCollision is true, after its support update; the caller must keep
that production gate and phase order. Body is authoritative admission data and
does not contribute position or velocity to the angle calculation.

The result contains the Bool, rotated X/Z, input and movement squared lengths,
and an optional `AngleDetails {dot, ratio, angle}`. The optional value is absent
when either squared length is below the exact widened `1e-5f` threshold. An
intermediate overflow or ratio outside [-1,1] follows the actual arithmetic
and produces the actual false final angle comparison. All initial yaw/input/
displacement fields must be finite; unsupported contexts reject before reading
the sine table. Tables are returned on every failure.

`edge_begin_checked(Body, requested, EdgeContext)` returns a checked
`EdgeProgress`:

```text
EdgeDone {movement: Movement.Vec3}
EdgeQuery {box: Geometry.AABB, continuation: Continuation}
```

`EdgeContext` holds actual resolved `maximum: F32`, `fall_distance: F64`,
`flying: Bool`, current sampled `PlayerInput.Buttons`, mover kind, and admission
mode. The Body's actual grounded flag and fall-distance history drive the
above-ground predicate. The actual helpers do not inspect the cached supporting
block; that cache remains recorded in the reference receiver histories. It
must not be substituted for onGround/fallDistance. A world adapter must resolve
fallDistance faithfully before admitting airborne edge backoff.

For each `EdgeQuery`, the caller runs the actual admitted
`noCollision(entity, box)` query and passes its checked Bool/error to
`edge_answer_checked(progress, answer)`. That advances exactly one production
query. The world adapter retains its sole owned world across reads. Actual
noCollision includes block, entity and world-border policies; a block-only
answer is admissible only when the entity/border context has separately been
established. Unknown shapes, incomplete query ranges and unavailable context
must reject, never become a default clear answer.

`backoff_checked(Owner, owner, fuel, observations, Body, requested, context)`
provides an owner-retaining bounded replay for callers with a complete finite
ordered observation set. Each `QueryObservation` has exact raw AABB words and
a checked Bool/error. It rejects mismatched boxes, missing observations, extra
observations, denied queries and exhausted query fuel. Fuel is explicit caller
policy; it counts noCollision observations, including the above-ground probe.
Exhaustion is an admission limitation, not a different Java movement result.
An adapter can instead drive begin/answer directly with a closed typed
`~Driver` template and its sole world owner. The module mutates no Body or world.

Modes admit `NeutralDry` only. Flight, swimming, passengers, noPhysics,
nonneutral effects and unsupported worlds reject. Flying abilities and movers
other than SELF/PLAYER reject. Initial Body/displacement/step/fall fields are
validated before probes. Step must be finite and nonnegative; fallDistance must
be finite. The direct reference includes explicitly labelled guard/nonfinite
cases beyond checked hook admission. Its slab cases use actual supplied query
answers; they do not establish slab admission in the current full-cube world
adapter.

## Exact operations and phase order

Minor collision computes the F32 yaw multiplication by `.017453292f`, widens
the result, reads the actual pinned Mth sine/cosine table, and widens its F32
values. It separately rounds the F64 products, rotated sums/subtraction,
squared lengths, dot product, norm product, square root, division and acos.
The angle comparison is strictly below `0.13962633907794952d`. The norm guard
uses `9.999999747378752e-6d`, the exact widening of `1e-5f`. Displacement Y has
no numerical contribution, though the checked facade requires it finite.

The acos implementation uses pinned OpenJDK25 FdLibm.Acos coefficient words,
branches and separately rounded operations. The primary source was fetched from
[OpenJDK jdk-25+36](https://github.com/openjdk/jdk/blob/jdk-25%2B36/src/java.base/share/classes/java/lang/FdLibm.java)
and its SHA-256 is `2b67c20cbbe16ed18294a0c58051374ef409ecac4392170b6b2b258e682f8c0f`.
`evidence/local-collision-primary-source.json` records retrieval provenance;
the source itself stays under ignored build storage. Actual installed
StrictMath.acos bytecode calls FdLibm.Acos.compute. All 3,072 recorded actual
Math.acos and StrictMath.acos outputs are bit-identical. This measured pinned
behavior is distinct from a universal correctly-rounded acos claim. No cosine
threshold shortcut, host trig, renderer trig, or native gameplay code is used.

Edge backoff is called before Entity.collide, following the stuck-speed phase.
It reads maxUpStep before its guards, then checks flying, requested Y, mover,
actual current shift and isAboveGround. Above-ground is onGround or the actual
fallDistance/step predicate and one supporting noCollision probe. Its exact
query box is:

```text
minX = (body.minX + 1e-7d) + dx
minY = (body.minY - drop) - 1e-7d
minZ = (body.minZ + 1e-7d) + dz
maxX = (body.maxX - 1e-7d) + dx
maxY = body.minY
maxZ = (body.maxZ - 1e-7d) + dz
```

The actual AABB constructor normalizes endpoints. The state machine preserves
that constructor and every arithmetic node. It queries X-only, then Z-only,
then both, computing each signed `.05d` decrement once from the original
horizontal component. Each probe occurs before the abs<=.05 termination test;
combined shrink updates X and then Z. A shrunk tiny nonzero value becomes
positive zero. An original numerical zero, including negative zero, skips its
axis probes and retains its payload. Returned Y always retains original bits.

## Direct reference and numeric audit

`tools/reference_local_collision_probe.py` calls the untouched protected methods
on normally constructed actual LocalPlayer receivers. It reuses the four
explicit external service substitutes and real finite ClientLevel fixture from
LocalInput without editing those templates. The world is 25 real stone states
at x,z=-2..2/y=0, otherwise air, with labelled real air/slab writes. Plain
receivers and super-calling observers agree. The Level observer calls actual
super noCollision and wraps the original BlockCollisions iterator to record
only shapes actually yielded, preserving short-circuit behavior and order.

The frozen corpus contains 3,072 acos cases, 337 direct minor cases and 99
direct backoff cases, with 719 actual noCollision traces. Receiver projected
state is unchanged by every helper call. Independent execution reproduced all
results, query traces, official loaded classes and JRT math class bytes.
Five injected provenance/source/observation mutations were rejected.

Three duplicate actual/debug/independent reports are stored as hash-linked
tracked summaries totaling 48,250 bytes, reduced from 12,725,468 bytes. Complete
raw reports remain under ignored `build/local-collision-reference/`; the fresh
independent report also retains complete stdout/stderr and the full official
class tree. Reference bytes, observation hashes, receiver source, corpus and
launcher are unchanged. A fresh actual rerun and all five integrity injections
passed after the storage change. See
`evidence/local-collision-reference-storage.json`. Final producer SHA-256 is
`657a97c9c459ff8dc294710f306aab48a93cdfa9bb530ff72e911b43773bbd6b`;
reference SHA-256 is
`549a49a0e1b8cfb8e9790023cabb718e1d8f8c2e9ebdd2bb6be57603a93eb1da`.

The decisive minor Bool and backoff Vec3 come only from direct production
calls. Supplemental rotated/squared/dot/ratio/angle observations are explicitly
labelled numeric instrumentation, not captured production locals or synthesized
gameplay expectations. A separate exact integer/Fraction audit checks 334 F32
multiplies, 5,294 F64 add/sub/mul nodes, 296 divisions and 296 integer-square-root
rounding results against that instrumentation. Its arithmetic decodes dyadic
payloads with integers and explicitly rounds ties to even. Overflow cases are
kept in the Java/native corpus and are not mislabeled finite rational checks.

The successful native comparisons cover 3,072 acos cases, 334 admitted minor
cases, 94 admitted backoff cases with 705 exact query boxes/order checks, and eight
explicitly measured admission failures. Fourteen of the 719 actual query
observations belong to the helper-only NaN-Y backoff case, which the checked
facade rejects before probing; they are retained as reference observations.
Twenty-five additional error-policy cases check unsupported modes, fields,
missing/mismatched/denied/extra observations and query budgets. Each failure is
followed by a valid minor call using the retained real Tables owner in the same
process, for 33 owner-retention followups. Five malformed protocol requests
also reject. NaNs compare class only; finite values, infinities and signed zeros
compare exact bits. Java's Vec3 object identity is recorded in the reference
but is not equated with immutable Bend value identity.

Five quantified production laws cover rejected minor owner retention, skipped
edge payload retention, zero query budget, mismatched-query rejection, and
original negative-zero horizontal movement preserving payloads without probes.
All five laws and the complete imported source closure passed the independent
kernel with `ALL PROOFS CHECK` in 3.937278 seconds. The unchanged native build
completed in 2.510009 seconds; the complete native comparisons took 2.011975
seconds. These are verification tool timings, not gameplay benchmarks. Both
bounded processes finished before the first five-second memory sample.

The final receipts are `evidence/local-collision-build-final.json`,
`evidence/local-collision-kernel-final.json`, and
`evidence/local-collision-verification.json`. The final verification receipt
seals the existing successful native comparisons with the completed exact-source
build/kernel receipts; it does not rebuild or repeat the successful corpus.
Production source SHA-256 is
`7b2b8301246f3e385a038eca81790fa7d6c4285113a069e040d968e105be5cc0`,
harness SHA-256 is
`8e70d5c234c11663d6c91ac5634fa0a454c477955b9c55430a91c9d4822c11bf`,
and native driver SHA-256 is
`6bb9e93b6e45a6447c1f0886eceb7804b2035042066c8aacbaa2e8a9d6e32680`.
The successful 1,337,432-byte executable SHA-256 is
`e986059eb044ea6a698e0aa3026c111722f441c64101038f9d7d7530dbed234e`.

`evidence/local-collision-native-closure.json` pins the discovered Bend graph,
actual installed Base/native effect bodies, compiler executable, relevant
Python tools, table and reference. It records one separately regenerated C
file from the same frozen source generation, emitted in 1.045764 seconds after
verification. That 1,016,454-byte file has SHA-256
`744f150dfe71d51b30762db175062371f335d9c8ae1f15a2532aa631f7cb7e46`.
It is explicitly not the original native compile's temporary C, which Bend
removed. The successful executable was unchanged before/after this emission;
no executable rebuild occurred. The native system-library ABI and OS build are
recorded separately because macOS resolves libSystem from its dyld shared cache.

Reproduce direct observations with
`python3 tools/reference_local_collision_probe.py --rerun`; run integrity
mutations with `--selftest`. Prepare mapping and numeric audit without compiling
with `python3 tools/test_local_collision.py --prepare-only`. Full checks use
`python3 tools/test_local_collision.py`; completed builds/kernel checks can be
reused only with exact hash verification through
`--skip-build --skip-checks --reuse-checked`.
