# Historical bounded custom superflat scene

The regular saved client source now uses typed durable settings and demand
population described in [WORLD_GENERATION.md](WORLD_GENERATION.md). The fixed
75-section layout and native test expectations below remain the historical
instrument/reference scope; they are not production Minecraft world bounds.

The original bounded client instrument uses the explicit profile `bendex:stone-dirt-superflat`:
one stone layer, two dirt layers, and one stone surface layer, starting at
Overworld `min_y=-64`. Player feet start at `(0.5,-60,0.5)`. These names resolve
through the loaded registry; state IDs are not built into the generator.

`src/superflat_world.bend` creates five by five complete chunk columns with
world x/z coordinates `-32..47`. Three complete sections per column cover
y=`-80..-33`, including an air section below vanilla's build minimum and loaded
air above the four terrain layers. There are 75 sections, 307,200 loaded cells,
and 25,600 terrain writes. Generation accepts one Core revision at tick zero;
it leaves time zero and the world paused. Core sections remain authoritative
for rendering, collision, interaction, and persistence.

`ClassicFlat{}` represents the independently observed vanilla preset's
bedrock/dirt/dirt/grass layers. Its focused test covers Core generation. The
playable renderer and world adapters retain their supported stone/dirt/planks
domain, so this profile does not establish classic-flat client parity.

## Owned startup and view

`Scene.initialize_superflat` queries the nondurable fresh/load provenance
carried from the inventory codec initializer or decoder through the session.
Only genuinely fresh sessions may generate terrain and call `R.fresh` with the
same owned world and sine tables. This anchors Body, support, fall history,
controller state, and common-tick historical positions together. The fresh
flag is cleared after successful initialization. A decoded empty Core is still
a loaded save; its LocalPlayer record is retained.

The generator's separate pure Core guard requires empty sections, tick/time/
revision zero, pause and daylight enabled, and no pending edits or events.
It transfers and returns the same owned section map. This guard avoids importing
the persistence module into the standalone terrain verification graph; it does
not replace the session's fresh/load provenance check.

Loaded sessions keep Core, player state, tables, time, pause, pending edits,
and events. Startup changes the transient render aperture around the restored
body. A body whose floored position lies outside x/z=`-32..47`, y=`-80..-33`
receives `unsupported-superflat-view:outside-generated-region`. That failure
releases the startup lease without publishing a save. A legacy fixture at y=1
therefore needs the existing explicitly named verification-fixture route.
The saved format currently has no persistent terrain-profile marker; an
in-range loaded body is not proof that every expected section exists.

The transient aperture is 8×8×8. Its origins clamp to x/z=`-31..39`,
y=`-79..-41`, leaving a complete loaded one-cell neighbor halo on every face.
Floored coordinates are range checked and clamped before offsets are
subtracted, so `INT_MIN` cannot wrap to the opposite edge. A fully filled
aperture contains at most 512 supported full cubes, or 3,072 source quads,
within the model producer's 4,096 pre-occlusion limit.

Scene realtime steps and dispatches refresh this aperture through the existing
runtime world owner. Unchanged bounds retain the snapshot cache; changed bounds
invalidate it. Height-six verification-fixture views retain their old behavior.
This follows the player within the finite footprint; it does not stream or
generate additional chunks.

## Independent reference and focused verification

`tools/reference_superflat_probe.py --signatures` reuses the existing verified
official 26.3 server extraction and library classpath. `--observe` creates
real `FlatLevelGeneratorSettings` through `RegistryOps` and its production
codec, constructs untouched `FlatLevelSource`, and invokes `getBaseColumn` and
`getBaseHeight` at eight coordinates crossing negative and positive chunk
boundaries for each profile. It records 16 columns and 160 cell states. The
accessor supplies minY `-64`, height `384`; an unused `RandomState` argument is
Java null. Structure overrides are explicitly empty.

The observed four-layer states are exactly:

| Profile | y=-64 | y=-63 | y=-62 | y=-61 | y=-60 |
| --- | --- | --- | --- | --- | --- |
| Custom | stone 1 | dirt 10 | dirt 10 | stone 1 | air 0 |
| Classic | bedrock 88 | dirt 10 | dirt 10 | grass_block 9 | air 0 |

In this recorded standalone bootstrap, `WORLD_SURFACE` and
`WORLD_SURFACE_WG` base heights are `-60`; motion-blocking and ocean-floor
variants return `-64`. Those actual results are retained without treating
all height variants as interchangeable. No Bend base-height API is claimed.
These observations establish the recorded base-column/base-height calls;
chunk filling, structures, features, biomes, noise terrain, world spawn
selection, lighting, and complete world generation remain outside this test.

Three small installed-JAR entries record official flat preset, classic preset,
and Overworld dimension metadata, with their exact hashes in
`reference/superflat_world.json`. This does not repeat the full installed asset
inventory. The initial javap batch used the wrong package for `NoiseColumn`;
javap returned zero but printed class-not-found. Its raw receipt is preserved,
and a separate corrected `net.minecraft.world.level.NoiseColumn` extraction is
retained. Generator and settings signatures succeeded in the initial batch.

`tools/test_superflat_world.py --prepare` runs only host fixture/comparator
checks and prepares four modes for the root's single playable test artifact:
custom generation, classic Core generation, signed aperture bounds, and cache
follow. Generation compares every section's ordered 4,096-word FNV digest
against fixed section layout plus actual Java columns; the 32-bit digest is a
bounded regression checksum, not a collision-free proof. Eight complete
sampled columns and three outside-coordinate reads are also compared directly.
The edited-world case preserves time, pause, daylight, pending edits, event
history, complete Body/View/cache fields, and section digests through
reinitialization. Nondefault velocity, collision flags, camera angles and cache
contents make reset-to-default failures visible. Five injected
host-output corruptions must be rejected. Native simulation and integrated
save/cold-load checks execute only through the root's admitted shared artifact.

Raw reference argv, stdout, stderr, deadlines, exit status, process-group
cleanup and leader reaping are retained under
`build/superflat-world/reference/`. Summaries are in
`evidence/superflat-world-reference.json` and
`evidence/superflat-world-preparation.json`. Ordinary and native results must
be reported separately; preparation alone establishes neither.

The first bounded ordinary checks caught a local Boolean match in the new
coordinate helper and an imported block-interaction computed-Body destructure.
Their raw diagnostics remain under `ordinary-superflat`, `ordinary-harness`,
and `ordinary-scene`. The coordinate/cache helpers and corresponding test
parser destructures were split into parameter helpers. A fresh bounded check
must establish those repairs; the old failures are not overwritten.

The first repair check then reached the persistent-world import's 31 custom
foreign-code boundaries, and the harness exposed a Char separator requirement.
The standalone terrain module now uses the pure Core guard above, and the
harness supplies a Char separator. Those historical receipts remain unchanged.

The final commands `bend src/superflat_world.bend --check-only` and
`bend tests/superflat_world.bend --check-only` both report `ALL PROOFS CHECK`,
with empty stderr and no custom foreign-boundary refusals. Each completed in
about 1.16 seconds under its 30-second deadline; owned process groups were
absent and leaders reaped. `evidence/superflat-world-ordinary-final.json` pins
the checked source bytes and full receipts. This is ordinary checking;
`--verdict` and native gameplay were not run by the terrain lane.
