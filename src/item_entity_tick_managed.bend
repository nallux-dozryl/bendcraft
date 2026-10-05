import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick.bend as Tick
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_merge.bend as Merge
import ./cooking_effect_entities_model.bend as E
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as MS
import ./vanilla_entity_fields.bend as V
import ./campfire_authority_items.bend as CI
import ./inventory.bend as I

type Publication is Data:
  Publication{effects:List<&2,T.Publication>,callbacks:List<&2,M.CallbackEvent>}
type Plan is Data:
  Plan{tick:T.Plan,section:M.Proposal}
type Stage is Data:
  Stage{section:M.Proposal,removed:List<&2,U32>}
type Loop is Data:
  Loop{record:E.Record,stage:Stage,effects:List<&2,T.Publication>}
type Frame is Data:
  Frame{context:T.Context,record:E.Record,stage:Stage,effects:List<&2,T.Publication>,ids:List<&2,U32>,budget:Nat,tail:List<&2,Frame>}

def records(stage:Stage) -> List<&2,E.Record>:
  Stage{M.Proposal{view,order,records,journal},removed}=stage
  records
def view(stage:Stage) -> M.View:
  Stage{M.Proposal{view,order,records,journal},removed}=stage
  view
def staged_records(stage:Stage,records:List<&2,E.Record>) -> Stage:
  Stage{M.Proposal{view,order,prior,journal},removed}=stage
  Stage{M.Proposal{view,order,records,journal},removed}
def appended_removal(+prior:Stage,proposal:M.Proposal,id:U32) -> Stage:
  Stage{M.Proposal{old,old_order,old_records,journal},removed}=prior
  M.Proposal{view,order,records,events}=proposal
  Stage{M.Proposal{view,order,records,List.append(&2,M.CallbackEvent,journal,events)},id <> removed}
def removed_one(+stage:Stage,+id:U32) -> Result<&2,&2,T.Error,Stage>:
  Stage{M.Proposal{+view,+order,+records,+journal},removed}=stage
  do Result<&2,&2,T.Error,Stage>:
    +record : E.Record <- Merge.lookup(records,id)
    _ : Unit <- U.guard(U.removed(record),"manager removal requires actual discarded item record")
    proposal : M.Proposal <- MS.on_removed(view,MS.common_dimension(E.common(record)),id,True{},order,records)
    return appended_removal(stage,proposal,id)
def removal_gate(+stage:Stage,+id:U32,already:Bool) -> Result<&2,&2,T.Error,Stage>:
  match already:
    case True{}: Done{stage}
    case False{}: removed_one(stage,id)
def removal(+stage:Stage,+id:U32) -> Result<&2,&2,T.Error,Stage>:
  Stage{proposal,+removed}=stage
  removal_gate(stage,id,Merge.used(removed,id))
def removals(events:List<&2,T.Publication>,+stage:Stage) -> Result<&2,&2,T.Error,Stage>:
  match events:
    case Nil{}: Done{stage}
    case T.Removed{+id} <> rest:
      do Result<&2,&2,T.Error,Stage>:
        stage : Stage <- removal(stage,id)
        removals(rest,stage)
    case head <> rest: removals(rest,stage)
def unique_ids(ids:List<&2,U32>) -> Bool:
  match ids:
    case Nil{}: True{}
    case +id <> +rest: Bool.not(Merge.used(rest,id)) && unique_ids(rest)
def loop_pair(+stage:Stage,effects:List<&2,T.Publication>,pair:Merge.MergePair,continue:E.Record -> Stage -> List<&2,T.Publication> -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  Merge.MergePair{+source,+other,+events}=pair
  +updated : Stage = staged_records(stage,Merge.replace(Merge.replace(records(stage),other),source))
  do Result<&2,&2,T.Error,Loop>:
    stage : Stage <- removals(events,updated)
    continue(source,stage,List.append(&2,T.Publication,effects,events))
def loop_other(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,+other:E.Record,allowed:Bool,continue:E.Record -> Stage -> List<&2,T.Publication> -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  match allowed:
    case False{}: continue(record,stage,effects)
    case True{}:
      do Result<&2,&2,T.Error,Loop>:
        pair : Merge.MergePair <- Merge.private_pair(Tick.items(context),record,other)
        loop_pair(stage,effects,pair,continue)
def loop_head(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,id:U32,continue:E.Record -> Stage -> List<&2,T.Publication> -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  do Result<&2,&2,T.Error,Loop>:
    +other : E.Record <- Merge.lookup(records(stage),id)
    +meta : I.ItemMetadata <- Merge.metadata_for(Tick.items(context),other)
    loop_other(context,record,stage,effects,other,Merge.eligible(meta,other),continue)
def loop_done(frame:Frame) -> Result<&2,&2,T.Error,Loop>:
  Frame{context,record,stage,effects,ids,budget,tail}=frame
  Done{Loop{record,stage,effects}}
def loop_zero_gate(frame:Frame,finished:Bool) -> Result<&2,&2,T.Error,Loop>:
  match finished:
    case True{}: loop_done(frame)
    case False{}: Fail{T.Refused{"item managed merge query budget exhausted"}}
def loop_zero(+frame:Frame) -> Result<&2,&2,T.Error,Loop>:
  Frame{context,+record,stage,effects,+ids,budget,tail}=frame
  loop_zero_gate(frame,U.removed(record) || List.is_empty(&2,U32,ids))
def loop_from_frame(+frame:Frame,id:U32,ids:List<&2,U32>,+next:Nat,continue:Frame -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  Frame{+context,record,stage,effects,prior,budget,tail}=frame
  loop_head(context,record,stage,effects,id,r => stage => events => continue(Frame{context,r,stage,events,ids,next,[]}))
def loop_ids(ids:List<&2,U32>,frame:Frame,next:Nat,continue:Frame -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  match ids:
    case Nil{}: loop_done(frame)
    case id <> rest: loop_from_frame(frame,id,rest,next,continue)
def loop_positive_gate(+frame:Frame,next:Nat,dead:Bool,continue:Frame -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  Frame{context,record,stage,effects,ids,budget,tail}=frame
  match dead:
    case True{}: loop_done(frame)
    case False{}: loop_ids(ids,frame,next,continue)
def loop_positive(+frame:Frame,next:Nat,continue:Frame -> Result<&2,&2,T.Error,Loop>) -> Result<&2,&2,T.Error,Loop>:
  Frame{context,+record,stage,effects,ids,budget,tail}=frame
  loop_positive_gate(frame,next,U.removed(record),continue)
def loop_framed(left:Nat,+frame:Frame) -> Result<&2,&2,T.Error,Loop>:
  match left:
    case 0n: loop_zero(frame)
    case 1n+ +rest: loop_positive(frame,rest,next => loop_framed(rest,next))
def selected(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,+budget:Nat,raw:List<&2,E.Record>) -> Result<&2,&2,T.Error,Loop>:
  do Result<&2,&2,T.Error,Loop>:
    +ids : List<&2,U32> <- Merge.ordered_ids(raw,Tick.items(context),E.record_id(record))
    _ : Unit <- U.guard(unique_ids(ids),"actual managed item query must contain unique IDs")
    loop_framed(budget,Frame{context,record,stage,effects,ids,budget,[]})
def queried(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,budget:Nat) -> Result<&2,&2,T.Error,Loop>:
  do Result<&2,&2,T.Error,Loop>:
    candidates : List<&2,E.Record> <- MS.query(view(stage),MS.common_dimension(E.common(record)),Merge.inflate(U.body(record)),records(stage))
    selected(context,record,stage,effects,budget,candidates)
def merge_gate(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,budget:Nat,eligible:Bool) -> Result<&2,&2,T.Error,Loop>:
  match eligible:
    case False{}: Done{Loop{record,stage,effects}}
    case True{}: queried(context,record,stage,effects,budget)
def merge_due(+context:T.Context,+record:E.Record,+stage:Stage,effects:List<&2,T.Publication>,budget:Nat,due:Bool) -> Result<&2,&2,T.Error,Loop>:
  match due:
    case False{}: Done{Loop{record,stage,effects}}
    case True{}:
      do Result<&2,&2,T.Error,Loop>:
        +meta : I.ItemMetadata <- Merge.metadata_for(Tick.items(context),record)
        merge_gate(context,record,stage,effects,budget,Merge.eligible(meta,record))
def finish_stage(plan:T.Plan,stage:Stage) -> Plan:
  Stage{section,removed}=stage
  Plan{plan,section}
def final_plan(+stage:Stage,+plan:T.Plan) -> Result<&2,&2,T.Error,Plan>:
  T.Plan{snapshot,+records,+events}=plan
  do Result<&2,&2,T.Error,Plan>:
    stage : Stage <- removals(events,staged_records(stage,records))
    return finish_stage(plan,stage)
def finished(+context:T.Context,+runtime:T.Runtime,+old:V.Vec3,value:Loop) -> Result<&2,&2,T.Error,Plan>:
  Loop{+record,+stage,effects}=value
  do Result<&2,&2,T.Error,Plan>:
    plan : T.Plan <- Tick.merged(context,runtime,effects,old,Merge.Neighbours{record,records(stage),[]})
    final_plan(stage,plan)
def after_manager(+context:T.Context,effects:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,moved:M.Moved) -> Result<&2,&2,T.Error,Plan>:
  T.Context{items,g,cells,coverage,min,server,fast,loaded,complete,rain,portal,mount,+budget,clip,tail}=context
  M.Moved{T.Snapshot{+record,runtime},proposal}=moved
  do Result<&2,&2,T.Error,Plan>:
    loop : Loop <- merge_due(context,record,Stage{proposal,[]},effects,budget,server && Tick.merge_due(old_position,U.pos(record),U.tick_count(record)))
    finished(context,runtime,old_velocity,loop)
def moved_gate(+context:T.Context,+original:E.Common,+registered:M.SectionKey,+view:M.View,+order:Nat,+records:List<&2,E.Record>,+snapshot:T.Snapshot,effects:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,removed:Bool) -> Result<&2,&2,T.Error,Plan>:
  match removed:
    case True{}:
      after_manager(context,effects,old_position,old_velocity,M.Moved{snapshot,M.Proposal{view,order,Merge.replace(records,Tick.record(snapshot)),[]}})
    case False{}:
      do Result<&2,&2,T.Error,Plan>:
        moved : M.Moved <- MS.on_move(view,original,registered,snapshot,U.body(Tick.record(snapshot)),order,records)
        after_manager(context,effects,old_position,old_velocity,moved)
def prepared(+context:T.Context,+original:E.Common,+registered:M.SectionKey,+view:M.View,+order:Nat,+records:List<&2,E.Record>,value:T.Prepared) -> Result<&2,&2,T.Error,Plan>:
  match value:
    case T.Settled{+plan}: final_plan(Stage{M.Proposal{view,order,records,[]},[]},plan)
    case T.Physics{+snapshot,effects,+old_position,+old_velocity}:
      moved_gate(context,original,registered,view,order,records,snapshot,effects,old_position,old_velocity,U.removed(Tick.record(snapshot)))
def plan(+context:T.Context,+original:E.Common,+registered:M.SectionKey,+view:M.View,+order:Nat,+records:List<&2,E.Record>,snapshot:T.Snapshot) -> Result<&2,&2,T.Error,Plan>:
  do Result<&2,&2,T.Error,Plan>:
    preparation : T.Prepared <- Tick.prepare(context,snapshot,records)
    prepared(context,original,registered,view,order,records,preparation)
