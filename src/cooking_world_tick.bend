import Base
import ./core.bend as C
import ./inventory.bend as Inv
import ./schedule.bend as Q
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as S
import ./cooking_world_items.bend as I
import ./furnace_authority.bend as F
import ./furnace_authority_fuel.bend as FF
import ./campfire_authority.bend as A
import ./campfire_authority_items.bend as AI
import ./cooking_effect_publication_journal.bend as Journal
import ./local_player_cooking_dirty_stamp.bend as DirtyStamp

type Change is Data:
  Furnace{transition:F.Transition}
  Campfire{candidate:A.Candidate}
type Plan is Data:
  Plan{position:C.Position,binding:B.Binding,change:Change,lit_operation:Maybe<&2,W.Prepared>}

def partner(+catalog:B.Catalog,+previous:B.Binding,value:B.Classification) -> Result<&2,&2,String,B.Binding>:
  match value:
    case B.Other{}: Fail{"cooking-world:lit-partner-is-not-cooking"}
    case B.Cooking{+binding}:
      do Result<&2,&2,String,B.Binding>:
        AI.guarded(B.same_block(previous,binding),"cooking-world:lit-partner-changes-block-identity")
        return binding
def world_descriptor(value:Result<&2,&2,W.Error,L.Descriptor>) -> Result<&2,&2,String,L.Descriptor>:
  match value:
    case Fail{error}: Fail{"cooking-world:missing-or-invalid-lit-partner-light-descriptor"}
    case Done{descriptor}: Done{descriptor}
def partner_result(catalog:B.Catalog,previous:B.Binding,value:Result<&2,&2,String,B.Classification>) -> Result<&2,&2,String,B.Binding>:
  match value:
    case Fail{message}: Fail{message}
    case Done{classification}: partner(catalog,previous,classification)
def furnace_plan(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,+catalog:B.Catalog,+position:C.Position,+binding:B.Binding,+transition:F.Transition) -> Result<&2,&2,String,Plan>:
  F.Transition{after,F.Effects{dirty,change,drops,completed}} = transition
  match change:
    case None{}: Done{Plan{position,binding,Furnace{transition},None{}}}
    case Some{value}:
      do Result<&2,&2,String,Plan>:
        +next : B.Binding <- partner_result(catalog,binding,B.classify(catalog,B.lit_state(binding,value)))
        descriptor : L.Descriptor <- world_descriptor(W.descriptor(~Light,~properties,~enabled,light_context,position,B.lit_state(next,value)))
        return Plan{position,next,Furnace{transition},Some{W.Block{position,descriptor}}}
def furnace_admitted(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    +light_context:Light,+context:CW.Context,+position:C.Position,+binding:B.Binding,+snapshot:F.Snapshot,
    result:Result<&2,&2,String,I.Admission>) -> Result<&2,&2,String,Plan>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  B.Binding{state,block,family,lit,dark,bright} = binding
  match result:
    case Fail{message}: Fail{message}
    case Done{I.Admission{metadata,profiles}}:
      do Result<&2,&2,String,Plan>:
        transition : F.Transition <- F.tick(recipes,fuel,FF.Context{block,depth},profiles,snapshot,metadata)
        furnace_plan(~Light,~properties,~enabled,light_context,catalog,position,binding,transition)
def plan(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,+context:CW.Context,view:S.View) -> Result<&2,&2,String,Plan>:
  S.View{+position,+binding,body,removal} = view
  match body:
    case S.FurnaceView{+snapshot}:
      furnace_admitted(~Light,~properties,~enabled,light_context,context,position,binding,snapshot,I.furnace(CW.recipes(context),snapshot))
    case S.CampfireView{kind,+lit,+cells,+cache}:
      do Result<&2,&2,String,Plan>:
        candidate : A.Candidate <- A.proposed(CW.recipes(context),lit,cells,cache,A.validate(CW.recipes(context),cells))
        return Plan{position,binding,Campfire{candidate},None{}}
def plans(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    values:List<&2,S.View>,+light_context:Light,+context:CW.Context) -> Result<&2,&2,String,List<&2,Plan>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,Plan>>:
        first : Plan <- plan(~Light,~properties,~enabled,light_context,context,head)
        tail : List<&2,Plan> <- plans(~Light,~properties,~enabled,rest,light_context,context)
        return first <> tail
def dirty(position:C.Position,value:Bool) -> List<&2,S.Effect>:
  match value:
    case False{}: []
    case True{}: [S.Dirty{position}]
def furnace_drops(values:List<&2,Inv.Slot>,+position:C.Position) -> List<&2,S.Effect>:
  match values:
    case Nil{}: []
    case item <> rest: S.Drop{position,1,item} <> furnace_drops(rest,position)
def furnace_effects(+position:C.Position,value:F.Effects) -> List<&2,S.Effect>:
  F.Effects{changed,lit,drops,completed} = value
  List.append(&2,S.Effect,furnace_drops(drops,position),dirty(position,changed))
def campfire_effects(+position:C.Position,value:A.Effects) -> List<&2,S.Effect>:
  A.Effects{drops,changed,updates,changes} = value
  List.append(&2,S.Effect,S.drops(position,drops),List.append(&2,S.Effect,dirty(position,changed),[S.BlockUpdate{position,updates},S.BlockChange{position,changes}]))
def furnace_committed(+position:C.Position,binding:B.Binding,result:F.State & Result<&2,&2,String,F.Effects>) -> S.Entry & List<&2,S.Effect>:
  (owner,effects) = result
  match effects:
    case Fail{message}: (S.Entry{position,binding,S.Furnace{owner}},[])
    case Done{value}: (S.Entry{position,binding,S.Furnace{owner}},furnace_effects(position,value))
def campfire_committed(+position:C.Position,binding:B.Binding,result:A.State & Result<&2,&2,String,A.Effects>) -> S.Entry & List<&2,S.Effect>:
  (owner,effects) = result
  match effects:
    case Fail{message}: (S.Entry{position,binding,S.Campfire{owner}},[])
    case Done{value}: (S.Entry{position,binding,S.Campfire{owner}},campfire_effects(position,value))
def commit_entry(entry:S.Entry,plan:Plan) -> S.Entry & List<&2,S.Effect>:
  match entry plan:
    case S.Entry{position,old,S.Furnace{owner}} Plan{p,binding,Furnace{transition},operation}:
      furnace_committed(position,binding,F.commit(owner,Done{transition}))
    case S.Entry{position,old,S.Campfire{owner}} Plan{p,binding,Campfire{candidate},operation}:
      campfire_committed(position,binding,A.committed(owner,Done{candidate}))
    case entry plan: (entry,[])
def commit_cons(head:S.Entry & List<&2,S.Effect>,tail:List<&1,S.Entry> & List<&2,S.Effect>) -> List<&1,S.Entry> & List<&2,S.Effect>:
  (entry,effects) = head
  (rest,more) = tail
  (entry <> rest,List.append(&2,S.Effect,effects,more))
def commit_entries(entries:List<&1,S.Entry>,plans:List<&2,Plan>) -> List<&1,S.Entry> & List<&2,S.Effect>:
  match entries plans:
    case Nil{} _: ([],[])
    case head <> rest plan <> tail: commit_cons(commit_entry(head,plan),commit_entries(rest,tail))
    case entries Nil{}: (entries,[])
def lit_done(rest:List<&2,Plan>,world:W.State,status:Result<&2,&2,W.Error,Unit>,
    next:W.State -> W.State & Result<&2,&2,CW.Error,Unit>) -> W.State & Result<&2,&2,CW.Error,Unit>:
  match status:
    case Fail{error}: (world,Fail{CW.World{error}})
    case Done{unit}: next(world)
def lit_applied(+rest:List<&2,Plan>,result:W.State & Result<&2,&2,W.Error,Unit>,
    next:W.State -> W.State & Result<&2,&2,CW.Error,Unit>) -> W.State & Result<&2,&2,CW.Error,Unit>:
  (world,status) = result
  lit_done(rest,world,status,next)
def lit_write(+operation:W.Prepared,world:W.State) -> W.State & Result<&2,&2,W.Error,Unit>:
  W.State{C.World{+tick,time,paused,daylight,+revision,count,sections,pending,events},light,loading} = world
  W.apply_finished(Q.Stamp{tick,0,1n+revision},W.apply_prepared(W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},operation))
def write_lit(values:List<&2,Plan>,world:W.State) -> W.State & Result<&2,&2,CW.Error,Unit>:
  match values:
    case Nil{}: (world,Done{Unit{}})
    case Plan{position,binding,change,None{}} <> rest: write_lit(rest,world)
    case Plan{position,binding,change,Some{operation}} <> +rest:
      lit_applied(rest,lit_write(operation,world),world => write_lit(rest,world))
def finish_entries(world:W.State,effects:List<&2,S.Effect>,result:List<&1,S.Entry> & List<&2,S.Effect>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,more) = result
  (CW.State{world,entries,CW.Idle{},[]},Done{List.append(&2,S.Effect,effects,more)})
def finish_written(entries:List<&1,S.Entry>,tick:Nat,effects:List<&2,S.Effect>,+values:List<&2,Plan>,
    result:W.State & Result<&2,&2,CW.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{world,entries,CW.Cooking{tick,effects},[]},Fail{error})
    case Done{unit}: finish_entries(world,effects,commit_entries(entries,values))
def finish_planned(state:CW.State,result:Result<&2,&2,String,List<&2,Plan>>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match state result:
    case state Fail{message}: (state,Fail{CW.Authority{message}})
    case CW.State{world,entries,CW.Cooking{tick,effects},keys} Done{+values}:
      finish_written(entries,tick,effects,values,write_lit(values,world))
    case state Done{values}: (state,Fail{CW.Busy{}})
def finish_resident(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,entries:List<&1,S.Entry>,phase:CW.Phase,+views:List<&2,S.View>,
    result:W.State & Result<&2,&2,CW.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{world,entries,phase,[]},Fail{error})
    case Done{unit}: finish_planned(CW.State{world,entries,phase,[]},plans(~Light,~properties,~enabled,views,light_context,context))
def finish_inspected(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,world:W.State,phase:CW.Phase,
    result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,status) = result
  match status:
    case Fail{message}: (CW.State{world,entries,phase,[]},Fail{CW.Authority{message}})
    case Done{+views}: finish_resident(~Light,~properties,~enabled,light_context,context,entries,phase,views,CW.resident(views,world))
def finish_with_context(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,world:W.State,entries:List<&1,S.Entry>,phase:CW.Phase,campfire:AI.Context) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  AI.Context{recipes,defaults,features} = campfire
  finish_inspected(~Light,~properties,~enabled,light_context,context,world,phase,S.inspect(recipes,entries))
# All item/default/fuel/recipe, residency and light-partner checks happen before
# committing any owner. The pending phase survives refusal and cannot replay a
# completed cooking tick. In-range loaded-section writes cannot remove another
# section; an internal commit failure remains an explicit invariant defect.
def finish_tick(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,+context:CW.Context,state:CW.State) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match state:
    case CW.State{world,entries,CW.Idle{},keys}: (CW.State{world,entries,CW.Idle{},keys},Done{[]})
    case CW.State{world,entries,phase,key <> rest}: (CW.State{world,entries,phase,key <> rest},Fail{CW.Loading{}})
    case CW.State{world,entries,phase,Nil{}}:
      finish_with_context(~Light,~properties,~enabled,light_context,context,world,entries,phase,CW.recipes(context))

# Owned publication is additive. Legacy finish_tick and its callers retain the
# original position-only Dirty stream. The pending phase effects are passed
# verbatim; only effects produced by the commits below receive a cached source.
def owned_plan_aligned(+source:Journal.Source,value:Plan) -> Bool:
  Journal.Source{position,+previous,incarnation} = source
  Plan{candidate,binding,change,operation} = value
  B.equal_position(position,candidate) && B.same_block(previous,binding)

def owned_plans_aligned(values:List<&2,Plan>,sources:List<&2,Journal.Source>) -> Bool:
  match values sources:
    case Nil{} Nil{}: True{}
    case value <> rest source <> tail:
      owned_plan_aligned(source,value) && owned_plans_aligned(rest,tail)
    case _ _: False{}

def commit_entries_owned(entries:List<&1,S.Entry>,values:List<&2,Plan>,sources:List<&2,Journal.Source>) ->
    List<&1,S.Entry> & List<&2,S.Effect>:
  match entries values sources:
    case Nil{} _ _: ([],[])
    case head <> rest value <> tail source <> more:
      commit_cons(DirtyStamp.committed(source,commit_entry(head,value)),
        commit_entries_owned(rest,tail,more))
    case entries _ _: (entries,[])

def finish_entries_owned(world:W.State,effects:List<&2,S.Effect>,
    result:List<&1,S.Entry> & List<&2,S.Effect>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,more) = result
  (CW.State{world,entries,CW.Idle{},[]},Done{List.append(&2,S.Effect,effects,more)})

def finish_written_owned(entries:List<&1,S.Entry>,tick:Nat,effects:List<&2,S.Effect>,
    +values:List<&2,Plan>,sources:List<&2,Journal.Source>,
    result:W.State & Result<&2,&2,CW.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{world,entries,CW.Cooking{tick,effects},[]},Fail{error})
    case Done{unit}: finish_entries_owned(world,effects,commit_entries_owned(entries,values,sources))

def finish_aligned_owned(entries:List<&1,S.Entry>,tick:Nat,effects:List<&2,S.Effect>,
    +values:List<&2,Plan>,sources:List<&2,Journal.Source>,world:W.State,aligned:Bool) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match aligned:
    case False{}:
      (CW.State{world,entries,CW.Cooking{tick,effects},[]},
        Fail{CW.Authority{"cooking-dirty-stamp:source-plan-alignment"}})
    case True{}: finish_written_owned(entries,tick,effects,values,sources,write_lit(values,world))

def finish_planned_owned(state:CW.State,cache:DirtyStamp.Cache,
    result:Result<&2,&2,String,List<&2,Plan>>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match state cache result:
    case state _ Fail{message}: (state,Fail{CW.Authority{message}})
    case CW.State{world,entries,CW.Cooking{tick,effects},keys} DirtyStamp.Cache{+sources} Done{+values}:
      finish_aligned_owned(entries,tick,effects,values,sources,world,owned_plans_aligned(values,sources))
    case state _ Done{values}: (state,Fail{CW.Busy{}})

def finish_resident_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,entries:List<&1,S.Entry>,phase:CW.Phase,+views:List<&2,S.View>,
    cache:DirtyStamp.Cache,result:W.State & Result<&2,&2,CW.Error,Unit>) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{world,entries,phase,[]},Fail{error})
    case Done{unit}:
      finish_planned_owned(CW.State{world,entries,phase,[]},cache,
        plans(~Light,~properties,~enabled,views,light_context,context))

def finish_inspected_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,world:W.State,phase:CW.Phase,cache:DirtyStamp.Cache,
    result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,status) = result
  match status:
    case Fail{message}: (CW.State{world,entries,phase,[]},Fail{CW.Authority{message}})
    case Done{+views}:
      finish_resident_owned(~Light,~properties,~enabled,light_context,context,entries,phase,views,cache,CW.resident(views,world))

def finish_with_context_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,world:W.State,entries:List<&1,S.Entry>,phase:CW.Phase,
    cache:DirtyStamp.Cache,campfire:AI.Context) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  AI.Context{recipes,defaults,features} = campfire
  finish_inspected_owned(~Light,~properties,~enabled,light_context,context,world,phase,cache,S.inspect(recipes,entries))

def finish_captured_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,+context:CW.Context,world:W.State,phase:CW.Phase,keys:List<&2,String>,
    result:List<&1,S.Entry> & Result<&2,&2,String,DirtyStamp.Cache>) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,status) = result
  match status:
    case Fail{message}: (CW.State{world,entries,phase,keys},Fail{CW.Authority{message}})
    case Done{cache}:
      finish_with_context_owned(~Light,~properties,~enabled,light_context,context,world,entries,phase,cache,CW.recipes(context))

# The supplied map is the actual Sidecar incarnation map AFTER acknowledgement
# of the accepted start_tick's pending OwnerReset markers. No Core step occurs
# here beyond the existing finish writes. Sources are captured and validated
# before any write, with complete pre-lit bindings and unique positions.
def owned_catalog(context:CW.Context) -> B.Catalog:
  CW.Context{catalog,campfire,fuel,depth} = context
  catalog

def finish_tick_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,+context:CW.Context,incarnations:Map<&2,Nat>,state:CW.State) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match state:
    case CW.State{world,entries,CW.Idle{},keys}: (CW.State{world,entries,CW.Idle{},keys},Done{[]})
    case CW.State{world,entries,phase,key <> rest}: (CW.State{world,entries,phase,key <> rest},Fail{CW.Loading{}})
    case CW.State{world,entries,phase,Nil{}}:
      finish_captured_owned(~Light,~properties,~enabled,light_context,context,world,phase,[],
        DirtyStamp.capture(owned_catalog(context),incarnations,entries))
