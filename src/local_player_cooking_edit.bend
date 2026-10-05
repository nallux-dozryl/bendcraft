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

def initialized(world:C.World,sidecar:K.Sidecar,cap:C.Capability,position:C.Position,state:U32,
    expected:Nat,sequence:Nat,maybuild:Bool) -> C.World & K.Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case K.Uninitialized{}: (world,K.Uninitialized{},Fail{"local-cooking:uninitialized"})
    case K.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,entity_owner,tail}:
      returned(K.with_owner(~List<&2,Store.Effect>,world,
        K.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,entity_owner,tail},
        cooking => owner => E.player_edit(~K.Context,~K.properties,~K.enabled,context,cooking,owner,
          cap,position,state,expected,sequence,maybuild)))

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
