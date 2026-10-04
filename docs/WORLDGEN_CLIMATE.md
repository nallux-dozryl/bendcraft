# Pinned 26.3 climate parameter-list resolver

The production implementation in `src/worldgen_climate.bend` loads an actual
ordered `Climate.ParameterList`, constructs its search tree in Bend, and resolves
an already sampled climate target to the selected biome identifier. The decoded
parameter table and all search decisions remain in Bend. The full normal terrain
producer still refuses in the existing world-generation runtime.

`C.Loaded{identity,entries}` preserves the loaded registry key and original preset
JSON separately from the ordered seven-dimensional parameter points. Each
`C.Entry` has its original ordinal, biome identifier, and seven intervals: the
six actual climate axes followed by offset. `worldgen_climate_codec.bend` accepts
the decoded long-word table boundary, verifies consecutive ordinals, native
parameter/offset ranges, nonempty input and the explicit caller entry budget.
It is not a replacement for Minecraft's float JSON codec or for
`OverworldBiomeBuilder`'s source algorithm. The actual pinned generated table is
loaded for the independent production parity consumer; integrating this
boundary into the game's data-pack/preset resource loader remains required.

The consumer API is:

```text
C.prepare(plan:B.Plan, loaded:C.Loaded, build_budget:Nat)
  -> Result<&2,&1,String,C.Resolver>
C.resolve_target(resolver:C.Resolver, target:B.Target)
  -> C.Resolver & Result<&2,&2,String,C.Selection>
C.resolve_values(resolver:C.Resolver, values:B.Values)
  -> C.Resolver & Result<&2,&2,String,C.Selection>
```

`C.Selection` contains the selected biome, original entry ordinal and exact
Java-long fitness words. Fixed-biome plans need no climate search. Multi-noise
plans admit only matching registry keys and decoded preset identities. The
complete loaded definition, table, tree and original six `B.Inputs` expressions
stay with the affine resolver. Its previous selected leaf is deliberate mutable
search history. A resolver represents one Java R-tree thread-local history;
callers need separate histories when reproducing separate Java sampling threads.

## Actual 26.3 search semantics

The pinned classes use **19** children per tree node. They stably sort by the
sum of absolute interval centers in terminal groups. Larger groups try all seven
cyclic lexicographic axis orders, retain the first partition with strictly lower
sum of interval-span costs, stably sort the chosen buckets by absolute centers,
and recursively construct their children. The Bend builder uses a bounded
explicit work stack and stable bottom-up merge sort. Its bucket-size expression
is the largest power of 19 strictly below the admitted list size, corresponding
to the observed Java `pow/log/floor` expression for these sizes.

`Parameter.distance` computes both wrapping long subtractions before signed
comparison. Node fitness is the left-to-right wrapping sum of seven wrapping
squares. The target's seventh coordinate is zero, so a point's offset contributes
its square. Long comparison, subtraction, addition, multiplication, signed
center division and `Math.abs` behavior are implemented using exact word pairs.
There is no host fitness or search implementation.

Search traverses the actual ordered tree and prunes unless a node's signed
fitness is strictly lower than the current best. Equal fitness preserves the
previous cached leaf. Thus a flat scan's first-entry tie rule would be wrong.
The official observation contains 177 selected-entry differences between cold
and warm history among 2001 identical targets. The resolver's explicit DFS stack
preserves ordered traversal and the previous winner; the root singleton follows
Java's unconditional leaf return.

## Evidence and current scope

`reference/worldgen_climate.json` records the original Java-generated **7,594**
Overworld entries, **8,018** constructed tree nodes, and **2,001** cold plus
**2,001** warm queries. It includes targets obtained from the earlier actual
climate sampler observations, actual parameter endpoints and neighbours, a fixed
Java random stream, and extreme signed-long words. Five distinct-leaf tie queries
exercise changing cache history separately. The source/classpath process receipt
and loaded class-byte pins are in `evidence/worldgen-climate-reference.json`. A
separate actual Java primitive probe contributes 368 cold/warm queries over
nonzero offsets and singleton/19/20-entry construction boundaries, recorded in
`evidence/worldgen-climate-extra-reference.json`; the original large observation
was reused unchanged.
The reference is derived numeric/identifier expectation data, not copied class
files or installed assets.

The actual two-entry tie sequence passes the production Bend loader, builder,
prepared biome plan and resolver in the ordinary JS execution route. The ordinary content-checked native build passed in 12.228748s. Eleven native
fixture processes then passed in 3.379353s total, comparing **4,375** selected
ordinals/biome identifiers/exact fitness values and **16,135** serialized tree
nodes with complete bounds and order. Both full Overworld histories are compared
independently; the additional cases exercise nonzero offsets and singleton, 19
and 20 entries. All process groups were reaped and absent.
`evidence/worldgen-climate-native.json` records artifact/source identity, all
scenario counts and the exact raw receipt. No compiler/runtime retry or cached
native hit supplied this checkpoint.

`evidence/worldgen-climate-proof.json` records **12** independently admitted
laws, with exact original types, source bodies and checked proof terms retained,
zero export exclusions, stable source snapshots, and the independent BendTT
verdict. They cover complete immutable loaded-owner retention for arbitrary
lookups, precise construction/refusal diagnostics, fixed-biome lookup, complete
failed history retention, actual selected-leaf history, equal signed-fitness tie
preservation, actual `B.Values` quantizer composition and decoded-loader refusal
boundaries. They do not prove global nearest optimality, stable tree construction
ordering, machine arithmetic parity, output selection membership, or a compiled
climate graph. Independent Java/native evidence must establish its own stated
numerical cases. Prior noise/flat proof artifacts are unchanged and were not
rerun.

Reproduce the narrow checks with:

```sh
python3 tools/reference_worldgen_climate.py --observe
python3 tools/reference_worldgen_climate.py --observe-extra
python3 tools/test_worldgen_climate_proof.py --check
python3 tools/test_worldgen_climate.py --compare-cached
```

The native comparison requires the current content-checked build pointer in
`build/superflat-world/reference/worldgen-climate-native-current.json`; it uses
the ordinary `tools/build_native.py` route, verifies all actual Bend/Base build
inputs and artifact identity, then compares every serialized tree bound/order
and selected ordinal/biome/fitness against official Java results. Exact raw
supervised inputs, outputs and process cleanup receipts remain under `build`.

The parent density compiler must still evaluate the six actual router-bound
samplers and supply `B.Values`; this resolver does not invent that graph or choose
a fallback biome. Quart coordinates use the existing `B.to_block` Java int shift
boundary before density sampling. Complete normal population further requires
final density, aquifer/material/surface, carvers, structures, features, spawn and
region persistence integration. This checkpoint does not turn a loaded table or
selected biome into a complete normal world.
