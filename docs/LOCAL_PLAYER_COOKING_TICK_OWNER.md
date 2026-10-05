# Cooking tick recovery inside the live player owner

This working consumer follows the immutable actor021 checkpoint. It is not
part of the proposed actor022 overlay, which keeps actor021 scope and fixes
only measured native callback representation.

`EntityOwner.TickBound` retains one actual `Model.State`, its authenticated
context, remaining constructor-clock inputs, geometry owner and publication
owner. Its recursive metadata box contains exact runtime availability,
independent sound RNG and an optional saved section-manager image. The old
five-field `Bound` constructor remains available and saves its original
`EntityRecovery` representation. No second entity state is created.

The actual fresh bootstrap route retains the sound source from the existing
second factory call. Both calls still use their actual monotonic clock
observations, and the second advances the same constructor uniquifier. This
fresh isolated process has no existing entities, so its runtime list is known
empty. There is no third allocation or alias to LEVEL RNG. Existing saved
owners bypass both constructor calls. Earlier saves without runtime or sound
authority retain that absence.

`Session.cooking_entities` now uses `Cooking.saved_entity_snapshot`. For
TickBound it observes the real `Model.inspect` result and emits one
`CookingStorage.TickRecovery` image containing those entities, exact ordered
runtime entries, sound, clock inputs and manager availability. Loading this
variant installs that one entity image and retains all other fields unchanged.
It does not call a fresh-runtime constructor or install a manager.

Actual geometry, publisher and entity delivery detours preserve the metadata
box through their existing affine continuations, including refused effects
and unused clock inputs. Entity delivery currently does not invent runtime
entries for newly spawned records. A future item-tick caller must join the
actual constructor/runtime admission and refuse a missing per-ID runtime.

The complete persistence gate refuses a nonempty recursive metadata tail
before projection. The live owner and that tail remain intact. Canonical
metadata reaches the existing atomic player/body/effect/entity/publication
transaction through the native-verified format5 wrapper. The actual durable
writer receipt still controls publication journal acknowledgement.

Frame capture projects only the actual entity view into the shared immutable
render snapshot. Runtime, sound, clocks, manager data and publication owners
remain inside Session. The frame still observes the world sample and entity
view in one synchronous continuation.

A saved manager image is Data, with no live visibility or ticking authority.
Activation requires the parent's recovery validator and current loader
observations for record identity, position, cursor, registration and separate
visibility/load-completion state. Physical section residency, camera position
and cached flags do not supply those observations. Actual managed item ticks,
their callback publications and item pickup are separate consumer work.

## Verification

`python3 tools/test_local_player_cooking_tick_owner.py --generation 2` checks
the whole actual loaded consumer Book: 8,791 declarations, zero holes, and one
original `B.book_valid` call. This includes Session save/restore, Frame,
bootstrap, geometry/delivery and five meaningful owner composition laws.
Original checking plus unchanged selected export took 19.266075 seconds;
the five roots passed the independent kernel in 0.042453 seconds with zero
exclusions. All source hashes matched afterward and both process groups were
absent.

The laws cover complete bound restore refusal; arbitrary recursive metadata
tail save refusal; retained entity/runtime domains across a publisher detour;
actual inspection-result publication with every Sidecar owner; and the real
delivery-result continuation installing returned Engine, geometry, entity,
pending suffix and clocks while retaining all metadata. They establish no
native bootstrap timing, manager activation, item simulation or durable IO.
The separate storage owner has verified format5 native codecs; a coherent
future actor is still needed for live save/cold-restore acceptance.

Receipts are `evidence/local-player-cooking-tick-owner-source-002.json` and
`evidence/local-player-cooking-tick-owner-proof-002.json`. The initial harness
namespace failure is retained separately; it was fixed without a production
change. Actor021's independent twelve-law export failure remains recorded and
is not promoted by these five newer kernel roots.
