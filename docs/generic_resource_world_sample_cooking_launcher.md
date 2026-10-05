# Cooking client delivery

The public launcher now selects the verified Actor024/Generic012 pair. Run
`./tools/play_minecraft_cooking_demo.sh` for a fresh unpaused cooking world.
It creates a separate save and prints its exact resume command. Confidence is
high for the recorded limited cooking/save/reload slice. Coordinated foreground
OS input and presentation acceptance remains pending.

The launcher pins Actor024 SHA `c8dd57c0f5cd6d3607bc932bf6bb74ce27009f8b90efa7db4309beea5d1e2cc4`
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

The actual unmodified public shell ran in 53.357 seconds, returned two complete
960×540 P6 CPU images, chose free ports 58834/58835, and completed cooking-aware
close and durable save at highwater 42. A new actual actor cold-loaded that
save, returned the full player and 43-slot cooking authority, and saved at
highwater 44; its 43.582-second owner was reaped. Complete format-4 reconstruction
checks all 104 sections, Core clock, player metadata, status/WG, empty furnace
Details, effects, entity/RNG owner and publication state. Historical Actor012
and its conventional listeners remain alive. Both default-world paths were
recorded before launch and checked unchanged afterward; the actual save used
only the separate unique demo path. The public and cold stages passed without
a host failure or retry, and all owned groups and listeners were closed.

The Actor024 synthetic cooking run separately passed open, four input/fuel clicks,
partial/completed images, two output clicks, E close, native window close,
full durable save and actual cold reload. Its driver and cleanup passed directly.
The final paused Core tick was 858, with fuel remaining at 743/1600 and the
furnace still lit. The full cooking save retained RecipesUsed×2 and advanced
highwater 43 to 45 through the actual cold restore/save. These results are in
`evidence/generic_resource_world_sample_cooking_runtime_003.json` and
`evidence/generic_resource_world_sample_cooking_launcher_runtime_002.json`.

The two ordinary 200-tick beef recipes took 23.863 seconds in the Actor024
synthetic workload, compared with 67.009 seconds in the retained Actor023 run.
Both values use the same unpause-through-completed-image boundary and include
protocol and presentation work. Actor024 changes only cached-recipe selection
to check its ID before evaluating unrelated matches and plans. These observed
consumer intervals do not establish exact 20 ticks per second or vanilla
responsiveness. The original renderer uses the admitted Appleclang
`-O3 -fno-stack-check` native command; the initial stack-check compiler crash
and the failed011 emission are retained separately. No original compiler was
changed.

The earlier Actor023 public/cold host oracles wrongly expected
`Core.max_peer=0` instead of the seeded `None`, and its synthetic run had a
duplicate Relay cleanup receipt failure. Those qualified records and their
explicit finalization remain preserved in the preceding runtime002 and
launcher001 receipts; the current accepted pair has fresh clean results.

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
with `--demo-seed-generation 11`. Explicit generation selection does not change
the public launcher. A future actor requires its own actual cooking flow and
public-shell/save/reload acceptance.
