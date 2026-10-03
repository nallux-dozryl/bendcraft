# Visible native client acceptance

Full completion requires recorded end-to-end inspection of the **actual visible
native client** using computer use or demonstrably equivalent real OS input and
presentation automation. Hidden render readback, pure pixel comparisons,
synthetic Bend events, reference oracles and proofs remain part of verification.
They do not demonstrate that the OS presents the intended window or that real
keyboard/mouse capture, release and interaction work.

This makes the verification method explicit within the existing full fidelity
goal. It changes neither feature scope nor implementation priority, and creates
no intermediate completion gate or milestone stop.

## Session policy

Routine automated launches continue to use the guarded `hidden` mode and must
preserve the foreground application and Space. Do not start a foreground client
merely to collect evidence. First establish whether an isolated controllable
desktop is genuinely available. Do not infer isolation from a hidden window,
another Space, virtual display, remote session or unfocused window. If the
required OS interaction unavoidably takes the user's foreground, coordinate that
specific visible session with the user when the scenario is ready. Approval of
the implementation does not silently waive the focus constraint.

Use the native human input/presentation branch during the coordinated session.
Exercise capture and release deliberately, retain the expected exit/recovery
path, and record the actual automation surface and foreground context. Both
visible acceptance and focus preservation remain requirements.

## Progressive schedule

| When | Required visible scenario | Evidence scope |
| --- | --- | --- |
| Stable controls path | Launch actual native window; inspect presentation; real keyboard press/hold/release and mouse movement; capture/release; continuous movement, jump and collision; close/reopen | Early smoke evidence for the implemented controls and scene only |
| Relevant UI becomes usable | Menus, HUD, inventory interactions, settings, text entry, scaling, accessibility and error/recovery flows | Each implemented flow, including real focus/input transitions |
| World and persistence integration | Actual world edit; save; close/reload; observe restored state and relevant player state | Visible integration combined with codec/interruption tests |
| Multiplayer integration | Actual client-to-server sessions, other player interactions and state synchronization | Visible multi-client behavior combined with transport/scenario evidence |
| Presentation/content expansion | Representative geometry, materials, lighting/transparency, equipment, particles, dimensions and modes under relevant settings | Recorded comparison against the pinned vanilla build; explicit unresolved differences |
| Packaged client ready | Repeat representative end-to-end paths from the package, including launch/input/close/reload and settings | Package behavior; previous development-binary checks do not substitute |

Begin the bounded smoke scenario when controls are stable enough. Expand visible
checks alongside feature work; do not defer every visible test to the final
package. A few successful scenes never establish complete vanilla parity.

## Record and compare

Each record must identify the source/build and executable digest, native window
mode, OS/automation surface, scenario/world/seed, game mode, relevant settings,
resource/data packs and mods, input steps, observed outcomes, screenshots or
other presentation artifacts, defects and exact covered/uncovered scope. Pin
the reference to Java 26.3 with matched scenario/settings where comparing it to
the Bend client. Record material mismatches rather than reducing their scope.

Screenshots establish only the visual observations they show. Audio playback,
mixing, timing and device behavior require suitable separate listening/capture
or measurement evidence. Input/frame latency requires actual timed events and
presentation observations; frame appearance alone establishes no latency.
Equivalent-workload performance comparisons retain their separate contract.

## Current state

No recorded visible native end-to-end acceptance session has run. Hidden native
launches, independent framebuffer comparisons, synthetic controller checks and
actual TCP/MCP/save/restart tests cover their stated bounded scopes. The new
actual player tick/held-input path is still being implemented. The next visible
step is a bounded smoke scenario once that path is stable, using the session
policy above. Visible acceptance remains **unverified**.
