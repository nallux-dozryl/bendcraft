import Base
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as Definitions
import ../src/player_crafting_authority_load.bend as L
import ../src/player_crafting_authority_startup.bend as Startup
import ../src/player_crafting_authority_components.bend as M
import ../src/item_component.bend as C
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/json.bend as J
import ../src/player_inventory.bend as I
import ../src/player_crafting_authority.bend as A
import ../src/player_crafting_authority_menu.bend as Menu
import ./player_crafting_authority.bend as T

type Request is Data:
  Request{metadata:J.Value,ids:List<&2,String>}

def identifier(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{text}: Done{text}
    case _: Fail{"requested recipe identity must be a string"}

def ids(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        id:String <- identifier(value)
        tail:List<&2,String> <- ids(rest)
        return id <> tail

def request(+value:J.Value) -> Result<&2,&2,String,Request>:
  do Result<&2,&2,String,Request>:
    metadata:J.Value <- D.field(value,"metadata")
    raw:J.Value <- D.field(value,"ids")
    values:List<&2,J.Value> <- D.array(raw)
    identifiers:List<&2,String> <- ids(values)
    return Request{metadata,identifiers}

def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}

def slot(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"components",J.JString{components}},J.JMember{"count",number(count)}]}

def output_record(id:String,kind:String,+output:Inv.Slot,+definitions:Definitions.Catalog) -> J.Value:
  J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"kind",J.JString{kind}},J.JMember{"output",slot(output)},J.JMember{"default_admitted",J.JBool{M.valid_slot(M.DefaultOnly{},definitions,output)}},J.JMember{"typed_stew_admitted",J.JBool{M.valid_slot(M.TypedStew{C.InitializedSuspiciousStew{}},definitions,output)}}]}

def recipe(value:R.Recipe,definitions:Definitions.Catalog) -> J.Value:
  match value:
    case R.Shaped{id,width,height,cells,output}: output_record(id,"shaped",output,definitions)
    case R.Shapeless{id,ingredients,output}: output_record(id,"shapeless",output,definitions)
    case R.Unsupported{id,kind}: J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"kind",J.JString{kind}}]}

def recipes(values:List<&2,R.Recipe>,+definitions:Definitions.Catalog) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: recipe(value,definitions) <> recipes(rest,definitions)

def observed(label:String,reply:Menu.Reply,result:A.State & A.Snapshot) -> A.State & J.Value:
  Menu.Reply{accepted,message,I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,abilities},equipment,status},craft,carried,output,opened,revision},active_grid,taken,refreshed} = reply
  (state,A.Snapshot{current,grid,cache}) = result
  (state,J.JObject{[J.JMember{"label",J.JString{label}},J.JMember{"accepted",J.JBool{accepted}},J.JMember{"message",J.JString{message}},J.JMember{"selected",number(selected)},J.JMember{"revision",number(U32.from_nat(revision))},J.JMember{"opened",J.JBool{opened}},J.JMember{"slots",J.JArray{T.data_slots(List.append(&2,Inv.Slot,main,List.append(&2,Inv.Slot,equipment,List.append(&2,Inv.Slot,craft,[carried]))))}},J.JMember{"taken",slot(taken)},J.JMember{"result",T.maybe_slot(output)},J.JMember{"cache",T.cache(cache)},J.JMember{"cache_refreshed",J.JBool{refreshed}}]})

def printed(value:A.State & J.Value,next:A.State -> IO(Unit)) -> IO(Unit):
  (state,record) = value
  do IO<Unit>:
    IO.print(J.encode(record))
    next(state)

def emitted(label:String,result:A.State & Menu.Reply,next:A.State -> IO(Unit)) -> IO(Unit):
  (state,reply) = result
  printed(observed(label,reply,A.inspect(state)),next)

def done(state:A.State) -> IO(Unit): IO.pure(Unit,Unit{})
def closed_player(result:A.State & Menu.Reply) -> IO(Unit): emitted("closed",result,done)
def refused_player(result:A.State & Menu.Reply) -> IO(Unit): emitted("absent",result,state => closed_player(Menu.close(state)))
def second_player(result:A.State & Menu.Reply) -> IO(Unit): emitted("second",result,state => refused_player(Menu.click(state,0,I.Pickup{0})))
def first_player(result:A.State & Menu.Reply) -> IO(Unit): emitted("first",result,state => second_player(Menu.click(state,0,I.Pickup{0})))
def opened_player(result:A.State & Menu.Reply) -> IO(Unit): emitted("opened",result,state => first_player(Menu.click(state,0,I.Pickup{1})))

def empty_slots(n:Nat) -> List<&2,Inv.Slot>:
  match n:
    case 0n: []
    case 1n+rest: Inv.InvEmpty{} <> empty_slots(rest)

def seed(definitions:Definitions.Catalog,craft:List<&2,Inv.Slot>,opened:Bool) -> I.State:
  I.State{I.write_returned(List.append(&2,Inv.Slot,empty_slots(43n),List.append(&2,Inv.Slot,craft,[Inv.InvEmpty{}])),0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),7,I.Abilities{False{},True{}},I.Profile{definitions,I.Status{False{},False{},False{},1036831949,1028443341},I.Menu{opened,0n,None{}}}}

def ready_stew(result:A.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{unit}: emitted("typed-stew",Menu.click(state,0,I.Pickup{0}),done)

def play(+definitions:Definitions.Catalog,+catalog:R.Catalog) -> IO(Unit):
  do IO<Unit>:
    opened_player(Menu.open(A.new(seed(definitions,[Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},2},Inv.InvEmpty{},Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},2},Inv.InvEmpty{}],False{}),catalog)))
    ready_stew(A.refresh(A.new_with_components(seed(definitions,[Inv.InvStack{Inv.ItemKey{"minecraft:bowl",""},1},Inv.InvStack{Inv.ItemKey{"minecraft:brown_mushroom",""},1},Inv.InvStack{Inv.ItemKey{"minecraft:brown_mushroom",""},1},Inv.InvStack{Inv.ItemKey{"minecraft:allium",""},1}],True{}),catalog,M.TypedStew{C.InitializedSuspiciousStew{}})))
    T.run_fixtures("build/player-crafting-authority-tests/cases.json",definitions)

def completed(result:Result<&2,&2,String,L.Service>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{L.Service{+definitions,+catalog}}:
      R.Catalog{values,tags,items} = catalog
      do IO<Unit>:
        IO.print(J.encode(J.JObject{[J.JMember{"definitions",number(Definitions.count(definitions))},J.JMember{"items",number(U32.from_nat(List.length(&2,R.ItemDefinition,items)))},J.JMember{"tags",number(U32.from_nat(List.length(&2,R.Tag,tags)))},J.JMember{"recipes",J.JArray{recipes(values,definitions)}}]}))
        play(definitions,catalog)

def requested(result:Result<&2,&2,String,Request>,jar:String,table:String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{Request{metadata,identifiers}}:
      do IO<Unit>:
        service:Result<&2,&2,String,L.Service> <- L.service(jar,identifiers,table,metadata,L.defaults())
        completed(service)

def parsed(result:Result<&2,&2,String,J.Value>,jar:String,table:String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: requested(request(value),jar,table)

def read_result(result:Result<&1,&1,U32 & String,String>,jar:String,table:String) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{text}: parsed(J.parse_bounded(text,8388608n,64),jar,table)

def closed(read:File & Result<&1,&1,U32 & String,String>,jar:String,table:String) -> IO(Unit):
  (file,result) = read
  do IO<Unit>:
    File.close(file)
    read_result(result,jar,table)

def opened(result:Result<&1,&1,U32 & String,File>,jar:String,table:String) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{file}:
      do IO<Unit>:
        read:File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        closed(read,jar,table)

def artifact_loaded(result:Result<&2,&2,String,R.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{catalog}: IO.print("artifact loaded")

def artifact_limit(result:Maybe<&2,U32>,path:String) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit,2,"invalid artifact budget")
    case Some{maximum}:
      do IO<Unit>:
        loaded:Result<&2,&2,String,R.Catalog> <- L.load_artifact(path,maximum,32)
        artifact_loaded(loaded)

def startup(jar:String,table:String,path:String) -> IO(Unit):
  do IO<Unit>:
    result:Result<&2,&2,String,L.Service> <- Startup.service(jar,table,path,L.defaults())
    completed(result)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> "--facts" <> jar <> table <> path <> Nil{}: startup(jar,table,path)
    case program <> "--artifact" <> path <> maximum <> Nil{}: artifact_limit(U32.read(maximum),path)
    case program <> jar <> table <> request <> Nil{}:
      do IO<Unit>:
        file:Result<&1,&1,U32 & String,File> <- File.open(request,"r")
        opened(file,jar,table)
    case _: IO.die(Unit,2,"expected jar, item-definition table and metadata/request paths")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
