import Base
import ./local_player_cooking_session_edit_laws.bend as Laws
import ./local_player_session.bend as S
import ./local_player_runtime.bend as R
import ./local_player_cooking.bend as K
import ./local_player_cooking_edit.bend as Edit
import ./player_block_interaction.bend as BI
import ./game.bend as G
import ./locomotion.bend as Motion

def Laws.block_action_result_installs_returned_owners_and_retains_complete_session(
    identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,record,
    palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail,
    returned_engine,returned_cooking,returned_tables,outcome):
  {==}

def Laws.block_action_publishes_actual_returned_owners_and_retains_complete_session(
    identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking,
    abilities,held,cap,sequence,button,engine,record,tables,palette,region,cache,buttons,mouse,
    options,receiver,error,state_tail,motion_tail,metadata_tail,
    returned_engine,returned_cooking,returned_tables,outcome,supplied):
  %Equal.sym(G.Engine & K.Sidecar & Motion.Tables & BI.Outcome,
    BI.execute_with_owner(K.Sidecar,Edit.edit,cooking,engine,record,tables,
      abilities,held,cap,sequence,button),
    (returned_engine,returned_cooking,returned_tables,outcome),supplied) :
    {S.block_action_executed(
        cooking => S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking},
        record,palette,region,cache,buttons,mouse,options,receiver,error,
        state_tail,motion_tail,metadata_tail,_) ==
      (S.State{R.attach(returned_engine,record,
          R.Detached{returned_tables,palette,region,cache,buttons,mouse,options,receiver,error,
            state_tail,motion_tail,metadata_tail}),
        S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,returned_cooking}},outcome) :
      S.State & BI.Outcome}
  {==}
