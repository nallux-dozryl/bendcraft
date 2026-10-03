# Visible input preflight

No actually controllable isolated desktop was demonstrated. Confidence is high
for the read-only inventory and source observations below; availability of an
unexposed or offline guest remains unknown. Visible OS-input acceptance remains
unverified. The original inventory launched no client or VM, bound no app, sent
no input, captured no screen, changed no focus/Space, and ran no compiler build.
The follow-up built only the dormant Swift OS-input helper and executed its
read-only modes. It launched no client, posted no input and requested no TCC
permission. No armed mode was invoked.

The measured host is macOS 26.4.1 (25E253), Apple M3 Pro, with one online built-in
display: 3456 × 2234 physical pixels, 1728 × 1117 logical at 120 Hz. CUA reports
native target `mac`; its latest inventory has 32 apps, 21 running, and two empty
in-app browser surfaces. ChatGPT and Minecraft Launcher are running. No guest or
isolated-desktop selector is exposed by the documented API. Inventory success
does not establish screenshot, accessibility or physical-input authorization;
those actions were not attempted. The follow-up helper's read-only samples
reported foreground PID 50401, bundle `com.brave.Browser`; they did not activate
or bind it. This is a sample, not an exhaustive transient-focus observation.

UTM 4.7.5 (118) is installed. Its saved registry lists GroundSeg, Linux, Ubuntu
x86 and macOS. Only Linux's recorded bundle/config path exists: QEMU x86_64,
q35, 4096 MiB, virtio-gpu-pci, hypervisor disabled. The recorded macOS path is
absent. No UTM/QEMU/guest process appeared in the bounded process-name inventory.
The saved `Suspended=false` flags are metadata, not live observations. Bookmarks
were not resolved, and guest disks, credentials and guest contents were not read.

The installed UTM scripting dictionary declares QEMU-only raw PC AT scan-code,
ASCII-keystroke and absolute mouse-click commands, plus a guest execution API.
None was invoked. A saved VM and a declared API do not establish a booted guest,
usable desktop, screenshot/input connection or focus isolation. The present
Linux config is also not a verified substitute for this macOS client: current
`window_input.c` reports focus/capture false outside Objective-C, and no guest
client/renderer/toolchain has been exercised.

CUA documents `pressKey`, click, drag and observations. It exposes no separate
key-down/key-up duration control or free relative-pointer-motion method in the
documentation returned here. A momentary key press cannot be assumed to satisfy
a held-key test, and a drag cannot be assumed to produce the intended captured
relative deltas without observing actual outcomes. The ready session needs an
observed physical-input lane or a demonstrated equivalent mechanism. The
documented CoreGraphics helper below prepares the latter but has not posted
an event or established actual delivery.

## Entry and launch boundary

The acceptance target is now the completed continuous `player_client.bend`
entry, joining Session, Presenter, renderer and the real-time driver.
`build/player-client/client` is 5,526,248 bytes, SHA-256
`dc23c1d632273ce59b26e7a67bc79bab7cbf94497d7d49d709bf9ae1f1a455f3`.
Its immutable artifact is
`build/platform-cache/artifacts/dc23c1d632273ce59b26e7a67bc79bab7cbf94497d7d49d709bf9ae1f1a455f3/program`.
`evidence/player-client-native.json` passes the recorded hidden integration:
22 native entry launches, 850 pre-draw frame descriptions, 48 MCP requests,
16 raw TCP requests, three exact saved bundles and startup/lease refusals.
These frame descriptions are not presented-pixel evidence. No held OS input,
focused capture or visible presentation was established by those runs.

Session source SHA-256 is
`e4d515442e9446aa308dee68630ef48755565562a2441052f54d3e422416e6d2`.
The final `player-session-native.json`, `player-session-reproduction.json` and
`player-session-audit.json` all report `passed`, including matching behavioral
manifests over two complete custom-bundle/neutral runs and five actual
publication-stage SIGKILL interruptions per run. The older Session/client
`prepared-native-unverified` preflights are historical preparation records.
Session's independent full kernel run remains a recorded foreign-boundary
refusal; no whole-client kernel theorem is claimed. The legacy `client.bend`
entry's per-key movement and `0.0025` Look shortcut are not this target.

Retain the complete `build/player-client/build.full.json` receipt and the
actual immutable artifact before a coordinated launch. The launch must use
`BEND_MINECRAFT_LAUNCH_MODE=human`, initially with `--gpu off`. This selects the
normal foreground Base path and normal capture requests. `hidden` preserves the
user's focus for routine automation but cannot supply ordinary focused input.
The verified source supplies this launch shape, conditional on the agreed
visible session; it was not executed here:

```sh
BEND_MINECRAFT_LAUNCH_MODE=human \
MC_WORLD_PATH="$visible_bundle_path" MC_WORLD_MISSING=create \
MC_LIVE_PORT="$visible_port" MC_DEV_TOKEN="$visible_fixture_token" \
"$visible_client_artifact" --gpu off -- \
  --verification-fixture --unpaused \
  --jar "$visible_pinned_jar" --sine "$visible_verified_sine"
```

Use an exclusive disposable bundle, an unused loopback port, the recorded pinned
26.3 assets/sine table and the newly verified player-client artifact. Record
their resolved paths and hashes. Reuse the verified artifact; no client rebuild
or foreground launch was performed by this capability task.

Bindings must match actual Base AppKit events: lowercase character codes and
modifier fallback `65536 + NSEvent.keyCode`. New `PlayerScene.bindings()` uses
119/115/97/100/32/65592/65595. These modifier values are source-derived; actual
physical verification is still needed. The Runtime harness's 340/341 modifiers
are separate fixture values. Record the real layout and emitted codes before
assessing modifiers. Escape is the
presenter's explicit release path; a primary-button click can request recapture.

## Dormant OS-input helper

`tools/visible_os_input.swift` compiles to `build/visible-os-input`. The measured
toolchain is Apple Swift 6.1.2 (swiftlang-6.1.2.1.2), with the installed
`MacOSX.sdk` resolving to macOS SDK 15.5. Source SHA-256 is
`4850508d835a7d91286d7b47f6c7a86ace35315f4e8782b046a3f3804890ef97`;
the 200,240-byte executable SHA-256 is
`475b6be4b3260758039c540177c7d18f9a13fbb1f3ffe89f0fce50303989304d`.
Compiler/header/SDK identities and the exact successful build command are in
`evidence/visible-os-input-capability.json`.

Default, `--preflight`, `--help` and `--plan` create/post no input events.
Thirty actual subprocess checks cover those modes, valid hold/relative plans,
the absent target PID and malformed/budget/duplicate options. All returned
expected statuses and reported zero posts and zero permission requests.
The source and native imports contain no permission-request function, app
activation, Unicode-text setter, event tap, global event-post function or
pointer-warp function. Armed delivery and handled-abort cleanup were deliberately
not executed, so this is preparation evidence rather than an input-success test.

The actual helper subprocess reports:

| Read-only check | Observed value |
| --- | --- |
| `CGPreflightPostEventAccess()` | `false` |
| `AXIsProcessTrusted()` | `false` |
| Selected input source | `com.apple.keylayout.US`, U.S. |
| Effective keyboard layout | `com.apple.keylayout.US`, U.S. |
| Unicode layout data | 5032 bytes, SHA-256 `464baf9b5025c0e060e45b1ceeafe45307e8be4c7a518d1bf4606edfecd98545` |
| HID modifier flags / six admitted key states | zero / all up |

Permission checks describe this executable/invocation's current access, not
future authorization or actual event delivery. The helper never asks macOS to
grant access. With post access absent, its armed guard refuses before posting.
The current fallback is a coordinated human physical-key hold and physical
mouse movement. Internal Bend packets or API movement commands are not a
substitute. A separately established permission grant would still require
rechecking this exact helper identity and observing actual client delivery.

Read-only planning is safe before arranging a session:

```sh
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/visible-os-input --preflight
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/visible-os-input \
  --plan --operation hold --keys w --duration-ms 300
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/visible-os-input \
  --plan --operation relative --dx 12 --dy -4 --moves 2 --interval-ms 60
```

Posting requires the literal arm phrase, a running target PID, its absolute
executable path and SHA-256, and matching current input/layout source IDs.
The helper binds process launch identity and file identity; it checks digest
before normal posts and checks target identity, foreground, access, modifiers
and layout throughout the operation. Normal posts are refused on focus loss.
No application is launched or activated by the helper. Supported physical
keys are ANSI-position W/A/S/D (13/0/1/2), Space (49) and Escape (53), with at
most two distinct keys and no Unicode override or generated repeats. Hold
duration is 20–2000 ms. Relative plans use nonzero integer deltas in [-64,64],
2–8 events at 20–200 ms intervals. A cooperative five-second operation budget
and at-most-10-ms polling bound apply; native framework calls are not a hard
real-time deadline.

The proposed future hold command, **not executed here**, is:

```sh
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/visible-os-input \
  --arm POST-TO-VERIFIED-FOREGROUND \
  --target-pid "$visible_pid" --target-executable "$visible_client_artifact" \
  --target-sha256 dc23c1d632273ce59b26e7a67bc79bab7cbf94497d7d49d709bf9ae1f1a455f3 \
  --expect-input-source com.apple.keylayout.US \
  --expect-layout-source com.apple.keylayout.US \
  --operation hold --keys w --duration-ms 300
```

The proposed relative operation uses the same guards, replacing the operation
options with `--operation relative --dx 12 --dy -4 --moves 2 --interval-ms 60`.
These source IDs must match a fresh preflight, rather than being silently
updated. The target path must be the actual launched executable. Capture must
be established and observed separately; foreground alone does not prove it.

Posting uses `CGEventPostToPid`, the documented process-specific OS event
stream before the target's event taps. It is not hardware HID input or a
simulation API call. The void API gives no delivery acknowledgement. Trace
entries therefore say `post_attempted_delivery_unverified`, with monotonic
times, target/foreground PID, physical key codes or delta fields. Relative
events keep the current global position fixed and set `mouseEventDeltaX/Y`;
there is no pointer warp. Whether AppKit/Base sees those fields as captured
`NSEvent.deltaX/Y` remains unmeasured until actual response is observed.

Matching key-ups are prepared before any key-down and attempted through a
single deferred cleanup path on completion and handled SIGINT/SIGTERM/SIGHUP
or refusal. Cleanup targets the original verified PID even after focus loss,
with an explicit `cleanup` trace phase. Target exit/reuse, SIGKILL, crash or
revoked access can prevent a delivered key-up; the helper cannot guarantee OS
delivery. Cleanup rechecks process identity rather than the on-disk executable,
so a changed executable file stops normal input without suppressing release to
the same live process. Its cleanup was not tested in armed mode. A client's held state
clearing after this cleanup does **not** prove the client's own focus-loss
release behavior. Use the independent human focus-loss lane below, or establish
release before any helper cleanup, and record which occurred first.

## Ready-session scenario

Use a disposable Overworld scene/session and retain its manifest. The existing
39-block fixture has a floor at y=0 over x/z=-3..2, a dirt cube at (1,1,1), and an
oak-plank column at (2,1,2)/(2,2,2). The neutral saved-player start is
(0.5,1,-2.5), standing dimensions 0.6 × 1.8, zero degree view, sensitivity 0.5,
inversion off, smoothing off and scoping off. The final entry must confirm and
admit this setup. Run Core unpaused with the actual 50 ms actor timer; avoid
manual `simulation.step` calls during the continuous-input evidence lane.

1. Record executable/source hashes, actual window/foreground context, settings
   and input surface. Launch the normal visible client and inspect its presented
   scene, geometry and scale.
2. Establish actual capture. Observe the first captured movement discard and a
   later movement's actual raw-degree response; retain visible frame evidence.
3. Hold forward across several distinct simulation ticks and release well before
   the floor edge. Check held-state clearing and cessation of input acceleration;
   existing velocity may decay through physics. Repeat backward, strafe and an
   opposing-key combination, correlating actual OS events with body/view state.
4. Align with the dirt cube and hold toward it. Observe collision without
   penetration, then a ground jump and landing. Record body/collision flags and
   visible outcomes rather than camera displacement alone.
5. Escape, observe release, click to recapture and observe first-move rearming.
   Use the independent human-input lane to lose focus while a movement key
   remains physically held; observe Runtime release before the human key-up,
   release it in the other app, return and recapture. Do not count the helper's
   abort-cleanup key-up as evidence of Runtime's own release. Verify actual
   focus/capture transitions and no stuck input;
   do not infer that losing focus pauses the simulation.
6. Close while captured and verify pointer recovery, cleanup, process exit and
   listener release. Reopen. With the Session entry, additionally verify admitted
   body/support/view restoration and clearing of ephemeral keys/mouse state.
7. Compare representative observations with pinned Java 26.3 under matched
   admitted scene/settings. Record differences and the limited neutral scope.

Keep timestamps, actual event/focus/capture provenance, simulation ticks and raw
controller/body/view diagnostics together with screenshots or other visible
presentation artifacts. Synthetic Bend packets, TCP stepping, hidden pixels and
Java method fixtures supplement this evidence; they do not replace the actual
OS-input lane. This smoke does not establish full LocalPlayer behavior, complete
UI, vanilla saves, audio, latency, multiplayer or whole-game parity.

## Coordination still needed

The repository's `VISUAL_ACCEPTANCE.md` says to “coordinate that specific visible
session with the user when the scenario is ready” if OS interaction takes their
foreground. With the currently exposed host surface, the proposed normal-focus
launch/capture and deliberate focus-loss test will do so. The verified entry
and dormant input plan are now concrete; arrange that bounded interruption,
or first demonstrate a compatible isolated guest with an actual screenshot/input route.
No foreground session is authorized or scheduled by this preflight itself, and
the helper's arm phrase does not grant that foreground-session authorization.

`evidence/visible-input-preflight.json` records the read-only methods, narrow
inventory projections, source/receipt hashes, unresolved capabilities and exact
test boundary for the original inventory. `evidence/visible-os-input-capability.json`
records the follow-up helper build, read-only observations, refreshed Session
and client identities and the remaining delivery/permission boundary. No
foreground launch, posted input, permission prompt or commit occurred here.
