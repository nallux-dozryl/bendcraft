# Atomic remote entity scene

`remote_entity_frame.Frame` is the shared immutable DTO:
`Frame{sample:GS.Sample,entities:RenderModel.Snapshot,dimension:String,partial:F32}`.
The server owns the real Session and entity model. The DTO contains neither a
second mutable entity owner nor entity RNG, UUID, constructor clocks or health.

`local_player_entity_scene.capture` validates the requested frame and finite
fraction in `[0,1]`, obtains the actual player dimension, and reads the pose-aware
world sample followed by `Session.cooking_entities` in one pure continuation.
No simulation step or IO delivery occurs between these reads. The existing
sampler addresses the Overworld, so another current player dimension refuses.
An absent entity carrier is `Unbound`; an initialized empty carrier is
`Bound{[]}`. The render fraction is caller supplied, not a server clock reading.

The additive version-1 private protocol keeps command tags 0–19 and reply tags
0–8 intact:

```
request: [1,1,epoch,sequence,[20,width,height,partialF32Bits]]
reply:   [1,9,epoch,sequence,[sample,entities,dimension,partialF32Bits]]
sample:  [registry,tick,revision,originF64Words,cameraF32Words,cells]
entities: [0] | [1,[record,...]]
record:   [0,common,itemSlot,bobF32Bits] | [1,common,orbValue]
common:   [dimension,id,currentF64Words,oldF64Words,tickCount,
           removed,accessible,sourceOrder]
itemSlot: [0] | [1,itemId,completeComponents,count]
```

`remote_entity_snapshot_wire` strictly validates cardinalities, canonical
unsigned scalars, native Nat48 fields, canonical dimension identifiers, finite
position/bob words and the actual catalog-free item structural gate. It retains
record order and every admitted raw word, including signed zero. Duplicate
entity IDs refuse. Cross-dimension records, empty item records, orb value zero
and unordered/repeated source-order values remain represented; these are not
authority claims. Initialized catalog admission belongs to the item owner.

The reply uses the existing whole Wire envelope: 65,536 ASCII bytes, depth 8 and
16,384 AST values. It neither truncates records nor imposes a fixture-derived
record or item-key limit. `RemoteEntitySceneBackend.frame` admits the actual
lease before the capture and consumes it once. A whole reply that exceeds its
envelope fails encoding through the actual transport path.

`EntityWire.stamp` extracts registry, Core tick/revision, dimension, exact F64
origin, camera F32 words and fraction from the same frame. `checked_stamp` and
`Wire.scene_stamp_matches` refuse any mismatched stamp. Actual RemotePresenter
uses its existing epoch/sequence correlation and additionally requires the
requested fraction bits on a SceneFrame reply. Consumers combining independent
publications must use the full stamp check.

The observer is `tests/remote_entity_scene_wire.bend`, driven by
`tools/test_remote_entity_scene_wire.py`. Its 407 independent literal cases cover
old and new protocol tags, exact projected fields, strict malformed refusal,
19 stamp comparisons and eight header/fraction/stamp probes. One 1,200-effect
item key produces a 60,363-byte frame that fits; two produce 119,908 bytes that
refuse. A separate 700-orb frame is only 42,918 bytes but exceeds the 16,384-value
budget with 16,849 values. These expectations do not redefine product bounds.

The actual native codec passed all 407 literal cases in 4.735803 seconds:
134 admissions and 273 refusals, including the stamp/correlation probes above.
`evidence/remote-entity-scene-wire-native.json` identifies the artifact and its
frozen 157-file source/foreign manifest. C emission took 47.392042 seconds and
O3 clang took 11.587496 seconds. The existing private producer's nine-graph
C/GC equivalence basis is retained; no new original-CLI byte-equivalence claim
is made. A 120-second CLI source attempt and a later source-drift rejection are
retained. The complete original observer source book separately passed in
19.5846095 seconds with 4,931 declarations, 5,026 events and zero holes.

Reproduce the native codec boundary from a fresh directory:

```
python3 tools/test_remote_entity_scene_wire.py --phase build --verified-producer \
  --work build/remote-entity-scene-wire/FRESH \
  --binary build/remote-entity-scene-wire/FRESH/receiver \
  --build-report build/remote-entity-scene-wire/FRESH/native-build.json
python3 tools/test_remote_entity_scene_wire.py --phase native \
  --work build/remote-entity-scene-wire/FRESH \
  --binary build/remote-entity-scene-wire/FRESH/receiver \
  --build-report build/remote-entity-scene-wire/FRESH/native-build.json
```

`tools/test_remote_entity_scene_network.py` is a separate real TCP consumer. It
requires an explicitly selected successful actor generation greater than 20
whose frozen source has the real command20/atomic capture endpoint. Its seed is
the verified complete saved two-Item/one-Orb owner, preserving all RNG/factory
bytes on the server. It compares every projected record with that save, checks
old tag13 compatibility and lease/header refusals, and compares complete
physical saves before/after paused polling. The Entry initializes a bound
carrier, so network Unbound is explicitly unexercised. The codec corpus covers
Unbound and Bound-empty separately. This socket consumer has not run yet.

Immutable actor020 has no command20 and is not changed by this work. Codec
observations cannot establish Session capture atomicity, rendered pixels, OS
input, entity simulation or Java behavioral parity. The three extracted-stamp
and conditional complete-frame laws passed the independent kernel with zero
exclusions. Their complete original source closure has 3,814 declarations,
64 files and zero holes (7.427226 seconds); kernel checking took 0.015828
seconds. `evidence/remote-entity-snapshot-proof.json` records the exact roots
and term identities. These proofs do not establish parser authenticity,
initialized entity authority or actor serialization.

The actual new Transport/capture graph check reached an imported binder-order
failure in `local_player_cooking_publication_owner` after 5.286528 seconds.
Its owner repaired that location; the broader Sidecar/save join is still being
completed. This does not change the independently passed frozen codec or
stamp-law scopes. A coherent new actor and its TCP consumer remain required.
