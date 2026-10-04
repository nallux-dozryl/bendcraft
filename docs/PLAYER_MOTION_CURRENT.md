# Current stuck-speed movement phase — Java 26.3

The existing saved actor calls `X.reset_stage_travel_started` →
`TH.ability_travel_with_reset_checked`. That production path now consumes the
explicit current `TH.Hooks.stuck_multiplier` observation before edge backoff and
collision. Previously the downstream `LM` neutral admission rejected every
numerically nonzero multiplier. Neutral, required-reset and ability-history
travel entry points now share the new phase; their public request/result types
are unchanged.

Confidence is **high for the recorded phase and complete Player.travel cases**.
The current four-state live world provider still supplies zero. Resolving cobweb,
berry or other `blockInside` behavior from world state, keeping the actual
receiver multiplier across ticks, and enabling those block definitions remain
dependencies. This change does not establish those services or visible movement
acceptance.

`M.stuck_checked(body, requested, multiplier)` returns
`Result<M.Error,M.StuckPreparation>`, where `StuckPreparation` contains the
corrected Body, corrected request, remaining multiplier and applied flag.
For admitted SELF/PLAYER movers, unchanged pinned `Entity.move` evaluates
`((x*x)+(y*y))+(z*z) > 1e-7d` with binary64 threshold
`3e7ad7f29abcaf48`. Equality is inactive. An inactive phase preserves every raw
Body, request and multiplier word, including signed zero. An active phase
multiplies the already accelerated displacement request component by component,
replaces Body velocity with positive `Vec3.ZERO`, and clears the receiver
multiplier to positive zero. This occurs before `maybeBackOffFromEdge` and
collision, so backoff observes the scaled request and restitution starts from
the cleared velocity. Piston and noPhysics have earlier distinct branches and
are outside this entry.

`T.stuck_checked(prepared,multiplier)` applies the same checked phase after
`T.prepare_checked`, preserving friction, acceleration, step maximum, gravity,
air drag and friction-discard values. TH's original Frame remains the complete
rollback anchor. Only the downstream LM admission receives a resolved zero
multiplier; the retained Frame still contains the original receiver observation.
Late movement, history, reset-supplier and finish failure therefore restore the
same original Body, world/registry owner, support, minor flag, history and Tables.
The lower `prepared`, `reset_prepared` and `ability_reset_prepared` helpers now
take a preparation whose stuck phase has already resolved; checked public entry
points perform that phase automatically.

Nonfinite input multipliers are rejected as `M.InvalidBody{component:3,field}`.
Finite componentwise multiplication overflow is rejected as
`M.NonFiniteResult{component:3,field}`. Existing T `MovementError` and TH
preparation-error wrappers retain these errors. Raw Java accepts nonfinite
numbers; these checked refusals protect the existing finite simulation contract.
The returned `M.StuckPreparation.multiplier` is the exact field value that a
future stateful receiver provider must retain after successful movement. TH's
current immutable Hooks are conditional observations, not a newly stored
receiver authority.

The new oracle in `tools/reference_player_motion_current_probe.py` normally
constructs an actual Player and finite actual Level through the retained travel
fixture. It sets the real `Entity.stuckSpeedMultiplier` field and observes the
actual edge hook while calling its superclass. `Player.travel`, inherited
LivingEntity travel and `Entity.move` execute unchanged. Both independent JVM
runs agree on all **105 complete Player.travel cases**: 77 active, 28 inactive,
six exact threshold equalities, 31 collision cases and 11 actual step-query
cases. Signed zeros, strict threshold neighbors, single/pair axes, finite huge
multipliers with zero requests, floor/wall/ceiling/step collisions and
gravity/drag/discard combinations are covered. The reference contains complete
raw Body snapshots before stuck, after stuck, after collision and after travel.
Jar/class/source/runtime/library pins and checksum plus resealed-corruption
checks pass in `evidence/player-motion-current-reference*.json`.

The standalone native harness calls the actual production `T.prepare`,
`M.stuck`, `T.stuck`, `M.move` and travel finish functions. All **525 exact phase
comparisons** pass, followed by ten checked multiplier/overflow refusals and ten
successful same-process Tables-owner recovery calls. A corrupted expected Body
is rejected. The one native build emitted C in 3.210 seconds and compiled in
4.967 seconds; total builder time was 13.383 seconds, with zero retries and a
reaped process group. These are verification timings, not game-performance
claims. Compact receipts link the full retained report/C/artifact and raw output
under ignored `build/player-motion-current/`.

Eight laws in `src/player_motion_current_laws.bend` state actual production
inactive preservation, active request scaling and velocity reset, refusal
without a candidate, complete travel-factor preservation, all other Hook-field
preservation, and complete TH ability-owner rollback. The inactive law binds the
actual `M.stuck` selector to its explicit numerical-service premise. The
whole-owner refusal law binds the actual `T.stuck_checked` result to TH's
checked ability dispatch. These laws do not independently prove arbitrary IEEE
arithmetic or the provenance of receiver observations. Ordinary checking and the
independent kernel pass. The read-only selective export preserves all original
declaration maps and every selected type/body, recursively retains actual
dependencies, and has zero exclusions; its final IR is 811,601 bytes. The earlier
wrapper success-marker mismatch is retained as a host failure, and the corrected
wrapper records the actual kernel's `ALL PROOFS CHECK` result.

Reproduce from the Minecraft repository:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_motion_current_probe.py --verify-existing
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_motion_current.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_motion_current_proof.py
```

`--skip-build` on the native test verifies all 1,632 retained build dependency
hashes/aliases and both executable digests before reusing the binary. It also
checks the current owned sources/reference. The historical local-travel corpus's
`local-move-context:2` refusal for a nonzero multiplier describes the prior
unsupported contract; that single expectation is superseded by this exact phase.
Historical frozen receipts remain unchanged. Root integration should recheck its
current saved actor on the joined source generation. The existing
`local_player_reset_proof.bend` and `local_player_abilities_proof.bend` targets
both pass current ordinary checking after this change, recorded in
`evidence/player-motion-current-integration.json`; their full current kernel and
saved-actor refresh remain root integration work. No slab scanner, saved player
codec, root entry or compiler source was changed by this lane.
