# Complete entity membership image

`src/entity_membership_codec.bend` saves the actual
`entity_section_membership_model.View`: members, sections, observed chunks,
tracking registrations and ticking registrations. Every list retains its
original order. `inspect_encode(limits,state)` consumes the sole manager through
the existing `Membership.inspect` and returns that original owner alongside the
fallible encoded image.

The public persistence API is:

```bend
encode(limits:N.Limits,view:M.View)
  -> Result<&2,&2,String,List<&2,U32>>
decode(limits:N.Limits,bytes:List<&2,U32>)
  -> Result<&2,&2,String,M.View>
inspect_encode(limits:N.Limits,state:M.State)
  -> M.State & Result<&2,&2,String,List<&2,U32>>
```

The canonical NBT root `bendex:entity-membership` has six ordered fields:
`format` (Int 1), then `members`, `sections`, `chunks`, `tracked`, `ticked`
(each a list of compounds, including empty lists). Missing, additional,
duplicate, reordered or differently typed fields refuse the whole image.
The existing NBT byte, depth and aggregate element limits apply to the entire
payload; malformed input or a budget failure cannot yield a partial View.

Members retain dimension Char words in an IntArray, the raw entity ID,
packed section key, a Nat48 insertion order in TAG_Long, all twelve words of
the actual six-coordinate AABB and all four UUID words. Sections retain exact
ID insertion order. Chunks retain raw signed coordinate words, loaded flags
and visibility discriminants. Tracking and ticking registration lists retain
their independent orders. Exceptional F64 words, inverted boxes, opaque
dimensions, zero IDs and repeated numeric insertion orders are represented
without normalization because the manager's supplied image can contain them.

Structural admission requires unique dimension/ID and dimension/UUID members,
valid packed keys, unique sections, nonempty section IDs, exact section/member
links and insertion order, unique masked chunk columns, matching cached section
and chunk visibility, and complete tracking/ticking membership sets. It permits
unused chunk facts and unloaded populated sections. The relation between the
member list and a section is the reverse of that list's matching members: the
actual manager prepends newly inserted members and appends section IDs.

Decoding produces a Data image. Live restore must authenticate it against the
sole recovered entity records and the real loader. That join must validate
dimension, ID, UUID, physical bounding box, registered key, accessibility and
insertion order using the actual entity cursor, then reconstruct loaded and
visibility state from loader authority. Cached flags alone cannot grant live
tracking or ticking. The codec creates no entity owner, advances no cursor and
performs no manager installation. `None` in the format5 helper remains distinct
from `Some` of an empty manager.

Run the independent physical/native target with:

```sh
python3 tools/test_entity_membership_codec.py --prepare
python3 tools/test_entity_membership_codec.py --native
```

The original complete module source check passed in attempt003 (1.283 seconds,
empty stderr and unchanged imported source pins). Native attempt005 passed all
24 owner/raw/budget guards and 277 independently authored physical inputs:
20 accepted byte-exact roundtrips and 257 refusals. Its complete 2,562-byte
golden image has SHA256
`c46af64ea45a5c311213cd474f5febbf7fc05caa68890c31414fd084677087e9`.
All 105 imported source/tool pins stayed unchanged. C emission took 2.710
seconds, native compilation 5.707 seconds, owner guards 0.714 seconds and the
physical corpus 0.687 seconds. The compact reproducible receipt is
`evidence/entity-membership-codec-native.json`.

The real format5 TickStorage helper also consumed these codec APIs in its
separate native attempt003: 15 guards and 46 physical inputs passed, including
`None` versus `Some(empty)` and a combined-envelope byte refusal. That result
establishes payload integration; loader-authorized manager installation remains
open. Its substantive attempt004 added the complete nonempty manager image
beside entity recovery and clocks: all 15 guards and 47 physical inputs passed,
including six accepted byte-exact envelopes. The consumer receipt is
`evidence/local-player-cooking-tick-storage-004.json`. The five production proof
obligations are recorded separately from both native targets.
