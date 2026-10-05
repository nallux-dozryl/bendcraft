# Real TCP entity scene observer

`tools/test_remote_entity_scene_network.py` is prepared for an explicitly selected
successful actor producer after020. No actor with the new command20 endpoint has
been exercised by this runner yet. Actor020 and all existing receipts stay intact.
The separate 407-case native codec receipt remains
`evidence/remote-entity-scene-wire-native.json`.

The real input owner comes from the acknowledged save in
`evidence/playable-client-cooking-entities-native-005.json`: two Item records and
one Orb record, with complete player/inventory/status/generation, entity fields,
RNG states, factory counters and clock inputs independently decoded and reencoded.
Its original 21,186-byte save has SHA256
`aa3515bbe0b68b31dab76c0cb1dee9ea454add72b6a8bd6f4da6333cf5162c65`.

That save has unspecified generation settings and only one resident section.
The actual runtime default view region is `(-4,-1,-4)` with dimensions `8×6×8`
(`client_world.default_region`). Legacy `Scene.ensure` preserves it. The earlier
generated-world helper's centered `8³` expectation does not apply. Preparation
therefore adds the seven absent neighboring sections as static air fixture input.
Every original section, other Core field, generation byte, player/inventory/body
and full entity owner remains unchanged. This is fixture serialization, with no
host simulation or entity construction. The original verified save is retained.

The new Entry initializes a fresh publication journal and saves format4. The
observer uses the existing strict publication physical decoder and independently
builds the expected complete format4 save. This fixture's incarnation map is
empty and its journal is sequence0 with no dirty chunks/latest receipt. Paused
frame reads and private lease operations must preserve that complete state.
Prepared physical round trips establish serialization expectations only.

The planned actual socket run will:

- Admit the genuine private capability and read old command13/reply7. Check all
  384 actual default-region cells, traversal order, state IDs, boundaries,
  declared policy/mixer, saved pose-aware F64 eye, camera and Core stamp.
- Request command20/reply9 with exact fraction words for `0.5`, signed negative
  zero and `1.0`. Compare the entire correlated reply with the independently
  projected saved records: full ItemKeys/counts, current/old F64 words, bob words,
  order, Orb value, dimension and the same world sample.
- Refuse bad capability, a second lease owner, an unassigned scene socket,
  invalid width, negative/nonfinite fractions, bad version and a genuinely
  replayed sequence. Reacquire the lease and confirm the original frame again.
- Acknowledge physical saves before/after polling and compare every format4
  byte, including full Core/player/inventory/entity/RNG/factory/publication state.
  Record raw private request/reply streams, actual ASCII reply sizes and owned
  process cleanup. A PASS requires the bounded runner's complete cleanup verdict.

Use the bundled Python runtime that already imports the existing helper closure:

```
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B \
  tools/test_remote_entity_scene_network.py --actor-generation 21 --expectations
```

Once the actual successful Actor021 binary/source/runtime pins are available,
the same command with `--native` starts one bounded paused actor and its real
public/private TCP clients. It never builds. Every attempt uses a fresh numbered
directory and receipt; artifact/source/runtime identity is checked automatically.
The old actor protocol is not substituted if the new artifact is unavailable.

Network Unbound remains unexercised because Entry initializes a bound entity
owner; the codec independently covers Unbound and Bound-empty. The socket run
will establish this paused read scenario, not general capture serialization,
entity simulation, Java behavioral parity, rendered pixels, Window/OS input or
whole-game acceptance. Camera/fraction are captured within the actual atomic
DTO; this runner does not join separately timed publications.

Preparation001 retained the initial format4 serializer check using the original
single-section seed. Preparation002 also validates the resident fixture needed
for the actual default sampler. Both are file-only records, with no socket or
actor execution claim. The latest preparation receipt pins the current runner
and exact physical input/expectations.
