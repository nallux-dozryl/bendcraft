import Base
import ../src/local_tick_world.bend as LW
import ../src/local_input.bend as I
import ../src/player_tick.bend as P
import ../src/player_tick_world.bend as PW
import ../src/player_input.bend as PI
import ../src/travel_world.bend as TW
import ../src/travel.bend as T
import ../src/client_world.bend as W
import ../src/game.bend as G
import ../src/registry.bend as R
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/section_map.bend as SM
import ../src/client_render.bend as V
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/locomotion.bend as L
import ../src/f64.bend as F

def number_gate(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{word} Some{words}: Some{word <> words}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case word <> rest: number_gate(U32.read(word), numbers(rest))

def bit(value: U32) -> Bool:
  U32.is_ne(value, 0)

def vector_show(vector: PI.Vector) -> String:
  PI.Vector{x, z} = vector
  U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(z))

def state_show(state: I.State) -> String:
  I.State{keys, move, trigger, crouching, x, y, xo, yo} = state
  U32.show(PI.mask(keys)) ++ "|" ++ vector_show(move) ++ "|" ++ U32.show(trigger) ++ "|" ++ U32.show(Bool.to_u32(crouching)) ++ "|" ++
    U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(xo)) ++ "|" ++ U32.show(F32.bits(yo))

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vec3_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vec3_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vec3_show(velocity) ++ "|" ++ U32.show(F32.bits(width)) ++ "|" ++ U32.show(F32.bits(height)) ++ "|" ++
    U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def player_show(value: P.State) -> String:
  P.State{body, P.Input{x, y, z}, jump, delay, trigger, sync, speed, head} = value
  body_show(body) ++ "|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++
    U32.show(Bool.to_u32(jump)) ++ "|" ++ U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ U32.show(Bool.to_u32(sync)) ++ "|" ++ U32.show(F32.bits(speed)) ++ "|" ++ U32.show(F32.bits(head))

def parse_state(fields: List<&2, U32>) -> Maybe<&2, I.Controls>:
  match fields:
    case keys <> x <> z <> trigger <> crouching <> bx <> by <> ox <> oy <> sprinting <> Nil{}:
      Some{I.Controls{I.State{PI.from_mask(keys), PI.Vector{L.float_bits(x), L.float_bits(z)}, trigger, bit(crouching), L.float_bits(bx), L.float_bits(by), L.float_bits(ox), L.float_bits(oy)}, bit(sprinting), Nil{}}}
    case _: None{}

def parse_player_input(body: M.Body, fields: List<&2, U32>) -> Maybe<&2, P.State>:
  match fields:
    case x <> y <> z <> jump <> delay <> trigger <> sync <> speed <> head <> Nil{}:
      Some{P.State{body, P.Input{L.float_bits(x), L.float_bits(y), L.float_bits(z)}, bit(jump), delay, trigger, bit(sync), L.float_bits(speed), L.float_bits(head)}}
    case _: None{}

def parse_player(fields: List<&2, U32>) -> Maybe<&2, P.State>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> rest:
      parse_player_input(M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}},
        A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}},
        M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)}, rest)
    case _: None{}

def parse_apply(fields: List<&2, U32>) -> Maybe<&2, I.ApplyContext>:
  match fields:
    case x <> y <> z <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprinting <> no_gravity <> discard <> strength_hi <> strength_lo <> factor <> affected <> sneak_hi <> sneak_lo <> pitch <> Nil{}:
      Some{I.ApplyContext{P.Context{T.Context{T.GroundSample{T.BlockPos{x, y, z}, L.float_bits(friction)}, T.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), bit(sprinting), bit(no_gravity), bit(discard), T.NeutralDryAir{}}, F.F64{strength_hi, strength_lo}, L.float_bits(factor), bit(affected), P.Neutral{}}, F.F64{sneak_hi, sneak_lo}, L.float_bits(pitch)}}
    case _: None{}

def optional_player(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.State>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_player(fields)

def optional_apply(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, I.ApplyContext>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_apply(fields)

def error_show(error: I.Error) -> String:
  match error:
    case I.UnsupportedContext{mode}: "mode"
    case I.UnsupportedPose{}: "pose"
    case I.UnsupportedAbilities{}: "abilities"
    case I.InvalidState{field}: "state|" ++ U32.show(field)
    case I.InvalidAttribute{}: "attribute"
    case I.InvalidPitch{}: "pitch"
    case I.SprintContextMismatch{}: "sprint"
    case I.PlayerError{cause}: "player"

def commands_word(values: List<&2, Bool>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case value <> rest: commands_word(rest, U32.add(U32.mul(acc, 2), Bool.to_u32(value)))

def controls_show(value: Result<&2, &2, I.Error, I.Controls>) -> String:
  match value:
    case Fail{error}: "error|" ++ error_show(error)
    case Done{I.Controls{state, sprinting, +updates}}: "controls|" ++ state_show(state) ++ "|" ++ U32.show(Bool.to_u32(sprinting)) ++ "|" ++ U32.show(U32.from_nat(List.length(&2, Bool, updates))) ++ "|" ++ U32.show(commands_word(updates, 0))

def pose(word: U32) -> I.Pose:
  match word:
    case 0: I.Standing{}
    case 1: I.Crouching{}
    case _: I.OtherPose{}

def mode(word: U32) -> I.Mode:
  match word:
    case 0: I.Neutral{}
    case 1: I.NonControlledCamera{}
    case 2: I.Swimming{}
    case 3: I.FallFlying{}
    case 4: I.Passenger{}
    case 5: I.UsingItem{}
    case 6: I.Screen{}
    case 7: I.AutoJump{}
    case 8: I.NoPhysics{}
    case 9: I.Sleeping{}
    case 10: I.VisualCrawling{}
    case 11: I.Portal{}
    case 12: I.PushOutNeeded{}
    case 13: I.EdgeBackoffNeeded{}
    case 14: I.Immobile{}
    case _: I.NonNeutralEffects{}

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def block(position: T.BlockPos) -> String:
  T.BlockPos{x, y, z} = position
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def palette(value: W.Palette) -> String:
  W.Palette{a, b, c, d} = value
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def bounds(value: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def raw_blocks(values: List<&2, W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, edge}, state, material} <> rest: block(T.BlockPos{x, y, z}) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2, W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{rev, region, colors, blocks}}: Nat.show(rev) ++ "/" ++ bounds(region) ++ "/" ++ palette(colors) ++ "/" ++ raw_blocks(blocks)

def view(value: W.View) -> String:
  match value:
    case W.View{body, yaw, pitch, None{}, region, old}: U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|none|" ++ bounds(region) ++ "|" ++ cache(old)
    case W.View{body, yaw, pitch, Some{colors}, region, old}: U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ palette(colors) ++ "|" ++ bounds(region) ++ "|" ++ cache(old)

def world_report(+id: String, engine: G.Engine, +saved: W.View) -> IO(W.State):
  G.Engine{C.World{+tick, +time, +paused, +daylight, +revision, count, sections, +pending, +events}, registry} = engine
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body_show(PW.view_body(saved)))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(List.length(&2, C.CoreEvent, events)) ++ "|" ++ Nat.show(Q.length(C.Mutation, pending)))
    IO.print(id ++ "|view|" ++ view(saved))
    return W.attach(G.Engine{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, saved)

def report_extracted(id: String, result: G.Engine & W.View) -> IO(W.State):
  (engine, saved) = result
  world_report(id, engine, saved)

def report(id: String, world: W.State) -> IO(W.State):
  report_extracted(id, W.take(world))

def install_body(world: W.State, body: M.Body) -> W.State:
  W.paired(G.Engine, W.View, W.State, W.take(world), engine => saved => W.attach(engine, TW.with_body(saved, body)))

def warmed(result: W.State & Result<&2, &2, String, V.Snapshot>) -> W.State:
  (world, status) = result
  world

type Harness is Type:
  Harness{world: W.State, tables: L.Tables, local: Maybe<&2, I.State>, player: Maybe<&2, P.State>, sprinting: Bool, tail: List<&1, Harness>}

type ControlFields is Data:
  ControlFields{held: PI.Buttons, context: I.Context, horizontal_override: Bool}

type Command is Data:
  Command{local: I.State, player: P.State, sprinting: Bool, held: PI.Buttons, controls: I.Context, context: I.ApplyContext, horizontal_override: Bool, tail: List<&2, Command>}

type Phase is Data:
  Phase{local: I.State, player: P.State, current: Bool, controls: I.Controls, context: I.ApplyContext, tail: List<&2, Phase>}

type SprintReport is Data:
  SprintReport{current: Bool, next: Bool}

type Outcome is Data:
  Outcome{local: I.State, player: P.State, sprint: SprintReport, status: Result<&2, &2, LW.Error, P.Transition>, tail: List<&2, Outcome>}

type FinishCheck is Data:
  FinishCheck{body: M.Body, error: P.Error, tail: List<&2, FinishCheck>}

def travel_error(error: TW.Error) -> String:
  match error:
    case TW.PreparationError{cause}: "travel|prepare"
    case TW.WorldMovementError{cause}: "travel|world|" ++ cause
    case TW.FinishError{cause}: "travel|finish"

def local_error(error: LW.Error) -> String:
  match error:
    case LW.BodyMismatch{}: "body-mismatch"
    case LW.PreparationError{cause}: "prepare|" ++ error_show(cause)
    case LW.TravelError{cause}: travel_error(cause)
    case LW.FinishError{cause}: "finish"

def context_show(context: I.ApplyContext) -> String:
  I.ApplyContext{P.Context{T.Context{T.GroundSample{position, friction}, T.Attributes{speed, gravity, drag, air}, yaw, maximum, sprinting, no_gravity, discard, travel_mode}, strength, factor, affected, tick_mode}, sneak, pitch} = context
  block(position) ++ "|" ++ U32.show(F32.bits(friction)) ++ "|" ++ f64_show(speed) ++ "|" ++ f64_show(gravity) ++ "|" ++ f64_show(drag) ++ "|" ++ f64_show(air) ++ "|" ++ U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(maximum)) ++ "|" ++ flag(sprinting) ++ "|" ++ flag(no_gravity) ++ "|" ++ flag(discard) ++ "|" ++ f64_show(strength) ++ "|" ++ U32.show(F32.bits(factor)) ++ "|" ++ flag(affected) ++ "|" ++ f64_show(sneak) ++ "|" ++ U32.show(F32.bits(pitch))

def phase_report(phase: Phase) -> SprintReport:
  Phase{local, player, current, I.Controls{next, sprinting, updates}, context, tail} = phase
  SprintReport{current, sprinting}

def report_sprinting(sprint: SprintReport, success: Bool) -> Bool:
  SprintReport{current, next} = sprint
  W.choose(Bool, next, current, success)

def outcome_local(outcome: Outcome) -> I.State:
  Outcome{local, player, sprint, status, tail} = outcome
  local

def outcome_player(outcome: Outcome) -> P.State:
  Outcome{local, player, sprint, status, tail} = outcome
  player

def outcome_sprinting(outcome: Outcome) -> Bool:
  match outcome:
    case Outcome{local, player, sprint, Fail{error}, tail}: report_sprinting(sprint, False{})
    case Outcome{local, player, sprint, Done{transition}, tail}: report_sprinting(sprint, True{})

def outcome_lines(+id: String, outcome: Outcome) -> String:
  Outcome{local, player, sprint, status, tail} = outcome
  match status:
    case Fail{error}:
      id ++ "|error|" ++ local_error(error) ++ "\n" ++ id ++ "|local|" ++ state_show(local) ++ "\n" ++ id ++ "|state|" ++ player_show(player)
    case Done{P.Transition{state, M.Transition{body, delta, stepped, changed}, attempted, jumped}}:
      id ++ "|local|" ++ state_show(local) ++ "\n" ++ id ++ "|state|" ++ player_show(player) ++ "\n" ++ id ++ "|transition-state|" ++ player_show(state) ++ "\n" ++ id ++ "|transition|" ++ vec3_show(delta) ++ "|" ++ flag(stepped) ++ "|" ++ flag(changed)

def outcome_report(+id: String, world: W.State, tables: L.Tables, +outcome: Outcome) -> IO(Harness):
  do IO<Harness>:
    IO.print(outcome_lines(id, outcome))
    kept : W.State <- report(id ++ "-after", world)
    return Harness{kept, tables, Some{outcome_local(outcome)}, Some{outcome_player(outcome)}, outcome_sprinting(outcome), []}

def result_report(id: String, sprint: SprintReport, result: W.State & L.Tables & I.State & P.State & Result<&2, &2, LW.Error, P.Transition>) -> IO(Harness):
  (world, tables, local, player, status) = result
  outcome_report(id, world, tables, Outcome{local, player, sprint, status, []})

def call_tick(id: String, world: W.State, tables: L.Tables, +phase: Phase) -> IO(Harness):
  Phase{local, player, current, controls, context, tail} = phase
  result_report(id, SprintReport{current, LW.controls_sprinting(controls)}, LW.tick_checked(world, tables, local, player, controls, context))

def shapes(values: List<&2, A.Collider>) -> String:
  match values:
    case Nil{}: ""
    case A.EmptyCollider{} <> rest: "empty;" ++ shapes(rest)
    case A.BoxCollider{box} <> rest: box_show(box) ++ ";" ++ shapes(rest)

def trace_step(+id: String, registry: R.Registry, saved: W.View, tables: L.Tables, phase: Phase, initial: List<&2, A.Collider>, result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "trace step:" ++ error)
    case Done{step}:
      do IO<Harness>:
        IO.print(id ++ "|colliders|" ++ shapes(initial) ++ "|" ++ shapes(step))
        call_tick(id, W.attach(G.Engine{world, registry}, saved), tables, phase)

def SW_ground(body: M.Body) -> Bool:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  ground

def query_show(query: A.AABB, present: Bool) -> String:
  match present:
    case False{}: "none"
    case True{}: box_show(query)

def initial_status(+id: String, registry: R.Registry, +saved: W.View, tables: L.Tables, phase: Phase, prepared: T.Prepared, world: C.World, status: Result<&2, &2, String, List<&2, A.Collider>>) -> IO(Harness):
  match saved prepared status:
    case W.View{old, yaw, pitch, Some{colors}, region, cache} T.Prepared{+body, +requested, friction, acceleration, +maximum, gravity, drag, discard} Done{+initial}:
      +box = W.body_box(body)
      +baseline = M.resolve(box, SW_ground(body), 0.0, requested, initial, [])
      +query = W.resolution_query(box, requested, maximum, baseline)
      +eligible = W.needs_step(body, maximum, requested, baseline)
      do IO<Harness>:
        IO.print(id ++ "|query-step|" ++ query_show(query, eligible))
        trace_step(id, registry, saved, tables, phase, initial, W.step_read(world, colors, query, eligible))
    case _ _ _: IO.die(Harness, 4, "initial trace unavailable")

def initial_result(id: String, registry: R.Registry, saved: W.View, tables: L.Tables, phase: Phase, prepared: T.Prepared, result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> IO(Harness):
  (world, status) = result
  initial_status(id, registry, saved, tables, phase, prepared, world, status)

def trace_world(+id: String, tables: L.Tables, phase: Phase, +prepared: T.Prepared, engine: G.Engine, +saved: W.View) -> IO(Harness):
  match prepared engine saved:
    case T.Prepared{+body, +requested, friction, acceleration, maximum, gravity, drag, discard} G.Engine{world, registry} W.View{old, yaw, pitch, Some{colors}, region, cache}:
      +stationary = F.is_zero(M.Vec3.length_squared(requested))
      do IO<Harness>:
        IO.print(id ++ "|query-initial|" ++ query_show(M.initial_block_query(W.body_box(body), requested), Bool.not(stationary)))
        initial_result(id, registry, saved, tables, phase, prepared, W.initial_read(world, colors, body, requested, stationary))
    case _ _ _: IO.die(Harness, 4, "trace palette unavailable")

def trace_extracted(id: String, tables: L.Tables, phase: Phase, prepared: T.Prepared, result: G.Engine & W.View) -> IO(Harness):
  (engine, saved) = result
  trace_world(id, tables, phase, prepared, engine, saved)

def accelerated(+id: String, world: W.State, phase: Phase, result: L.Tables & Result<&2, &2, T.Error, T.Prepared>) -> IO(Harness):
  (tables, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "trace acceleration failed")
    case Done{+prepared}:
      T.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
      do IO<Harness>:
        IO.print(id ++ "|requested|" ++ vec3_show(requested))
        trace_extracted(id, tables, phase, prepared, W.take(world))

def phase_context(phase: Phase) -> I.ApplyContext:
  Phase{local, player, current, controls, context, tail} = phase
  context

def observed_prepared(+id: String, world: W.State, +phase: Phase, result: L.Tables & Result<&2, &2, I.Error, I.PreTravel>) -> IO(Harness):
  (tables, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "trace preparation:" ++ error_show(error))
    case Done{I.PreTravel{local, P.PreTravel{+player, +input, attempted, jumped}}}:
      do IO<Harness>:
        IO.print(id ++ "|prepared|" ++ state_show(local) ++ "|" ++ player_show(player) ++ "|" ++ vec3_show(input) ++ "|" ++ flag(attempted) ++ "|" ++ flag(jumped))
        accelerated(id, world, phase, T.prepare_checked(tables, PW.player_body(player), input, PW.travel_context(LW.context_tick(phase_context(phase)))))

def invalid_finish_context(context: I.ApplyContext) -> P.Context:
  I.ApplyContext{P.Context{travel, strength, factor, affected, mode}, sneak, pitch} = context
  P.Context{travel, strength, factor, affected, P.NearbyActors{}}

def finish_prior(view: W.View, phase: Phase) -> LW.Prior:
  Phase{local, player, current, controls, context, tail} = phase
  LW.Prior{view, local, player, []}

def finish_body(phase: Phase) -> M.Body:
  Phase{local, player, current, controls, context, tail} = phase
  T.body_velocity(PW.player_body(player), M.Vec3{F.from_f32(0.5), M.zero(), M.zero()})

def finish_rejection(phase: Phase, intermediate: M.Body) -> Result<&2, &2, P.Error, P.Transition>:
  Phase{local, player, current, controls, context, tail} = phase
  P.finish_checked(P.PreTravel{player, M.Vec3{M.zero(), M.zero(), M.zero()}, False{}, False{}}, invalid_finish_context(context), M.Transition{intermediate, M.Vec3{M.zero(), M.zero(), M.zero()}, False{}, False{}})

def finish_checked_error(body: M.Body, result: Result<&2, &2, P.Error, P.Transition>) -> Maybe<&2, FinishCheck>:
  match result:
    case Fail{error}: Some{FinishCheck{body, error, []}}
    case Done{transition}: None{}

def finish_check(+phase: Phase) -> Maybe<&2, FinishCheck>:
  +body = finish_body(phase)
  finish_checked_error(body, finish_rejection(phase, body))

def checked_finish_body(check: FinishCheck) -> M.Body:
  FinishCheck{body, error, tail} = check
  body

def checked_finish_error(check: FinishCheck) -> P.Error:
  FinishCheck{body, error, tail} = check
  error

def finish_bounded(id: String, engine: G.Engine, view: W.View, tables: L.Tables, +phase: Phase, prior: LW.Prior, +check: FinishCheck) -> IO(Harness):
  result_report(id, phase_report(phase), LW.completed(W.attach(engine, TW.with_body(view, checked_finish_body(check))), tables, prior, I.initial(), Fail{checked_finish_error(check)}))

def finish_extracted(id: String, tables: L.Tables, +phase: Phase, check: FinishCheck, result: G.Engine & W.View) -> IO(Harness):
  (engine, +view) = result
  finish_bounded(id, engine, view, tables, phase, finish_prior(view, phase), check)

def finish_checked_world(id: String, world: W.State, tables: L.Tables, phase: Phase, status: Maybe<&2, FinishCheck>) -> IO(Harness):
  match status:
    case None{}: IO.die(Harness, 4, "actual checked finish unexpectedly succeeded")
    case Some{check}: finish_extracted(id, tables, phase, check, W.take(world))

def finish_injected(id: String, world: W.State, tables: L.Tables, +phase: Phase) -> IO(Harness):
  finish_checked_world(id, world, tables, phase, finish_check(phase))

def run_phase(id: String, op: String, world: W.State, tables: L.Tables, +phase: Phase) -> IO(Harness):
  match op:
    case "reject": call_tick(id, world, tables, phase)
    case "finish-injection": finish_injected(id, world, tables, phase)
    case _: 
      Phase{local, player, current, controls, context, tail} = phase
      observed_prepared(id, world, phase, I.prepare_checked(tables, controls, player, context))

def phase_before(+id: String, op: String, world: W.State, tables: L.Tables, +phase: Phase) -> IO(Harness):
  Phase{local, player, current, +controls, +context, tail} = phase
  do IO<Harness>:
    IO.print(id ++ "-before|local|" ++ state_show(local))
    IO.print(id ++ "-before|state|" ++ player_show(player))
    IO.print(id ++ "|" ++ controls_show(Done{controls}))
    IO.print(id ++ "|context|" ++ context_show(context))
    kept : W.State <- report(id ++ "-before", world)
    run_phase(id, op, kept, tables, phase)

def control_context_player(player: P.State, context: I.Context, override: Bool) -> P.State:
  P.State{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, input, jumping, delay, trigger, sync, speed, head} = player
  I.Context{standing, crouching, food, abilities, mobility, observed, minor, window, pose, mode} = context
  P.State{M.Body{position, box, velocity, width, height, ground, W.choose(Bool, observed, horizontal, override), vertical, below}, input, jumping, delay, trigger, sync, speed, head}

def apply_rejection(op: String, context: I.ApplyContext) -> I.ApplyContext:
  match op context:
    case "sprint-mismatch" I.ApplyContext{P.Context{T.Context{ground, attrs, yaw, maximum, sprint, no_gravity, discard, travel_mode}, strength, factor, affected, mode}, sneak, pitch}:
      I.ApplyContext{P.Context{T.Context{ground, attrs, yaw, maximum, Bool.not(sprint), no_gravity, discard, travel_mode}, strength, factor, affected, mode}, sneak, pitch}
    case "invalid-sneak" I.ApplyContext{tick, sneak, pitch}: I.ApplyContext{tick, F.from_f32(2.0), pitch}
    case "invalid-pitch" I.ApplyContext{tick, sneak, pitch}: I.ApplyContext{tick, sneak, L.float_bits(2143289345)}
    case "invalid-jump" I.ApplyContext{P.Context{travel, strength, factor, affected, mode}, sneak, pitch}: I.ApplyContext{P.Context{travel, strength, 2.0, affected, mode}, sneak, pitch}
    case _ _: context

def operation(op: String) -> String:
  match op:
    case "finish-injection": op
    case "sprint-mismatch": "reject"
    case "invalid-sneak": "reject"
    case "invalid-pitch": "reject"
    case "invalid-jump": "reject"
    case "mismatch": "reject"
    case "zero-mismatch": "reject"
    case "missing": "reject"
    case "unsupported": "reject"
    case _: op

def mismatch_world(op: String, world: W.State, player: P.State) -> W.State:
  match op:
    case "mismatch": install_body(world, T.body_velocity(PW.player_body(player), M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}))
    case "zero-mismatch": install_body(world, T.body_velocity(PW.player_body(player), M.Vec3{F.F64{2147483648, 0}, M.zero(), M.zero()}))
    case "missing":
      W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
      W.State{G.Engine{C.replace_sections(core, SM.EmptySections{}), registry}, body, yaw, pitch, palette, region, cache}
    case _: world

def controlled_result(id: String, +op: String, world: W.State, tables: L.Tables, local: I.State, +player: P.State, current: Bool, context: I.ApplyContext, status: Result<&2, &2, I.Error, I.Controls>) -> IO(Harness):
  match status:
    case Fail{error}: IO.die(Harness, 4, "control admission:" ++ error_show(error))
    case Done{controls}: phase_before(id, operation(op), mismatch_world(op, world, player), tables, Phase{local, player, current, controls, apply_rejection(op, context), []})

def current(id: String, op: String, world: W.State, tables: L.Tables, +local: I.State, +player: P.State, +sprint: Bool, command: Command) -> IO(Harness):
  Command{old_local, old_player, old_sprint, held, control, context, override, tail} = command
  controlled_result(id, op, world, tables, local, player, sprint, context, I.controls_checked(local, sprint, held, control))

def continuing(id: String, op: String, harness: Harness, +command: Command) -> IO(Harness):
  match harness:
    case Harness{world, tables, Some{local}, Some{old_player}, sprint, tail}:
      Command{old_local, old_state, old_sprint, held, +control, context, override, rest} = command
      +player = control_context_player(old_player, control, override)
      current(id, op, install_body(world, PW.player_body(player)), tables, local, player, sprint, command)
    case _: IO.die(Harness, 2, "absent local motion chain")

def starting(id: String, op: String, harness: Harness, +command: Command) -> IO(Harness):
  Harness{world, tables, old_local, old_player, old_sprint, tail} = harness
  Command{+local, +player, +sprint, held, controls, context, override, rest} = command
  current(id, op, install_body(world, PW.player_body(player)), tables, local, player, sprint, command)

def parse_control(fields: List<&2, U32>) -> Maybe<&2, ControlFields>:
  match fields:
    case held <> standing <> crouching <> food <> mayfly <> flying <> mobility <> horizontal <> minor <> window <> pose_word <> mode_word <> override <> Nil{}:
      Some{ControlFields{PI.from_mask(held), I.Context{bit(standing), bit(crouching), food, I.Abilities{bit(mayfly), bit(flying)}, bit(mobility), bit(horizontal), bit(minor), window, pose(pose_word), mode(mode_word)}, bit(override)}}
    case _: None{}

def optional_control(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, ControlFields>:
  match fields:
    case None{}: None{}
    case Some{fields}: parse_control(fields)


# Both fixtures are explicit checked setup outside the pure facade. The base
# 25 stone cells match actual ClientLevel, and collision mode adds (1,1,0).
def queue_changes(mutations: List<&2, C.Mutation>, world: C.World, +tick: Nat, +sequence: Nat) -> C.World:
  match mutations:
    case Nil{}: C.step(world)
    case mutation <> rest: W.paired(C.World, Result<&2, &2, C.Error, Unit>, C.World, C.admit(world, C.Developer{}, Q.Stamp{tick, 73, sequence}, mutation), next => status => queue_changes(rest, next, tick, 1n+sequence))

def queued(world: C.World, tick: Nat, sequence: Nat, mutations: List<&2, C.Mutation>) -> C.World:
  queue_changes(mutations, world, tick, sequence)

def edits_row(n: Nat, +z: U32, +x: U32, +state: U32) -> List<&2, C.Mutation>:
  match n:
    case 0n: []
    case 1n+rest: C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, state} <> edits_row(rest, U32.inc(z), x, state)

def edits_column(n: Nat, +x: U32, +z: U32, +state: U32) -> List<&2, C.Mutation>:
  match n:
    case 0n: []
    case 1n+rest: C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, state} <> edits_column(rest, U32.inc(x), z, state)

def fixture_palette(world: C.World, registry: R.Registry, view: W.View, tick: Nat, palette: Maybe<&2, W.Palette>) -> W.State:
  match palette:
    case None{}: W.attach(G.Engine{world, registry}, view)
    case Some{W.Palette{+air, +stone, dirt, planks}}:
      mutations = List.append(&2, C.Mutation, edits_row(6n, 4294967293, 4294967293, air), List.append(&2, C.Mutation, edits_column(5n, 4294967294, 4294967293, air), List.append(&2, C.Mutation, edits_row(5n, 4294967294, 2, stone), [C.BlockSet{C.Position{"minecraft:overworld", 1, 1, 1}, air}, C.BlockSet{C.Position{"minecraft:overworld", 2, 1, 2}, air}, C.BlockSet{C.Position{"minecraft:overworld", 2, 2, 2}, air}])))
      W.attach(G.Engine{queued(world, tick, 0n, mutations), registry}, view)



def fixture(world: W.State) -> W.State:
  W.State{G.Engine{C.World{+tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, body, yaw, pitch, +palette, region, cache} = world
  fixture_palette(C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry, W.View{body, yaw, pitch, palette, region, cache}, 1n+tick, palette)

def edit_extracted(value: U32, position: C.Position, result: G.Engine & W.View) -> W.State:
  (G.Engine{C.World{+tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, saved) = result
  W.attach(G.Engine{queued(C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, 1n+tick, 0n, [C.BlockSet{position, value}]), registry}, saved)

def edit_world(world: W.State, position: C.Position, value: U32) -> W.State:
  edit_extracted(value, position, W.take(world))

def edit_material_palette(world: W.State, position: C.Position, stone_selected: Bool, palette: Maybe<&2, W.Palette>) -> W.State:
  match palette:
    case None{}: world
    case Some{W.Palette{air, stone, dirt, planks}}: edit_world(world, position, W.choose(U32, stone, air, stone_selected))


def edit_material(world: W.State, position: C.Position, stone_selected: Bool) -> W.State:
  W.State{engine, body, yaw, pitch, +palette, region, cache} = world
  edit_material_palette(W.State{engine, body, yaw, pitch, palette, region, cache}, position, stone_selected, palette)


def default_block(result: R.Registry & Result<&2, &2, R.Error, R.Block>) -> R.Registry & U32:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, 4294967295)
    case Done{R.Block{protocol, name, first, count, default_id, properties}}: (registry, default_id)

def glass(world: W.State) -> W.State:
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  W.paired(R.Registry, U32, W.State, default_block(R.Registry.block(registry, "minecraft:glass")), owner => value => edit_world(W.State{G.Engine{core, owner}, body, yaw, pitch, palette, region, cache}, C.Position{"minecraft:overworld", 0, 0, 0}, value))

def recover_palette(world: C.World, registry: R.Registry, view: W.View, +tick: Nat, colors: Maybe<&2, W.Palette>) -> W.State:
  match colors:
    case None{}: W.attach(G.Engine{world, registry}, view)
    case Some{palette}: fixture(W.attach(G.Engine{queued(world, 1n+tick, 0n, W.fixture_mutations(palette)), registry}, view))

def recover_world(world: W.State) -> W.State:
  W.State{G.Engine{C.World{+tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, body, yaw, pitch, +palette, region, cache} = world
  recover_palette(C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry, W.View{body, yaw, pitch, palette, region, cache}, tick, palette)

def command_execute(id: String, op: String, harness: Harness, command: Command) -> IO(Harness):
  match op:
    case "start": starting(id, op, harness, command)
    case "start-finish": starting(id, "finish-injection", harness, command)
    case "start-block":
      Harness{world, tables, local, player, sprint, tail} = harness
      starting(id, "start", Harness{warmed(W.snapshot(edit_material(world, C.Position{"minecraft:overworld", 1, 1, 0}, True{}), 64, 48)), tables, local, player, sprint, tail}, command)
    case "unsupported":
      Harness{world, tables, local, player, sprint, tail} = harness
      starting(id, op, Harness{glass(world), tables, local, player, sprint, tail}, command)
    case "repair":
      Harness{world, tables, local, player, sprint, tail} = harness
      starting(id, "start", Harness{edit_material(world, C.Position{"minecraft:overworld", 0, 0, 0}, True{}), tables, local, player, sprint, tail}, command)
    case "missing": starting(id, op, harness, command)
    case "fixture-recovery":
      Harness{world, tables, local, player, sprint, tail} = harness
      starting(id, "start", Harness{warmed(W.snapshot(recover_world(world), 64, 48)), tables, local, player, sprint, tail}, command)
    case _: continuing(id, op, harness, command)

def command_parsed(id: String, op: String, harness: Harness, local: Maybe<&2, I.Controls>, player: Maybe<&2, P.State>, control: Maybe<&2, ControlFields>, apply: Maybe<&2, I.ApplyContext>) -> IO(Harness):
  match local player control apply:
    case Some{I.Controls{local, sprint, updates}} Some{player} Some{ControlFields{held, controls, override}} Some{apply}:
      +command = {Command{local, player, sprint, held, controls, apply, override, []} : Command}
      command_execute(id, op, harness, command)
    case _ _ _ _: IO.die(Harness, 2, "invalid local-world command")
def optional_local(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, I.Controls>:
  match fields:
    case None{}: None{}
    case Some{fields}: parse_state(fields)


def header(fields: List<&2, String>, harness: Harness, local: String, player: String, controls: String, context: String) -> IO(Harness):
  match fields:
    case id <> op <> Nil{}: command_parsed(id, op, harness, optional_local(numbers(String.split(local, '|'))), optional_player(numbers(String.split(player, '|'))), optional_control(numbers(String.split(controls, '|'))), optional_apply(numbers(String.split(context, '|'))))
    case _: IO.die(Harness, 2, "invalid local-world header")


def dispatch_parts(parts: List<&2, String>, harness: Harness) -> IO(Harness):
  match parts:
    case name <> local <> player <> controls <> context <> Nil{}: header(String.split(name, '|'), harness, local, player, controls, context)
    case _: IO.die(Harness, 2, "invalid local-world parts")

def continue_args(args: List<String>, harness: Harness) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        next : Harness <- dispatch_parts(String.split(value, ';'), harness)
        continue_args(rest, next)

def loaded_world(args: List<String>, tables: L.Tables, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Unit, 3, "fixture:" ++ error)
    case Done{unit}: continue_args(args, Harness{warmed(W.snapshot(fixture(world), 64, 48)), tables, None{}, None{}, False{}, []})

def loaded_table(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "table load")
    case Done{tables}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        loaded_world(args, tables, W.fixture(engine))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded_table(rest, tables)
    case _: IO.die(Unit, 2, "local-world table path required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)
