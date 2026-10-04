# Local-player session integration tests

The prepared entry is `tests/local_player_session.bend`. Its normal server mode uses the production `LocalPlayerSession.new`, `dispatch`, `input`, `release`, `snapshot`, and `realtime_step` paths, with the production `LocalPlayerRuntime.driver`. Python constructs independent NBT/Core expectations and orchestrates processes; it supplies no runtime movement, support, collision, or local input algorithm. Native verification has not run yet.

The primary oracle is the pinned `reference/local_phase_runtime.json`: four scheduled histories contain eight successful compatible outcomes (shift4, jump2, sprint1, zero1). These preserve all raw durable fields: motion/body/support, current and past degree fields and their exact radians projection, sampled seven keys, six local floats, sprint/crouch/timers, pose/eye, minor collision, fall distance, previous positions, invulnerability time and tick counter. Other recorded step-height profiles and the sprint-particle fixture-service failure are excluded. The declared profile uses measured constructor/default movement and jump values widened from F32, the measured sprint result, gravity.08d, max-step.6f, and sneaking.3d; it does not supply a general attribute/equipment/effect service.

The shared executable also exposes three explicit verification-only CLI lanes:

- `record-cases MODE INPUT OUTPUT ...` calls the unchanged `RecordTest.batch` for the frozen755-case record corpus, with two immediate, bounded comparisons. It includes accepted cases immediately after malformed records in the same process.
- `phase-cases TABLE` runs the unchanged phase harness and its existing15 actual and28 project-policy comparisons. Its host comparator is pinned separately from the original producer generation.
- `facade-cases TABLE` invokes the unchanged three forged-stage guards. Complete before/after owner projections must match and reject with `apply-provider-authority-drift`, proving the callback that would advance Core was not invoked.

The real session scenarios cover actual TCP and stdio MCP discovery/authentication, strict step lexemes/bounds/no-`at`/sequence behavior, read-only full-record inspection and cached-eye snapshot coordinates, explicit pause/release, three measured shift steps continuing after a durable restart, rich paused field restoration, scheduled equivalent full-cube edits before a tick, and a separately labelled unsupported-state policy rejection after Core/common commits. The latter checks recovery and must not be described as Java exception atomicity. Forged X/MH/metadata/pose tails exercise save/inspect admission, error priority and subsequent valid delegated reads with retained owner projections; X children have different clocks, queues and owned table markers. Table retention is witnessed by an all65536-word FNV32 projection, not a cryptographic equality theorem.

Save tests compare exact complete custom `bendex:bundle` Core bytes and `bendex:local-player-record` payload bytes. They cover exclusive publication collision, acknowledged-save versus unsaved SIGKILL restoration,44 independently rejected startup bundles, refusal before listener, same-path lease recovery and the official registry fresh empty initializer. Five additional SIGKILL points use an explicitly separate leased `Atomic.publish_with` stage-hook lane, then restart the real Session. They establish complete old/new generations at those returned process stages; quiet `Session.world.save` is tested separately.

The synthetic raw-TCP operations `fixture.input`, `fixture.release`, `fixture.transient`, `fixture.owners`, and `fixture.snapshot` are absent from production MCP discovery. They are verification controls, not OS input, a production player-mutation API, GPU rendering or visible-client acceptance. These tests do not establish vanilla `player.dat`, general world/environment parity, or full-game completion.

Only `--prepare` creates fixtures and runs ordinary checks. It seals the full source/tool/compiler/reference/input closure, original Java class bytes and observations, frozen codec inputs, and the retained actual MCP artifact. `--audit`, `--build-only` and `--skip-build` admit that immutable seal first and never regenerate fixtures or run Java/version/javap probes. Build and native attempts are exclusive; all complete argv/stdout/stderr and first failures are retained. The build cap is600seconds, native integration/fixture children120seconds each, and owned groups are explicitly reaped. No heavy phase is permitted without the lead's grant.

Commands, after preparation:

```
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session.py --audit
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session.py --build-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session.py --skip-build
```

The read-only oracle check is `python3 tools/test_local_player_session.py --oracle-check`. Ordinary checking exposes inherited lifetime/IO foreign boundaries and is not an independent-kernel claim. A native result must name its actual sealed artifact and comparison receipt; preparation alone is not integration evidence.
