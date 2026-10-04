# Durable LocalPlayer record

Confidence: high in the declared format and ordinary type checks. Native fixture and kernel validation are separately reported; preparation is not execution. This is a custom Bendex record, not vanilla player.dat or complete player persistence.

`src/local_player_record.bend` exposes pure Data `Record{motion:PlayerRecord.Record,local:LocalInput.State,sprinting:Bool,pose:PlayerPose.State,minor:LocalMoveWorld.MinorState,history:PlayerFallHistory.History,entity:EntityCommonTick.Metadata}`. `validate(+record)`, `encode(record)` and `decode(bytes)` return `Result<&2,&2,Error,A>`; `error_text` renders the typed error. Data inputs remain available to the caller on failure. The record is an immutable save projection; it does not create another live Body owner.

The existing motion record retains raw Body position, velocity and AABB F64 words; width/height and Player input/speed/head F32 words; all ground/collision flags; jumping, needs_sync and raw signed delay/trigger words; cached support; exact current/previous degree angles and checked renderer radians; dimension. New fields retain previous sampled LocalInput keys and movement, sprint trigger, crouching, four bob floats, sprinting, pose/cached eye, minor-collision cache, fall-distance F64, both distinct historical position triples, signed invulnerability timer and wrapping tick count. No physical held-button or mouse field is present. Restoring sampled input is independent of releasing actual held buttons.

The version-one NBT root is named `bendex:local-player-record`. Canonical member order is:

| Key | Exact tag and payload |
| --- | --- |
| format | Int 1 |
| motion | ByteArray: existing `bendex:player-record` physical NBT |
| local_keys | ByteArray of seven 0/1 bytes: forward, backward, left, right, jump, shift, sprint |
| local_floats | Float list of six raw words: movement x/z, x_bob/y_bob/x_bob_old/y_bob_old |
| local_trigger | Int: raw signed word |
| local_crouching, sprinting | Byte 0 or 1 |
| pose | Int: Standing 0 or Crouching 5 |
| eye | Float: exact cached eye-height word |
| minor | Byte 0 or 1 |
| fall_distance | Double: exact raw F64 pair |
| old_positions | Double list of six: position_o xyz, then position_old xyz |
| invulnerable_time, tick_count | Int: raw U32 words |

The decoder accepts reordered members and writes canonical order. It rejects duplicate, absent or unexpected keys, other versions/names, wrong numeric tag widths, wrong list declarations/counts, invalid Boolean bytes and unsupported poses/dimensions. There is no numeric-tag coercion. The existing physical NBT codec retains raw floating payloads; admissible signed zeros and subnormals therefore survive exactly.

Admission combines existing PlayerRecord validation (including degree-to-radian raw projection), LocalInput.state_error, History.history_error, EntityCommonTick.metadata_error and PlayerPose.state_error against the sole motion Body. Standing and crouching use actual adult unit dimensions and cached eye values; pose tail must be empty and the Body AABB must match the canonical computed box bit for bit. Dimension is overworld. History requires finite F64 only: finite negatives are retained. All signed counter words and support main/flag combinations are admitted. No new relationship is inferred between prior sampled input, Player input/jumping, support, minor collision, fall history, old positions or current Body. These caches can differ at a phase boundary.

Physical parsing and encoding use a fixed 16,384-byte cap, depth two and 8,192 elements per container. Input bytes/counts/depth are bounded by NBT before allocating tag containers. Embedded motion is independently bounded by its existing 8,192-byte codec. Fixed schema lists then require exact lengths. Failure publishes no partial record or encoded bytes.

`src/local_player_storage.bend` exposes `encode(record)->record & Result<Data String,Bytes>`, `decode(schema,bytes)->Result<&2,&1,String,Record>`, `initial(Unit)`, `refuse_core_only(Unit)`, `codec()` and `limits()`. The closed leased ExtendedPersistence codec uses namespace `bendex:local-player-record`, schema one and extension cap 16,384. Encode returns the complete record unchanged on success or failure. Initial state is standing at (0.5,1,-2.5), grounded, zero motion/look/history/counters and initial sampled input; both old-position triples equal initial position. Core-only and older plain Player saves require an explicit migration rather than invented missing caches. Existing ExtendedPersistence owns the lease, world-clock/edit state and atomic bundle publication; this module adds no filesystem effects.

Runtime ownership tails, terrain cache, tables, physical buttons, mouse accumulation/options and last diagnostic remain in the facade's Transient owner. Generic detach/attach must retain even forged tails; active tick admission and any checked save projection are separate caller policies. The durable Pose tail is validated here. The record codec alone cannot inspect tails that its Record does not contain.

Reproduce preparation and bounded verification with `python3 tools/test_local_player_record.py prepare`, then `audit`, `ordinary`, `build`, `native`, `kernel` as separate modes. Build/native/kernel require the lead's heavy-slot grant. Only prepare can write input fixtures; other modes verify existing bytes and sealed source/oracle/import pins first. Audit writes no receipt or fixture. Existing attempt artifacts are refused. Build, each native batch and each kernel command have process-group watchdogs of 600, 120 and 60 seconds. Raw argv, streams and receipts are retained before comparisons; each batch is compared immediately and execution stops on its first mismatch. Kernel runs only after both complete native comparisons and checks source before harness.

The independent Python oracle constructs physical NBT, reads all raw words and verifies the admission domain using existing independent numeric/wire oracles. The 755 prepared cases cover rich Standing/Crouching records, independent random values, signed timers/count wrap words, signed zeros/subnormals/extreme finite words, finite negative history, support caches, numeric-equal but raw-inconsistent AABB zeros, malformed embedded motion, tag/schema/Boolean/list errors, truncation, depth/count/byte limits, direct in-memory Pose-tail rejection and accepted same-process recovery after every rejection. Preparation seals all Bend/Base/effect imports, transitive local Python helpers and loaded Python runtime modules; the full seal and raw fixtures live under ignored build/local-player-record/generation-1. Source/harness laws establish exact error retention and test mutation preservation, not a universal codec-roundtrip or vanilla equivalence theorem. Actual TCP save/restart and corruption recovery belong to the separate LocalPlayerSession consumer evidence.

Storage's ordinary checker reports the existing 42 unsafe/foreign definitions from imported durability, locking and persistence effects. The pure record and pure harness pass ordinary checks. This foreign boundary is not a pure kernel proof of filesystem atomicity. No foreground client or OS input was launched for this codec.

## Consolidated consumer verification

The lead deferred a separate component emission and kernel run in favor of actual LocalPlayerSession integration. The final Session test entry imports this pure harness as RecordTest and exposes `record-cases MODE INPUT OUTPUT ...` calling RecordTest.batch. `tools/test_local_player_record_consumer.py` verifies the same 755 frozen fixtures against that one explicitly pinned Session binary. It accepts the consumer's complete schema-one file-pin manifest, whose seal hashes canonical JSON excluding seal_sha256, and requires that manifest to include the binary, verifier and original oracle. It checks the frozen 83 Bend/effect and 151 Python import pins, whole executable, full unchanged consumer manifest and all input bytes before and after each batch. No original preparation, oracle or input is rewritten. Each of two runs retains its own output files and full exclusive attempted-command/process/comparison receipts, including the first failure. Actual TCP/MCP/save/restart and the LocalPlayer tick-path comparisons remain the Session runner's responsibility. No consolidated consumer result is claimed until that artifact executes and passes.
