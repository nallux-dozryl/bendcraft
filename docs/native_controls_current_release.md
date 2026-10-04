# Unconditional controller release and atomic consumer join

`src/player_controls.bend` now exposes `capture_release(controller) -> Controller`.
It consumes the existing `client_controls.release()` signal and returns the
complete released controller without consulting `controller_error`, packet
admission, mouse options or numeric input. `release_packet(controller,packet)`
performs that state operation if any explicit `Release` occurs anywhere in the
packet; `release_requested(actions)` exposes the same signal test for the
actual affine runtime owner. Packets without that signal return the complete
controller unchanged. The existing `apply`, action fold, error precedence and
atomic rejection contract remain unchanged.

Release empties all seven held buttons, clears both accumulated mouse deltas to
positive zero and arms first-move suppression. It retains every raw look field,
both mouse position fields and every option field, including invalid values,
NaN payloads, infinities and signed zero. It is unconditional and idempotent.
This API owns a full `Controller`; it does not own or modify world, abilities,
LocalPlayer metadata, session shell, renderer lease or actor scheduling.

## Verified controller contracts

`tests/native_controls_current_release_laws.bend` states ten laws against the
production controller and client packet types; the accompanying proof file
passes the independent kernel with no axioms or foreign/unsafe assumptions:

- The canonical existing release packet invokes the existing field release.
- Release preserves every complete-controller field except its specified held,
  accumulated-delta and first-move fields, for arbitrary raw field values.
- Both canonical release and packet-selected release are idempotent.
- A release before an arbitrary tail survives every tail action.
- Any platform payload before release cannot prevent its state operation.
- An absent release preserves the complete controller; a present release
  produces the complete canonical release result.
- Pre-release remains available when existing controller admission rejects.
- For an admitted released controller, a release followed by a NaN Look still
  rejects ordinary input while retaining the separate release result in the
  controller/result pair, whether that Look is captured or uncaptured.

The kernel rejects a mutant whose selected release branch returns the original
controller. The existing eight control laws and four successful-fold laws also
pass. The exact production controller pin at this handoff is SHA256
`69e06c1f5900d816e15c88fa093dbc5ab47a0fc2fb5d784a6cbb38fcc4c14d90`,
8,413 bytes.

Run `python3 tools/native_controls_current_release_check.py --build`, after
coordinating a narrow CPU compile slot. The runner uses the pinned native build
cache, builds only the release observer and existing control harness, exports
the kernel IR and verifies that source identities remain stable throughout.
It does not open a native window or post OS input.

The passing `evidence/native_controls_current_release.json` records:

- 1,280 native full-controller raw-word cases covering every held mask.
- 256 initially valid controllers with release followed by malformed Look.
- The frozen independent Java/rational atomic corpus: 1,141 cases and 1,727
  reports, plus 54 malformed protocol cases.
- Ten kernel roots, the rejected ignored-release mutant, the existing twelve
  laws, source/binary hashes and native build receipts.

Expected release words are calculated independently by copying the full
20-word controller, changing only its held mask, accumulated mouse words and
first-move bit. The fixture's `retained_controller` failure report echoes the
prior controller supplied to it. These receipts establish the controller API
and unchanged atomic input behavior, not an actual affine runtime commit after
refusal or a physical macOS focus/capture event.

## Concrete root-owned consumer proposal

`docs/native_controls_current_release_join.patch` is a proposed integration
patch; this lane has not edited its nine consumer/test files. Its SHA256 is
`68c4c41ab0ffe400ac961364db93e0d94746982d8bfb5658d700b5467fc59c78`.
The patch passes `git apply --check` against the handoff source and makes these
changes:

1. Add an unconditional `State -> State` release callback to Common's Driver,
   connecting all four production scene drivers to their existing session
   release operation. Adapt the presenter fixture driver as well.
2. Keep `Common.local_input` as one `S.local_call`. Within that callback,
   `input_released` first invokes the release callback if the packet contains
   Release, then processes the original ordered packet using that released
   owner. Input rejection therefore retains the released prior. A timer pulse
   cannot observe an artificial intermediate state between two actor calls.
3. Make standalone `Common.local_release` directly commit the release callback
   through `S.local_call`, without sending an admitted input packet.
4. Keep remote per-frame transport as one `Wire.Input`. After existing renderer
   lease/sequence admission, pre-release its actual saved session inside the
   same backend input operation before `Scene.input`. Invalid leases still
   retain the original complete backend state. Standalone menu release uses
   the existing dedicated `Wire.Release`, as close already does.
5. Adapt the existing presenter's fixture counting: dedicated cleanup is no
   longer counted as an input packet; release-bearing packets record their
   unconditional callback before their original action trace.

A proposal using separate release and input actor/wire operations was rejected
and replaced: an aiStep timer could otherwise execute between those operations.
The current patch has no extra per-frame actor or wire operation.

`evidence/native_controls_current_release_join.json` records proposed-copy
checks and their limits. Common and its presenter fixture reach only existing
foreign/unsafe admissions with no type error. The proposed complete remote
backend check timed out after 55.26 seconds without a diagnostic; that broad
graph was not retried. Inspection found no semantic/order/affine defect in the
revised join. Actual integration, full Session/LocalPhase/World preservation on
`W.look` failure, native actor/transport replay and physical OS acceptance remain
root-owned obligations, not conclusions of these controller receipts.

Confidence is **high** for the specified controller contracts and native replay.
The consumer proposal has a concrete implementation and narrow source-check
support; backend integration and physical capture acceptance are **unverified**.
The native C generation included in renderer004 remains unchanged at SHA256
`0c6aebd6a22f999851798a13980a0c04ac6bfa6d85ff6193429efff1a4a61363`.
Renderer003 and renderer004 were not modified by this release work.
