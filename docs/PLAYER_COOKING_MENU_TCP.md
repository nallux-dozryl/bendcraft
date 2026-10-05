# Actual cooking-menu TCP consumer

`tools/test_playable_client_cooking_menu.py` consumes an existing successful
actor generation. It never builds an actor or substitutes host gameplay.
The default paused scenario uses real public TCP and the retained private
socket/lease owner to send CookingOpen, Inspect, Click, QuickMove and Close.
It checks each complete correlated reply, including the actual furnace slots
and four raw timer words, all exposed player cells, saved abilities, carried
item, menu revision and authoritative handle.

Run file-only preparation with the bundled Python runtime:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_playable_client_cooking_menu.py --actor-generation 20 --expectations
```

The same command with `--native` runs the existing immutable actor020 binary.
It creates a new numbered `build/playable-client-cooking-menu` directory,
uses unique owned ports, retains raw requests/replies and the first failure,
and records cleanup. The unrelated old actor on ports25565/25566 is untouched.
The current full-catalog startup allowance is150seconds; the default actor
lifetime is240seconds within a300second supervisor allowance.

The independent expectations reuse the pinned26.3 menu observations in
`reference/player_cooking_menu.json`. Six observed single-operation cases
establish right-half pickup and quick-move direction. Eight literal sequential
deltas compose those observations with occupied destination cells and the
existing inventory close-return contract. This composition is an expected
live scenario, not a retained complete Java world observation.

The default scenario first covers retained-owner refusals for a wrong menu,
range or dimension, observer mutation denial, bad capability/socket/header,
second lease and stale sequence. It then runs the actual transfers and carried
return. `menu-positive-summary.json` is written before save or optional costly
work, so a later failure does not conceal which operations succeeded. The save
projection checks the actual Core, player record,43 durable inventory cells,
raw status, keyed cooking body and exact acknowledged publication. It retains
and hashes pending effects rather than pretending they were delivered.

Frozen actor020 has a concrete publication dependency: a furnace slot mutation
can enqueue `Store.Dirty`, whose effect consumer refuses with
`cooking-entities:block-entity-and-comparator-publisher-required`. The actual
run must retain that trigger and its owners. The host runner never drains the
queue or fabricates an acknowledgement. A real publisher belongs in a later
production generation; this consumer does not rebuild020.

`--lifecycle-only` is a separate initially empty, unlit-furnace scenario. It
opens the real menu, queues a same-position remove/recreate through the actual
Core, takes one explicit simulation tick, rejects the old incarnation, closes
the stale empty handle, and checks a new incarnation and monotonically
allocated menu ID. Its save checks the fresh physical body with cleared prior
Details. No earlier GUI mutation introduces Dirty into this fixture. This is
a distinct lifecycle test, not a replay of the transfer scenario.

`--component-overflow` is optional and runs only after default positive/save
checks. It uses the existing actual initialized1200-effect item profile,
places one exact key in the furnace and one in the player owner, and measures
the complete prospective reply against65536ASCII bytes. On refusal it checks
the same retained lease, complete acknowledged physical bytes, and recovery
without consuming the next menu ID. Frozen020 predates the linear component
tail repair; this path can be expensive and is not a prerequisite for ordinary
cooking-menu availability. Its receiver allowance is90seconds per reply and
its actor allowance600seconds.

The TCP DTO exposes48 logical player cells and three furnace slots. It does
not expose player backing48..63 or the fourth furnace backing cell; their
retention remains the separately recorded51-case native owner-consumer scope.
This runner makes no render, OS input, item/orb constructor, RNG parity,
complete opaque recipe-cache or unfinished atomic-write claim. Those consumers
have separate receipts. Prepared receipts are file-only until a numbered
native receipt records an actual run.

Actual actor020 results are recorded separately:

- `evidence/playable-client-cooking-menu-native-006.json`: default scenario
  passed in34.212seconds, with20 complete correlated cooking replies, five
  lease/header fault cases, exact inventory transfers and carried return, and
  an acknowledged20269byte save. Pending effects were retained; their
  delivery was not tested in this paused route.
- `evidence/playable-client-cooking-menu-native-008.json`: the initially empty
  lifecycle passed with six complete replies, a real remove/recreate tick,
  old-incarnation refusal, new incarnation1/menu ID2 and an acknowledged
  19240byte save whose fresh physical body cleared the old Details.

Both runs used binary SHA256
`54b79ea92479b84ebd3d194d2f2fadd8f8504970d6aa9db2b42beb2d865741e8`.
Owned actor groups and listeners were cleaned. Neither run requested the
optional aggregate component case.

`evidence/playable-client-cooking-menu-save-body-006.json` adds a file-only
byte comparison of the already acknowledged006 save against the independent
physical encoder. Its283byte furnace body exactly retains the original raw
root name and ordered duplicate extra members, with three empty slots,
timers10/10/0/200, empty RecipesUsed and speed bits1065353216. The original
acknowledged file hash is required; this projection neither reruns the actor
nor fabricates another save acknowledgement. Future default runs assert those
exact body bytes directly.
