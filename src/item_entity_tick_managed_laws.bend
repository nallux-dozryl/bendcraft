import Base
import ./item_entity_tick_managed_scene.bend as Scene
import ./item_entity_tick_managed.bend as Managed
import ./item_entity_tick.bend as Tick
import ./item_entity_tick_model.bend as T
import ./cooking_effect_entities_model.bend as E
import ./entity_section_membership_model.bend as M
import ./random.bend as R
import ./item_entity_tick_scene.bend as Sounds

law refused_managed_plan_preserves_both_complete_affine_owners:
  for scene:T.State
  for manager:M.State
  for view:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for error:T.Error
  for sound:Maybe<&2,R.Source>
  {Scene.committed(scene,manager,view,runtimes,Fail{error},sound) == (scene,manager,Fail{error}) : T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>}
def refused_managed_plan_preserves_both_complete_affine_owners(scene,manager,view,runtimes,error,sound):
  match view:
    case E.View{level,unique,cursor,order,records}: {==}
law sound_refusal_rolls_back_membership_records_runtime_and_all_rng:
  for scene:T.State
  for manager:M.State
  for view:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for proposal:M.Proposal
  for error:T.Error
  {Scene.accepted(scene,manager,view,runtimes,proposal,Fail{error}) == (scene,manager,Fail{error}) : T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>}
def sound_refusal_rolls_back_membership_records_runtime_and_all_rng(scene,manager,view,runtimes,proposal,error):
  match proposal:
    case M.Proposal{membership,order,records,journal}: {==}
law accepted_scene_installs_the_manager_and_sound_in_one_transition:
  for scene:T.State
  for manager:M.State
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +membership:M.View
  for order:Nat
  for records:List<&2,E.Record>
  for +journal:List<&2,M.CallbackEvent>
  for +sound:Maybe<&2,R.Source>
  for +effects:List<&2,T.Publication>
  {Scene.accepted(scene,manager,view,runtimes,M.Proposal{membership,order,records,journal},Done{Sounds.Sounds{sound,effects}}) ==
    (T.State{E.install(view),runtimes,sound},M.State{membership},Done{Managed.Publication{effects,journal}}) : T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>}
def accepted_scene_installs_the_manager_and_sound_in_one_transition(scene,manager,view,runtimes,membership,order,records,journal,sound,effects): {==}
law settled_empty_preparation_retains_the_actual_discard_plan:
  for +plan:T.Plan
  {Tick.settled_plan(plan) == Done{plan} : Result<&2,&2,T.Error,T.Plan>}
def settled_empty_preparation_retains_the_actual_discard_plan(plan): {==}
law removal_dedup_preserves_the_already_staged_manager_and_journal:
  for +stage:Managed.Stage
  for id:U32
  {Managed.removal_gate(stage,id,True{}) == Done{stage} : Result<&2,&2,T.Error,Managed.Stage>}
def removal_dedup_preserves_the_already_staged_manager_and_journal(stage,id): {==}
