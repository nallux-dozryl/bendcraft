# Current cooking actor consumer

`tools/test_playable_client_cooking.py` consumes an explicitly selected successful
immutable actor artifact. Current preparation targets Actor004/producer019 with
`--actor-generation 19`. The selection binds the existing actor helper's `WORK`,
`SOURCE` and `ACTOR` together; it never falls back to another generation. It never
builds an actor, compiles a checker, or launches a foreground client. File-only
preparation passed; native behavior is pending a successful actual019 executable
and the existing lane-capacity coordination.

The retained producer018 prepared receipt records file-only preparation only.
Its actual producer later failed native arity greater than247, with no emitted C.
The new source generation boxes the cooking sidecar and adds atomic pending-intent
recovery. This consumer has not established a native verdict for either generation.

Use the bundled Python runtime required by the existing actor helpers:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_playable_client_cooking.py --actor-generation 19 --expectations
```

The native consumer uses the same command with `--native`. It reuses
`test_playable_client_actor004_boundary.artifact`, `PlayableBackend`, the actual
TCP/MCP clients, `R.bounded`, owned-group journals and descendant cleanup. It
requires the successful selected build and pins its binary, source map,
runtime facts, installed26.3 JAR and independent references. No native run has
been performed by this preparation.

The fixture contains one real loaded Core section, a standing player and one
north-facing lit furnace. It uses the existing `W.Unspecified` legacy generation
metadata (`format=1`, `kind=unspecified`, empty payload), encoded by the actual
WG codec schema and retained byte for byte. Scene's legacy admission preserves
this loaded section; this fixture makes no generated-terrain behavior claim.
Its bootstrap budget is the actual section-derived 4100 units. The saved furnace
contains beef2, coal2, progress40/total200,
remaining burn10/total10 and speed1. The body uses the physical receiver's tag
types and retains its root UTF16 code units, unknown fields, duplicate unknown
names and raw floating/integer words through accepted `Details`.

The expected first tick composes the actual pinned Java `lit_progress` receiver
observation (progress41, remaining9, no dirty/drop/LIT-change effects) with the
actual Java-decoded and original-JAR `minecraft:cooked_beef` recipe, whose time
is200. This is an explicit recipe-parameter inference, not a retained full-world
Java beef-tick observation. The physical unknown-field input is reused from
`reference_cooking_block_entity_codec.inputs()` and its recorded Java acceptance.
The test does not interpret raw CustomName/Lock/base fields as gameplay authority.

The prepared native sequence is:

1. Cold-start the actual Entry from the physical cooking wrapper. Verify that
   startup/discovery did not advance Core, then acknowledge the complete save.
2. Invoke one paused `simulation.step` through real TCP. Verify the sole Core
   clock/player tick and full effect-free furnace body, then acknowledge a
   complete atomic save through actual MCP.
3. Perform another unsaved in-progress tick, SIGKILL the actual owned actor
   group, cold-start another actual actor and verify the last acknowledged
   Core/player/body/Details snapshot. A further complete save must retain it.
4. Schedule removal and recreation of the same furnace through real
   `world.block.set`, then one `simulation.step`. Observe both accepted Core
   edits and the resulting unlit furnace. Acknowledge a complete atomic save
   containing its fresh empty physical body and the ordered pending Drop intents.
   The fresh body must have an empty root name, four zero timers, speed1, empty
   Items with element type0, empty RecipesUsed, and no prior unknown/base fields.
5. Request another step; the unsupported pending queue must leave Core and player
   unchanged. SIGKILL, cold-start a third actor from the acknowledged reset save,
   retry that blocked step, and acknowledge another complete save with the exact
   restored ordered queue and fresh body.

Every successful save compares all physical bytes for the atomic Core,
LocalPlayer, inventory, equipment, status, generation and cooking extension. All
five saves are compared. The
independent decoder also checks the complete wrapper, keyed location/body and
peer highwater. A successful narrow native run will report `PASS_NARROW`; the
post-reset saved physical projection exposes whether keyed Details were cleared.

## Actual operation hooks and missing consumers

The current public TCP/MCP hooks are `simulation.step`, `simulation.pause`,
`world.block.get`, scheduled `world.block.set`/`world.section.create`,
`player.inspect`, `world.clock` and `world.save`. Developer authorization is
supplied through the existing verification session. The scheduled edits and
Session tick route reach CW lifecycle/OwnerReset; the test does not use bare
Core advancement or the private direct CoreEdit renderer action.

There is no public/private-wire cooking body load/save/inspect command. Initial
body admission uses the actual Entry consumer of `CookingStorage.Saved`;
physical inspection uses the actual saved file after `world.save`. Startup restores
the saved ordered queue only after body admission, then tries the actual safe
delivery consumer before listeners. A missing owner retains the queue and records
the returned error without discarding a viable recovery session. Session's next
tick retries delivery before beginning another Core tick; completion runs player
work once before trying delivery.

No real item-entity, XP-orb, level-RNG or comparator publisher is supplied by this
join. The safe consumer takes the already applied OwnerReset prefix and zero-count
notification prefixes; at the first unsupported effect it retains the entire
ordered suffix. Even an empty Drop requires the missing real entity/RNG owner.
For this fixture the retained suffix is exactly slot0 beef2, slot1 coal2, slot2
empty, with empty unchanged-default component identities and no XP records.

The format1 body wrapper and empty-body player payload remain byte exact when
the queue is empty. A nonempty queue uses wrapper format2 with ordered
`format`, `player`, `bodies`, `effects:ByteArray`; the ByteArray contains the
`bendex:cooking-effects` root, format1 and its ordered Compound effect list.
Drop records preserve raw identifier/component character words, position words,
counts and empty items. These are internal recovery intents, not delivered entities.

No effects are drained, simulated or acknowledged by Python. An effect-free
in-progress furnace supplies the initial tick; a completed campfire emits
notification records and would exercise a different delivery boundary. Cooking
completion/drop/XP delivery, cooking UI, native OS controls, light-field parity
and whole-game completion remain outside this narrow check.
