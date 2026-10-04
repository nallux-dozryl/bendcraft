# Current native control boundary repair

The production change is in `src/native/player_presentation.c`. The existing
`Native.configure(Window,width,height,native,fullscreen,human)` and
`Native.measure(Window)` interfaces, JavaScript refusal behavior, pure packet
contract and affine Window owner remain unchanged. The native adapter installs
`MCPlayerPresentationView`, a subclass of the pinned Base `BendView`, when the
actual remote resource presenter calls `Native.configure`. It retains the
existing Metal layer and queued event buffer, then installs the view as the
window delegate and first responder. Base and the guarded launch transform are
unchanged.

The prior Base view clamped pointer coordinates before Bend could reject an
outside drag or release. The subclass now emits floor-rounded content points
inside the view and the relevant content extent as an outside sentinel on every
edge. It uses the view's content bounds, independently of the drawable extent.
The existing Bend presentation policy then maps these points into the output
canvas and rejects the sentinel. Mouse button and relative movement payloads
continue through the Base event methods.

The subclass records each physical AppKit `keyCode` with its original public
logical character/modifier code. A release removes that recorded key rather
than recomputing its code from possibly changed characters or modifiers. Two
physical keys producing the same logical code keep that logical key held until
both are released. Repeated downs are suppressed, including an OS repeat after
a release cleared the cache; holding a menu key therefore does not repeatedly
activate it. The logical character convention remains Base's lowercase
`charactersIgnoringModifiers`, including its handling of Shift-generated
symbols. The ten modifier key codes use the SDK's actual sided/device flags,
so simultaneous left/right modifier transitions do not depend on a change to
the aggregate modifier flag.

Window focus loss, application inactivity and close release the cached keys
and clear stale modifier flags. Ending an existing grab releases them as well.
Capture is refused for hidden launches and while the application is inactive
or the window is not key. Positive capture retains Base's cursor implementation.
The current native scale and `convertRectToBacking` determine drawable geometry;
windowed limits are updated on every measurement and oversized windowed content
is constrained to the supported 4096-pixel bound after a scale change. Configure
honors both fullscreen and windowed requests and releases capture before a
transition; hidden launches skip human geometry and fullscreen operations.

The final native C generation has SHA256
`0c6aebd6a22f999851798a13980a0c04ac6bfa6d85ff6193429efff1a4a61363`
and 9,311 bytes. Root's renderer004 source snapshot contains this generation.
The existing renderer003 and its human launcher were preserved.

## Verification

Run `python3 tools/native_controls_current_check.py`. The runner compiles a
narrow Objective-C harness with the exact pinned Base view and the actual
production adapter. It creates an unordered native window under AppKit's
Prohibited activation policy, delivers unposted synthetic event objects directly
to the native view, and records source and executable digests. It does not post
events to the user's desktop, order a foreground window, or invoke a positive
cursor grab or fullscreen transition. A right-button payload uses an unposted
native CGEvent: AppKit's convenience synthetic mouse-event constructor reports
button zero even when given the right-mouse event type, so that constructor is
not used to assert the button identity.

The passing receipt is `evidence/native_controls_current.json`: 77 assertions
on the actual 2× backing display, unchanged foreground PID, zero observed
Space-change notifications, hidden/non-key/non-main window and inactive app.
It covers view/layer/event-buffer ownership, content-point and outside pointer
translation on all four edges, native right-button identity, signed relative
Look fields under a fixture grab flag, physical key pairing and repeat
suppression, all ten modifier masks, simultaneous sided Shift, focus/application/
close release, hidden capture refusal, drawable/content measurement and a hidden
resize. The relative-motion test changes the view's fixture flag directly and
never hides, warps or disassociates the cursor. The native wrapper check reports
exactly its four declared foreign
boundaries and no type error. The adapter itself compiles in the native harness.

`tests/native_controls_current_proof.bend` adds four laws over the actual
production `player_controls.fold`: an action prefix executes before the rest,
a captured key changes held buttons while retaining other fields, release after
a key clears held controls, and an uncaptured key cannot restore released
controls. All four pass `bend --verdict`, as do the existing eight control laws.
A mutation that drops every successful action is rejected at
`ordered_action_prefix`. These proofs make no claim about the foreign adapter.

Confidence is **high** for these recorded native boundary checks and pure
contracts. Visible physical OS input, positive cursor capture/release, real
fullscreen transitions, physical screen migration, continuous movement and
rendered native framebuffer acceptance remain **unverified** under the session
policy in `docs/VISUAL_ACCEPTANCE.md`. The hidden callback tests establish their
event translation and release logic; they do not demonstrate that macOS delivers
the corresponding real user events.

## Remaining specific boundaries

The presenter measures geometry before rendering but pumps events during
`Window.frame`; an intervening resize can therefore produce pointer points for
a different geometry than the earlier Bend plan. Pending-event geometry needs
a batch consistency contract and an actual resize-during-frame check.

The pure `player_controls.apply` deliberately validates the initial controller
and rolls back a failing atomic packet. Thus a release packet can be refused
for invalid controller/options, or rolled back when a later Look is nonfinite.
The direct runtime `release` operation bypasses that admission, while the common
presenter currently sends the release packet. This native repair retains that
established packet contract; total release on an invalid controller is a separate
consumer safety obligation.

The native API references are Apple's
[NSEvent documentation](https://developer.apple.com/documentation/appkit/nsevent)
and [convertRectToBacking documentation](https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)-3zors).
The sided masks are read from the installed SDK's
`IOKit.framework/Headers/hidsystem/IOLLEvent.h`, rather than inferred from
aggregate flag changes.
