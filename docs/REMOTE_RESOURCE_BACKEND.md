# Saved LocalPlayer resource backend

`remote_resource_server.bend` is the authoritative half of the split resource
client. It owns the actual `LocalPlayerSession.State`, its complete supported
record, world lease, Core and tables in one existing `Server` actor. The renderer
owns resource assets and Window in another Bend process. No Python code provides
simulation, rendering, resource decoding or product persistence.

The entry requires `--verification-fixture`; a playable world loader remains
open. `--sine PATH` selects the verified table, `--unpaused` requests realtime
simulation, and `--stdin-control` accepts the line `stop`. Startup uses the same
LocalPlayer storage codec, restore gate and pristine-only finite scene initializer
as `local_player_client.bend`. Loaded terrain, complete record and pause state
remain authoritative. The existing `MC_WORLD_PATH`, `MC_WORLD_MISSING` and
registry loader settings still apply.

The public API uses `MC_LIVE_PORT` and `MC_DEV_TOKEN` and retains the existing
18-operation saved-player catalog. The private renderer listener uses required
`MC_RENDER_PORT`, `MC_RENDER_TOKEN` and `MC_RENDER_EPOCH`. The token is nonempty
printable ASCII with a 256-character bound; the boot nonce has a 32-character
bound. Launch orchestration must generate a fresh nonce and token for each
backend lifetime. Both listeners bind `127.0.0.1`. Tokens are never printed in
ready events. The public and private ports must be independently available;
actual listener binding refuses a collision.

After public `server.ready`, the private listener prints `renderer.ready` with
its port and protocol version 1. See [RESOURCE_CLIENT_WIRE.md](RESOURCE_CLIENT_WIRE.md)
for the strict ASCII DTO format. A private capability authenticates one active
renderer. Public developer privilege does not supply the renderer capability.
The actor assigns `bootNonce:counter`; HelloAck sequence is zero, and calls start
at one. A socket may send Hello once and thereafter must use its own assigned
epoch. The actor additionally requires exactly its next expected sequence.
Usable call sequences are 1 through 281474976710654. The syntactically valid
Nat48 terminal number 281474976710655 is refused before increment, and a terminal lease
counter refuses a further Hello; neither counter wraps.

Each Frame command runs the entire Pose-eye/relative-camera/raw-cell/palette/
visibility sample in one actor operation. It performs no simulation step or
physical input sample. Input applies one ordered whole packet through the actual
LocalPlayer scene. Release clears physical controls and advances the private
sequence. These calls do not consume public peer/session sequence numbers.

Admitted calls refresh a lease of 100 actor Pulse callbacks. The timer schedules
50 ms deadlines, including paused callbacks. Expiry releases physical controls
before that pulse can advance LocalPlayer physics. This is a callback-count
policy; actor backlog and timer scheduling are not a measured wall-clock
latency guarantee. EOF, request/read failure and reply encoding/send failure
also release the socket's assigned epoch. A stale socket cannot clear a newer
lease. A failed Hello reply cleans up the newly assigned epoch.

The connection reader has a five-second absolute deadline for each record.
The reader checks time again after poll and after decode before actor submission;
late received data is refused. Partial chunks do not renew it. Completed request/reply processing starts the
next record deadline. Received scalars are segmented at LF before ASCII and
framing admission, so a malformed later record cannot erase a completed earlier
request delivered by the same TCP poll. Native `TCP.poll` replacement decoding
is admitted only for the ASCII domain; actual malformed-byte observations remain
required integration evidence. The read deadline does not cancel a parked
native send or actor operation; the independent actor lease still expires.

With stdin control, `stop` releases current physical controls, revokes the private
capability and suppresses later timer pulses, stops the actor,
then exits the owning process. Process exit releases parked listener sockets
and the OS world lease. Public `world.save` acknowledgment is a separate
operation; stop and SIGTERM do not imply an automatic save. EOF on control stdin
also stops the process. Release and Stop are separate actor messages; queued
public requests may still dispatch before Stop. No general API quiescence or
automatic save is implied. Without stdin control, the actor/listeners continue
until process termination.

The whole entry currently passes ordinary checking with exactly 97 declared
unsafe/foreign dependencies and no other diagnostic. The two backend laws cover
complete-state preservation on explicitly failed authentication and stale
disconnect admission. They are ordinary-checker laws; no independent kernel or
native behavior is claimed here. The retained source check is
`build/remote-resource-server-ordinary.stop-revoke.full.json` (14.394435 seconds,
five source pins unchanged). Native compilation, paired protocol/render/save
regressions and visible controls remain pending. The renderer documents its
selected resource and image-quality boundaries separately.
