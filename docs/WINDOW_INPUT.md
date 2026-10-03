# Native window focus and capture

Pinned Base emits key press/release and relative `Look` events, but no focus
event. Its AppKit `windowDidResignKey` releases the cursor without emitting an
event; `Window.grab` returns only the same Window and can refuse capture when
the window is not key. Treating a requested grab as success can therefore leave
logical held keys active after focus loss.

`window_input.Native.status(window)` returns the **same affine Base Window**
and two Boolean observations: focused (`isKeyWindow && NSApp.isActive`) and
captured (focused plus the pinned BendView `grab` field). The narrow native
effect reads these OS fields; it does not pump events, activate applications,
change capture or implement game behavior. `capture(window,on)` requests the
ordinary Base grab and then reports actual capture. It does not invent a new
handle or modify the compiler/runtime. The generated-window launch transform
and its complete pinned digest remain unchanged.

The project presenter checks this status after each real Window frame pumps
events. Losing capture clears all held buttons in the sole actor. An uncaptured
left click attempts recapture and uses the observed result. Escape clears
buttons and releases the cursor. Frame-query/render failures close Window and
renderer assets and stop the actor; window-open failure closes assets and
stops the actor before exiting. These presenter paths require separate native
integration and real visible input evidence.

`python3 tools/test_window_input.py` builds the actual native boundary and runs
three hidden windows. It compares initial/attempted-capture/post-frame status,
actual platform visibility/focus, foreground identity and Spaces notifications.
The hidden cases cannot establish focused capture, physical input, focus-loss
behavior with held keys, or visible gameplay acceptance. JavaScript explicitly
rejects the unavailable native query. The C boundary outside Objective-C
returns false observations; other native platforms are unverified.

Ordinary source checking reaches the explicitly declared foreign/unsafe
boundary. This observation has no kernel correctness proof. Its AppKit/KVC
layout depends on the pinned Base Window implementation and must be reverified
when that implementation changes.
