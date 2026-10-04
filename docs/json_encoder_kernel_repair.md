# JSON encoder kernel repair: two private candidates rejected

No satisfying source-only repair is established. Production `src/json.bend`,
the original compiler and the independent kernel were not modified. Confidence
is high in the observed rejections; whether another complete source construction
can meet the contract remains unknown.

The contract covers every directly constructed `Value`, including arbitrary
alternating array/object nesting beyond the parser envelope. Number lexemes,
string/key escaping, member order, compact delimiters and `encode_go`'s
continuation behavior must remain exact. Fixed fuel, a new AST limit, truncation,
axioms and foreign/unsafe serialization would not satisfy it.

The complete private late-witness candidate uses
`visit(-A:Data, payload:A, kind:VisitKind<A>, continuation:Bool)`, with live
witnesses for `Value`, `List<Value>` and `List<Member>`. All scalar, array and
member cases are present. Its intended recursive arguments are raw fields or
list tails. An ordinary statement match first fails the binder-order rule.
Replacing that match with inline case lambdas gets past that rule, but the
actual `JArray` call on its raw list is rejected as nondecreasing: the type
transport does not preserve its relationship to the earlier generic payload.
The final ordinary check took 0.400 seconds. Neither a kernel verdict nor a
semantic execution was attempted for this rejected source.

The second private copy changes only the Decimal import path and the quantity
of `encode_go`'s input to `+value`. It keeps the full production encoder body.
Its generic law states that every raw number lexeme is emitted exactly, without
a numeric conversion. The ordinary checker passes in 0.655 seconds. The
unchanged source API exports 94 complete dependency declarations, 662,990 bytes,
with zero exclusions in 1.221 seconds. This includes every actual encoder
branch, both rebuilt tail calls, and its string escaping dependencies. The
unchanged independent kernel rejects that artifact in 0.299 seconds:

```text
SOME PROOFS FAIL
In json.encode_go:
affine live code, calls that descend
```

Making the value reusable does not repair the reconstructed-tail descent.
`Term.pos` recognizes tagged raw variables, matched labels and aligned live
pair rebuilds; the rebuilt `JArray{tail}` and `JObject{tail}` do not align with a
proper-piece path. This is a descent failure, not a demonstrated duplicate-use
failure. Kernel `Quan.live` treats both affine and reusable quantities as live.

Three raw visitors would give proper pieces on every semantic edge:
`Value → List<Value>`, `Value → List<Member>`, list head → child `Value`, and
list → raw tail. Their call graph requires live mutual recursion. The inspected
source filled-definition rule prevents that direct family. The payload-first
witness alternative instead needs type-refining elimination that retains the
payload column. Its complete private source fails that requirement; kernel
`Term.takes` also does not propagate pending payload tags through `Rwt`.

These findings exclude the tested routes, not all possible Bend programs. A
checked mutual raw-payload traversal or a heterogeneous eliminator preserving
descent would address the precise gap. No such capability is demonstrated here,
and no candidate is ready for adoption. The scalar law export is not a universal
canonical-output proof or a substitute for the full 13 component laws.

Exact source, tool, artifact and raw process receipts are linked by
[`json_encoder_kernel_repair_001.json`](../evidence/json_encoder_kernel_repair_001.json).
All five bounded child groups were reaped and absent. Private candidate code and
raw captures remain under `build/jsonencoder-late-witness-001` and
`build/jsonencoder-reusable-001`; those retained build files are not published.
