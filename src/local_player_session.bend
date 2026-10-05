import Base
import ./local_player_cooking.bend as Cooking
import ./cooking_block_entity_codec.bend as CookingCodec
import ./cooking_world_store.bend as CookingStore
import ./nbt.bend as Nbt
import ./local_player_cooking_storage.bend as CookingStorage
import ./local_player_cooking_entities.bend as CookingEntities
import ./local_player_cooking_publication.bend as CookingPublication
import ./local_player_cooking_publication_delivery.bend as CookingDelivery
import ./local_player_cooking_publication_codec.bend as PublicationCodec
import ./local_player_cooking_publication_owner.bend as PublicationOwner
import ./cooking_effect_publication_journal.bend as PublicationJournal
import ./local_player_cooking_bootstrap.bend as CookingBootstrap
import ./local_player_cooking_geometry.bend as CookingGeometry
import ./local_player_cooking_edit.bend as CookingEdit
import ./local_collision_world.bend as Collision
import ./cooking_effect_entities_model.bend as CookingModel
import ./random.bend as Random
import ./player_block_inside_stuck.bend as Inside
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./player_fall_history.bend as H
import ./player_runtime.bend as Plain
import ./player_controls.bend as CT
import ./mouse_input.bend as MI
import ./local_player_record.bend as PR
import ./local_player_storage.bend as PS
import ./client_controls.bend as CC
import ./player_input.bend as PI
import ./client_world.bend as W
import ./client_render.bend as CR
import ./extended_persistence.bend as E
import ./persistence.bend as P
import ./world_lock.bend as WL
import ./locomotion.bend as T
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./live.bend as L
import ./json.bend as J
import ./player_inventory.bend as I
import ./player_inventory_codec.bend as IC
import ./inventory.bend as Inv
import ./player_block_interaction.bend as BI
import ./world_generation_settings.bend as WG
import ./player_item_definitions.bend as D

# The LocalPlayer runtime owns the only Engine/body. The leased save shell
# transfers that Engine and the complete supported local record through the
# existing atomic extension transaction. Renderer/API reads never tick it.
type Shell is Type:
  Shell{identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>,inventory:I.State,fresh:Bool,generation:WG.Settings,cooking:Cooking.Sidecar}
type State is Type:
  State{player:X.State,shell:Shell}

# Startup provenance is transient. An empty loaded Core is still a loaded
# world; only the codec's fresh initializer authorizes terrain initialization.
def fresh(state:State) -> State & Bool:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,+initial,generation,cooking}} = state
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,initial,generation,cooking}},initial)

def mark_initialized(state:State) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,initial,generation,cooking}} = state
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,False{},generation,cooking}}

def generation(state:State) -> State & WG.Settings:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,+settings,cooking}} = state
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,settings,cooking}},settings)

def generation_assign(state:State,settings:WG.Settings) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,old,cooking}} = state
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,settings,cooking}}

def generation_validated(state:State,result:Result<&2,&2,String,WG.Settings>) -> State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{settings}: (generation_assign(state,settings),Done{Unit{}})

def set_generation(state:State,settings:WG.Settings) -> State & Result<&2,&2,String,Unit>:
  generation_validated(state,WG.validate(settings))

def to_bundle_split(shell:Shell,result:G.Engine & PR.Record & R.Detached) -> E.State<IC.Saved> & R.Transient:
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking} = shell
  (engine,record,transient) = result
  (E.State{P.State{engine,identity,path,highwater,limits,lease},IC.Saved{record,inventory,fresh,generation},maximum,catalog},R.Transient{transient,cooking})

def to_bundle(state:State) -> E.State<IC.Saved> & R.Transient:
  State{player,shell} = state
  to_bundle_split(shell,R.detach(player))

def from_bundle(stored:E.State<IC.Saved>,transient:R.Transient) -> State:
  E.State{P.State{engine,identity,path,highwater,limits,lease},IC.Saved{record,inventory,fresh,generation},maximum,catalog} = stored
  R.Transient{player,cooking} = transient
  State{R.attach(engine,record,player),Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}}

# This pure detour transfers the sole Core owner to cooking. The saved header,
# player record, array owners and all unsaved fields remain in their existing
# bundle carriers; no physical encoding or second world is constructed.
def cooking_returned(-A:Data,registry:B.Registry,identity:String,path:String,highwater:U32,
    limits:P.Limits,lease:WL.Lease,saved:IC.Saved,maximum:U32,catalog:List<&2,E.Operation>,
    player:R.Detached,result:C.World & Cooking.Sidecar & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  (world,cooking,status) = result
  (from_bundle(E.State{P.State{G.Engine{world,registry},identity,path,highwater,limits,lease},saved,maximum,catalog},
    R.Transient{player,cooking}),status)

def cooking_detached(-A:Data,operation:C.World -> Cooking.Sidecar -> C.World & Cooking.Sidecar & Result<&2,&2,String,A>,
    result:E.State<IC.Saved> & R.Transient) -> State & Result<&2,&2,String,A>:
  (E.State{P.State{G.Engine{world,registry},identity,path,highwater,limits,lease},saved,maximum,catalog},
    R.Transient{player,cooking}) = result
  cooking_returned(A,registry,identity,path,highwater,limits,lease,saved,maximum,catalog,player,operation(world,cooking))

def cooking_query(-A:Data,state:State,operation:C.World -> Cooking.Sidecar -> C.World & Cooking.Sidecar & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  cooking_detached(A,operation,to_bundle(state))

# IO suppliers receive the same sole Core and Sidecar as the pure detour.
# The other Session owners live in this continuation until the supplier returns.
def cooking_detached_io(-A:Data,
    operation:C.World -> Cooking.Sidecar -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,A>),
    result:E.State<IC.Saved> & R.Transient) -> IO(State & Result<&2,&2,String,A>):
  (E.State{P.State{G.Engine{world,registry},identity,path,highwater,limits,lease},saved,maximum,catalog},
    R.Transient{player,cooking}) = result
  do IO<State & Result<&2,&2,String,A>>:
    returned : C.World & Cooking.Sidecar & Result<&2,&2,String,A> <- operation(world,cooking)
    return cooking_returned(A,registry,identity,path,highwater,limits,lease,saved,maximum,catalog,player,returned)

def cooking_query_io(-A:Data,state:State,
    operation:C.World -> Cooking.Sidecar -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,A>)) -> IO(State & Result<&2,&2,String,A>):
  cooking_detached_io(A,operation,to_bundle(state))

# Geometry suppliers borrow the sole Engine so the authenticated Registry and
# Core travel together. Every saved/player/Shell owner stays in this detour.
def cooking_engine_returned(-A:Data,identity:String,path:String,highwater:U32,
    limits:P.Limits,lease:WL.Lease,saved:IC.Saved,maximum:U32,catalog:List<&2,E.Operation>,
    player:R.Detached,result:G.Engine & Cooking.Sidecar & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  (engine,cooking,status) = result
  (from_bundle(E.State{P.State{engine,identity,path,highwater,limits,lease},saved,maximum,catalog},
    R.Transient{player,cooking}),status)

def cooking_engine_detached_io(-A:Data,
    operation:G.Engine -> Cooking.Sidecar -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,A>),
    result:E.State<IC.Saved> & R.Transient) -> IO(State & Result<&2,&2,String,A>):
  (E.State{P.State{engine,identity,path,highwater,limits,lease},saved,maximum,catalog},
    R.Transient{player,cooking}) = result
  do IO<State & Result<&2,&2,String,A>>:
    returned : G.Engine & Cooking.Sidecar & Result<&2,&2,String,A> <- operation(engine,cooking)
    return cooking_engine_returned(A,identity,path,highwater,limits,lease,saved,maximum,catalog,player,returned)

def cooking_engine_query_io(-A:Data,state:State,
    operation:G.Engine -> Cooking.Sidecar -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,A>)) -> IO(State & Result<&2,&2,String,A>):
  cooking_engine_detached_io(A,operation,to_bundle(state))

def cooking_engine_detached(-A:Data,
    operation:G.Engine -> Cooking.Sidecar -> G.Engine & Cooking.Sidecar & Result<&2,&2,String,A>,
    result:E.State<IC.Saved> & R.Transient) -> State & Result<&2,&2,String,A>:
  (E.State{P.State{engine,identity,path,highwater,limits,lease},saved,maximum,catalog},R.Transient{player,cooking}) = result
  cooking_engine_returned(A,identity,path,highwater,limits,lease,saved,maximum,catalog,player,operation(engine,cooking))

def cooking_engine_query(-A:Data,state:State,
    operation:G.Engine -> Cooking.Sidecar -> G.Engine & Cooking.Sidecar & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  cooking_engine_detached(A,operation,to_bundle(state))

# A container transaction also transfers the actual player inventory once.
# The operation returns both array owners before the Session is reconstructed.
def cooking_inventory_returned(-A:Data,registry:B.Registry,identity:String,path:String,highwater:U32,
    limits:P.Limits,lease:WL.Lease,record:PR.Record,fresh:Bool,generation:WG.Settings,
    maximum:U32,catalog:List<&2,E.Operation>,player:R.Detached,
    result:C.World & Cooking.Sidecar & I.State & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  (world,cooking,inventory,status) = result
  (from_bundle(E.State{P.State{G.Engine{world,registry},identity,path,highwater,limits,lease},
    IC.Saved{record,inventory,fresh,generation},maximum,catalog},R.Transient{player,cooking}),status)

def cooking_inventory_detached(-A:Data,
    operation:C.World -> Cooking.Sidecar -> I.State -> C.World & Cooking.Sidecar & I.State & Result<&2,&2,String,A>,
    result:E.State<IC.Saved> & R.Transient) -> State & Result<&2,&2,String,A>:
  (E.State{P.State{G.Engine{world,registry},identity,path,highwater,limits,lease},
    IC.Saved{record,inventory,fresh,generation},maximum,catalog},R.Transient{player,cooking}) = result
  cooking_inventory_returned(A,registry,identity,path,highwater,limits,lease,record,fresh,generation,
    maximum,catalog,player,operation(world,cooking,inventory))

def cooking_inventory_query(-A:Data,state:State,
    operation:C.World -> Cooking.Sidecar -> I.State -> C.World & Cooking.Sidecar & I.State & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  cooking_inventory_detached(A,operation,to_bundle(state))

def cooking_begin(state:State,context:Cooking.Context) -> State & Result<&2,&2,String,Unit>:
  cooking_query(Unit,state,world => sidecar => Cooking.begin(world,sidecar,context))

def cooking_resume_loading(state:State,budget:Nat) -> State & Result<&2,&2,String,Bool>:
  cooking_query(Bool,state,world => sidecar => Cooking.resume_loading(world,sidecar,budget))

def cooking_load_body(state:State,position:C.Position,limits:Nbt.Limits,bytes:List<&2,U32>,cap:C.Capability) -> State & Result<&2,&2,String,CookingCodec.Details>:
  cooking_query(CookingCodec.Details,state,world => sidecar => Cooking.load_body(world,sidecar,position,limits,bytes,cap))

def cooking_save_body(state:State,position:C.Position,limits:Nbt.Limits,cap:C.Capability) -> State & Result<&2,&2,String,List<&2,U32>>:
  cooking_query(List<&2,U32>,state,world => sidecar => Cooking.save_body(world,sidecar,position,limits,cap))

def cooking_effects_returned(player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>,inventory:I.State,fresh:Bool,generation:WG.Settings,
    result:Cooking.Sidecar & List<&2,CookingStore.Effect>) -> State & List<&2,CookingStore.Effect>:
  (cooking,effects) = result
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},effects)

def cooking_take_effects(state:State) -> State & List<&2,CookingStore.Effect>:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  cooking_effects_returned(player,identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,
    Cooking.take_effects(cooking))

def cooking_sidecar_returned(-A:Data,player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>,inventory:I.State,fresh:Bool,generation:WG.Settings,
    result:Cooking.Sidecar & A) -> State & A:
  (cooking,value) = result
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},value)

def cooking_sidecar_query(-A:Data,state:State,operation:Cooking.Sidecar -> Cooking.Sidecar & A) -> State & A:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  cooking_sidecar_returned(A,player,identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,
    operation(cooking))

# Queue reads are snapshots; save detours never drain or replay the live queue.
def cooking_pending(state:State) -> State & List<&2,CookingStore.Effect>:
  cooking_sidecar_query(List<&2,CookingStore.Effect>,state,Cooking.pending_snapshot)

def cooking_restore_pending(state:State,effects:List<&2,CookingStore.Effect>) -> State & Result<&2,&2,String,Unit>:
  cooking_sidecar_query(Result<&2,&2,String,Unit>,state,sidecar => Cooking.restore_pending(sidecar,effects))

def cooking_enqueue_effects(state:State,effects:List<&2,CookingStore.Effect>) -> State & Result<&2,&2,String,Unit>:
  cooking_sidecar_query(Result<&2,&2,String,Unit>,state,sidecar => Cooking.enqueue_effects(sidecar,effects))

def cooking_deliver_pending(state:State) -> State & Result<&2,&2,String,Unit>:
  cooking_sidecar_query(Result<&2,&2,String,Unit>,state,Cooking.deliver_pending)

def cooking_deliver_pending_io(state:State) -> IO(State & Result<&2,&2,String,Unit>):
  cooking_engine_query_io(Unit,state,engine => sidecar => CookingDelivery.deliver_io(engine,sidecar))

def cooking_initialize_publication(state:State,recovery:Maybe<&2,PublicationCodec.Recovery>,pending:List<&2,CookingStore.Effect>) -> State & Result<&2,&2,String,Unit>:
  cooking_engine_query(Unit,state,engine => sidecar => CookingPublication.initialize(engine,sidecar,recovery,pending))

def cooking_publication(state:State) -> State & Maybe<&2,PublicationCodec.Recovery>:
  cooking_sidecar_query(Maybe<&2,PublicationCodec.Recovery>,state,CookingPublication.snapshot)

def cooking_prepare_publication_save(state:State) -> State & Maybe<&2,PublicationOwner.Prepared>:
  cooking_sidecar_query(Maybe<&2,PublicationOwner.Prepared>,state,CookingPublication.prepare_save)

# Geometry initialization authenticates the catalog against the retained live
# Registry after body/entity initialization and before pending effect delivery.
def cooking_load_geometry(state:State,path:String,environment:Collision.Environment) -> IO(State & Result<&2,&2,String,Unit>):
  cooking_engine_query_io(Unit,state,engine => sidecar => CookingGeometry.load(sidecar,engine,path,environment))

def cooking_recovery(view:Maybe<&2,CookingModel.View>,inputs:List<&2,Random.Bits64>) -> Maybe<&2,CookingStorage.EntityRecovery>:
  match view:
    case None{}: None{}
    case Some{value}: Some{CookingStorage.EntityRecovery{value,inputs}}

def cooking_entity_observed(result:Cooking.Sidecar & Maybe<&2,CookingModel.View> & List<&2,Random.Bits64>) ->
    Cooking.Sidecar & Maybe<&2,CookingStorage.EntityRecovery>:
  (sidecar,view,inputs) = result
  (sidecar,cooking_recovery(view,inputs))

# The immutable View is observed from the actual owner; the live carrier and
# its complete clock queue remain inside the same Session throughout saving.
def cooking_entities(state:State) -> State & Maybe<&2,CookingStorage.EntityRecovery>:
  cooking_sidecar_query(Maybe<&2,CookingStorage.EntityRecovery>,state,Cooking.saved_entity_snapshot)

def cooking_restore_entities(state:State,context:CookingModel.Context,recovery:Maybe<&2,CookingStorage.EntityRecovery>) -> State & Result<&2,&2,String,Unit>:
  match recovery:
    case None{}:
      cooking_sidecar_query(Result<&2,&2,String,Unit>,state,sidecar => Cooking.restore_entity_view(sidecar,context,None{},[]))
    case Some{CookingStorage.EntityRecovery{view,inputs}}:
      cooking_sidecar_query(Result<&2,&2,String,Unit>,state,sidecar => Cooking.restore_entity_view(sidecar,context,Some{view},inputs))
    case Some{CookingStorage.TickRecovery{snapshot}}:
      cooking_sidecar_query(Result<&2,&2,String,Unit>,state,sidecar => Cooking.restore_entity_tick(sidecar,context,snapshot))

# Existing Views restore their exact owner and supplied clock queue with no
# factory draws. Legacy/fresh absence enters only the declared fresh process
# factory boundary, after actual Sidecar admission and before pending delivery.
def cooking_initialize_entities(state:State,context:CookingModel.Context,recovery:Maybe<&2,CookingStorage.EntityRecovery>) -> IO(State & Result<&2,&2,String,Unit>):
  match recovery:
    case None{}: cooking_query_io(Unit,state,world => sidecar => CookingBootstrap.begin(world,sidecar,context))
    case Some{value}: IO.pure(State & Result<&2,&2,String,Unit>,cooking_restore_entities(state,context,Some{value}))

def cooking_entity_bound(player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>,inventory:I.State,fresh:Bool,generation:WG.Settings,
    result:Cooking.Sidecar & Maybe<&1,CookingModel.State> & Result<&2,&2,String,Unit>) ->
    State & Maybe<&1,CookingModel.State> & Result<&2,&2,String,Unit>:
  (cooking,rejected,status) = result
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},rejected,status)

def cooking_bind_entities(state:State,context:CookingModel.Context,owner:CookingModel.State,inputs:List<&2,Random.Bits64>) ->
    State & Maybe<&1,CookingModel.State> & Result<&2,&2,String,Unit>:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  cooking_entity_bound(player,identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,
    Cooking.bind_entity_owner(cooking,context,owner,inputs))

def cooking_positions(state:State) -> State & List<&2,C.Position>:
  cooking_sidecar_query(List<&2,C.Position>,state,Cooking.positions)

def cooking_details_at(state:State,position:C.Position) -> State & Maybe<&2,CookingCodec.Details>:
  cooking_sidecar_query(Maybe<&2,CookingCodec.Details>,state,sidecar => Cooking.details_at(sidecar,position))

def cooking_bodies_cons(position:C.Position,bytes:List<&2,U32>,result:State & Result<&2,&2,String,List<&2,CookingStorage.Body>>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  (state,status) = result
  (state,Result.map(&2,&2,String,List<&2,CookingStorage.Body>,List<&2,CookingStorage.Body>,
    rest => CookingStorage.Body{position,bytes} <> rest,status))

def cooking_body_merged(+position:C.Position,state:State,
    next:State -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>,
    result:Result<&2,&2,String,List<&2,U32>>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{bytes}: cooking_bodies_cons(position,bytes,next(state))

def cooking_body_details(position:C.Position,bytes:List<&2,U32>,
    next:State -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>,
    result:State & Maybe<&2,CookingCodec.Details>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  (state,details) = result
  cooking_body_merged(position,state,next,CookingStorage.with_details(CookingStorage.nbt_limits(),bytes,details))

def cooking_body_saved(+position:C.Position,
    next:State -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>,
    result:State & Result<&2,&2,String,List<&2,U32>>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{bytes}: cooking_body_details(position,bytes,next,cooking_details_at(state,position))

def cooking_collect(positions:List<&2,C.Position>,state:State) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  match positions:
    case Nil{}: (state,Done{[]})
    case +position <> rest:
      cooking_body_saved(position,state => cooking_collect(rest,state),
        cooking_save_body(state,position,CookingStorage.nbt_limits(),C.Developer{}))

def cooking_collect_positions(result:State & List<&2,C.Position>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  (state,positions) = result
  cooking_collect(positions,state)

def cooking_collect_ready(result:State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{unit}: cooking_collect_positions(cooking_positions(state))

# Collect complete known bodies plus their retained physical extras before the
# single existing durable transaction. Queries do not perform this collection.
def cooking_bodies(state:State) -> State & Result<&2,&2,String,List<&2,CookingStorage.Body>>:
  cooking_collect_ready(cooking_sidecar_query(Result<&2,&2,String,Unit>,state,Cooking.persistence_ready))

def queried(-A:Type,shell:Shell,result:X.State & A) -> State & A:
  (player,value) = result
  (State{player,shell},value)

def query(-A:Type,state:State,operation:X.State -> X.State & A) -> State & A:
  State{player,shell} = state
  queried(A,shell,operation(player))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,CR.Snapshot>:
  query(Result<&2,&2,String,CR.Snapshot>,state,p => R.snapshot(p,width,height))

def input(state:State,bindings:PI.Bindings,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  query(Result<&2,&2,String,Unit>,state,p => R.input(p,bindings,packet))

def release(state:State) -> State:
  State{player,shell} = state
  State{R.release(player),shell}

def cooking_error_returned(result:State & Unit) -> State:
  (state,unit) = result
  state

def cooking_error(state:State,message:String) -> State:
  cooking_error_returned(query(Unit,state,player => (R.with_error(player,Some{message}),Unit{})))

def inventory_queried(-A:Type,player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,cooking:Cooking.Sidecar,result:I.State & A) -> State & A:
  (inventory,value) = result
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},value)

def inventory_query(-A:Type,state:State,operation:I.State -> I.State & A) -> State & A:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  inventory_queried(A,player,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,cooking,operation(inventory))

def inventory_inspect(state:State) -> State & I.Snapshot:
  inventory_query(I.Snapshot,state,I.inspect)

def inventory_selected(state:State) -> State & Inv.Slot:
  inventory_query(Inv.Slot,state,I.selected)

def inventory_select(state:State,index:U32) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.select(i,index))

def inventory_transfer(state:State,source:U32,destination:U32,count:U32,mode:Inv.TransferMode) -> State & Inv.TransferStatus:
  inventory_query(Inv.TransferStatus,state,i => I.transfer(i,source,destination,count,mode))

def inventory_acquire(state:State,index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.acquire(i,index,key,count))

def inventory_abilities(state:State) -> State & I.Abilities:
  inventory_query(I.Abilities,state,I.abilities)

def inventory_status(state:State) -> State & I.Status:
  inventory_query(I.Status,state,I.status)

def inventory_status_updated(result:State & Unit) -> State:
  (state,unit) = result
  state

def set_inventory_status(state:State,status:I.Status) -> State:
  inventory_status_updated(inventory_query(Unit,state,i => (I.set_status(i,status),Unit{})))

def status_runtime_updated(shell:Shell,result:X.State & I.Status) -> State:
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking} = shell
  (player,status) = result
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,I.set_status(inventory,status),fresh,generation,cooking}}

def status_inventory_read(operation:I.Status -> X.State -> X.State & I.Status,player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,cooking:Cooking.Sidecar,result:I.State & I.Status) -> State:
  (inventory,status) = result
  status_runtime_updated(Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},operation(status,player))

def run_with_status(state:State,operation:I.Status -> X.State -> X.State & I.Status) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  status_inventory_read(operation,player,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,cooking,I.status(inventory))

def cooking_delivery_completed(result:State & Result<&2,&2,String,Unit>) -> State:
  (state,status) = result
  match status:
    case Fail{message}: cooking_error(state,message)
    case Done{unit}: state

def cooking_tick_completed(driver:R.Driver,result:State & Result<&2,&2,String,Bool>) -> State:
  (state,status) = result
  match status:
    case Fail{message}: cooking_error(state,message)
    case Done{False{}}: state
    case Done{True{}}:
      cooking_delivery_completed(cooking_deliver_pending(run_with_status(state,
        status => player => R.status_after_world_tick(driver,status,player))))

def cooking_tick_shaped(driver:R.Driver,scheduled:Bool,result:State & Maybe<&2,X.Error>) -> State:
  (state,error) = result
  match error:
    case Some{cause}: cooking_error(state,R.error_text(cause))
    case None{}:
      cooking_tick_completed(driver,cooking_query(Bool,state,world => sidecar => Cooking.tick(world,sidecar,scheduled)))

# A failed cooking finish owns an already started Core tick. A later success
# completes common/player processing once even if Core's tick did not change.
def cooking_step_delivered(driver:R.Driver,scheduled:Bool,result:State & Result<&2,&2,String,Unit>) -> State:
  (state,status) = result
  match status:
    case Fail{message}: cooking_error(state,message)
    case Done{unit}: cooking_tick_shaped(driver,scheduled,query(Maybe<&2,X.Error>,state,X.stage_shape))

# A missing effect publisher blocks the next Core tick. Completion above runs
# common/player once before delivery, so a retained queue cannot skip that work.
def cooking_step(driver:R.Driver,state:State,scheduled:Bool) -> State:
  cooking_step_delivered(driver,scheduled,cooking_deliver_pending(state))

def realtime_step(driver:R.Driver,state:State) -> State:
  cooking_step(driver,state,False{})

def step(driver:R.Driver,state:State) -> State:
  cooking_step(driver,state,True{})

# The closed delivery supplier may obtain real monotonic inputs while retaining
# the actual World. No player/common continuation starts before that IO returns.
def cooking_tick_completed_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,result:State & Result<&2,&2,String,Bool>) -> IO(State):
  (state,status) = result
  match status:
    case Fail{message}: IO.pure(State,cooking_error(state,message))
    case Done{False{}}: IO.pure(State,state)
    case Done{True{}}:
      do IO<State>:
        delivered : State & Result<&2,&2,String,Unit> <- delivery(
          run_with_status(state,status => player => R.status_after_world_tick(driver,status,player)))
        return cooking_delivery_completed(delivered)

def cooking_tick_shaped_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,scheduled:Bool,result:State & Maybe<&2,X.Error>) -> IO(State):
  (state,error) = result
  match error:
    case Some{cause}: IO.pure(State,cooking_error(state,R.error_text(cause)))
    case None{}:
      cooking_tick_completed_io(~delivery,driver,cooking_query(Bool,state,world => sidecar => Cooking.tick(world,sidecar,scheduled)))

def cooking_step_delivered_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,scheduled:Bool,result:State & Result<&2,&2,String,Unit>) -> IO(State):
  (state,status) = result
  match status:
    case Fail{message}: IO.pure(State,cooking_error(state,message))
    case Done{unit}: cooking_tick_shaped_io(~delivery,driver,scheduled,query(Maybe<&2,X.Error>,state,X.stage_shape))

def cooking_step_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,state:State,scheduled:Bool) -> IO(State):
  do IO<State>:
    delivered : State & Result<&2,&2,String,Unit> <- delivery(state)
    cooking_step_delivered_io(~delivery,driver,scheduled,delivered)

def realtime_step_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,state:State) -> IO(State):
  cooking_step_io(~delivery,driver,state,False{})

def step_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,state:State) -> IO(State):
  cooking_step_io(~delivery,driver,state,True{})

def advance_runtime_error(player:X.State) -> X.State & Maybe<&2,String>:
  X.State{motion,tables,X.Metadata{local,record,sprint,pose,controls,entity,receiver,+error,metadata_tail},tail} = player
  (X.State{motion,tables,X.Metadata{local,record,sprint,pose,controls,entity,receiver,error,metadata_tail},tail},error)

def advance_completed(next:State -> State,result:State & Maybe<&2,String>) -> State:
  (state,error) = result
  match error:
    case Some{message}: state
    case None{}: next(state)

def advance_go(+driver:R.Driver,ticks:Nat,state:State) -> State:
  match ticks:
    case 0n: state
    case 1n+rest: advance_completed(state => advance_go(driver,rest,state),
      query(Maybe<&2,String>,step(driver,state),advance_runtime_error))

def advance(~driver:R.Driver,state:State,ticks:U32) -> State:
  advance_go(driver,U32.to_nat(ticks),state)

def advance_completed_io(next:State -> IO(State),result:State & Maybe<&2,String>) -> IO(State):
  (state,error) = result
  match error:
    case Some{message}: IO.pure(State,state)
    case None{}: next(state)

def advance_go_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    +driver:R.Driver,ticks:Nat,state:State) -> IO(State):
  match ticks:
    case 0n: IO.pure(State,state)
    case 1n+rest:
      do IO<State>:
        stepped : State <- step_io(~delivery,driver,state)
        advance_completed_io(state => advance_go_io(~delivery,driver,rest,state),query(Maybe<&2,String>,stepped,advance_runtime_error))

def advance_io(~delivery:State -> IO(State & Result<&2,&2,String,Unit>),
    driver:R.Driver,state:State,ticks:U32) -> IO(State):
  advance_go_io(~delivery,driver,U32.to_nat(ticks),state)

def inventory_definitions(state:State) -> State & D.Catalog:
  inventory_query(D.Catalog,state,I.definitions)

def menu_inspect(state:State) -> State & I.MenuSnapshot:
  inventory_query(I.MenuSnapshot,state,I.menu_inspect)

def menu_open(state:State) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,I.menu_open)

def menu_close(state:State) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,I.menu_close)

def menu_click(state:State,index:U32,click:I.Click) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.menu_click(i,index,click))

def catalog(unit:Unit) -> List<&2,E.Operation>:
  [E.Operation{"player.inspect",L.Public{},[],"Observe the complete supported LocalPlayer record as exact typed NBT bytes; this query does not advance simulation."}]

def byte_values(bytes:List<&2,U32>) -> List<&2,J.Value>:
  match bytes:
    case Nil{}: []
    case byte <> rest: L.uint(byte) <> byte_values(rest)

def inspected(engine:G.Engine,record:PR.Record,result:Result<&2,&2,PR.Error,List<&2,U32>>) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{error}: (engine,record,Fail{L.bad("InvalidPlayerState",PR.error_text(error))})
    case Done{bytes}: (engine,record,Done{L.obj([J.JMember{"format",L.text("bendex:local-player-record")},J.JMember{"nbt_bytes",J.JArray{byte_values(bytes)}}])})

def operation_dispatch(engine:G.Engine,+record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  L.Envelope{id,op,args,at} = envelope
  match op:
    case "player.inspect": inspected(engine,record,PR.encode(record))
    case _: (engine,record,Fail{L.bad("UnknownOperation","unknown player operation")})

def operation_dispatch_plain(engine:G.Engine,record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  operation_dispatch(engine,record,session,envelope)

def operations() -> E.Operations<PR.Record>:
  E.Operations{catalog,operation_dispatch_plain}

def inventory_catalog(unit:Unit) -> List<&2,E.Operation>:
  List.append(&2,E.Operation,catalog(unit),[
    E.Operation{"inventory.inspect",L.Public{},[],"Read the owned 36-slot main inventory, selected hotbar and player build abilities without advancing simulation."},
    E.Operation{"inventory.selected",L.Public{},[],"Read the selected hotbar item without advancing simulation."},
    E.Operation{"inventory.select",L.DeveloperOnly{},[L.Field{"slot",L.Unsigned{0,8},True{}}],"Select one of the nine hotbar slots."},
    E.Operation{"inventory.transfer",L.DeveloperOnly{},[L.Field{"source",L.Unsigned{0,35},True{}},L.Field{"destination",L.Unsigned{0,35},True{}},L.Field{"count",L.Unsigned{0,4294967295},True{}},L.Field{"mode",L.Text{["transfer","split","merge"]},True{}}],"Transfer a clamped count between two main-inventory slots; split requires an empty destination and merge requires a stack."},
    E.Operation{"inventory.acquire",L.DeveloperOnly{},[L.Field{"slot",L.Unsigned{0,35},True{}},L.Field{"item",L.Text{[]},True{}},L.Field{"count",L.Unsigned{0,99},True{}}],"Creative acquisition replaces one main slot with an enabled pinned default item; its observed stack limit and player instabuild ability are required."}])

def inventory_slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      L.obj([J.JMember{"id",L.text(id)},J.JMember{"components",L.text(components)},J.JMember{"count",L.uint(count)}])

def inventory_slot_values(slots:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match slots:
    case Nil{}: []
    case slot <> rest: inventory_slot_value(slot) <> inventory_slot_values(rest)

def inventory_abilities_value(profile:I.Abilities) -> J.Value:
  I.Abilities{instabuild,maybuild} = profile
  L.obj([J.JMember{"instabuild",L.boolean(instabuild)},J.JMember{"maybuild",L.boolean(maybuild)}])

def inventory_snapshot_value(snapshot:I.Snapshot) -> J.Value:
  I.Snapshot{selected,slots,abilities} = snapshot
  L.obj([J.JMember{"selected",L.uint(selected)},J.JMember{"slots",J.JArray{inventory_slot_values(slots)}},J.JMember{"abilities",inventory_abilities_value(abilities)}])

def inventory_answer(engine:G.Engine,record:PR.Record,fresh:Bool,generation:WG.Settings,result:I.State & Result<&2,&2,L.Fault,J.Value>) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  (inventory,answer) = result
  (engine,IC.Saved{record,inventory,fresh,generation},answer)

def inventory_inspected(result:I.State & I.Snapshot) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,snapshot) = result
  (inventory,Done{inventory_snapshot_value(snapshot)})

def inventory_selected_value(index:U32,result:I.State & Inv.Slot) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,slot) = result
  (inventory,Done{L.obj([J.JMember{"index",L.uint(index)},J.JMember{"slot",inventory_slot_value(slot)}])})

def inventory_selected_index(result:I.State & U32) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,index) = result
  inventory_selected_value(index,I.selected(inventory))

def inventory_selected_inspected(inventory:I.State) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  inventory_selected_index(I.selection(inventory))

def inventory_selection_value(index:U32,result:I.State & Result<&2,&2,String,Unit>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Fail{message}: (inventory,Fail{L.bad("InvalidArguments",message)})
    case Done{unit}: (inventory,Done{L.obj([J.JMember{"selected",L.uint(index)}])})

def inventory_select_args(inventory:I.State,result:Result<&2,&2,L.Fault,U32>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{+index}: inventory_selection_value(index,I.select(inventory,index))

def inventory_transfer_value(result:I.State & Inv.TransferStatus) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Inv.InvRejected{reason}: (inventory,Fail{L.bad("InventoryTransferRejected",Inv.error_name(reason))})
    case Inv.InvMoved{count}: (inventory,Done{L.obj([J.JMember{"moved",L.uint(count)}])})

type InventoryTransfer is Data:
  InventoryTransfer{source:U32,destination:U32,count:U32,mode:Inv.TransferMode}

def inventory_transfer_mode(mode:String) -> Result<&2,&2,L.Fault,Inv.TransferMode>:
  match mode:
    case "transfer": Done{Inv.TransferAny{}}
    case "split": Done{Inv.TransferSplit{}}
    case "merge": Done{Inv.TransferMerge{}}
    case _: Fail{L.invalid("mode")}

def inventory_transfer_arguments(+args:J.Value) -> Result<&2,&2,L.Fault,InventoryTransfer>:
  do Result<&2,&2,L.Fault,InventoryTransfer>:
    source : U32 <- L.get_number(args,"source",False{})
    destination : U32 <- L.get_number(args,"destination",False{})
    count : U32 <- L.get_number(args,"count",False{})
    mode : String <- L.get_string(args,"mode")
    parsed : Inv.TransferMode <- inventory_transfer_mode(mode)
    return InventoryTransfer{source,destination,count,parsed}

def inventory_transfer_args(inventory:I.State,result:Result<&2,&2,L.Fault,InventoryTransfer>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{InventoryTransfer{source,destination,count,mode}}:
      inventory_transfer_value(I.transfer(inventory,source,destination,count,mode))

type InventoryAcquire is Data:
  InventoryAcquire{slot:U32,item:String,count:U32}

def inventory_acquire_arguments(+args:J.Value) -> Result<&2,&2,L.Fault,InventoryAcquire>:
  do Result<&2,&2,L.Fault,InventoryAcquire>:
    slot : U32 <- L.get_number(args,"slot",False{})
    item : String <- L.get_string(args,"item")
    count : U32 <- L.get_number(args,"count",False{})
    return InventoryAcquire{slot,item,count}

def inventory_acquisition_value(result:I.State & Result<&2,&2,String,Unit>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Fail{message}: (inventory,Fail{L.bad("InventoryAcquisitionRejected",message)})
    case Done{unit}: (inventory,Done{L.obj([J.JMember{"acquired",L.boolean(True{})}])})

def inventory_acquire_args(inventory:I.State,result:Result<&2,&2,L.Fault,InventoryAcquire>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{InventoryAcquire{slot,item,count}}:
      inventory_acquisition_value(I.acquire(inventory,slot,Inv.ItemKey{item,""},count))

def inventory_record_inspected(inventory:I.State,fresh:Bool,generation:WG.Settings,result:G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  (engine,record,answer) = result
  (engine,IC.Saved{record,inventory,fresh,generation},answer)

def inventory_operation_dispatch(engine:G.Engine,saved:IC.Saved,session:L.Session,envelope:L.Envelope) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  IC.Saved{record,inventory,fresh,generation} = saved
  L.Envelope{id,+op,args,at} = envelope
  match op:
    case "player.inspect": inventory_record_inspected(inventory,fresh,generation,operation_dispatch(engine,record,session,L.Envelope{id,op,args,at}))
    case "inventory.inspect": inventory_answer(engine,record,fresh,generation,inventory_inspected(I.inspect(inventory)))
    case "inventory.selected": inventory_answer(engine,record,fresh,generation,inventory_selected_inspected(inventory))
    case "inventory.select": inventory_answer(engine,record,fresh,generation,inventory_select_args(inventory,L.get_number(args,"slot",False{})))
    case "inventory.transfer": inventory_answer(engine,record,fresh,generation,inventory_transfer_args(inventory,inventory_transfer_arguments(args)))
    case "inventory.acquire": inventory_answer(engine,record,fresh,generation,inventory_acquire_args(inventory,inventory_acquire_arguments(args)))
    case _: (engine,IC.Saved{record,inventory,fresh,generation},Fail{L.bad("UnknownOperation","unknown player inventory operation")})

def inventory_operations() -> E.Operations<IC.Saved>:
  E.Operations{inventory_catalog,inventory_operation_dispatch}

def dispatched(transient:R.Transient,result:E.State<IC.Saved> & L.Session & J.Value) -> State & L.Session & J.Value:
  (stored,session,value) = result
  (from_bundle(stored,transient),session,value)

def delegate_bundle(session:L.Session,token:String,request:J.Value,result:E.State<IC.Saved> & R.Transient) -> IO(State & L.Session & J.Value):
  (stored,transient) = result
  do IO<State & L.Session & J.Value>:
    result : E.State<IC.Saved> & L.Session & J.Value <- E.dispatch(~IC.Saved,~IC.codec(),~inventory_operations(),stored,session,token,request)
    return dispatched(transient,result)

def delegate(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  delegate_bundle(session,token,request,to_bundle(state))

def response(state:State,session:L.Session,value:J.Value) -> State & L.Session & J.Value:
  (state,session,value)

def success(state:State,session:L.Session,id:String,value:J.Value) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(True{})},J.JMember{"result",value}]))

def failure(state:State,session:L.Session,id:String,fault:L.Fault) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(False{})},J.JMember{"error",L.fault_value(fault)}]))

def observed(state:State,+peer:U32) -> State:
  State{player,Shell{identity,path,+highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  State{player,Shell{identity,path,U32.max(highwater,peer),limits,lease,maximum,catalog,inventory,fresh,generation,cooking}}

def reserved_local_peer(state:State,result:Result<&2,&2,String,U32>) -> State & Result<&2,&2,String,C.Capability>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{4294967295}: (state,Fail{"peer ID range cannot reserve a local player and a public peer"})
    case Done{+peer}: (observed(state,peer),Done{C.Player{peer}})

# The renderer's Player identity belongs to the durable peer allocator. Reserve
# it before opening public listeners; no peer zero or fabricated identity is used.
def reserve_local_player(state:State) -> State & Result<&2,&2,String,C.Capability>:
  State{player,Shell{identity,path,+highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  reserved_local_peer(State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},P.next_peer(highwater))

def block_action_executed(restore:Cooking.Sidecar -> Shell,record:PR.Record,palette:Maybe<&2,W.Palette>,region:W.Bounds,cache:Maybe<&2,W.SnapshotCache>,buttons:PI.Buttons,mouse:MI.State,options:MI.Options,receiver:Inside.Receiver,error:Maybe<&2,String>,state_tail:List<&1,X.State>,motion_tail:List<&1,MH.State>,metadata_tail:List<&2,X.Metadata>,result:G.Engine & Cooking.Sidecar & T.Tables & BI.Outcome) -> State & BI.Outcome:
  (engine,cooking,tables,outcome) = result
  (State{R.attach(engine,record,R.Detached{tables,palette,region,cache,buttons,mouse,options, receiver, error,state_tail,motion_tail,metadata_tail}),restore(cooking)},outcome)

def block_action_detached(shell:Shell,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,result:G.Engine & PR.Record & R.Detached) -> State & BI.Outcome:
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking} = shell
  (engine,+record,R.Detached{tables,palette,region,cache,buttons,mouse,options, receiver, error,state_tail,motion_tail,metadata_tail}) = result
  block_action_executed(cooking => Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},
    record,palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail,
    BI.execute_with_owner(Cooking.Sidecar,CookingEdit.edit,cooking,engine,record,tables,abilities,held,cap,sequence,button))

def block_action_record(abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,shell:Shell,result:X.State & Result<&2,&2,String,PR.Record>) -> State & BI.Outcome:
  (player,status) = result
  match status:
    case Fail{message}: (State{player,shell},BI.Outcome{False{},message})
    case Done{record}: block_action_detached(shell,abilities,held,cap,sequence,button,R.detach(player))

def block_action_abilities(player:X.State,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,cooking:Cooking.Sidecar,result:I.State & I.Abilities) -> State & BI.Outcome:
  (inventory,abilities) = result
  block_action_record(abilities,held,cap,sequence,button,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},R.record_checked(player))

def block_action_selected(cap:C.Capability,sequence:Nat,button:U32,result:State & Inv.Slot) -> State & BI.Outcome:
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},held) = result
  block_action_abilities(player,held,cap,sequence,button,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,cooking,I.abilities(inventory))

def block_action(state:State,cap:C.Capability,sequence:Nat,button:U32) -> State & BI.Outcome:
  block_action_selected(cap,sequence,button,inventory_selected(state))

def clock_core(registry:B.Registry,view:W.View,result:C.World & C.Clock) -> W.State & C.Clock:
  (world,clock) = result
  (W.attach(G.Engine{world,registry},view),clock)

def clock_world(result:G.Engine & W.View) -> W.State & C.Clock:
  (G.Engine{world,registry},view) = result
  clock_core(registry,view,C.clock(world))

def clock_read(world:W.State) -> W.State & C.Clock:
  clock_world(W.take(world))

def clock_response(session:L.Session,id:String,result:State & C.Clock) -> State & L.Session & J.Value:
  (state,clock) = result
  success(state,session,id,L.clock_value(clock))

def stepped(advance:State -> U32 -> State,state:State,session:L.Session,id:String,result:Result<&2,&2,L.Fault,L.Command>) -> State & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(state,session,id,fault)
    case Done{L.StepCommand{ticks}}:
      clock_response(session,id,query(C.Clock,advance(state,ticks),p => R.query(C.Clock,p,clock_read)))
    case _: failure(state,session,id,L.bad("InvalidArguments","expected a simulation step command"))

def step_checked(advance:State -> U32 -> State,state:State,session:L.Session,id:String,args:J.Value,valid:Bool,allowed:Bool) -> State & L.Session & J.Value:
  match valid allowed:
    case False{} _: failure(state,session,id,L.bad("InvalidArguments","arguments or scheduled at field do not match the operation schema"))
    case True{} False{}: failure(state,session,id,L.bad("PermissionDenied","developer capability required"))
    case True{} True{}: stepped(advance,state,session,id,L.decode(L.StepTicks{},args))

# Intercept the real reserved core operation. Each individual tick applies due
# edits then player physics; delegating to Core.advance would skip interleaving.
def step_envelope(advance:State -> U32 -> State,state:State,session:L.Session,envelope:L.Envelope) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,+capability} = session
  L.Envelope{id,op,+args,at} = envelope
  step_checked(advance,observed(state,peer),L.Session{peer,1n+sequence,capability},id,args,L.validate_args(args,[L.Field{"ticks",L.Unsigned{1,1000},True{}}]) && Maybe.is_none(&2,Nat,at),C.developer(capability))

def stepped_io(advance:State -> U32 -> IO(State),state:State,session:L.Session,id:String,
    result:Result<&2,&2,L.Fault,L.Command>) -> IO(State & L.Session & J.Value):
  match result:
    case Fail{fault}: IO.pure(State & L.Session & J.Value,failure(state,session,id,fault))
    case Done{L.StepCommand{ticks}}:
      do IO<State & L.Session & J.Value>:
        advanced : State <- advance(state,ticks)
        return clock_response(session,id,query(C.Clock,advanced,p => R.query(C.Clock,p,clock_read)))
    case _: IO.pure(State & L.Session & J.Value,
      failure(state,session,id,L.bad("InvalidArguments","expected a simulation step command")))

def step_checked_io(advance:State -> U32 -> IO(State),state:State,session:L.Session,id:String,args:J.Value,
    valid:Bool,allowed:Bool) -> IO(State & L.Session & J.Value):
  match valid allowed:
    case False{} _: IO.pure(State & L.Session & J.Value,
      failure(state,session,id,L.bad("InvalidArguments","arguments or scheduled at field do not match the operation schema")))
    case True{} False{}: IO.pure(State & L.Session & J.Value,
      failure(state,session,id,L.bad("PermissionDenied","developer capability required")))
    case True{} True{}: stepped_io(advance,state,session,id,L.decode(L.StepTicks{},args))

# Authority/sequence/schema semantics match step_envelope. Each admitted tick's
# delivery IO finishes before the next tick in an explicit multi-step request.
def step_envelope_io(advance:State -> U32 -> IO(State),state:State,session:L.Session,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Session{+peer,sequence,+capability} = session
  L.Envelope{id,op,+args,at} = envelope
  step_checked_io(advance,observed(state,peer),L.Session{peer,1n+sequence,capability},id,args,
    L.validate_args(args,[L.Field{"ticks",L.Unsigned{1,1000},True{}}]) && Maybe.is_none(&2,Nat,at),C.developer(capability))

# The durable codec cannot see transient ownership tails. Check the complete
# runtime only after the existing save/inspect schema and capability gates.
# Other requests keep the unconditional detach/attach owner-preserving path.
def record_refused(state:State,session:L.Session,id:String,code:String,message:String) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,capability} = session
  failure(observed(state,peer),L.Session{peer,1n+sequence,capability},id,L.bad(code,message))

def from_cooking_bundle(stored:E.State<CookingStorage.Saved>,transient:R.Transient) -> State:
  E.State{base,CookingStorage.Saved{saved,bodies,pending,entities,publication},maximum,catalog} = stored
  from_bundle(E.State{base,saved,maximum,catalog},transient)

def cooking_inventory_answer(bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,publication:Maybe<&2,PublicationCodec.Recovery>,result:G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>) -> G.Engine & CookingStorage.Saved & Result<&2,&2,L.Fault,J.Value>:
  (engine,saved,status) = result
  (engine,CookingStorage.Saved{saved,bodies,pending,entities,publication},status)

def cooking_inventory_dispatch(engine:G.Engine,saved:CookingStorage.Saved,session:L.Session,envelope:L.Envelope) -> G.Engine & CookingStorage.Saved & Result<&2,&2,L.Fault,J.Value>:
  CookingStorage.Saved{player,bodies,pending,entities,publication} = saved
  cooking_inventory_answer(bodies,pending,entities,publication,inventory_operation_dispatch(engine,player,session,envelope))

def cooking_inventory_operations() -> E.Operations<CookingStorage.Saved>:
  E.Operations{inventory_catalog,cooking_inventory_dispatch}

def cooking_dispatched(transient:R.Transient,result:E.State<CookingStorage.Saved> & L.Session & J.Value) -> State & L.Session & J.Value:
  (stored,session,value) = result
  (from_cooking_bundle(stored,transient),session,value)

def cooking_save_acknowledged(state:State,snapshot:PublicationJournal.Snapshot) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,
    CookingPublication.save_completed(cooking,Done{PublicationJournal.FullCookingSaveCommitted{snapshot}})}}

def cooking_save_committed(state:State,snapshot:Maybe<&2,PublicationJournal.Snapshot>) -> State:
  match snapshot:
    case None{}: state
    case Some{value}: cooking_save_acknowledged(state,value)

# The actual typed durable receipt is the first admission gate. JSON success,
# a missing snapshot and an unsynced publication cannot acknowledge a journal.
def cooking_save_completed(state:State,snapshot:Maybe<&2,PublicationJournal.Snapshot>,completion:E.SaveCompletion) -> State:
  match completion:
    case E.NotCommitted{}: state
    case E.DurablyCommitted{}: cooking_save_committed(state,snapshot)

def cooking_saved(transient:R.Transient,snapshot:Maybe<&2,PublicationJournal.Snapshot>,
    result:E.State<CookingStorage.Saved> & L.Session & J.Value & E.SaveCompletion) -> State & L.Session & J.Value:
  (stored,session,value,completion) = result
  (cooking_save_completed(from_cooking_bundle(stored,transient),snapshot,completion),session,value)

def cooking_delegate_bundle(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,publication:Maybe<&2,PublicationCodec.Recovery>,snapshot:Maybe<&2,PublicationJournal.Snapshot>,+session:L.Session,id:String,
    result:E.State<IC.Saved> & R.Transient) -> IO(State & L.Session & J.Value):
  L.Session{+peer,sequence,capability} = session
  (E.State{base,saved,maximum,catalog},transient) = result
  do IO<State & L.Session & J.Value>:
    result : E.State<CookingStorage.Saved> & L.Session & J.Value & E.SaveCompletion <-
      E.save_codec_receipt(~CookingStorage.Saved,
        CookingStorage.codec_with(definitions,False{},WG.legacy()),
        E.observe(CookingStorage.Saved,E.State{base,CookingStorage.Saved{saved,bodies,pending,entities,publication},maximum,catalog},peer),
        L.Session{peer,1n+sequence,capability},id)
    return cooking_saved(transient,snapshot,result)

def cooking_save_prepared(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,session:L.Session,id:String,state:State,
    value:Maybe<&2,PublicationOwner.Prepared>) -> IO(State & L.Session & J.Value):
  match value:
    case None{}: cooking_delegate_bundle(definitions,bodies,pending,entities,None{},None{},session,id,to_bundle(state))
    case Some{PublicationOwner.Prepared{publication,snapshot}}:
      cooking_delegate_bundle(definitions,bodies,pending,entities,Some{publication},Some{snapshot},session,id,to_bundle(state))

def cooking_save_publication(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,session:L.Session,id:String,
    result:State & Maybe<&2,PublicationOwner.Prepared>) -> IO(State & L.Session & J.Value):
  (state,publication) = result
  cooking_save_prepared(definitions,bodies,pending,entities,session,id,state,publication)

def cooking_save_entities(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,session:L.Session,id:String,
    result:State & Maybe<&2,CookingStorage.EntityRecovery>) -> IO(State & L.Session & J.Value):
  (state,entities) = result
  cooking_save_publication(definitions,bodies,pending,entities,session,id,cooking_prepare_publication_save(state))

def cooking_save_pending(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,session:L.Session,id:String,
    result:State & List<&2,CookingStore.Effect>) -> IO(State & L.Session & J.Value):
  (state,pending) = result
  cooking_save_entities(definitions,bodies,pending,session,id,cooking_entities(state))

def cooking_save_definitions(bodies:List<&2,CookingStorage.Body>,session:L.Session,id:String,
    result:State & D.Catalog) -> IO(State & L.Session & J.Value):
  (state,definitions) = result
  cooking_save_pending(definitions,bodies,session,id,cooking_pending(state))

def cooking_save_collected(session:L.Session,token:String,request:J.Value,id:String,
    result:State & Result<&2,&2,String,List<&2,CookingStorage.Body>>) -> IO(State & L.Session & J.Value):
  (state,status) = result
  match status:
    case Fail{message}: IO.pure(State & L.Session & J.Value,record_refused(state,session,id,"SaveEncodingFailed",message))
    case Done{bodies}: cooking_save_definitions(bodies,session,id,inventory_definitions(state))

def cooking_save(state:State,session:L.Session,token:String,request:J.Value,id:String) -> IO(State & L.Session & J.Value):
  cooking_save_collected(session,token,request,id,cooking_bodies(state))

def record_dispatch(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String) -> IO(State & L.Session & J.Value):
  match code:
    case "SaveEncodingFailed": cooking_save(state,session,token,request,id)
    case _: delegate(state,session,token,request)

def record_runtime_checked(shell:Shell,session:L.Session,token:String,request:J.Value,id:String,code:String,result:X.State & Result<&2,&2,String,PR.Record>) -> IO(State & L.Session & J.Value):
  (player,status) = result
  match status:
    case Fail{message}: IO.pure(State & L.Session & J.Value,record_refused(State{player,shell},session,id,code,message))
    case Done{record}: record_dispatch(State{player,shell},session,token,request,id,code)

def record_admitted(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String) -> IO(State & L.Session & J.Value):
  State{player,shell} = state
  record_runtime_checked(shell,session,token,request,id,code,R.record_checked(player))

def record_valid(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String,valid:Bool,permitted:Bool) -> IO(State & L.Session & J.Value):
  match valid permitted:
    case True{} True{}: record_admitted(state,session,token,request,id,code)
    case _ _: delegate(state,session,token,request)

def save_envelope(state:State,+session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"SaveEncodingFailed",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),C.developer(L.capability(session)))

def inspect_envelope(state:State,session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"InvalidPlayerState",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),True{})

def parsed(advance:State -> U32 -> State,state:State,session:L.Session,token:String,request:J.Value,result:Result<&2,&2,L.Fault,L.Envelope>) -> IO(State & L.Session & J.Value):
  match result:
    case Done{envelope}:
      L.Envelope{id,+op,args,at} = envelope
      match op:
        case "simulation.step": IO.pure(State & L.Session & J.Value,step_envelope(advance,state,session,L.Envelope{id,op,args,at}))
        case "world.save": save_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case "player.inspect": inspect_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case _: delegate(state,session,token,request)
    case _: delegate(state,session,token,request)

def dispatch_using(advance:State -> U32 -> State,state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  parsed(advance,state,session,token,request,L.envelope(request))

def parsed_io(advance:State -> U32 -> IO(State),state:State,session:L.Session,token:String,request:J.Value,
    result:Result<&2,&2,L.Fault,L.Envelope>) -> IO(State & L.Session & J.Value):
  match result:
    case Done{envelope}:
      L.Envelope{id,+op,args,at} = envelope
      match op:
        case "simulation.step": step_envelope_io(advance,state,session,L.Envelope{id,op,args,at})
        case "world.save": save_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case "player.inspect": inspect_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case _: delegate(state,session,token,request)
    case _: delegate(state,session,token,request)

def dispatch_using_io(advance:State -> U32 -> IO(State),state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  parsed_io(advance,state,session,token,request,L.envelope(request))

def dispatch(~driver:R.Driver,state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  dispatch_using(state => ticks => advance(~driver,state,ticks),state,session,token,request)

type Ready is Type:
  Ready{state:State,first_peer:U32}

def startup_closed(message:String,result:Result<&1,&1,U32 & String,Unit>) -> IO(Ready):
  match result:
    case Fail{(code,cause)}: IO.die(Ready,1,"player session startup refused: " ++ message ++ "; lease release: " ++ cause)
    case Done{unit}: IO.die(Ready,1,"player session startup refused: " ++ message)

def startup_failed(shell:Shell,message:String) -> IO(Ready):
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking} = shell
  do IO<Ready>:
    result : Result<&1,&1,U32 & String,Unit> <- WL.release(lease)
    startup_closed(message,result)

def startup_restored(shell:Shell,first_peer:U32,result:X.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (player,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: IO.pure(Ready,Ready{State{player,shell},first_peer})

def startup_world(shell:Shell,first_peer:U32,tables:T.Tables,record:PR.Record,result:W.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (world,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: startup_restored(shell,first_peer,R.restore(R.fresh(world,tables),record))

def startup_base(base:P.State,record:PR.Record,maximum:U32,catalog:List<&2,E.Operation>,first_peer:U32,tables:T.Tables) -> IO(Ready):
  P.State{engine,identity,path,highwater,limits,lease} = base
  startup_world(Shell{identity,path,highwater,limits,lease,maximum,catalog,I.new(),False{},WG.legacy(),Cooking.empty()},first_peer,tables,record,W.new(engine))

# Caller loads the closed PS codec/operations before adoption. The supplied
# Tables are the pinned owned sine lookup. Palette failure closes the save lease.
def new(ready:E.Ready<PR.Record>,tables:T.Tables) -> IO(Ready):
  E.Ready{E.State{base,record,maximum,catalog},first_peer} = ready
  startup_base(base,record,maximum,catalog,first_peer,tables)

def startup_inventory_validated(shell:Shell,first_peer:U32,tables:T.Tables,engine:G.Engine,result:Result<&2,&2,PR.Error,PR.Record>) -> IO(Ready):
  match result:
    case Fail{error}: startup_failed(shell,PR.error_text(error))
    case Done{record}: startup_world(shell,first_peer,tables,record,W.new(engine))

def startup_inventory_base(base:P.State,saved:IC.Saved,maximum:U32,catalog:List<&2,E.Operation>,first_peer:U32,tables:T.Tables) -> IO(Ready):
  P.State{engine,identity,path,highwater,limits,lease} = base
  IC.Saved{record,inventory,fresh,generation} = saved
  startup_inventory_validated(Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,Cooking.empty()},first_peer,tables,engine,PR.validate(record))

def new_inventory(ready:E.Ready<IC.Saved>,tables:T.Tables) -> IO(Ready):
  E.Ready{E.State{base,saved,maximum,catalog},first_peer} = ready
  startup_inventory_base(base,saved,maximum,catalog,first_peer,tables)

# Pending body bytes remain with Entry until its real context/bootstrap and
# discovery succeed. No transient fallback or second durable save is created.
def new_cooking_inventory(ready:E.Ready<CookingStorage.Saved>,tables:T.Tables) -> IO(Ready & List<&2,CookingStorage.Body> & List<&2,CookingStore.Effect> & Maybe<&2,CookingStorage.EntityRecovery> & Maybe<&2,PublicationCodec.Recovery>):
  E.Ready{E.State{base,CookingStorage.Saved{saved,bodies,pending,entities,publication},maximum,catalog},first_peer} = ready
  do IO<Ready & List<&2,CookingStorage.Body> & List<&2,CookingStore.Effect> & Maybe<&2,CookingStorage.EntityRecovery> & Maybe<&2,PublicationCodec.Recovery>>:
    ready : Ready <- startup_inventory_base(base,saved,maximum,catalog,first_peer,tables)
    return (ready,bodies,pending,entities,publication)

def returned_bundle(result:E.State<IC.Saved> & R.Transient) -> State:
  (stored,transient) = result
  from_bundle(stored,transient)


law bundle_transfer_preserves_all_local_runtime_and_save_fields:
  for state:State
  {returned_bundle(to_bundle(state)) == state : State}

def bundle_transfer_preserves_all_local_runtime_and_save_fields(state):
  match state:
    case State{X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,H.State{history},motion_tail},tables,
      X.Metadata{local,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
        CT.Controller{buttons,look,mouse,options},entity, receiver, error,metadata_tail},state_tail},
      Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}}: {==}
