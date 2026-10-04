# FallResetWorld R2 dependency admission

R2 is a bounded host repair of `tools/test_fall_reset_world_continuation.py`.
The R1 file, documentation, prepared seal and evidence remain frozen at their
original paths. R2 owns `tools/test_fall_reset_world_continuation_r2.py`, this
document, `build/fall-reset-world-continuation-r2/` and evidence beginning
`fall-reset-world-continuation-r2`. Preparation and review establish host
admission only; the supplier's native and kernel outcomes remain unverified
until separately recorded execution succeeds.

The frozen producer/comparator is still `tools/test_fall_reset_world.py`, SHA256
`d304fd0e425d6790f316a99ce88635623584bea637e75d0b143c71318ecf72fc`.
Source SHA256 remains
`8353ad65484f28b80ae49a3b4191bf98aad5903f6565f6d17f2d64eeec2c7948`;
the harness remains `tests/fall_reset_world.bend`. R2 preserves the frozen
request, parser, raw comparisons, corpus, policy/recovery and registry-remap
functions, and retains the original 107 actual completed Java MISS cases,
29 policy/recovery cases and 14 remap cases per run, twice. Hits, watchdogs and
other exclusions remain excluded. No endpoint or result is fabricated.

R1 admitted native dependencies through resolved-path bytes/hash checks. R2
requires each builder dependency row to contain its original absolute `lookup`
and canonical absolute `path`, plus `kind`, `bytes` and `sha256`. Each lookup
must resolve to the declared target; the target must resolve to itself. Both
paths enter the sealed consumer manifest, including the exact original builder
row. Alias and target pins must agree on byte count, SHA256 and the six-field
stat tuple: device, inode, size, modification nanoseconds, change nanoseconds
and file mode. A missing lookup has no resolved-path fallback.

Every file pin resolves strictly before reading, verifies lookup/target stat
agreement, compares the opened descriptor's stat before and after the read,
then rechecks both paths and resolution. A same-byte alias retarget or target
replacement is rejected. Shared targets are memoized within one dependency
admission. `verify_build` hashes each consumer file once, then validates all
dependency rows against those observed pins and the sealed dependency records;
it does not rehash each target separately for hash and size.

The R1 constructor-abort strategy, process supervisor, raw streams, durable
PID/group journal, all-group cleanup and mode routing are retained. Constructing
the builder's `InputsChanged` raises a distinct refusal before its internal
retry catch can handle it. Every build must report zero retries and a cache
miss; every artifact/cache/attempt starts absent. Cleanup continues after each
group's permission error and preserves unknown absence as failure. Raw receipts
precede decoding/comparison; overall success follows the final parent sweep.

The preparation adds 11 file-only dependency controls to the 18 retained inert
controls: stable alias and direct-target admission, same-byte retarget and stat
drift refusal, explicit lookup/target/hash/length checks, missing consumer alias
refusal and duplicate lookup refusal. These controls use private files and fake
process objects. They launch no compiler, native child, kernel, JVM/Java or UI,
and signal no real process group. The preparation receipt and independent
review receipt carry their actual outcome.

Run from the Minecraft project directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation_r2.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation_r2.py --audit
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation_r2.py --build-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation_r2.py --native-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation_r2.py --proof-only
```

Execution modes remain mutually exclusive and require separate lead grants.
Build-only permits one 600-second builder child plus five-second cleanup and
never executes the binary. Native-only requires the completed exact artifact
and consumer seal, performs two complete 150-process runs, and permits at most
120 seconds plus five-second cleanup per child. Proof-only separately permits
one unchanged full-harness `--verdict` attempt for 60 seconds plus cleanup.
There is no chaining, build fallback, automatic repair, retry or overwrite.

Prepared files are `build/fall-reset-world-continuation-r2/prepared.json` and
`evidence/fall-reset-world-continuation-r2-preparation.json`. Build, native and
proof summaries use the corresponding `-r2-build.json`, `-r2-native.json` and
`-r2-proof.json` names. The artifact is
`build/fall-reset-world-continuation-r2/fall-reset-world-native`.

The existing explicit client-player/overworld four-state profile and finite
clear interior remain the supported supplier boundary. Host admission and
supplier comparisons do not establish required-ray integration in the saved
LocalPlayer consumer, general hits/callback order, whole-client presentation
or complete Minecraft 26.3 parity.
