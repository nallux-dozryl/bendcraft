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

## Cooking delivery: actor022 and client011

This is a prepared visible run, **not an executed acceptance record**. Confidence
is high for the source-derived gestures below. Actual window presentation,
physical input delivery, capture/release and the visible cooking/save/reload
sequence remain unverified. The existing actor022 publication/save/cold-restart
and SceneFrame TCP receipts cover their stated scopes; they do not supply these
OS observations.

### Ready pair and foreground boundary

The immutable actor is
`build/compiler-producer-diagnostic-022/actor`, 16,246,616 bytes, SHA-256
`1ba545e7ccd84e5011f51199c2ee9562e4063c24b98c64148323551039357712`.
Its source map is SHA-256
`95acf6a8c10c4f0eca5c696ef9126a5bfc27cdec36806288147714e2510835db`,
recorded in [the native build receipt](../evidence/playable-client-actor004-build-022.json).
The client011 executable digest, exact candidate launcher command, fixture
digest and matched hidden pair receipt must be recorded here or in the linked
session record when available. At preparation time the standard `011` artifact
directory was absent, and `tools/play_minecraft.sh` still selected actor017 and
client010. That historical route must not be labelled 022/011.

Catalog reports the new client caller's original source check passed 5,812
declarations with zero holes. Its immutable client010 baseline plus actual
Generic caller overlay has SHA-256
`496b9a9e5ddff0d1fde1d1d2accde490f7875e938a27a4d81ba3e1101e3a202b`.
This is a source identity, **not a client011 executable digest or paired launch
receipt**. The actual fixture and candidate close/reconnect route are still
being prepared by their owners.

Prepare the candidate and its exclusive disposable world before asking for
foreground access. Reuse the verified binaries and the existing launcher and
close/save helper; no new controller framework or rebuild belongs in this run.
Select unused loopback ports, retain their owning PIDs, and leave the older
baseline processes and the user's default `build/playable-world.nbt` untouched.
Record the actual pinned Java 26.3 jar, registry, item table, sine table and
candidate settings. Use the human launch mode, CPU renderer and a **windowed**
presentation; record measured content, drawable and HUD extents. Do not switch
Spaces or enter fullscreen.

No isolated controllable desktop has been established by the existing
[input preflight](VISIBLE_INPUT_PREFLIGHT.md). The unavoidable action is to
present and focus the actual client on the current desktop, send real keyboard
and mouse input, briefly switch away to test release, then close and reopen it
on the same save. Request **up to ten minutes** of coordinated foreground use
for both launches, the cooking sequence and cleanup. This is a planning budget,
not a measured runtime. Return to the previous foreground application at the
end. Request this once, only when the pinned pair and fixture are ready; no
window, input, focus or Space action was performed while preparing this section.

The existing computer-use click/key/screenshot surface can handle discrete
gestures after that coordination. Physical mouse motion and physical held keys
are the fallback for capture and continuous-input observations. The dormant
`tools/visible_os_input.swift` supports limited movement/Escape holds and relative
mouse motion, but lacks slot clicks, E, Shift and window-close gestures. Its
historical posting permission was unavailable, and its posting report does not
establish delivery. Do not treat an internal Bend event, TCP command, momentary
key press, helper cleanup key-up or CPU framebuffer dump as the corresponding
OS acceptance observation.

### Fixture and actual menu coordinates

The saved fixture must contain an empty, ordinary furnace on a resident flat
floor, with the player standing within the actual interaction range and aiming
at it. Use an overworld target with its complete collision/light scan halo
resident; the tested target `(12,8,12)` has the halo inside section zero. Record
the actual player position, rotation and fixture digest rather than assuming
the paused publication fixture is already aimed for a visible run. Give the
player a visible stack of two plain `minecraft:beef` and two plain
`minecraft:coal`, with empty inventory cells for returns and output. Setup is
fixture preparation, not an observed world edit or acquisition of those items.
The furnace body must use the normal initialized recipe/speed profile with no
accelerated cooking component. Before interaction, verify that the shared
simulation is unpaused and the ordinary beef recipe has its actual 200-tick
cooking total. Progress must come from real 50 ms simulation ticks, not explicit
`simulation.step` calls or frame polling.

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
| 2. Capture and release | Left-click the world while uncaptured; the first capturing click is consumed. Move the physical mouse and observe camera response. Hold W briefly on the clear floor, release it, then press Escape outside a menu and observe a usable released cursor. | Record the actual gesture timing and player position before/after with read-only public inspection. Continued inertial motion is not a held-key failure by itself. Do not infer raw capture flags from logs: the current stdout does not expose them. |
| 3. Open furnace | Recapture with a left-click, aim at the furnace and right-click. This sends actual main-hand CookingUse. Inspect the FURNACE panel, three furnace cells and player inventory; the cursor must now be usable over slots. | Retain the correlated accepted `client.menu` reply/sequence and the fixture's furnace position. A private TCP open command does not substitute for this gesture. |
| 4. Insert input | Left-click the beef stack, then left-click furnace input slot 0 to deposit it. Observe two beef in that cell and an empty carried stack. | Correlated accepted menu replies and the actual visible slot counts. No direct inventory or block-entity mutation during the run. |
| 5. Insert fuel | Left-click the coal stack, then left-click fuel slot 1. Observe fuel consumption and the flame. | Record actual furnace timing/counts from the received menu snapshot where logged; retain a public clock observation to distinguish unpaused simulation from polling. |
| 6. Watch progress | Take OS screenshots of the flame/progress arrow and successive output counts. Allow two normal beef recipes to finish, about 20 seconds at 20 ticks/second; allow up to 30 seconds of measured wall time before recording a timing/progress defect. | The real menu must reach two cooked beef; input is empty and one coal remains after the first coal ignites. Compare the actual total/speed and tick delta, not an assumed frame count. A CPU image alone does not show presentation. |
| 7. Take output | Left-click output slot 2, then an empty visible player cell. Observe two `minecraft:cooked_beef` in that cell, empty output and empty carried stack. | Retain both accepted correlated replies and the before/after slot counts. Do not count a merely predicted cursor icon as an accepted take. |
| 8. Close and focus recovery | Press E or Escape in the menu and wait for the correlated closed snapshot; the world should recapture while focused. Test Escape release once more. With a physical movement key briefly held, switch away, then physically release it before returning. Confirm the cursor is available outside the game and no held-control action resumes on return without a fresh press. | Record actual OS focus/cursor/presentation observations and public player observations. Helper key-up cleanup alone does not prove the client's focus-loss release. If the available automation cannot demonstrate this lane, mark it unverified. |
| 9. Save through exit | With no carried stack, use the native close button. If the menu is open, its actual authenticated cooking close must finish before Quit. Wait for the launcher close/save helper. There is no save keyboard shortcut. | Require the actual `world.save` result `status=durable`, `published=true`, `durable=true`, plus saved path, byte count and SHA-256. A JSON success with `published-unsynced` is not this witness. |
| 10. Reload | Launch the same pinned pair on the same disposable file. Visibly reopen that furnace by the same captured right-click gesture. Inspect empty input/output, the remaining coal, retained nonnegative burn time and two cooked beef in the recorded player cell. | Independently inspect the complete physical save, including furnace body, player inventory and publication recovery. Compare counts and owner fields; active burn time may advance during startup, so do not require frozen timer bytes. Record restored position/rotation, no restored held controls, and the second OS screenshot. |
| 11. Final close | Close the menu with E/Escape, release controls and close the native window. Restore the prior foreground application. | Require the second durable save receipt and bounded cleanup of this run's own processes, sockets and ports. Retain logs/screenshots/save hashes and record any surviving recovery actor explicitly. |

Read-only public queries and physical saved-body inspection supplement the OS
record; they do not supply the mouse/keyboard evidence. The renderer owns the
private lease throughout interaction. Do not acquire a competing private
observer lease or issue menu mutations from a test client. The visible run
does not require another SIGKILL: actor022 already has separate interruption
and cold-recovery evidence, and this run tests ordinary native exit/reload.

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
the exact 022/011 pair, retain real OS screenshots and correlated/save witnesses,
and record foreground/cursor restoration. A successful bounded furnace flow
would establish that flow only. Continuous collision, all inventory/settings
paths, campfires, pickup, audio, multiplayer and whole-game vanilla parity
retain their separate visible requirements.
