# Saved LocalPlayer abilities in the production actor

The production Scene queries the actual saved `I.Status` through
`S.run_with_status` before each admitted scheduled or realtime tick. The runtime
returns its complete `X.State` and a status value. A rejected tick retains every
original status field and raw binary32 word; a paused realtime pulse retains
both owners exactly. Scene admission failure bypasses the runtime. Successful
flight changes publish through the same saved inventory owner.

`R.step_status`, `R.realtime_status`, and `R.advance_status` retain the original
Driver request, environment, budgets and ownership. The original neutral
`R.step`, `R.realtime_step`, and `R.advance` interfaces remain available.

The actual non-spectator, controlled-camera, dry LocalPlayer phases are:

1. The saved mayfly/flying flags affect control sampling. Flying suppresses
   crouching; mayfly permits sprinting without the ordinary food threshold.
   Sprint setter order remains the existing production control sequence.
2. A new jump edge with mayfly arms the seven-tick trigger when it is zero.
   Another edge while it is nonzero toggles flying and clears the trigger.
   Turning flight on while grounded invokes the real ground-jump arithmetic
   before inherited Player/LivingEntity preparation; it does not itself set
   the inherited jump delay.
3. Flying adds the ordered binary32 expression
   `(float direction * saved flying speed) * 3.0f` to vertical velocity before
   inherited cleanup and input replacement. Opposed jump/shift inputs skip
   this addition, preserving the original signed-zero value at that phase.
4. Inherited movement still resolves the actual collision, support and minor
   collision outcome. Flying skips the player's crouching edge backoff.
   Airborne flight acceleration uses the saved flying speed, doubled by the
   actual sprint state; grounded acceleration uses the resolved movement
   attribute and ground friction.
5. The outer Player travel phase restores vertical velocity to the prepared
   pre-travel Y times `0.6d`, including after vertical collision. The returned
   body is installed into the same authoritative world owner before rotation
   and late pose. Successful grounded non-spectator completion clears flying.
6. Player flight resets fall history before movement. Entity movement still
   performs downward history accumulation and the required reset-ray gate.
   Mayfly makes actual Player fall damage return false; the checked history
   dispatcher therefore admits landing without a health mutation in that
   specific branch.

Walking speed remains a saved raw binary32 word. The runtime derives the
movement attribute using the real sprint modifier order and the attribute's
NaN/range sanitization to `[0,1024]`; it does not rewrite the saved word. Flying
speed also remains raw. Active nonfinite flight arithmetic is refused by the
checked runtime rather than replaced with an unrelated default. Invulnerable,
mayfly, and both speed words remain exact when flying is published.

The derivation uses the installed 26.3 LocalPlayer, AbstractClientPlayer,
Player, Abilities, AttributeInstance and RangedAttribute bytecode. The new
receiver probe constructs actual LocalPlayer, ClientLevel and
MultiPlayerGameMode normally, retaining the declared external client services
from the existing input probe. Its selected sequences cover vertical up/down,
opposed inputs with negative zero, sprinting with zero food, ground flight
activation, ground cancellation and double-tap activation. Python chooses
inputs and compares observations; it implements no movement expectation.

The new proof target is `src/local_player_abilities_proof.bend`. Its statements
cover the full actual LM/FR/H/T movement completion, required-ray refusal
through whole-phase rollback with complete saved status retention, and
publication of the complete returned tick owner with only the flying status
field changed. Supplier, numerical movement/history/finish and checked tick
results remain explicit service premises. These equations are extensional
ownership/composition claims, not operational call-count or IEEE proofs.

The existing dry lifecycle, fullcube/air world supplier, controlled-camera and
non-spectator service boundaries remain explicit. The current driver and reset
supplier retain the admitted `[-64,64]^3` box; this is not Minecraft world-border
parity. Fluid swimming, riders, spectator behavior, gliding, effects, observable
callbacks, health/combat, and whole Minecraft lifecycle are outside this
movement contract. Numerical parity and native actor execution require their
actual retained receipts; source acceptance alone does not establish them.

The three actual ownership laws passed ordinary checking and the independent
BendTT kernel in `evidence/local-player-abilities-proof-001.json`. The read-only
selective export retained all original declaration tables and compiled proof
terms, selected only the three roots, and produced 1,266,298 bytes with zero
exclusions. Export took 5.7766 seconds and the cached kernel took 0.1936 seconds;
source, API, IR and kernel pins remained unchanged and process groups were reaped.
The actual Java receivers passed complete plain/observer parity in the retained
reference runs recorded by `evidence/local-player-abilities-reference-001.json`.
The first run's case named `ground-flight-takeoff` began flying and therefore
observed flight turning off followed by an ordinary ground jump. That capture
is preserved. A second, one-case run began grounded and not flying with a live
jump trigger, and observed flight turning on with the actual ground takeoff.
The numerical suite uses this corrected capture for that case.

The separate numerical LI/P harness passed ordinary checking, compiled in
7.0786 seconds, and passed all 13 selected actual-Java tick comparisons in
0.6257 seconds. `evidence/local-player-abilities-native-001.json` retains the
exact complete Body and Player metadata, local input/bob and travel-input word
comparisons, the 1,322,952-byte binary pin, source generation, compiler identity,
argv, raw capture pins and process cleanup. Its binary SHA-256 is
`43fa66554d0f668bdcd07549ff6c3a984e38070395be791426e64aa87a0da886`.

This numerical target starts at the actual post-control observation and ends
at inherited pre-travel preparation. It supplies the observed toggle and
takeoff choice, so it does not independently certify the runtime selector.
Whole travel/collision/history, the outer post-travel Y override, the two
inherited attempted/jumped bookkeeping flags, and the current saved actor's
native execution remain outside these 13 numerical comparisons. Confidence is
high for the stated conditional ownership laws and exact preparation cases;
complete flight/world numerical parity remains unverified.
