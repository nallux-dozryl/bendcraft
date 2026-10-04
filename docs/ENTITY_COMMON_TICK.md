# Entity scheduler snapshot projection

`src/entity_common_tick.bend` implements the neutral metadata projection of the pinned Minecraft Java **26.3** `Entity.setOldPosAndRot()` and `Entity.commonTick()`. It owns the two previous-position triples, `invulnerableTime` and `tickCount`; current position and camera angles remain external authority. Its success result includes an immutable camera snapshot for a future runtime to install after success.

Current verification: production and harness pass ordinary checking and their **full imported independent BendTT verdicts**. Two fresh normally constructed Java receiver executions agree for **101 cases / 110 operations each**, with plain and super-calling observer parity. All six reference integrity mutations are rejected. One installed native build passed all **279 records twice**, including actual chains and explicit policy owner recovery. This module has no runtime consumer integration.

## Measured 26.3 phases

The installed client JAR is pinned to SHA-256 `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`. The recorded `Entity.class` hash is `7ac5f6a929abbf4fa00f0a87ad530669f7d96c8ee2bb86a5076ab1fab352fb3c`. Full class hashes, disassembly fingerprints and method-body hashes are in the reference and compact extraction report; ignored disassembly files retain the complete primary bytecode text.

Actual final `Entity.commonTick()` performs these operations in order:

1. Decrement signed `int invulnerableTime` only when it is greater than zero.
2. Invoke final zero-argument `setOldPosAndRot()`.
3. On a client level, invoke the actual interpolation handler's `interpolate()`.
4. Increment signed `int tickCount`, with Java's wrapping 32-bit payload.

Actual final zero-argument `setOldPosAndRot()` invokes `setOldPos()` and then `setOldRot()`. The private position copier writes `xOld` and `xo` from the same current X, `yOld` and `yo` from current Y, and `zOld` and `zo` from current Z. Both triples must be retained independently before the snapshot: they are different fields, and the reference deliberately initializes them differently. The private rotation copier assigns current yaw to `yRotO` and current pitch to `xRotO`, without clamping, wrapping, angle normalization or arithmetic. The setter alone changes neither countdown nor tick count.

The normal client `LocalPlayer` **does not use the `Entity` default NO_OP handler**. `LivingEntity.createInterpolationHandler()` invokes `SteppedInterpolationHandler.create`; the client fixture has a real `SteppedInterpolationHandler` with `hasActiveInterpolation() == false`. `AbstractInterpolationHandler.interpolate()` takes its inactive branch, calls `cancel()` and returns; `SteppedInterpolationHandler.cancel()` resets internal interpolation data. This module projects the measured camera/position/count fields only. It neither represents nor claims the handler's cancel/reset internals. Active interpolation is rejected explicitly.

The super-calling observer records `old_position_entry`, `old_position_exit`, `old_rotation_entry`, `old_rotation_exit`. Actual measurements show the countdown already updated at all four phases, the counter still unchanged until after them, both position triples copied at the position exit, and previous camera angles copied only at the rotation exit. Every observed current position, bounding box, velocity, width, height and four collision/ground flags remains raw-equal through these admitted calls. The normal real handler remains inactive before and after.

This is a scheduler prelude, distinct from `Entity.tick`, `LocalPlayer.tick`, `aiStep`, the post-aiStep previous-angle range loops, and the simulation Core clock. Polling/rendering does not invoke it. Existing runtime, world and rotation modules are unchanged.

## Public typed boundary

Imports use `E` for EntityCommonTick, `M` for Movement and `PL` for PlayerLook. Positions are `M.Vec3` with exact `F.F64` raw words. `PL.State` uses F32 **degrees** for current and previous yaw/pitch.

```text
Metadata is Data:
  Metadata{
    position_o: M.Vec3,       # xo / yo / zo
    position_old: M.Vec3,     # xOld / yOld / zOld
    invulnerable_time: U32,
    tick_count: U32
  }

State is Type:
  State{metadata: Metadata, tail: List<&1, State>}

Context is Data:
  NeutralClientInactiveInterpolation{}
  ActiveInterpolation{}
  NonClient{}
  UnsupportedLifecycle{}

Request is Data:
  Request{
    position: M.Vec3,
    look: PL.State,
    context: Context,
    tail: List<&2, Request>
  }

Snapshot is Data:
  Snapshot{metadata: Metadata, look: PL.State}

set_old_pos_and_rot(state: State, request: Request)
  -> State & Result<&2, &2, Error, Snapshot>

common_tick(state: State, request: Request)
  -> State & Result<&2, &2, Error, Snapshot>
```

The caller derives `Request.position` from its sole authoritative Body and supplies its sole current `PL.State`. No persistent Body, world owner or current-position copy exists in E.State. The returned State owns only metadata; Snapshot is an immutable value representing the successful update. The caller installs Snapshot.look only after `Done`. The API cannot establish the physical provenance of a Data request or infer a real interpolation handler from a token: `NeutralClientInactiveInterpolation` is explicit conditional caller evidence.

The request token admits the measured neutral client/inactive-handler lifecycle projection. It is not an implementation of handler activation, pending network interpolation, passengers, sleeping/death lifecycle, movement/travel, pose, fall history, damage, or old head/body yaw fields. `Entity.load` is not observed by this corpus; persistence consumers must use their own measured load phase rather than infer it from the commonTick copier.

U32 carries the raw payload of Java's signed int fields. Every counter and countdown word is admitted. The decrement condition is `0 < payload < 0x80000000`; zero and all high-bit-set negative int payloads are retained. Tick increment uses U32 addition modulo 2^32. Neither value passes through Nat or float conversion.

## Admission and rollback

All finite F64 payloads are admitted for both old-position triples and current position; all finite F32 payloads are admitted for all four camera fields. There is no magnitude gate, coordinate range, yaw-history bound, angle loop, conversion or fuel requirement. Signed zeros, positive/negative maximum finite values, subnormals and arbitrary finite raw words are copied unchanged.

This finite-input contract is a Bend extension. Actual Java raw assignments are not claimed to reject nonfinite fields. The checked module rejects them before mutation, including previous values that a successful snapshot would overwrite. Nonempty State and Request tails are also a canonical ownership/admission policy rather than a Java field.

Errors use a Data enum:

| Error | Meaning |
|---|---|
| `NonCanonicalState{}` | Owned State.tail contains an additional State owner. |
| `NonCanonicalRequest{}` | Request.tail contains another request. |
| `UnsupportedContext{context}` | Active interpolation, non-client or unsupported lifecycle token. |
| `NonFinite{field}` | An input float payload has an all-ones exponent. |

The exact refusal order is State tail, Request tail, Context, then numeric fields 0–12. Field numbering is:

| Fields | Payloads |
|---|---|
| 0, 1, 2 | metadata `position_o` X, Y, Z |
| 3, 4, 5 | metadata `position_old` X, Y, Z |
| 6, 7, 8 | request current position X, Y, Z |
| 9, 10 | current yaw, current pitch |
| 11, 12 | previous yaw, previous pitch |

Every refusal returns the complete original State, including all child/tail owners and every raw metadata word. It has no partial countdown, tick increment, position copy or previous-angle update. Request is immutable Data and is retained by the caller. No low-level foreign/unsafe code or host arithmetic implements this projection.

The harness explicitly repairs invalid finite-policy inputs to +0, replaces unsupported context by the neutral token and removes request tails. A retained owned child is independently invoked with the recovered request before the parent is invoked; both original owners are reused. This is a test-only recovery policy, not a new production reset API or a claim about Java recovery from nonfinite state. Valid repaired input outputs are separately observed on actual Java receivers, including the distinct child countdown 7 / counter 99.

## Actual reference boundary

`tools/reference_entity_common_tick_probe.py` derives a private fixture from the frozen `reference_local_input_probe.py` normal-constructor templates and launcher. It does not edit those files. The four substituted external service types remain `Minecraft`, `Gui`, `Tutorial` and `ClientPacketListener`; actual LocalPlayer, Player, LivingEntity, Entity, ClientLevel and inheritance bytes are unchanged. The fixture constructs a normal actual LocalPlayer with real Options, registry/profile/world services and the actual real inactive interpolation handler. It does not use Unsafe allocation or substitute a handler.

The observer overrides only `setOldPos` and `setOldRot`, records entry/exit and calls `super`. Final `commonTick` and final `setOldPosAndRot` are untouched. Both plain and observed instances are measured for every input. The loaded official class map is compared with pinned installed entry hashes; eight primary class inventories pin the Entity/interpolation call chain. Java/runtime/libraries/metadata and expanded fixture/launcher hashes accompany both fresh runs.

The original 87-case/96-operation corpus includes separate setters/common ticks, signed countdown edges, signed count wrapping, different old triples, signed zeros, distant ordinary coordinates, largest finite/subnormal raw fields, 48 seeded arbitrary finite cases and three multi-operation chains. Fourteen added finite inputs independently measure repaired field cases and the child owner, producing the final 101-case/110-operation corpus. Expected data consists of actual observed before/after and intermediate snapshots, not bytecode-derived outputs.

Ordinary position cases invoke actual `setPos`. Raw finite numeric-position cases seed the private position field **after normal construction**, without rebuilding the bounding box; they establish metadata copying and current field retention only. They do not establish physically coherent Body reachability or movement legality at arbitrary finite coordinates. No unequal huge-angle full-tick loop is invoked. Every target JVM has a 120-second process-group watchdog.

`reference/entity_common_tick.json` retains all actual fixture values. Compact `evidence/entity-common-tick-reference-extract.json` and `...-rerun.json` contain counts, canonical hashes, primary inventory/provenance and a hash-linked ignored full report. Full source strings, launcher, loaded class map, stdout and all plain/observer observations stay under `build/entity-common-tick-reference/`; they are not duplicated into checked evidence. The earlier two-case `...-feasibility.json` is a historical receipt from the pre-repair producer, not the final producer generation.

Reference integrity verification rejects all six injected changes: client JAR, Java runtime, library, official class, launcher source and actual observation. It also checks exact fixture/input/raw-row lengths, canonical fixture and observation digests, expanded source/templates, ignored raw report bytes and the loaded class-tree hash. The test runner verifies measured intermediate phase order without computing game outputs.

## Reproduction and completed validation

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_entity_common_tick_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_entity_common_tick_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_entity_common_tick.py --prepare
```

Preparation is the runner's default and performs only ordinary checks plus reference/integrity validation. It writes the sealed source/dependency/tool/compiler/reference generation and all expected cases under ignored storage. The fixed 25-U32 native protocol contains flags, countdown/counter, nine F64 values as high/low pairs and four F32 words. Harness imports only production modules, never another test module or JSON serializer. Owned reports use named, narrow continuations and a bounded stage machine; it retains the State on each error and sequence transition.

The completed 279-record suite replays all 110 actual operations independently, plus the three real multi-step chains, 58 measured finite owner recoveries, 104 nonfinite refusals and four error-priority checks. It exercises unsupported contexts, request/State tails, each numeric field with positive infinity, negative infinity, quiet NaN and signaling NaN, exact refusal priority and complete original owner retention. Chain replays intentionally reuse reference steps and are counted separately from unique actual observations. The one-child inspector reports deeper tails as present and retains them; the protocol constructs one distinct child level only and makes no arbitrary-depth output claim.

The following native and proof commands ran once under the lead's slot grant; future heavy reruns remain separately scheduled:

```sh
# One installed whole-process-group build, capped 600 seconds;
# retained executable compared twice, each entire comparison capped 120 seconds.
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_entity_common_tick.py --native --skip-ordinary

# After native success: source verdict capped 60 seconds, then harness capped
# 60 seconds only if the full source import graph passed. No retry is automatic.
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_entity_common_tick.py --kernel --skip-ordinary
```

The runner checks unchanged source, tools, reference, compiler, transitive Bend/native inputs and the retained native binary before/after. A content-keyed build receipt retains preflight emitted C separately from installed CLI output; no assertion equates it to unobserved internal temporary C or claims unseen compiler flags.

Five source laws state complete owner return on refusal, copying both old-position triples while preserving setter countdown/count, exact current-angle retention, noncanonical request retention and retention of every owned State tail. Five harness laws cover the positive countdown edge, two signed-negative payloads, count wrapping and magnitude-independent finite admission. These are their exact statements, not a universal Entity/commonTick/lifecycle equivalence proof. The full imported source verdict passed in 3.716601 seconds, then the full imported harness passed in 3.820310 seconds. No source projection, retry or proof-isolation substitution was used.


## Frozen execution receipts

The preflight generation remains unchanged: source SHA-256 `b8d5416c18423543d90eb3fa74cd9291c7786036f2708fe45c9534c4f2b41f4e`, harness `d8798e0609ffe242cc2aa9b361efa0c441cdd18e550b8159aa33580bf8d2b675`, probe `13a4aa0fec04a645e510a38cee4fecb08f864ec9a806e5adb2d8dc618058eb66`, driver `bbc6ee464ddb42506101ace971426cfee5d324dca3e99fcfa0806092e2c9b8e7` and reference `d49c9054f0ae9f7e4ac15baf068ae00809e331c88bf7465e80d9f160c000f578`. The final documentation is a reporting-only update; its old prepared hash remains in the historical sealed preflight.

The one granted build (PID 32967) completed in 3.741447 seconds, including a 1.079311-second installed native compilation phase. There was no cache hit. The 1,199,608-byte retained executable has SHA-256 `3f392bd94dd15a494cd3a7d03648b4b0e1ed56092d9e2b61e315ec41de0b8e90`. Two complete native suites took 0.605876 and 0.100599 seconds, both producing the canonical result hash `63f2fd5d77ad290c136544d1ba3b703ed7ef73329622a21ea61d51c71d90be56`. These short fixture timings are verification receipts, not a full-client performance benchmark.

The build receipt pins 1,632 native/compiler/system dependencies; ordinary/preflight generation pins 38 source/effect inputs. The associated preflight C has SHA-256 `1407b1d5639c919fba322b9a0967a63354384a852757ead53bc7cc87e6e2e44d`. The build completed before the first process inventory, so internal temporary C and live clang arguments were not separately captured. Recorded compiler flags are the build cache's resolved recipe and dependency audit; they are not falsely labeled a live process trace.

Native success evidence was written before the source kernel attempt (PID 33421), followed by the harness (PID 33456). The slot was explicitly released after all phases. Before/after verification confirmed unchanged source/tool/reference/compiler generation and retained native dependencies/binary. The original expected-record digest remains `325e6d1908b71b9ddf7b70e33c98d22a7a5f0e1eb8a68abfb127ae16497300ac`.

Relevant compact manifests:

- `evidence/entity-common-tick-preflight.json`: historical sealed preparation and owned-file pins.
- `evidence/entity-common-tick-prepared.json`: ordinary/reference preparation, exact categories and queued commands.
- `evidence/entity-common-tick-build.json`: single installed build and dependency/artifact receipt.
- `evidence/entity-common-tick-native.json`: both retained-binary comparisons and ignored raw output hashes.
- `evidence/entity-common-tick-kernel.json`: successful full imported source/harness verdicts.
- `evidence/entity-common-tick-final-verification.json`: final retained-output/generation audit.
- `evidence/entity-common-tick-handoff.json`: final reporting and owned-file generation.
