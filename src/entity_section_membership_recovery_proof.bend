import Base
import ./entity_section_membership_recovery_laws.bend as Laws
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./entity_section_membership_model.bend as M
import ./random.bend as R
import ./entity_section_membership_recovery.bend as Recovery
import ./entity_section_membership_recovery_model.bend as D
import ./entity_section_membership.bend as MS
import ./item_entity_tick_fields.bend as U
import ./entity_membership_codec_validation.bend as Check

# Supporting induction for the actual sole owner installed by activation.
# This is not an alternate recovery model or a finite ordered-record fixture.
def lossless_records(+records:List<&2,E.Record>) ->
  {E.records(E.install_records(records)) == (E.install_records(records),records) : List<&1,E.Entity> & List<&2,E.Record>}:
  match records:
    case Nil{}: {==}
    case +head <> +rest:
      %lossless_records(rest) :
        {E.records_cons(head,E.records(E.install_records(rest))) == E.records_cons(head,_) : List<&1,E.Entity> & List<&2,E.Record>}
      {==}

def lossless_view(+view:E.View) -> {E.inspect(E.install(view)) == (E.install(view),view) : E.State & E.View}:
  match view:
    case E.View{+level,+seed,+id,+order,+records}:
      %lossless_records(records) :
        {E.inspected(level,seed,id,order,E.records(E.install_records(records))) == E.inspected(level,seed,id,order,_) : E.State & E.View}
      {==}

def Laws.no_visibility_reconciliation_preserves_every_plan_field(plan): {==}
def Laws.unavailable_image_cannot_mint_recovered_registration(entities,runtimes,current): {==}
def Laws.unavailable_current_observation_refuses_arbitrary_image(image,entities,runtimes): {==}
def Laws.unavailable_current_observation_refuses_empty_image(entities,runtimes): {==}
def invalid_chronology_refuses(+image:M.View,+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,+current:List<&2,M.Chunk>,
  checked:{Recovery.checked(Check.validate(image)) == Done{Unit{}} : Result<&2,&2,T.Error,Unit>},
  invalid:{Recovery.insertion_order_valid(Laws.registered_members(image),None{}) == False{} : Bool}) ->
  {Recovery.prepare(Some{image},entities,runtimes,Some{current}) == Fail{T.Refused{"membership recovery insertion list disagrees with saved insertion chronology"}} : Result<&2,&2,T.Error,D.Plan>}:
  match image entities:
    case M.View{+members,+sections,+chunks,+tracked,+ticked} E.View{+level,+unique,+cursor,+order,+records}:
      %Equal.sym(Result<&2,&2,T.Error,Unit>,Recovery.checked(Check.validate(M.View{members,sections,chunks,tracked,ticked})),Done{Unit{}},checked) :
        {Result.bind(&2,&2,T.Error,Unit,D.Plan,_,ignore =>
          Result.bind(&2,&2,T.Error,Unit,D.Plan,U.guard(Recovery.insertion_order_valid(members,None{}),"membership recovery insertion list disagrees with saved insertion chronology"),ignore =>
            Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.records_valid(records,records,runtimes,members),ignore =>
              Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.runtimes_valid(runtimes,records),ignore =>
                Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.members_valid(members,M.View{members,sections,chunks,tracked,ticked},records,order),ignore =>
                  Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.observations_valid(current,current),ignore =>
                    Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.observations_cover(chunks,current),ignore =>
                      Recovery.reconcile(current,D.Plan{E.View{level,unique,cursor,order,records},runtimes,M.View{members,sections,chunks,tracked,ticked},[]})))))))) ==
          Fail{T.Refused{"membership recovery insertion list disagrees with saved insertion chronology"}} : Result<&2,&2,T.Error,D.Plan>}
      %Equal.sym(Bool,Recovery.insertion_order_valid(members,None{}),False{},invalid) :
        {Result.bind(&2,&2,T.Error,Unit,D.Plan,U.guard(_,"membership recovery insertion list disagrees with saved insertion chronology"),ignore =>
          Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.records_valid(records,records,runtimes,members),ignore =>
            Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.runtimes_valid(runtimes,records),ignore =>
              Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.members_valid(members,M.View{members,sections,chunks,tracked,ticked},records,order),ignore =>
                Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.observations_valid(current,current),ignore =>
                  Result.bind(&2,&2,T.Error,Unit,D.Plan,Recovery.observations_cover(chunks,current),ignore =>
                    Recovery.reconcile(current,D.Plan{E.View{level,unique,cursor,order,records},runtimes,M.View{members,sections,chunks,tracked,ticked},[]}))))))) ==
          Fail{T.Refused{"membership recovery insertion list disagrees with saved insertion chronology"}} : Result<&2,&2,T.Error,D.Plan>}
      {==}
def Laws.invalid_saved_insertion_chronology_preserves_both_complete_owners(scene,manager,image,entities,runtimes,current,acceptance,checked,invalid):
  Equal.cong(Result<&2,&2,T.Error,D.Plan>,T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>,result => Recovery.commit(scene,manager,result,acceptance),
    Recovery.prepare(Some{image},entities,runtimes,Some{current}),Fail{T.Refused{"membership recovery insertion list disagrees with saved insertion chronology"}},
    invalid_chronology_refuses(image,entities,runtimes,current,checked,invalid))
def Laws.reconciliation_preserves_all_rng_cursors_and_runtime_fields(plan,proposal):
  match plan proposal:
    case D.Plan{E.View{level,unique,id,order,prior},runtimes,membership,journal} M.Proposal{next,next_order,records,events}:
      {==}

def event_retains_members(+view:M.View,event:M.CallbackEvent) ->
  {Laws.registered_members(MS.registry_event(view,event)) == Laws.registered_members(view) : List<&2,M.Member>}:
  match view:
    case M.View{members,sections,chunks,tracked,ticked}:
      match event:
        case M.TrackingStart{dimension,id}: {==}
        case M.TrackingEnd{dimension,id}: {==}
        case M.TickingStart{dimension,id}: {==}
        case M.TickingEnd{dimension,id}: {==}
        case M.SectionCreated{dimension,key,visibility}: {==}
        case M.SectionDeleted{dimension,key}: {==}
        case M.Inserted{dimension,id,key,order}: {==}
        case M.Detached{dimension,id,key}: {==}
        case M.Created{dimension,id}: {==}
        case M.SectionChange{dimension,id}: {==}
        case M.Destroyed{dimension,id}: {==}
def journal_retains_members(+events:List<&2,M.CallbackEvent>,+view:M.View) ->
  {Laws.registered_members(MS.registry_events(events,view)) == Laws.registered_members(view) : List<&2,M.Member>}:
  match events:
    case Nil{}: {==}
    case head <> rest:
      Equal.trans(List<&2,M.Member>,Laws.registered_members(MS.registry_events(rest,MS.registry_event(view,head))),Laws.registered_members(MS.registry_event(view,head)),Laws.registered_members(view),
        journal_retains_members(rest,MS.registry_event(view,head)),event_retains_members(view,head))
def Laws.actual_chunk_reconciliation_preserves_registered_key_box_and_order(entities,runtimes,prior_membership,journal,members,sections,chunks,tracked,ticked,actual,cursor,changed_sections,records,events):
  journal_retains_members(events,{M.View{members,changed_sections,actual <> MS.erase_chunk(chunks,actual),tracked,ticked} : M.View})
def Laws.failed_recovery_plan_preserves_both_complete_owners(scene,manager,error,accepted): {==}
def Laws.refused_activation_preserves_both_complete_owners(scene,manager,plan,error): {==}
def Laws.accepted_activation_installs_complete_plan_and_retains_sound(old_entities,old_runtimes,manager,entities,runtimes,membership,journal,sound): {==}
def Laws.accepted_activation_preserves_every_rng_cursor_runtime_and_record(old_entities,old_runtimes,manager,entities,runtimes,membership,journal,sound):
  %lossless_view(entities) :
    {Laws.activation_inspected(runtimes,sound,M.State{membership},Done{journal},E.inspect(E.install(entities))) ==
      Laws.activation_inspected(runtimes,sound,M.State{membership},Done{journal},_) : T.State & M.State & (E.View & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>)}
  {==}
def Laws.failed_fresh_plan_preserves_both_complete_owners(scene,manager,error,accepted): {==}
def Laws.fresh_publication_refusal_preserves_both_complete_owners(scene,manager,plan,times,error): {==}
def Laws.accepted_fresh_activation_preserves_remaining_constructor_times(old_entities,old_runtimes,manager,entities,runtimes,membership,journal,sound,times): {==}

def Laws.fresh_registration_uses_constructor_cursor_without_second_advance(base,constructed,record,runtime,proposal,agreed):
  match base constructed proposal:
    case D.Plan{entities,runtimes,membership,journal} E.Plan{E.View{level,unique,id,+order,records},times} M.Proposal{next,+next_order,stored,events}:
      agreed
