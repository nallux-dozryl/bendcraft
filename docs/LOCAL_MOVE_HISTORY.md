# Atomic neutral local movement and fall history (26.3)

`src/local_move_history.bend` composes the frozen neutral `LocalMoveWorld`
projection with one authoritative owned `PlayerFallHistory.State`. There is one
world/body owner, one history owner and one externally returned sine-table owner.
No existing runtime, session, travel, collision, support or lifecycle consumer is
changed. Confidence is high in the independently observed bounded field projection and
native comparisons. Both native suites pass; independent kernel validation remains
unverified because the full imported source reports a compiler/kernel mismatch.

## API and authoritative inputs

Import as `MH`:

```text
State Type {
  world: W.State,
  support: SP.State,
  minor: LM.MinorState,
  history: H.State,
  tail: List<&1, State>
}
Request Data {
  move: LM.Request,
  clip: H.Clip,
  tail: List<&2, Request>
}
Outcome Data {
  move: LM.Outcome,
  history: H.History,
  tail: List<&2, Outcome>
}
move_checked(State, L.Tables, Request)
  -> State & L.Tables & Result<&2, &2, Error, Outcome>
```

Recursive boxes bound native continuation width. Canonical state/request tails,
including the inner `LM.Request.tail`, are empty. A nonempty request tail returns
`NonCanonicalRequest{field}` (`0` outer, `1` inner); a nonempty owned state tail
returns `NonCanonicalState`. All original owners and all tail contents return on
rejection. There is no independent history mode that can bypass movement
admission. `LM` must admit the neutral move; only its success reaches the fixed
`H.NeutralDryNoDamage` mode. Direct noPhysics remains unsupported by `LM`.

Before motion, the request's `LC.EdgeContext.fall_distance` must be **raw-bit equal**
to the sole owned history distance. Numerically equal positive/negative double
zeros do not satisfy this binding. A mismatch returns `HistoryMismatch` without
calling movement. The body in the immutable `LM.Request` is a checked snapshot;
`LM` requires it to equal the authoritative world body. It is not a second owned
body. Likewise `Outcome.history` is immutable observation data, not another owned
history state.

`MH.movement_from` derives every numeric history phase argument from the returned
`M.Transition`: the actual resolved vector's Y, the exact ordered binary64 length
squared, returned body onGround, and `position_changed`. The latter means the
position-application branch was taken, including when zero displacement or
rounded position addition retains the old XYZ payloads. It is not a bitwise
position-change test. Length squared uses the same ordered expression as the
measured actual `Vec3.lengthSqr()`:

```text
((x*x) + (y*y)) + (z*z)
```

The explicit clip value is an authoritative external phase observation. The
adapter does not implement or fabricate a ray result. A taken application branch
with old distance numerically nonzero and resolved length squared at least one
requires a real `Miss`. Other branches require `NotRequired`. `Hit` is explicitly
unsupported; missing/unknown or superfluous evidence returns a history error.
The fresh receiver records actual `ClientLevel.clip` entry, endpoints and returned
hit type, plus Java's actual resolved length squared and ray precondition.
Absence of a hook alone is not labeled as MISS.

## Phase equivalence and rollback

The untouched 26.3 receiver executes:

```text
backoff / collide / application gate
→ support (original velocity)
→ minor collision when called (original velocity)
→ actual getOnPosLegacy block sample
→ checkFallDamage(resolvedY, onGround, sampledBlock, sampledPosition)
→ removed gate
→ restitution / movement emission / block speed
→ autoJump / walkedDistance
```

`LM` supplies a checked immutable neutral final-motion candidate while preserving
the original velocity at its support/minor phases. This adapter can then apply the
history reducer atomically because the admitted support/minor/query operations do
not depend on the newly accumulated history, and its admitted history path has no
implemented observable callback effects: only actual MISS/NotRequired contexts
and default no-damage landings. This is equivalence of the stated field projection.
It is not a reordered execution of damage, block callbacks, sounds, game events,
movement emission, autoJump or walkedDistance.

The history update preserves the actual ordered expression:

```text
distance = distance - (double)(float)resolvedY   # when resolvedY < 0
```

It is not inferred from old/new position subtraction, requested Y or support.
The negative gate-skip fixture independently observes accumulation while XYZ
application is skipped. Ground resets to positive double zero after accumulation.
The reducer admits default no-damage landings only, using the separately verified
ordered threshold `((distance + 1e-6) - 3) < 1`; default safe-fall distance and both
multipliers are `3`, `1`, `1`. The new complete move observations also cover real
ordinary air/stone/dirt/oak-plank sampled blocks within `LM`'s four-state palette.

Every error returns the entire original world View, including raw body/velocity,
yaw/pitch, palette, bounds and snapshot cache; original support, minor flag and
history; and the external tables. `LM`/world queries return canonical engine data
without mutation. The adapter retains that engine and restores the prior View.
Thus a history failure after successful motion cannot publish partial body,
support, minor or history changes. Canonical clocks, revision, cell data, pending
actions and event queues are retained. Owned noncanonical tails are returned
verbatim before any extraction.

Errors are `NonCanonicalState`, `NonCanonicalRequest`, `HistoryMismatch`,
`MoveError{LM.Error}` and `HistoryError{H.Error}`. History failure can occur after
motion on a missing required clip, unsupported hit, or damaging landing; these are
atomic exclusions. The actual damaging fixture reaches vanilla's real damage path
and fails at the declared Minecraft service's absent `gameRenderer` field. That
observed fixture-service failure is not a vanilla rejection. Bend explicitly
rejects this context and restores all prior state.

## Fresh reference and verification preparation

The probe derives a private receiver copy from the frozen whole-move fixture and
uses normal actual LocalPlayer/ClientLevel constructors. It substitutes the same
four previously declared external services: Minecraft, Gui, Tutorial and
ClientPacketListener. Actual game Entity/LivingEntity/Player/LocalPlayer/
ClientLevel and block bytes remain pinned and untouched. FixtureLevel supplies
finite actual full-block/air lookup and chunks. Added player and clip observers
call `super`; the paired plain receiver establishes that observation did not
change field results.

The checked reference retains all fixture values and actual query/sample/phase
observations, rather than replacing expected history with Python arithmetic.
The complete raw Java reports, sources, expanded launcher and loaded-class map
live in ignored `build/local-move-history-reference/*.full.json`. Compact evidence
reports retain canonical input/observation/case/class-tree hashes, counts, pins,
commands and raw-file hashes.

Preparation observes **69 cases / 85 move attempts** on each paired
receiver. All original **61 LM cases / 75 moves** retain their complete earlier
projection after removal of only the new observational fields/sequence offsets.
There are **83 successful admitted moves**, one actual nonsuppressed-bounce context
excluded by `LM`, and one actual damaging callback-service failure excluded by
history. The measured ray contexts are **83 NotRequired / 2 actual MISS**. A fresh
independent Java execution reproduces the cases and all **4,390 loaded official
class hashes** exactly. Six corruption checks reject client, runtime, library,
source, loaded-class tree and actual observation mismatches.

The prepared Bend harness imports production modules only. It reuses unchanged
immutable serialization/query-audit helpers from the frozen LM harness and adds
history assertions. It compares exact callback Y/ordered length squared/ground/
application gate, all raw body and history bits, support/minor and query lists.
Read-only collision/support replays are labeled as harness audits; they are not
production trace instrumentation.

Canonical cell preservation uses **lossless run serialization of every cell of
every owned section plus the exact trie structure**, while returning the arrays.
It is not a checksum-only comparison. The suite passes 28 rejection/recovery cases,
including signed-zero history mismatch, outer/inner request tails, a distinct owned
world in `State.tail`, LM failure after backoff, required/superfluous clip errors,
damaging landing and running/pending-world history failure. Required-clip recovery
reuses the returned history/world without reseeding. The nonempty-tail test also
reuses the returned distinct child world and the tables. Four real-registry remaps
exercise 14 additional admitted moves. Both full suites pass on the same retained executable. Each run matches 83
admitted actual moves, preserves the two measured exclusions, passes all 28
recovery cases and 14 remapped moves. The exact canonical result hash is equal
across both runs. The suites take 16.316101 and 15.283459 seconds including
repeated fixture setup and audit serialization; these are not game-performance
measurements.

Six laws state callback derivation, complete rollback-frame retention, complete
history-failure rollback, noncanonical owned-tail retention, request-tail owner
retention and raw positive/negative-zero distinction. Ordinary checks pass. The single full imported production verdict exits 1 after
20.686065 seconds with the generic TypeScript/BendTT mismatch and no named law or
source location. Per the lead's conditional grant, the full harness verdict is
**not attempted**, because source validation did not succeed. The six laws remain
independently unverified. No retry, projection or source substitution was used.
No universal game-physics or callback-equivalence theorem is claimed; the frozen
LM module has its own separately recorded full-import mismatch.

Reproduce the lightweight preparation from the project directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_history_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_history_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_history_probe.py --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_history.py --prepare
```

The frozen native command used one whole-group 600-second installed build and
then the two unchanged suites:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_history.py --skip-ordinary --skip-kernel
```

The build passes in 89.825552 seconds: associated preflight C emission takes
36.991600 seconds and installed native compilation 45.153188 seconds. The retained
executable SHA256 is `b4387cd6eca3843948faa86541be358aaea33bc8fed78c49a37ae62d93f0488a`.
All **1,659 native dependencies**, resolved lookup paths, sizes and SHA256 values
are verified before execution and again afterward; the 65-file source graph,
Python tools, reference, sine table and artifact remain unchanged. The original
lightweight preflight remains a distinct frozen receipt, rather than being
rewritten to claim native/proof completion.

The associated content-keyed preflight C is retained under
`build/local-move-history-cache/sources/8bb28138166da5b4326b5adb6f12f2f4e72304baa33ea7b7d9b2a126c691d6a5/generated.c`,
8,584,008 bytes, SHA256
`db8f8be1b2f26f2ff6b1aa9af746973538bcbf07da7f2d0f45807665a079ab91`.
Read-only process samples observed the emission/build phases but did not capture
the actual temporary internal clang/C invocation. The receipt records installed
compiler driver flags `-std=c11 -O3 -lpthread -lm`; associated preflight C is not
silently labeled as byte-identical actual internal C.

The actual source verdict command was
`/Users/chuah/.bend/bin/bend src/local_move_history.bend --verdict`, capped at 60
seconds in the frozen runner's `bound('kernel-source', 60)` process group. A wrapper
would invoke `bound('kernel-harness', 60)` only after source success. It records
that conditional skip in `evidence/local-move-history-kernel.json`. The generic
`--kernel-only` runner route was not invoked for this grant; the actual conditional
sequence and individual command receipts are preserved. Successful native evidence
was sealed before starting proof.

No extra emission/native build, source projection, retry, runtime consumer edit,
foreground launch or lifecycle integration was performed. The heavy slot was
explicitly released after native/proof completion. Water, flying/passenger, climbing/effects, reset-ray hits,
altered damage attributes, block-specific effects, damage/health and whole
LocalPlayer.move/travel/tick parity remain outside this contract.
