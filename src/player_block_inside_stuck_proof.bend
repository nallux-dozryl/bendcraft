import Base
import ./player_block_inside_stuck.bend as P
import ./movement.bend as M
import ./f64.bend as F
import ./player_block_inside_stuck_laws.bend as Laws

def Laws.entity_web_replaces_multiplier_and_resets_fall_only(old, impulse, history, level, protocol, state, assignments):
  {==}

def Laws.flying_player_keeps_multiplier_and_history_but_clears_ready_impulse(old, position, history, weaving, level, protocol, state, assignments):
  {==}

def Laws.nonzero_impulse_grace_retains_exact_position(grace, position, nonzero):
  %Equal.sym(Bool, U32.is_eq(grace, 0), False{}, nonzero) : {P.impulse_gate(P.Impulse{grace, position}, _) == P.Impulse{grace, position} : P.Impulse}
  {==}

def Laws.excluded_living_berry_cannot_set_stuck_or_require_damage(receiver, history, effect, level, protocol, state, assignments):
  {==}

def Laws.eligible_berry_overwrites_previous_web_multiplier(old, impulse, history, effect, protocol, state):
  {==}

def Laws.refused_damage_cannot_commit_a_stuck_setter(receiver, history, facts, error):
  {==}

def Laws.callback_failure_discards_speculation_and_retains_complete_owner(state, facts, level, position, scratch, error):
  {==}

def Laws.exhausted_query_retains_arbitrary_complete_owner(state, facts, level, position, admission, rest, scratch):
  {==}

def Laws.unresolved_intersection_retains_owner_and_discards_candidate(state, facts, level, position, scratch):
  {==}

def Laws.failed_world_read_retains_world_registry_receiver_history_and_tail(world, registry, receiver, history, tail, facts, level, position, scratch, error):
  {==}

def Laws.successful_commit_preserves_all_affine_environment_owners(world, registry, old, previous, tail, receiver, history, impulse, reads):
  {==}

def Laws.consumed_multiplier_clears_only_multiplier(value, impulse):
  {==}

def Laws.inactive_success_preserves_raw_multiplier_and_impulse(value, impulse, inactive):
  %Equal.sym(Bool, F.is_gt(M.Vec3.length_squared(value), M.stuck_threshold()), False{}, inactive) : {P.consume_gate(P.Receiver{value, impulse}, _) == P.Receiver{value, impulse} : P.Receiver}
  {==}

def Laws.rejected_stationary_join_retains_full_actual_motion_owner(world, registry, view, support, minor, history, tail, receiver, request):
  {==}

def Laws.refused_decoded_callback_retains_owner_after_earlier_callbacks(state, facts, level, position, receiver, history, impulse, reads, resolved, error, refused):
  %Equal.sym(Result<&2, &2, P.Error, P.Candidate>, P.callback_checked(receiver, history, facts, level, resolved), Fail{error}, refused) : {(state, P.step_candidate(position, resolved, P.Scratch{P.Candidate{receiver, history, impulse}, reads}, _)) == (state, Fail{error}) : P.State & Result<&2, &2, P.Error, P.Scratch>}
  {==}
