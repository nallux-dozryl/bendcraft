import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/campfire_authority_items.bend as A
import ../src/campfire_authority_loader.bend as L
import ../src/inventory.bend as I
import ../src/player_inventory.bend as P
import ../src/player_item_definitions.bend as Definitions
import ../src/random.bend as R
import ../src/vanilla_entity_fields.bend as V
import ../src/cooking_effect_entities_model.bend as E
import ../src/item_entity_pickup_model.bend as M
import ../src/item_entity_pickup.bend as Pickup
import ../src/item_entity_pickup_scene.bend as Scene
import ../src/item_entity_pickup_properties.bend as Props
import ./cooking_effect_entities_values.bend as T

# Reference input keys are independently encoded patches; only production
# initialized-default resolution creates the canonical native identity.
def item_raw(+raw:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,I.Slot>:
  match raw:
    case J.JNull{}: Done{I.InvEmpty{}}
    case _:
      do Result<&2,&2,String,I.Slot>:
        id : String <- D.text_field(raw,"id")
        count : U32 <- D.number_field(raw,"count")
        patch : String <- C.patch_text(J.member(raw,"components"))
        D.resolve_output(I.InvStack{I.ItemKey{id,patch},count},defaults)
def items(values:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,I.Slot>>:
  match values:
    case Nil{}: Done{[]}
    case head <> tail:
      do Result<&2,&2,String,List<&2,I.Slot>>:
        head : I.Slot <- item_raw(head,defaults)
        tail : List<&2,I.Slot> <- items(tail,defaults)
        return head <> tail
def optional_uuid(value:J.Value) -> Result<&2,&2,String,Maybe<&2,E.Uuid>>:
  match value:
    case J.JNull{}: Done{None{}}
    case J.JArray{a <> b <> Nil{}}:
      do Result<&2,&2,String,Maybe<&2,E.Uuid>>:
        a : R.Bits64 <- T.read_bits(a)
        b : R.Bits64 <- T.read_bits(b)
        return Some{E.Uuid{a,b}}
    case _: Fail{"expected optional UUID words"}
def uuid_field(value:J.Value,name:String) -> Result<&2,&2,String,Maybe<&2,E.Uuid>>:
  do Result<&2,&2,String,Maybe<&2,E.Uuid>>:
    raw : J.Value <- D.field(value,name)
    optional_uuid(raw)
def player(slots:List<&2,I.Slot>,selected:U32,creative:Bool,definitions:Definitions.Catalog) -> P.State:
  P.State{P.write_returned(slots,0,I.Inventory{Array.new(I.Slot,6n,I.InvEmpty{}),48}),selected,P.Abilities{creative,True{}},P.Profile{definitions,P.default_status(),P.Menu{True{},17n,Some{I.InvStack{I.ItemKey{"minecraft:dirt",""},1}}}}}
def entity(item:I.Slot,delay:U32,thrower:Maybe<&2,E.Uuid>,target:Maybe<&2,E.Uuid>) -> E.Record:
  E.Item{E.Common{"minecraft:overworld",71,R.Bits64{1,2},R.Bits64{3,4},R.Legacy{R.Bits64{11,12}},V.default_fields(),33,False{},False{},True{},19n},item,41,delay,5,thrower,target,0.5}
def slot_values(values:List<&2,I.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: T.slot(head) <> slot_values(rest)
def publication(value:M.Publication) -> J.Value:
  match value:
    case M.PopTime{slot,duration}: T.obj([J.JMember{"kind",T.txt("pop")},J.JMember{"slot",T.num(slot)},J.JMember{"duration",T.num(duration)}])
    case M.TakePacket{entity,player,count}: T.obj([J.JMember{"kind",T.txt("take")},J.JMember{"count",T.num(count)},J.JMember{"removed_at_take",T.bool(False{})}])
    case M.MenuBroadcast{player}: T.obj([J.JMember{"kind",T.txt("broadcast")}])
    case M.EntityDiscard{entity}: T.obj([J.JMember{"kind",T.txt("discard")}])
    case M.PickupStat{player,id,count}: T.obj([J.JMember{"kind",T.txt("stat")},J.JMember{"id",T.txt(id)},J.JMember{"count",T.num(count)}])
    case M.ThrownPickedUpByEntity{thrower,receiver,item}: T.obj([J.JMember{"kind",T.txt("thrown_by_entity")},J.JMember{"item",T.slot(item)}])
    case M.ThrownPickedUpByPlayer{receiver,thrower,item}: T.obj([J.JMember{"kind",T.txt("thrown_by_player")},J.JMember{"item",T.slot(item)}])
def publications(values:List<&2,M.Publication>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: publication(head) <> publications(rest)
def effect_fields(effects:M.Effects) -> List<&2,J.Member>:
  M.Effects{returned,inserted,residue,discarded,events} = effects
  [J.JMember{"returned",T.bool(returned)},J.JMember{"inserted",T.num(inserted)},J.JMember{"residue",T.num(residue)},J.JMember{"publications",J.JArray{publications(events)}}]
def error(value:M.Error) -> String:
  match value:
    case M.Refused{message}: message
    case M.BudgetExhausted{}: "operation budget"
def status(value:Result<&2,&2,M.Error,M.Effects>) -> List<&2,J.Member>:
  match value:
    case Fail{message}: [J.JMember{"error",T.txt(error(message))}]
    case Done{effects}: effect_fields(effects)
def common_removed(value:E.Common) -> Bool:
  E.Common{dimension,id,most,least,random,fields,tick,first,removed,accessible,order} = value
  removed
def item(value:E.Record) -> I.Slot:
  match value:
    case E.Item{common,item,age,delay,health,thrower,target,bob}: item
    case _: I.InvEmpty{}
def observation(id:String,+record:E.Record,result:Result<&2,&2,M.Error,M.Effects>,state:P.State,+snapshot:P.MenuSnapshot) -> Result<&2,&2,String,J.Value>:
  P.MenuSnapshot{saved,craft,carried,output,opened,revision} = snapshot
  Done{T.obj(List.append(&2,J.Member,[J.JMember{"id",T.txt(id)},J.JMember{"slots",J.JArray{slot_values(P.menu_slots(snapshot))}},J.JMember{"entity_item",T.slot(item(record))},J.JMember{"removed",T.bool(common_removed(E.common(record)))},J.JMember{"menu_revision",T.num(U32.from_nat(revision))},J.JMember{"menu_result_present",T.bool(Maybe.is_some(&2,I.Slot,output))},J.JMember{"common",T.common(E.common(record))}],status(result)))}
def observed(id:String,record:E.Record,result:Result<&2,&2,M.Error,M.Effects>,snapshot:P.State & P.MenuSnapshot) -> Result<&2,&2,String,J.Value>:
  (state,view) = snapshot
  observation(id,record,result,state,view)
def touched(id:String,result:E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>) -> Result<&2,&2,String,J.Value>:
  (E.Entity{record},state,result) = result
  observed(id,record,result,P.menu_inspect(state))
def known_resolution(value:Maybe<&2,E.Uuid>,server:Bool) -> M.OwnerResolution:
  match value:
    case None{}: M.UnknownOwner{}
    case Some{uuid}: M.ResolvedOwner{uuid,server}
def resolution_choice(absent:Bool,name:String,value:Maybe<&2,E.Uuid>) -> M.OwnerResolution:
  match absent:
    case True{}: M.KnownAbsent{}
    case False{}: known_resolution(value,String.eq(name,"server"))
def resolution(+name:String,value:Maybe<&2,E.Uuid>) -> M.OwnerResolution:
  resolution_choice(String.eq(name,"absent"),name,value)
def other_record(id:U32) -> E.Record:
  E.Orb{E.Common{"minecraft:overworld",id,R.Bits64{1,2},R.Bits64{3,4},R.Legacy{R.Bits64{11,12}},V.default_fields(),33,False{},False{},True{},19n},7,41,5,1,None{}}
def target_record(values:List<&2,E.Record>) -> E.Record:
  match values:
    case before <> target <> after <> Nil{}: target
    case _: other_record(71)
def scene_observed(id:String,player:P.State,status:Result<&2,&2,M.Error,M.Effects>,snapshot:E.State & E.View) -> Result<&2,&2,String,J.Value>:
  (state,+view) = snapshot
  E.View{level,factory,cursor,order,+records} = view
  do Result<&2,&2,String,J.Value>:
    +answer : J.Value <- observed(id,target_record(records),status,P.menu_inspect(player))
    members : List<&2,J.Member> <- Props.members(answer)
    return T.obj(J.JMember{"scene",T.view(view)} <> members)
def scene_touched(id:String,result:E.State & P.State & Result<&2,&2,M.Error,M.Effects>) -> Result<&2,&2,String,J.Value>:
  (state,player,status) = result
  scene_observed(id,player,status,E.inspect(state))
def chosen(scene:Bool,id:String,admission:M.Admission,context:M.Context,record:E.Record,player:P.State,budget:Nat) -> Result<&2,&2,String,J.Value>:
  match scene:
    case False{}: touched(id,Pickup.touch(admission,context,E.Entity{record},player))
    case True{}: scene_touched(id,Scene.touch_id(admission,context,71,E.install(E.View{R.Legacy{R.Bits64{50,60}},R.Bits64{70,80},81,99n,[other_record(90),record,other_record(92)]}),player,budget))
def fixture(+raw:J.Value,+context:A.Context,definitions:Definitions.Catalog) -> Result<&2,&2,String,J.Value>:
  A.Context{recipes,+defaults,features} = context
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    selected : U32 <- D.number_field(raw,"selected")
    creative : Bool <- T.flag(raw,"creative")
    client : Bool <- T.flag(raw,"client")
    admitted : Bool <- T.flag(raw,"admitted")
    dimension : String <- D.text_field(raw,"dimension")
    server : Bool <- T.flag(raw,"server_player")
    budget : U32 <- D.number_field(raw,"budget")
    scene : Bool <- T.flag(raw,"scene")
    scan : U32 <- D.number_field(raw,"scan_budget")
    owner : String <- D.text_field(raw,"resolution")
    resolved : Maybe<&2,E.Uuid> <- uuid_field(raw,"resolved")
    delay : U32 <- D.number_field(raw,"delay")
    thrower : Maybe<&2,E.Uuid> <- uuid_field(raw,"thrower")
    target : Maybe<&2,E.Uuid> <- uuid_field(raw,"target")
    input : J.Value <- D.field(raw,"item")
    item : I.Slot <- item_raw(input,defaults)
    raw_slots : List<&2,J.Value> <- T.array_field(raw,"slots")
    slots : List<&2,I.Slot> <- items(raw_slots,defaults)
    chosen(scene,id,M.Admission{admitted,Bool.not(client),dimension,72,E.Uuid{R.Bits64{286335522,858997828},R.Bits64{1431660134,2004322440}},server,resolution(owner,resolved)},M.Context{context,U32.to_nat(budget)},entity(item,delay,thrower,target),player(List.append(&2,I.Slot,slots,[I.InvEmpty{},I.InvEmpty{},I.InvEmpty{},I.InvEmpty{},I.InvEmpty{}]),selected,creative,definitions),U32.to_nat(scan))
def fixtures(values:List<&2,J.Value>,+context:A.Context,+definitions:Definitions.Catalog) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(head,context,definitions)
        tail : List<&2,J.Value> <- fixtures(rest,context,definitions)
        return head <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    catalog : J.Value <- D.field(value,"catalog")
    context : A.Context <- L.catalog(catalog)
    table : String <- D.text_field(value,"item_table")
    definitions : Definitions.Catalog <- Definitions.parse(table)
    cases : List<&2,J.Value> <- T.array_field(value,"cases")
    results : List<&2,J.Value> <- fixtures(cases,context,definitions)
    return J.JArray{results}
def respond(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: respond(execute(value))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected pickup receiver fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
