# Cooking client delivery

The public launcher now selects the verified Actor023/Generic012 pair. Run
`./tools/play_minecraft_cooking_demo.sh` for a fresh unpaused cooking world.
It creates a separate save and prints its exact resume command. Confidence is
high for the recorded limited cooking/save/reload slice. Coordinated foreground
OS input and presentation acceptance remains pending.

The launcher pins Actor023 SHA `7fd7ee9269802a6e128716f53bf34030ec592728ef954f9b61bebecac36719d1`
and Generic012 SHA `3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232`.
It retains `MC_COOKING_PROTOCOL=1` in its private reconnect metadata. The existing
cooking-aware shutdown helper is root-owned and separately verified against
real opened, full-inventory and stale handles.

The conventional loopback ports are occupied by protected historical Actor012.
When no explicit port is supplied, the launcher tries 25565/25566 and otherwise
selects two free distinct loopback ports, excluding either explicit override.
Explicit ports and reconnect metadata remain authoritative. The new default
world path is separate from `build/playable-world.nbt`; the demo additionally
copies an independently validated unpaused seed into a unique world directory.
The demo prints the exact `MC_WORLD_PATH=... tools/play_minecraft.sh` command to
reopen its saved world. A refused close retains the existing mode-0600 reconnect path.

The demo supplies `--hud-scale 3` before user arguments so the panel is usable
at the actual 960×540 interactive window extent. Later user arguments override
this setting. The inventory starts with two beef and two coal, with a real empty
furnace ahead at `(12,8,12)` and player feet `(12.5,8,10.5)`, yaw 0°, pitch 30°.
Two normal 200-tick recipes take their real actor cadence; the test never
accelerates the cooking simulation.

The actual unmodified public shell ran in 56.763 seconds, returned two complete
960×540 P6 CPU images, chose free ports 54907/54908, and completed cooking-aware
close and durable save at highwater 42. A new actual actor cold-loaded that
save, returned the full player and 43-slot cooking authority, and saved at
highwater 44; its 44.346-second owner was reaped. Complete format-4 reconstruction
checks all 104 sections, Core clock, player metadata, status/WG, empty furnace
Details, effects, entity/RNG owner and publication state. Historical Actor012
and its conventional listeners remain alive. The initial default-world hashes
were not persisted; the actual save used only the separate unique demo path.

The public and cold host oracles wrongly expected `Core.max_peer=0`. The seed and
both actual saves preserved `None`; those host failures remain retained. Pure
verification finished their existing records without replaying either native
stage. The synthetic cooking run separately passed open, four input/fuel clicks,
partial/completed images, two output clicks, E close, native window close,
full durable save and actual cold reload. Its duplicate Relay cleanup receipt
failed afterward; a separate retained finalization verified all owned groups
and listeners absent without replay. These qualified results are in
`evidence/generic_resource_world_sample_cooking_runtime_002.json` and
`evidence/generic_resource_world_sample_cooking_launcher_runtime_001.json`.

The two ordinary 200-tick beef recipes took 67.009 seconds of wall time in the
synthetic workload. Tick catch-up after input completion also exhausted the
first fuel before final save. This does not establish 20 ticks per second or
vanilla responsiveness. The original renderer uses the admitted Appleclang
`-O3 -fno-stack-check` native command; the initial stack-check compiler crash
and the failed011 emission are retained separately. No original compiler was
changed.

Coal/beef/cooked-beef artwork is still explicitly marked missing in the current
item icon owner. The furnace panel, flame indicator and progress bar are drawn
procedurally with colored rectangles and font labels; they do not use loaded
GUI textures in the frozen Client012 screen.
Output transfer does not invoke furnace XP authority. Lighting, entity drawing,
full vanilla GPU appearance and whole-game completion are outside this slice.

For an actor-only follow-up, the existing public acceptance helper now takes an
explicit `--actor-generation` and validates its completed native-build receipt.
It accepts either a clean cooking runtime teardown or the historical explicit
cleanup finalization. The validated unpaused seed can be retained separately
with `--demo-seed-generation 11`. These helper changes leave the accepted public
Actor023/Client012 selection unchanged; a future actor requires its own actual
cooking flow and public-shell/save/reload acceptance.
