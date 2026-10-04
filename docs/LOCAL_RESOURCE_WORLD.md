# LocalPlayer resource-world adapter

`src/local_resource_world.bend` exports two pure, owner-retaining operations for the saved LocalPlayer Session:

```bend
snapshot(state: S.State, width: U32, height: U32)
  -> S.State & Result<&2, &2, String, V.Sample>
palette(state: S.State)
  -> S.State & Result<&2, &2, String, RF.Palette>
```

The backend invokes the complete `snapshot` operation once inside one actor `local_call`. Its single Session query captures the current Registry palette, the exact cached Pose eye position, the resource snapshot, the raw cached cells and their visibility masks. The query preserves the Session shell, leased save owner, runtime tails, tables and sole world owner. It advances no clock and samples no input.

The origin comes from `local_player_runtime.eye`; `local_player_runtime.snapshot` subtracts that exact F64 eye from exact signed cell coordinates before narrowing each relative block to F32. Camera XYZ remains zero. The adapter passes this same origin to frozen `world_visibility.raw_alignment`, then calls frozen `world_visibility.collect_blocks`. It bypasses only the fixed-eye `V.sample` and `V.collected` wrappers. Crouching uses the cached crouching eye, with no ratio or post-F32 correction. Face directions, neighbor reads, occlusion and downstream resource/model/mesh algorithms are unchanged.

The current Registry resolves air, stone, dirt and oak planks by identifier. Their distinct IDs must match the View palette before region sampling or neighbor reads. Frame dimensions are each 4..1024. The adapter uses `V.defaults`: at most 4096 raw blocks and 24576 checked neighbor reads; the downstream mesh budget remains 4096 blocks, 1024 bindings, 4096 quads, 64 translucent quads and 256 tint entries. These are finite admission limits, not full-world coverage. Every scanned missing section or unsupported state remains an error; an omitted neighbor is never inferred to be air.

Palette/frame/region refusal preserves the prior View and cache. A failed raw snapshot preserves its prior cache. Once the raw snapshot succeeds, its success-only cache is retained even if alignment, a count limit or a later neighbor read rejects the resource sample. Neighbor reads preserve the returned Core and complete post-snapshot View. Errors use the existing resource visibility formatting; an invalid frame returns `ResourceScene:Frame`. The separate `palette` operation reads only Registry/View binding and returns the same owner; a successful `V.Sample` also carries its bound palette, so the renderer need not obtain palette and frame from different actor calls.

Trusted direct `Core.write_block`, `Core.apply` or Registry mutations can bypass revision-based cache observation. Such callers must invalidate the View cache explicitly with `W.invalidate_cache`; this adapter does not broaden that existing contract. Query polling, look changes and pose changes recalculate camera-relative positions from exact cached raw cells.

The ordinary source check has no adapter declaration errors. Its full Session import reports 56 inherited unsafe/foreign durability, lock and save declarations, so it is not a kernel verdict. No new native, Java, proof, pixel or UI acceptance was run for this adapter. Consumer verification belongs to the shared split-client artifact; previous plain-player pixel oracles remain unchanged.
