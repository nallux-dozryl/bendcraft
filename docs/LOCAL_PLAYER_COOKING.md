# Cooking in the saved LocalPlayer owner

`local_player_session.Shell` owns `local_player_cooking.Sidecar` alongside the
existing player inventory and persistence lease. The sidecar holds the actual
lighting arrays and loading cursor, keyed furnace/campfire owners, pending
cooking phase, released effects and accepted physical `CB.Details`. It contains
no Core world, player body or copied inventory. The sole Core remains inside
the existing player engine.

`Session.cooking_query` temporarily transfers that Core and the sidecar to one
operation, then reinstalls both in the same Session. `Runtime.Detached` carries
the player-only unsaved fields. `Runtime.Transient{player,cooking}` carries the
complete Session bundle detour; player attach accepts only `Detached`.

The actual Scene scheduled and realtime tick routes now call Session's cooking
tick. The player shape gate runs before the cooking mutation. Idle realtime
ticks respect Core pause; scheduled developer steps permit a paused tick.
Cooking completion enters `Runtime.status_after_world_tick` and
`Phase.prepare_after_world_tick`, which perform the existing common/player
phases without another Core step. A failed cooking finish retains its already
started Core tick and pending phase. A successful retry releases common/player
processing once even when the Core tick number did not change.

Startup uses `new_cooking_inventory(E.Ready<CookingStorage.Saved>, tables)` and
returns the adopted Session, pending physical bodies and the saved ordered
effect queue. Entry retains those values while terrain initialization, authenticated context installation,
lighting bootstrap and cooking discovery complete, then attaches each body
through `cooking_load_body` with the trusted loader capability. It restores the
exact queue once, then attempts delivery before opening listeners. A missing
publisher retains the returned owner and queue for recovery save. There is no
fallback context or separate world. The context uses the actual loaded registry,
recipes, initialized item defaults, feature admission and fuel providers.

Valid, permitted `world.save` collects every current cooking body's known
physical bytes and merges its retained root name and unknown/base fields using
`CookingStorage.with_details`. The bodies and unchanged inventory/player record
then enter the same existing `E.dispatch_codec` atomic Core/extension transaction.
The same publication includes a read-only snapshot of released pending effects;
returning from that transaction keeps the live queue without replaying the
snapshot. Empty bodies and an empty queue preserve the old payload bytes and
`IC.Saved` ABI; nonempty pending effects use the strict format2 wrapper. Pending
cooking and loading/discovery still refuse save while retaining the live owner. Ordinary queries continue using the existing codec
and do not collect physical bodies.

Accepted `Store.OwnerReset{position}` markers clear only the old keyed physical
details. Both retained pending-phase markers and completed-tick effects are
processed, including removal followed by recreation of the same block in one
due batch. Each accepted reset also increments its transient container incarnation once;
a pending finish retry does not count acknowledged markers again. The ordered
effects then pass to `cooking_effect_delivery.deliver`. It acknowledges applied
OwnerReset and zero-count notifications, and retains the first unavailable
effect with its complete suffix. Item/XP entities, level RNG and notification
publishers remain concrete owner dependencies.

Successful cooking completion runs common/player processing once before this
delivery attempt. A missing publisher blocks subsequent Core ticks. The player
runtime diagnostic records that fault but does not invalidate its canonical
record, so physical bodies and the exact suffix can still be saved atomically.
`cooking_take_effects` remains an explicit transfer accessor; the live consumer
uses the retaining delivery operation.

The additive `Session.cooking_inventory_query` passes the sole Core, cooking
sidecar and actual player inventory to one operation. Its returned owners are
installed together, with the complete remaining player owner, persistence
header and runtime tails retained. This is the container transaction seam;
menu validity, distance, capability and prospective reply admission belong to
the actual menu operation. The 018 source receipt predates this 019 addition and pending recovery.

The Initialized Sidecar has an affine recursive tail. The original native
compiler therefore gives the owner one boxed word rather than flattening it
into every captured Session closure. Fresh owners use Nil; every read/refusal
and detour retains arbitrary tails, and active mutation refuses noncanonical
tails. Immutable018 native emission failed at the generated parameter arity
guard (247 words); no native cooking binary was produced. The read-only layout
observation uses the unchanged compiler's actual `lay_of`/`fun_of` routines and
does not identify the failed emitted capture or establish a build verdict.

The source receipt in `evidence/local-player-cooking-source.json` records the
complete actual Entry graph checked by the original compiler's `book_valid`,
with no declaration selection or source changes during checking. This is a
typing/ownership verdict; it does not claim an independent-kernel proof,
native cooking gameplay, interruption recovery or full block-entity semantics.
The changed019 receipt in `evidence/local-player-cooking-source-019.json`
checks the actual complete Entry graph with recursive boxing and pending
recovery: 7,786 declarations, zero holes, 16.821739 seconds. The immutable019
native build subsequently passed its original arity guard and produced a
12,151,256-byte executable (SHA256
`641089cd1a7e1fd48467df39a4a74068e5d71c507964d5ada3dd03ff038516fd`).
Its native consumer acceptance and ownership proofs have separate receipts.

`evidence/local-player-cooking-proof.json` records one ordinary Book checking
seven new quantified laws plus the changed Detached constructor closures.
The independent kernel checks three supported roots: both complete Session
supplier splices and the actual Sidecar delivery-result splice. Their safe
export has zero exclusions. The four public gate laws are ordinary checked;
their full-definition export retains the unsupported `Nat.show.fin/go`
mutual recursion through real diagnostic branches. The prior refusals remain
recorded, and those four laws receive no kernel claim.

The existing cooking authority, physical codec and scheduled lifecycle evidence
remain applicable to their unchanged production modules. Actual cooker menu
and player inventory transactions, direct player edit lifecycle adoption,
real effect-owner delivery and native save/reload acceptance remain named
consumer work.

Generation20 adds an actual entity/RNG carrier inside the same boxed Sidecar.
`Owner.Bound` retains the authenticated entity context, sole `Model.State` and
every unconsumed raw constructor-clock input. `entity_snapshot` observes the
real owner with `Model.inspect`; a rejected bind returns the incoming affine
owner separately. Restore refuses an already bound owner and never manufactures
an RNG source from an absent saved View.

The changed Session save snapshots the complete entity View and clock queue
alongside bodies and pending effects into the same atomic format3 wrapper.
Returning from that transaction retains the live carrier rather than installing
the copied save snapshot. `new_cooking_inventory` now returns a fourth value,
`Maybe<EntityRecovery>`, for startup restoration after physical body admission.
An unbound actor preserves the old format1/2 bytes.

`Scene.realtime_step_io`, `Scene.advance_io` and `Scene.dispatch_io` close the
actual `local_player_cooking_entities.deliver_io` supplier. It uses
`cooking_effect_consumer.deliver_io`, then installs the returned entity owner,
pending suffix and remaining clock list together. An entropy retry does not
repeat a completed Core/player tick. Both the pre-tick and post-completion
delivery paths keep the sole Core in their IO continuation. Accepted menu
effects have the ordered `Session.cooking_enqueue_effects` seam.

`evidence/local-player-cooking-source-scene-020.json` checks this complete
actual Scene closure with the original Book: 6,934 declarations, 138 files,
zero holes, 14.646279 seconds. Its source hashes remained unchanged throughout
checking. This is a typing verdict, not final Entry adoption or native entity
gameplay. The initial matcher refusal and parser repairs are retained in
`evidence/local-player-cooking-integration-attempts-020.json`.

Fresh or legacy startup still needs the pinned Level random-factory transition
using actual monotonic observations. It cannot substitute the world seed for
Level's Legacy RNG or reconstruct a historical factory from an absent View.
Creation of a new XP orb currently refuses the missing actual collision
placement service; item creation and existing-orb merge plans remain supplied
by the real entity consumer. The separately owned geometry and Entry producers
must complete those joins before a fresh live entity-delivery claim.

Run the changed source check with:

```
python3 tools/test_local_player_cooking_source.py --generation 19
```
