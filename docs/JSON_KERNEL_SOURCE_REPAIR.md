# JSON source repair design: unresolved checked traversal

**No complete source repair candidate is ready for execution or adoption.**
This design review specifies the full traversal and its proper-piece arguments,
then identifies where that design cannot yet be expressed through the inspected
checked source interfaces. It does not claim that no other implementation can
exist. Production JSON, the sealed diagnosis, tests, and toolchain are unchanged.
No new Bend check, export, verdict, kernel invocation, native build, or native
test was run in this task.

Confidence is **high** in the cited source/guide rules and the previously sealed
diagnostic results. Confidence in the existence of a satisfying source repair is
**unknown**. The failed designs below are excluded design routes, not repairs
waiting to be presented as verified.

## Required behavior

The public `Value`/`Member` constructors and `encode(Value) -> String` must
remain unchanged. Every caller-valid AST must retain compact exact output:
scalar strings and keys use the current escaping; number lexemes remain exact;
arrays and object members retain order. Arbitrarily alternating nested objects
and arrays, and direct ASTs beyond the parser's input/depth envelope, are part of
this contract. No object rejection, fixed work cap, truncated suffix, or smaller
parser envelope is a satisfying repair.

The [sealed diagnosis](JSON_KERNEL_DIAGNOSIS.md) establishes that the current
ordinary checker accepts the exact serializer while the actual pinned kernel
rejects `encode_go`. The rejected tail calls wrap a raw list tail in `JArray` or
`JObject`. The raw tail is a proper piece; the rebuilt wrapper has no accepted
piece path. This design starts from that concrete boundary.

## Complete semantic fold and exact structural edges

The direct raw-piece traversal has three visitor signatures:

```text
V(value: Value) -> String
A(values: List<&2, Value>, continuation: Bool) -> String
O(members: List<&2, Member>, continuation: Bool) -> String
encode(value: Value) -> String = V(value)
```

`V` emits null, Boolean and number tokens and calls the unchanged `quote` for
strings. For an array it emits `[` followed by `A(values, False{})`; for an
object it emits `{` followed by `O(members, False{})`. `A` and `O` emit the
closing delimiter when empty. A nonempty list emits a comma if continuing;
`A` visits its head, while `O` quotes its head key, emits a colon, and visits
its head value. Both then visit the raw tail with continuation true.

This specifies the complete mixed-object/array semantics, without an artificial
bound. It is **not** an admitted Bend definition family: its call graph contains
live mutual recursion.

The following piece paths use the pinned kernel's innermost-first convention,
where false/true selects the first/second field of an elaborated pair. A native
constructor elaborates as `(tag, (field0, (field1, ... ())))`.

| Caller case | Call and argument | Exact path in caller column 0 |
| --- | --- | --- |
| `V(JArray{xs})` | `A(xs, False{})` | `[false,true]` |
| `V(JObject{ms})` | `O(ms, False{})` | `[false,true]` |
| `A(h <> t, c)` | `V(h)` | `[false,true]` |
| `A(h <> t, c)` | `A(t, True{})` | `[false,true,true]` |
| `O(JMember{k,v} <> t, c)` | `V(v)` | `[false,true,true,false,true]` |
| `O(JMember{k,v} <> t, c)` | `O(t, True{})` | `[false,true,true]` |

Each raw argument is a genuine piece of its caller's matched input. These are
static structural paths, not a new kernel result. For the self-calls to `A` and
`O`, the first column descends, so their later Boolean change is irrelevant to
lexicographic termination.

The unresolved issue is a **source call graph**, rather than an arithmetic
measure for these individual edges:

```text
encode -> V
V -> A -> V
V -> O -> V
A -> A
O -> O
```

For plain user definitions, `V -> A` requires `A` filled before `V`, while
`A -> V` requires `V` filled before `A`. Both strict orderings cannot hold.
The `V`/`O` cycle has the same contradiction. A forward law supplies a type but
does not supply a live implementation. This is a proof that **this three-def
ordering scheme** cannot satisfy the inspected filled-definition gate; it is
not an impossibility proof over all source programs.

## Why inspected fold/lambda interfaces do not yet close the cycle

The guide states that closures are affine, including partial applications, and
that only top-level definitions can be called freely. A plain runtime callback
`f: Value -> String` therefore cannot simply be reused for every list element.
A `+f` binder is not a remedy: function types are `Type`, and a reusable binder
requires `Data`.

Base supplies these closed-template folds:

```text
List.foldl(~a, ~A, ~B, ~f: B -> A -> B, xs: List<a,A>, acc: B) -> B
List.foldr(~a, ~A, ~B, ~f: A -> B -> B, xs: List<a,A>, z: B) -> B
List.map(~A, ~B, ~f: A -> B, xs: List<A>) -> List<B>
```

A closed template callback can be used repeatedly. But the needed callback
still invokes the current value visitor. The previously measured callback
specialization attempts reached that visitor before its live body was filled;
they were rejected. This task does not retry them.

An outer template is not a demonstrated solution to this problem. The inspected
`def_inst` records an instance with a null body while checking it. If checking a
list-fold instance calls back into that already-instantiating visitor instance,
the callback is in a different definition. `def_inst` explicitly rejects that
unfilled cross-instance cycle. A direct self-call within one current instance
is a distinct case; it does not establish safety for the visitor/fold cycle.
The checked-in `tests/check/template_inst_cycle.bend` documents that gate with
its expected diagnostic. Its presence was inspected; it was not rerun here.

Capturing a matched child in a one-shot lambda can preserve a known piece
argument, but it does not supply a visitor for all the other dynamic list
elements. Capturing a local ancestor also makes that callback ineligible as a
closed `~` argument. A callback whose own parameter is a fresh `Value` does not
by itself tag that parameter as a piece of the outer visitor's input. No
checked lambda/fold construction resolving all these requirements was found.

Returning an affine callback beside each result would require a complete
checked construction of the next callback. No such construction is established
here; merely writing a recursively defined visitor/factory pair recreates the
same live cycle. This remains an unresolved design, rather than a claim that
owner-threaded callbacks are universally impossible.

## Other inspected routes and their precise gaps

**One indexed payload walker.** The historical runtime selector precedes its
dependent payload. Its change occurs before the payload can shrink, so the
ordinary left-to-right descent check rejects it. The erased-selector version
cannot select live code. Placing the selector after its dependent payload does
not yet provide a source route to refine and inspect that earlier payload in
the required binder order. These previously failed schemes are constraints,
not proposed experiments. Relabeling a selector as `~` does not supply a proved
live eliminator: template binders are erased and the generic check uses opaque
constants. No new mode-specialized walker is claimed to work.

**A private unified cursor/tree.** Merely adding wrappers around raw values,
value lists, or member lists recreates the unmatched-wrapper recursion argument.
Converting the public AST to a different tree also requires a complete checked
mixed-type traversal. No such converter is supplied by this design. A new
private representation is permitted in principle, but stating its type does
not resolve how to construct it from every valid public AST.

**A computed structural measure.** A sufficient exact fuel value would avoid
truncation only if a checked total constructor derives it for all valid ASTs.
The obvious `Value`/value-list/member-list size fold has the same traversal
cycle. A fixed limit, wrapping native arithmetic, or the current rejected
serializer used as a measure would not resolve the full-module kernel gate.
No total checked measure construction was found.

**An explicit work stack.** Replacing a popped item with its children constructs
new work. The resulting stack is not simply a proper piece of the previous
stack. This scheme still needs another decreasing structural argument or a
sufficient checked measure; neither is supplied here.

**The elaborator's existing group machinery.** `safe.ts` describes this as
handling Base forward-law helpers, such as `String.cmp.fin`. Base's native-law
exception is not a user source permission to invoke unfilled live definitions.
Moreover, `group_new` searches for a live leading parameter passed unchanged
in every helper callback. For the complete raw fold above, `A` calls `V(h)` and
`O` calls `V(v)` using matched fields, rather than their unchanged leading list
parameter. Thus this exact three-visitor scheme does not meet that inspected
group criterion either. The existence of group translation is not a verified
route to admitting this source family.

## Review threshold before any experiment

There is no execution plan to approve for the current unresolved designs.
A future **full** candidate needs all of the following supplied at source
level before a grant is requested:

1. Exact function signatures and a complete body for every helper, with the
   unchanged public AST and public `encode` signature.
2. Every recursive call identified, including its current live column, exact
   same-column piece path or unchanged-column prefix, and the later free
   arguments. A cross-type structural edge alone does not discharge the live
   callee-availability rule.
3. A declaration/specialization order that closes without an unfilled law,
   unfilled instance, escaping bare self-reference, or illicit reusable
   runtime closure. All template callbacks must actually be closed.
4. Full mixed-object/array behavior with exact quoting, number lexemes and
   ordering, and no artificial cap or narrower parser policy.

Only after that review would bounded ordinary/export/direct-kernel checks make
sense. Any production adoption would also require the complete JSON module's
kernel result, the finite fixture scope reported separately, and native
comparison of the existing 536 cases/299 roundtrips and direct valid-AST large,
deep and mixed cases. A serializer projection pass alone would not certify the
parser or the entire module. Native checks should exercise a scratch full
candidate with the unchanged parser before any coordinated production edit.

The plan receipt is `evidence/json-kernel-source-repair-plan.json`. It pins the
source/guide rules inspected and records the unresolved design status, complete
semantic fold signatures/edges, and **zero new semantic executions**. Scratch
design notes remain under ignored `build/json-kernel-source-repair/`.

## Additional review: erased index and trailing live witness

**This route does not yet supply a complete candidate in the pinned source
language.** Its argument order would solve the selector-before-payload descent
problem if the payload could be refined and matched there. The exact proposed
constructor targets are unsupported; the straightforward equation-field
emulation has separate match-order and descent-tag barriers. A type template
also creates a cross-instance cycle. These are specific design obstacles, not
a claim about all possible programs.

Before this update, the initial report, receipt, and fold note were copied
byte-for-byte to `build/json-kernel-source-repair/initial/`. The updated receipt
pins those copies. No new check, export, verdict, kernel, native build, or
native test was run. Confidence in the inspected rules is **high**; a complete
satisfying source repair remains **unknown**.

### Full intended body and exact recursion paths

This is the requested **semantic design**, not admitted Bend syntax:

```text
VisitKind<A : Data> with indexed constructor targets:
  ValueKind   : VisitKind<Value>
  ValuesKind  : VisitKind<List<&2, Value>>
  MembersKind : VisitKind<List<&2, Member>>

visit(-A : Data, payload : A, kind : VisitKind<A>, continuation : Bool)
  -> String

visit / ValueKind / payload:
  JNull{}       -> "null"
  JBool{b}      -> choose(String, "true", "false", b)
  JNumber{raw}  -> raw
  JString{s}    -> quote(s)
  JArray{xs}    -> "[" ++ visit(List<&2,Value>, xs, ValuesKind, False{})
  JObject{ms}   -> "{" ++ visit(List<&2,Member>, ms, MembersKind, False{})

visit / ValuesKind / payload:
  Nil{}        -> "]"
  Con{h,t}     -> comma(continuation)
                  ++ visit(Value, h, ValueKind, False{})
                  ++ visit(List<&2,Value>, t, ValuesKind, True{})

visit / MembersKind / payload:
  Nil{}                -> "}"
  Con{JMember{k,v},t}   -> comma(continuation) ++ quote(k) ++ ":"
                          ++ visit(Value, v, ValueKind, False{})
                          ++ visit(List<&2,Member>, t, MembersKind, True{})

comma(b) = choose(String, ",", "", b)
encode(value : Value) -> String = visit(Value, value, ValueKind, False{})
```

The intended graph is `encode -> visit`; `visit -> visit`, `quote`, `comma`,
and existing scalar helpers. It has no callback or helper recursion. For this
non-template signature, erased `A` is column 0 and skipped. Raw payload is
**column 1**:

| Caller branch | Recursive payload | Column 1 proper-piece path |
| --- | --- | --- |
| Value / array | `xs` | `[false,true]` |
| Value / object | `ms` | `[false,true]` |
| Values / cons | `h` | `[false,true]` |
| Values / cons | `t` | `[false,true,true]` |
| Members / member-cons | `v` | `[false,true,true,false,true]` |
| Members / member-cons | `t` | `[false,true,true]` |

If an actual case tree established these paths, each call would descend before
column 2's witness and column 3's Boolean; both later arguments could change.
That differs materially from the failed live-selector-first design. The missing
part is a checked source body establishing those matches and tags. This table
is static structural analysis, not a translation or kernel result.

### Constructor targets and implicit refinement are unavailable

`~A` denotes a **definition template** binder, not a datatype parameter.
Parametric datatype syntax is `type VisitKind<-A: Data> is Data:`. Constructor
rows do not accept result annotations. `parse_book` at `bend.ts:2533` generates
every result as the family applied to its own parameter variables.
`book_valid` at lines 3836–3845 independently requires that exact form, including
each unchanged corresponding variable. Thus neither alternative surface
spelling nor a hand-constructed book provides the requested constructor indices.

Checked-in `tests/parse/gadt_result_annotation_000.bend`, its `_001` variant,
and `ctor_indexed_target.bend` contain the rejected examples and expected
parser diagnostics. They were read, **not rerun**. Three nullary rows in a
parametric `VisitKind<-A:Data>` provide all three constructors at *every* `A`.
A `ValueKind{}` match therefore does not identify `A` with `Value`.

The ordinary `Mat` rule (`bend.ts:3632–3648`) fills a constructor telescope
with the existing family arguments and substitutes the constructed scrutinee
in the **goal**. It does not unify constructor-specific result indices or
replace the already-bound `payload:A` context entry. Runtime-erased and opaque
template indices consequently do not become concrete payload types from this
parametric witness match.

### Equation fields: supported evidence, unresolved traversal

The existing `tests/proof/gadt_refutation.bend` demonstrates the Ford encoding:
ordinary family parameters plus equation fields. An appropriate proposed shape
is:

```text
type VisitKind<-A: Data> is Data:
  ValueKind{eq: {Value == A : Data}}
  ValuesKind{eq: {List<&2,Value> == A : Data}}
  MembersKind{eq: {List<&2,Member> == A : Data}}
```

This declaration is **not newly checked**. The equation orientation permits
transporting a concrete-domain handler to `A -> String`. Live evidence fields
could supply a live rewrite; making them erased does not license live use of
that evidence. Neither an open law nor an axiom is a substitute.

Evidence does not implicitly rewrite context entries. The ordinary `Rwt` rule
at `bend.ts:3696–3698` checks its body under a transported **goal** with the same
context and descent state. The kernel's type rule has the same goal-only shape.
The inspected `tests/proof/context_rewrite_value.bend` transports a value through
such a goal, not an earlier payload's structural tags through a recursive match.
The direct emulation then encounters three specific barriers:

1. **Match the original payload after the witness.** `match_flatten` closes
   earlier binders as lambdas when advancing to a later constructor column
   (`bend.ts:2711–2713`). The old payload is no longer an open match column.
   Revisiting it reaches the earlier-binder-after-later-match refusal at lines
   2644–2649. A variable-only payload row keeps no constructor refinement;
   matching it first requires knowing its datatype before the witness arrives.
2. **Transport the payload itself.** A cast/helper/rewrite result is a computed
   term, not an original tagged raw field. A helper may inspect that result,
   but the kernel's `Term.pos` has no arbitrary helper-call or rewrite case
   giving it a proper-piece path. Native erasure cannot be assumed to erase
   the cast from the proof check.
3. **Transport a handler and apply it to the original payload.** The Value arm
   can abstractly attempt
   `(%eq : _ -> String; concrete_Value_handler)(payload)`. The handler's fresh
   `x:Value` can be type-directed, but checking it does not reconstruct the old
   payload's left-hand side. After the visitor's original binders are consumed,
   `term_check` extends `lhs` for lambdas/matches only while `lhs.n > 0`
   (`bend.ts:3505–3506`, `3645–3646`). Fresh `x` and its children are not pieces
   of the earlier `payload` column. In this straightforward expression shape,
   recursive calls on those children have no ordinary same-column descent.

The third shape has a separate independent-kernel barrier. `safe.ts`
`rwt_term` (lines 1339–1357) emits a `Rwt` with the translated handler, rather
than erasing it or transferring the applied payload's tag. `Term.takes` only
recognizes `Lam`, `Prj`, `Mat`, and `Efq` (`bendtt.lean:248–253`). `Term.tree`
transfers an applied variable's tag only to those heads (lines 1269–1274).
An applied `Rwt` goes to `Term.live`; its lambda binders receive `none` tags,
and its matches do not perform `Guard.next` piece splitting (lines 1231–1247).
The handler does not inherit the table's raw paths. This is static analysis of
that expression shape, **not a newly observed kernel rejection**.

Runtime equation evidence is a variable in the checked generic term, not a
reflexivity literal. Ordinary evaluation only reduces a rewrite when its
evidence normalizes to `Rfl` (`bend.ts:2859–2866`); the kernel's live check walks
emitted syntax without normalizing it away. Constructing closed witnesses using
`{==}` alone does not solve the generic body's access to the payload. These
findings leave more elaborate elimination designs open.

### Erased generic binder and direct template self-specialization

For `visit(-A:Data, payload:A, kind:VisitKind<A>, c:Bool)`, every type instance
still calls **one definition**. The erased column may vary; there is no template
instance cycle. If a checked elimination preserved column 1's pieces, all six
edges would satisfy the intended lexicographic rule. This review does not
establish that elimination.

Native layout is **not an established separate blocker** for this signature.
`comp.ts` distinguishes generic layout handling from `lay_el`'s particular
refusal of an open *Array element type*. `lay_of` defaults to a box when its
type cannot be exposed as an ADT. This visitor proposes no Array. No native
artifact exists for it; layout correctness is a future verification obligation,
not an observed or assumed failure.

For `visit(~A:Data, payload:A, kind:VisitKind<A>, c:Bool)`, the generic source
check still occurs. `def_check` at `bend.ts:3718–3729` substitutes a fresh opaque
constant for `A`; a concrete specialization cannot retroactively make an
invalid generic body admissible.

Even **assuming** that elimination were solved, the specified complete traversal
creates a mixed-type specialization cycle:

```text
first visit(~Value, ...) begins instance V (body initially null)
  array child -> visit(~List<&2,Value>, ...) begins instance A
    list head -> visit(~Value, ...) re-enters null V from A
```

The object/member-list path similarly creates `V -> O -> V`. `def_inst` installs
a null body before checking an instance (`bend.ts:3758–3763`), then rejects
re-entry into an existing null instance from another definition (3764–3765).
That applies when the erased type changes even though the raw payload is a
proper child. A same-type list-tail call can be a current-instance self-call;
it does not discharge either mixed-type cycle. No callback is needed to create
this new version of the cross-instance obstruction.

The remaining question is a **single non-template checked eliminator** whose
erased index and trailing witness permit inspecting the original payload at
its original column and recursively visiting its raw children. Direct indexed
constructors, implicit refinement, the late payload match, simple casts,
the simple transported handler, and type templates do not supply that body.
There is no full candidate to request execution for yet. Production semantics
and the previous parser/kernel/native obligations remain unchanged.
