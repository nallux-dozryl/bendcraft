import Base
import ./core.bend as C
import ./section_map.bend as M
import ./schedule.bend as Q
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as S
import ./campfire_authority_items.bend as AI
import ./furnace_authority_fuel.bend as FF
import ./player_core_edit.bend as PE
import ./local_player_cooking_incarnation_guard.bend as Incarnation

type Context is Data:
  Context{bindings:B.Catalog,campfire:AI.Context,fuel:FF.Catalog,max_provider_depth:Nat}
type Phase is Data:
  Idle{}
  Cooking{tick:Nat,effects:List<&2,S.Effect>}
type State is Type:
  State{world:W.State,entities:List<&1,S.Entry>,phase:Phase,loading:List<&2,String>}
type Error is Data:
  Busy{}
  Loading{}
  Authority{message:String}
  World{error:W.Error}
  Player{error:PE.Error}
  EntityMismatch{position:C.Position}
type Operation is Data:
  Operation{due:W.Due,classification:Maybe<&2,B.Classification>}
type Seed is Data:
  Seed{position:C.Position,binding:B.Binding}

def recipes(context:Context) -> AI.Context:
  Context{bindings,campfire,fuel,depth} = context
  campfire
def message(result:Result<&2,&2,String,Unit>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Fail{text}: Fail{Authority{text}}
    case Done{unit}: Done{Unit{}}
def begun(world:W.State,result:M.Sections & List<&2,String>) -> State:
  W.State{owner,light,loading} = world
  (sections,keys) = result
  State{W.State{C.replace_sections(owner,sections),light,loading},[],Idle{},keys}
# Existing saved sections are discovered from the actual sole Core owner.
def begin(world:W.State) -> State:
  W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading} = world
  begun(W.State{C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},light,loading},W.section_keys(sections))
def seed_cell(position:C.Position,value:B.Classification,rest:List<&2,Seed>) -> List<&2,Seed>:
  match value:
    case B.Other{}: rest
    case B.Cooking{binding}: Seed{position,binding} <> rest
def seed_cells(values:List<&2,U32>,+catalog:B.Catalog,+origin:C.Position,+index:U32) -> Result<&2,&2,String,List<&2,Seed>>:
  match values:
    case Nil{}: Done{[]}
    case id <> tail:
      do Result<&2,&2,String,List<&2,Seed>>:
        value : B.Classification <- B.classify(catalog,id)
        rest : List<&2,Seed> <- seed_cells(tail,catalog,origin,U32.add(index,1))
        return seed_cell(W.indexed(origin,index),value,rest)
def seeded(values:List<&2,Seed>,entries:List<&1,S.Entry>) -> List<&1,S.Entry>:
  match values:
    case Nil{}: entries
    case Seed{position,+binding} <> rest: S.Entry{position,binding,S.fresh(binding)} <> seeded(rest,entries)
def seed_commit(world:W.State,entries:List<&1,S.Entry>,phase:Phase,+keys:List<&2,String>,
    result:Result<&2,&2,String,List<&2,Seed>>) -> State & Result<&2,&2,Error,Unit>:
  match keys result:
    case _ Fail{text}: (State{world,entries,phase,keys},Fail{Authority{text}})
    case Nil{} Done{values}: (State{world,entries,phase,[]},Done{Unit{}})
    case key <> rest Done{values}: (State{world,seeded(values,entries),phase,rest},Done{Unit{}})
def seed_snapshot(+catalog:B.Catalog,+origin:C.Position,light:L.State,light_loading:Maybe<&2,W.Cursor>,
    entries:List<&1,S.Entry>,phase:Phase,keys:List<&2,String>,result:C.World & Maybe<&2,List<&2,U32>>) -> State & Result<&2,&2,Error,Unit>:
  (world,values) = result
  match values:
    case None{}: (State{W.State{world,light,light_loading},entries,phase,keys},Fail{EntityMismatch{origin}})
    case Some{cells}: seed_commit(W.State{world,light,light_loading},entries,phase,keys,seed_cells(cells,catalog,origin,0))
def seed_origin(+catalog:B.Catalog,state:State,+key:String,result:Result<&2,&2,W.Error,C.Position>) -> State & Result<&2,&2,Error,Unit>:
  State{W.State{world,light,light_loading},entries,phase,keys} = state
  match result:
    case Fail{error}: (State{W.State{world,light,light_loading},entries,phase,keys},Fail{World{error}})
    case Done{origin}: seed_snapshot(catalog,origin,light,light_loading,entries,phase,keys,W.snapshot(world,key))
# One complete section per call: a missing binding retains the exact section,
# entity store and cursor, while previously completed calls remain committed.
def load_next(context:Context,state:State) -> State & Result<&2,&2,Error,Unit>:
  Context{catalog,campfire,fuel,depth} = context
  match state:
    case State{world,entries,phase,Nil{}}: (State{world,entries,phase,[]},Done{Unit{}})
    case State{world,entries,phase,+key <> +rest}:
      seed_origin(catalog,State{world,entries,phase,key <> rest},key,W.key_origin(key))
def resident_back(+views:List<&2,S.View>,light:L.State,loading:Maybe<&2,W.Cursor>,
    read:C.World & Result<&2,&2,C.Error,U32>,+position:C.Position,state:U32,
    next:W.State -> W.State & Result<&2,&2,Error,Unit>) -> W.State & Result<&2,&2,Error,Unit>:
  (world,value) = read
  match value:
    case Fail{error}: (W.State{world,light,loading},Fail{World{W.CoreFailure{error}}})
    case Done{actual}:
      Bool.pick(W.State -> W.State & Result<&2,&2,Error,Unit>,U32.is_eq(actual,state),next,
        world => (world,Fail{EntityMismatch{position}}))(W.State{world,light,loading})
def resident(views:List<&2,S.View>,world:W.State) -> W.State & Result<&2,&2,Error,Unit>:
  match views:
    case Nil{}: (world,Done{Unit{}})
    case S.View{+position,B.Binding{state,block,family,lit,dark,bright},body,removal} <> +rest:
      W.State{owner,light,loading} = world
      resident_back(rest,light,loading,C.read_block(owner,position),position,state,
        world => resident(rest,world))
def operations(values:List<&2,W.Due>,+catalog:B.Catalog) -> Result<&2,&2,String,List<&2,Operation>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> rest:
      W.Due{stamp,+operation} = head
      match operation:
        case W.Plain{mutation}:
          Result.map(&2,&2,String,List<&2,Operation>,List<&2,Operation>,tail => Operation{head,None{}} <> tail,operations(rest,catalog))
        case W.Block{position,L.Descriptor{id,emission,dampening}}:
          do Result<&2,&2,String,List<&2,Operation>>:
            classification : B.Classification <- B.classify(catalog,id)
            tail : List<&2,Operation> <- operations(rest,catalog)
            return Operation{head,Some{classification}} <> tail
        case W.Fill{position,L.Descriptor{id,emission,dampening}}:
          do Result<&2,&2,String,List<&2,Operation>>:
            classification : B.Classification <- B.classify(catalog,id)
            tail : List<&2,Operation> <- operations(rest,catalog)
            return Operation{head,Some{classification}} <> tail
def fill_entries(left:Nat,+origin:C.Position,+binding:B.Binding,+index:U32,entries:List<&1,S.Entry>) -> List<&1,S.Entry>:
  match left:
    case 0n: entries
    case 1n+rest: S.Entry{W.indexed(origin,index),binding,S.fresh(binding)} <> fill_entries(rest,origin,binding,U32.add(index,1),entries)
def fill_classification(position:C.Position,value:B.Classification,entries:List<&1,S.Entry>) -> List<&1,S.Entry>:
  match value:
    case B.Other{}: entries
    case B.Cooking{binding}: fill_entries(4096n,W.origin(position),binding,0,entries)
def lifecycle(operation:W.Prepared,classification:Maybe<&2,B.Classification>,entries:List<&1,S.Entry>,views:List<&2,S.View>) -> List<&1,S.Entry> & List<&2,S.Effect>:
  match operation classification:
    case W.Block{position,descriptor} Some{value}: S.change(position,value,entries,views)
    case W.Fill{position,descriptor} Some{value}: (fill_classification(position,value,entries),[])
    case _ _: (entries,[])
def lifecycle_done(world:C.World,light:L.State,effects:List<&2,S.Effect>,
    result:List<&1,S.Entry> & List<&2,S.Effect>) -> State:
  (next,more) = result
  State{W.State{world,light,None{}},next,Cooking{0n,List.append(&2,S.Effect,effects,more)},[]}
def due_views(operation:W.Prepared,value:Maybe<&2,B.Classification>,views:List<&2,S.View>) -> List<&2,S.View>:
  match operation value:
    case W.Block{position,descriptor} Some{classification}: S.changed_views(position,classification,views)
    case _ _: views
def due_next(result:State & List<&2,S.View>,next:List<&2,S.View> -> State -> State) -> State:
  (state,views) = result
  next(views,state)
def due_applied(+operation:W.Prepared,+classification:Maybe<&2,B.Classification>,+stamp:Q.Stamp,
    light:L.State,entries:List<&1,S.Entry>,effects:List<&2,S.Effect>,+views:List<&2,S.View>,
    result:C.World & Result<&2,&2,C.Error,Unit>) -> State & List<&2,S.View>:
  (world,+status) = result
  match status:
    case Fail{error}: (State{W.State{C.finish(world,stamp,status),light,None{}},entries,Cooking{0n,effects},[]},views)
    case Done{unit}:
      (lifecycle_done(C.finish(world,stamp,status),W.changed_light(operation,light),effects,lifecycle(operation,classification,entries,views)),due_views(operation,classification,views))
def due(values:List<&2,Operation>,+views:List<&2,S.View>,state:State) -> State:
  match values state:
    case Nil{} State{world,entries,phase,loading}: State{world,entries,phase,loading}
    case Operation{W.Due{stamp,+operation},classification} <> rest State{W.State{world,light,loading},entries,Cooking{tick,effects},keys}:
      due_next(due_applied(operation,classification,stamp,light,entries,effects,views,C.apply(world,W.prepared_mutation(operation))),
        views => state => due(rest,views,state))
    case _ state: state
def mark_tick(state:State) -> State:
  match state:
    case State{W.State{C.World{+tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,Cooking{old,effects},keys}:
      State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,Cooking{tick,effects},keys}
    case state: state
def started(+views:List<&2,S.View>,state:State,future:List<&2,Q.Pending<C.Mutation>>,
    result:Result<&2,&2,String,List<&2,Operation>>) -> State & Result<&2,&2,Error,Unit>:
  State{W.State{C.World{+tick,time,paused,+daylight,revision,count,sections,pending,events},light,loading},entries,phase,keys} = state
  match result:
    case Fail{text}: (State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,phase,keys},Fail{Authority{text}})
    case Done{ops}:
      (mark_tick(due(ops,views,State{W.State{C.World{1n+tick,C.daylight_tick(time,daylight),paused,daylight,revision,count,sections,future,events},light,None{}},entries,Cooking{0n,[]},[]})),Done{Unit{}})
def start_prepared(views:List<&2,S.View>,state:State,future:List<&2,Q.Pending<C.Mutation>>,catalog:B.Catalog,
    result:Result<&2,&2,W.Error,List<&2,W.Due>>) -> State & Result<&2,&2,Error,Unit>:
  match result:
    case Fail{error}: (state,Fail{World{error}})
    case Done{due}: started(views,state,future,operations(due,catalog))
def start_partition(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    +light_context:Light,views:List<&2,S.View>,state:State,+catalog:B.Catalog,+count:U32,
    partition:List<&2,Q.Pending<C.Mutation>> & List<&2,Q.Pending<C.Mutation>>) -> State & Result<&2,&2,Error,Unit>:
  (due,future) = partition
  start_prepared(views,state,future,catalog,W.prepare_due(~Light,~properties,~enabled,due,light_context,count))
def start_world(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,views:List<&2,S.View>,entries:List<&1,S.Entry>,catalog:B.Catalog,world:W.State) -> State & Result<&2,&2,Error,Unit>:
  W.State{C.World{+tick,time,paused,daylight,revision,+count,sections,+pending,events},light,loading} = world
  start_partition(~Light,~properties,~enabled,light_context,views,
    State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,Idle{},[]},catalog,count,Q.take_due(C.Mutation,pending,1n+tick))
def start_resident(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,views:List<&2,S.View>,entries:List<&1,S.Entry>,catalog:B.Catalog,
    result:W.State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  (world,status) = result
  match status:
    case Fail{error}: (State{world,entries,Idle{},[]},Fail{error})
    case Done{unit}:
      start_world(~Light,~properties,~enabled,light_context,views,entries,catalog,world)
def start_inspected(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,world:W.State,catalog:B.Catalog,result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>) -> State & Result<&2,&2,Error,Unit>:
  (entries,status) = result
  match status:
    case Fail{text}: (State{world,entries,Idle{},[]},Fail{Authority{text}})
    case Done{+views}: start_resident(~Light,~properties,~enabled,light_context,views,entries,catalog,resident(views,world))
# Actual Core scheduled admission and due application, never a manufactured
# player/developer capability. Clock advances exactly once; finish_tick below
# is the required second phase before another start_tick may run.
def start_tick(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:Context,state:State) -> State & Result<&2,&2,Error,Unit>:
  Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  match state:
    case State{world,entries,Cooking{tick,effects},keys}: (State{world,entries,Cooking{tick,effects},keys},Fail{Busy{}})
    case State{world,entries,Idle{},key <> rest}: (State{world,entries,Idle{},key <> rest},Fail{Loading{}})
    case State{W.State{world,light,Some{cursor}},entries,Idle{},Nil{}}:
      (State{W.State{world,light,Some{cursor}},entries,Idle{},[]},Fail{World{W.LoadingInProgress{}}})
    case State{world,entries,Idle{},Nil{}}:
      start_inspected(~Light,~properties,~enabled,light_context,world,catalog,S.inspect(recipes,entries))
def world_status(result:Result<&2,&2,W.Error,Unit>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Fail{error}: Fail{World{error}}
    case Done{unit}: Done{Unit{}}
def admitted(entries:List<&1,S.Entry>,phase:Phase,keys:List<&2,String>,result:W.State & Result<&2,&2,W.Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  (world,status) = result
  (State{world,entries,phase,keys},world_status(status))
def admit(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,state:State,cap:C.Capability,stamp:Q.Stamp,mutation:C.Mutation) -> State & Result<&2,&2,Error,Unit>:
  State{world,entries,phase,keys} = state
  admitted(entries,phase,keys,W.admit(~Light,~properties,~enabled,light_context,world,cap,stamp,mutation))

def incarnation_operations(values:List<&2,Operation>) -> List<&2,Incarnation.Operation>:
  match values:
    case Nil{}: []
    case Operation{W.Due{stamp,prepared},classification} <> rest:
      Incarnation.Operation{prepared,classification} <> incarnation_operations(rest)

def owned_guarded(views:List<&2,S.View>,light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,S.Entry>,
    phase:Phase,keys:List<&2,String>,future:List<&2,Q.Pending<C.Mutation>>,ops:List<&2,Operation>,
    result:C.World & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,Error,Unit>:
  match result:
    case (world,Fail{text}): (State{W.State{world,light,loading},entries,phase,keys},Fail{Authority{text}})
    case (world,Done{unit}): started(views,State{W.State{world,light,loading},entries,phase,keys},future,Done{ops})

def owned_ready(+views:List<&2,S.View>,future:List<&2,Q.Pending<C.Mutation>>,+ops:List<&2,Operation>,
    incarnations:Map<&2,Nat>,acknowledged:Nat,state:State) -> State & Result<&2,&2,Error,Unit>:
  State{W.State{world,light,loading},entries,phase,keys} = state
  owned_guarded(views,light,loading,entries,phase,keys,future,ops,
    Incarnation.check(world,views,incarnation_operations(ops),incarnations,acknowledged))

def owned_classified(views:List<&2,S.View>,state:State,future:List<&2,Q.Pending<C.Mutation>>,
    incarnations:Map<&2,Nat>,acknowledged:Nat,result:Result<&2,&2,String,List<&2,Operation>>) -> State & Result<&2,&2,Error,Unit>:
  match result:
    case Fail{text}: (state,Fail{Authority{text}})
    case Done{ops}: owned_ready(views,future,ops,incarnations,acknowledged,state)

def owned_prepared(views:List<&2,S.View>,state:State,future:List<&2,Q.Pending<C.Mutation>>,catalog:B.Catalog,
    incarnations:Map<&2,Nat>,acknowledged:Nat,result:Result<&2,&2,W.Error,List<&2,W.Due>>) -> State & Result<&2,&2,Error,Unit>:
  match result:
    case Fail{error}: (state,Fail{World{error}})
    case Done{due}: owned_classified(views,state,future,incarnations,acknowledged,operations(due,catalog))

def owned_partition(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,views:List<&2,S.View>,state:State,catalog:B.Catalog,count:U32,incarnations:Map<&2,Nat>,acknowledged:Nat,
    partition:List<&2,Q.Pending<C.Mutation>> & List<&2,Q.Pending<C.Mutation>>) -> State & Result<&2,&2,Error,Unit>:
  (due,future) = partition
  owned_prepared(views,state,future,catalog,incarnations,acknowledged,
    W.prepare_due(~Light,~properties,~enabled,due,light_context,count))

def owned_world(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,views:List<&2,S.View>,entries:List<&1,S.Entry>,catalog:B.Catalog,incarnations:Map<&2,Nat>,acknowledged:Nat,
    world:W.State) -> State & Result<&2,&2,Error,Unit>:
  W.State{C.World{+tick,time,paused,daylight,revision,+count,sections,+pending,events},light,loading} = world
  owned_partition(~Light,~properties,~enabled,light_context,views,
    State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,Idle{},[]},
    catalog,count,incarnations,acknowledged,Q.take_due(C.Mutation,pending,1n+tick))

def owned_resident(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,views:List<&2,S.View>,entries:List<&1,S.Entry>,catalog:B.Catalog,incarnations:Map<&2,Nat>,acknowledged:Nat,
    result:W.State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  (world,status) = result
  match status:
    case Fail{error}: (State{world,entries,Idle{},[]},Fail{error})
    case Done{unit}: owned_world(~Light,~properties,~enabled,light_context,views,entries,catalog,incarnations,acknowledged,world)

def owned_inspected(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,world:W.State,catalog:B.Catalog,incarnations:Map<&2,Nat>,acknowledged:Nat,
    result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>) -> State & Result<&2,&2,Error,Unit>:
  (entries,status) = result
  match status:
    case Fail{text}: (State{world,entries,Idle{},[]},Fail{Authority{text}})
    case Done{+views}:
      owned_resident(~Light,~properties,~enabled,light_context,views,entries,catalog,incarnations,acknowledged,resident(views,world))

# The original start API remains unchanged. This owned actor seam admits the
# entire prospective reset sequence before tick/time/pending/events or any
# section/light/Entry write. Refusal retains the complete input owner.
def start_tick_owned(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:Context,incarnations:Map<&2,Nat>,acknowledged_resets:Nat,state:State) ->
    State & Result<&2,&2,Error,Unit>:
  Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  match state:
    case State{world,entries,Cooking{tick,effects},keys}: (State{world,entries,Cooking{tick,effects},keys},Fail{Busy{}})
    case State{world,entries,Idle{},key <> rest}: (State{world,entries,Idle{},key <> rest},Fail{Loading{}})
    case State{W.State{world,light,Some{cursor}},entries,Idle{},Nil{}}:
      (State{W.State{world,light,Some{cursor}},entries,Idle{},[]},Fail{World{W.LoadingInProgress{}}})
    case State{world,entries,Idle{},Nil{}}:
      owned_inspected(~Light,~properties,~enabled,light_context,world,catalog,incarnations,acknowledged_resets,S.inspect(recipes,entries))
