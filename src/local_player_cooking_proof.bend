import Base
import ./local_player_cooking_laws.bend as Laws
import ./local_player_cooking.bend as K
import ./local_player_session.bend as Session
import ./core.bend as C
import ./cooking_world.bend as CW
import ./cooking_effect_delivery.bend as Delivery
import ./block_light_registry.bend as LR
import ./cooking_world_bindings.bend as Bindings
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./player_fall_history.bend as H
import ./client_world.bend as W
import ./game.bend as G
import ./local_player_runtime.bend as R
import ./local_player_record.bend as Record
import ./player_record.bend as Saved
import ./player_codec.bend as Codec
import ./player_runtime.bend as Plain
import ./player_controls.bend as Controls
import ./player_inventory_codec.bend as IC
import ./player_inventory.bend as I

def Laws.already_initialized_begin_retains_complete_cooking_owner(world,context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail,replacement):
  {==}

def Laws.paused_idle_tick_retains_complete_cooking_owner(tick,time,daylight,revision,count,sections,pending,events,context,light,loading,entries,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail,admitted):
  %Equal.sym(Bool,K.context_counts(count,context),True{},admitted) :
    {K.tick_checked(K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},False{},
      (C.World{tick,time,True{},daylight,revision,count,sections,pending,events},_)) ==
      (C.World{tick,time,True{},daylight,revision,count,sections,pending,events},
        K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,incarnations,acknowledged_resets,sidecar_tail},Done{False{}}) :
      C.World & K.Sidecar & Result<&2,&2,String,Bool>}
  {==}

def Laws.noncanonical_context_save_retains_complete_cooking_owner(world,registry,enabled,cooking,head,tail,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail,position,limits,cap):
  match world registry cooking:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}
      LR.Catalog{identity,states,shapes,rows,faces}
      CW.Context{Bindings.Catalog{other,cooking_states,bindings},campfire,fuel,depth}: {==}

def Laws.cooking_query_publishes_supplied_owner_and_retains_complete_session(world,registry,body,yaw,pitch,palette,region,cache,support,minor,history,motion_tail,tables,metadata,state_tail,identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking,returned_world,returned_cooking,status,operation,supplied):
  match metadata:
    case X.Metadata{local,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
      Controls.Controller{buttons,look,mouse,options},entity,receiver,error,metadata_tail}:
      %Equal.sym(C.World & K.Sidecar & Result<&2,&2,String,Unit>,operation(world,cooking),
        (returned_world,returned_cooking,status),supplied) :
        {Session.cooking_returned(Unit,registry,identity,path,highwater,limits,lease,
          IC.Saved{Record.Record{Saved.Record{Codec.Snapshot{
            Plain.compose(body,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head}),support,yaw,pitch,"minecraft:overworld"},look},
            local,sprinting,pose,minor,history,entity},inventory,fresh,generation},maximum,catalog,
          R.Detached{tables,palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail},_) ==
          (Session.State{X.State{MH.State{W.State{G.Engine{returned_world,registry},body,yaw,pitch,palette,region,cache},
              support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
              Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,returned_cooking}},status) :
          Session.State & Result<&2,&2,String,Unit>}
      {==}

def Laws.cooking_inventory_query_publishes_all_supplied_owners_and_retains_session(world,registry,body,yaw,pitch,palette,region,cache,support,minor,history,motion_tail,tables,metadata,state_tail,identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking,returned_world,returned_cooking,returned_inventory,status,operation,supplied):
  match metadata:
    case X.Metadata{local,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
      Controls.Controller{buttons,look,mouse,options},entity,receiver,error,metadata_tail}:
      %Equal.sym(C.World & K.Sidecar & I.State & Result<&2,&2,String,Unit>,operation(world,cooking,inventory),
        (returned_world,returned_cooking,returned_inventory,status),supplied) :
        {Session.cooking_inventory_returned(Unit,registry,identity,path,highwater,limits,lease,
          Record.Record{Saved.Record{Codec.Snapshot{
            Plain.compose(body,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head}),support,yaw,pitch,"minecraft:overworld"},look},
            local,sprinting,pose,minor,history,entity},fresh,generation,maximum,catalog,
          R.Detached{tables,palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail},_) ==
          (Session.State{X.State{MH.State{W.State{G.Engine{returned_world,registry},body,yaw,pitch,palette,region,cache},
              support,minor,H.State{history},motion_tail},tables,metadata,state_tail},
              Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,returned_inventory,fresh,generation,returned_cooking}},status) :
          Session.State & Result<&2,&2,String,Unit>}
      {==}

def Laws.pending_delivery_installs_actual_suffix_and_preserves_complete_sidecar(context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,sidecar_tail,pending,status,supplied):
  %Equal.sym(Delivery.Outcome,Delivery.deliver(effects),Delivery.Outcome{pending,status},supplied) :
    {K.pending_delivered(context,light,loading,entries,phase,keys,details,
        incarnations,acknowledged_resets,sidecar_tail,_) ==
      (K.Initialized{context,light,loading,entries,phase,keys,pending,details,
        incarnations,acknowledged_resets,sidecar_tail},status) :
      K.Sidecar & Result<&2,&2,String,Unit>}
  {==}

def Laws.noncanonical_tail_active_tick_retains_complete_cooking_owner(tick,time,paused,daylight,revision,count,sections,pending,events,context,light,loading,entries,keys,effects,details,incarnations,acknowledged_resets,child,sidecar_tail,admitted):
  %Equal.sym(Bool,K.context_counts(count,context),True{},admitted) :
    {K.tick_checked(K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,
        incarnations,acknowledged_resets,child <> sidecar_tail},True{},
      (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},_)) ==
      (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
        K.Initialized{context,light,loading,entries,CW.Idle{},keys,effects,details,
          incarnations,acknowledged_resets,child <> sidecar_tail},Fail{"local-cooking:noncanonical-sidecar-tail"}) :
      C.World & K.Sidecar & Result<&2,&2,String,Bool>}
  {==}
