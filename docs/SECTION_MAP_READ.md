# Order-preserving section reads

`src/section_map_read.bend` provides an owned read of the actual section trie. It imports only Base, `section_map.bend` and `section.bend`, so the shared Core can call it without a dependency cycle.

```text
read(sections, key, local_x, local_y, local_z)
  -> Sections & Maybe<Result<Section.Error, U32>>
```

The previous `Core.read_block` path removed the requested section with `pop`, then reinserted it with `set`. In a bucket containing two different keys with the same hash, reinsertion could move the queried entry to the front. An otherwise read-only query could therefore change the raw owned world representation, including on a later callback refusal. The new reader reconstructs every branch and bucket entry in its original position and calls the original checked `Section.get` for the selected key. It also retains empty bucket and malformed trie constructors when a lookup cannot descend through them. Missing keys return `None`; checked local-coordinate errors return `Some(Fail(...))` with all bucket entries retained.

The root joined `Core.read_block` to this interface through `Core.read_retained`. The shared Core still owns the sole clock, queues, event list and section map; the reader owns and returns the map during the read. Existing missing-section and invalid-coordinate mappings are preserved. `player_block_inside_stuck.query` continues to use `Core.read_block`; there is no callback-specific world clone or substitute map.

Eleven laws in `section_map_read_laws.bend` cover checked getter refusal with arbitrary arrays, selected entry position, collision prefixes, exact empty/malformed trie constructors, branch framing and full bucket-entry order. The two actual bucket composition laws state their premises explicitly: the original `Section.get` returns its owner, and the recursive bucket read returns its owner. They are source-coupled interface obligations, not an unconditional proof of every array read or of every Core lifecycle. The actual native callback consumer passed all 1,965 expected responses in 30.457 seconds. Its collision corpus exercises both queried keys in both orders, repeated reads, and a later refused block callback while observing every raw section cell, branch and bucket.

The unchanged eleven proof roots passed the independent kernel with zero exclusions. IR: 54,538 bytes; ordinary/source-export/kernel times: 0.115/1.105/0.018 seconds. See `evidence/section-map-read-proof.json`.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_section_map_read_proof.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_block_inside_stuck.py
```

The native comparison and its collision-owner checks are recorded separately in `evidence/player-block-inside-stuck-native.json`. Historical failed build attempts remain retained; a successful proof receipt does not claim a native run occurred.
