import Base
import ./core.bend as C
import ./game.bend as G
import ./player_core_edit.bend as Edit
import ./player_block_interaction.bend as BI
import ./player_block_interaction_laws.bend as Laws
import ./locomotion.bend as T

import ./player_core_edit_proof.bend as CoreEditProof

def Laws.unauthorized_action_rollback(engine,record,tables,abilities,held,cap,sequence,button,denied):
  %Equal.sym(Maybe<&2,U32>,Edit.player_peer(cap),None{},denied) :
    {BI.execute_checked(engine,record,tables,abilities,held,cap,sequence,button,Maybe.is_some(&2,U32,_)) ==
      (engine,tables,BI.Outcome{False{},"interaction:permission-denied"}) : G.Engine & T.Tables & BI.Outcome}
  {==}

def Laws.observer_action_rollback(engine,record,tables,abilities,held,sequence,button):
  {==}

def Laws.invalid_player_action_rollback(engine,record,tables,abilities,held,sequence,button):
  {==}

def Laws.disabled_build_action_checked_owners(engine,record,tables,instabuild,held,cap,sequence,button,authorized):
  match instabuild authorized:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Laws.disabled_build_action_owners(engine,record,tables,instabuild,held,cap,sequence,button):
  Laws.disabled_build_action_checked_owners(engine,record,tables,instabuild,held,cap,sequence,button,Maybe.is_some(&2,U32,Edit.player_peer(cap)))

