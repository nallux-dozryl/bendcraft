import Base
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./local_player_cooking.bend as K
import ./local_player_cooking_entity_owner.bend as Owner
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_edit.bend as E
import ./cooking_world_store.bend as Store
import ./cooking_world_bindings.bend as Bindings
import ./campfire_authority_items.bend as AI
import ./local_player_cooking_incarnation_guard.bend as Incarnation
import ./player_core_edit.bend as P
import ./player_block_interaction.bend as BI

# A direct player edit uses the same sole Core and initialized lighting/cooking
# owners as a scheduled edit. The registry/residency suppliers are the retained
# actor Context; a caller cannot replace an unknown descriptor with invented air.
# Geometry is a retained catalog/environment, with captures made per effect.

def released(context:K.Context,light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,Store.Entry>,
    phase:CW.Phase,keys:List<&2,String>,previous:List<&2,Store.Effect>,acknowledged:Nat,
    entity_owner:Owner.Carrier,tail:List<&1,K.Sidecar>,+effects:List<&2,Store.Effect>,walk:K.ResetWalk) -> K.Sidecar:
  K.ResetWalk{details,incarnations,remaining,seen} = walk
  K.Initialized{context,light,loading,entries,phase,keys,
    List.append(&2,Store.Effect,previous,effects),details,incarnations,acknowledged,entity_owner,tail}

def publish(sidecar:K.Sidecar,+effects:List<&2,Store.Effect>) -> K.Sidecar:
  match sidecar:
    case K.Uninitialized{}: K.Uninitialized{}
    case K.Initialized{context,light,loading,entries,phase,keys,previous,details,incarnations,acknowledged,entity_owner,tail}:
      released(context,light,loading,entries,phase,keys,previous,acknowledged,entity_owner,tail,effects,
        K.reset_events(effects,K.ResetWalk{details,incarnations,0n,0n}))

def returned(result:C.World & K.Sidecar & Result<&2,&2,String,List<&2,Store.Effect>>) ->
    C.World & K.Sidecar & Result<&2,&2,String,Unit>:
  match result:
    case (world,sidecar,Fail{message}): (world,sidecar,Fail{message})
    case (world,sidecar,Done{effects}): (world,publish(sidecar,effects),Done{Unit{}})

# Reuse the scheduled guard's exact first-entry lifecycle classification. Only
# immutable headers are projected; no Core, light or cooking owner is copied.
def reset_capacity(result:Map<&2,Nat> & Nat) -> Bool:
  (retained,current) = result
  Nat.is_lt(current,Incarnation.maximum())

def capacity(incarnations:Map<&2,Nat>,change:Incarnation.Change) -> Bool:
  match change:
    case Incarnation.Change{headers,None{}}: True{}
    case Incarnation.Change{headers,Some{position}}:
      reset_capacity(Map.get(Nat,0n,incarnations,Bindings.key(position)))

def capacity_checked(world:W.State,entries:List<&1,Store.Entry>,views:List<&2,Store.View>,
    operation:W.Prepared,classification:Bindings.Classification,cap:C.Capability,position:C.Position,state:U32,
    expected:Nat,sequence:Nat,maybuild:Bool,allowed:Bool) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  match allowed:
    case False{}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Authority{"incarnation-exhausted"}})
    case True{}: E.world_apply(world,operation,position,state,cap,expected,sequence,maybuild,classification,entries,views)

def player_read(light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,Store.Entry>,+views:List<&2,Store.View>,
    operation:W.Prepared,+classification:Bindings.Classification,incarnations:Map<&2,Nat>,
    cap:C.Capability,+position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    result:C.World & Result<&2,&2,C.Error,U32>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{CW.Player{P.CoreError{error}}})
    case Done{old}:
      capacity_checked(W.State{world,light,loading},entries,views,operation,classification,cap,position,state,expected,sequence,maybuild,
        capacity(incarnations,Incarnation.change(Incarnation.headers(views),position,classification)))

def player_validated(world:W.State,entries:List<&1,Store.Entry>,views:List<&2,Store.View>,
    operation:W.Prepared,classification:Bindings.Classification,incarnations:Map<&2,Nat>,
    cap:C.Capability,+position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    status:Result<&2,&2,C.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  W.State{owner,light,loading} = world
  match status:
    case Fail{error}: (CW.State{W.State{owner,light,loading},entries,CW.Idle{},[]},Fail{CW.Player{P.CoreError{error}}})
    case Done{unit}:
      player_read(light,loading,entries,views,operation,classification,incarnations,cap,position,state,expected,sequence,maybuild,
        C.read_block(owner,position))

def player_current(world:W.State,entries:List<&1,Store.Entry>,views:List<&2,Store.View>,
    operation:W.Prepared,classification:Bindings.Classification,incarnations:Map<&2,Nat>,
    cap:C.Capability,+position:C.Position,+state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    revision:Nat,count:U32,positive:Bool,matching:Bool) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  match positive matching:
    case False{} _: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Player{P.InvalidSequence{}}})
    case True{} False{}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Player{P.StaleRevision{expected,revision}}})
    case True{} True{}: player_validated(world,entries,views,operation,classification,incarnations,cap,position,state,expected,sequence,maybuild,
      C.validate(C.BlockSet{position,state},count))

def classified(world:W.State,entries:List<&1,Store.Entry>,views:List<&2,Store.View>,operation:W.Prepared,
    incarnations:Map<&2,Nat>,cap:C.Capability,position:C.Position,state:U32,+expected:Nat,+sequence:Nat,maybuild:Bool,
    status:Result<&2,&2,String,Bindings.Classification>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  W.State{C.World{tick,time,paused,daylight,+revision,+count,sections,pending,events},light,loading} = world
  match status:
    case Fail{message}: (CW.State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,CW.Idle{},[]},Fail{CW.Authority{message}})
    case Done{classification}:
      player_current(W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},
        entries,views,operation,classification,incarnations,cap,position,state,expected,sequence,maybuild,revision,count,
        Nat.is_gt(sequence,0n),Nat.is_eq(expected,revision))

def prepared(world:W.State,entries:List<&1,Store.Entry>,views:List<&2,Store.View>,catalog:Bindings.Catalog,
    incarnations:Map<&2,Nat>,cap:C.Capability,position:C.Position,+state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    status:Result<&2,&2,W.Error,W.Prepared>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  match status:
    case Fail{error}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.World{error}})
    case Done{operation}: classified(world,entries,views,operation,incarnations,cap,position,state,expected,sequence,maybuild,
      Bindings.classify(catalog,state))

def resident(context:K.Context,catalog:Bindings.Catalog,entries:List<&1,Store.Entry>,+views:List<&2,Store.View>,
    incarnations:Map<&2,Nat>,cap:C.Capability,+position:C.Position,+state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    result:W.State & Result<&2,&2,CW.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  (world,status) = result
  W.State{C.World{tick,time,paused,daylight,revision,+count,sections,pending,events},light,loading} = world
  match status:
    case Fail{error}: (CW.State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,CW.Idle{},[]},Fail{error})
    case Done{unit}:
      prepared(W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,views,catalog,
        incarnations,cap,position,state,expected,sequence,maybuild,
        W.checked_prepare(~K.Context,~K.properties,~K.enabled,context,C.BlockSet{position,state},C.validate(C.BlockSet{position,state},count)))

def inspected(context:K.Context,catalog:Bindings.Catalog,world:W.State,incarnations:Map<&2,Nat>,
    cap:C.Capability,position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool,
    result:List<&1,Store.Entry> & Result<&2,&2,String,List<&2,Store.View>>) -> CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  (entries,status) = result
  match status:
    case Fail{message}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Authority{message}})
    case Done{+views}: resident(context,catalog,entries,views,incarnations,cap,position,state,expected,sequence,maybuild,
      CW.resident(views,world))

# Match the existing CWEdit admission order before checking reset capacity.
# Sequence, revision and actual resident reads precede the new overflow refusal.
# Only the final admitted branch calls the original prepared mutation once.
def operation(context:K.Context,cooking:CW.Context,owner:CW.State,incarnations:Map<&2,Nat>,
    cap:C.Capability,position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool) ->
    CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = cooking
  match owner:
    case CW.State{world,entries,CW.Cooking{tick,effects},keys}:
      (CW.State{world,entries,CW.Cooking{tick,effects},keys},Fail{CW.Busy{}})
    case CW.State{world,entries,CW.Idle{},key <> rest}:
      (CW.State{world,entries,CW.Idle{},key <> rest},Fail{CW.Loading{}})
    case CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},Nil{}}:
      (CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},[]},Fail{CW.World{W.LoadingInProgress{}}})
    case CW.State{world,entries,CW.Idle{},Nil{}}:
      inspected(context,catalog,world,incarnations,cap,position,state,expected,sequence,maybuild,Store.inspect(recipes,entries))

def initialized(world:C.World,sidecar:K.Sidecar,cap:C.Capability,position:C.Position,state:U32,
    expected:Nat,sequence:Nat,maybuild:Bool) -> C.World & K.Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case K.Uninitialized{}: (world,K.Uninitialized{},Fail{"local-cooking:uninitialized"})
    case K.Initialized{+context,light,loading,entries,phase,keys,effects,details,+incarnations,acknowledged,entity_owner,tail}:
      returned(K.with_owner(~List<&2,Store.Effect>,world,
        K.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,entity_owner,tail},
        cooking => owner => operation(context,cooking,owner,incarnations,cap,position,state,expected,sequence,maybuild)))

def admitted(world:C.World,sidecar:K.Sidecar,cap:C.Capability,position:C.Position,state:U32,
    expected:Nat,sequence:Nat,maybuild:Bool,allowed:Bool) -> C.World & K.Sidecar & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (world,sidecar,Fail{"local-cooking:interaction:permission-denied"})
    case True{}: initialized(world,sidecar,cap,position,state,expected,sequence,maybuild)

def player_edit(world:C.World,sidecar:K.Sidecar,+cap:C.Capability,position:C.Position,state:U32,
    expected:Nat,sequence:Nat,+maybuild:Bool) -> C.World & K.Sidecar & Result<&2,&2,String,Unit>:
  admitted(world,sidecar,cap,position,state,expected,sequence,maybuild,
    maybuild && Maybe.is_some(&2,U32,P.player_peer(cap)))

def edited(registry:B.Registry,result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) ->
    G.Engine & K.Sidecar & BI.Outcome:
  match result:
    case (world,sidecar,Fail{message}): (G.Engine{world,registry},sidecar,BI.Outcome{False{},message})
    case (world,sidecar,Done{unit}): (G.Engine{world,registry},sidecar,BI.Outcome{True{},""})

def clocked(registry:B.Registry,sidecar:K.Sidecar,authority:BI.Authority,position:C.Position,state:U32,
    result:C.World & C.Clock) -> G.Engine & K.Sidecar & BI.Outcome:
  BI.Authority{cap,sequence,maybuild} = authority
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  edited(registry,player_edit(world,sidecar,cap,position,state,revision,sequence,maybuild))

# Supplier for BI.execute_with_owner. It receives the current authoritative
# Engine after the actual ray and placement checks, then performs exactly one
# same-owner edit. Legacy BI.execute remains available with its original edit.
def edit(authority:BI.Authority,engine:G.Engine,sidecar:K.Sidecar,position:C.Position,state:U32) ->
    G.Engine & K.Sidecar & BI.Outcome:
  G.Engine{world,registry} = engine
  clocked(registry,sidecar,authority,position,state,C.clock(world))
