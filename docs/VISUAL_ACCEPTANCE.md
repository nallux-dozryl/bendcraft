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

## Cooking delivery: actor023 and client012

This is a prepared visible run, **not an executed acceptance record**. Confidence
is high for the source-derived gestures below. Actual window presentation,
physical input delivery, capture/release and the visible cooking/save/reload
sequence remain unverified. The existing actor022 publication/save/cold-restart
and SceneFrame TCP receipts cover their stated scopes; they do not supply these
OS observations.

### Candidate pins and foreground boundary

The previously verified immutable actor022 is
`build/compiler-producer-diagnostic-022/actor`, 16,246,616 bytes, SHA-256
`1ba545e7ccd84e5011f51199c2ee9562e4063c24b98c64148323551039357712`.
Its source map is SHA-256
`95acf6a8c10c4f0eca5c696ef9126a5bfc27cdec36806288147714e2510835db`,
recorded in [the native build receipt](../evidence/playable-client-actor004-build-022.json).
Its earlier bounded consumers remain valid, but the normal ambient cooking
caller exposed a required lease defect: callback run009 accepted sequence
98 with two cooked beef, then refused the correct next sequence 99 Input before
the output take. The run used normal ambient ticks with no host pause. Full CPU
frame 28 is retained at 90.4008217 seconds; it is not an OS screenshot or a
successful take/close/save/reload observation.

The changed native actor is
`build/compiler-producer-diagnostic-023/actor`, 16,246,584 bytes, SHA-256
`7fd7ee9269802a6e128716f53bf34030ec592728ef954f9b61bebecac36719d1`.
Its source-map SHA-256 is
`1508c034ab9b614551ef2353bfbd5de434b0111e51c2ef1790803b0deb9c97f2`.
The sole change removes Backend runtime pulse charging: every actual Scene
pulse remains, as does the real 5,000 ms transport idle timeout. The actual
socket idle/EOF/epoch/replay suite passed. These facts do not establish
presentation or cooking timing parity.

The production client is
`build/generic-resource-world-sample-client-native/012/renderer`, 6,986,328
bytes, SHA-256
`3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232`.
Its source-map SHA-256 is
`ec255df0c52c6214aeece182c7ac92276c0c00ce2a59dd0769f3faadbc6d4e7c`.
It combines the immutable client010 baseline, the actual Generic cooking caller
and only the verified block-model scanner repair. Client011's 600-second
scanner timeout and client012's first Apple O3 stack-probe crash are retained
failures. The same generated C then compiled successfully with O3 and
`-fno-stack-check`; that flag is part of this candidate's recorded build, not
evidence of OS behavior.

Actual ambient callback run011 completed the full functional cooking flow,
durable save and cold stage with this 023/012 pair. Its observer ran for
107.234 seconds without a focus or Space change. This is **synthetic UI
consumer evidence only**. The outer duplicate-relay-receipt cleanup failed;
that original failure is retained and cleanup was finalized without new
gameplay or compiler runs, as recorded in the
[retained callback receipt](../evidence/generic_resource_world_sample_cooking_runtime_002.json).
The original outer run is not relabelled a success. There is no OS acceptance
claim.

Material timing remains unresolved: two recipes with 200 cooking ticks each
took **67.009 seconds** in the actual callback run. This is substantially slower
than the intended simulation cadence. Do not report achieved 20 TPS or a
20-second cooking flow for this artifact. Record wall time and actual tick/
progress observations separately; timing parity remains open.

The **original-binary public launcher run001 passed** with this actor023 and
production client012, recorded in the
[public launcher receipt](../evidence/generic_resource_world_sample_cooking_launcher_runtime_001.json).
It produced two complete 960 by 540 CPU frames, performed actual close/save at
peer high-water 42, cold-loaded and independently reconstructed all 104
sections, all 43 durable inventory cells, raw status, world-generation settings,
furnace bodies, effects, entity and publication owners, then saved at high-water
44. Its own process groups and listeners were absent after cleanup; the old
baseline was preserved. The source-None/max-peer oracle negatives are retained,
and the public shell run was not replayed. CPU frames and the test-only native
callback queue remain separate from actual OS presentation/input evidence.

The adopted public launcher `tools/play_minecraft.sh` is 6,490 bytes, SHA-256
`6c69f6999554e43e205e87c04d72cf664dc27e8690e4fc3aee905ca4fe1e45c0`.
The cooking demo `tools/play_minecraft_cooking_demo.sh` is 1,695 bytes, SHA-256
`4542830092ac941bb231817e5c1f80d4f83b88993b8e7abaab7e5bb8f0f7cc2c`.
The demo validates the actual pair and seed, copies the seed into a new
world directory with a permission-0600 save, and prints its unique saved-world
reopen command. That protects older saves. These pins and the public run make
the prepared foreground scenario concrete; they do not establish its OS
acceptance.

The validated unpaused demo seed is
`build/generic-resource-world-sample-cooking-runtime/011/demo-seed.nbt`,
1,712,794 bytes, SHA-256
`e88e15ab0267beb9fea4ad55c9b9b7cd3cca27eea0cf5a3cc6d7b59a2ad1b859`.
Compared with its controlled source seed, only the Core.paused byte at offset
330 changes to zero; all 104 terrain sections, 43 durable player inventory
cells and furnace owners are retained. This is the initial demo image, not a
successful cooking-run save. The paused controlled seed is not a substitute
for it.

The prepared human launch command is the following. It is **not executed by this
preparation**; foreground coordination remains required:

```sh
BEND_MINECRAFT_LAUNCH_MODE=human \
  /Users/chuah/Documents/ChatGPT/bendex/minecraft/tools/play_minecraft_cooking_demo.sh \
  --width 960 --height 540 --render-scale 100
```

HUD scale 3 is already the demo's default. Retain its printed new save path and
reopen command. For step 10, reopen that saved world with the printed public
launcher route and the same display options, including `--hud-scale 3`; do not
run the demo again, which creates a fresh world instead of reloading the save.

Prepare the candidate and its exclusive disposable world before asking for
foreground access. Reuse the verified binaries and the existing launcher and
close/save helper; no new controller framework or rebuild belongs in this run.
Select unused loopback ports, retain their owning PIDs, and leave the older
baseline processes and the user's default `build/playable-world.nbt` untouched.
Record the actual pinned Java 26.3 jar, registry, item table, sine table and
candidate settings. Use the human launch mode, CPU renderer and a **windowed**
presentation; record measured content, drawable and HUD extents. Do not switch
Spaces or enter fullscreen. The prepared interactive candidate requests
960 by 540 geometry. The demo CLI supplies `--hud-scale 3` before caller
overrides: the 176 by 166 logical panel has a nominal scaled extent of 528 by
498. Record the final effective settings and measure actual
content/backing/HUD extents instead of assuming these are all the same units
or that nominal scale determines global OS click coordinates.

No isolated controllable desktop has been established by the existing
[input preflight](VISIBLE_INPUT_PREFLIGHT.md). The unavoidable action is to
present and focus the actual client on the current desktop, send real keyboard
and mouse input, briefly switch away to test release, then close and reopen it
on the same save. Request **up to ten minutes** of coordinated foreground use
for both launches, the cooking sequence and cleanup. This is a planning budget,
not a measured runtime. Return to the previous foreground application at the
end. Root has now asked for this single coordinated foreground session and the
response is pending. Do not treat elapsed time as an answer or approval. No
window, input, focus or Space action was performed while preparing this section.

Use **`cua_repl` for all agent-operated UI interactions** in the coordinated
session, following its documented API. Do not use the dormant Swift
CoreGraphics helper, AppleScript or another input synthesizer as a substitute
unless the human specifically requests that mechanism. The current CUA API
documents discrete key/click/drag/screenshot actions but no separate key-down
and key-up duration controls. Therefore a verified held-key duration or a
focus transition while a key is held is **not promised by this run**. Leave
those observations unverified unless an actually supported input mechanism is
available and its outcome is observed. Likewise, do not equate a drag with
captured relative camera motion without observing its real effect. An internal
Bend event, callback injection, TCP command, momentary key press, cleanup key-up
or CPU framebuffer dump is not the corresponding OS acceptance observation.

### Fixture and actual menu coordinates

The saved fixture must contain an empty, ordinary furnace on a resident flat
floor, with the player standing within the actual interaction range and aiming
at it. Catalog's prepared GUI fixture has the empty unlit overworld furnace at
`(12,8,12)`, player feet at `(12.5,8,10.5)`, yaw zero and pitch 30 degrees. Its
104 authentic superflat terrain sections cover x origins 0/16 and z origins
-16/0 across 26 vertical sections; the requested aperture is x 8..15, y 4..11,
z 6..13. The furnace collision/light scan halo is resident. Main inventory
slots 0/1 contain two plain `minecraft:beef` and two plain `minecraft:coal`,
which appear as cooking menu cells 30/31. Empty cells remain for returns and
output. These fixture facts are pinned by the unpaused demo image above and
retained through the accepted original public run. Visible OS acceptance
remains pending. Do not silently substitute the paused publication fixture.
Setup is fixture preparation, not an observed world edit or acquisition of
those items.
The furnace body must use the normal initialized recipe/speed profile with no
accelerated cooking component. Before interaction, verify that the shared
simulation is unpaused and the ordinary beef recipe has its actual 200-tick
cooking total. Progress must come from the actual ambient simulation path,
not explicit `simulation.step` calls or frame polling. Fifty milliseconds is
the intended tick cadence, not an established achieved cadence for this pair;
retain the measured 67.009-second two-recipe observation above.

The actual `player_cooking_menu_screen.bend` panel is 176 by 166 logical HUD
units, centered in the measured HUD viewport. Input, fuel and output are slots
0, 1 and 2 with top-left offsets `(56,17)`, `(56,53)` and `(116,35)`; each hit cell
is 16 by 16, so click its center by adding `(8,8)`. Player slots 3 through 29
start at `(8 + 18*column, 84 + 18*row)`, and hotbar slots 30 through 38 at
`(8 + 18*column,142)`. Identify the actual beef/coal cells from their visible
icons and the retained fixture inventory, not from an assumed slot number.
Convert the measured window content coordinates through the actual drawable
extent and then the HUD extent, preserving both floor operations in
`player_presentation.native_event` and `CookingScreen.hit`. These are content
coordinates with a top-left origin, not global display pixels. Targeting must
agree with the visible slot/hover feedback; do not reuse another window's
absolute coordinates or assume a Retina scale.

### Bounded run and witnesses

| Step | Real OS action and required observation | State/persistence witness |
| --- | --- | --- |
| 1. Present | Launch the pinned human-mode candidate. Inspect the actual window, world, HUD and furnace; record an OS screenshot and the window/content extents. | Record binary/launcher/fixture hashes, owning processes/ports, settings and ready logs. Startup deadline remains the candidate's verified limit, at most 150 seconds per launch. |
| 2. Capture and release | Use the documented CUA left-click on the world while uncaptured; the first capturing click is consumed. Observe the available cursor/camera response, then press Escape outside a menu and observe a usable released cursor. Any relative-pointer or continuous movement check must use a supported mechanism and its observed result. | Record actual gestures and player observations. A discrete W press does not verify held duration, and continued inertia is not a held-key failure by itself. Do not infer raw capture flags from logs: the current stdout does not expose them. Mark unsupported held-key or relative-pointer observations unverified. |
| 3. Open furnace | Recapture with a left-click, aim at the furnace and right-click. This sends actual main-hand CookingUse. Inspect the FURNACE panel, three furnace cells and player inventory; the cursor must now be usable over slots. | Retain the correlated accepted `client.menu` reply/sequence and the fixture's furnace position. A private TCP open command does not substitute for this gesture. |
| 4. Insert input | Left-click the beef stack, then left-click furnace input slot 0 to deposit it. Observe two beef in that cell and an empty carried stack. | Correlated accepted menu replies and the actual visible slot counts. No direct inventory or block-entity mutation during the run. |
| 5. Insert fuel | Left-click the coal stack, then left-click fuel slot 1. Observe fuel consumption and the flame. | Record actual furnace timing/counts from the received menu snapshot where logged; retain a public clock observation to distinguish unpaused simulation from polling. |
| 6. Watch progress | Take OS screenshots of the flame/progress arrow and successive output counts. Record a timing defect if two recipes take more than 30 seconds. If targeting, lease and accepted progress remain safe, continue observing functional progress for up to 90 seconds, within the ten-minute session budget. The hidden caller measured 67.009 seconds; do not label that normal timing. | The real menu must reach two cooked beef; input is empty and one coal remains after the first coal ignites. Preserve elapsed wall time, actual recipe total/speed and tick/progress observations. Functional completion after 30 seconds does not clear the timing defect. A CPU image alone does not show presentation. |
| 7. Take output | Left-click output slot 2, then an empty visible player cell. Observe two `minecraft:cooked_beef` in that cell, empty output and empty carried stack. | Retain both accepted correlated replies and the before/after slot counts. Do not count a merely predicted cursor icon as an accepted take. |
| 8. Close and focus recovery | Press E or Escape in the menu through CUA and wait for the correlated closed snapshot; the world should recapture while focused. Test Escape release once more. Use CUA to briefly select the prior application and return; confirm a usable outside cursor and no new movement without a new key action. | Record actual OS focus/cursor/presentation observations and public player observations. This discrete focus test does not verify focus loss while a movement key is held. Keep that stronger held-input lane unverified unless supported and actually exercised. |
| 9. Save through exit | With no carried stack, use the native close button. If the menu is open, its actual authenticated cooking close must finish before Quit. Wait for the launcher close/save helper. There is no save keyboard shortcut. | Require the actual `world.save` result `status=durable`, `published=true`, `durable=true`, plus saved path, byte count and SHA-256. A JSON success with `published-unsynced` is not this witness. |
| 10. Reload | Launch the same pinned pair on the same disposable file. Visibly reopen that furnace by the same captured right-click gesture. Inspect empty input/output, the remaining coal, retained nonnegative burn time and two cooked beef in the recorded player cell. | Independently inspect the complete physical save, including furnace body, player inventory and publication recovery. Compare counts and owner fields; active burn time may advance during startup, so do not require frozen timer bytes. Record restored position/rotation, no restored held controls, and the second OS screenshot. |
| 11. Final close | Close the menu with E/Escape, release controls and close the native window. Restore the prior foreground application. | Require the second durable save receipt and bounded cleanup of this run's own processes, sockets and ports. Retain logs/screenshots/save hashes and record any surviving recovery actor explicitly. |

Read-only public queries and physical saved-body inspection supplement the OS
record; they do not supply the mouse/keyboard evidence. The renderer owns the
private lease throughout interaction. Do not acquire a competing private
observer lease or issue menu mutations from a test client. The visible run
does not require another SIGKILL: separate actor022 recovery receipts and the
actor023 callback cold stage retain their stated scopes, while this run tests
ordinary native exit/reload.

Stop posting input at the first unsafe targeting, unexpected capture, menu
refusal, startup timeout or save failure. Release every physically held key
and mouse button, then use Escape/the normal cursor recovery path as applicable.
Retain the exact error and screenshot. The existing launcher preserves the
actor and a permission-0600 reconnect file when close/save is refused; do not
kill that unsaved owner merely to satisfy a cleanup assertion. Use its normal
reconnect route to make inventory space or finish closing. Successful cleanup
may terminate only the PIDs/groups owned by this run, after the durable witness;
verify their listeners are gone without touching the baseline or unrelated
applications. Never print authentication tokens or private reconnect contents
in the acceptance record.

The resulting record must distinguish PASS, FAIL and unobserved steps, name
the exact adopted actor/client012 pair, retain real OS screenshots and
correlated/save witnesses,
and record foreground/cursor restoration. A successful bounded furnace flow
would establish that flow only. Continuous collision, all inventory/settings
paths, campfires, pickup, audio, multiplayer and whole-game vanilla parity
retain their separate visible requirements.
