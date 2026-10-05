# Cooking incarnation admission before the scheduled tick

An incarnation token is a transient `Nat` identifying a cooking owner at its
complete dimension/position key. Its maximum is `2^48-1`; accepting one more
teardown at that token would wrap the native representation and could admit an
old menu handle as the new owner. Refusing after a due write would already have
changed Core, Entry arrays, light and the clock.

`Core.prospective_results(world, mutations)` therefore queries application
admission through the actual retained Section trie. It returns the same sole
complete World and an ordered result for each mutation. The query never calls
`apply`, `step`, `pop`, array writes, or `Section.new`. It preserves empty
buckets, malformed constructors, collision ordering, duplicate keys and every
array payload. It distinguishes a rejected malformed section create from a
missing write. An ordered immutable list records only earlier successful
SectionCreate keys, so a later write to that new section is accepted and a
second create is rejected. Permission, dimension, state/catalog and due
descriptor validation remain the existing caller's responsibility, exactly as
for `Core.apply`.

`local_player_cooking_incarnation_guard.check` projects immutable headers from
the actual `Store.inspect` views, which retain and describe the actual Entry
order. Each accepted Core BlockSet performs the same first matching header
selection and real `Bindings.same_block` identity test as `Store.change`.
Changing only LIT or properties retains the owner. Replacing/removing an
existing owner emits one prospective reset; creating an absent owner does not.
Cooking SectionCreate inserts the original 4096 indexed headers and emits no
reset itself. Rejected Core applications change no lifecycle metadata.
Duplicate entries are retained: this is an ordered list, not a position map
that silently merges owners. Temporary counters check `current < MAX` before
each increment, including repeated replacement/remove/recreate in one batch.
Acknowledgement skips a global prefix of reset markers, independently of
Drop/XP effects or position. Normal newly completed Idle phases have zero
acknowledgement; pending retry uses the existing cooking phase rather than
starting another due batch.

The additive actor seam is:

```bend
CW.start_tick_owned(~Light, ~properties, ~enabled,
  light_context, context, incarnations, acknowledged_resets, state)
  -> CW.State & Result<CW.Error, Unit>
```

It preserves the original Busy/loading, inspection, residency, sorted due
partition, descriptor authentication and classification order. After those
readonly steps it checks the whole prospective reset sequence. An exhausted
counter returns `Authority{"local-cooking:incarnation-exhausted"}` with the
complete input World/light/Entries/phase/loading owner, before tick, time,
pending queue, event history, revision, sections or light changes. Admission
then invokes unchanged `CW.started`, which advances the clock once and applies
the original ordered due operations. Legacy `CW.start_tick` is unchanged. The
LocalCooking caller supplies its retained map and acknowledgement, and later
actual OwnerReset publication remains the only counter mutation authority.

Production verification: the exact `Core`, `CookingWorld` and guard production
bytes passed the original complete Entry012 Book check: 9,564 declarations,
211 source files, zero holes, 4.75804225 seconds. The source checkpoint pins
that complete closure and all three matching production files in
`evidence/local-player-cooking-incarnation-guard-checkpoint.json`. This is a
source/API result. Its checkpoint preserves the first seven failed narrow
source attempts, including their exact process/output receipts.

The revised narrow source and receiver subsequently passed one original Book
check: 1,683 declarations, all 11 laws, 0.4549085 seconds. Nine unchanged roots
exported with no exclusions; the independent kernel accepted that exact
881,770-byte artifact with `ALL PROOFS CHECK` in 0.16387 seconds. Source and
kernel receipts are recorded separately in
`evidence/local-player-cooking-incarnation-guard-{source,kernel}.json`. The two
additional source failures are retained. The native receiver is source-checked
but has not run, so the numeric MAX48 threshold behavior remains unverified by
this new receiver.

The new laws quantify over arbitrary owners. The inductive route law retains
every actual trie path, including malformed shapes and collision arrays;
other laws connect real binding identity, rejected Core results, the actual
exhaustion branch before increment, acknowledged resets, cancelled later scans and actual CW prepared
failure publication. Their exact scope does not assert universal prospective
status agreement or universal header/lifecycle parity. The focused native
receiver uses original `C.apply` for differential application admission and
the complete structural Core observer for preservation. It tests MAX and
MAX-1 late refusal, repeated replacement, remove/recreate/remove, absent
owner creation followed by removal, accepted SectionCreate with its later
write and 4096 fresh headers, ignored missing writes/existing creates,
same-block properties, physical furnace padding and a retained light FIFO.
The lifecycle fixture is explicitly synthetic; it is not Java parity evidence.

The universal law connecting `observed` to the concrete MAX48 comparison is
currently open. The original checker overflows its normalization stack while
unfolding `Nat.is_lt(current, maximum())` in that proposed proof. The selected
branch law instead establishes that actual `counted(False{}, ...)` refuses
before touching the arbitrary counter map; it does not prove the arithmetic
comparison or that every exhausted observed value reaches this branch. The
production bound remains exactly MAX48. The native threshold cases exercise
the actual `start_tick_owned`/`check`/`observed` path separately when run.

Reproducible commands, after coordinating the existing two-heavy-job limit:

```sh
python3 tools/test_local_player_cooking_incarnation_guard.py --prepare
python3 tools/test_local_player_cooking_incarnation_guard.py --source-only
python3 tools/test_local_player_cooking_incarnation_guard.py --proof-only
python3 tools/test_local_player_cooking_incarnation_guard.py
```

The runner checks the original proof and narrow test in one original Book,
selects original checked root declarations without rewriting their types or
bodies, and passes that artifact to the independent kernel. It records source,
tool, term, output and process receipts in its fresh build directory and
`evidence/local-player-cooking-incarnation-guard*.json`. No compiler source,
Java fixture, full actor build or previous cooking corpus is changed. A failed
source/export/kernel/native attempt receives a preserved failure receipt; no
unexecuted verification is implied by prepared source.

Direct player edits require their separate before-edit counter guard. Durable
storage, actual menu handles, rendering/OS input and tick-wide rollback after
an already accepted cooking start are outside this additive preflight seam.
