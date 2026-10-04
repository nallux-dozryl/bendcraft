# Resource client compiler diagnosis after both timeouts

The dominant cause is **unknown**. Both sealed resource generations exceeded a
600-second process-group limit inside the Bend invocation and produced no C or
native artifact. Boxing Frame and Assets did not make the second build complete
within that limit. These are censored observations, so they establish neither an
exact slowdown nor a boxing speedup. No third emission, checker, kernel, native
build or client launch was performed for this diagnosis. The later granted Node
graph-control attempt failed during loading, before checking or native analysis.

Confidence is high in the directly inspected compiler mechanisms and accepted C
measurements, moderate in the hypothesis below, and unknown in the dominant
phase of either failed invocation. All prior entry/scene/helper/preflight/seal
and resource pins pass the existing read-only audits unchanged.

## Observations and the missing measurement

| Generation | Source closure | Existing ordinary entry check | Native observation |
| --- | ---: | --- | --- |
| Accepted plain PlayerClient | 85 dependencies | previously accepted | Bend C CLI 51.778994 s; guarded native build 58.913358 s |
| First resource client | 98: 63 Bend, 34 native effects, Base | 14.454548 s; 92 inherited boundary refusals | timeout 600.082812 s; no C |
| Boxed resource client | 99: 64 Bend, 34 native effects, Base | 17.901897 s; 92 inherited boundary refusals | timeout 600.065755 s; no C |

The ordinary checks are prior sealed runs, not fresh profiling in this diagnosis.
They show that these sources previously completed ordinary checking; they do
not time checking inside the timed-out native invocations. Common dependencies
between the accepted plain entry and the first resource entry have no changed
hashes. The resource graph adds model/bake/resource loading, exact float parsing
and big integers, resource JSON/frame, visibility, world mesh, mesh rendering,
and the new entry/scene. The accepted Bend C CLI phase includes its
loading/checking/backend work; it is not an isolated compile_book timing.

The accepted original C is SHA-256
`c2cd3816316e902b73e715458f309968680383482fbb0ece1cac406be0e2730a`,
17,075,035 bytes. Its actual `FID_T[][3]` table has 4,219 entries and maximum
worker arity 209. Mapping the table through the actual `FID_*` definitions gives:

| Family | Workers | Maximum arity |
| --- | ---: | ---: |
| Server actor | 42 | 138 |
| Server local-call helpers | 13 | 4 |
| Client presenter | 219 | 128 |
| Player scene | 22 | 128 |
| Player session | 35 | 138 |
| Player runtime | 33 | 191 |

The accepted C has no WorldResourceFrame, ResourceFrame or MeshRender worker
families. Neither failed resource invocation supplied a worker table, so their
segment counts and arities remain unmeasured. The boxed emitter's one authorized
OS sample reported physical footprint and peak as literal `17.0G`; its main
thread frames were not symbolized to compiler source functions. That sample
does not identify a layout, allocation, garbage-collection or emission cause.

## What persists after outer boxing

All three entries start the same `Server.actor` specialization with
`Session.State` and the same `player_scene.realtime_step`/`dispatch` callbacks.
The plain entry calls those callbacks through its Scene alias; resource entries
call them through their Player alias. The loader resolves aliases to canonical
real-file namespaces and loads each real file once (`bend.ts:952`). There is no
source evidence that the actor's concrete State grew in the resource entries.

`CP.Driver` specializes snapshot/input/capture callbacks, and `CP.Renderer`
specializes draw/describe/close callbacks. `CP.loop` sends a local snapshot query
closure through `S.local_call`, then retains the frame in the draw/image/window/
event/input continuations. `S.local_call` captures the reply channel and query;
its Local operation receives the sole actor-owned State at execution. It does
not copy that State into the posted operation. The native C `Env` is a separate
runtime structure containing memory/allocation pointers; it is not the language
closure environment or the Minecraft Session.State.

Recursive Scene.Frame/Assets change outer representation but leave all resource
algorithms reachable. The boxed draw adapter unwraps into the same WRF.draw.
Inside WRF, `DrawSource{sample,info,config}` remains a finite record, and RF.info
returns retained RF.Assets together with duplicable RF.Info/catalog metadata.
The source-derived 52-word DrawSource and its shared immutable metadata remain
present in both resource generations. This fact does not establish excessive
arity or a performance defect. Further boxing that record without measuring the
backend would be another representation guess.

Template instantiation is memoized by the closed arguments' syntax in
`book.tmps`, and checked instances are placed in `book.tlds` outside `book.order`
(`bend.ts:3729`). Counting only import files or `book.order` would miss this
specialization graph. Outer boxing does not inherently remove its instances.
Actual instance counts for the failed Books have not been retained or measured.

## Falsifiable bottleneck hypothesis

The resource callbacks expose a larger checked term graph whose shared bodies
are repeatedly traversed or fused during native dependency analysis and
ownership/sharing emission. Outer boxing narrows captures but does not remove
those bodies. This is the leading bounded hypothesis, not an established cause.

Direct reading of the installed executable's embedded backend and unchanged
79df source supports the following mechanisms:

- `file_book` discovers the native reachable graph using `term_any`,
  `term_spine`, `fun_of` and datatype reachability. It counts reference sites and
  records dependencies for flat definitions (`comp.ts:1310`). The recursive
  term traversal is distinct from the real-file import de-duplication.
- `memo_gc` clears six term memo maps per visited definition and again before
  emitting each definition (`comp.ts:1838`, `1359`, `2768`). This permits repeated
  work across definitions; its actual cost has not been measured.
- `emit_fuse` recursively emits a non-flat callee body into the caller segment.
  `emit_body` selects fusion for eligible flat calls or single-site tail calls
  (`comp.ts:2126`, `2450`). A closure boundary or a recursive value box is not a
  universal source-body specialization barrier.
- `compile_book` emits every reachable definition, closes lending facts, and
  repeats until ownership/hot/static fact counts stop changing. It clears the
  spin/emission collections on each pass (`comp.ts:2750`). A large graph can
  therefore be emitted repeatedly. No fact-pass count was captured in either
  failed invocation.
- `main.ts:358` writes C only after `compile_book` returns. Missing C does not
  distinguish loading/checking, file_book, a fact pass, final graph filtering or
  C-string assembly. No Clang process was observed for either failed attempt.

A slow native `file_book` traversal would support the first branch of this
hypothesis. A quick native graph with disproportionate template/site counts
would motivate measuring fusion/fact passes. A small quick graph would weaken
the specialization explanation and shift the next question to an individual
emitted body, final assembly, or engine allocation behavior. None of these
outcomes is presently known.

## Granted graph-only experiment and stopped control

Request a **graph-only diagnostic**, one process at a time, with a 90-second
whole-process-group cap per entry: accepted `player_client.bend`, then frozen
`resource_player_boxed_client.bend`. Stop if the control fails. The first unboxed
entry is unnecessary for this first discrimination. No compile_book, C output,
Clang, kernel, platform build, client or UI is part of this experiment.

Use an ignored copy of the pinned `bend.ts` and `comp.ts`, never edit ../bend or
the installed executable. The prepared copies were extracted directly with
`git show 79df8d9c40722ee9507a1e253f283b51025f9d6c:bend2/<file>`; they are not
copies of an assumed matching working tree. The git bytes happen to match the
current clean working files. Their SHA-256 values are bend.ts `7deae369…`,
comp.ts `32fb66e0…` and main.ts `d1a3e026…` (full values in the receipt).
Preserve original bytes and a complete minimal patch.
The patch only appends a diagnostic export using compile_book's exact native
root construction (`show_main`, runtime ADTs, printer families, `js=false`) and
adds bounded start/end counters inside file_book. The harness repeats main's
`book_nil -> book_load -> book_valid -> holes==0` preparation. It must use the
original entry paths, canonical namespaces and **installed** Base: a copied
module's BEND_DIR otherwise resolves a different Base location. Symlink the
scratch Base to the pinned installed Base and verify its resolved identity and
every load/native-effect lookup against the sealed manifests. No hub fetch or
missing dependency is permitted.

Static parsing compared a conservative 193-function helper closure rooted at
main.book_read, bend.book_nil/load/valid and comp.show_main/file_book against the
installed embedded functions. Acorn from the pinned Node executable parsed the
functions as data; no compiler function ran. After explicit namespace/bundle
name and literal-spelling normalization, 184 ASTs match. Nine syntactic
mismatches remain visible in the ignored report:

- Scoped variable renames in name_show, parse_body, parse_book, parse_term_ops,
  term_show, lay_of, show_main and term_spine. Their statements/operators and
  values otherwise match under the corresponding local rename.
- term_check's nested term_check_mat_goal declaration is hoisted in the bundle
  into a let initialized with the same function body before the surrounding
  const declarations. Its recursive references and later call are retained.

These are source/bundle syntactic differences, not claimed theorem-level
equivalence. No behavioral body change was identified. Native compile_book's
first three statements (root construction), RUNTIME_ADTS, OWNED, WORDS, WIDE
and OPTIMIZED all have matching normalized ASTs. File_book and the loader/check
entry helpers themselves match. The comparison explicitly distinguishes Bend's
term_force/strip/tele_unbind from Comp's private helpers renamed with `2` by the
bundle; it does not accidentally compare those different functions.

The inert files are `source-79df/comp-probe.ts`, `source-79df/probe.ts`,
`probe.patch`, `probe-pins.full.json` and `run_graph_probe.py` beneath the ignored
diagnosis directory. The patched copy counts term_any calls and reference/call
edges, logs each native definition, and appends the native-graph-only export.
It never calls compile_book, emit_body or effect_srcs. Original git files remain
byte-for-byte intact. The wrapper pins its own bytes, the copies/patch/harness,
Node/Bend/Base, manifests, prior runners/preflights/seals, refuses existing
attempt receipts and stops before boxed on any control failure. Default mode
only prints the plan. The exact proposed execution command is:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-next/run_graph_probe.py --root-graph-slot-granted
```

Root granted that exact runner once after its final 20-pin self-check. Each
actual child argv is the pinned absolute
Node path, `--experimental-strip-types`, the absolute probe.ts path, the original
absolute entry, and its sealed manifest. NODE_OPTIONS/NODE_PATH are removed and
their names recorded, preventing unsealed Node startup injection. The wrapper
enforces the 90-second/8-MiB bounds externally, sends group SIGTERM then SIGKILL
after a two-second grace, and records partial output/digests and genuine exit.

The accepted plain control process/group **30628** exited 1 after
**1.161467416 s** with `RangeError: Maximum call stack size exceeded` in
`term_higher` (`bend.ts:718`, repeated recursive frames at 703/762). Its only
stdout event was `load.start`. No check, native file_book, layouts, template
instance counts or graph summary was reached. Stdout is 172 bytes and stderr
1,805 bytes; both are retained with hashes. Neither timeout nor the output cap
triggered. The boxed process was never started. No code/flags/algorithms were
changed and no retry was made after this refusal.

This establishes that the current Node configuration cannot load the successful
control for this diagnostic. It does not locate the installed compiler's native
timeout, measure its graph, or disprove the stated graph/fusion hypothesis. The
primary question remains unknown. Source procedure matching does not eliminate
JavaScript runtime stack limits. A differently configured or independently pinned
Bun diagnostic would need separate review; it is not adopted by this receipt.

All 20 preparation pins plus the 85/99 source/native/Base manifest contents
were rehashed after the failure. The process group has no remaining processes,
the wrapper has completed, and slot A was explicitly released. Raw attempt and
post-audit receipts are `plain-graph-result.full.json` and
`post-graph-audit.full.json` under the ignored diagnosis directory.

Node v23.5.0 is available and its local help declares
`--experimental-strip-types`; Bun is absent from the current PATH. The two
source modules were imported only in the granted control attempt described
below. On import/load/control failure, preserve the refusal and stop; do not
rewrite algorithms or silently install a runtime.
Use a shell-independent subprocess argv with that explicit flag and record the
resolved Node executable hash. Source-copy execution is a **Node diagnostic of
the inspected source**, not the installed Bun executable, so its times cannot
be presented as installed compiler phase times or a speedup. Equality of the
source procedures is necessary but does not equal JavaScript-engine identity.

Flush bounded JSONL before/after load/check/native file_book and before/after
each file_book definition. Record:

- Source, copy, patch, installed compiler, Node, Base, source/native-effect
  manifests, original entry and every resolved lookup hash before and after.
- Check duration, hole count, declaration/filled-definition counts, template
  instance counts by family from both book.tmps and book.tlds; hash closed keys
  rather than dumping enormous term strings.
- Native reachable definitions/ADTs, dependency edges, flat/non-flat counts,
  reference-site counts, actual `fun_of` live layout widths and namespace totals.
- Per-definition term visits and elapsed time, bounded slowest-definition list,
  timestamps, process RSS/engine heap observations, JSONL bytes and its digest.
  Limit total diagnostic output to 8 MiB; overflow is a diagnostic failure.

Counters/logging alter performance and the runtime differs. Use counts and
phase completion to discriminate structural hypotheses; do not turn the
diagnostic timing ratio into an installed compiler benchmark. A fast graph-only
run cannot establish that full native emission would finish.

If the graph completes without explaining the cost, report that result for root
review. No emission/fact-pass probe is prepared, granted or part of this plan.
Any later source-copy emission diagnosis would first need a separate provenance
gate against the accepted original C and separate authorization.

Do not use `-o .mjs` as the native graph probe: js_lib(mod=true) roots all host-
callable non-IO definitions. Ordinary JS output uses JS lowering and does not
run native ownership/layout fact passes. Either route answers a different
question and could not locate the native timeout by itself.

## Receipt and preservation

`evidence/resource-player-client-diagnosis-next.json` contains compact hashes,
measurements, confidence, frozen experiment contract and stopped-control receipt. Ignored raw
extraction/audit/C-table summaries are under
`build/resource-player-client-diagnosis-next/`. Embedded ranges were read as
data; no embedded code was evaluated. Both existing runner `--audit` operations
passed before and after the control, as did direct hashes of the accepted/first
source closure. All earlier seals
and visible-client files remain unchanged. This task recommends no production
source change until the phase/graph measurement exists.
