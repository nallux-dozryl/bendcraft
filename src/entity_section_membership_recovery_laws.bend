import Base
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./entity_section_membership_model.bend as M
import ./random.bend as Random
import ./entity_section_membership_recovery.bend as Recovery
import ./entity_section_membership_recovery_model.bend as D
import ./entity_section_membership.bend as MS
import ./entity_membership_codec_validation.bend as Check

def registered_members(view:M.View) -> List<&2,M.Member>:
  M.View{members,sections,chunks,tracked,ticked}=view
  members
def plan_members(plan:D.Plan) -> List<&2,M.Member>:
  D.Plan{entities,runtimes,membership,journal}=plan
  registered_members(membership)
def entity_order(view:E.View) -> Nat:
  E.View{level,unique,last_id,order,records}=view
  order
def constructed_entities(plan:E.Plan) -> E.View:
  E.Plan{entities,times}=plan
  entities
def plan_entities(plan:D.Plan) -> E.View:
  D.Plan{entities,runtimes,membership,journal}=plan
  entities
def fresh_order(fresh:D.Fresh) -> Nat:
  D.Fresh{plan,times}=fresh
  entity_order(plan_entities(plan))
def proposal_order(proposal:M.Proposal) -> Nat:
  M.Proposal{membership,order,records,journal}=proposal
  order
def recovery_controls(plan:D.Plan) -> Random.Source & Random.Bits64 & U32 & Nat & List<&2,T.RuntimeEntry>:
  D.Plan{E.View{level,unique,id,order,records},runtimes,membership,journal}=plan
  (level,unique,id,order,runtimes)

# Observes the actual returned affine owners; the entity owner stays in the
# returned T.State while every ordered raw record is inspected alongside it.
def activation_inspected(runtimes:List<&2,T.RuntimeEntry>,sound:Maybe<&2,Random.Source>,manager:M.State,status:Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>,result:E.State & E.View) ->
  T.State & M.State & (E.View & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>):
  (entities,view)=result
  (T.State{entities,runtimes,sound},manager,(view,status))
def inspect_activation(value:T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>) ->
  T.State & M.State & (E.View & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>):
  (T.State{entities,+runtimes,+sound},manager,status)=value
  activation_inspected(runtimes,sound,manager,status,E.inspect(entities))

law no_visibility_reconciliation_preserves_every_plan_field:
  for +plan:D.Plan
  {Recovery.reconcile([],plan) == Done{plan} : Result<&2,&2,T.Error,D.Plan>}

law unavailable_image_cannot_mint_recovered_registration:
  for entities:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for current:Maybe<&2,List<&2,M.Chunk>>
  {Recovery.prepare(None{},entities,runtimes,current) ==
    Fail{T.Refused{"membership recovery image is unavailable; decoded records cannot mint registration"}} : Result<&2,&2,T.Error,D.Plan>}

law unavailable_current_observation_refuses_arbitrary_image:
  for image:M.View
  for entities:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  {Recovery.prepare(Some{image},entities,runtimes,None{}) ==
    Fail{T.Refused{"membership recovery requires actual current loader visibility observations"}} : Result<&2,&2,T.Error,D.Plan>}

law unavailable_current_observation_refuses_empty_image:
  for entities:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  {Recovery.prepare(Some{M.View{[],[],[],[],[]}},entities,runtimes,None{}) ==
    Fail{T.Refused{"membership recovery requires actual current loader visibility observations"}} : Result<&2,&2,T.Error,D.Plan>}

law invalid_saved_insertion_chronology_preserves_both_complete_owners:
  for scene:T.State
  for manager:M.State
  for +image:M.View
  for +entities:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +current:List<&2,M.Chunk>
  for acceptance:Result<&2,&2,T.Error,Unit>
  for checked:{Recovery.checked(Check.validate(image)) == Done{Unit{}} : Result<&2,&2,T.Error,Unit>}
  for invalid:{Recovery.insertion_order_valid(registered_members(image),None{}) == False{} : Bool}
  {Recovery.commit(scene,manager,Recovery.prepare(Some{image},entities,runtimes,Some{current}),acceptance) ==
    (scene,manager,Fail{T.Refused{"membership recovery insertion list disagrees with saved insertion chronology"}}) :
    T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>}

law reconciliation_preserves_all_rng_cursors_and_runtime_fields:
  for +plan:D.Plan
  for proposal:M.Proposal
  {recovery_controls(Recovery.reconciled(plan,proposal)) == recovery_controls(plan) :
    Random.Source & Random.Bits64 & U32 & Nat & List<&2,T.RuntimeEntry>}

law actual_chunk_reconciliation_preserves_registered_key_box_and_order:
  for entities:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for prior_membership:M.View
  for journal:List<&2,M.CallbackEvent>
  for +members:List<&2,M.Member>
  for sections:List<&2,M.Section>
  for +chunks:List<&2,M.Chunk>
  for tracked:List<&2,M.Registration>
  for ticked:List<&2,M.Registration>
  for +actual:M.Chunk
  for cursor:Nat
  for +changed_sections:List<&2,M.Section>
  for records:List<&2,E.Record>
  for +events:List<&2,M.CallbackEvent>
  {plan_members(Recovery.reconciled(D.Plan{entities,runtimes,prior_membership,journal},MS.updated_chunk(M.View{members,sections,chunks,tracked,ticked},actual,cursor,M.ChunkChanged{changed_sections,records,events}))) ==
    members : List<&2,M.Member>}

law failed_recovery_plan_preserves_both_complete_owners:
  for scene:T.State
  for manager:M.State
  for error:T.Error
  for accepted:Result<&2,&2,T.Error,Unit>
  {Recovery.commit(scene,manager,Fail{error},accepted) == (scene,manager,Fail{error}) :
    T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>}

law refused_activation_preserves_both_complete_owners:
  for scene:T.State
  for manager:M.State
  for plan:D.Plan
  for error:T.Error
  {Recovery.accepted(scene,manager,plan,Fail{error}) == (scene,manager,Fail{error}) :
    T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>}

law accepted_activation_installs_complete_plan_and_retains_sound:
  for old_entities:E.State
  for old_runtimes:List<&2,T.RuntimeEntry>
  for manager:M.State
  for +entities:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +membership:M.View
  for +journal:List<&2,M.CallbackEvent>
  for +sound:Maybe<&2,Random.Source>
  {Recovery.accepted(T.State{old_entities,old_runtimes,sound},manager,D.Plan{entities,runtimes,membership,journal},Done{Unit{}}) ==
    (T.State{E.install(entities),runtimes,sound},M.State{membership},Done{journal}) :
    T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>}

law accepted_activation_preserves_every_rng_cursor_runtime_and_record:
  for old_entities:E.State
  for old_runtimes:List<&2,T.RuntimeEntry>
  for manager:M.State
  for +entities:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +membership:M.View
  for +journal:List<&2,M.CallbackEvent>
  for +sound:Maybe<&2,Random.Source>
  {inspect_activation(Recovery.accepted(T.State{old_entities,old_runtimes,sound},manager,D.Plan{entities,runtimes,membership,journal},Done{Unit{}})) ==
    (T.State{E.install(entities),runtimes,sound},M.State{membership},(entities,Done{journal})) :
    T.State & M.State & (E.View & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>)}

law failed_fresh_plan_preserves_both_complete_owners:
  for scene:T.State
  for manager:M.State
  for error:T.Error
  for accepted:Result<&2,&2,T.Error,Unit>
  {Recovery.fresh_commit(scene,manager,Fail{error},accepted) == (scene,manager,Fail{error}) :
    T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>}

law fresh_publication_refusal_preserves_both_complete_owners:
  for scene:T.State
  for manager:M.State
  for plan:D.Plan
  for times:List<&2,Random.Bits64>
  for error:T.Error
  {Recovery.fresh_commit(scene,manager,Done{D.Fresh{plan,times}},Fail{error}) == (scene,manager,Fail{error}) :
    T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>}

law accepted_fresh_activation_preserves_remaining_constructor_times:
  for old_entities:E.State
  for old_runtimes:List<&2,T.RuntimeEntry>
  for manager:M.State
  for +entities:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +membership:M.View
  for +journal:List<&2,M.CallbackEvent>
  for +sound:Maybe<&2,Random.Source>
  for +times:List<&2,Random.Bits64>
  {Recovery.fresh_commit(T.State{old_entities,old_runtimes,sound},manager,Done{D.Fresh{D.Plan{entities,runtimes,membership,journal},times}},Done{Unit{}}) ==
    (T.State{E.install(entities),runtimes,sound},M.State{membership},Done{D.FreshPublication{journal,times}}) :
    T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>}

law fresh_registration_uses_constructor_cursor_without_second_advance:
  for +base:D.Plan
  for +constructed:E.Plan
  for +record:E.Record
  for +runtime:T.Runtime
  for +proposal:M.Proposal
  for agreed:{proposal_order(proposal) == entity_order(constructed_entities(constructed)) : Nat}
  {fresh_order(Recovery.fresh_added(base,constructed,record,runtime,proposal)) ==
    entity_order(constructed_entities(constructed)) : Nat}
