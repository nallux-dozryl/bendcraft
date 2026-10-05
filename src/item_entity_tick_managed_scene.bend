import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_scene.bend as Scene
import ./item_entity_tick_managed.bend as Managed
import ./item_entity_tick_fields.bend as U
import ./cooking_effect_entities_model.bend as E
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as MS
import ./random.bend as R

def registered(+context:T.Context,+manager:M.View,+view:E.View,+record:E.Record,+runtime:T.Runtime,common:Bool,+located:M.Located) -> Result<&2,&2,T.Error,Managed.Plan>:
  E.View{level,unique,cursor,+order,+records}=view
  M.Located{M.Member{dimension,id,+key,old_order,box,uuid},M.Section{d,k,+status,ids}}=located
  do Result<&2,&2,T.Error,Managed.Plan>:
    _ : Unit <- U.guard(MS.ticking(status) && Nat.is_eq(MS.id_count(MS.scheduled(manager,dimension),id),1n),"item tick ID must be present in actual section ticking registry")
    Managed.plan(context,E.common(record),key,manager,order,records,Scene.snapshot_phase(record,runtime,common))
def planned(+context:T.Context,+manager:M.View,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,+id:U32,+common:Bool) -> Result<&2,&2,T.Error,Managed.Plan>:
  E.View{level,unique,cursor,order,+records}=view
  do Result<&2,&2,T.Error,Managed.Plan>:
    _ : Unit <- U.guard(U32.is_eq(Scene.count_id(records,id),1) && U32.is_eq(Scene.count_runtime(runtimes,id),1),"item tick entity/runtime ID must be unique")
    +record : E.Record <- Scene.found(records,id)
    _ : Unit <- U.guard(Bool.not(U.removed(record)),"removed item must leave tick scheduling after removal publication")
    runtime : T.Runtime <- Scene.runtime_for(runtimes,id)
    located : M.Located <- MS.locate(manager,MS.common_dimension(E.common(record)),id)
    registered(context,manager,view,record,runtime,common,located)
def accepted(scene:T.State,manager:M.State,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,+proposal:M.Proposal,result:Result<&2,&2,T.Error,Scene.Sounds>) -> T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>:
  M.Proposal{membership,order,records,journal}=proposal
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{Scene.Sounds{sound,effects}}:
      (T.State{E.install(view),runtimes,sound},M.State{membership},Done{Managed.Publication{effects,journal}})
def committed(scene:T.State,manager:M.State,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,result:Result<&2,&2,T.Error,Managed.Plan>,+sound:Maybe<&2,R.Source>) -> T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>:
  E.View{+level,+unique,+cursor,old_order,prior}=view
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{Managed.Plan{T.Plan{T.Snapshot{+record,runtime},records,+effects},+proposal}}:
      M.Proposal{membership,+order,+records,journal}=proposal
      accepted(scene,manager,E.View{level,unique,cursor,order,records},Scene.replace_runtime(runtimes,E.record_id(record),runtime),proposal,Scene.sounds(effects,sound))
def inspected(+context:T.Context,+id:U32,+common:Bool,+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,entities:E.State & E.View,sections:M.State & M.View) -> T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>:
  (owner,+view)=entities
  (manager,+membership)=sections
  committed(T.State{owner,runtimes,sound},manager,view,runtimes,planned(context,membership,view,runtimes,id,common),sound)
# Both affine owners and every RNG/cursor survive any physics/query/removal/
# sound failure. T.State remains exactly the existing persisted scene contract.
def tick_id(+context:T.Context,+id:U32,+common:Bool,scene:T.State,manager:M.State) -> T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>:
  T.State{entities,+runtimes,+sound}=scene
  inspected(context,id,common,runtimes,sound,E.inspect(entities),MS.inspect(manager))
