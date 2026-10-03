# macOS launch boundary

The pinned Bend 2.0.35 Base window effect has no launch-policy argument. Its
macOS `window_make` always makes the window key, orders it to the front, and
calls `activateIgnoringOtherApps:YES`. A preceding configuration effect alone
cannot bypass those statements. Automated launches must therefore use the
project build adapter rather than a direct native `bend -o` build.

## Build and launch

From the Minecraft project root:

```sh
python3 tools/platform_build.py tests/platform.bend -o build/platform-probe \
  --report build/platform-build.json
BEND_MINECRAFT_LAUNCH_MODE=hidden build/platform-probe --gpu off
```

Integration uses the same build command with the real client entry point.
`--bend PATH` and `--cc PATH` select the executables. `-o OUTPUT.c` emits the
transformed C for inspection instead of building a native executable. Entries
without a reachable Base window implementation should use ordinary Bend
builds; this adapter is specifically for macOS native windows.

| Process launch environment | Behavior |
| --- | --- |
| Variable absent, or `BEND_MINECRAFT_LAUNCH_MODE=human` | Base's original Regular application policy and foreground window activation. |
| `BEND_MINECRAFT_LAUNCH_MODE=hidden` | Prohibited application activation policy; creates the normal Base NSWindow and Metal layer, but never orders it, makes it key, or activates the application. |
| Any other value, including an empty value | `Window.open` fails with `EINVAL` before application setup or window creation. |

Set the mode before starting the process, and keep it fixed for that process.
The hidden path assumes Base owns initial NSApplication setup, as it does in
the tested native client. It is a display-session test mode, not a headless
window replacement: Base still requires a display and a Metal device. All
automated client execution must explicitly set `hidden`. The build command
does not launch the client; GPU sidecar generation invokes only the pinned
runtime's `--gpu-build` path and also sets the hidden environment.

Human play retains the normal Base input/focus path. Automated tests do not
exercise that path because doing so would intentionally take focus. The
adapter does not provide a visible background window or test keyboard/mouse
input. Hidden clients cannot receive normal focused input.

## Transformation guard

`tools/platform_build.py` first asks the verified installed compiler to emit
C. It checks all of the following before changing that output:

- The compiler executable SHA-256 is
  `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`.
- `bend version` reports exactly `bend 2.0.35`.
- Exactly one complete emitted Base window effect source is present.
- Its SHA-256 is
  `9cd6435eb582b65deca88afe1ddc8a4d9700f21347acbcf086fc19611cc1c4ba`.
  This is the complete pinned `window.c` after Bend substitutes its stable C
  constructor names, not a digest of only the activation statements.
- Each replaced statement occurs exactly once, and the source has not already
  been transformed.

It adds environment validation inside the macOS `window_make`, chooses the
application activation policy, and places the existing two foreground calls
inside `if (!hidden)`. Every other part of Base's window implementation,
including its Metal rasterization, ownership, events, close behavior and Linux
branch, is retained. The full runtime is neither vendored nor forked. No file
in `../bend` is edited.

Native compilation follows the pinned Bend CLI's macOS Objective-C flags. A
program containing `!` adds `BEND_METAL=1` and builds the GPU sidecar with the
runtime's `--gpu-build`. Reports include compiler, emitted-C, transformed-C
and executable digests. A compiler update, rebuild with a different binary,
or changed emitted window source is rejected and requires a deliberate
review of this narrow adapter.

## Verification and evidence

```sh
python3 tools/platform_test.py
```

The test checks the exact pinned source, preservation of the human foreground
calls, and rejection of changed behavior, duplicate source, missing source
boundary, and repeat transformation. It then builds a separate Swift AppKit
observer. That observer starts a native Bend child, samples the frontmost PID
every 20 ms, and listens for application-activation and active-Space-change
notifications. It does not activate an app, order a window, click, type, move
the cursor, or capture the screen.

`tests/platform.bend` calls Base `Window.open`, Base `Window.frame`, and Base
`Window.close`. The narrow foreign effects in `src/platform.bend` and
`src/native/platform.c` report the observed native window's visibility, key/main
flags, application activation policy, active state, frontmost PID and Space
notifications. Their JS sibling explicitly reports `native_macos:false`;
Base JS window creation remains unsupported.

The recorded test on 2026-10-03 used macOS 26.4.1, Apple clang 17 and the pinned
compiler. Four actual native runs passed: a CPU window probe, invalid-mode
rejection, a program containing a bang run with `--gpu off`, and that same
program forced through Metal with `--gpu on`. Across those runs the external
observer sampled 98 times. The frontmost PID remained `83354`, no child
activation or Space-change notifications were observed, and each successful
window was invisible, nonkey, nonmain and inactive with activation policy `2`.
Each successful Base frame call returned. Exact observations and commands are
in `evidence/platform-launch.json`.

Confidence is high that the tested adapter takes the hidden launch path and
preserves the human branch's original calls. The finite focus and notification
observations do not prove that every possible transient OS change is absent.
A hidden CAMetalLayer can have no drawable; a returned Base `Window.frame`
does not prove that pixels were presented or establish rendering fidelity.
Forced GPU execution tests the adapter's native/GPU build path, not Minecraft
rendering or performance.

## Proof boundary

These diagnostics are foreign effects. `bend tests/platform.bend --check-only`
correctly exits `1` and reports `SOME PROOFS FAIL` for the five definitions that
rely on them. The native build passes the live code checker and runs, but no
Bend law proves AppKit, focus, Spaces, Metal or these native observations.
There are no axioms or placeholder proofs. No Minecraft gameplay, UI, audio,
renderer or Java parity is established by this platform test.
