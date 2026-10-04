# Compiler memory diagnosis (2026-10-04)

The retained 15.7 GiB peak is the macOS compiler process physical footprint before
Minecraft ran. It does not establish the game's runtime memory requirement.
`evidence/compiler-memory-diagnosis.json` pins the diagnostic inputs, compiler,
receipts, production parser changes and independently checked proof artifacts.

## Demonstrated contributors

The application parser in `remote_resource_server.bend` used long literal string
patterns, including the 27-character profile `bendex:stone-dirt-superflat`.
The read-only source-API trace identifies `fun_of` / `def_raise` for actual app
`checked_options`, then `parse`. The validator takes 2.768 seconds in raising;
the parser exhausts the explicit 4096 MiB Node heap before raising completes.
This is application option parsing, not the compiler's own command-line parser.

Installed Bend2.0.35 isolated diagnostics contain Base and the actual Options /
validator/parser, with no game imports. Equivalent validator string equality
reduces sampled peak RSS from 1785.922 MiB to 81.391 MiB and C emission from 3.456
seconds to 0.368 seconds. The original option vocabulary still exceeds 2 GiB after
only the validator fix. Keeping that parser's control flow but shortening its
literal vocabulary emits C in 0.440 seconds at 169.750 MiB. The shortened vocabulary
is a causal diagnostic only. These results show large avoidable literal-pattern
cost; no particular exponential complexity law has been established.

The real replacement is `src/resource_server_options.bend`: equality classifies
complete unchanged tokens, then a structural parser consumes classified args.
It retains defaults, exact option names, argument consumption/order, repeated
flags, fixture policy and error messages. Its actual isolated installed-CLI
consumer emits 156,181 bytes of C in 0.232 seconds at 83.125 MiB sampled peak RSS.
The native consumer passes 111 independently transcribed grammar/error/order /
Unicode observations. These finite observations complement the 19 actual
production laws over arbitrary tails and complete option records. Full 93,574-byte
IR passes the pinned independent kernel in 0.043 seconds. Root aggregation now
independently certifies 65 laws (35 foundation + 11 CoreEdit + 19 options).

After that source fix, a bounded source-API trace exposes 1,437,228 dependency
queue entries while 2148 distinct definitions have been visited. The compiler
already skips repeated processing, but queues every duplicate type reference.
A private compiler copy deduplicates enqueue only. It preserves first distinct
FIFO order, leaves actual term traversal/call counts/tail distinctions unchanged,
and reduces the complete queue to 3351 entries. The earlier observed firstvisit
prefix matches exactly. It finishes dependency analysis and reaches emission
pass five before the 45-second deadline. Ownership marks grow 3253→3383→3431→3441
across the first four passes, while hot marks stabilize at 1310 after pass two.
No complete C artifact was emitted before this deadline.

## Scope and remaining work

The production server now delegates to the proved real options module. Original
`bend/bend2/bend.ts` and `comp.ts` remain unchanged; the queue mitigation is a
private diagnostic copy, not installed tooling or a product-cache artifact.

An installed-CLI test of the retained failed backend graph with only the parser
fix still crosses the 2 GiB sampled-RSS cutoff in 2.52 seconds. This does not show
that the parser fix failed: source-API ordinary checking alone retains about
2.506 GB of heap for this 5320-declaration graph before C emission. The runtimes,
heap measurements and sampled RSS/physical footprint differ. Do not infer a
backend limit or speedup from the isolated parser or private instrumentation.

Confidence is high in both demonstrated contributors. Attribution of the entire
original 15.7 GiB peak remains open until a complete controlled backend build
succeeds. Minecraft runtime memory, frame times and client performance remain
unmeasured by these experiments. Preserve all failed inputs and continue from
the named producer/pass state with bounded jobs; no equivalent 10-minute retry.
