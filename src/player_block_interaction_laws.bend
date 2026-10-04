import Base
import ./core.bend as C
import ./game.bend as G
import ./player_core_edit.bend as Edit
import ./player_block_interaction.bend as BI
import ./locomotion.bend as T
import ./local_player_record.bend as Record
import ./player_inventory.bend as I
import ./inventory.bend as Inv

# These are contracts of the actual actor-owned operation. Equality covers the
# entire affine Engine and Tables, including their arrays; no copied model of
# the world or sine table is substituted for the production owners.
import ./player_core_edit_laws.bend as CoreEditLaws

def owners(result:G.Engine & T.Tables & BI.Outcome) -> G.Engine & T.Tables:
  (engine,tables,outcome) = result
  (engine,tables)

law unauthorized_action_rollback:
  for engine:G.Engine
  for record:Record.Record
  for tables:T.Tables
  for abilities:I.Abilities
  for held:Inv.Slot
  for +cap:C.Capability
  for sequence:Nat
  for button:U32
  for denied:{Edit.player_peer(cap) == None{} : Maybe<&2,U32>}
  {BI.execute(engine,record,tables,abilities,held,cap,sequence,button) ==
    (engine,tables,BI.Outcome{False{},"interaction:permission-denied"}) : G.Engine & T.Tables & BI.Outcome}

law observer_action_rollback:
  for engine:G.Engine
  for record:Record.Record
  for tables:T.Tables
  for abilities:I.Abilities
  for held:Inv.Slot
  for sequence:Nat
  for button:U32
  {BI.execute(engine,record,tables,abilities,held,C.Observer{},sequence,button) ==
    (engine,tables,BI.Outcome{False{},"interaction:permission-denied"}) : G.Engine & T.Tables & BI.Outcome}

law invalid_player_action_rollback:
  for engine:G.Engine
  for record:Record.Record
  for tables:T.Tables
  for abilities:I.Abilities
  for held:Inv.Slot
  for sequence:Nat
  for button:U32
  {BI.execute(engine,record,tables,abilities,held,C.Player{0},sequence,button) ==
    (engine,tables,BI.Outcome{False{},"interaction:permission-denied"}) : G.Engine & T.Tables & BI.Outcome}

law disabled_build_action_checked_owners:
  for engine:G.Engine
  for record:Record.Record
  for tables:T.Tables
  for instabuild:Bool
  for held:Inv.Slot
  for cap:C.Capability
  for sequence:Nat
  for button:U32
  for authorized:Bool
  {owners(BI.execute_checked(engine,record,tables,I.Abilities{instabuild,False{}},held,cap,sequence,button,authorized)) ==
    (engine,tables) : G.Engine & T.Tables}

law disabled_build_action_owners:
  for engine:G.Engine
  for record:Record.Record
  for tables:T.Tables
  for instabuild:Bool
  for held:Inv.Slot
  for +cap:C.Capability
  for sequence:Nat
  for button:U32
  {owners(BI.execute(engine,record,tables,I.Abilities{instabuild,False{}},held,cap,sequence,button)) ==
    (engine,tables) : G.Engine & T.Tables}

