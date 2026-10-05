The first-order numeric scanners passed both actual production decoder harnesses,
two C emissions, two native builds, all 45 pinned original-Java cases and four
exact cached baseline exponent refusals. Confidence in those observations is
high. They replace only the numeric sections of `block_model.bend` and
`blockstate_model.bend`; their public scanner signatures, token/error ADTs,
wrapped arithmetic, 100000 threshold and downstream conversions are unchanged.

Each public scanner calls a shrinking-text worker with `admitted:Bool` second.
The worker matches text, then character/admission together. An empty-text helper
checks admission before returning the old reversed token. This preserves refusal
when an excessive exponent consumes the last character. Ordinary recursive
branches pass True; the exponent branch passes the existing exact update and
threshold. No recursive closure captures the remaining text or digit list.
Existing guard definitions remain available to previous law imports.

| Actual unchanged harness | Cached production C | First-order C | Reduction | Cached / new final scanner and helper lines |
| --- | ---: | ---: | ---: | ---: |
| Model | 5,814,673 bytes | 4,407,248 bytes | 24.20% | 31,511 / 30,359 |
| Blockstate | 5,331,406 bytes | 3,824,645 bytes | 28.26% | 33,242 / 31,961 |

The comparisons include all new workers, finish helpers and public wrappers.
Both new emissions performed the complete ordinary check before producing C,
retained their loaded-source pins unchanged and reaped their owned groups.
Plain CPU route guards and Clang `-std=c11 -O3 -lpthread -lm` passed. The native
model/state binaries are 1,865,656 and 1,908,600 bytes respectively.

Emission was **slower** than the historical focused production runs: model
66.870 versus 37.285 seconds, blockstate 96.393 versus 51.122 seconds. Completed
scanner/helper body emission totaled 50.856 versus 23.369 seconds and 77.114
versus 35.873 seconds. These runs used different machine workloads and were not
a controlled benchmark. The deterministic C-size benefit is established;
compiler or whole-client speedup is not. Thin public wrappers still incur
substantial compiler traversal, despite emitting few C lines.

The native adapter consumed the unchanged 35 cached and ten executed exponent
cases from the original pinned Java harness. All accepted complete projections
matched; Java rejections compare status, with only the existing blockstate
diagnostics field omitted. Four separate exponent-limit cases matched the exact
cached native errors, including paths and blockstate detail. Cached baseline
binaries and Java were not rerun. Original corpus, prior native observations,
refusal inputs and candidate binary hashes were verified against their retained
receipts. Native run receipts and all raw observations remain in ignored
`build/generic-resource-world-sample-numeric-first-order-003`.

The first private worker failed before C because matching admission before a
nested character match violated actual binder order. Its 0.788-second refusal
and reaped group remain in generation001. Generation002 was file-only and
exposed an overbroad indentation replacement before any checker/build; it is
preserved. Generation003 uses the corrected character/admission matcher and
passed. Original compiler files and frozen generic005 remain unchanged.

Six new complete-scanner equivalence equations and structural induction drafts
compare arbitrary strings, stages, digit prefixes, fractions, exponents, signs
and paths against reversibly qualified exact `b27e64f` original scanner bodies,
using identical actual token/error ADTs. These drafts are unverified; no theorem
or independent-kernel acceptance is asserted. Their retained source receipt is
`003/equivalence/source-receipt.json`. They are separate from the actual native
Java comparisons and do not gate the next changed client consumer.

The substantive next full client is generic006. Generic005's genuine600-second
failure is retained in commit `fd30f61`; no unchanged retry or bound extension
occurred. The public launcher remains Actor017/Renderer008 until a changed
renderer passes actual demand heartbeats, pixels, durable save and cold restore.

Reproduce private preparation with
`python3 tools/generic_resource_world_sample_numeric_first_order.py --generation N`
for a fresh N. Run each explicit `--build block_model`, `--build blockstate_model`,
`--clang block_model`, `--clang blockstate_model`, then `--compare-native` and
`--report`, retaining N. Coordinate actual memory-heavy occupancy before each
stage. Preparation requires the cached baseline scanner bytes and deliberately
refuses once working production differs; generation003 is retained for the
already-adopted candidate. The helper supplies orchestration, never a parser,
compiler implementation or expected Java behavior.
