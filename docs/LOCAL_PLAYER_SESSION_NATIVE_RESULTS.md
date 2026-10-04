# Saved LocalPlayer composite native results

Confidence: high for the declared neutral consumer. The fresh composite passes
both actual TCP/MCP/persistence suites and the complete frozen codec, phase and
facade checks. Full gameplay and physical client acceptance remain open.

## Current generation

The entry is unchanged `tests/local_player_session.bend` (SHA2081023f). The
sole Bend delta is the due_wall fixture stamp tick0→tick1 in
`tests/local_phase_runtime.bend` (SHA73015803→9589c371). Production runtime,
session, codec and independent references are unchanged.

The separate producer is `tools/test_local_player_session_continuation_r2.py`
(SHA51810052). Prepared seal7024be27 has 6,110 pins/111 imports;
consumer457fbd8f has 6,116 pins. The 13,519,272-byte artifact is
`build/local-player-session-continuation-r2/local-player-session-native`
(SHAc7da9766), with native receipt5b6efc5d.

One build passed in 567.740 seconds under its 600-second child cap, with zero
retries and a cache miss. All 1,693 native dependencies were independently
rehashed. Retained generated C is 42,087,419 bytes (SHA6bc5cd65); the lead hashed
the actual Clang input while present and confirmed equality. Actual driver and
frontend arguments are retained; no second C payload copy was made.

## Completed native checks

| Lane | Result |
| --- | --- |
| Primary0 | 26 checks, 37 exact save comparisons, 50 refusals; 29.215 seconds |
| Record | Original 755 cases twice: 1,510 executions in 32 native batches |
| Phase | 15 actual Java outcomes plus 28 project-policy comparisons, twice |
| Facade | Three forged-stage callback guards, twice |
| Primary1 | 26 checks, 37 exact save comparisons, 50 refusals; 28.631 seconds |

Both primary runs verify actual TCP/MCP transport, input/tick ordering, complete
supported local records, cold restart, continued movement, queued edits,
invalid-owner recovery and corrupted startup refusal. Each also interrupts all
five Atomic publication stages with SIGKILL, checking the complete old/new
generation, lease recovery and restart. Both phase streams are byte-identical:
538,712 bytes (SHAf300c44d). Facade streams are also byte-identical, and all
required completion markers were reached.

Root replay recomputed every phase/facade comparison, all 1,510 codec output
files, and all codec command arguments and expected stdout lines. It independently
reconstructed 28 retained final save bundles and checked all 74 producer
save-byte-comparison receipts. Intermediate saves overwritten at the same path
were compared by the immutable producer; their original bytes are not all retained.

The final sweep and fresh independent probes confirm all 252 owned groups are
absent. All 158 listener probes returned Darwin ECONNREFUSED61. Each actual
group has a 120-second run cap, with separate cleanup budgets; this is not an
overall 120-second suite duration claim.

## Reproduction and history

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --audit
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --build-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --skip-build
```

Preparation, generated references, pinned compiler/SDK and retained MCP bridge
are prerequisites. Attempts use exclusive paths: already executed commands
refuse to overwrite this generation. Audit is read-only; build does not
automatically execute the artifact.

The original artifact1958e777, host-fixture failures, incomplete phase output
and archived tick0 harness remain preserved. Held continuation R1 passed closure
checks but failed inert permission-error cleanup admission. R2 changes only
external supervision: durable codec PID registration, retained raw/process/
cleanup errors, complete per-PID sweeping and restored scoped bindings.
Unknown or erroneous cleanup rejects the lane. Original parsers, expectations,
corpus and comparison bodies remain unchanged.

Current evidence: `evidence/local-player-session-continuation-r2-completion.json`,
the full native receipt, root build/native/codec audits and admission receipts.
Raw outputs and journals are in the ignored generation tree. Historical
`LOCAL_PLAYER_SESSION_TESTS.md` remains frozen.

## Client scope

This verifies the neutral adult/unscaled four-state/default-attribute profile
and custom bundled persistence, with synthetic fixture input over actual
transports. Required reset rays, general attributes, fluids, flight, full player
lifecycle, vanilla player.dat and broader gameplay remain outside this consumer.
No new independent kernel verdict follows from a native pass.

The separately built saved resource client also passes its paired native suite.
Its current launch and explicit save/stop instructions are in
[RESOURCE_CLIENT_NATIVE_RESULTS.md](RESOURCE_CLIENT_NATIVE_RESULTS.md).
Physical OS input, visible drawable/GPU presentation and packaged-client
acceptance require the coordinated procedure in VISUAL_ACCEPTANCE.md.
