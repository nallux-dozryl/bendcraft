import Base
import ./local_travel_history.bend as TH
import ./local_phase_runtime.bend as X
import ./local_player_runtime.bend as R
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./fall_reset_world.bend as FR
import ./travel.bend as T
import ./movement.bend as M
import ./locomotion.bend as L
import ./client_world.bend as W
import ./support.bend as SP
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./entity_common_tick.bend as ECT
import ./player_runtime.bend as PR
import ./player_look.bend as PL

import ./player_inventory.bend as I
import ./local_player_abilities_laws.bend as Laws

def Laws.required_ray_refusal_retains_whole_owner_and_saved_status(engine,tables,candidate,support,minor,reset_work,phase_work,mode,saved,selection,cause,refused):
  match candidate reset_work selection:
    case W.View{body,yaw,pitch,palette,region,cache} TH.ResetWork{TH.ResetStage{TH.Frame{W.View{old_body,old_yaw,old_pitch,old_palette,old_region,old_cache},old_support,old_minor,old_history,old_request,frame_tail},policy,prepared,stage_tail},move,ray,work_tail} R.AbilitySelection{flying,trigger,takeoff,jump,sneak}:
      %Equal.sym(W.State & Result<&2,&2,FR.Error,FR.Observation>,FR.clip_checked(W.attach(engine,candidate),TH.reset_ray_request(TH.reset_work_stage(reset_work),MH.outcome_transition(TH.reset_work_move(reset_work)))),(W.attach(engine,candidate),Fail{cause}),refused) : {R.status_tick_result(saved,selection,X.reset_stage_traveled(phase_work,TH.ability_reset_supplied(mode,tables,support,minor,reset_work,_))) == (R.with_error(X.State{MH.State{W.attach(engine,X.frame_view(X.work_frame(phase_work))),X.frame_support(X.work_frame(phase_work)),X.frame_minor(X.work_frame(phase_work)),H.State{X.frame_history(X.work_frame(phase_work))},[]},tables,X.frame_metadata(X.work_frame(phase_work)),[]},Some{R.error_text(X.reset_stage_error(TH.ResetSupplierError{cause}))}),saved) : X.State & I.Status}
      {==}

def Laws.admitted_tick_publishes_returned_owner_and_only_flying_status(stage,ready,facts,selection,invulnerable,mayfly,old_flying,walking_speed,flying_speed,sprinting,updates,engine,body,yaw,pitch,palette,region,cache,support,minor,history,owned,tables,metadata,tail,observation,supplied,applied):
  match selection body:
    case R.AbilitySelection{flying,trigger,takeoff,jump,sneak} M.Body{position,box,velocity,width,height,ground,horizontal,vertical,below}:
      %Equal.sym(X.ApplyStage & Result<&2,&2,X.Error,X.ApplyFacts>,X.stage_query(stage,world => support => R.status_apply_provider(I.Status{invulnerable,mayfly,old_flying,walking_speed,flying_speed},selection,sprinting,world,support)),(ready,Done{facts}),supplied) : {R.status_apply_resolved(I.Status{invulnerable,mayfly,old_flying,walking_speed,flying_speed},selection,_) == (R.with_error(X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,history,owned},tables,metadata,tail},None{}),I.Status{invulnerable,mayfly,flying && Bool.not(ground),walking_speed,flying_speed}) : X.State & I.Status}
      %Equal.sym(X.State & Result<&2,&2,X.Error,X.Observation>,X.resume_apply_with_reset_checked(ready,Done{facts},R.reset_policy()),(X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,history,owned},tables,metadata,tail},Done{observation}),applied) : {R.status_tick_result(I.Status{invulnerable,mayfly,old_flying,walking_speed,flying_speed},selection,_) == (R.with_error(X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,history,owned},tables,metadata,tail},None{}),I.Status{invulnerable,mayfly,flying && Bool.not(ground),walking_speed,flying_speed}) : X.State & I.Status}
      {==}

def Laws.status_history_dispatch_commits_resolved_movement_once(mode, engine, tables, frame, policy, prepared, candidate, returned, support, minor, move, observation, history, finished, resolved, metadata_valid, required, supplied, accumulated, completed):
  match candidate:
    case W.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>, LM.move_checked(W.attach(engine, TH.with_body(TH.frame_view(frame), TH.prepared_body(prepared))), tables, TH.frame_support(frame), TH.frame_minor(frame), TH.reset_move_request(frame, prepared)), (W.attach(engine, candidate), returned, support, minor, Done{move}), resolved) : {TH.ability_reset_moved(mode,TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Maybe<&2, H.Error>, H.movement_error(MH.movement_from(MH.outcome_transition(move), H.NotRequired{})), None{}, metadata_valid) : {TH.ability_reset_metadata_checked(mode,W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Bool, TH.reset_is_required(TH.frame_history(frame), MH.outcome_transition(move)), True{}, required) : {TH.ability_reset_requirement(mode,W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(W.State & Result<&2, &2, FR.Error, FR.Observation>, FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, MH.outcome_transition(move))), (W.attach(engine, candidate), Done{observation}), supplied) : {TH.ability_reset_supplied(mode,returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(H.State & Result<&2, &2, H.Error, Unit>, H.movement(mode, MH.movement_from(MH.outcome_transition(move), FR.observation_clip(observation)), H.State{TH.frame_history(frame)}), (H.State{history}, Done{Unit{}}), accumulated) : {TH.reset_history_finished(W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, Some{observation}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Result<&2, &2, T.Error, M.Transition>, T.finish_checked(prepared, MH.outcome_transition(move)), Done{finished}, completed) : {TH.reset_finished(W.attach(engine, candidate), returned, support, minor, H.State{history}, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, Some{observation}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      {==}

