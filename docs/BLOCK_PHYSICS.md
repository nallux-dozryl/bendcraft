# Pinned stored block factors

Confidence is **high for the pinned stored factors, exact widening and tested catalog admission/owner behavior**. Two native runs each matched all **74,866 independent expectations** using the same immutable executable. `src/block_physics.bend` and its standalone harness pass ordinary checking. The separate full production `--verdict` attempt failed with the compiler's TypeScript/BendTT kernel mismatch diagnostic; independent mathematical validation remains unresolved. These results implement a primitive catalog, not complete block physics or a broader movement/collision admission policy.

The only catalog values are the actual `Block.getFriction()`, `getSpeedFactor()` and `getJumpFactor()` results. Fresh pinned Java execution visits all **1,286 registered blocks and 35,723 state IDs twice**, producing byte-identical raw F32 and Java-widened F64 observations. Every registered receiver resolves all three getters to `net.minecraft.world.level.block.Block`. Fresh `javap` inspection confirms each complete method body is `aload_0`, one `getfield ...:F`, then `freturn`, with no call or world/entity/position input. Reflection independently identifies their fields in `BlockBehaviour` as `protected final`, and all 107,169 getter observations equal the corresponding stored field bits.

This complete body/receiver/field evidence supports treating these three getters as world independent for the pinned registered catalog. It does not infer independence from a few sampled worlds. The existing broader reference's collision, outline, shape, light and entity-dependent results are excluded entirely. Applying a speed/jump/friction factor to an entity, choosing a position, movement equations, block effects and contextual overrides remain separate responsibilities.

## Reference and representation

The fresh Java observations agree with every corresponding entry in the earlier independent `reference_block_physics.tsv`. State IDs and block protocol/range ownership are independently checked against the official generator metadata. Every F32-to-F64 pair is also checked with exact rational arithmetic. Actual named class bytes, method bodies, source, runtime, official classpath manifest and both raw output hashes are pinned in `reference/block_primitives.json` and `evidence/block-physics-reference.json`; complete observation files remain ignored under `build/block-physics/reference`.

The source values have **six distinct triples**. Compressing equal adjacent triples produces **15 exact, complete, contiguous state ranges**, serialized into an **815-byte** ignored `generated/reference_block_primitives.tsv`:

```text
BendBlockPrimitives<TAB>1<TAB>26.3<TAB>REGISTRY_IDENTITY<TAB>35723
first_state_id<TAB>state_count<TAB>friction_f32_bits<TAB>speed_factor_f32_bits<TAB>jump_factor_f32_bits
first<TAB>count<TAB>raw_u32<TAB>raw_u32<TAB>raw_u32
...
```

All numbers in the derived file are unsigned decimal integers, including the raw F32 bit words. Its exact canonical LF bytes are SHA256 `e4a4ad19274a04559ea8aa72a61db792744a54c84d50f0a4a5321aec75fc6e93`. The catalog binds to canonical Registry identity `4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc` and 35,723 states. This identity hashes parsed registry metadata, not the raw registry TSV layout.

Typical friction is F32 `3f19999a`, widened exactly to F64 `3fe3333340000000`; a double literal 0.6 is different. Ice/packed ice/frosted ice use F32 `3f7ae148`, blue ice `3f7d2f1b`, and slime `3f4ccccd`. Soul sand and honey have speed F32 `3ecccccd`; honey has jump F32 `3f000000`. The catalog retains source F32 values and computes exact widening on each query using the existing pure F64 substrate.

## API and ownership

```bend
Factors{friction:F32,speed_factor:F32,jump_factor:F32}
WideFactors{friction:F.F64,speed_factor:F.F64,jump_factor:F.F64}
Sample{factors:Factors,widened:WideFactors}
Catalog{ranges:Array<Range>,range_count:U32,state_count:U32,identity:String}

Catalog.parse(identity:String,count:U32,text:String)
  -> Result<&2,&1,Error,Catalog>
Catalog.decode(identity:String,count:U32,bytes:List<&2,U32>)
  -> Result<&2,&1,Error,Catalog>
Catalog.bind(registry:B.Registry,text:String)
  -> B.Registry & Result<&2,&1,Error,Catalog>
Catalog.load(registry:B.Registry,path:String)
  -> IO(B.Registry & Result<&2,&1,Error,Catalog>)
Catalog.query(catalog:Catalog,identity:String,state:U32)
  -> Catalog & Result<&2,&2,Error,Sample>
Catalog.replace(catalog:Catalog,text:String)
  -> Catalog & Result<&2,&2,Error,Unit>
```

`bind` and `load` compute the actual owned Registry's canonical identity; they return that owner on success and failure. The lower-level `parse`/`decode` identity argument is explicit context and does not compute a caller's registry. Loading the current official registry through its admitted parser and using `bind`/`load` is the integration boundary.

Each query retains the unique Catalog owner. Caller identity and state bounds are checked before any array read, then catalog identity/count/capacity checks prevent Array's wrapping index semantics. The owned array has sixteen Range slots, with fifteen admitted entries; query walks at most sixteen ranges without a state-sized allocation. Array contents are read only. The result preserves all three F32 payloads and their exact binary64 widening, with no decimal conversion or approximation.

`replace` admits a new fully pinned catalog before swapping the old owner. Failure returns the complete old catalog with no partial update. Successful replacement drops the old owned array and adopts the new one. Initial admission rejects wrong identity/count, corrupt canonical bytes, invalid UTF-8/raw byte values and byte ceilings. The pinned checksum binds the complete range map, so a valid finite value changed to another value still fails admission.

`parse` checks identity and state count before strict UTF-8 encoding, bounds encoded text to 8192 bytes, then verifies the pinned checksum before parsing the range schema. Consequently, malformed but decodable table layout normally reports `IntegrityMismatch`; semantic parser helpers do not grant integrity admission independently. `decode` checks the raw byte count and strict UTF-8 before the text path. `load` reads at most 8192 bytes, requires EOF with one additional byte, and closes every opened File on all declared result branches.

Raw public constructors/internal helpers remain outside this admission contract. Defensive query fixtures exercise malformed range counts, short arrays, wrong stored identity/count and empty/overflowing ranges. They do not establish that an arbitrarily hand-forged catalog containing plausible altered finite factors has the pinned integrity provenance.

Three ordinary-checked universal laws state that a public empty-identity query and maximum-U32 state query retain their complete Catalog owner, and that replacement admission failure retains the old owner. They do not prove Java behavioral parity, cryptographic security or complete block physics.

## Executed verification

The controlled native corpus reads dynamic TSV fixtures; expected Java data are not embedded as giant Bend checker constants. It queries every state ID in forward and reverse order, repeats 1,024 seeded IDs and targeted unusual blocks, and compares all nine raw output words. It interleaves invalid keys/IDs, corrupt parse/bind/load/replace inputs and raw decoder/Unicode failures with valid queries in the same process. It also performs 1,024 repeated failed actual file loads, successful replacement/rebinding, malformed-owner rejection/recovery, and a foreign Registry rejection followed by identity observation of the returned foreign owner and continued queries of the original catalog. The final Registry identity/name lookup checks the retained official registry owner.

Independent malformed reference tests reject altered state counts/IDs/owners, F32 values, widenings, a jointly resealed F32/F64 pair, release version, registered getter overrides, mutable fields and block protocol IDs. Ten receipt fault-injection cases reject altered source/C/native/compiler/dependency/cache metadata. They mutate deep copies only; shared source/reference/cache/artifact files are preserved. The two actual native runs cover 73,656 getter requests plus 116 corrupt catalog operations, 1,024 repeated failed actual loads and the remaining admission/context/ownership cases. Every rejected operation is followed by a successful query where the retained catalog is available.

`evidence/block-physics-preflight.json` records fixture preparation and ordinary checks. `evidence/block-physics-native.json` records the independent native PASS before the separately attempted kernel result. Both response files contain 74,866 lines and exactly match expected bytes SHA256 `63e38be74a9c26df17c9377ba66a2be7386e00e17dcd562b6ba3f36cc0e51ed5`; request bytes are pinned by SHA256 `252298c89e4b5c10a98ae866f22ccfac98dddac641566350c724f446343e67eb`. The reference validator also checks all 107,169 Java F32-to-F64 pairs independently with rational arithmetic.

The frozen seven-file Bend source closure includes module SHA256 `227f3764f1d420ab8b927df027b7a2efb72f77a4434157e5aec1bdfa611c0c2c` and harness SHA256 `6e7a30ad41718ba82a0ea4a65c187b8cb22dc092f463f3421ee30dbd812ce171`. Native executable SHA256 is `28fa4e3b5a392f97dd390e819220ce80a76a746758a27ebc7e47bd4eb26173e0` (1,757,800 bytes), emitted C SHA256 `3ae333761bdb7bcc07ae95ba82fb887fa61a6892e5837f5c718d52eba3f91d80`, cache key `179e0faf146e16a7f84f91e7456385d33f499b5207ed6289a78d3c795737c8f5`. The authoritative ignored receipt `build/block-physics/native-build.json` pins Apple clang 17.0.0, its driver/flags/SDK and 1,633 hashed native dependencies; their compact manifest SHA256 is `786158f9143e312e237c39ac776e8d0ad8edaf2dff62571d3105366beaad1b70`. No native artifact was rebuilt between runs.

The build's recorded total duration is 30.22 seconds. Native run `seconds` values of 129.21 and 128.33 measure execution **plus Python comparison**, not native execution alone: the frozen comparator eagerly rereads the request file when forming every assertion message. The native child itself had a separate 120-second timeout and completed in both runs. This inefficient reporting/comparison code was retained unchanged throughout the granted generation. No game lookup behavior runs in that comparator.

`evidence/block-physics-kernel.json` separately records one full production verdict attempt: exit 1 after 3.34 seconds, without timeout, with “a mismatch between the TypeScript implementation, and the formalized BendTT kernel.” No independent kernel pass, substitute projection proof, retry or additional build is claimed. Three universal source laws are ordinary-checked only.

Reproduce the actual Java measurement twice and verify the ignored derived asset:

```sh
python3 tools/reference_block_primitives_probe.py
python3 tools/reference_block_primitives_probe.py --verify-existing
python3 tools/test_block_physics.py --preflight
```

After a granted heavy slot, build once with a 600-second process-group bound, run two native comparisons against that immutable generation, then optionally attempt the production module's kernel verification with a separate 60-second bound:

```sh
python3 tools/test_block_physics.py --build-only
python3 tools/test_block_physics.py --skip-build --kernel
```

The native harness imports production modules only. It accepts `REGISTRY CATALOG REQUESTS` paths after runtime flags and `--`, outputs one bounded response line per dynamic request, and uses no native window. It adds no game lookup logic in Python and makes no changes to Registry, ClientWorld, Runtime or SupportWorld. Integration of this catalog with those owners remains unimplemented in this bounded task.
