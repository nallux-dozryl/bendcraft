# JSON kernel diagnosis for the unchanged production serializer

The independent kernel rejection is reproducible in a **58-line verbatim
projection of the current production serializer**, without the parser, its
limits, test laws, or game imports. The ordinary checker accepts that projection;
the actual pinned BendTT kernel rejects `encode_go`. A control containing the
other 91 unchanged translated definitions passes the same kernel.

Confidence is **high** in the recorded source hashes, exact translation
comparisons, ordinary result, direct kernel result, and control result. The
separate static trace identifies the reconstructed array/object tail arguments
as the failed descent comparisons. That trace is diagnostic instrumentation,
not another proof checker. No general JSON theorem, serializer repair, or
impossibility result is claimed.

This task changed no production source, test, compiler, runtime, native binary,
or earlier JSON receipt. It did not rerun the native JSON corpus or a full
module verdict. The experiment and its control each ran once with a 15-second
process-group limit; neither timed out.

## Existing evidence and scope

| Record | Source generation and result | Scope |
| --- | --- | --- |
| `evidence/json-tests.json` at commits `7463513` and `49f4a23` | JSON SHA256 `a546726a…`; ordinary checks pass, module and fixture `--verdict` exit 1 with the generic mismatch message | 536 native independent cases and 299 roundtrips pass; the generic message alone does not name a cause |
| `evidence/json-kernel.json` | The same old source; direct cached kernel names `encode_go` and reports `affine live code, calls that descend` | Also records the 192-byte nested-list `Node` reproducer and five direct constructed-AST native checks; no kernel validation |
| `evidence/json-tests.json` at `22923d0` and the current file | Current JSON SHA256 `bf6cb1ca…`; ordinary checks pass, module/fixture verdicts remain generic failures | The existing native corpus still passes; this diagnosis did not repeat it |
| `evidence/json-limits.json` | Current source; direct pinned kernel on retained export SHA256 `7682dddf…` names the same `encode_go` diagnostic | Configurable parser limits and native resource/boundary tests; unchanged serializer/accessor suffix |
| This diagnosis | Current source projected verbatim; all 93 exported definitions equal the retained full-module definitions | Actual kernel rejection in `encode_go`; actual pre-encoder control pass; separate static descent/usage analysis |

The parser-limit change introduced `Limits`, threaded the configured depth, and
added checked cap/fuel entry helpers. It did not change the serializer or
accessors: their old/current source suffix is byte-identical, SHA256
`ec117bb02a661735a49e97abcdabb154b5cfe992c8beb8062e72bacd68cacf93`.
The retained old and current BendTT exports have identical `Value`, `Member`,
`choose`, escaping/quoting helpers, `encode_go`, and `encode` definitions.
There is no need to infer the current blocker from a generic failure of a later
importing module.

The historical indexed-walker and erased-selector probes were rejected by the
ordinary checker, as recorded in `JSON_KERNEL.md`. The earlier unfilled-law and
template self-reference attempts were also unsuccessful. None was repeated or
presented as a repair here.

## Toolchain generations

The installed tool reports `bend 2.0.35`. The following pins were read before
the diagnostic commands and compared again afterward:

| Component | SHA256 | Observed relationship |
| --- | --- | --- |
| `/Users/chuah/.bend/bin/bend` | `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e` | Identical to the compiler pin in the earlier JSON kernel receipt |
| Installed/repository `base.bend` | `c742fae9c49b14f0cc9128429a2c6109364c8a933a142f2c90b9f2e5fd976661` | Both match the pinned Bend commit `79df8d9c40722ee9507a1e253f283b51025f9d6c` |
| Installed/repository/cached `bendtt.lean` | `e15042434e73aab07ab05cea4b77b5619082c00a6d4924ea2d4a2cdec05facce` | All byte-identical; cache directory is its first 16 hash characters |
| Cached kernel executable | `04f97a0aba640bf1246c425ba70f3790584e42f8bcf8c608991f293d78ef58a7` | Identical to the earlier JSON kernel executable pin |
| Repository `bend.ts` | `7deae3693eb896f33c73867081b99d2c6f3ed3b57e77e55eb5f6260840dd0e63` | Matches the pinned Bend commit and earlier inspected checker source |
| Repository `safe.ts` | `54cb3a534ab7cc9ee313bf6383b3948ccdcac022469b3020e00745bbfe6f7e04` | Matches the pinned Bend commit |
| Repository `main.ts` | `d1a3e026f5014f8daec3614df8e39cf261e3fbc47769eb0916fd891bc18703c9` | Matches the pinned Bend commit |

`BENDTT` and `BEND_LIB` are unset in the observed environment. The checked-in
loader locates installed Base and Lean beside the installed executable; the
verdict launcher chooses a cached kernel by the Lean source hash unless
`BENDTT` is supplied. Those files and the cached executable are consistent with
the recorded pins. **No observed generation drift explains this result.**

The installed executable bundles its TypeScript implementation. This diagnosis
does not independently establish the original build manifest linking that
executable to each repository TypeScript file. It therefore reports the
binary/source pins and exact emitted-definition comparisons separately, rather
than claiming a stronger build provenance than the artifacts supply.

`main.ts` returns the generic mismatch message when `safe_check` is false.
`safe_check` combines translation scope and direct kernel acceptance. The
generic text alone therefore does not distinguish a scope exclusion from a
specific kernel rule. The retained and newly isolated **direct kernel output**
provides the narrower observation used here.

## Exact projection and actual kernel results

The ignored file `build/json-kernel-diagnosis/serializer_exact.bend` consists of
`import Base` and these source blocks, copied verbatim and in production order:

```text
Value, Member, choose, hex_char, escape_char,
quote_body, quote, encode_go, encode
```

It is 1,720 bytes, 58 lines, SHA256
`e5a7dce5ca3dbf4b3b8e89b4a255645128c1415da4881baef42e601b2be1a26d`.
Its manifest records each copied block hash. There are no replacement bodies,
new laws, placeholders, axioms, unsafe code, foreign calls, fuel caps, or AST
changes in this projection. The existing Base translation dependencies retain
their exact generated forms.

| Command | Result | Seconds |
| --- | --- | ---: |
| `bend build/json-kernel-diagnosis/serializer_exact.bend --check-only` | Exit 0, `ALL PROOFS CHECK` and the ordinary verdict hint | 0.187 |
| `bend build/json-kernel-diagnosis/serializer_exact.bend -o build/json-kernel-diagnosis/serializer_exact.bendtt` | Exit 0, no scope exclusions printed | 0.272 |
| Pinned cached kernel on that translation | Exit 1, diagnostic below | 0.152 |
| Pinned cached kernel on the dependency-closed pre-`encode_go` control | Exit 0, `ALL PROOFS CHECK` | 0.151 |

The projection export is 659,542 bytes, SHA256
`c2e13a158636e02c1ef013237b3a28f07e0977076a0e867e1c3398ecff01739d`.
**Every one of its 93 definition blocks is byte-identical to the corresponding
block in the retained current full-module export.** The actual direct output is:

```text
SOME PROOFS FAIL
In encode_go:
affine live code, calls that descend
```

The control selects the exact translated definitions preceding `encode_go`,
adds their named dependencies, and preserves original order and all definition
bytes. It contains 91 definitions and omits only `encode_go` and `encode`.
It does not change a recursive call or invent a helper implementation.
Its pass establishes acceptance of that specific control; it does not establish
acceptance of the serializer or full JSON module.

Exact commands, process IDs, caps, stdout/stderr, translation comparison rows,
control definition names/hashes, and before/after pins are recorded in
`evidence/json-kernel-diagnosis-projection.json`.

## Separating quantity usage from descent

The kernel's `Def.check` performs type and closure checks before one combined
`Term.tree` check whose message is `affine live code, calls that descend`.
That message alone does not identify which conjunct failed.

The scratch script `build/json-kernel-diagnosis/static_trace.py` reads the
retained, exact `encode_go` translation. It implements only the inspected
`Quan.allows`, `Guard.next`/`bind`, usage, piece-path, live-call, and case-tree
rules needed by that term. Unsupported syntax is rejected. It neither checks
types nor normalizes terms; its output cannot replace the actual kernel.

For this definition it reports **zero binder-use quantity violations** and
**zero rejected calls to other definitions**. Its four self-call comparisons
are:

| Production source call | Exact first translated argument | First-column `Term.pos` | Descent comparison |
| --- | --- | --- | --- |
| `encode_go(h, False{})` | `x0` | Proper piece at `[false,true,false,true]` | `lt` |
| `encode_go(JArray{t}, True{})` | `(.JArray, (x1, ()))` | No path | `gt` |
| `encode_go(v, False{})` | `x1` | Proper piece at `[false,true,true,false,true,false,true]` | `lt` |
| `encode_go(JObject{t}, True{})` | `(.JObject, (x2, ()))` | No path | `gt` |

Paths use the kernel's **innermost-first** convention. Both raw list tails
have a proper-piece tag at `[false,true,true,false,true]`. The problem in this
trace is the reconstructed wrapper argument, rather than the raw tail itself.
The original outer constructor label is a hit at `[false]`; the newly wrapped
tail is nested at a different piece path. `Term.pos` only reconstructs a pair
when its components are matching first/second pieces of the same split. This
combination has no such path. Consequently `Arg.descend` stops at `gt` in the
first live column, without reaching the changed continuation Boolean.

The ordinary checker's `term_descend` handles a matching constructor by
comparing its fields recursively. For `JArray{t}` against the current
`JArray{Con{h,t}}`, the matching outer constructor is retained and the list
field descends to its tail. The object-tail call uses the same pattern.
The exported kernel term retains exactly that source-level rebuilt wrapper;
there is no observed quantity change or translation-body drift in the isolated
comparison.

This is a source/translation-level localization supported by an actual kernel
rejection, an exact helper control pass, and the separately labeled static
trace. It does not show nontermination, falsity of the finite fixture
equalities, or impossibility of a different checked implementation.

## Actionable boundary

The bounded diagnostic package isolates the question to the agreement between
the ordinary constructor-field descent rule, its unchanged exported argument,
and the kernel's exact-piece descent relation. The 58-line production
projection and the already recorded 192-byte structural reproducer provide
local inputs for a toolchain investigation. Neither needs game modules, parser
limits, native runtime work, or another broad corpus run.

No repair was attempted in this task. A future change to the serializer or
toolchain needs its own authorization and checks; acceptance of this control
must not be used as acceptance of the omitted encoder. The project continues
to have its existing bounded native JSON evidence and a specifically rejected
full JSON kernel gate.

The new inventory is `evidence/json-kernel-diagnosis-inventory.json`, actual
diagnostic commands are `evidence/json-kernel-diagnosis-projection.json`, and
the separate static trace is `evidence/json-kernel-diagnosis-static-trace.json`.
