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
visibility sample in one actor operation. It admits the shared frame dimensions
before calling the actual Scene.ensure demand route, then samples the returned
world. Demand failure forwards the actual returned saved owner and diagnostic;
WGUnspecified keeps the existing fixture route. Frame sampling performs no
simulation step or physical input sample. Input applies one ordered whole packet through the actual
LocalPlayer scene. Release clears physical controls and advances the private
sequence. These calls do not consume public peer/session sequence numbers.

The additive reserved-player constructor `Backend.new_reserved` supports
Action, Hotbar and Inventory on the same lease. Action computes the actual
pose-eye ray against the owned world, then admits a creative edit with the
server-reserved Player capability. The private DTO contains no peer or
developer mutation. Inventory returns the owned 36-slot snapshot; Hotbar sets
only the selected slot. `Backend.new` retains Observer and its actions are
denied. All three commands use the same expected sequence and refresh rule;
unsuccessful gameplay actions return `ActionReply{changed=false,message}` while
protocol faults retain the existing close/cleanup behavior. See
[PLAYER_BLOCK_INTERACTION.md](PLAYER_BLOCK_INTERACTION.md) for the restricted
shape/item domain and Java reference evidence. The combined playable entry's
startup owns saved-player peer reservation; original frozen fixture acceptance
must remain explicitly distinguished from that additive startup path.

The same lease now carries typed main-inventory Transfer/Acquire and complete
MenuInspect/Open/Close/Click operations. Mutations require the actor's retained
Player peer to be greater than zero; the private request cannot replace it.
Transfer/Acquire independently check the main 0..35 domain. MenuClick delegates
the actual InventoryMenu slot numbering and slot rules to the saved inventory
owner. Ordinary movement remains available without maybuild; acquisition uses
the owner's instabuild gate. Each admitted operation or gameplay refusal
returns MenuReply with its actual complete persisted/equipment/craft/carried/
result/status/revision snapshot and advances the private sequence. Lease faults
retain Fault and socket cleanup. Unsupported recipe, equipment or click
semantics remain explicit owner refusals/dependencies, never client-owned state.
The current Transport check includes these actual Backend/frame routes and
completed in 14.207 seconds with exactly 104 declared foreign/unsafe-dependent
definitions and no syntax, type, quantity or law error. Earlier imported
runtime/terrain errors and their substantive repairs are retained in
[the source and proof evidence](../evidence/player-inventory-menu-wire-source-checks.json).
Native menu/frame behavior remains part of the combined acceptance artifact.
Five exact inline production contracts independently pass the pinned kernel
in 0.375 seconds: complete-owner preservation for stale disconnect, rejected
menu admission, an actual inadmissible lease/sequence premise, rejected action
owner and an actual absent retained Player premise. They quantify the actual
Backend.State or saved S.State, including every affine world/array and inventory
owner; no copied state or replacement model is used. The read-only selective
export checks the original whole book and retains all declaration tables and
unchanged checked theorem terms. Its one excluded failed-Hello contract depends
on Nat.show.fin/Nat.show.go mutual recursion outside the exporter's live-parameter
scope. That sixth contract remains unverified by the independent kernel.
Successful menus, demand correctness and FFI behavior require their separate
contracts or boundary evidence. The independent 16 CoreEdit/BI permission and
commit contracts are recorded separately in
[PLAYER_BLOCK_INTERACTION.md](PLAYER_BLOCK_INTERACTION.md).

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

The retained entry previously passed ordinary checking with exactly 97 declared
unsafe/foreign dependencies and no other diagnostic. The two backend laws cover
complete-state preservation on explicitly failed authentication and stale
disconnect admission. They are ordinary-checker laws; no independent kernel or
native behavior is claimed here. The retained source check is
`build/remote-resource-server-ordinary.stop-revoke.full.json` (14.394435 seconds,
five source pins unchanged). Native compilation, paired protocol/render/save
regressions and visible controls were pending in that historical preparation.
The later native result is recorded in
[RESOURCE_CLIENT_NATIVE_RESULTS.md](RESOURCE_CLIENT_NATIVE_RESULTS.md). Those
results do not establish the new action/inventory graph; its source and native
status belongs to the current combined playable-client acceptance. The renderer
documents its selected resource and image-quality boundaries separately.
