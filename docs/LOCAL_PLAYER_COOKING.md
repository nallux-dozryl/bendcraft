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
actual Session `cooking_deliver_pending_io` supplier. Its current Engine route invokes `local_player_cooking_entities.deliver_engine_io`. It uses
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

The later generation20 working source adds the fresh isolated actor factory
boundary. Absent recovery uses two actual monotonic clock observations: one
Level Legacy factory and one sound factory advance of the same uniquifier.
A saved complete View restores without either draw. This is the explicitly
supported isolated factory/ID profile; it does not infer a historical seed or
cursor. The entity context uses the authenticated cooking items and explicit
whole-effect resource budgets (4096 spawn steps, 65536 rejection/ID steps),
with no other resident entity-ID owner. A different Level still needs its own
random owner; item/XP effects outside the overworld refuse with their suffix.

The same carrier now retains an authenticated affine Slab collision catalog
and the actual driver's declared collision environment. Entry loads
`generated/reference_slab_collision.tsv` against the retained live Registry
after physical bodies and entity-owner initialization. The actual Scene IO
supplier moves Engine plus Sidecar, permitting the parent's shape capture to
return the sole Core, Registry and catalog together. Every saved/player/Shell
field remains in the Session detour. Geometry is transient and reauthenticated
on reload; complete RNG/entity View and unused clocks remain durable format3.

Ordered delivery first attempts each atomic effect using the real entity
consumer. Existing-orb merges require no shape query. Only a new-orb placement
request captures a fresh current Core region and retries that uncommitted
effect with retained clock inputs. Successful earlier effects are preserved;
a missing section, unsupported state, unresolved border/entity policy or later
missing publisher retains the complete current suffix. The shape scanner has
its actual one-block halo; absent sections are never treated as air. This
catalog currently supports the actual neutral full blocks and registered slab
shapes, and does not invent furnace collision support. Dirty/comparator,
nonzero block-update and game-event publication remain explicit dependencies.

The earlier Scene020 receipt above predates these bootstrap and geometry
changes. The complete changed Entry now passes the original Book with 8,998
declarations, 187 imported files, zero holes and 18.232369 seconds in
`evidence/local-player-cooking-source-020.json`. Every source hash remained
unchanged during checking and matches the retained working source. This covers
the actual IO serving driver, authenticated defaults/collision catalog,
bootstrap, geometry/delivery and format3 save/recovery integration. It does
not establish native gameplay or save/reload execution; those verdicts belong
to the actual generation20 consumer. The six prior full Entry refusals remain
in the generation20 failure ledger, including the new driver matcher/recursion
repairs and actual Backend/Transport/Entry ownership annotations.

Run the changed full Entry source check with:

```
python3 tools/test_local_player_cooking_source.py --generation 20
```

The frozen generation 20 native consumer now passes the actual private actor
path in `evidence/playable-client-cooking-entities-native-005.json`: five
complete atomic saves, two SIGKILL/cold restores, two complete item entities
and an XP orb of value 7. It observes the exact retained record/factory/ID
fields, constructor-clock bounds, 45 Level RNG draws during publication and
18 draws from cold empty-drop delivery, and clears the old physical Details.
This is the narrow real delivery/save/recovery scenario, not item pickup,
multi-Level ownership or visible gameplay acceptance.

The following generation 21 working source joins direct player block edits to
the same cooking Sidecar. `Session.block_action_detached` transfers its actual
Engine, Sidecar and motion tables to `BI.execute_with_owner` with
`CookingEdit.edit`. The returned continuation installs all three returned
owners and preserves the player record, inventory, persistence header/lease,
view, physical controls, block-inside receiver, diagnostic and all runtime
tails. Refused outcomes also publish their actual returned owners; the Session
does not infer rollback from `Outcome.changed=False`.

Accepted edits use the real `CWEdit.player_edit` path and append its ordered
effects once. Only new accepted OwnerReset markers clear keyed Details and
increment container incarnation. The same retained entity/RNG/clock/geometry
carrier remains in the Sidecar. Rejected edits do not publish a reset. The
block-interaction owner separately added pinned full-cube furnace, smoker and
blast-furnace outlines for picking; campfire picking remains unsupported, and
this outline admission does not add cooker collision support to the geometry
catalog.

`evidence/local-player-cooking-source-021.json` records one complete original
Entry Book plus the two actual Session edit laws: 9054 declarations, 191 files,
zero holes and 18.0295 seconds. Both laws pass ordinary checking. The pure
returned-owner continuation also passes the independent kernel in 0.014642
seconds with zero export exclusions, recorded in
`evidence/local-player-cooking-session-edit-proof-021.json`. This root permits
arbitrary returned Engine/Sidecar/tables, inventory and player/save/receiver
tails and either outcome. It does not prove BI ray/placement/admission,
`Runtime.attach` losslessness, cooking lifecycle algorithms or native player
edit gameplay. The actual detached-consumer law uses the complete real BI
result as its explicit premise and receives only the ordinary verdict.

The host receipt helper initially compared its text result with bytes after
both compiler and kernel had already passed. That assertion was repaired and
the existing outputs finalized after verifying all 191 source hashes. Its
failure is retained in the same build folder; neither check was repeated.
The frozen generation 20 graph and its consumer receipt remain unchanged.

Run the changed consumer and owner-law check with:

```
python3 tools/test_local_player_cooking_source.py --generation 21 --edit-proof
```
