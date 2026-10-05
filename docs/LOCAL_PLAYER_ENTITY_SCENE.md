# Atomic world and entity frame capture

`local_player_entity_scene.capture(Session.State,width,height,policy,partial)`
returns the same sole Session owner and the shared immutable
`remote_entity_frame.Frame{sample,entities,dimension,partial}`. The backend's
actual command20 route uses this capture; the Wire codec imports only the DTO,
not the effectful Session graph.

After frame/finite interpolation validation and normal Scene residency
preparation, the synchronous continuation reads the canonical player record,
the real `GS.Sample`, then the actual retained entity owner. No Core step or IO
occurs between those observations. The sample therefore carries the same
registry identity, tick, revision, pose-aware F64 eye origin and camera used
for the entity frame. `partial` is the exact validated supplied render fraction
in [0,1]; it is not a fabricated clock observation. The current sample reader
fixes world cell queries to the Overworld, so other player dimensions refuse.

Only the parent's minimal `RenderSnapshot` leaves the owner. It contains item
and XP render fields in actual retained list order, with IDs, dimensions,
current/old positions, accessibility and interpolation inputs. Level/entity
RNG, UUID/factory data, health and constructor-clock queues remain inside the
complete Session. An unbound entity carrier publishes an explicit Unbound
snapshot. Wire stamp validation rejects mixed registry/tick/revision/dimension/
origin/camera/interpolation frames.

The six actual capture laws cover early invalid-frame/interpolation/dimension
refusals, exact sample refusal forwarding, and publication of the actual bound
or unbound presentation projection while retaining the complete returned
Session. They do not establish residency preparation rollback, actor
serialization, renderer behavior, entity simulation or network behavior. The
full original Entry graph and these law closures passed together in actual
Entry012: 9,564 declarations, 211 source files, zero holes, and one original
`B.book_valid` call (4.75804225 seconds). All source hashes still matched after
the checker reaped. The subsequent unchanged twelve-law export hit a stack
overflow, so no independent kernel claim is made for this generation.
`evidence/local-player-entity-scene-source-012.json` records the source pass
separately from that export failure. Actual TCP acceptance belongs to the
coherent new actor artifact and strict Wire consumer.

Actor022 has now exercised this frozen capture through genuine private TCP
tag20/reply9. Five full frames matched the independent 384-cell sample and
the saved two Item records and one XP Orb, including exact interpolation bits
for 0.5, negative zero and 1. Eight lease/header fault and reacquisition cases
also passed. Complete 136,449-byte format4 saves before and after the reads
were identical, retaining RNG, factory and publication fields; the paused
Core clock was unchanged. The 40.092-second narrow run ended all owned groups.
`evidence/remote-entity-scene-network-native-004.json` records this acceptance.
It covers the frozen actor022 capture, not the newer format5 recovery path,
managed entity ticks, renderer parity or visible client acceptance.
