# Typed component admission and prospective inventory replies

The component foundation, catalog admission and version 3 codec retain their
typed domain. A transport byte limit does not restrict an individual semantic
component profile. Empty/default identities and old version 2 wire records retain
their spelling and accepted counts.

`player_inventory.structural_slot` admits a nonempty identity only through the
complete closed typed stew validator. The actual mutation still obtains
authoritative `player_item_definitions.metadata` from the player's catalog.
The wire's key/slot decoders apply that same structural gate, with count 1 for a
modified stack. Acquisition count 0 remains the existing clear operation; modified
acquisition count 2 is refused. No marker/prefix alone grants admission.

The transport has a separate aggregate obligation. A request can fit its
65,536-byte envelope while its proposed inventory reply does not. In particular,
two ordered 1,200-effect profiles can each fit an Acquire request and collectively
exceed the MenuReply envelope. A failed reply encoding after mutation would leave
an owner the renderer cannot observe.

`remote_resource_transport.command_prepared` now checks an admitted inventory or
menu command inside the existing actor callback. `item_component_wire_candidate.prepare`
uses actual `Base.Array.clone` to retain an independent complete original
`I.State` while installing a candidate. It preserves all raw Array leaves/tree
shape, logical length, selected slot, abilities, definition catalog, raw status
words, opened flag, revision and derived result. The actual existing command runs
once. The actual encoder validates its exact epoch, sequence, acceptance,
diagnostic and snapshot before the callback can publish candidate state. The
socket receives the resulting preencoded text; it does not repeat encoding.

On refusal, the candidate is discarded and the complete original inventory and
recipe context/cache are restored. An admitted refusal renews the original lease
once, matching the presenter's consumed sequence. The fallback reports the
original snapshot without refreshing its cache and is itself preflighted. If
that original snapshot cannot encode, a compact fault closes the link. Neither
path truncates components or drops stacks. Invalid lease/sequence requests do
not clone or mutate the original actor. A later socket write failure remains
the existing committed-operation/disconnect boundary.

The eligible commands are Transfer, Acquire, MenuInspect, MenuOpen, MenuClose,
MenuClick and Select. Inspection is included because it refreshes derived
recipe output/cache. World-changing actions, frames and physical packets do not
use inventory-only rollback. The Session callback retains the singular world,
runtime, durable Shell and File lease. Before indexed menu access, the existing
crafting authority geometry guard rejects malformed public Array constructors.
Fallback inspection uses its structural snapshot walker.

The unchanged transport budget is 65,536 ASCII bytes, the parser budget 65,536
code points at depth 8, and the independent wire AST budget 16,384 values. Component
maps travel as canonical identity strings, so their escaped bytes count toward
the transport but their interior fields are not wire AST nodes. The MenuSnapshot
can contain 49 nonempty stacks: 36 main, 7 equipment, 4 crafting, carried and derived
result. Its visible InventoryMenu projection remains 46 slots. The independent
test corpus builds all 49 entries for every actual 17 recipe profile. The worst
permitted diagnostic consists of 2,048 supplementary Unicode scalars, which expand
to 24,576 ASCII escape bytes before quotes. With a 64-quote epoch, false flags,
maximum raw status words and Nat 48 headers, the longest actual recipe snapshot
is 65,401 bytes. This observation is evidence for those recipes, not a product
profile cap.

The version 3 inner IC decoder uses depth 8. Its payload is an NBT ByteArray in
the outer extension envelope; the outer depth 6 limit does not descend into
those inner bytes. No outer depth increase is required for this join.

Verification targets are `tools/item_component_wire_transport_check.py --build`
(actual Transport candidate, complete inventory/tree/context/lease and raw Core),
`tools/item_component_wire_check.py` (actual I/Wire admission, all 49-slot output
and existing default/frame corpus), and `tools/item_component_wire_proof.mjs`
(actual checked proof roots, retained declarations/types/bodies, exact kernel
scope). Source validation passed the original 7,345-event production and complete raw
observer graph. All 16 proposed laws passed ordinary checking against an unchanged
140-file snapshot; the full export refused one publication root because reachable
wire numeric rendering uses unsupported `Nat.show` mutual recursion. The independent
kernel rejected the remaining 15-root export at `json.encode_go` with
`affine live code, calls that descend`. The five actual clone/candidate laws
passed a separate unchanged-term export and independent kernel with zero exclusions;
this certifies five of the sixteen laws. A new two-root rollback export was
explicitly deferred during checkpoint prioritization and has no verdict. The native target
distinguishes 59 actual Transport cases, 614 admission/wire comparisons, and two
unequal-child Array constructors refused by the native ABI before Transport.
The ordinary native emitter reached its explicit 600-second bound without
producing C; its frozen graph, process receipt and failure remain preserved.
`tools/item_component_wire_cached_native.py` uses that exact unchanged graph
with the private emitter already tested on actor016. It retains the original
full checker, declaration order and holes check, and uses the original CPU
compiler flags. This route emitted 32,006,351 C bytes in 211.769 seconds including
source checking and process cleanup. Native compilation took 123.419 seconds.
All 59 complete Transport comparisons and 614 component/wire comparisons completed
successfully on that binary. Two unequal-child Array constructors separately
produced the expected native fail-stop. The appended legacy dispatcher stops at
its `overflow_menu()` construction of `1n + Wire.nat_max()`, beyond the native
48-bit immediate Nat range; the complete legacy dispatcher has no PASS claim.
The actual private-framing helper separately passed its fragmented 19,784-byte
frame, 65,536-byte boundary, oversize/non-ASCII atomic-refusal and CRLF probes.
Replay accepts its artifact through `tools/item_component_wire_transport_check.py
--binary build/item_component_wire_transport/private-native-001/observer` and
verifies its build manifest and frozen source/tool pins. Working-source differences
are recorded separately. The direct command observer does not execute the live
socket feed. Root integrated the resource-client framing adapter after the observed
16,384-scalar general-framing refusal and reported full large-request actor017
acceptance. This native observer retains its frozen older Transport generation;
the later socket acceptance is a distinct root-owned receipt.
The source and exact export scope are recorded in
`evidence/item_component_wire_source.json` and
`evidence/item_component_wire_proof.json`; the completed native scopes and retained
aggregate failures are in `evidence/item_component_wire_native.json`. These checks do
not establish physical OS acceptance, socket write recovery, durable world
publication or effect-consumption gameplay.
