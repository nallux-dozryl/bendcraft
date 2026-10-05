# Cooking save continuation representation

The actual Session save route now carries its retained `R.Transient` and the
captured publication snapshot through `CookingSaveAnchor`. Its recursive
constructor makes this one native reference. `CompletedSave` then owns that
anchor together with the exact returned `E.State<CookingStorage.Saved>`,
Session, JSON reply and typed save-completion receipt. The completed input stays
closed across the IO return; the pure consumer opens it afterward.

These are representation carriers for the existing transaction. The actual
peer observation, single Session-sequence increment, codec and atomic writer
remain in the original admitted save branch. The exact returned player/world,
inventory and save-shell fields rejoin their retained runtime and Sidecar.
`E.NotCommitted` retains the live publication journal. Only the existing
`E.DurablyCommitted` gate can acknowledge the captured snapshot. A successful
JSON reply from an unsynced publication does not change that gate.

Both recursive nesting constructors preserve their complete inner owner and
are handled by structurally decreasing consumers. They introduce no new world,
entity, RNG or publication owner. Current mutable Session also retains the
separately checked TickRecovery path; that future path was not added to the
immutable actor022 source overlay.

## Measured scope

The private frozen021 overlay002 passed one complete original source check:
9,546 declarations, all 9,586 declaration-order entries, and zero holes. The
actual selected native-body observations reduced the codec continuation from
268 to 199 parameter words and the completed-save return from 250/251 to 58.
The selected maximum was 245 in `profile_loaded$k4`, below the compiler's 247
parameter limit. These observations cover the selected frozen021 bodies; they
are not a full native build or a guarantee for an expanded future graph.

The accepted patch is `build/actor021_arity_overlay_002/candidate.diff`, SHA256
`ee7986d2680bdc109954f3d72d99f510de952680285f8542b6e36412bddf3f38`.
Root applied this exact source change to the separate actor022 snapshot and
started its full compiler/native chain. The working-source merge changes only
the same save continuation block, retaining current recovery and owner APIs.

## Current consumer verification

`python3 tools/test_local_player_cooking_save_box.py --generation 1` passed
the whole actual loaded current consumer Book: 8,796 declarations across 185
source files, zero holes, and one unchanged original `B.book_valid` call.
Checking took 4.923573333 seconds; checking plus selected export took 15.677965
seconds. The three new roots passed the independent kernel in 0.036209 seconds
with zero exclusions. All source hashes matched after verification and both
process groups were absent.

All three laws quantify arbitrary depths of both recursive wrappers and
complete stored player, save-shell, runtime and cooking owners. Their premise
uses the actual `R.attach` returned player, rather than a parallel owner model.
The nondurable branch retains that complete owner and exact returned Session
and JSON for any captured snapshot. The durable branch without a snapshot does
the same. With a snapshot, the typed durable branch invokes the actual
acknowledgement consumer using that exact capture and owner; validation and
journal mutation remain that consumer's separate contract. Input builders
construct only the production wrappers and contain no save-result model.

Receipts are `evidence/local-player-cooking-save-box-source-001.json` and
`evidence/local-player-cooking-save-box-proof-001.json`. This check includes
current Session recovery, Frame and bootstrap consumers, including retained
format5 metadata. It does not check the entire Entry graph or execute the
physical writer. No native IO, save durability, future actor arity or managed
tick claim follows from these pure laws or the private selected measurements.
