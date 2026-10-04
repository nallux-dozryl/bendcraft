import Base
import ./local_player_cooking.bend as K
import ./local_player_session.bend as Session
import ./core.bend as C
import ./section_map.bend as Sections
import ./schedule.bend as Q
import ./block_light.bend as Light
import ./block_light_world.bend as BW
import ./block_light_registry.bend as LR
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./cooking_effect_delivery.bend as Delivery
import ./nbt.bend as N
import ./registry.bend as B
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./movement.bend as M
import ./support.bend as SP
import ./client_world.bend as W
import ./locomotion.bend as L
import ./game.bend as G
import ./persistence.bend as P
import ./world_lock.bend as WL
import ./extended_persistence.bend as E
import ./player_inventory.bend as I
import ./world_generation_settings.bend as WG

# These gates preserve arbitrary complete affine owners, including queued light
# work, physical furnace arrays, pending cooking effects and retained details.
# They do not assert rollback after a cooking tick has accepted a Core batch.
law already_initialized_begin_retains_complete_cooking_owner:
  for world:C.World
  for context:K.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for sidecar_tail:List<&1,K.Sidecar>
  for replacement:K.Context
  {K.begin(world,K.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},replacement) ==
    (world,K.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},Fail{"local-cooking:already-initialized"}) :
    C.World & K.Sidecar & Result<&2,&2,String,Unit>}

# Pausing an idle owner without a scheduled tick does not discover sections,
# drain light, advance Core clocks, inspect item arrays or consume effects.
# The public context admission remains an explicit independent premise.
law paused_idle_tick_retains_complete_cooking_owner:
  for tick:Nat
  for time:Nat
  for daylight:Bool
  for revision:Nat
  for +count:U32
  for sections:Sections.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for +context:K.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for sidecar_tail:List<&1,K.Sidecar>
  for admitted:{K.context_counts(count,context) == True{} : Bool}
  {K.tick(C.World{tick,time,True{},daylight,revision,count,sections,pending,events},
      K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},False{}) ==
    (C.World{tick,time,True{},daylight,revision,count,sections,pending,events},
      K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},Done{False{}}) :
    C.World & K.Sidecar & Result<&2,&2,String,Bool>}

# A forged nonempty Context tail refuses before the physical save supplier.
# In particular this retains details even when phase contains OwnerReset.
law noncanonical_context_save_retains_complete_cooking_owner:
  for world:C.World
  for registry:LR.Catalog
  for enabled:Map<&2,Bool>
  for cooking:CW.Context
  for head:K.Context
  for tail:List<&2,K.Context>
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for sidecar_tail:List<&1,K.Sidecar>
  for position:C.Position
  for limits:N.Limits
  for cap:C.Capability
  {K.save_body(world,K.Initialized{K.Context{registry,enabled,cooking,head <> tail},
      light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},position,limits,cap) ==
    (world,K.Initialized{K.Context{registry,enabled,cooking,head <> tail},
      light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},Fail{"local-cooking:invalid-context"}) :
    C.World & K.Sidecar & Result<&2,&2,String,List<&2,U32>>}

# This is the actual Session detour, not a smaller view or copied world.
# The sole premise is the operation's complete returned Core/Sidecar/status.
# Success and failure both publish that returned owner, since an accepted
# cooking tick can commit Core before a later supplier refuses its finish.
# Registry, tables, inventory, lease and every owned/Data runtime tail remain.
# Arbitrary input/returned Sidecar includes incarnation counters, reset ack
# and its complete recursively boxed affine tail.
law cooking_query_publishes_supplied_owner_and_retains_complete_session:
  for world:C.World
  for registry:B.Registry
  for body:M.Body
  for yaw:F32
  for pitch:F32
  for palette:Maybe<&2,W.Palette>
  for region:W.Bounds
  for cache:Maybe<&2,W.SnapshotCache>
  for support:SP.State
  for minor:LM.MinorState
  for history:H.History
  for motion_tail:List<&1,MH.State>
  for tables:L.Tables
  for metadata:X.Metadata
  for state_tail:List<&1,X.State>
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:WL.Lease
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for inventory:I.State
  for fresh:Bool
  for generation:WG.Settings
  for cooking:K.Sidecar
  for returned_world:C.World
  for returned_cooking:K.Sidecar
  for status:Result<&2,&2,String,Unit>
  for operation:C.World -> K.Sidecar -> C.World & K.Sidecar & Result<&2,&2,String,Unit>
  for supplied:{operation(world,cooking) == (returned_world,returned_cooking,status) :
    C.World & K.Sidecar & Result<&2,&2,String,Unit>}
  {Session.cooking_query(Unit,
      Session.State{X.State{MH.State{W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache},
        support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
        Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},operation) ==
    (Session.State{X.State{MH.State{W.State{G.Engine{returned_world,registry},body,yaw,pitch,palette,region,cache},
        support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
        Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,returned_cooking}},status) :
    Session.State & Result<&2,&2,String,Unit>}

# A container transaction also publishes its actual returned inventory owner.
# No copy, snapshot reconstruction or successful-status premise is involved.
law cooking_inventory_query_publishes_all_supplied_owners_and_retains_session:
  for world:C.World
  for registry:B.Registry
  for body:M.Body
  for yaw:F32
  for pitch:F32
  for palette:Maybe<&2,W.Palette>
  for region:W.Bounds
  for cache:Maybe<&2,W.SnapshotCache>
  for support:SP.State
  for minor:LM.MinorState
  for history:H.History
  for motion_tail:List<&1,MH.State>
  for tables:L.Tables
  for metadata:X.Metadata
  for state_tail:List<&1,X.State>
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:WL.Lease
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for inventory:I.State
  for fresh:Bool
  for generation:WG.Settings
  for cooking:K.Sidecar
  for returned_world:C.World
  for returned_cooking:K.Sidecar
  for returned_inventory:I.State
  for status:Result<&2,&2,String,Unit>
  for operation:C.World -> K.Sidecar -> I.State -> C.World & K.Sidecar & I.State & Result<&2,&2,String,Unit>
  for supplied:{operation(world,cooking,inventory) == (returned_world,returned_cooking,returned_inventory,status) :
    C.World & K.Sidecar & I.State & Result<&2,&2,String,Unit>}
  {Session.cooking_inventory_query(Unit,
      Session.State{X.State{MH.State{W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache},
        support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
        Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}},operation) ==
    (Session.State{X.State{MH.State{W.State{G.Engine{returned_world,registry},body,yaw,pitch,palette,region,cache},
        support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
        Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,returned_inventory,fresh,generation,returned_cooking}},status) :
    Session.State & Result<&2,&2,String,Unit>}

# Actual delivery decides which released prefix needs no missing supplier.
# Its pending suffix and status are returned verbatim; the physical and
# lifecycle owners are neither reconstructed from a snapshot nor discarded.
law pending_delivery_installs_actual_suffix_and_preserves_complete_sidecar:
  for context:K.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for +effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for sidecar_tail:List<&1,K.Sidecar>
  for +pending:List<&2,Store.Effect>
  for +status:Result<&2,&2,String,Unit>
  for supplied:{Delivery.deliver(effects) == Delivery.Outcome{pending,status} : Delivery.Outcome}
  {K.deliver_pending(K.Initialized{context,light,loading,entries,phase,keys,effects,details,
      incarnations,acknowledged_resets,sidecar_tail}) ==
    (K.Initialized{context,light,loading,entries,phase,keys,pending,details,
      incarnations,acknowledged_resets,sidecar_tail},status) :
    K.Sidecar & Result<&2,&2,String,Unit>}

# An admitted scheduled tick refuses a recursive child owner before Core
# clocks, queued mutations, light work or cooking arrays can be changed.
law noncanonical_tail_active_tick_retains_complete_cooking_owner:
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for revision:Nat
  for +count:U32
  for sections:Sections.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for +context:K.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for child:K.Sidecar
  for sidecar_tail:List<&1,K.Sidecar>
  for admitted:{K.context_counts(count,context) == True{} : Bool}
  {K.tick(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
      K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,
        incarnations,acknowledged_resets,child <> sidecar_tail},True{}) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
      K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,
        incarnations,acknowledged_resets,child <> sidecar_tail},Fail{"local-cooking:noncanonical-sidecar-tail"}) :
    C.World & K.Sidecar & Result<&2,&2,String,Bool>}
