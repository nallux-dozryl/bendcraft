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
returns the adopted Session plus pending physical bodies. Entry retains those
bytes while terrain initialization, authenticated context installation,
lighting bootstrap and cooking discovery complete, then attaches each body
through `cooking_load_body` with the trusted loader capability. There is no
fallback context or separate world. The context uses the actual loaded registry,
recipes, initialized item defaults, feature admission and fuel providers.

Valid, permitted `world.save` collects every current cooking body's known
physical bytes and merges its retained root name and unknown/base fields using
`CookingStorage.with_details`. The bodies and unchanged inventory/player record
then enter the same existing `E.dispatch` atomic Core/extension transaction.
Empty body lists preserve the old payload bytes and `IC.Saved` ABI. Pending
cooking, loading/discovery and undelivered released effects refuse save while
retaining the live owner. Ordinary queries continue using the existing codec
and do not collect physical bodies.

Accepted `Store.OwnerReset{position}` markers clear only the old keyed physical
details. Both retained pending-phase markers and completed-tick effects are
processed, including removal followed by recreation of the same block in one
due batch. The ordered effects themselves remain queued until an actual
consumer takes them. Taking effects transfers their delivery responsibility;
the accessor alone does not spawn items, grant XP or publish notifications.

The source receipt in `evidence/local-player-cooking-source.json` records the
complete actual Entry graph checked by the original compiler's `book_valid`,
with no declaration selection or source changes during checking. This is a
typing/ownership verdict; it does not claim an independent-kernel proof,
native cooking gameplay, interruption recovery or full block-entity semantics.
The existing cooking authority, physical codec and scheduled lifecycle evidence
remain applicable to their unchanged production modules. Actual cooker menu
and player inventory transactions, direct player edit lifecycle adoption,
effect delivery and native save/reload acceptance remain named consumer work.

Run the changed source check with:

```
python3 tools/test_local_player_cooking_source.py
```
