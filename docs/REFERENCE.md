# Pinned 26.3 release reference

The release inventory is extracted and reproducible. It establishes which official inputs and identifiers this project must cover. It establishes **no Bend gameplay implementation or parity**. Confidence in the recorded artifact identities, counts, state mappings and extraction comparisons is high; complete executable behavior remains unspecified.

The installed client and version metadata are the designated reference inputs. The matching server bundle is downloaded only from the artifact URL in that metadata. The extractor never opens account files, launcher profiles, credentials or worlds. Original jars, libraries, generator output, Java probes and logs remain in ignored `reference/cache`, `reference/reports` and `reference/extracted` directories. Tracked files contain code and reference metadata, not extracted game assets.

## Release identity

[reference/release.json](../reference/release.json) records the complete fingerprints and the generator report digests.

| Field | Observed value |
| --- | --- |
| Release ID | 26.3 |
| Release timestamp in installed version metadata | 2026-09-15T11:23:02+00:00 |
| Internal build timestamp | 2026-09-15T11:20:48+00:00 |
| World data version | 5023 |
| Network protocol version | 777 |
| Resource pack version | 97.1 |
| Data pack version | 121.0 |
| Required Java major version | 25 |
| Used runtime | Microsoft OpenJDK 25.0.1+8-LTS, launcher `java-runtime-epsilon` |
| Official asset index | 34 |

The pack versions above come from the client jar's internal `version.json`, rather than assumptions about older pack-format conventions. All three built-in experimental data packs declare `min_format` and `max_format` 121 in their own `pack.mcmeta`.

| Artifact | Bytes | SHA-1 |
| --- | ---: | --- |
| Installed `26.3.json` | 44,992 | `4fe1aa1ef8da1cb95c5bad1fb98890ca56dd8ca3` |
| Installed client jar | 41,483,720 | `e877b6a07acd633fb3bb475002175cec036e7b87` |
| Official server bundle | 62,294,556 | `33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c` |
| Asset index 34 | 597,035 | `abfaa525f923f807df8b4e4d29c1b5e3a104adbe` |

SHA-256 fingerprints:

```text
version metadata  9a7b39dae3b9c8d30006b650e357aae220629b7852fa0fc7221db7a8646bd5e4
client jar        4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d
server bundle     d052f14d7a173734fba553711e5b570162e2f2a313267ee31a21b975a679be64
asset index       0f026e5396e2d709b3e6d8c7b2cc2fba9e6a7f02b53b632ba051edb1cd362377
```

The installed metadata names the [official client artifact](https://piston-data.mojang.com/v1/objects/e877b6a07acd633fb3bb475002175cec036e7b87/client.jar), [official server artifact](https://piston-data.mojang.com/v1/objects/33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c/server.jar), and [official asset index](https://piston-meta.mojang.com/v1/packages/abfaa525f923f807df8b4e4d29c1b5e3a104adbe/34.json). The client, server and index sizes and SHA-1 values are verified before extraction. The inner server jar's SHA-256 is independently checked against the bundle manifest. The tick probe additionally verifies the unpacked server and every listed library.

## Reproduction

Run from the `minecraft` project directory:

```sh
python3 tools/reference_inventory.py
python3 tools/reference_verify.py
python3 tools/reference_tick_probe.py
python3 tools/reference_structures.py
python3 tools/reference_coverage.py
python3 tools/reference_selftest.py
```

The first command obtains the pinned server if it is absent, reuses the installed asset index when its hash matches, invokes the official data generator, compares its data with the client, and emits the release inventory and eight TSV tables. `--version-dir` and `--java` allow explicit installation/runtime paths. `--skip-generator` reuses existing reports and records that the generator was not rerun; it still verifies artifact identities and table extraction.

The exact generator argument vector is recorded in [evidence/reference_inventory.json](../evidence/reference_inventory.json). Its shape is:

```sh
"/Users/chuah/Library/Application Support/minecraft/runtime/java-runtime-epsilon/mac-os-arm64/java-runtime-epsilon/jre.bundle/Contents/Home/bin/java" \
  -DbundlerMainClass=net.minecraft.data.Main \
  -jar "/Users/chuah/Documents/ChatGPT/bendex/minecraft/reference/cache/26.3-server.jar" \
  --server --reports \
  --output "/Users/chuah/Documents/ChatGPT/bendex/minecraft/reference/reports"
```

Its working directory is `reference/cache`. The bundle unpacks its own pinned server and libraries there. The log is `reference/cache/report-run.log`. This invokes the headless data generator, with no game window or account login.

`reference_verify.py` separately reads the emitted TSVs and official reports. It verifies table hashes and row counts, reconstructs every block state, and compares registry IDs, packet IDs and command nodes with their report counterparts. `reference_selftest.py` reruns the pipeline and compares every reference JSON and generated TSV byte. It also corrupts the air state ID in a temporary copy, verifies the checksum rejection, reseals that checksum, and verifies that the independent state comparison still rejects the wrong mapping. [The resulting evidence](../evidence/reference_selftest.json) records 14 reproduced reference outputs and two rejected corruption cases.

## Inventory counts

[reference/inventory.json](../reference/inventory.json) contains all 95 static registry counts, all data/resource categories, observed JSON shapes and report summaries. Selected counts are:

| Reference group | Count |
| --- | ---: |
| Static registries | 95 |
| Static registry entries, summed across registries | 7,053 |
| Blocks | 1,286 |
| Block states | 35,723 |
| Items / item default-component reports | 1,658 |
| Entity types | 161 |
| Block-entity types | 49 |
| Registered data-component types | 122 |
| Registered game rules | 59 |
| Registered effects | 40 |
| Registered sound events | 1,991 |
| Registered particle types | 128 |
| Menu types | 25 |
| Recipe types / serializers | 8 / 22 |
| Command roots, including aliases | 94 |
| Command-tree nodes | 2,475 |
| Command executable nodes / redirects | 1,424 / 114 |
| Distinct command parser identifiers | 59 |
| Packet IDs, across states and directions | 260 |
| Server JSON-RPC methods / named schema definitions | 89 / 14 |
| Bundled data files, including pack metadata and marker | 9,884 |
| Bundled data elements and tags, across pack scopes | 9,880 |
| Client-jar resource files, including marker | 11,604 |
| Asset-index names / unique object hashes | 5,147 / 5,147 |

Registry counts describe declared types. For example, 128 particle types and 115 particle resource definitions are different inventories; neither number establishes particle behavior. Likewise, the 1,288 blockstate resource definitions include the `item_frame` and `glow_item_frame` presentation definitions in addition to all 1,286 block registry names. They must not be mistaken for additional block types.

Principal vanilla data categories:

| Category | Files |
| --- | ---: |
| Recipes | 2,042 |
| Advancements | 1,866 |
| Loot tables | 1,447 |
| Structure NBT templates | 1,511 |
| Tags, across registries | 883 |
| Villager trades / trade sets | 391 / 68 |
| Enchantments / enchantment providers | 43 / 7 |
| Damage types | 51 |
| Dimension types | 4 |
| World presets / noise settings | 7 / 7 |
| Biomes | 67 |
| Configured features / placed features | 240 / 273 |
| Structure definitions / structure sets | 52 / 21 |
| Template pools / processor lists | 245 / 40 |
| Density functions / noise parameter definitions | 55 / 64 |

All seven built-in world presets declare the three dimension identifiers `minecraft:overworld`, `minecraft:the_nether` and `minecraft:the_end`. The fourth dimension **type** is `minecraft:overworld_caves`; a dimension type is not an additional built-in playable dimension. Exact generator declarations are recorded per preset in the inventory. A directory count alone would miss these dimensions because this release places those declarations in `worldgen/world_preset` data.

The optional packs are `minecart_improvements`, `redstone_experiments` and `trade_rebalance`. The first two carry feature-flag metadata only. `trade_rebalance` has 103 content/tag records besides `pack.mcmeta`: 81 villager trades, five loot tables, seven enchantment tags and ten villager-trade tags. The tables preserve each pack's scope, rather than silently folding optional replacements into the vanilla counts.

The official server generator emits 8,372 data files. **Every file is byte-for-byte equal to the matching installed-client entry.** There are no extra generated paths or mismatches. The client-only remainder is exactly the 1,511 structure NBT templates and `data/.mcassetsroot`. This comparison establishes reference extraction consistency, not execution of recipes, loot, world generation or other game behavior.

## Compact tables and Bend consumption

| Table | Contents |
| --- | --- |
| [reference_registries.tsv](../generated/reference_registries.tsv) | Registry, official numeric protocol ID, identifier; 7,053 rows |
| [reference_blocks.tsv](../generated/reference_blocks.tsv) | Block protocol ID, identifier, first/count/default state IDs, ordered property domains; 1,286 rows |
| [reference_data.tsv](../generated/reference_data.tsv) | Pack scope, category, identifier, format, jar path and SHA-256; 9,880 rows |
| [reference_resources.tsv](../generated/reference_resources.tsv) | Source, category, logical path, format, size and hash; 16,751 rows |
| [reference_commands.tsv](../generated/reference_commands.tsv) | Lossless path segments, node type, executable marker, parser/properties and redirects; 2,475 rows |
| [reference_packets.tsv](../generated/reference_packets.tsv) | Connection state, direction, identifier and protocol ID; 260 rows |
| [reference_item_components.tsv](../generated/reference_item_components.tsv) | Item name, default component identifiers and canonical default-value hash; 1,658 rows |
| [reference_rpc_methods.tsv](../generated/reference_rpc_methods.tsv) | Method names and declared parameter/result schemas; 89 rows |

The resource table's `content_hash` is SHA-256 for a client-jar entry and SHA-1 for an asset-index object address; the `source` column distinguishes them. The extractor inventories all external names and hashes but downloads none of those media objects. Decoded audio, language, font and external texture correctness remains separate work. The index names include 4,961 sound files and 142 language files; these are files, rather than registered sound-event or supported-locale counts.

The block table is 182,136 bytes rather than a generated Bend function with 35,723 cases. Its property domains are ordered from slowest to fastest changing state ordinal. For a complete property assignment, fold the value indexes through their domain lengths:

```text
ordinal = 0
for property in ordered_properties:
    ordinal = ordinal * len(property.values) + index_of(assigned_value)
state_id = first_state_id + ordinal
```

The inverse uses quotient/remainder from the last property to the first. The default state ID is explicit. This mapping is validated against every official state. Java's property-map iteration order is insufficient: chest variants and piston-related states require a different significance order. The extractor infers strides from the explicit official state sequence and rejects any noncartesian or noncontiguous case rather than inventing a rule.

Bend can load these ordinary data tables through its pack/registry initialization, or generate compact immutable arrays. Do not compile the entire resource/data manifest into a massive checker expression. Static numeric registry IDs describe the pinned vanilla base; modded registry composition needs its own rules. Data-path identifiers have **no runtime numeric registry IDs assigned by this extractor**. Stable block IDs and schemas do not implement placement, collision, random ticks, rendering or drops.

## Schemas, structures and non-data coverage

[reference/datapack_structure.json](../reference/datapack_structure.json) preserves the official data generator's 155 registry locations: 60 support element files, and all 155 support tags. It also records function and structure content formats. Each category's observed JSON root types, top-level field frequencies and `type` discriminators are in the main inventory. These describe bundled examples and format locations; they are **not complete codec schemas**, allowed-value constraints, defaults, error behavior or merge/reload semantics.

[reference/structures.json](../reference/structures.json) fully parses the 1,511 gzip-compressed NBT templates, all with data version 5023 and empty compound root names. There are 1,491 single-palette templates and 20 multi-palette templates, totaling 1,651 palette sets, 24,242 palette entries, 1,170,664 stored block records and 288 stored entity records. The 475 distinct palette block identifiers all exist in the pinned block registry. Observed root tag types, structure sizes and field frequencies are retained without retaining the decoded assets.

In this exact release, all 24,242 palette entries use lowercase **`id`**, and 17,770 include lowercase **`properties`**. Historical `Name`/`Properties` assumptions would misread these official templates. Block records use `pos`, `state` and optional `nbt`; entity records use `blockPos`, `pos` and `nbt`. Decoding those records does not establish placement, jigsaw, processor, block-entity migration or generation behavior.

[reference/behavior_inventory.json](../reference/behavior_inventory.json) maps 39 non-data obligation groups to 92 actual named classes and selected verified method declarations. Classes are shipped with readable names; no downloaded mapping set is needed. The installed launcher JDK includes `javap`, `javac` and `java`. `javap -p` and `javap -c -p` work against the pinned jar. No separate decompiler was downloaded for this inventory. Raw declaration output stays ignored in `reference/cache/behavior-signatures.txt`.

The direct Java [tick probe](../evidence/reference_tick_probe.json) observes default 20 TPS / 50,000,000 ns / 50 ms, `setTickRate(7)` producing 142,857,142 ns by integer truncation, the tested 0.25 TPS request clamping to 1 TPS, and the exact two-step frozen countdown. It does not cover player/passenger freeze exceptions, server scheduling, pause, sprint or Bend comparison.

[docs/COVERAGE.md](COVERAGE.md) describes the ledger and outstanding work. The extraction cannot specify packet field codecs, every block/entity transition, numerical movement/collision behavior, random-stream consumption, renderer/audio/UI fidelity, save recovery, multiplayer synchronization, complete pack semantics or version-specific quirks. Those require named-code analysis and independent Java fixtures or observations. Additional Bend modding, live API/MCP, proofs, packaging and equivalent-workload performance obligations are also tracked; they have no vanilla data-file inventory that could establish their implementation.
