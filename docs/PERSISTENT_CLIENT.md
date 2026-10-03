# Shared save-owning client instrument

`persistent_client.bend` connects the existing checked view/collision bridge to
the existing leased persistence wrapper and shared actor. The sole
`Game.Engine` lives inside `Persistence.State`. `PersistentClientWorld.State`
adds only an immutable `ClientWorld.View`; rendering and control queries
temporarily transfer that same engine into the bridge, then reattach it to the
same path, identity, high-water mark, limits and affine lease. No world or
registry clone is created.

The shared window/controller code lives in `src/client_host.bend`. Its closed
typed callbacks select the actor State for snapshot, move and look. The normal
ephemeral client still uses the existing legacy snapshot API. The save-owning
client uses `relative_snapshot`, so signed integer block coordinates and the
binary64 eye position are subtracted **before** narrowing to rendering F32.
The relative camera position is zero and its angles remain fresh.

## Run

```sh
python3 tools/platform_build.py persistent_client.bend \
  -o build/minecraft-persistent-client \
  --report build/persistent-client-build.json

MC_WORLD_PATH=/absolute/stable/world.nbt \
MC_WORLD_MISSING=create MC_DEV_TOKEN=your-configured-token \
MC_LIVE_PORT=47163 build/minecraft-persistent-client --gpu off \
  --verification-fixture
```

The existing client options `--jar PATH`, `--frames N` and `--dump PATH` apply.
`BEND_MINECRAFT_LAUNCH_MODE=hidden` selects the guarded automated window policy;
hidden launches do not grab the cursor. An absent frame limit runs until the
window closes. The current controls remain discrete quarter-unit verification
actions; actual held input, travel, jumping and vanilla player controls are
separate required work.

Startup requires the explicit verification-fixture option. It acquires and
retains the existing world lease, validates the registry identity and saved
world before listening, and carries the restored first-peer allocation into the
actor. An empty section store with tick/revision zero and no pending/events is
eligible for the explicitly requested fixture initializer. A restored populated
world uses `ClientWorld.new` and retains its blocks/clock; it is not recreated
from the scene recipe. Only the current finite palette/region can be rendered.
An incompatible or missing section/state rejects rather than fabricating air.

The existing developer `world.save` operation publishes the complete current
Core.World envelope. The catalog contains 17 operations. Save publication runs
inside the owning actor and reports publication/durability separately, exactly
as in the server wrapper. There is currently no automatic save on close.
View/body, player inventory/mode and mod state are not part of this envelope;
restarting constructs the default instrument view. Complete player/mod
persistence, migration, journal/recovery and vanilla save formats remain open.

## Verification

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  tools/test_persistent_client.py
```

The actual hidden native client starts with 39 rendered blocks at tick/revision
1/47. An authenticated TCP peer changes all 36 floor blocks and explicitly
steps the simulation to 2/83. Every pixel before and after matches an
independent float32 ray/texture oracle. `world.save` produces a 136,909-byte
snapshot checked by an independent NBT/world validator. A second actual client
loads that saved world, retains tick/revision 2/83, verifies all 36 edited cells,
and reproduces the edited frame. Its new peer exceeds the persisted high-water
mark. Reload leaves saved bytes unchanged. Both native processes exit zero and
their real listener ports refuse further connections.

`evidence/persistent-client-integration.json` records 49,152 independent pixel
comparisons, 500 initial and 150 restart frames, the native build/source/binary
hashes and explicit scope. `evidence/client-host-integration.json` separately
reruns the existing ephemeral client's 100-frame TCP edits and synthetic
Key/Look controller checks after the shared-host refactor. All recorded source
hashes are checked again after each integration run.

Confidence is **high for these recorded shared-ownership, edit/save/restart and
pixel observations**. They establish neither vanilla player gameplay nor
vanilla final-frame fidelity. The effectful adapter inherits the existing OS
durability/lease and unsafe actor/window lifetime boundaries. Its complete
program is outside the independent pure kernel verdict. The first measured
save-owning window build took 250.075 seconds under concurrent compilation;
generic host build overhead is being profiled separately and is not a runtime
performance claim.
