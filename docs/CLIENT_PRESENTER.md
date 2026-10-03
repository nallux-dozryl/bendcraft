# Shared actor presenter verification

The presenter connects an owned server state to native frames through `Driver<State,Frame>` and `Renderer<Frame,Assets>`. A snapshot returns the next owned state and either a `Frame` or a string error. Input receives one `ClientControls.Packet` for the entire native event batch. The frame policy controls capture requests during frame input. The renderer returns its assets on both success and failure and supplies an asset-close callback.

The implementation queries actual focus/capture after grab attempts and after each native frame. It adds logical `Release` actions for loss of previously recorded capture, Escape, Close, and final cleanup. This is necessary because the pinned Base event stream has no focus-loss event. Actions accumulated during event processing are reversed before the single actor call.

## Reproduction

```sh
python3 tools/test_client_presenter.py --prepare-only
python3 tools/test_client_presenter.py --build-timeout 600
```

The first command performs only ordinary checking. The harness reaches the exact 38 declarations that depend on native or explicitly unsafe code; it has no other typing or affinity error. This is not a whole-module kernel verdict. The second command uses the unchanged `tools/platform_cache.py::ensure_platform` guarded macOS CPU Window route. It bounds the build subprocess group to 600 seconds, retains its complete dependency receipt, and runs each of fourteen scenarios twice. No other Bend test module is imported.

All automated executions set `BEND_MINECRAFT_LAUNCH_MODE=hidden`. They use real AppKit windows, Base `Window.frame`, native focus/capture observations, and the shared `Server.start_handle` actor and timer. The independent existing AppKit observer samples the foreground application and records activation and Spaces notifications. Native in-process observations additionally check that inspected windows are invisible, not key/main, and use the Prohibited activation policy. The `open` wrapper scenario is checked by the external observer and actor-reported native frame flags without a separate window inspection.

The Bend harness owns a paused `Core.World`, counters, audit trace, and a File-backed renderer asset. Two explicit actor operations establish tick 2 before presentation. At least four real timer pulses must run during the initial 250 ms delay. TCP developer `world.clock` queries and every snapshot/cleanup report must retain tick 2. Since explicit `Core.step` advances even paused state, an accidental presenter step would fail this check. Python only starts processes, exchanges actual live requests, reads marker files, and compares fixed expectations; it implements no presenter or simulation behavior.

## Scenarios

| Mode | Scenario | Required result |
|---|---|---|
| 0 | Three normal frames | Three snapshots/draws and three frame packets, followed by one final release packet |
| 1 | First snapshot fails | No draw; release and asset close precede error exit |
| 2 | First draw fails | Returned assets reach cleanup after one attempted draw |
| 3 | Input callback rejects | Presenter logs each rejection and continues to the bounded frame limit and cleanup |
| 4 | Human capture requested, frame policy denies | Hidden native capture remains false; every frame policy is false |
| 5 | Synthetic held-key/look/click/Escape/Close batch | One actor packet, original action order, releases retained, events after Close discarded |
| 6 | Synthetic click requests capture | Actual hidden capture refusal appears in the click and subsequent key action |
| 7 | Synthetic prior-capture flag with no current focus | Real native status is false; empty event list produces one release |
| 8 | Injected `opened(Fail)` | Release, asset close, actor stop, and injected error code; no window was allocated |
| 9 | Second snapshot fails | The first real native frame completes; assets survive into failure cleanup |
| 10 | Second draw fails | The first real native frame completes; second attempted draw returns assets to cleanup |
| 11 | Public `open` wrapper | One bounded native frame and cleanup |
| 12 | `Some(0)` frame budget | No frame snapshot, draw, native frame, or frame packet; final release and full cleanup still run |
| 13 | `Some(1)` frame budget | Exactly one frame |

For the synthetic scenarios, Bend supplies the explicit event list to `frame_input` after a real native frame and reports the actual physical event count separately. The audit trace distinguishes `Release`, event order, key state, and per-event capture. A report before cleanup requires exactly one packet for the full batch. The close callback queries the same actor after final `Release`, writes its counters/trace and native post-close platform observation to the owned marker File, and closes that File. A missing callback, early actor stop, or dropped asset prevents the required marker from being produced. `harness.frame` diagnostics describe successful snapshot values before drawing; a failed draw can therefore produce a frame description without reaching `Window.frame`.

The live listener is checked to be inaccessible after process exit. `Server.stop` closes the actor and stops future timer sends, but its accept socket may remain parked until the process exits; the test does not claim that `stop` independently releases that listener. The marker establishes invocation and ordering of the renderer cleanup callback, not an exhaustive native-resource count.

## Evidence boundary

All 28 native executions passed. The zero-frame runs recorded zero snapshots/draws and one final release packet. Every final marker retained paused tick 2, with 5–22 timer pulses observed, and every process released its live listener after exit. No foreground change, child activation, or Spaces notification was observed. Guarded C emission took 6.50 seconds and native compilation 5.43 seconds; these are build measurements, not gameplay performance claims.

Native results, exact source/binary/adapter hashes, all 3,642 build dependencies, TCP replies, platform observations, marker contents, and diagnostics are recorded in `evidence/client-presenter-native.json`. The tested presenter source is SHA-256 `c86d607b6a68f34d20d7fe19f4c81d88314ad942422e7246ec8f3c993eb8e2e4`; the binary is `1dc327159012eb24bf9aadf0223366547b9e8e4b6543901798e4a5cee9b1b66d`. Confidence is high for the bounded recorded scenarios. The record explicitly distinguishes ordinary admission through the native boundary from a kernel proof.

This harness does not establish visible presentation, real keyboard/mouse input, successful focused capture, or an actual focused-to-unfocused OS transition. Mode 7 supplies the previous-capture flag synthetically and tests the release branch against real unfocused native state. `opened` requests initial capture from the human-launch flag before the first snapshot/policy check; mode 4 observes refusal in the hidden window and later policy denial, and cannot establish focused capture behavior during that initial interval. The open failure is injected into the existing callback; it is not an observed AppKit allocation failure. Required visible OS-input acceptance remains governed by `VISUAL_ACCEPTANCE.md`.
