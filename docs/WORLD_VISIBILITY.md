# Measured full-cube face visibility

`src/world_visibility.bend` composes an owned `ClientWorld.State` with the frozen camera-relative snapshot and mesh producers. It implements the measured Minecraft Java **26.3** neighbor rule for exactly `minecraft:air`, `minecraft:stone`, `minecraft:dirt`, and `minecraft:oak_planks`. The live registry resolves these names and must give each block one state and no properties. Numeric state IDs are not hardcoded. Missing sections, unknown states, and unsupported palette domains return explicit errors.

The no-window Java probe executes unmodified `Block.shouldRenderFace(BlockState, BlockState, Direction)`, `BlockState.skipRendering`, face-shape accessors, and `BlockPos.relative`. For all four current states and all six directions, the adjacent-air result is true and each adjacent-solid result is false. Every measured solid face is the identical `Shapes.block()` object; every air face is `Shapes.empty()`. All measured `skipRendering` calls are false. `shouldRenderFace` checks the adjacent full-block identity before `skipRendering`, and its adjacent-empty shortcut returns true even for air against air, where a generic `ONLY_FIRST` shape difference would be empty. The production rule follows these measured shortcuts, rather than inferring visibility from model geometry.

`reference/world_visibility.json` records two fresh JVM reproductions, class/JAR and method-bytecode fingerprints, 1,632 state-pair/direction/position observations, 102 actual neighbor steps including 24 signed-int wraps, and 528 face observations across 11 finite scenes. Position repetitions do not add a position argument to this Java method: the method takes states and direction only. The raw `BlockPos.relative` observations separately establish exact coordinate stepping. Reproduce or verify the sealed input with:

```sh
python3 tools/reference_world_visibility_probe.py
python3 tools/reference_world_visibility_probe.py --verify-existing
```

## Typed composition

```text
Limits { mesh: WorldMesh.Limits, max_neighbor_reads: U32 }
Visibility { cell: ClientWorld.Cell, state: U32, visible: U32 }
Sample {
  snapshot: ClientRender.Snapshot,
  raw: List<ClientWorld.RawBlock>, visibility: List<Visibility>,
  origin: Movement.Vec3, palette: ClientWorld.Palette, neighbor_reads: U32
}

sample(state, limits) -> state & Result<Error, Sample>
produce(sample, bindings, texture_count, frame, mesh_limits) -> Result<Error, MeshRender.Scene>
snapshot_mesh(state, bindings, texture_count, frame, limits)
  -> state & Result<Error, MeshRender.Scene>
```

`sample` validates the owned registry palette and bounded region, calls `World.relative_snapshot`, and takes the exact raw cells from the matching returned cache. It then reads six neighbors of every nonair raw block from the same sole owned `Core.World`. No IO, simulation step, clock advance, or owner duplication occurs between snapshot and halo reads. It returns that owner on every failure. Neighbor reads deliberately include duplicate halo cells; successful `neighbor_reads` is exactly six times the nonair block count. Air-only snapshots need no halo reads.

Cell identity is the original raw signed Java-int XYZ bit pattern in `World.RawBlock.cell`. `Cell.boundary` is region metadata and is not a coordinate key. Neighbor stepping uses U32 increment/subtraction, matching Java signed-int overflow wraparound, including across `2147483647`/`-2147483648`. Neither relative F32 origins nor baked vertex positions select neighbor cells. Missing halo sections are errors and are never filled with implicit air.

Masks use bits Down=1, Up=2, North=4, South=8, West=16, East=32. `produce` checks palette IDs are distinct, list counts/order align, raw XYZ cells are unique, states/materials match the palette, masks identify the same raw cells/states and use only six bits, read counts are consistent, the F64 eye origin is supported, and every snapshot F32 XYZ value exactly equals the existing raw-to-relative conversion. The owner-taking facade establishes the palette's registry meaning. An independently constructed public `Sample` cannot establish actual world observations by itself; its metadata must come from a validated sampler or an equally checked caller.

The original `World` cache contract remains in force. Scheduled edits advance revision; low-level raw writes affecting the sampled region must call `World.invalidate_cache`. The facade validates cache structure, but it does not rescan a cache hit's entire region to detect a caller's unannounced raw write. Halo cells are reread each time: an outside-region raw halo edit can change visibility without invalidating the unchanged inside snapshot or advancing tick/revision. The native harness checks that case explicitly.

## Quad preservation and limits

`produce` first invokes the exact frozen `WorldMesh.produce` on the entire unculled snapshot. Only after it succeeds does this facade remove quads according to each corresponding `BlockBake.Baked.cullface` group. `None` is always retained. The actual baked face normal (`Baked.direction`) does not replace the declared cull group, and `MeshRender.Cull` remains the independent triangle backface setting.

Filtering returns the original retained `MeshRender.Quad` values. Local F32 translation, UVs, sprite/material slot, tint/light/shade, address mode, triangle cull, and original order are preserved. Removed quads leave gaps in `Quad.order`; this is the existing snapshot/baked-list order, not a claim about every vanilla dispatch or transparency tie.

The defaults use `WorldMesh.defaults()` and 24,576 neighbor reads for at most 4,096 nonair blocks. Smaller budgets are explicit configuration. Larger unsupported budgets reject. Region dimensions remain the existing 1..16-per-axis bound. There is no truncation or implicit partial frame. **WorldMesh's pre-filter budgets still apply:** a 234-quad unculled input that would retain 108 faces fails a configured 108-quad budget. Full source-binding and translucent budgets are checked before neighbor filtering too.

## Verification boundary

Source and harness ordinary checks pass. `evidence/world-visibility-kernel.json` records ordinary checking, `--verdict`, emitted BendTT, and the independent cached kernel for an exact 227-line pure production projection. It includes raw neighbor stepping, the measured class rule, cull-group mask folds, retained-quad filtering, exact selected Data types, and the actual lookup dependency. Three generic laws establish that a classified full-cube neighbor hides the face, ungrouped faces are retained, and retaining a quad returns that exact value. This isolated check does not cover the affine world facade, F64 snapshot alignment, effects, or aggregate imports. The separately recorded imported JSON checker/kernel boundary remains.

The native runner is `python3 tools/test_world_visibility.py`. The original combined build reached its enforced 600-second process-group limit before producing a binary. `evidence/world-visibility-combined-build.json` preserves that receipt and its exact checked harness source: zero runtime invocations, zero native comparisons, no frames, and complete owned-process cleanup. All 37 transitive source/helper fingerprints and pinned inputs remained unchanged. This establishes no native pass or semantic failure.

A narrower harness separates the owned sampler from geometry/rendering and retains the same independent expectations. Generated entries copy checked test-helper source and select a main; they do not import another test module. Both separated entries pass ordinary checking. The sampler emitted complete C, then its installed `-O3` C compilation also reached the 600-second limit without a binary or runtime results. `evidence/world-visibility-sampler-o3-build.json` records the exact driver and compiler flags, stage samples, cleanup and source/input fingerprints. Its 48,489,853-byte emitted C is retained byte-for-byte at `build/world-visibility-oracle/sampler-emitted-after-time-limit.c`, with SHA-256 `ca28c3d401f8f634d3a5cf2d799dc08d56f951988ba8e410cd3029e0900eb51c`.

The separately authorized `-O0` compile of those exact C bytes passed in 200.37 seconds through the original `/usr/bin/clang` launcher. `evidence/world-visibility-sampler-o0-build.json` records the original flags with only optimization/output changed, the launcher and actual driver, target/SDK15.5, direct header/runtime pins, and before/after fingerprints. The retained CPU binary `build/world-visibility-sampler-O0` has SHA-256 `5ab7ea1d2b6db7ac95a19ff3013ecce3a68e69a8a02d393e51023d08f0164dab`. This is explicit CPU behavioral evidence; it does not establish an optimized release build or performance. Failed launcher/runtime-selection and diagnostic-comparator attempts are preserved in separate receipts and supplied no substituted results.

All 42 unchanged sampler groups then passed in 99.64 seconds against that binary. `evidence/world-visibility-sampler.json` records 46 actual snapshots, 353 sampled blocks, 2,118 neighbor reads, 96 face-pair results, 102 signed neighbor steps, and 11 rejected configurations/halo cases with 11 world-owner recovery checks. It verifies source/reference/input/output/generated-entry/binary/build-receipt/handoff fingerprints before and after. Actual native `Sample` data is retained losslessly, including raw XYZ/boundary/state/material, visibility XYZ/boundary/state/mask, F64 origin, relative F32 snapshot and registry palette. Python implements only the test DTO codec. The installed `-O3` sampler build remains unverified; the completed sampler results belong to the explicit retained `-O0` artifact.

`evidence/world-visibility-bake-preparation.json` verifies the existing compiled Bend baker and all twelve recorded dependency hashes. That existing native binary consumed the three original model JSON chains with explicit normalized sprite slots and emitted eighteen actual `K.Baked` quads in the recorded native invocation. Every emitted field was compared with actual Java before preparing geometry inputs. Python's subsequent conversion is a lossless test DTO codec; it computes no gameplay visibility or geometry. The sampler emitted its actual snapshot, raw cells, masks, F64 origin, and palette into the geometry entry, which called the production `Visibility.produce` and `MeshRender.render_flat`. Expected Java masks/quads/pixels remain comparison-only. The sampler stage is verified against its explicit `-O0` artifact, and geometry is verified by the separate installed `-O3` build.

The geometry build passed in 215.05 seconds. `evidence/world-visibility-geometry-emission.json` preserves its complete 6,515,428-byte C source captured during clang, exact launcher/compiler flags and provenance; its C SHA-256 is `18acc5cf60a4f89a48b8299600c45e7a0aec268a59d7d644d2f8e5dd1b1269e9`. The retained `build/world-visibility-geometry` binary has SHA-256 `3812a14ce457d7d08116d1c7964feefb257319c0d0b38df54e25f947e20ad11b`. `evidence/world-visibility-geometry-build.json` records that successful installed `-O3` compilation and the later test-runner framing failure. Its overall failure status refers to an extra blank line joining two actual stdout streams, not a failed compile or a geometry mismatch. The runner correction changes only the join boundary and artifact/generation admission; all comparison, parser, validation and expectation helpers remain source-identical. The failed inputs/stdouts and the original actual sampler handoff remain byte-identical and separately archived.

`evidence/world-visibility-geometry.json` records the retained-binary geometry run, which passed all 47 calls in 1.89 seconds, checking 993 world quads and two standalone retained quads word-for-word, 22 frames and all 16,896 RGB pixels against the independent oracle. It rechecked all 46 saved native snapshots, 353 blocks and 2,118 neighbor reads. Fourteen public-sample outcomes include 13 explicit rejections and one success; three cull-group fixtures distinguish an ungrouped face, a declared East group with a Down normal, and that same group hidden. The in-region raw edit changes 39 to 40 blocks, 108 to 112 retained quads, and 42 pixels while tick/revision remain 1/47. The outside-region halo edit changes mask 22 to 23 and three to four quads while retaining the inside snapshot/cache and tick/revision 1/7. Registry-remapped frames match exactly. Every source/input/output/generated-entry/binary/C/build-receipt/handoff/generation integrity check passed. The reserved slot was released after all owned compiler, native and observer processes exited.

The sampler run covers the actual 39-block fixture and 40-block raw edit, remapped registry IDs, signed far cells, sparse halo worlds, cache-preserving halo edits, malformed cache/limit/region/palette errors, unknown/missing halo errors, and owner recovery. The geometry run additionally covers malformed public samples, declared-cull-group cases, pre-filter mesh budget rejection and retained-frame comparisons using the independent existing mesh pixel oracle. `evidence/world-visibility-native.json` links the separate sampler and geometry receipts and preserves their different optimization scopes: 89 native sampler/geometry calls, 25 validation outcomes (24 rejections and one success), 11 owner recoveries, and 32 far-cell cases. The unique snapshot/block/read counters count the same actual sampler data once; geometry revalidates it without another world sampling call. The original combined receipt still records zero runtime invocations.

With the retained binaries, sealed actual sampler output and original compilation receipts, replay the geometry comparisons without emission:

```sh
python3 tools/test_world_visibility.py --geometry-only --skip-build \
  --sampler-binary build/world-visibility-sampler-O0 \
  --sampler-build-receipt evidence/world-visibility-sampler-o0-build.json \
  --geometry-build-receipt evidence/world-visibility-geometry-build.json
```

This module establishes this four-state cached full-cube rule only. Contextual voxel shapes, arbitrary block `skipRendering` overrides, leaves/glass/fluid behavior, neighbor lighting, ambient occlusion, biome tint, entities, transparency selection, production chunk meshing, and visible client acceptance remain separate work.
