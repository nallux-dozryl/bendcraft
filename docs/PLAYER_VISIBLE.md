# Bounded manual/CUA visible smoke

The early smoke orchestration is prepared. **Visible acceptance remains unverified.**
No app was registered or launched, no UI action/input post/permission prompt was
performed, and no screenshot was taken during preparation. Confidence is high
for the content/dependency audits and actual Java reference observations; actual
visible input, presentation and wrapper association remain unobserved.

`tools/test_player_visible.py` owns only orchestration and observations. Default
preparation creates a disposable fixture/app and runs actual Java reference
methods. `--audit` reads and verifies prepared files. `--run` attaches to an
already launched, explicitly authorized target. It does not launch the app,
activate anything, post keys, move/click the pointer, capture screenshots, kill a
process or call `simulation.step`.

```sh
python3 tools/test_player_visible.py --prepare
python3 tools/test_player_visible.py --audit
```

The verified normal CPU client has SHA-256
`dc23c1d632273ce59b26e7a67bc79bab7cbf94497d7d49d709bf9ae1f1a455f3`
and cache key `cc54411dd05d4dff64679237368f48fb64540916138cc7c16f45ffbf29d9eac4`.
Preparation audits all 3,678 recorded native dependencies, lookup identities,
content/sizes, compiler/platform policy, original/transformed C, cache receipt,
assets and executable. The frozen Entry, Scene, Runtime and Session are unchanged.
The app contains an exact binary copy; it is not a recompiled or transformed build.

The exclusive mode0700 fixture directory is under ignored
`build/player-visible/session-…/`. It contains the independently encoded/admitted
Core+PlayerRecord bundle, a mode0600 private disposable token, wrapper and future
logs. The 39-block scene has tick1/revision47/paused Core and body `(1.5,1,-0.5)`,
zero look/velocity, facing the dirt cube `(1,1,1)`. This is the declared neutral
plain Player test profile (.1d movement, .08d gravity, .42d jump), not LocalPlayer.
The existing loaded Core prevents terrain/body reinitialization. Do not hold
backward or strafe indefinitely near this finite floor's edges.

Preparation creates `Minecraft Player Smoke.app`, bundle identifier
`local.bendex.minecraft.visible-smoke`. Its recorded absolute path is
`plan.app_path_for_later_cua_binding` in
`evidence/player-visible-preparation.json`. The generated Python launcher is
syntax-checked, content-pinned and dormant; its interpreter is also content-pinned.
No LaunchServices registration or CUA app binding occurs now. Actual app
association is a future observation, not guaranteed by the plist alone.

The launcher reads a private root/human coordination grant, verifies this final
preparation digest, wrapper/native/resource hashes and expiry, and uses fixed
shell-independent environment/argv. It copies the token into the child environment
without logging it. `BEND_MINECRAFT_LAUNCH_MODE=human`, two threads and GPU off are
fixed. Initial launch has `--unpaused`; restart omits it to preserve saved pause.
No arbitrary command-line or environment values are accepted. Logs go directly to
phase-specific fixture files, preventing stdout-pipe blockage. The launcher
executes the pinned Mach-O in the same PID and records its process start time.

Only after root and human explicitly coordinate the foreground interruption:

1. Root writes the mode0600 launch grant named by the preparation. Required fields
   and exact values are recorded in `plan.launch_authorization_required_fields`.
   The grant must cite actual human coordination, pin the final preparation SHA,
   select `manual-and-cua`/`human`, name this app, set `launch_phase=initial`, expire
   at a timezone-qualified time and bound the entire session to at most180seconds.
   Preparation creates no such grant.
2. Root uses the documented CUA native app binding/launch on that exact app path.
   The observed PID comes from `initial.launch.json`; verify its actual executable,
   copied binary digest and start time. This uses the user's foreground and normal
   capture branch. Follow `docs/VISUAL_ACCEPTANCE.md` and
   `docs/VISIBLE_INPUT_PREFLIGHT.md`; an isolated controllable desktop has not been
   demonstrated.
3. Root writes a separate mode0600 observer grant with the same coordination/pins
   plus actual `target_pid`, exact `target_executable` and `launch_phase`. Execute
   the exact argv in `plan.observer_command`. The observer attaches; it never
   launches or controls UI. Reuse the single initial launch deadline across both
   initial and restart phases.
4. Human performs short W hold/release toward the cube and a short ground jump;
   CUA retains actual screenshots and can use its documented momentary Escape,
   click/recapture and close operations. Human supplies physical held keys and
   free mouse movement because documented CUA has no held-duration method.
5. Release all physical keys; pause and save through authorized observer commands.
   Close through the normal visible route. The observer records actual process
   exit, listener refusal and exact independent bundle bytes. Root changes only
   the launch grant to `restart`, reopens the same app within the original budget,
   attaches an observer with the new PID and checks paused restoration, screenshot
   and close. The dormant launcher requires the initial observer's verified save
   and observed exit before permitting restart.

The observer commands, after coordination and target verification, are:

```sh
python3 tools/test_player_visible.py --run --authorization <private-observer-grant>
python3 tools/test_player_visible.py --authorization <private-observer-grant> --command pause
python3 tools/test_player_visible.py --authorization <private-observer-grant> --command resume
python3 tools/test_player_visible.py --authorization <private-observer-grant> --command save
python3 tools/test_player_visible.py --authorization <private-observer-grant> --mark "Human released W"
python3 tools/test_player_visible.py --authorization <private-observer-grant> --mark "CUA scene screenshot" --screenshot <existing-image-path>
```

Commands are exclusive private files consumed by the observer; command submission
also verifies the current target PID/path/start time and grant. `snapshot` marks an
observation and `abort` stops the observer. Existing CUA screenshots are hashed and
retained with target identity; this tool never acquires one. Root's CUA/human record
must supply actual window identity and screenshot provenance. A declared marker
alone does not establish physical input delivery.

Actual loopback TCP polling authenticates with the private token and checks the
exact18-operation Session catalog. Authentication args are omitted from all logs.
Polling records clock-before, canonical raw Record bytes, clock-after and monotonic
intervals. A tick between calls is explicitly marked; a paused owner must retain
its clock. Only normal `simulation.pause` and `world.save` controls are allowed.
The movement lane uses the real actor50ms timer; API stepping is forbidden.
The saved paused bundle is compared byte-for-byte to an independent NBT encoding
of the prescribed unchanged scene, observed Core header, canonical Record and
actual durable peer highwater. Restart checks exact saved Record/Core and durable
bytes; it does not infer transient held/capture state from persistent bytes.

When a separate read-only NSWorkspace observation reports the verified target
frontmost, the observer may execute the dormant helper's `--preflight`. It retains
HID key states only if the helper and subsequent PID identity agree. This never
uses `--arm`, posts events, creates input-event objects, installs an event tap or
requests permission. The final helper receipt verifies 30 read-only cases and
current post/accessibility checks are both false. Actual human holds must establish
whether the HID readout is available and responsive; prior all-up samples cannot
do that. Reading a held key still does not prove AppKit delivery or capture.

Five actual untouched Java26.3 receiver cases supply60unique steps, each repeated
in a fresh process (120observed steps). They cover short forward/release, neutral
opposing-input and collision/jump from the admitted scene. The fixed collision
trace collides at ticks8–10 and observes a ground jump call at tick9. These are
conditional expectations: initial body/support/yaw/profile and actual per-tick
input must match. Nominal human hold duration is insufficient. Input metadata is
Player.aiStep output, not the hidden raw button state. Missing tick history prevents
an exact raw-bit sequence claim; actual body/input/look response, finite collision,
jump/landing and release can still establish their narrower observed scope.

The planned session can cover presented geometry, actual manual held/released
movement, timer-driven collision/jump, raw look changes, Escape/click response,
normal close and exact custom save/paused reload. It cannot establish internal
capture/ignore-first flags or first-move discard without independent observability.
Those gaps do not indefinitely block the early smoke. No broad UI, inventory,
LocalPlayer/full-game behavior, audio, latency, multiplayer or vanilla-save claim
is made. A pre-draw frame description is not a screenshot; CG process-post traces
would be attempts rather than delivery, and this lane uses no CG posts.

Observation files and future reports remain under the ignored fixture directory.
They initially have `observed-visible-session-unreviewed` status; running the tool
does not automatically certify visible acceptance. The observer stops on its
single bounded deadline, identity/content error, finite-floor safety violation or
root abort. It never releases human keys or closes/kills the app itself. Root and
human must perform the coordinated release/close promptly; any forced recovery
must be recorded separately and cannot establish normal-close/pointer recovery.
