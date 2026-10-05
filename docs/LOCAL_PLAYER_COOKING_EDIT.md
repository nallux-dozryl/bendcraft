# Direct player edits and cooking lifecycle

`local_player_cooking_edit.player_edit` joins the caller's sole `Core.World`
with the complete initialized `LocalPlayerCooking.Sidecar`, then calls the
existing `CookingWorldEdit.player_edit`. Light descriptors and cooking
classification come from the retained actor context. Player capability,
observed build permission, sequence, expected revision and existing-section
checks remain in the actual PlayerCoreEdit path.

The successful operation publishes the existing light change and cooking store
change. Its ordered effects are appended once to the actor's existing queue.
Only newly returned `OwnerReset` markers remove physical block-entity Details
and increment their keyed incarnation counters. The phase's existing reset
acknowledgement is preserved. Refusal cannot publish those effects or reset
physical metadata. Entity/RNG ownership, raw clock inputs, live geometry
catalog/environment and recursive sidecar tails are carried through unchanged.
Geometry captures are taken from current Core per delivered effect by the
existing delivery consumer; the adapter introduces no copied Core or light owner.

The additive BlockInteraction interface is:

```text
BI.execute_with_owner(Extra, editor, extra, engine, record, tables,
                      abilities, held, capability, sequence, button)
  -> Engine & Extra & Tables & BI.Outcome

editor : BI.Authority -> Engine -> Extra -> Position -> U32
         -> Engine & Extra & BI.Outcome
```

`Extra=Cooking.Sidecar` and `editor=CookingEdit.edit` fit the actual Session
Shell extraction/rejoin. The same ray, reach, shape, placement, held-item and
ability checks serve both paths. Every legacy public BI wrapper retains its
signature and uses the actual old Core editor with `Extra=Unit`.

The generation020 source snapshot was copied before the working BI patch was
applied. Its immutable source graph is unchanged. Motion has written the
subsequent Session extraction/rejoin consumer. The focused fixture's original
source check passes in 9.330 seconds, with all 4,992 original entries checked.
Motion's separate complete Entry21 check includes the exact BI/Edit sources
and passes in 18.030 seconds over 9,054 entries / 191 files; its Session publication
helper independently passes the kernel. That separate receipt does not certify
these adapter laws or native fixture execution.

All four adapter laws pass ordinary checking in 9.414 seconds. They quantify
complete actual Core/Sidecar owners for disabled build, Observer and Player0
refusal, and complete Core/light/cooking-entry owners at the actual CWEdit
continuation for a PlayerCoreEdit refusal. The unchanged fourth root's complete
197,116-byte/316-declaration closure passes the pinned independent kernel.
The first three roots remain specifically excluded by the exporter's
Nat.show.fin/go mutual-recursion limitation reached through player_edit's
actual successful Sidecar error path. Their ordinary derivations are not
independent-kernel certificates. No replacement model or axiom is supplied.

The native fixture's 22 guards pass and exercise successful direct and
actual-ray furnace teardown, exact reset/drop/XP ordering, stale revision,
absent residency and complete retained raw Core/Sidecar observations. One
guarded ordinary C emission takes 17.063 seconds, its direct CPU clang build
11.225 seconds, the cache/dependency recheck 1.112 seconds and the actual native
run 0.734 seconds. All process groups are reaped. Exact raw receipts and frozen
sources remain in `build/local-player-cooking-edit/native-001`; the compact
record is [local-player-cooking-edit-prepared-001.json](../evidence/local-player-cooking-edit-prepared-001.json).
No TCP, physical input, complete placement or entity delivery IO claim follows
from these finite fixtures. The two earlier
fixture attempts are retained: a repaired match-order error and a parser
stack overflow on large raw numeric patterns, corrected to binders with exact
word comparisons without changing the payload or assertion.

Focused commands use the existing original source checker and guarded C/native
route. Each work directory must be new:

```sh
python3 tools/test_local_player_cooking_edit.py --mode source --work build/local-player-cooking-edit/source-004
python3 tools/test_local_player_cooking_edit.py --mode proof --work build/local-player-cooking-edit/proof-002
python3 tools/test_local_player_cooking_edit.py --mode included-proof --export build/local-player-cooking-edit/proof-001 --work build/local-player-cooking-edit/included-proof-002
python3 tools/test_local_player_cooking_edit.py --mode native --work build/local-player-cooking-edit/native-002
```

The complete proof command currently returns the recorded three export
exclusions. The included-proof command reuses that retained artifact and checks
only the exact exportable refusal root. Use fresh directories for a new run.

Picking now admits furnace, smoker and blast furnace. In the pinned 26.3 JAR,
each concrete class inherits `getShape` through AbstractFurnaceBlock,
BaseEntityBlock and Block to BlockBehaviour. That method returns Shapes.block()
with no state-dependent branch. The returned BLOCK is a filled 1×1×1
CubeVoxelShape. This establishes the outline used by picking for every state;
it does not infer collision properties or change the separate empty interaction
shape. Campfire remains outside BI's full cube set. The fixture additionally
uses actual Core reads, Registry dispatch, DDA and cube clip to select a furnace
south face, then the injected editor to perform the same verified teardown
observations. Its registry IDs are explicitly synthetic test IDs.

The retained evidence is [player-cooking-protocol-reference.json](../evidence/player-cooking-protocol-reference.json),
with the complete extracted members and hashes in
[player_cooking_protocol.json](../reference/player_cooking_protocol.json)
(SHA256 28bfe6fa8dfd422e7df04375bdaaff84c04423e02c9bdb4bc7dfbff6e5a1eecb).
It is reproducible with `python3 tools/reference_player_cooking_protocol.py`;
this static extraction starts no JVM or game. Its pinned 26.3 JAR SHA256 is
4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d.

This change does not approximate skylight/RGB lighting or frontend lighting.
