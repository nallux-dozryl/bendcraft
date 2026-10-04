import Base
import ../src/inventory.bend as Inv
import ../src/player_inventory.bend as I
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/player_crafting_authority.bend as A
import ../src/crafting_recipe.bend as R
import ../src/player_crafting_authority_components.bend as M
import ../src/item_component.bend as C
import ../src/json.bend as J
import ./player_crafting_authority_fixtures.bend as F
import ./player_crafting_authority_observer.bend as Observe

def text(value:String) -> J.Value: J.JString{value}
def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}
def object(values:List<&2,J.Member>) -> J.Value: J.JObject{values}

def slot(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      object([J.JMember{"id",text(id)},J.JMember{"components",text(components)},J.JMember{"count",number(count)}])

def slots(values:List<&1,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: slot(value) <> slots(rest)

def data_slots(values:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: slot(value) <> data_slots(rest)

def maybe_slot(value:Maybe<&2,Inv.Slot>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{result}: slot(result)

def grid_value(grid:R.Grid) -> J.Value:
  R.Grid{width,height,cells} = grid
  object([J.JMember{"width",number(width)},J.JMember{"height",number(height)},J.JMember{"slots",J.JArray{data_slots(cells)}}])

def consumption(values:List<&2,R.Consumption>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Consumption{index,count,remainder} <> rest:
      object([J.JMember{"slot",number(index)},J.JMember{"count",number(count)},J.JMember{"remainder",slot(remainder)}]) <> consumption(rest)

def cache(value:Maybe<&2,R.Plan>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{R.Plan{id,result,R.Grid{width,height,cells},steps}}:
      object([J.JMember{"id",text(id)},J.JMember{"width",number(width)},J.JMember{"height",number(height)},J.JMember{"slots",J.JArray{data_slots(cells)}},J.JMember{"output",slot(result)},J.JMember{"consumption",J.JArray{consumption(steps)}}])

def abilities(ability:I.Abilities,status:I.Status) -> J.Value:
  I.Abilities{instabuild,maybuild} = ability
  I.Status{invulnerable,mayfly,flying,walking_speed,flying_speed} = status
  object([J.JMember{"instabuild",J.JBool{instabuild}},J.JMember{"maybuild",J.JBool{maybuild}},J.JMember{"invulnerable",J.JBool{invulnerable}},J.JMember{"mayfly",J.JBool{mayfly}},J.JMember{"flying",J.JBool{flying}},J.JMember{"walking_speed",number(walking_speed)},J.JMember{"flying_speed",number(flying_speed)}])

def append_table(owner:A.GridOwner,values:List<&2,J.Member>) -> List<&2,J.Member>:
  match owner:
    case A.PlayerGrid{}: J.JMember{"bench_logical_length",J.JNull{}} <> J.JMember{"bench_backing_slots",J.JNull{}} <> J.JMember{"bench_revision",J.JNull{}} <> values
    case A.TableGrid{Inv.Inventory{cells,length},revision}:
      J.JMember{"bench_logical_length",number(length)} <> J.JMember{"bench_backing_slots",J.JArray{slots(Array.to_list(~Inv.Slot,cells))}} <> J.JMember{"bench_revision",number(U32.from_nat(revision))} <> values

def reported(label:String,expected_definitions:D.Catalog,expected_recipes:R.Catalog,expected_mode:M.Mode,accepted:Bool,message:String,taken:Inv.Slot,result:A.State & A.Snapshot) -> IO(Unit):
  (A.State{I.State{Inv.Inventory{cells,length},selected,ability,I.Profile{+catalog,status,I.Menu{opened,revision,output}}},recipes,owner,cached,mode},A.Snapshot{snapshot,grid,previous}) = result
  IO.print(J.encode(object(append_table(owner,[J.JMember{"context_retained",J.JBool{Observe.context_same(expected_definitions,expected_recipes,expected_mode,catalog,recipes,mode)}},J.JMember{"id",text(label)},J.JMember{"accepted",J.JBool{accepted}},J.JMember{"message",text(message)},J.JMember{"selected",number(selected)},J.JMember{"abilities",abilities(ability,status)},J.JMember{"opened",J.JBool{opened}},J.JMember{"revision",number(U32.from_nat(revision))},J.JMember{"result",maybe_slot(output)},J.JMember{"logical_length",number(length)},J.JMember{"catalog_count",number(D.count(catalog))},J.JMember{"all_backing_slots",J.JArray{slots(Array.to_list(~Inv.Slot,cells))}},J.JMember{"grid",grid_value(grid)},J.JMember{"cache",cache(cached)},J.JMember{"taken",slot(taken)}]))))

def completed(label:String,expected_definitions:D.Catalog,expected_recipes:R.Catalog,expected_mode:M.Mode,result:A.State & Result<&2,&2,String,Inv.Slot>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: reported(label,expected_definitions,expected_recipes,expected_mode,False{},message,Inv.InvEmpty{},A.inspect(state))
    case Done{taken}: reported(label,expected_definitions,expected_recipes,expected_mode,True{},"",taken,A.inspect(state))

def changed_first(operation:U32,values:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  match operation values:
    case 2 Inv.InvStack{key,count} <> rest: Inv.InvStack{key,U32.inc(count)} <> rest
    case 3 Inv.InvStack{key,count} <> rest: Inv.InvStack{Inv.ItemKey{"minecraft:birch_planks",""},count} <> rest
    case 4 Inv.InvStack{Inv.ItemKey{id,components},count} <> rest: Inv.InvStack{Inv.ItemKey{id,"unvalidated component identity"},count} <> rest
    case _ _: values

def changed_steps(operation:U32,values:List<&2,R.Consumption>) -> List<&2,R.Consumption>:
  match operation values:
    case 7 R.Consumption{index,count,remainder} <> rest: R.Consumption{index,2,remainder} <> rest
    case 8 R.Consumption{index,count,remainder} <> rest: R.Consumption{index,count,Inv.InvStack{Inv.ItemKey{"minecraft:bucket",""},1}} <> rest
    case _ _: values

def changed_output(operation:U32,output:Inv.Slot) -> Inv.Slot:
  match operation output:
    case 6 Inv.InvStack{key,count}: Inv.InvStack{key,U32.inc(count)}
    case _ _: output

def changed_id(operation:U32,id:String) -> String:
  match operation:
    case 5: "fixture:forged_selection"
    case _: id

def changed_width(operation:U32,width:U32) -> U32:
  match operation:
    case 1: 3
    case _: width

def changed_cache(+operation:U32,cache:Maybe<&2,R.Plan>) -> Maybe<&2,R.Plan>:
  match operation cache:
    case 9 _: None{}
    case _ None{}: None{}
    case _ Some{R.Plan{id,output,R.Grid{width,height,slots},steps}}:
      Some{R.Plan{changed_id(operation,id),changed_output(operation,output),R.Grid{changed_width(operation,width),height,changed_first(operation,slots)},changed_steps(operation,steps)}}

def changed_player(operation:U32,player:I.State) -> I.State:
  match operation:
    case 10:
      I.State{inventory,selected,ability,I.Profile{definitions,status,I.Menu{opened,revision,output}}} = player
      I.State{inventory,selected,ability,I.Profile{definitions,status,I.Menu{False{},revision,output}}}
    case 30:
      I.State{Inv.Inventory{cells,length},selected,ability,profile} = player
      I.State{Inv.Inventory{cells,47},selected,ability,profile}
    case 31:
      I.State{inventory,selected,ability,profile} = player
      I.State{Inv.Inventory{Array.new(Inv.Slot,5n,Inv.InvEmpty{}),48},selected,ability,profile}
    case 32:
      I.State{Inv.Inventory{cells,length},selected,ability,profile} = player
      I.State{Inv.Inventory{ANode{ALeaf{Inv.InvEmpty{}},cells},48},selected,ability,profile}
    case _: player

def changed_owner(operation:U32,owner:A.GridOwner) -> A.GridOwner:
  match operation owner:
    case _ A.PlayerGrid{}: A.PlayerGrid{}
    case 33 A.TableGrid{Inv.Inventory{cells,length},revision}: A.TableGrid{Inv.Inventory{cells,8},revision}
    case 34 A.TableGrid{table,revision}: A.TableGrid{Inv.Inventory{Array.new(Inv.Slot,3n,Inv.InvEmpty{}),9},revision}
    case 35 A.TableGrid{Inv.Inventory{cells,length},revision}: A.TableGrid{Inv.Inventory{ANode{ALeaf{Inv.InvEmpty{}},cells},9},revision}
    case _ _: owner

def changed_state(+operation:U32,state:A.State) -> A.State:
  A.State{player,catalog,owner,cache,mode} = state
  A.State{changed_player(operation,player),catalog,changed_owner(operation,owner),changed_cache(operation,cache),mode}

def ready(label:String,button:U32,operation:U32,expected_definitions:D.Catalog,expected_recipes:R.Catalog,expected_mode:M.Mode,result:A.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: reported(label,expected_definitions,expected_recipes,expected_mode,False{},message,Inv.InvEmpty{},A.inspect(state))
    case Done{unit}: completed(label,expected_definitions,expected_recipes,expected_mode,A.take(changed_state(operation,state),button))

def table_tail() -> List<&2,Inv.Slot>:
  [Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},1},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},2},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},3},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},4},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},5},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},6},Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},7}]

def component_mode(operation:U32) -> M.Mode:
  match operation:
    case 20: M.TypedStew{C.InitializedSuspiciousStew{}}
    case _: M.DefaultOnly{}

def seed_table(table:Bool,player:I.State,catalog:R.Catalog,grid:R.Grid,mode:M.Mode) -> A.State:
  match table:
    case False{}: A.new_with_components(player,catalog,mode)
    case True{}:
      R.Grid{width,height,inputs} = grid
      A.State{player,catalog,A.TableGrid{I.write_returned(List.append(&2,Inv.Slot,inputs,table_tail()),0,Inv.Inventory{Array.new(Inv.Slot,4n,Inv.InvEmpty{}),9}),5n},None{},mode}

def execute(value:F.Case,+definitions:D.Catalog) -> IO(Unit):
  F.Case{label,+recipe,+grid,slots,selected,ability,status,revision,opened,button,+operation} = value
  R.Grid{width,height,inputs} = grid
  ready(label,button,operation,definitions,recipe,component_mode(operation),A.refresh(seed_table(U32.is_eq(width,3),I.State{I.write_returned(slots,0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),selected,ability,I.Profile{definitions,status,I.Menu{opened,revision,None{}}}},recipe,grid,component_mode(operation))))

def cases(values:List<&2,F.Case>,+definitions:D.Catalog) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        execute(value,definitions)
        cases(rest,definitions)

def parsed(result:Result<&2,&2,String,List<&2,F.Case>>,definitions:D.Catalog) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{values}: cases(values,definitions)

def fixture_read(result:Result<&1,&1,U32 & String,String>,definitions:D.Catalog) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{text}: parsed(F.parse(text),definitions)

def fixture_closed(read:File & Result<&1,&1,U32 & String,String>,definitions:D.Catalog) -> IO(Unit):
  (file,result) = read
  do IO<Unit>:
    File.close(file)
    fixture_read(result,definitions)

def fixture_opened(result:Result<&1,&1,U32 & String,File>,definitions:D.Catalog) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{file}:
      do IO<Unit>:
        read:File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        fixture_closed(read,definitions)

def run_fixtures(path:String,definitions:D.Catalog) -> IO(Unit):
  do IO<Unit>:
    result:Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    fixture_opened(result,definitions)

def loaded(result:Result<&2,&2,String,D.Catalog>,path:String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{definitions}: run_fixtures(path,definitions)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> table <> path <> Nil{}:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        loaded(catalog,path)
    case _: IO.die(Unit,2,"expected authoritative item metadata table and runtime fixture paths")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
