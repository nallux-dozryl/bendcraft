# Resource Player client emission diagnosis: recursive frame and asset boxes

The frozen first resource entry exceeded its single 600-second build limit during
observed Bend C emission. It supplied no completed C, compiler diagnostic or
native artifact. **The dominant cause remains unknown.** Boxing is a concrete
representation experiment, not an established fix or measured speedup.

Confidence is high in the installed compiler's representation rules and the
source-derived word counts below, moderate that narrower presenter captures may
reduce emission work, and unknown for the candidate's build time, allocation cost
and native behavior. No emitter, checker, kernel, build or client was invoked for
this diagnosis. The first entry, scene, runner, preflight, reference and resources
remain unchanged.

## What the installed compiler actually does

The pinned installed executable is SHA-256
`99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`.
Its embedded JavaScript contains the relevant functions; they were read directly
from the Mach-O bytes and retained under ignored
`build/resource-player-client-diagnosis/embedded-functions.full.json`.
No embedded code was executed. The inspected checkout is the unchanged
`../bend` commit `79df8d9c40722ee9507a1e253f283b51025f9d6c`.

In `bend2/comp.ts`:

- `lay_of` (line 938) gives Array, IO.OP, recursive datatypes and a type whose
  fields re-enter it a single `BOX`. Other finite ADTs concatenate their field
  layouts, adding a tag for multiple constructors. An ordinary single-field
  record wrapper therefore does not box its payload.
- `ty_holds` (line 883) traverses type arguments before constructor fields.
  `List<&2,Frame>` or `List<&1,Assets>` exposes the enclosing type to the cycle
  test, even though production values use `Nil{}`.
- `emit_clo` (line 2227) concatenates all live captured values' representation
  words. `seg_open` (line 1529) uses the same concatenation for captured worker
  parameters. A boxed value contributes one word to such a capture.
- `fun_of` (line 1174) can box wide ordinary function arguments when their
  combined width exceeds 247. Closure capture is a different path. The final
  segment arity check is in `compile_book` (line 2824).
- `compile_book` (line 2750) repeats emission until ownership/hot/static facts
  stabilize. `main.ts` writes the `.c` file only after `compile_book` returns.
  The absence of an output file during the timeout does not locate work within
  checking, book construction, fact passes, fusion or string construction.

The CLI exposes C output, ordinary checking and BendTT output; inspection found
no dedicated checked-book IR dump or phase-profiler option. No first-attempt
checked Book or generated native IR survived. The evidence therefore identifies
layout consequences by applying the actual rules to source declarations; it does
not pretend to measure the failed entry's emitted segments or fact-pass count.

## Source-derived layouts and retained baseline

For the finite source records, Nat occupies one `w64`, U32/F32 one `w32`, and
recursive List/Map/String one box. A single-constructor record has no tag.

| Value | Derived native words | Derivation |
| --- | ---: | --- |
| `CR.Snapshot` | 8 | tick + revision + block List + five camera F32 words |
| `V.Sample` | 21 | Snapshot 8 + raw List 1 + masks List 1 + F64 origin 6 + palette 4 + reads 1 |
| `Result<String,V.Sample>` | 22 | tag plus largest payload |
| `CR.Assets` | 1 | its texture List |
| `RF.Assets` | 25 | CR.Assets 1 + bindings List 1 + count 1 + palette 4 + Catalog 18 |
| `RF.Info` | 24 | bindings 1 + count 1 + palette 4 + Catalog 18 |
| `WRF.DrawSource` | 52 | Sample 21 + Info 24 + DrawConfig 7 |
| Recursive `Scene.Frame` | 1 | self-reference through its List tail forces BOX |
| `Result<String,Scene.Frame>` | 2 | tag plus boxed payload |
| Recursive `Scene.Assets` | 1 | self-reference through its affine List tail forces BOX |

Catalog's 18 words are four root/model/sprite collections, Context's nine words,
and five Usage counters. Context contains one sprite Map and the eight-word
Maybe<Sprite>; Sprite has seven words. These are mechanical layout inferences,
not candidate compilation results.

The combined frame/asset contribution falls from **46 words to two**, a reduction
of **44 words per live pair**. Frame alone saves 20; Assets saves 24. This is not
44 words saved in every presenter worker: actual liveness, specialization and
unboxing determine each site's width. Each box still retains its full payload.
The Frame constructor has 22 payload words including its empty tail, and Assets
has 26; allocation size classes may round their storage. This representation
adds heap nodes, indirection and ownership/reference-count work rather than
eliding simulation, visibility or texture contents.

`CP.loop` retains `+frame` after describe/draw through image-ready, Window.frame,
paired image/event continuations and the later capture-policy/input operation
(`src/client_presenter.bend:166–186`). Assets likewise travel through draw,
image presentation, input, scheduling and closing. Narrowing these two generic
values addresses those surrounding continuations while leaving the actual
visibility and renderer kernels intact.

The earlier accepted plain Player client C was inspected without recompiling.
Its SHA-256 is
`c2cd3816316e902b73e715458f309968680383482fbb0ece1cac406be0e2730a`.
Its 17,075,035 bytes contain 4,219 worker-table entries; maximum arity is 209.
The presenter has 219 entries; the loop family has 131 and maximum arity 128.
These are actual `FID_T` table measurements from that different accepted entry.
They do not establish the resource entry's arity or predict whether it would hit
247. V.Sample's own width of 21 is below 247.

The first resource closure has 98 dependencies versus the prior client's 85:
13 additions and no changed or removed common dependencies. The additions
include block model/bake/resources, exact float parsing/big integers, resource
JSON/frame, mesh/world mesh/visibility/resource frame and the new entry/scene.
That larger work graph is another plausible source of cost. Boxing the presenter
values leaves those algorithms and WRF.DrawSource's internal flattening in place;
it cannot be assumed to remove the dominant work.

## Minimal new generation proposed by the root

Preserve the first generation and its timeout receipt. The root has created
new `src/resource_player_boxed_scene.bend` and
`resource_player_boxed_client.bend`, with an independently sealed runner/build
path for the later approved experiment. The only production surface changes are
new wrappers and adapters in those new files. CP, WRF, RF, Runtime, Session and
all prior client/visible artifacts remain unchanged.

The intended recursive types are:

```bend
type Frame is Data:
  Frame{sample:V.Sample,tail:List<&2,Frame>}
type Assets is Type:
  Assets{resources:RF.Assets,tail:List<&1,Assets>}
```

Canonical constructors use empty tails. Frame stays duplicable Data; the assets
wrapper remains affine Type and preserves the sole RF.Assets owner. A
nonrecursive wrapper would flatten again and would not test this hypothesis.

The versioned scene should expose `CP.Driver<S.State,Frame>` and
`CP.Renderer<Frame,Assets>`:

1. Successful world snapshot wraps the unchanged V.Sample into a canonical
   Frame before it leaves the snapshot query. Failure errors and complete actor
   state are retained. The invalid-frame rollback law changes its result type
   and keeps the same real failing branch. A pure wrap/unwrap law can establish
   only exact Sample projection, not renderer or Minecraft parity.
2. Describe/capture adapters project the sample and retain the identical frame
   JSON and policy. Capture policy remains the finite instrument's existing
   policy for canonical Frames, with actual capture still checked by CP.
3. Draw first checks the Frame tail and then destructs the affine Assets wrapper
   once to check its tail. A nonempty tail rejects. Every rejected branch returns
   the **complete original Assets owner**, including nested tails, without
   invoking F.draw or closing resources. It must not reconstruct only the root
   RF.Assets and discard the other owners.
4. The canonical branch passes exactly its sample and sole RF.Assets to F.draw,
   then rewraps exactly the RF.Assets returned by that real function with an
   empty tail. Width/height, actual Image, error text and owner sequencing stay
   unchanged. No foreign cast or unsafe ownership escape is required.
5. Close destructs each Assets node, calls RF.close_assets on its RF owner, and
   structurally traverses the entire `List<&1,Assets>` tree. Noncanonical
   values therefore still close every nested owner. Mutual structural traversal
   must pass the real checker/termination rules; do not add unsafe recursion to
   avoid that obligation.
6. The new entry continues to use RF.load, wraps each successful returned owner
   once, and instantiates Presenter.open with `Scene.Frame` and `Scene.Assets`.
   Loading failures preserve the existing lease-release path. Server, timer,
   persistence, CLI, launch policy and callback semantics remain identical.

Read-only review of the new root-owned adapters found these branches present:
`draw` rejects a Frame tail with `ResourceScene:FrameTail`, `draw_assets` returns
the entire reconstructed owner on `ResourceScene:AssetsTail`, and `drawn` wraps
exactly the returned RF owner. `close_all` traverses nested tails and remaining
siblings directly, calling RF.close_assets for each node; it avoids mutual
recursion. Capture policy is canonical-tail admission, so canonical frames keep
the previous True result. The new entry wraps RF.load's Done owner and changes
only the presenter Frame/Assets parameters and Scene import. This is source
review, not native cleanup verification. Root reports ordinary 92/79 inherited
boundary-only results for its separately sealed 99-dependency generation.

Pure validation coverage should include canonical and noncanonical tails and
real draw-adapter failure retaining the whole asset value. Native cleanup tests
must actually own and consume multiple nested assets; a type-check or an
empty-tail-only exit cannot establish that behavior. Behavioral failure
comparison and full existing hidden integration remain required.

## Bounded later verification plan

No compiler or client invocation was made for this diagnosis. The later root-
granted boxed build is recorded separately in `resource-player-boxed-client-*`
receipts and does not replace the first timeout. Its verification obligations are:

- Seal its new entry/scene/runner and unchanged dependency/resource closure;
  retain the first generation's pins, timeout and raw receipt.
- Ordinary-check the actual new adapter signatures, affine invalid-tail
  rollback and structural close before asking for a native slot. Preserve
  inherited foreign/unsafe boundary diagnostics without declaring a proof pass.
- Use one guarded platform-cache build with the same 600-second process-group
  cap, route, flags and source/SDK/C/transform/artifact checks. Stop on its first
  failure, preserving raw receipts. Do not weaken any hidden test or timeout.
- If emission succeeds, count native words/worker arities/C size in the actual
  emitted generation and record phase timings. The first attempt only gives a
  lower bound of 600 seconds to a completed build, not an exact baseline time.
- Execute all preserved hidden resource/TCP/MCP/Java/queue/save/restart/cadence/
  zero-frame/failure/recovery lanes against the returned immutable artifact.
  No visible UI/input/permission/screenshot work follows from this experiment.

A successful build would show that the new representation fits this budget; it
would not prove boxing was the unique timeout cause, establish a repeatable
compiler speedup, or measure gameplay speed. Runtime allocation/frame/timer
observations must be reported separately.

Evidence is `evidence/resource-player-client-diagnosis-frame-boxing.json`.
Extracted installed functions, retained-baseline segment counts, source-closure
comparison and layout arithmetic stay under ignored
`build/resource-player-client-diagnosis/`. This work changes documentation and
new diagnosis evidence only.
