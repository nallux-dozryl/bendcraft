import Base
import ../src/inventory_key_consumer.bend as K
import ../src/player_menu_input.bend as M
import ../src/player_inventory_screen.bend as S
import ../src/player_inventory.bend as I
import ../src/player_item_definitions.bend as D
import ../src/player_presentation.bend as P
import ../src/resource_client_wire.bend as W
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/png.bend as Choice
import ./player_inventory_screen.bend as Fixture

def numbers_cons(head:Maybe<&2,U32>,tail:Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match head tail:
    case Some{value} Some{rest}: Some{value <> rest}
    case _ _: None{}

def numbers(values:List<&2,String>) -> Maybe<&2,List<&2,U32>>:
  match values:
    case Nil{}: Some{[]}
    case head <> rest: numbers_cons(U32.read(head),numbers(rest))

def event_cons(head:Event,tail:Maybe<&2,List<&2,Event>>) -> Maybe<&2,List<&2,Event>>:
  match tail:
    case None{}: None{}
    case Some{rest}: Some{head <> rest}

def events(values:List<&2,U32>) -> Maybe<&2,List<&2,Event>>:
  match values:
    case Nil{}: Some{[]}
    case 0 <> code <> down <> rest: event_cons(Key{code,U32.is_ne(down,0)},events(rest))
    case 1 <> x <> y <> rest: event_cons(Move{x,y},events(rest))
    case _: None{}

def profile(mode:U32) -> K.Profile:
  match mode:
    case 0: K.defaults()
    case 1: K.Profile{[Some{18},Some{19},Some{20},Some{21},Some{23},Some{22},Some{26},Some{28},Some{25}],Some{12},Some{14},Some{53}}
    case 2: K.Profile{[None{},None{},None{},None{},None{},None{},None{},None{},None{}],None{},Some{14},Some{53}}
    case _: K.Profile{[Some{3},None{},None{},None{},None{},None{},None{},None{},None{}],Some{3},None{},Some{53}}

def wire_head(head:Maybe<&2,W.Command>) -> List<&2,J.Value>:
  match head:
    case None{}: []
    case Some{command}: [W.command_value(command)]

def wire_values(intents:List<&2,S.Intent>) -> List<&2,J.Value>:
  match intents:
    case Nil{}: []
    case head <> rest: List.append(&2,J.Value,wire_head(M.wire(head)),wire_values(rest))

def event_value(event:Event) -> J.Value:
  match event:
    case Key{code,down}: J.JArray{[L.uint(0),L.uint(code),L.boolean(down)]}
    case Move{x,y}: J.JArray{[L.uint(1),L.uint(x),L.uint(y)]}
    case _: J.JNull{}

def event_values(events:List<&2,Event>) -> List<&2,J.Value>:
  match events:
    case Nil{}: []
    case head <> rest: event_value(head) <> event_values(rest)

def snapshot_value(snapshot:Maybe<&2,I.MenuSnapshot>) -> J.Value:
  match snapshot:
    case None{}: J.JNull{}
    case Some{value}: W.menu_snapshot_value(value)

def report(id:U32,batch:M.Batch) -> IO(Unit):
  M.Batch{M.State{controller,snapshot,catalog},+intents,events} = batch
  IO.print(J.encode(L.obj([J.JMember{"id",L.uint(id)},J.JMember{"controller",Fixture.state_value(controller)},
    J.JMember{"authority",snapshot_value(snapshot)},J.JMember{"catalog_count",L.uint(D.count(catalog))},
    J.JMember{"intents",J.JArray{Fixture.intent_values(intents)}},J.JMember{"wire",J.JArray{wire_values(intents)}},
    J.JMember{"world",J.JArray{event_values(events)}}])))

def received_snapshot(snapshot:I.MenuSnapshot,accepted:Bool) -> I.MenuSnapshot:
  I.MenuSnapshot{saved,craft,carried,result,opened,+revision} = snapshot
  I.MenuSnapshot{saved,craft,carried,result,opened,Choice.choose(Nat,1n+revision,revision,accepted)}

def received_case(id:U32,keys:K.Profile,snapshot:I.MenuSnapshot,result:M.State & List<&2,S.Intent>) -> IO(Unit):
  (state,intents) = result
  report(id,M.packet_keys(True{},keys,state,[Key{2147549187,True{}},Key{113,True{}}],S.Viewport{320,180,640,360},True{},False{}))

def after_run(id:U32,keys:K.Profile,+snapshot:I.MenuSnapshot,physical:U32,batch:M.Batch) -> IO(Unit):
  match physical batch:
    case 2 M.Batch{state,intents,events}:
      received_case(id,keys,snapshot,M.completed(state,received_snapshot(snapshot,True{}),True{}))
    case 3 M.Batch{state,intents,events}:
      received_case(id,keys,snapshot,M.completed(state,snapshot,False{}))
    case _ batch: report(id,batch)

def run(id:U32,+mode:U32,+opened:U32,tab:U32,+focused:U32,+captured:U32,carried:U32,+physical:U32,pending:Maybe<&2,List<&2,Event>>) -> IO(Unit):
  match pending:
    case None{}: IO.die(Unit,2,"invalid event fixture")
    case Some{inputs}:
      +plan = P.plan(P.Settings{640,360,100,2,False{},False{}},P.Geometry{640,360,320,180},False{})
      +snapshot = Fixture.with_carried(Fixture.fixture(U32.is_ne(opened,0)),
        Choice.choose(Inv.Slot,Inv.InvEmpty{},Fixture.stack("minecraft:dirt",3),U32.is_zero(carried)))
      after_run(id,profile(mode),snapshot,physical,M.packet_keys(U32.is_ne(physical,0),profile(mode),
        M.State{S.State{U32.is_ne(opened,0),0,0,U32.is_ne(captured,0),U32.is_ne(focused,0),None{},None{},0,tab,0,"",S.Ready{},S.Outside{}},Some{snapshot},D.legacy()},
        P.native_events(M.game_events(inputs),plan),M.viewport(P.hud_viewport(plan)),U32.is_ne(focused,0),U32.is_ne(captured,0)))

def fixture(values:Maybe<&2,List<&2,U32>>) -> IO(Unit):
  match values:
    case Some{id <> mode <> opened <> tab <> focused <> captured <> carried <> physical <> rest}:
      run(id,mode,opened,tab,focused,captured,carried,physical,events(rest))
    case _: IO.die(Unit,2,"invalid consumer fixture")

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        fixture(numbers(String.split(arg,'|')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1,String,args))
