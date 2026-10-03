# Neutral Player aiStep projection

`src/player_tick.bend` implements the admitted motion/input/counter projection of the pinned Minecraft Java **26.3** `Player.aiStep()` wrapper. It performs Player velocity cleanup, horizontal float input decay, jump-delay and Player jump-trigger countdowns, dry grounded jumps and sprint impulses before travel. It reuses exact `travel.bend`, `locomotion.bend`, and `movement.bend`; afterward it records Player's actual head-yaw and stored-speed assignments.

Confidence is **high for recorded admitted projected cases**. This is not complete `Player.tick`, LocalPlayer input control, ServerPlayer behavior, or all entity state changed by aiStep. Fall distance, fire, health, effect/movement bookkeeping, animation, inventory semantics, pose/abilities, controllers and other modes remain outstanding under the full Minecraft goal.

## Stable owner-retaining contract

```bend
type Input is Data:
  Input{xxa: F32, yya: F32, zza: F32}

type State is Data:
  State{body: M.Body, input: Input, jumping: Bool,
        jump_delay: U32, jump_trigger: U32, needs_sync: Bool,
        stored_speed: F32, head_yaw: F32}

type Context is Data:
  Context{travel: T.Context, jump_strength: F.F64,
          jump_factor: F32, affected_by_fluids: Bool, mode: Mode}

type PreTravel is Data:
  PreTravel{state: State, input: M.Vec3,
            jump_attempted: Bool, jumped: Bool}

type Transition is Data:
  Transition{state: State, movement: M.Transition,
             jump_attempted: Bool, jumped: Bool}

prepare_checked(tables: L.Tables, state: State, context: Context)
  -> L.Tables & Result<&2,&2,Error,PreTravel>

finish_checked(prepared: PreTravel, context: Context,
               movement: M.Transition)
  -> Result<&2,&2,Error,Transition>

tick_checked(tables: L.Tables, state: State, context: Context,
             initial: List<&2,G.Collider>, step: List<&2,G.Collider>)
  -> L.Tables & Result<&2,&2,Error,Transition>
```

Both counter words store **signed Java int two's-complement payloads in U32**. Negative counters are supported: only strictly positive signed values decrement. Zero and negative Player jump-trigger values persist; holding jump with a negative nonzero delay blocks ground jumping until release resets it to zero.

For an owned world, retain the earlier immutable state until every phase succeeds:

1. Resolve actual supporting-block friction, current attributes, jump strength and block jump factor, yaw/sprint/gravity/drag flags, and eligible context. `jump_strength` is the current resolved `JUMP_STRENGTH` attribute. `jump_factor` must follow actual `Entity.getBlockJumpFactor()`: read both the current and support block factors, choose support when widened current factor equals `1d`, otherwise choose current. This module does not invent or own the supporting-block resolver.
2. Call `prepare_checked`; retain the returned Tables owner on success or failure. `PreTravel.state.body` contains cleaned and possibly jumped velocity. Grounding still comes from the original Body. `PreTravel.input` widens the decayed float fields.
3. Perform the existing owned-world travel bridge using that Body, widened input, and `context.travel`. Its collision queries must derive from travel's accelerated request, not the original velocity or the jump impulse alone.
4. Call `finish_checked` on the successful travel transition. Install the final body and tick fields together only after success. Restore the earlier state on any rejected preparation, world move, travel finish or tick finish.

`tick_checked` combines supplied complete ordered collision lists for callers that already hold them. It does not collect world shapes. Finishing does not repeat travel, gravity or drag.

Errors are `UnsupportedContext{mode}`, `TravelError{cause:T.Error}`, `InvalidState{field}` and `InvalidJump{field}`. State indices 0/1/2 are float X/Y/Z input, 5 is stored speed and 6 is head yaw; counter fields admit all signed-int payloads. Jump indices 0/1 are strength and factor. Body errors retain Travel/Movement's existing named components. All failed preparation/combined tick paths return the affine Tables owner.

## Admission

`Mode.Neutral` requires movement simulation, effective AI and local authority, awake/alive mobility, no body/head interpolation, empty inventory and equipment, no nearby actors or auto-spin, dry weather and non-neutral block effects absent. The existing Travel context additionally requires no passenger/controller, fluids/swimming, ability flight, glide, climb, powder snow, mob effects or edge backoff, loaded applicable client chunks, unit block speed factor and suppressed bounce. These facts are caller-resolved context; a Body alone cannot establish them.

Rejecting tick modes are `Immobile`, `Interpolating`, `SimulationDisabled`, `IneffectiveAi`, `NonEmptyEquipment`, `NearbyActors` and `NonNeutralEffects`, with the existing Travel modes providing the fluid/flight/climb/passenger/effect rejection. Admission occurs before Tables lookup and state mutation. Finite input/head/stored-speed values, finite jump strength `[0,32]`, and finite jump factor `[0,1]` are checked. Travel's attribute/body/context checks remain in force.

The recorded actual Player corpus has `isAffectedByFluids()==true`. The explicit Boolean also represents the production selector's reset behavior when false, but that alternative is not claimed as observed ordinary neutral Player behavior. This context field must come from entity/ability state; it does not license an unsupported flight/fluid mode.

Stone, dirt, oak planks, ice and blue ice are admitted oracle materials. **Slime is excluded for aiStep**: actual `SlimeBlock.stepOn` changes horizontal velocity after travel even with suppressed bounce. Honey and other speed/inside/step effects also need explicit implementations. Travel's earlier slime observations establish its own narrower pre-block-effect path and do not establish slime aiStep parity.

## Exact order and numbers

Player first decrements its positive `jumpTriggerTime`; inherited LivingEntity then decrements positive `noJumpDelay`. Interpolation, non-simulation velocity damping, equipment, immobility and AI branches have their original order, while unsupported branches are rejected by this module's admission contract.

Cleanup tests the original velocity:

```text
horizontal = round_f64(round_f64(x*x) + round_f64(z*z))
if horizontal < 9.0E-6d: x = +0d; z = +0d
if abs(y) < .003d: y = +0d
```

Player uses a combined horizontal squared-speed test, not independent `.003d` component tests. Exact thresholds are `3ee2dfd694ccab3f` and `3f689374bc6a7efa`. Equality preserves the original value. Cleanup-selected zero is positive, including for tiny negative components and negative zero.

`applyInput()` separately rounds `xxa *= .98f` and `zza *= .98f`; the float payload is `3f7ae148`. `yya` is preserved. For a dry grounded player, held jumping with the decremented delay equal to zero invokes `jumpFromGround`, then assigns delay **10 even if jump power is too small to apply an impulse**. Releasing jump immediately resets delay zero. Holding while airborne retains the decremented delay.

With no Jump Boost, jump power is separately rounded float:

```text
power = ((narrow_f32(current_jump_strength) * 1f) * jump_factor) + +0f
```

Power at or below `1.0E-5f` (`3727c5ac`) returns without changing velocity or `needsSync`. Otherwise Y becomes `Math.max(widen_f32(power), oldY)`. Already greater upward velocity survives. Successful jump does not directly clear grounding.

Sprinting computes float `yaw * .017453292f` (`3c8efa35`), widens the angle for the actual Mth lookup semantics, negates sine as float, widens the trig results, and multiplies X/Z by double `.2d`. It adds `(x,+0d,z)` in binary64 and sets `needsSync=true`. Exact table ownership is retained between sine and cosine reads. No rendering trig, fixed-point substitute, foreign gameplay function or GPU bang is used.

Travel consumes the widened decayed float input and the cleaned/jumped velocity. Its acceleration precedes Entity movement, then gravity/drag. After inherited aiStep, Player sets `head_yaw=yaw` and `stored_speed=narrow_f32(current resolved MOVEMENT_SPEED)`. Existing stored speed does not determine actual Player ground acceleration.

## Decisive oracle and verification

`tools/reference_player_tick_probe.py` calls **untouched actual `Player.aiStep()`**, including inherited LivingEntity.aiStep, original applyInput/jumpFromGround/jump-power and block-jump-factor code, actual Player travel/Entity movement, actual inventory/equipment ticks, block effects, and push/touch loops. Observer overrides call their superclass and record cleaned/pre-travel/post-travel/final projected state. Expected states come from direct Java reads, not a host-composed algorithm.

The fixture reuses Travel's actual Player constructor/attributes and real finite Level/BlockCollisions, including its declared local-authority, suppressed-bounce and no-emission return contracts and its guarded real loaded no-fluid LevelChunk sections. New Level adapters return an actual empty Scoreboard with no teams and an empty actor-query result for the declared actor-free world. This preserves production team predicate construction and Level.getPushableEntities. No aiStep entity algorithm or block-effect hook is suppressed. Player regeneration, shoulder and LivingEntity server-AI hooks are already empty production methods. Empty inventory/equipment make their actual loops empty. ServerLevel-only hazards/animation branches are outside this plain Level fixture.

The first reproduced held-forward/jump sequence executes 24 calls on the same actual Player. The complete corpus contains **511 sequences and 2,752 actual aiStep calls**, including float-decay chains, release/repress and sprint sequences, cleanup thresholds and neighbors, signed counters, tiny/threshold jump powers, greater existing upward velocity, huge finite yaw, input subnormal/signed-zero/rounding/extremes, five materials, collision/step worlds and 256 seeded eight-tick sequences. Another **60 direct `jumpFromGround` / jump-power observations** exercise actual honey/slime current/support block-factor priority and float narrowing. Those call only the jump method and validate its numerical helper; they do not admit honey/slime aiStep, travel or block effects.

Native verification compares every pre-travel projected state and exact widened input, every final projected state, and separately repeats all sequences while carrying the previous native state forward. Only actual external control updates overwrite the carried input/jumping flags. **61 rejected inputs/contexts** are each followed by a continued correct chain to check Tables retention and prior-state rollback; three malformed requests also fail. The six kernel laws state the precise ownership, decay, cleanup, release, ineffective-jump cooldown and failed-travel properties; they do not prove full Player parity.

```sh
python3 tools/reference_player_tick_probe.py
python3 tools/reference_player_tick_probe.py --verify-existing
python3 tools/reference_player_tick_probe.py --selftest
python3 tools/test_player_tick.py
```

The reference pins official jar, class/method, runtime, library and composite probe-source hashes and explicitly records return contracts and projection limits. Two direct Java reruns and deliberate counter corruption with and without a resealed checksum test provenance and expected-data integrity. Reproducible commands, current kernel/native/build timings, counts, source/table/binary hashes and rejection summaries are in `evidence/player-tick*.json`. Timing measures this verification workload and does not establish a Minecraft performance advantage.

Required continuation includes owned-world/actor integration and real support/attribute resolution, actual Player.tick/LocalPlayer control and sprint/pose/ability policies, jumping effects and non-unit block behavior, full mutated entity fields, actual ServerPlayer/server-world execution, fluid/flight/glide/climb/passenger/effect branches, hazards, inventory semantics, networking and authoritative controller state.
