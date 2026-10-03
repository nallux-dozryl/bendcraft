# JSON serializer kernel investigation

The current public AST and `encode(value: Value) -> String` are unchanged.
The native serializer passes the existing 536 independent cases and 299
roundtrips, plus five direct-AST checks in `tests/json_kernel.bend`.
The independent BendTT kernel still rejects `encode_go`. No kernel validation
of the JSON module or its fixture laws is claimed.

Confidence is high in these reproduced results. Whether another implementation
can satisfy every constraint with this public AST is unknown; this bounded
investigation does not establish impossibility.

## Exact blocker

The array branch calls `encode_go(JArray{t}, True{})`; the object branch similarly
calls `encode_go(JObject{t}, True{})`. The tail `t` is structurally smaller.
The ordinary checker accepts a constructor rebuilt around that smaller field.
Its `term_descend` compares matching constructors field by field.

The formalized kernel uses a narrower relation. In `bendtt.lean`, `Term.pos`,
`Term.piece`, and `Arg.descend` accept a direct tagged piece, a label hit while
matching, or a pair that exactly rebuilds two pieces of the same split.
The new `JArray` / `JObject` wrapper around a tail is neither the original
column nor an exact piece of it. The direct kernel diagnostic is:

```text
SOME PROOFS FAIL
In encode_go:
affine live code, calls that descend
```

This is a specific disagreement between the ordinary descent checker and the
independent kernel, not a native JSON failure. The plain `--verdict` command
reports the compiler's generic mismatch message; invoking the cached kernel
on the emitted `.bendtt` identifies the rejected definition.

## Minimal reproducer

This removes JSON grammar, Unicode handling, and serialization completely:

```python
import Base

type Node is Data:
  Node{children: List<&2, Node>}

def count(node: Node) -> Nat:
  match node:
    case Node{Nil{}}: 1n
    case Node{h <> t}: Nat.add(count(h), count(Node{t}))
```

Save that text as `build/json-kernel-structural-probe.bend`, then run:

```sh
/Users/chuah/.bend/bin/bend build/json-kernel-structural-probe.bend --check-only
/Users/chuah/.bend/bin/bend build/json-kernel-structural-probe.bend --verdict
/Users/chuah/.bend/bin/bend build/json-kernel-structural-probe.bend -o build/json-kernel-structural-probe.bendtt
/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt build/json-kernel-structural-probe.bendtt
```

The first command reports `ALL PROOFS CHECK`. The second fails. The last
command reports `In count: affine live code, calls that descend`. The evidence
file records the exact source and outputs, so the ignored `build` files need
not be retained.

## Bounded alternatives examined

A private dependent walker can give each raw piece the appropriate type:
`Payload(ValueSort{}) = Node` and
`Payload(ArraySort{}) = List<&2, Node>`. This would avoid reconstructing a
container, but a first runtime selector changes from `ValueSort{}` to
`ArraySort{}` before the payload column can shrink. The ordinary checker
rejects that self-call as nondecreasing.

Making this first selector erased instead is also rejected: matching it to
select live code reports `a live scrutinee (a - scrutinee matches only in a dead
region)`. Placing a runtime selector after its payload does not provide a
working source route to inspect the payload: the payload needs the selector's
type refinement before it can be matched, and source matches must follow
binder order. These observations eliminate the tested indexed route; they are
not a theorem about every possible private representation.

The earlier JSON investigation also tried an unfilled `encode_go` law plus
earlier list helpers, and a closed `List.foldr` template callback referring to
the current `encode_go`. Both were rejected as live calls to an unfilled
definition. They were not repeated here.

No `@unsafe`, foreign routine, axiom, unchecked law, compiler/kernel edit,
fixed serializer fuel, truncation, AST migration, or parser-limit reduction
was introduced. Computing a structural fuel bound with the same nested-tree
recursion would itself require resolving the reproduced descent mismatch.

## Direct AST verification

Run the existing corpus and build the additional native fixtures:

```sh
python3 tools/test_json.py
/Users/chuah/.bend/bin/bend tests/json_kernel.bend --check-only
/Users/chuah/.bend/bin/bend tests/json_kernel.bend -o build/json-kernel-tests
```

The new executable emits five JSON lines in order:

| Fixture | Independently expected output | Code points |
| --- | --- | ---: |
| Mixed AST | Ordered nested containers, escaped key, NUL/newline/emoji string, exact `-0.00E+400` token | 56 |
| Depth 256 | 256 `[` characters, `9007199254740993`, 256 `]` characters | 528 |
| Array with 20,000 values | `[` plus 20,000 `null` tokens separated by commas plus `]` | 100,001 |
| Object with 4,000 members | Keys `k3999` through `k0`, in that order, each with exact `-0.00E+400` token | 74,891 |
| String with 20,000 emoji scalars | A quoted string containing 20,000 literal U+1F600 characters | 20,002 |

The last four ASTs exceed the parser's depth or size envelope. They test the
existing serializer contract for direct valid AST construction without
lowering it to the parser's bounds. Native output was compared byte for byte
with independently constructed expected strings using this reproducible check:

```python
import subprocess

lines = subprocess.run(
    ["build/json-kernel-tests", "--threads", "1"],
    check=True, capture_output=True, text=True,
).stdout.removesuffix("\n").split("\n")
expected = [
    '{"z":[null,[],false],"q\\\"\\\\":"\\u0000\\n😀","n":-0.00E+400}',
    "[" * 256 + "9007199254740993" + "]" * 256,
    "[" + ",".join(["null"] * 20000) + "]",
    "{" + ",".join('"k' + str(i) + '":-0.00E+400'
                     for i in range(3999, -1, -1)) + "}",
    '"' + "😀" * 20000 + '"',
]
assert lines == expected
print("Five direct AST outputs match exactly")
```

The finite `exact_mixed_fixture` equality normalizes under the ordinary
checker. `tests/json_kernel.bend --verdict` fails because its imported
`encode_go` is rejected; its finite equality is not presented as a general
serializer theorem. Source hashes, kernel identity, commands, outputs, and
native output hashes are saved in `evidence/json-kernel.json`.
