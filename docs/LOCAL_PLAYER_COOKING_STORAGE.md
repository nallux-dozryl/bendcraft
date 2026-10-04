# Cooking bodies in the atomic world save

`local_player_cooking_storage.Saved` wraps the unchanged
`player_inventory_codec.Saved` and an ordered list of
`Body{position:Core.Position,bytes:List<U32>}`. Empty cooking state encodes the
existing inventory payload exactly. Nonempty state uses the explicitly named
`bendex:local-player-cooking-record` NBT root with format 1, the existing player
payload as a ByteArray, and physical cooking bodies with their complete
dimension and raw signed-coordinate words. Duplicate positions, unsupported
formats and malformed wrapper fields refuse the complete decode.

The outer extension namespace/schema remain `bendex:local-player-record`/1.
Core, player inventory and cooking bodies therefore use the existing single
`extended_persistence` atomic publication and acknowledgment. There is no
separately acknowledged cooking file. Legacy player/inventory payloads decode
with an empty body list. The current wrapper uses the existing NBT defaults:
16 MiB bytes, depth 512 and 1,048,576 elements; the extension admits 16 MiB and
the outer file bound adds that budget to the existing default file bound.
These resource limits remain explicit.

The initialized item catalog is runtime data captured by one codec owner.
`extended_persistence.dispatch_codec` and `encode_codec` carry that owner
through the existing routing and encoding helpers. The closed-codec entry
points delegate to the same helpers. Schema checks, capability checks, peer
observation, request sequencing, atomic publication and acknowledgments
therefore remain shared with the existing world-save path.

The live cooking owner produces known cooking-body bytes. `with_details`
decodes those bytes as a Compound and reinserts the root name and ordered
unknown/base fields retained by the accepted physical load. It preserves
UTF-16 names, duplicate unknown fields, tag types and raw numeric bits.
Malformed or noncompound known bytes refuse the merge. These retained fields
are preserved physical data; this wrapper does not interpret base BlockEntity
components or grant item, fuel or player authority.

Entry restores the existing Core sections first, completes lighting bootstrap
and cooking-owner discovery, then loads each stored body against its actual
registered block. A failed body admission stops startup before ticks or
listeners. The Session save collector must retain the sole Core and affine
owners on any refusal, reject pending discovery/ticks or undelivered effects,
and collect every current body before the single atomic transaction. Accepted
owner-reset markers clear old keyed Details even when a due batch recreates
the same block. These live joins require the coherent actor consumer.

`python3 tools/test_local_player_cooking_storage.py` passed nine actual Bend
default-JavaScript guards in attempt 002. The checks cover byte-identical
empty inventory encoding, physical wrapper dimensions/coordinate words/body
order, duplicate positions, format/list rejection, physical extras and
malformed/noncompound merge refusal. Attempt 001 preserves a test-only
matcher-order failure; its repaired fixture passed without a production
change. This is high-confidence evidence for these codec boundaries. It is
not native actor interrupted-save/cold-reload acceptance or an independent
kernel proof. The standalone CLI proof-only command also rejects the existing
43 unsafe/foreign atomic-persistence dependencies; whole effectful actor
typing and mathematical proof scope are separate results.
