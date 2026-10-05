# Retained scene lighting producer

`entity_scene_lighting_model`, `entity_scene_lighting` and
`entity_scene_lighting_sample` compose the actual block and sky engines. The
only Core owner is `State.block.world`. The sky owner contains its physical
descriptors, retained levels, column sources, revision and resumable work.
`attach` initializes only the missing sky owner from an existing `BW.State`;
it does not restart the existing block engine or replace its loading cursor.
An invalid catalog/count, generation settings or empty epoch returns the
original block owner in `Attachment.Retained`.

The existing [flat authority](../src/sky_light_flat_authority.bend) supplies
registry descriptors, exact face occlusion, saved generation bounds and the
missing-section policy. A missing section becomes KnownEmpty only under its
explicit valid, feature-free flat-layer rule. Core residency, renderer bounds,
an allocated light cell and an unspecified generator are insufficient.

## Actual owner interface

The stored Session carrier must keep `Detached{sky,authority,epoch}`, not a
second World. During one existing engine continuation, assemble `BW.State`
from the transferred actual Core and existing block light/loading, then call
`rejoin(block,detached)`. After the operation, `split(state)` returns that same
block owner and the detached sky owner. Move `BW.world` back to the Engine;
retain only the block light/loading and `Detached` in the appropriate sidecar.

`load(block_budget,sky_budget,state)` resumes both real acquisition cursors.
`advance` runs their actual pending propagation; neither operation steps the
simulation clock. `sky_enabled` and `sky_sources` call the retained Java-backed
sky lifecycle operations. They do not implement block-light enable callbacks.

`apply` is the low-level seam for an already-authorized Core continuation.
`apply_finished` also consumes the real schedule stamp through `C.finish`.
Descriptor refusal or actual block/Core refusal publishes no sky notification.
After an accepted mutation, only that actual result enters `SW.accept_result`.
A post-commit sky failure returns **Done(RepairRequired)**, retains the changed
Core and block field, and invalidates the sky revision. It is never reported as
an atomic mutation refusal. `reacquire_sky` is an explicit full acquisition
operation for this condition. The existing sky implementation also explicitly
reacquires after section creation or an edit during a non-ready sky phase;
this checkpoint does not claim retained Java history across those rebuilds.

`admit` uses the actual Core permission/future-tick/queue validation through
`BW.admit`; it queues without changing either field. A combined scheduled
due-batch step and external residency/unload callback are not implemented here.
Calling `BW.step` independently and then declaring sky current would be an
invalid join. The real actor edit/tick/residency paths must feed accepted
changes through the retained producer before this provider becomes live.

## Stamped stencil publication

`sample(capture,request,state)` returns the same actual owners and either a
complete `Publication` or an explicit error. `Capture{epoch,Wire.Stamp,
Maybe<vanilla_lightmap_model.Inputs>}` must be projected from the actual atomic
frame continuation. No realtime step or edit may occur between its Core,
camera, entity, environment and light queries. The request supplies expected
epoch/stamp and ordered `Site` rows; it cannot choose the producer's camera or
environment. The producer checks epoch, catalog identity, full raw stamp
equality, finite partial tick, matching environment partial tick, current Core
tick/revision, stencil dimensions, and the two engines' settled/revision gates.

Each Site labels a caller-supplied face/vertex point or entity-stencil point and
an exact Core position. Samples retain that order and duplicates. Both engine
observations must agree on resident block ID and contain levels in 0..15.
Missing residency refuses the complete publication, including when sky storage
could otherwise provide a public fallback level. No unknown cell becomes dark,
white or fullbright. Both actual clocks must also agree after the read sequence.
The 4096-site admission limit bounds one publication without changing its order.

This output contains raw block/sky levels, actual IDs, the complete capture and
Core clock. It has no RGB, packed vanilla brightness, directional shade or AO
claim. The parent `vanilla_block_lighting` stencil/resolve consumer must supply
the real per-face/per-vertex geometry and state/occlusion attributes; the parent
`vanilla_lightmap` owner evaluates actual environment/player/options/flicker
authority separately. Environment `None` remains `None`. This module allocates
no renderer RNG and derives no day/weather/camera defaults.

## Verification and live status

The focused runner is `python3 tools/test_entity_scene_lighting.py`. Its default
checks the actual production lifecycle/sampler, seven complete-owner law/proof
definitions and eleven prepared guard cases. `--native` is an opt-in narrow
guard build using the existing bounded native builder; it does not establish
Java-level parity or the live consumer join.

The final [source receipt](../evidence/entity-scene-lighting-003.json) records
exit 0, ALL PROOFS CHECK, empty stderr and unchanged loaded source pins in
6.8693 seconds. Failed binder/affinity/proof-reduction attempts remain in the
two earlier guard receipts and the separate source-failures receipt. All owned
check process groups are reaped. No independent kernel or native guard was run.

The seven laws cover complete detach/rejoin, rejected attachment authority,
zero acquisition budgets, failed sky preflight, failed actual Core result,
failed capture preflight and stale Core-stamp refusal. Independent kernel work
and native guard execution are held for the runnable cooking-client priority.
This source checkpoint does not attest a live Session/Frame light carrier,
wire lighting publication, enabled block lifecycle, lightmap/AO integration,
retained light recovery, visible native appearance, or GPU behavior. Existing
pinned block/sky reference evidence belongs to those engine implementations,
not to an unexecuted new combined receiver.
