import Base
import ./local_player_session.bend as S
import ./local_player_cooking.bend as K
import ./local_player_cooking_edit.bend as Edit
import ./local_player_runtime.bend as R
import ./local_player_record.bend as Record
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./player_block_inside_stuck.bend as Inside
import ./player_block_interaction.bend as BI
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_input.bend as Input
import ./mouse_input.bend as Mouse
import ./client_world.bend as W
import ./core.bend as C
import ./game.bend as G
import ./locomotion.bend as Motion
import ./persistence.bend as P
import ./world_lock.bend as Lock
import ./extended_persistence.bend as E
import ./world_generation_settings.bend as Generation

# The live continuation must publish the actual returned affine owners even
# when Outcome reports a refusal. Its closure retains every unrelated saved
# player owner; this pure constructor boundary is independently exportable.
law block_action_result_installs_returned_owners_and_retains_complete_session:
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:Lock.Lease
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for inventory:I.State
  for fresh:Bool
  for generation:Generation.Settings
  for record:Record.Record
  for palette:Maybe<&2,W.Palette>
  for region:W.Bounds
  for cache:Maybe<&2,W.SnapshotCache>
  for buttons:Input.Buttons
  for mouse:Mouse.State
  for options:Mouse.Options
  for receiver:Inside.Receiver
  for error:Maybe<&2,String>
  for state_tail:List<&1,X.State>
  for motion_tail:List<&1,MH.State>
  for metadata_tail:List<&2,X.Metadata>
  for returned_engine:G.Engine
  for returned_cooking:K.Sidecar
  for returned_tables:Motion.Tables
  for outcome:BI.Outcome
  {S.block_action_executed(
      cooking => S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},
      record,palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail,
      (returned_engine,returned_cooking,returned_tables,outcome)) ==
    (S.State{R.attach(returned_engine,record,
        R.Detached{returned_tables,palette,region,cache,buttons,mouse,options,receiver,error,
          state_tail,motion_tail,metadata_tail}),
      S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,returned_cooking}},outcome) :
    S.State & BI.Outcome}

# This is the actual saved-player block-action consumer. The premise names the
# complete result of the real BI owner path, including a refused Outcome. It
# does not reconstruct or copy the Core, cooking arrays, entity/RNG carrier or
# geometry catalog. Arbitrary cooking and runtime tails remain in their owners.
law block_action_publishes_actual_returned_owners_and_retains_complete_session:
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:Lock.Lease
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for inventory:I.State
  for fresh:Bool
  for generation:Generation.Settings
  for cooking:K.Sidecar
  for abilities:I.Abilities
  for held:Inv.Slot
  for cap:C.Capability
  for sequence:Nat
  for button:U32
  for engine:G.Engine
  for record:Record.Record
  for tables:Motion.Tables
  for palette:Maybe<&2,W.Palette>
  for region:W.Bounds
  for cache:Maybe<&2,W.SnapshotCache>
  for buttons:Input.Buttons
  for mouse:Mouse.State
  for options:Mouse.Options
  for receiver:Inside.Receiver
  for error:Maybe<&2,String>
  for state_tail:List<&1,X.State>
  for motion_tail:List<&1,MH.State>
  for metadata_tail:List<&2,X.Metadata>
  for returned_engine:G.Engine
  for returned_cooking:K.Sidecar
  for returned_tables:Motion.Tables
  for outcome:BI.Outcome
  for supplied:{BI.execute_with_owner(K.Sidecar,Edit.edit,cooking,engine,record,tables,
      abilities,held,cap,sequence,button) ==
      (returned_engine,returned_cooking,returned_tables,outcome) :
      G.Engine & K.Sidecar & Motion.Tables & BI.Outcome}
  {S.block_action_detached(
      S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},
      abilities,held,cap,sequence,button,
      (engine,record,R.Detached{tables,palette,region,cache,buttons,mouse,options,receiver,error,
        state_tail,motion_tail,metadata_tail})) ==
    (S.State{R.attach(returned_engine,record,
        R.Detached{returned_tables,palette,region,cache,buttons,mouse,options,receiver,error,
          state_tail,motion_tail,metadata_tail}),
      S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,returned_cooking}},outcome) :
    S.State & BI.Outcome}
