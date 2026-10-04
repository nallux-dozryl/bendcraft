import Base
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./movement.bend as M
import ./f64.bend as F
import ./core.bend as C
import ./registry.bend as B
import ./player_fall_history.bend as H
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./client_world.bend as W
import ./game.bend as G
import ./support.bend as SP

law entity_web_replaces_multiplier_and_resets_fall_only:
  for old: M.Vec3
  for +impulse: P.Impulse
  for history: H.History
  for level: P.Level
  for protocol: U32
  for state: U32
  for assignments: List<&2, B.Assignment>
  {P.callback_checked(P.Receiver{old, impulse}, history, P.OtherEntity{}, level,
    B.Resolved{protocol, "minecraft:cobweb", state, assignments}) ==
    Done{P.Candidate{P.Receiver{P.web_multiplier(False{}), impulse}, H.History{M.zero()}, False{}}} : Result<&2, &2, P.Error, P.Candidate>}

law flying_player_keeps_multiplier_and_history_but_clears_ready_impulse:
  for +old: M.Vec3
  for position: Maybe<&2, M.Vec3>
  for +history: H.History
  for +weaving: Bool
  for level: P.Level
  for protocol: U32
  for state: U32
  for assignments: List<&2, B.Assignment>
  {P.callback_checked(P.Receiver{old, P.Impulse{0, position}}, history, P.Player{True{}, weaving}, level,
    B.Resolved{protocol, "minecraft:cobweb", state, assignments}) ==
    Done{P.Candidate{P.Receiver{old, P.Impulse{0, None{}}}, history, True{}}} : Result<&2, &2, P.Error, P.Candidate>}

law nonzero_impulse_grace_retains_exact_position:
  for +grace: U32
  for +position: Maybe<&2, M.Vec3>
  for nonzero: {U32.is_eq(grace, 0) == False{} : Bool}
  {P.impulse_reset(P.Impulse{grace, position}) == P.Impulse{grace, position} : P.Impulse}

law excluded_living_berry_cannot_set_stuck_or_require_damage:
  for +receiver: P.Receiver
  for +history: H.History
  for effect: Bool
  for level: P.Level
  for protocol: U32
  for state: U32
  for assignments: List<&2, B.Assignment>
  {P.callback_checked(receiver, history, P.OtherLiving{True{}, effect}, level,
    B.Resolved{protocol, "minecraft:sweet_berry_bush", state, assignments}) ==
    Done{P.Candidate{receiver, history, False{}}} : Result<&2, &2, P.Error, P.Candidate>}

law eligible_berry_overwrites_previous_web_multiplier:
  for old: M.Vec3
  for +impulse: P.Impulse
  for history: H.History
  for effect: Bool
  for protocol: U32
  for state: U32
  {P.callback_checked(P.Receiver{P.web_multiplier(effect), impulse}, history, P.OtherLiving{False{}, effect}, P.ClientLevel{},
    B.Resolved{protocol, "minecraft:sweet_berry_bush", state, [B.Assignment{"age", "3"}]}) ==
    Done{P.Candidate{P.Receiver{P.berry_multiplier(), impulse}, H.History{M.zero()}, False{}}} : Result<&2, &2, P.Error, P.Candidate>}

law refused_damage_cannot_commit_a_stuck_setter:
  for receiver: P.Receiver
  for history: H.History
  for facts: P.Facts
  for +error: P.Error
  {P.berry_ready(receiver, history, facts, Fail{error}) == Fail{error} : Result<&2, &2, P.Error, P.Candidate>}

law callback_failure_discards_speculation_and_retains_complete_owner:
  for state: P.State
  for facts: P.Facts
  for level: P.Level
  for position: C.Position
  for scratch: P.Scratch
  for +error: P.Error
  {P.loop(3n, state, facts, level, [P.Contact{position, P.BlockIntersection{}}], Fail{error}) ==
    (state, Fail{error}) : P.State & Result<&2, &2, P.Error, P.Observation>}

law exhausted_query_retains_arbitrary_complete_owner:
  for state: P.State
  for facts: P.Facts
  for level: P.Level
  for position: C.Position
  for admission: P.Admission
  for rest: List<&2, P.Contact>
  for scratch: P.Scratch
  {P.loop(0n, state, facts, level, P.Contact{position, admission} <> rest, Done{scratch}) ==
    (state, Fail{P.QueryBudget{}}) : P.State & Result<&2, &2, P.Error, P.Observation>}

law unresolved_intersection_retains_owner_and_discards_candidate:
  for state: P.State
  for facts: P.Facts
  for level: P.Level
  for position: C.Position
  for scratch: P.Scratch
  {P.contact(state, facts, level, P.Contact{position, P.UnresolvedIntersection{}}, scratch) ==
    (state, Fail{P.UnknownIntersection{}}) : P.State & Result<&2, &2, P.Error, P.Scratch>}

law failed_world_read_retains_world_registry_receiver_history_and_tail:
  for world: C.World
  for registry: B.Registry
  for receiver: P.Receiver
  for history: H.State
  for tail: List<&1, P.State>
  for facts: P.Facts
  for level: P.Level
  for position: C.Position
  for scratch: P.Scratch
  for +error: C.Error
  {P.block_read(registry, receiver, history, tail, facts, level, position, scratch, (world, Fail{error})) ==
    (P.State{world, registry, receiver, history, tail}, Fail{P.WorldError{error}}) : P.State & Result<&2, &2, P.Error, P.Scratch>}

law successful_commit_preserves_all_affine_environment_owners:
  for world: C.World
  for registry: B.Registry
  for old: P.Receiver
  for previous: H.State
  for tail: List<&1, P.State>
  for +receiver: P.Receiver
  for +history: H.History
  for +impulse: Bool
  for +reads: List<&2, P.Read>
  {P.commit(P.State{world, registry, old, previous, tail}, P.Scratch{P.Candidate{receiver, history, impulse}, reads}) ==
    (P.State{world, registry, receiver, H.State{history}, tail},
      Done{P.Observation{receiver, history, impulse, List.reverse(&2, P.Read, reads)}}) : P.State & Result<&2, &2, P.Error, P.Observation>}

law consumed_multiplier_clears_only_multiplier:
  for value: M.Vec3
  for +impulse: P.Impulse
  {P.consume_gate(P.Receiver{value, impulse}, True{}) == P.Receiver{M.Vec3.zero(), impulse} : P.Receiver}

law inactive_success_preserves_raw_multiplier_and_impulse:
  for +value: M.Vec3
  for +impulse: P.Impulse
  for inactive: {F.is_gt(M.Vec3.length_squared(value), M.stuck_threshold()) == False{} : Bool}
  {P.travel_succeeded(P.Receiver{value, impulse}) == P.Receiver{value, impulse} : P.Receiver}

law rejected_stationary_join_retains_full_actual_motion_owner:
  for world: C.World
  for registry: B.Registry
  for +view: W.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for request: P.Stationary
  {PM.stationary_gate(P.State{world, registry, receiver, history, []}, PM.Frame{view, support, minor, tail}, request, False{}) ==
    (MH.State{W.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, Fail{P.BodyMismatch{}}) : MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>}

# The premise names the actual callback service; even after earlier callbacks,
# a later refused callback returns the original affine State, not Scratch.
law refused_decoded_callback_retains_owner_after_earlier_callbacks:
  for state: P.State
  for +facts: P.Facts
  for +level: P.Level
  for +position: C.Position
  for +receiver: P.Receiver
  for +history: H.History
  for +impulse: Bool
  for +reads: List<&2, P.Read>
  for +resolved: B.Resolved
  for +error: P.Error
  for refused: {P.callback_checked(receiver, history, facts, level, resolved) == Fail{error} : Result<&2, &2, P.Error, P.Candidate>}
  {P.decoded(state, facts, level, position, P.Scratch{P.Candidate{receiver, history, impulse}, reads}, Done{resolved}) ==
    (state, Fail{error}) : P.State & Result<&2, &2, P.Error, P.Scratch>}
