# Renderer inactivity and queued simulation pulses

Actor023 retains the immutable Actor022 graph and changes only
`src/remote_resource_backend.bend`. Both actual realtime entry paths now run
their Scene step without charging `lease_tick`. They still consume every
serialized timer pulse; vanilla cooking and player simulation keep their
existing cadence and catch-up behavior. The Lease and Backend.State layouts,
epoch authentication, exact next-sequence admission and menu owners are unchanged.

The actual private transport already enforces a monotonic 5000ms inactivity
deadline. It sets a deadline after accepting a socket and after successfully
sending each response, uses the remaining time in TCP.poll, and checks the
deadline after polling and before processing a request. Timeout, EOF, invalid
input and send failure close the socket and serialize Backend.disconnect with
the epoch assigned to that socket. Disconnect releases controls only when that
epoch matches the active lease. An incoming request's claimed epoch cannot
release a replacement owner.

The previous second expiry mechanism decremented a 100-pulse budget. Server.timer
advances its previous deadline by 50ms, and the bounded actor mailbox admits
queued pulses. Consequently, a pulse consumed after renewal can represent time
before that renewal. Charging those pulses can expire a recently renewed lease.
`lease_tick` remains an explicit legacy pure operation for compatibility; runtime
steps no longer call it. Its `remaining` field is not runtime elapsed time.

The retained normal ambient cooking run009 accepted CookingInspect sequence98
with two cooked beef, then rejected the identical epoch's exact next Input99
with RendererLeaseOrSequence. No intervening admitted request or host pause is
recorded. Sequence and epoch mismatches are excluded by the retained relay.
Catch-up pulses causing this particular expiry remain an inference: the old
actor did not record pulse timestamps, and host file mtimes do not measure the
backend's renewal instant.

The source-only check uses the original complete Book loader/checker without
selection, altered declarations or holes. Actor023's single producer/native
attempt retains original compiler guards and the tested private producer. The
initial source diagnostic accidentally forced garbage collection on every
declaration; it was stopped in its own process group and retained as source001.
The corrected source002 observer uses threshold collection and passed the same
complete source. That diagnostic failure is not a source-check failure.

Run the targeted actual socket consumer with bundled Python:

```sh
python3 -B tools/test_renderer_lease_elapsed.py --actor-generation 23 --native
```

It checks actual idle EOF, next-tick release, EOF/reacquisition, stale socket
isolation, twelve seconds of CookingInspect/Input continuation, and replay
refusal. It retains every private request/response and registered process group.
Host-observed closure intervals do not prove immediate wall-time control release:
disconnect remains serialized in the actor mailbox. The meaningful unpaused
input/fuel/progress/output/close/save/reload flow belongs to the existing cooking
runtime consumer with Actor023 and the unchanged client012.

Native acceptance is pending until its actual receipt exists. This change makes
no future entity, lighting, membership, save-format or visible-OS acceptance claim.
