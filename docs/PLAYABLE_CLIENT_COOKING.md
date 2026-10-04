# Current cooking actor consumer

`tools/test_playable_client_cooking.py` consumes only the successful immutable
Actor004/producer018 artifact. It never builds an actor, compiles a checker, or
launches a foreground client. Its file-only preparation passed; native behavior
is pending the actual018 executable and the existing lane-capacity coordination.

Use the bundled Python runtime required by the existing actor helpers:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_playable_client_cooking.py --expectations
```

The native consumer uses the same command with `--native`. It reuses
`test_playable_client_actor004_boundary.artifact`, `PlayableBackend`, the actual
TCP/MCP clients, `R.bounded`, owned-group journals and descendant cleanup. It
requires the successful current018 build and pins its binary, source map,
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
   edits and the resulting unlit furnace. Verify that `world.save` refuses
   undelivered cooking intents and leaves the last durable bytes unchanged.

Every successful save compares all physical bytes for the atomic Core,
LocalPlayer, inventory, equipment, status, generation and cooking extension. The
independent decoder also checks the complete wrapper, keyed location/body and
peer highwater. A successful narrow native run will report `PASS_NARROW`; it
will explicitly report that post-reset keyed Details were not inspected.

## Actual operation hooks and missing consumers

The current public TCP/MCP hooks are `simulation.step`, `simulation.pause`,
`world.block.get`, scheduled `world.block.set`/`world.section.create`,
`player.inspect`, `world.clock` and `world.save`. Developer authorization is
supplied through the existing verification session. The scheduled edits and
Session tick route reach CW lifecycle/OwnerReset; the test does not use bare
Core advancement or the private direct CoreEdit renderer action.

There is no public/private-wire cooking body load/save/inspect command. Initial
body admission uses the actual Entry consumer of `CookingStorage.Saved`;
physical inspection uses the actual saved file after `world.save`. Session's
`cooking_take_effects` has no production caller. `persistence_ready` therefore
refuses queued intents with `local-cooking:save-undelivered-effects`, surfaced as
`SaveEncodingFailed`.

Consequently, the native test can verify accepted Core remove/recreate and the
required no-loss save refusal, but cannot observe cleared keyed extras through
this transport. That property remains the direct Session/lifecycle consumer's
obligation until actual item/XP/UI effect delivery supplies an observable
consumer. No effects are drained, omitted or acknowledged by the Python test.
Any completed campfire tick also queues BlockUpdate/BlockChange records, even
when their counts are zero; this fixture uses an effect-free in-progress furnace
instead. Cooking completion/drop/XP delivery, cooking UI, native OS controls,
light-field parity and whole-game completion are outside this narrow check.
