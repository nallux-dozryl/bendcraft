# Direct player edits and cooking lifecycle

`local_player_cooking_edit.player_edit` joins the caller's sole `Core.World`
with the complete initialized `LocalPlayerCooking.Sidecar`. The current adapter
preserves the existing admission order: player capability/build permission;
initialized context and canonical sidecar tail; cooking phase, section discovery
and loading; actual store inspection and residency; light preparation and cooking
classification; positive sequence and matching expected revision; Core validation
and the actual resident block read. Light descriptors and cooking classification
come from the retained actor context.

After those checks, the adapter projects only immutable entry headers and checks
whether the actual first matching cooking owner would be reset. A reset requires
its keyed incarnation counter to be below the Nat48 maximum,
`281474976710655` (`2^48 - 1`); a missing counter means zero. Exhaustion returns
`local-cooking:authority:incarnation-exhausted` before the Core write, light/store
publication, physical Details removal or counter increment. The admitted branch
calls the original `CookingWorldEdit.world_apply`/PlayerCoreEdit path once.

The no-reset decision uses the actual `same_block` test: both block name and
cooking family must match. Property/LIT changes and an identical-state edit can
therefore succeed at MAX without consuming an incarnation token. They remain
actual player edits: Core records the actual tick/peer/sequence stamp and
increments its revision.

The successful operation publishes the existing light change and cooking store
change. Its ordered effects are appended once to the actor's existing queue.
Only newly returned `OwnerReset` markers remove physical block-entity Details
and increment their keyed incarnation counters. The phase's existing reset
acknowledgement is preserved. Refusal cannot publish those effects or reset
physical metadata. Entity/RNG ownership, raw clock inputs, live geometry
catalog/environment, the actual fifth publisher field with its journal and
recursive publisher tail, and recursive sidecar tails are carried through
unchanged.
Geometry captures are taken from current Core per delivered effect by the
existing delivery consumer; the adapter introduces no copied Core or light owner.

The current MAX preflight passed the original whole-book source checker over
5,252 entries in 9.675079 seconds. Its frozen 99-file native fixture passed all
39 guards: the 22 existing direct/ray edit observations and 17 new MAX cases.
The fixture carries the actual fifth publisher owner and observes its complete
journal, receipt, dirty-chunk list and recursive tail alongside the existing
Core, physical furnace, raw Details, light, RNG and geometry markers. The new
cases compare `Nat.show(MAX)` independently with the literal `281474976710655`,
refuse MAX teardown/replacement, preserve stale revision, zero-sequence,
permission and tail refusal precedence, accept same-owner identical/LIT edits
at MAX, and accept a MAX-1 teardown that reaches MAX exactly. Guarded C emission
took 32.260792 seconds, O3 CPU compilation 12.587666 seconds, dependency
rechecking 1.278640 seconds and native execution 0.715972 seconds. All groups
were reaped; native and clang stderr were empty.

The three new laws state prepared-owner retention on exhaustion, complete
outer-owner retention on that refusal, and capacity for an operation with no
reset. All their unchanged derivations passed original ordinary checking.
Their exact three-root export then failed in `Safe.ctr_term` with a JavaScript
`RangeError: Maximum call stack size exceeded`. A narrower selection of the
two owner-retention roots also passed whole-book checking and failed while
exporting constructors. Neither attempt produced an independent-kernel
closure or ran the kernel. The responsible term has not been isolated; the
two-root failure rules out attributing this solely to the no-reset root.
No axiom, substitute model, excluded-body export or compiler modification was
used. The current results and retained failures are recorded in
[local-player-cooking-edit-max-001.json](../evidence/local-player-cooking-edit-max-001.json)
and [local-player-cooking-edit-max-001-failures.json](../evidence/local-player-cooking-edit-max-001-failures.json).

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

The historical five BI authority/build-denial contracts were recertified against
their then-pinned source: original whole-book checking passed in 18.406 seconds,
and their unchanged 1,192,276-byte / 854-declaration exact closure passed the
pinned independent kernel in 0.188 seconds, with no exclusions. Raw evidence
is in `build/local-player-cooking-edit/legacy-bi-proof-001`. This certifies those
actual default wrappers; it does not certify the omitted Sidecar law roots.

The historical generation020 source snapshot was copied before the working BI
patch was applied. Its immutable source graph is unchanged. Motion wrote the
subsequent Session extraction/rejoin consumer. The historical focused fixture's
original source check passed in 9.330 seconds, with all 4,992 original entries checked.
Motion's separate complete Entry21 check includes the exact BI/Edit sources
and passed in 18.030 seconds over 9,054 entries / 191 files; its Session publication
helper independently passed the kernel. That separate receipt does not certify
these adapter laws or native fixture execution.

The original four adapter laws historically passed ordinary checking in 9.414
seconds. They quantify complete actual Core/Sidecar owners for disabled build, Observer and Player0
refusal, and complete Core/light/cooking-entry owners at the actual CWEdit
continuation for a PlayerCoreEdit refusal. The unchanged fourth root's complete
197,116-byte/316-declaration closure passed the pinned independent kernel.
The first three roots remain specifically excluded by the exporter's
Nat.show.fin/go mutual-recursion limitation reached through player_edit's
actual successful Sidecar error path. Their ordinary derivations are not
independent-kernel certificates. No replacement model or axiom is supplied.

The historical native fixture's 22 guards passed and exercised successful direct
and actual-ray furnace teardown, exact reset/drop/XP ordering, stale revision,
absent residency and complete retained raw Core/Sidecar observations. One
guarded ordinary C emission took 17.063 seconds, its direct CPU clang build
11.225 seconds, the cache/dependency recheck 1.112 seconds and the actual native
run 0.734 seconds. All process groups are reaped. Exact raw receipts and frozen
sources remain in `build/local-player-cooking-edit/native-001`; the compact
record is [local-player-cooking-edit-prepared-001.json](../evidence/local-player-cooking-edit-prepared-001.json).
That retained 22-guard receipt does not verify the current 39-guard fixture or
MAX preflight; the separate current receipt above does. No TCP, physical input,
complete placement or entity delivery IO
claim follows from these finite fixtures. The two earlier fixture attempts are
retained: a repaired match-order error and a parser
stack overflow on large raw numeric patterns, corrected to binders with exact
word comparisons without changing the payload or assertion.

The retained current-source commands used the existing original source checker,
the separate three-law overflow selection and the guarded C/native route:

```sh
python3 tools/test_local_player_cooking_edit.py --mode source --work build/local-player-cooking-edit/source-max-005
python3 tools/test_local_player_cooking_edit.py --mode overflow-proof --work build/local-player-cooking-edit/overflow-proof-max-001
python3 tools/test_local_player_cooking_edit.py --mode overflow-owner-proof --work build/local-player-cooking-edit/overflow-owner-proof-max-001
python3 tools/test_local_player_cooking_edit.py --mode native --work build/local-player-cooking-edit/native-max-001
```

The original complete four-law proof attempt returned the recorded three export
exclusions. Its historical included-proof check reused that retained artifact
and checked only the exact exportable CWEdit refusal root. Those exclusions and
the fourth-root certificate remain historical results; the new three-law
overflow selections do not replace them or establish a new certificate. Work
directories are immutable once executed; any changed-source check uses a new
directory. The native fixture's synthetic registry/context validates this
adapter contract and does not establish a new Java behavioral observation.

Motion's latest complete Entry012 check passed over 9,564 declarations / 211
loaded files with no holes in 4.75804225 seconds. Root copied the exact adapter
SHA256 `4b375bc890d7ab362127c730dca2aa34ae552d2c9512fdb024f60b05fa76bd5b`
into the immutable Actor021 snapshot. Those integration source facts do not
certify these three law roots or establish the eventual actor's native runtime
behavior. Core, CookingWorld, Session and the scheduled-tick guard remain owned
by their respective integration lanes.

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
