import Base
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as BW
import ./block_light_registry.bend as LR
import ./cooking_world.bend as CW
import ./cooking_world_actor.bend as Actor
import ./cooking_world_tick.bend as Tick
import ./cooking_world_store.bend as Store
import ./cooking_world_bindings.bend as Bindings
import ./cooking_world_persistence.bend as Persistence
import ./cooking_block_entity_codec.bend as CB
import ./nbt.bend as N
import ./player_core_edit.bend as Edit
import ./player_inventory.bend as I

# Catalogs must come from the authenticated registry loaders and the same
# initialized recipe/item/fuel reload. The tail is an explicit canonical gate.
# Section keys use BW's complete dimension/raw-coordinate representation.
type Context is Data:
  Context{registry:LR.Catalog,enabled_sections:Map<&2,Bool>,cooking:CW.Context,
    tail:List<&2,Context>}
type BodyDetails is Data:
  BodyDetails{position:C.Position,details:CB.Details}
type Lifecycle is Data:
  Lifecycle{details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,acknowledged_resets:Nat}
type ResetWalk is Data:
  ResetWalk{details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,remaining:Nat,seen:Nat}

# There is no Core, Engine, Body, or copied inventory in this sidecar. Each
# operation temporarily joins the caller's sole Core with these actual owners.
type Sidecar is Type:
  Uninitialized{}
  Initialized{context:Context,light:L.State,light_loading:Maybe<&2,BW.Cursor>,
    entities:List<&1,Store.Entry>,phase:CW.Phase,keys:List<&2,String>,
    effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,
    incarnations:Map<&2,Nat>,acknowledged_resets:Nat}

def empty() -> Sidecar:
  Uninitialized{}

def cooking_context(context:Context) -> CW.Context:
  Context{registry,sections,cooking,tail} = context
  cooking

def properties(context:Context,state:U32) -> Maybe<&2,L.Descriptor>:
  Context{registry,sections,cooking,tail} = context
  LR.properties(registry,state)

def enabled_value(result:Map<&2,Bool> & Bool) -> Bool:
  (sections,value) = result
  value

# Absent keys are disabled by the explicit section policy, never unknown air.
def enabled(context:Context,position:C.Position) -> Bool:
  Context{registry,sections,cooking,tail} = context
  enabled_value(Map.get(Bool,False{},sections,L.key(BW.origin(position))))

def occludes(context:Context,source:L.Descriptor,target:L.Descriptor,direction:L.Direction) -> Bool:
  Context{registry,sections,cooking,tail} = context
  LR.occludes(registry,source,target,direction)

def context_counts(count:U32,context:Context) -> Bool:
  match context:
    case Context{LR.Catalog{+identity,+states,shapes,rows,faces},sections,
      CW.Context{Bindings.Catalog{other,cooking_states,bindings},campfire,fuel,depth},Nil{}}:
      Bool.not(String.is_empty(identity)) && String.eq(identity,other) &&
        U32.is_gt(states,0) && U32.is_eq(states,count) && U32.is_eq(states,cooking_states)
    case _: False{}

def checked_world(world:C.World,context:Context) -> C.World & Bool:
  C.World{tick,time,paused,daylight,revision,+count,sections,pending,events} = world
  (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},context_counts(count,context))

def position_text(position:C.Position) -> String:
  Bindings.key(position)

def core_error(error:C.Error) -> String:
  match error:
    case C.PermissionDenied{}: "permission-denied"
    case C.UnknownDimension{dimension}: "unknown-dimension:" ++ dimension
    case C.InvalidState{state}: "invalid-state:" ++ U32.show(state)
    case C.MissingSection{key}: "missing-section:" ++ key
    case C.SectionExists{key}: "section-exists:" ++ key
    case C.InvalidCoordinate{}: "invalid-coordinate"
    case C.PastTick{}: "past-tick"
    case C.TooManyPending{}: "too-many-pending"

def light_error(error:BW.Error) -> String:
  match error:
    case BW.CoreFailure{error}: "core:" ++ core_error(error)
    case BW.LoadingInProgress{}: "light-loading"
    case BW.MissingDescriptor{state}: "missing-light-descriptor:" ++ U32.show(state)
    case BW.InvalidDescriptor{state}: "invalid-light-descriptor:" ++ U32.show(state)
    case BW.InvalidSectionKey{key}: "invalid-section-key:" ++ key
    case BW.LightPending{pending}: "light-pending:" ++ Nat.show(pending)
    case BW.ResidencyMismatch{position}: "light-residency:" ++ position_text(position)

def error_text(error:CW.Error) -> String:
  match error:
    case CW.Busy{}: "local-cooking:pending-tick"
    case CW.Loading{}: "local-cooking:section-discovery"
    case CW.Authority{message}: "local-cooking:authority:" ++ message
    case CW.World{error}: "local-cooking:" ++ light_error(error)
    case CW.Player{error}: "local-cooking:" ++ Edit.error_text(error)
    case CW.EntityMismatch{position}: "local-cooking:entity-mismatch:" ++ position_text(position)

def details_remove_head(+head:BodyDetails,position:C.Position,+rest:List<&2,BodyDetails>) -> List<&2,BodyDetails>:
  BodyDetails{candidate,details} = head
  Bool.pick(List<&2,BodyDetails>,Bindings.equal_position(candidate,position),rest,head <> rest)

def details_remove(values:List<&2,BodyDetails>,+position:C.Position) -> List<&2,BodyDetails>:
  match values:
    case Nil{}: []
    case head <> rest: details_remove_head(head,position,details_remove(rest,position))

def incarnation_incremented(key:String,result:Map<&2,Nat> & Nat) -> Map<&2,Nat>:
  (values,previous) = result
  Map.set(&2,Nat,values,key,1n+previous)

def incarnation_increment(values:Map<&2,Nat>,+key:String) -> Map<&2,Nat>:
  incarnation_incremented(key,Map.get(Nat,0n,values,key))

def reset_marker(+position:C.Position,walk:ResetWalk) -> ResetWalk:
  match walk:
    case ResetWalk{details,incarnations,0n,seen}:
      ResetWalk{details_remove(details,position),incarnation_increment(incarnations,Bindings.key(position)),0n,1n+seen}
    case ResetWalk{details,incarnations,1n+remaining,seen}:
      ResetWalk{details,incarnations,remaining,1n+seen}

# Acknowledgement counts only OwnerReset markers. Other effects cannot shift
# the skipped prefix. Markers remain in their original effect sequence.
def reset_events(effects:List<&2,Store.Effect>,walk:ResetWalk) -> ResetWalk:
  match effects:
    case Nil{}: walk
    case Store.OwnerReset{position} <> rest: reset_events(rest,reset_marker(position,walk))
    case other <> rest: reset_events(rest,walk)

def reset_observed(previous:Nat,walk:ResetWalk) -> Lifecycle:
  ResetWalk{details,incarnations,remaining,seen} = walk
  Lifecycle{details,incarnations,Nat.max(previous,seen)}

def lifecycle_effects(lifecycle:Lifecycle,effects:List<&2,Store.Effect>) -> Lifecycle:
  Lifecycle{details,incarnations,+acknowledged} = lifecycle
  reset_observed(acknowledged,reset_events(effects,ResetWalk{details,incarnations,acknowledged,0n}))

def lifecycle_phase(phase:CW.Phase,lifecycle:Lifecycle) -> Lifecycle:
  match phase:
    case CW.Idle{}: lifecycle
    case CW.Cooking{tick,effects}: lifecycle_effects(lifecycle,effects)

def lifecycle_completed(lifecycle:Lifecycle) -> Lifecycle:
  Lifecycle{details,incarnations,acknowledged} = lifecycle
  Lifecycle{details,incarnations,0n}

def installed(context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,entries:List<&1,Store.Entry>,
    phase:CW.Phase,keys:List<&2,String>,effects:List<&2,Store.Effect>,lifecycle:Lifecycle) -> Sidecar:
  Lifecycle{details,incarnations,acknowledged_resets} = lifecycle
  Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}

def split_result(~A:Data,context:Context,effects:List<&2,Store.Effect>,lifecycle:Lifecycle,
    result:CW.State & Result<&2,&2,CW.Error,A>) -> C.World & Sidecar & Result<&2,&2,String,A>:
  match result:
    case (CW.State{BW.State{world,light,loading},entries,+phase,keys},Fail{error}):
      (world,installed(context,light,loading,entries,phase,keys,effects,lifecycle),Fail{error_text(error)})
    case (CW.State{BW.State{world,light,loading},entries,+phase,keys},Done{value}):
      (world,installed(context,light,loading,entries,phase,keys,effects,lifecycle_phase(phase,lifecycle)),Done{value})

def operation_checked(~A:Data,+context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,
    entries:List<&1,Store.Entry>,phase:CW.Phase,keys:List<&2,String>,effects:List<&2,Store.Effect>,
    details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,acknowledged_resets:Nat,
    operation:CW.Context -> CW.State -> CW.State & Result<&2,&2,CW.Error,A>,
    result:C.World & Bool) -> C.World & Sidecar & Result<&2,&2,String,A>:
  match result:
    case (world,False{}):
      (world,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:invalid-context"})
    case (world,True{}):
      split_result(~A,context,effects,Lifecycle{details,incarnations,acknowledged_resets},
        operation(cooking_context(context),CW.State{BW.State{world,light,loading},entries,phase,keys}))

# Generic same-owner seam for subsequent slot/edit consumers. Returned effects
# remain the operation's result; only tick appends its released effects here.
def with_owner(~A:Data,world:C.World,sidecar:Sidecar,
    operation:CW.Context -> CW.State -> CW.State & Result<&2,&2,CW.Error,A>) ->
    C.World & Sidecar & Result<&2,&2,String,A>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      operation_checked(~A,context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,operation,checked_world(world,context))

def inventory_returned(-A:Data,context:Context,effects:List<&2,Store.Effect>,lifecycle:Lifecycle,
    result:CW.State & I.State & Result<&2,&2,String,A>) ->
    C.World & Sidecar & I.State & Result<&2,&2,String,A>:
  match result:
    case (CW.State{BW.State{world,light,loading},entries,phase,keys},inventory,Fail{message}):
      (world,installed(context,light,loading,entries,phase,keys,effects,lifecycle),inventory,Fail{message})
    case (CW.State{BW.State{world,light,loading},entries,+phase,keys},inventory,Done{value}):
      (world,installed(context,light,loading,entries,phase,keys,effects,lifecycle_phase(phase,lifecycle)),inventory,Done{value})

def inventory_started(-A:Data,world:C.World,sidecar:Sidecar,inventory:I.State,
    operation:CW.Context -> CW.State -> I.State -> CW.State & I.State & Result<&2,&2,String,A>) ->
    C.World & Sidecar & I.State & Result<&2,&2,String,A>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},inventory,Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      inventory_returned(A,context,effects,Lifecycle{details,incarnations,acknowledged_resets},
        operation(cooking_context(context),CW.State{BW.State{world,light,loading},entries,phase,keys},inventory))

def inventory_checked(-A:Data,sidecar:Sidecar,inventory:I.State,
    operation:CW.Context -> CW.State -> I.State -> CW.State & I.State & Result<&2,&2,String,A>,
    result:C.World & Bool) -> C.World & Sidecar & I.State & Result<&2,&2,String,A>:
  match result:
    case (world,False{}): (world,sidecar,inventory,Fail{"local-cooking:invalid-context"})
    case (world,True{}): inventory_started(A,world,sidecar,inventory,operation)

# The actual player inventory and every cooking array move through the supplied
# operation once. Its String status and returned owners pass through unchanged.
def with_inventory_owner(-A:Data,world:C.World,sidecar:Sidecar,inventory:I.State,
    operation:CW.Context -> CW.State -> I.State -> CW.State & I.State & Result<&2,&2,String,A>) ->
    C.World & Sidecar & I.State & Result<&2,&2,String,A>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},inventory,Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      inventory_checked(A,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},
        inventory,operation,checked_world(world,context))

def begin_checked(+context:Context,result:C.World & Bool) -> C.World & Sidecar & Result<&2,&2,String,Unit>:
  match result:
    case (world,False{}): (world,Uninitialized{},Fail{"local-cooking:invalid-context"})
    case (world,True{}): split_result(~Unit,context,[],Lifecycle{[],Map.new(&2,Nat),0n},(CW.begin(BW.begin(world)),Done{Unit{}}))

def begin(world:C.World,sidecar:Sidecar,+context:Context) -> C.World & Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Uninitialized{}: begin_checked(context,checked_world(world,context))
    case installed: (world,installed,Fail{"local-cooking:already-initialized"})

def loading_status(world:C.World,sidecar:Sidecar) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{context,light,+loading,entries,phase,+keys,effects,details,incarnations,acknowledged_resets}:
      (world,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},
        Done{Maybe.is_none(&2,BW.Cursor,loading) && List.is_empty(&2,String,keys)})

def loading_light_result(context:Context,entries:List<&1,Store.Entry>,phase:CW.Phase,
    keys:List<&2,String>,effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,acknowledged_resets:Nat,
    result:BW.State & Result<&2,&2,BW.Error,Unit>) -> C.World & Sidecar & Result<&2,&2,String,Unit>:
  match result:
    case (BW.State{world,light,loading},Fail{error}):
      (world,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:" ++ light_error(error)})
    case (BW.State{world,light,loading},Done{unit}):
      (world,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},Done{unit})

def loading_round(world:C.World,sidecar:Sidecar) -> C.World & Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,Some{cursor},entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      loading_light_result(context,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
        BW.load_resume(~Context,~properties,~enabled,context,1n,BW.State{world,light,Some{cursor}}))
    case Initialized{context,light,None{},entries,phase,Nil{},effects,details,incarnations,acknowledged_resets}:
      (world,Initialized{context,light,None{},entries,phase,[],effects,details,incarnations,acknowledged_resets},Done{Unit{}})
    case Initialized{+context,light,None{},entries,phase,key <> rest,effects,details,incarnations,acknowledged_resets}:
      split_result(~Unit,context,effects,Lifecycle{details,incarnations,acknowledged_resets},
        CW.load_next(cooking_context(context),CW.State{BW.State{world,light,None{}},entries,phase,key <> rest}))

def loading_continue(done:Bool,world:C.World,sidecar:Sidecar,
    next:C.World -> Sidecar -> C.World & Sidecar & Result<&2,&2,String,Bool>) ->
    C.World & Sidecar & Result<&2,&2,String,Bool>:
  match done:
    case True{}: (world,sidecar,Done{True{}})
    case False{}: next(world,sidecar)

def loading_observed(result:C.World & Sidecar & Result<&2,&2,String,Bool>,
    next:C.World -> Sidecar -> C.World & Sidecar & Result<&2,&2,String,Bool>) ->
    C.World & Sidecar & Result<&2,&2,String,Bool>:
  match result:
    case (world,sidecar,Fail{message}): (world,sidecar,Fail{message})
    case (world,sidecar,Done{done}): loading_continue(done,world,sidecar,next)

def loading_return(result:C.World & Sidecar & Result<&2,&2,String,Unit>,
    next:C.World -> Sidecar -> C.World & Sidecar & Result<&2,&2,String,Bool>) ->
    C.World & Sidecar & Result<&2,&2,String,Bool>:
  match result:
    case (world,sidecar,Fail{message}): (world,sidecar,Fail{message})
    case (world,sidecar,Done{unit}): loading_observed(loading_status(world,sidecar),next)

# One fuel unit is one BW bootstrap unit or one whole CW section discovery.
# A zero budget reports incomplete success without discarding either cursor.
def loading_go(budget:Nat,world:C.World,sidecar:Sidecar) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match budget:
    case 0n: loading_status(world,sidecar)
    case 1n+rest:
      loading_return(loading_round(world,sidecar),world => sidecar => loading_go(rest,world,sidecar))

def loading_phase(world:C.World,sidecar:Sidecar,budget:Nat) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets}:
      (world,Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets},Fail{"local-cooking:pending-tick"})
    case installed: loading_go(budget,world,installed)

def loading_checked(sidecar:Sidecar,budget:Nat,result:C.World & Bool) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match result:
    case (world,False{}): (world,sidecar,Fail{"local-cooking:invalid-context"})
    case (world,True{}): loading_phase(world,sidecar,budget)

def resume_loading(world:C.World,sidecar:Sidecar,budget:Nat) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      loading_checked(Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},budget,checked_world(world,context))

def light_advanced(context:Context,entries:List<&1,Store.Entry>,phase:CW.Phase,keys:List<&2,String>,
    effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,acknowledged_resets:Nat,result:BW.State & BW.Progress) ->
    C.World & Sidecar & Result<&2,&2,String,BW.Progress>:
  (BW.State{world,light,loading},progress) = result
  (world,Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},Done{progress})

def light_running(world:C.World,sidecar:Sidecar,budget:Nat) -> C.World & Sidecar & Result<&2,&2,String,BW.Progress>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      light_advanced(context,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
        BW.advance(~Context,~occludes,context,budget,BW.State{world,light,loading}))

def light_checked(sidecar:Sidecar,budget:Nat,result:C.World & Bool) -> C.World & Sidecar & Result<&2,&2,String,BW.Progress>:
  match result:
    case (world,False{}): (world,sidecar,Fail{"local-cooking:invalid-context"})
    case (world,True{}): light_running(world,sidecar,budget)

# Registry properties/enablement were used by bootstrap/publication. Advance
# uses their retained descriptors and the actual authenticated face table.
# It preserves Core's clock and every cooking phase, body and metadata owner.
def advance_light(world:C.World,sidecar:Sidecar,budget:Nat) -> C.World & Sidecar & Result<&2,&2,String,BW.Progress>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      light_checked(Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},budget,checked_world(world,context))

def completed(context:Context,effects:List<&2,Store.Effect>,lifecycle:Lifecycle,
    result:CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match result:
    case (CW.State{BW.State{world,light,loading},entries,+phase,keys},Fail{error}):
      (world,installed(context,light,loading,entries,phase,keys,effects,lifecycle_phase(phase,lifecycle)),Fail{error_text(error)})
    case (CW.State{BW.State{world,light,loading},entries,phase,keys},Done{+more}):
      (world,installed(context,light,loading,entries,phase,keys,List.append(&2,Store.Effect,effects,more),
        lifecycle_completed(lifecycle_effects(lifecycle,more))),Done{True{}})

def tick_selected(active:Bool,world:C.World,+context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,
    entries:List<&1,Store.Entry>,keys:List<&2,String>,effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,
    incarnations:Map<&2,Nat>,acknowledged_resets:Nat) ->
    C.World & Sidecar & Result<&2,&2,String,Bool>:
  match active:
    case False{}:
      (world,Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets},Done{False{}})
    case True{}:
      completed(context,effects,Lifecycle{details,incarnations,acknowledged_resets},Actor.started(~Context,~properties,~enabled,context,cooking_context(context),
        CW.start_tick(~Context,~properties,~enabled,context,cooking_context(context),
          CW.State{BW.State{world,light,loading},entries,CW.Idle{},keys})))

def tick_idle(world:C.World,scheduled:Bool,context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,
    entries:List<&1,Store.Entry>,keys:List<&2,String>,effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,
    incarnations:Map<&2,Nat>,acknowledged_resets:Nat) ->
    C.World & Sidecar & Result<&2,&2,String,Bool>:
  C.World{tick,time,+paused,daylight,revision,count,sections,pending,events} = world
  tick_selected(scheduled || Bool.not(paused),C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
    context,light,loading,entries,keys,effects,details,incarnations,acknowledged_resets)

def tick_ready(world:C.World,sidecar:Sidecar,scheduled:Bool) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets}:
      completed(context,released,Lifecycle{details,incarnations,acknowledged_resets},Tick.finish_tick(~Context,~properties,~enabled,context,cooking_context(context),
        CW.State{BW.State{world,light,loading},entries,CW.Cooking{tick,effects},keys}))
    case Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets}:
      tick_idle(world,scheduled,context,light,loading,entries,keys,effects,details,incarnations,acknowledged_resets)

def tick_checked(sidecar:Sidecar,scheduled:Bool,result:C.World & Bool) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match result:
    case (world,False{}): (world,sidecar,Fail{"local-cooking:invalid-context"})
    case (world,True{}): tick_ready(world,sidecar,scheduled)

# True releases one new/resumed cooking tick to the caller's common/player
# continuation. A failed finish can already have committed Core's clock/batch.
# Pending retries complete that original tick even when currently paused.
def tick(world:C.World,sidecar:Sidecar,scheduled:Bool) -> C.World & Sidecar & Result<&2,&2,String,Bool>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      tick_checked(Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},scheduled,checked_world(world,context))

def take_effects(sidecar:Sidecar) -> Sidecar & List<&2,Store.Effect>:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},[])
    case Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,loading,entries,phase,keys,[],details,incarnations,acknowledged_resets},effects)

# The legacy player bundle cannot encode a cooking owner or pending intents.
# This admission is temporary until the actor's physical body framing is used.
def save_admission(sidecar:Sidecar) -> Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},Done{Unit{}})
    case Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-pending-tick"})
    case Initialized{context,light,Some{cursor},entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,Some{cursor},entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-light-loading"})
    case Initialized{context,light,None{},entries,CW.Idle{},key <> rest,effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},entries,CW.Idle{},key <> rest,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-section-discovery"})
    case Initialized{context,light,None{},entry <> rest,CW.Idle{},Nil{},effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},entry <> rest,CW.Idle{},[],effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-physical-bodies-required"})
    case Initialized{context,light,None{},Nil{},CW.Idle{},Nil{},effects,detail <> rest,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},[],CW.Idle{},[],effects,detail <> rest,incarnations,acknowledged_resets},Fail{"local-cooking:save-body-details-required"})
    case Initialized{context,light,None{},Nil{},CW.Idle{},Nil{},effect <> rest,Nil{},incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},[],CW.Idle{},[],effect <> rest,[],incarnations,acknowledged_resets},Fail{"local-cooking:save-undelivered-effects"})
    case Initialized{context,light,None{},Nil{},CW.Idle{},Nil{},Nil{},Nil{},incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},[],CW.Idle{},[],[],[],incarnations,acknowledged_resets},Done{Unit{}})

# Complete physical framing may retain known bodies and their base/extras.
# Pending work and unreleased intents still cannot be silently omitted.
def persistence_ready(sidecar:Sidecar) -> Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},Done{Unit{}})
    case Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,loading,entries,CW.Cooking{tick,effects},keys,released,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-pending-tick"})
    case Initialized{context,light,Some{cursor},entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,Some{cursor},entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-light-loading"})
    case Initialized{context,light,None{},entries,CW.Idle{},key <> rest,effects,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},entries,CW.Idle{},key <> rest,effects,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-section-discovery"})
    case Initialized{context,light,None{},entries,CW.Idle{},Nil{},effect <> rest,details,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},entries,CW.Idle{},[],effect <> rest,details,incarnations,acknowledged_resets},Fail{"local-cooking:save-undelivered-effects"})
    case Initialized{context,light,None{},entries,CW.Idle{},Nil{},Nil{},details,incarnations,acknowledged_resets}:
      (Initialized{context,light,None{},entries,CW.Idle{},[],[],details,incarnations,acknowledged_resets},Done{Unit{}})

def positions_cons(head:Store.Entry,result:List<&1,Store.Entry> & List<&2,C.Position>) ->
    List<&1,Store.Entry> & List<&2,C.Position>:
  Store.Entry{+position,binding,entity} = head
  (rest,values) = result
  (Store.Entry{position,binding,entity} <> rest,position <> values)

def entry_positions(entries:List<&1,Store.Entry>) -> List<&1,Store.Entry> & List<&2,C.Position>:
  match entries:
    case Nil{}: ([],[])
    case head <> rest: positions_cons(head,entry_positions(rest))

def positions_done(context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,phase:CW.Phase,
    keys:List<&2,String>,effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,incarnations:Map<&2,Nat>,acknowledged_resets:Nat,
    result:List<&1,Store.Entry> & List<&2,C.Position>) -> Sidecar & List<&2,C.Position>:
  (entries,values) = result
  (Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},values)

def positions(sidecar:Sidecar) -> Sidecar & List<&2,C.Position>:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},[])
    case Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      positions_done(context,light,loading,phase,keys,effects,details,incarnations,acknowledged_resets,entry_positions(entries))

def incarnation_found(context:Context,light:L.State,loading:Maybe<&2,BW.Cursor>,entries:List<&1,Store.Entry>,
    phase:CW.Phase,keys:List<&2,String>,effects:List<&2,Store.Effect>,details:List<&2,BodyDetails>,acknowledged_resets:Nat,
    result:Map<&2,Nat> & Nat) -> Sidecar & Nat:
  (incarnations,value) = result
  (Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},value)

def incarnation(sidecar:Sidecar,position:C.Position) -> Sidecar & Nat:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},0n)
    case Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets}:
      incarnation_found(context,light,loading,entries,phase,keys,effects,details,acknowledged_resets,
        Map.get(Nat,0n,incarnations,Bindings.key(position)))

def details_replace(values:List<&2,BodyDetails>,+position:C.Position,+details:CB.Details) -> List<&2,BodyDetails>:
  match values:
    case Nil{}: [BodyDetails{position,details}]
    case BodyDetails{+candidate,+old} <> +rest:
      Bool.pick(List<&2,BodyDetails>,Bindings.equal_position(candidate,position),
        BodyDetails{candidate,details} <> rest,
        BodyDetails{candidate,old} <> details_replace(rest,position,details))

def details_found(values:List<&2,BodyDetails>,+position:C.Position) -> Maybe<&2,CB.Details>:
  match values:
    case Nil{}: None{}
    case BodyDetails{candidate,+details} <> rest:
      Bool.pick(Maybe<&2,CB.Details>,Bindings.equal_position(candidate,position),Some{details},details_found(rest,position))

def body_details(sidecar:Sidecar,position:C.Position) -> Sidecar & Maybe<&2,CB.Details>:
  match sidecar:
    case Uninitialized{}: (Uninitialized{},None{})
    case Initialized{context,light,loading,entries,phase,keys,effects,+details,incarnations,acknowledged_resets}:
      (Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets},details_found(details,position))

def details_at(sidecar:Sidecar,position:C.Position) -> Sidecar & Maybe<&2,CB.Details>:
  body_details(sidecar,position)

def loaded_ready(world:C.World,position:C.Position,+details:CB.Details,sidecar:Sidecar) ->
    C.World & Sidecar & Result<&2,&2,String,CB.Details>:
  match sidecar:
    case Uninitialized{}: (world,Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Initialized{context,light,loading,entries,phase,keys,effects,previous,incarnations,acknowledged_resets}:
      (world,Initialized{context,light,loading,entries,phase,keys,effects,details_replace(previous,position,details),incarnations,acknowledged_resets},Done{details})

def loaded_result(position:C.Position,result:C.World & Sidecar & Result<&2,&2,String,CB.Details>) ->
    C.World & Sidecar & Result<&2,&2,String,CB.Details>:
  match result:
    case (world,sidecar,Fail{message}): (world,sidecar,Fail{message})
    case (world,sidecar,Done{details}): loaded_ready(world,position,details,sidecar)

# Trusted physical loading uses the caller's actual capability; no player
# endpoint gains Developer authority. Metadata replaces its exact key only on
# success. Known-body save leaves original root/base extras with the actor.
def load_body(world:C.World,sidecar:Sidecar,+position:C.Position,limits:N.Limits,bytes:List<&2,U32>,cap:C.Capability) ->
    C.World & Sidecar & Result<&2,&2,String,CB.Details>:
  loaded_result(position,with_owner(~CB.Details,world,sidecar,
    context => owner => Persistence.load(context,owner,position,limits,bytes,cap)))

def save_body(world:C.World,sidecar:Sidecar,position:C.Position,limits:N.Limits,cap:C.Capability) ->
    C.World & Sidecar & Result<&2,&2,String,List<&2,U32>>:
  with_owner(~List<&2,U32>,world,sidecar,
    context => owner => Persistence.save(context,owner,position,limits,cap))
