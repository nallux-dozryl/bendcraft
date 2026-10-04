# Resource graph probe: host watchdog adoption

Status: prepared only, 2026-10-04. Root found a host watchdog defect in the [previous Bun proposal](resource-player-client-diagnosis-bun.md): after the group leader exited, its `process.poll()` condition could suppress SIGKILL while a descendant retained stdout/stderr. That runner was not granted source execution.

The complete previous Bun generation was copied before adoption into ignored `build/resource-player-client-diagnosis-bun-watchdog/lineage/sealed-bun/`: 27 regular files are byte-identical, and the installed-Base symlink has the same target. Its original wrapper, tracked documentation and preparation receipt remain unchanged. The separate Node generation and failure receipts also remain unchanged.

The new runner is `build/resource-player-client-diagnosis-bun-watchdog/run_graph_probe.py`. This adoption changes Python process supervision, durable receipts and output validation only. It reads the previous sealed plan, retaining the exact installed executable, TypeScript source/probe, config, manifests, argv, environment adaptation, 90-second group limit and 8,388,608-byte combined output cap. It does not copy or alter compiler functions for a new experiment.

## Watchdog and receipt contract

Each attempt claims its receipt exclusively and writes/fsyncs an `attempt-started` record before launching a fresh process group. Existing receipts refuse a second attempt. After launch, the PID/group and invocation are recorded atomically. Final receipts include partial output digests, signals, leader status, cleanup observations and structured watchdog/cleanup errors.

Pipe reads are nonblocking. The supervisor watches both pipe EOF and leader status, so closing pipes while the leader remains alive does not bypass the deadline. At the 90-second deadline or output cap it sends group SIGTERM; two seconds later it sends group SIGKILL if still supervising. Neither signal depends on the leader being alive. Final cleanup always attempts SIGKILL against the owned group, independently of the leader and pipe state.

The pipe-drain deadline is at most 92.5 seconds from supervision start. Pipes close at that boundary even if a remaining descendant prevents EOF. Final leader wait and group observation share a separate budget of at most 0.5 seconds, bounded by the absolute 93-second deadline. There is no unbounded `wait()`. Early errors also get only the 0.5-second cleanup budget. Filesystem receipt operations are separate from the pipe/wait timing contract.

An incomplete group cleanup, wait error, signal error or capture error marks the attempt failed. Cleanup errors do not bypass the final receipt. Abrupt termination of the host runner itself may leave the durable initial/PID receipt rather than a completed receipt; it is still an attempt and cannot silently be rerun.

## Exit-zero control validation

Before boxed can start, the plain attempt must exit zero, preserve all pins, finish cleanup and pass host validation of its complete stdout/stderr. Nonempty stderr, invalid UTF-8/JSON, duplicate JSON members or invalid phase records are refusals.

The five required completion phases are `load.end`, `check.end`, `native.file_book.end`, `graph.complete` and `post.audit.pass`. The host also requires `load.start`, `check.start` and `native.file_book.start`. All eight must occur exactly once in order.

The validator checks the sealed case/argv and manifest hash, the actual `load.start` entry and installed Base, the loader file count against the admitted manifest, integer-zero checker holes, matching positive traversal counters and exact native roots. The two manifests contain 51 and 65 Bend files respectively, including Base. The unchanged source harness itself checks exact loaded-file membership and live hashes before and after the graph call.

Expected roots are:

```text
main, Sigma, String, Word.Con, IO.OP, Result, Maybe, Bool, Unit
```

This contract comes from the pinned `RUNTIME_ADTS` array and the `compile_book`/`show_main` IO branch. Both sealed entries declare `main() -> IO(Unit)`, so the pure-main descriptor contributes no datatype families. `phase-contract.full.json` records those source and entry hashes. This was derived by reading source and Python literal parsing; no TypeScript compiler module ran.

## Python-only verification

The final host test generation passed five process fixtures and 15 synthetic phase fixtures. An initial passing host generation was retained separately before tightening the final cleanup budget; neither generation loaded Bun/compiler source.

The decisive fixture forks a child, exits the leader with code zero, and leaves the child holding both pipes while ignoring SIGTERM. With a test-only 0.5-second soft limit and the production two-second grace, the final runner sent SIGTERM at 0.500651 seconds and SIGKILL at 2.501076 seconds while the recorded leader exit code was already zero. It completed in 2.502171 seconds, reaped the leader and observed no group remaining. The production plan retains its 90-second soft limit.

The other actual process fixtures cover a living leader that closes both pipes, the real 8 MiB output cap, launch failure with a persisted receipt, and an injected cleanup exception after the real signal with a persisted receipt. All created groups were absent afterward. The injection is explicitly a Python host test, not an observed OS signal failure.

The protocol fixtures accept synthetic valid plain/boxed records and reject every missing completion phase, wrong entry, wrong manifest argv, wrong roots, nonzero holes, disagreeing counters, stderr, duplicate final phase and wrong order. These fixtures verify the host validator; they do not establish that the actual Bun control succeeds.

## Frozen preparation and proposed command

Default only audits files and prints the sealed plan:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-bun-watchdog/run_graph_probe.py
```

The proposed future command remains ungranted:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-bun-watchdog/run_graph_probe.py --root-bun-watchdog-graph-slot-granted
```

Plain runs first. Every process/watchdog/pin/protocol failure stops before boxed. There is no source retry, third case, emission, Clang, kernel or client launch in this adoption.

The AST scope receipt identifies unchanged `digest` and `environment` functions, the equivalent ambient lookup with `WORK` renamed to the original `SOURCE` location, changed host receipt/signal/plan/audit/run/main functions, and four new host helpers: group observation, supervision, strict JSON parsing and phase validation. Compiler/probe/source/config/manifest changes are zero. The [new preflight](../evidence/resource-player-client-diagnosis-bun-watchdog-preflight.json) pins the archive, AST diff, host tests and inert runner. Confidence is high in the tested host behavior and unchanged source provenance; actual Bun loading/graph results and the installed compiler bottleneck remain unknown.
