# Resource renderer wire v1

`src/resource_client_wire.bend` is a pure monomorphic codec shared by the actual
LocalPlayer Session backend and remote resource renderer. It owns no actor,
world, resource assets, socket, timer or authentication state. Its action command
requests the backend's reserved player interaction; it accepts no block position,
state ID, player peer, ability, inventory mutation or developer capability.

Public API:

- `encode_request(Request)` and `encode_reply(Reply)` return
  `Result<String,String>`; invalid or oversized DTOs fail.
- `decode_request(String)` and `decode_reply(String)` return typed results.
- `correlation(epoch,sequence,reply)` compares exact expected header values.
- `nat_max()`, `sequence_valid()`, `epoch_valid()`, `transport_bytes()`,
  `parser_scalars()`, `parser_depth()`, `sample_blocks()` and `mesh_limits()`
  expose the admitted limits.

Types are `Hello{capability}` or `Call{epoch,sequence,command}`;
`Command` is `Frame{width,height}`, `Input{packet:CC.Packet}`, `Release{}`,
`Action{button}`, `Hotbar{index}` or `Inventory{}`.
Replies are `HelloAck{epoch,sequence}`, `FrameReply{epoch,sequence,sample:V.Sample}`,
`Ack{epoch,sequence}`, `Fault{epoch,sequence,message}`,
`InventoryReply{epoch,sequence,snapshot:I.Snapshot}` or
`ActionReply{epoch,sequence,changed,message}`.

The backend owns token authentication, a fresh boot nonce plus monotonic lease
counter as epoch, the one active renderer lease and strict expected-sequence
transition. HelloAck sequence is exactly zero; subsequent calls start at one.
Sequences are exact nonwrapping Nat48 values through `281474976710655`. Checking
correlation does not advance a counter or authorize a lease. Counter exhaustion
must retire the lease before adding one. Root's actor policy expires a lease
at 100 actual 50ms timer callbacks, including paused callbacks; admitted calls
refresh it. Only matching-epoch cleanup may release keys.

## Exact JSON arrays

Transport is ASCII JSON. Strings are escaped with `\uXXXX` and surrogate pairs
for non-ASCII scalars. Raw non-ASCII transport is rejected before parsing;
escaped Unicode diagnostics decode losslessly. Integer fields admit canonical
unsigned decimal lexemes only. There are no decimal floating values: F32 is one
raw U32 word, F64 is `[hi,lo]`.

| DTO | JSON shape |
| --- | --- |
| Hello | `[1,0,capability]` |
| Call | `[1,1,epoch,sequence,command]` |
| Frame command | `[0,width,height]` |
| Input command | `[1,packet]` |
| Release command | `[2]` |
| Action command | `[3,button]`, button 0 breaks, 1 places |
| Hotbar command | `[4,index]`, index 0 through 8 |
| Inventory command | `[5]` |
| HelloAck | `[1,0,epoch,0]` |
| FrameReply | `[1,1,epoch,sequence,sample]` |
| Ack | `[1,2,epoch,sequence]` |
| Fault | `[1,3,epoch,sequence,message]` |
| InventoryReply | `[1,4,epoch,sequence,inventory]` |
| ActionReply | `[1,5,epoch,sequence,changed,message]` |

The additive commands keep version 1 and every original tag/shape unchanged.
An inventory is `[selected,instabuild,maybuild,slots]`. It contains exactly 36
ordered main-inventory slots, with hotbar slots first. A slot is `[0]` for empty
or `[1,itemIdentifier,components,count]` for a stack. The current consumer admits
unmodified stone, dirt and oak planks only: the component string is empty and
count is 1 through 64. Selection is 0 through 8. Abilities are exact Booleans
owned by the backend; the client cannot set them through this wire.

Hotbar uses the existing Ack. An admitted Action uses ActionReply even for a
miss or a gameplay refusal (`changed=false` with a diagnostic); these outcomes
consume the expected sequence and keep the lease. Protocol/admission failures
still use Fault and close the socket. Inventory is an atomic actor read and
does not tick simulation. [PLAYER_BLOCK_INTERACTION.md](PLAYER_BLOCK_INTERACTION.md)
records the actual interaction scope and independent Java geometry evidence.

The sample is `[tick,revision,origin,camera,palette,neighborReads,cells]`.
Origin is `[xHi,xLo,yHi,yLo,zHi,zLo]`; camera is five F32 words in XYZ/yaw/pitch
order; palette is the actual dynamic `[air,stone,dirt,planks]` registry IDs.
Every cell has exactly ten U32 words:
`[x,y,z,boundary,state,material,visibleMask,relativeX,relativeY,relativeZ]`.
The final three values are raw F32 words. Decode reconstructs all three
`V.Sample` lists from the same ordered cells. Validation requires exact list
cardinality, raw/material/palette coherence, duplicate-free cells, masks in
0..63, identical raw/mask boundary flags, six neighbor reads per cell, finite
F64 origin and bit-exact relative positions, and a valid relative camera.

A packet is `[focused,captured,actions]`. Flags are JSON Booleans. Actions are
`[0]` for `CC.Release` or `[1,captured,event]` for `CC.PlatformEvent`.

| Base event | JSON shape |
| --- | --- |
| Key | `[0,code,down]` |
| Mouse | `[1,x,y,button,down]` |
| Move | `[2,x,y]` |
| Look | `[3,dxBits,dyBits]` |
| Scroll | `[4,x,y,dxBits,dyBits]` |
| Close | `[5]` |

Whole packets retain action order, per-action capture and final focus/capture;
no event or action is split into multiple actor operations. Raw input float
words, including signed zero and NaN payloads, are transported without decimal
conversion. The existing checked controller owns gameplay input admission.

## Refusal boundaries and verification

Both encoding and decoding enforce 65536 ASCII transport characters/bytes,
depth 8, and an independent 16384 JSON values including containers. The parser
character limit is 65536: a valid initial 256-cell frame is 16826 characters and
cannot fit the former conflated 16384-character limit. Existing diagnostic,
capability, epoch, input-action and inventory schema bounds remain separate.
Canonical ASCII means the character bound also limits byte length. Frame size is 4..1024 in
both axes; samples contain at most 4096 raw cells and 24576 neighbor reads.
`mesh_limits()` supplies the existing actual defaults: 4096 blocks, 1024
bindings, 4096 quads, 64 translucent quads and 256 tints, each below 16384.
Mesh expansion is enforced by the renderer against its loaded bindings, not
estimated by the wire codec. Packets contain at most 1024 actions; epochs are
nonempty printable ASCII up to 64 characters, capabilities up to 256, and
Unicode diagnostic text up to 2048 scalars. Smaller textual budgets can reject
an otherwise admitted sample or packet. No collection or string is truncated.
All tags, versions, tuple lengths and lexical shapes are exact; objects and
extra fields are refused.

Source checking passes with five concrete schema laws: raw Look decoding,
version refusal, extra Release-field refusal, sequence overflow refusal and
ordered packet roundtrip. A direct mathematical host check confirms the Nat48
bound. A maximal sequence decoding law was removed after its ordinary
normalization exceeded the small-check lane; no universal roundtrip proof is
claimed. Native sequence/float-word roundtrips, socket segmentation and invalid
byte rejection remain integration evidence to collect in the actual endpoints.
Pinned TCP.poll source inspection supports replacement of invalid bytes with
non-ASCII U+FFFD; decoded ASCII admission is therefore the intended rejection
boundary. This is not a native malformed-byte observation.

The additive finite checks in `tests/resource_client_interaction_wire.bend`
cover original and new serialization, all hotbar selections, ordered inventory
roundtrips, malformed slot counts/items/components/stacks, extra fields,
correlation and escaped Unicode. Their current execution status is recorded by
the combined playable-client acceptance artifact; prepared assertions alone
do not establish a native pass. No standalone native build accompanies this
module.
