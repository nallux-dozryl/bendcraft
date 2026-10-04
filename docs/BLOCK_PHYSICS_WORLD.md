# Core-backed stored block factors

Confidence is **high for the measured stored factors and tested owned Core lookup boundaries**. Two native runs each passed all **138,339 independent expected responses** on one retained executable. Production and the standalone harness pass ordinary checking. The separate full production verdict failed with the compiler's TypeScript/BendTT mismatch diagnostic; independent mathematical validation remains unresolved. This module composes the existing stored-factor catalog with an actual owned Core cell read; it does not implement collision shapes, entity travel, terrain admission or contextual block behavior.

## Boundary and API

```bend
Observation{state_id:U32,sample:BP.Sample}

query_cell(world:W.State,catalog:BP.Catalog,cell:C.Position)
  -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>

query_exact(world:W.State,catalog:BP.Catalog,dimension:String,position:M.Vec3)
  -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>

query_cells(world:W.State,catalog:BP.Catalog,cells:List<&2,C.Position>)
  -> W.State & BP.Catalog
     & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>
```

`C.Position` coordinates are exact two's-complement signed-I32 cell words stored in U32. Every word represents a finite integer in [-2147483648,2147483647], including both endpoints. This API adds no border, world-height, renderer-region or palette restriction. It accepts the Core foundation's three known dimension identifiers only. An absent section is an explicit error, including sections in known dimensions; it never becomes implicit air. A stored official air state remains an ordinary observed state 0 with its measured getters.

`query_exact` accepts raw binary64 coordinates, requires each to be finite and exactly integral in the signed-I32 range, and converts through the existing F64 substrate. It compares the input numerically with the reconstructed signed integer. Both zero signs designate cell 0. Fractional values, subnormals, NaN, infinities and out-of-range values fail explicitly, with the first failing axis index 0/1/2. There is no floor, rounding, clamping or entity-position policy.

Single-cell dimension checks happen before registry traversal. Exact-coordinate conversion precedes that dimension check. After these early checks, a call requires both Registry and Core state counts to equal 35,723 and computes the actual Registry's canonical identity. It must equal official identity `4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc`. Identity serialization errors and foreign identities retain both owners. A foreign registry cannot remap its state IDs into the official factor catalog merely by retaining the same number of entries.

Only after admission does the module call `Core.read_block` at the requested cell and `BP.Catalog.query` using that observed state ID. The result retains all three raw F32 getter words and exact widened F64 words. Invalid stored IDs and catalog metadata errors remain explicit. All 35,723 registered IDs are supported for these three getters; `W.Palette`, `W.material`, body position, snapshot cache and collision admission are never consulted.

Batch input is limited to 65,536 cells. An oversized batch fails before registry traversal or any cell read. A bounded batch validates actual Registry/Core identity/count context once for that call, then returns one result per cell in input order. Individual unknown-dimension, missing-section, invalid-state and catalog errors do not abort subsequent cells. This ordering makes a batch's global context error precede its per-cell errors. An empty batch validates Registry/Core context and returns an empty result list without reading catalog ranges. No copied admission token, persistent identity cache or stale registry inference is added.

The supplied catalog must come from BP's admitted parse/decode/bind/load boundary. BP's public raw constructors remain outside integrity admission, as documented in `BLOCK_PHYSICS.md`; this wrapper does not turn arbitrary manually constructed finite factors into verified reference data. Defensive fixtures deliberately forge metadata and test owner retention/recovery, without claiming cryptographic admission for raw constructors.

## Ownership and invariants

Every public result returns both affine owners. `W.take`/`W.attach` preserves the complete View: body position/box/velocity/pose/raw flags, current yaw/pitch, optional palette, region and optional snapshot-cache contents. Core clocks, state count, cells, pending mutation queue and event contents remain unchanged by lookup. Catalog query performs no array update.

Core reads internally pop and reinsert the owned section. This can reconstruct a collision bucket's entry order. The contract preserves complete canonical Core contents and the full View, rather than claiming the internal trie node layout is identical. Ordinary-checked universal laws state complete owner retention on the explicit unknown-dimension, exact-coordinate failure and batch-limit branches. They do not prove general read equivalence or Java behavior.

## Executed independent verification

The standalone harness imports production modules only and receives `REGISTRY CATALOG WORLD_NBT REQUESTS` paths after runtime flags and `--`. Fixture loading goes through the actual WorldCodec decoder. Python constructs independent NBT/coordinate/Java-getter expectations; runtime lookup executes in Bend.

The initial 296,710-byte fixture has 18 sections, with all 35,723 state IDs mapped across nine sections, signed section boundaries and both I32 extremes, nether/end cells, and two independently confirmed FNV-colliding section keys. It retains nontrivial clocks, four future pending mutations and two prior events. Its View includes signed zeros, all body fields, a deliberately stale nonempty cache and an explicit palette; another phase removes palette/cache and continues querying.

The frozen corpus contains **279 instrument operations and 138,339 expected response lines**, all matched twice. It includes complete forward/reverse state traversals, 1,024 seeded repeats, the exact 65,536-cell batch boundary and 65,537-cell refusal, mixed per-cell errors, 52 raw exact-coordinate cases, seven forged catalog owners, nine forged Registry/Core metadata settings and same-process recovery. Catalog observations include every owned array slot plus public metadata before/after rejected queries. Raw Core/Registry counts are observed before/after metadata rejection. A same-count registry with stone/dirt names exchanged has independently different canonical identity and was rejected. A populated unknown-dimension section and invalid stored cell IDs were also rejected without an air fallback.

Seven full canonical Core checkpoints matched independent bytes and decoded through the Python NBT/world schema in each run. They cover primary and defensive lookup phases, an explicit actual `Core.admit` plus one `Core.advance` edit, and repeated reads after that edit. The edit is a harness instrument; lookup itself performs no mutation. The cell initially containing state 0 was changed to honey state 25173, observed by subsequent lookup, and retained in the complete new Core contents. Before/after query checkpoints are byte-identical: initial-world SHA256 `6f3e045a29da0850b1cd191788a81eac4636a29c6da30e8069d468a050b16966`, edited-world SHA256 `5314c05a7691ef8097cb5ee2da748fa9783fc37e66acad8631c23281ba4bc8d4`.

Frozen module SHA256 is `6f1fee1aaacb41de852252f470d863ea791b9a101de5a136205fffeaaeaa4777`; harness SHA256 `835dea0d4c4abfbc27d18dbd608350c5c78c531b07285817bc2b964b040beebf`. The 24-file Bend closure, 15 loaded Python helper files, source reference hashes, actual ordinary results, and compact fixture manifests are recorded in `evidence/block-physics-world-preflight.json`. Request bytes SHA256 `693f220b638e036ffb224e0dea0224dfe4385aba04140c317ce54a13d452cce3`; both actual response files exactly match expected bytes SHA256 `3da8fe8c232eb16ae03a3e604f59162fbaca8c5af8c2bc09beb2fd94d111d2df`. Large fixture/response/native artifacts remain ignored under `build/block-physics-world`.

`evidence/block-physics-world-native.json` records native PASS before any kernel attempt. Native executable SHA256 is `5e8e39263c1feb33d14a614e43d431100ccdf8503c3f8db2b7ab4dc352b6cb45` (3,302,200 bytes); emitted C SHA256 `469808291397cfa48e363652e20add9b4fc33c29ee6f19cb3f72b447df16f8ad`; cache key `379064da91c3b33c816631f049a93ae13eaeee5b3eba4ad1b26a902db3afa98e`. The ignored authoritative receipt `build/block-physics-world/native-build.json` retains actual Apple clang 17.0.0 flags/driver/SDK and all 1,650 hashed native dependencies, with compact dependency manifest SHA256 `8846489a5549124ce11b5f89638479f7f8c7a7e5e4f3ca8d5166d93f81899843`. Build total was 38.93 seconds; native children completed in 4.64/4.14 seconds, with execution plus comparison/checkpoint validation 8.86/8.39 seconds. These are this bounded verification workload's timings, not a gameplay performance benchmark.

Ten deep-copy reference corruptions and ten native-receipt corruptions were rejected. Source, tool, reference, eleven prepared input/expectation files, emitted C, actual compiler/native dependencies and the immutable executable were sealed before/after the single build and audited again after both comparisons and the verdict. `evidence/block-physics-world-seal.json` and `evidence/block-physics-world-audit.json` confirm the frozen hashes stayed unchanged. No source/tool edit, retry, substitute artifact or extra build occurred in the granted sequence.

The separate `evidence/block-physics-world-kernel.json` records one full production `--verdict` attempt: exit 1 in 13.45 seconds, without timeout, reporting “a mismatch between the TypeScript implementation, and the formalized BendTT kernel.” No independent kernel pass or substitute projection proof is claimed. The three rejection/owner-retention laws are ordinary-checked only.

Reproduce preparation without emission or execution:

```sh
python3 tools/test_block_physics_world.py --preflight
```

After a lead-granted heavy slot, the prepared commands build once within a 600-second process-group bound, retain the immutable native receipt, compare two runs with separate 120-second native-child bounds, and optionally attempt one full production verdict within 60 seconds:

```sh
python3 tools/test_block_physics_world.py --build-only
python3 tools/test_block_physics_world.py --skip-build --kernel
```

Native status must be recorded separately before any kernel diagnostic. No source edits to BP, W, Core, Registry, SupportWorld or Runtime are part of this module. The existing player support/travel consumers do not yet use this catalog. Admission of contextual collision/shape/light data or application of stored getters to an entity remains unimplemented here.
