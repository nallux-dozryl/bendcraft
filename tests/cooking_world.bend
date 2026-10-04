import Base
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/block_light.bend as L
import ../src/block_light_world.bend as W
import ../src/cooking_world.bend as CW
import ../src/cooking_world_tick.bend as T
import ../src/cooking_world_slots.bend as S
import ../src/cooking_world_edit.bend as E
import ../src/cooking_world_persistence.bend as P
import ../src/cooking_block_entity_codec.bend as CB
import ../src/nbt.bend as N
import ../src/cooking_world_bindings.bend as B
import ../src/cooking_world_bindings_loader.bend as BL
import ../src/cooking_world_store.bend as Store
import ../src/campfire_authority_items.bend as A
import ../src/campfire_authority_loader.bend as AL
import ../src/furnace_authority_decoder.bend as FD
import ../src/furnace_authority_fuel.bend as FF
import ../src/furnace_authority.bend as F
import ../src/cooking_recipe.bend as K
import ../src/inventory.bend as I
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/unicode.bend as U

type Fixture is Data:
  Fixture{context:CW.Context,properties:Map<&2,Maybe<&2,L.Descriptor>>,states:List<&2,U32>}
def game(f:Fixture) -> CW.Context:
  Fixture{context,props,states} = f
  context
def position(x:U32) -> C.Position: C.Position{"minecraft:overworld",x,0,0}
def properties_map(values:List<&2,J.Value>,map:Map<&2,Maybe<&2,L.Descriptor>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,L.Descriptor>>>:
  match values:
    case Nil{}: Done{map}
    case +head <> rest:
      do Result<&2,&2,String,Map<&2,Maybe<&2,L.Descriptor>>>:
        +id : U32 <- D.number_field(head,"state")
        emission : U32 <- D.number_field(head,"emission")
        dampening : U32 <- D.number_field(head,"dampening")
        properties_map(rest,Map.set(&2,Maybe<&2,L.Descriptor>,map,U32.show(id),Some{L.Descriptor{id,emission,dampening}}))
def found(result:Map<&2,Maybe<&2,L.Descriptor>> & Maybe<&2,L.Descriptor>) -> Maybe<&2,L.Descriptor>:
  (map,value) = result
  value
def properties(context:Fixture,state:U32) -> Maybe<&2,L.Descriptor>:
  Fixture{game,props,states} = context
  found(Map.get(Maybe<&2,L.Descriptor>,None{},props,U32.show(state)))
def enabled(context:Fixture,position:C.Position) -> Bool: True{}
def states(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        state : U32 <- D.number(head)
        tail : List<&2,U32> <- states(rest)
        return state <> tail
def fixture(+raw:J.Value) -> Result<&2,&2,String,Fixture>:
  do Result<&2,&2,String,Fixture>:
    catalog : J.Value <- D.field(raw,"catalog")
    campfire : A.Context <- AL.catalog(catalog)
    fuel_raw : J.Value <- D.field(raw,"fuel_catalog")
    fuel : FF.Catalog <- FD.catalog(fuel_raw)
    text : String <- D.text_field(raw,"manifest")
    identity : String <- D.text_field(raw,"registry_identity")
    bytes : List<&2,U32> <- U.encode(1048576n,text)
    bindings : B.Catalog <- BL.parse(identity,35723,1048576n,bytes)
    property_raw : J.Value <- D.field(raw,"properties")
    property_values : List<&2,J.Value> <- D.array(property_raw)
    map : Map<&2,Maybe<&2,L.Descriptor>> <- properties_map(property_values,MTip{})
    state_raw : J.Value <- D.field(raw,"states")
    state_values : List<&2,J.Value> <- D.array(state_raw)
    loaded : List<&2,U32> <- states(state_values)
    return Fixture{CW.Context{bindings,campfire,fuel,64n},map,loaded}
def guard(label:String,value:Bool) -> IO(Unit):
  match value:
    case False{}: IO.die(Unit,3,"guard failed: " ++ label)
    case True{}: IO.print("ok " ++ label)
def expect(~R:Data,label:String,result:CW.State & Result<&2,&2,CW.Error,R>,next:R -> CW.State -> IO(Unit)) -> IO(Unit):
  (owner,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"operation failed: " ++ label)
    case Done{value}: next(value,owner)
def refuse(~R:Data,label:String,result:CW.State & Result<&2,&2,CW.Error,R>,next:CW.State -> IO(Unit)) -> IO(Unit):
  (owner,status) = result
  match status:
    case Done{value}: IO.die(Unit,2,"refusal accepted: " ++ label)
    case Fail{error}:
      do IO<Unit>:
        IO.print("ok " ++ label)
        next(owner)
def admit(+f:Fixture,owner:CW.State,sequence:Nat,mutation:C.Mutation) -> CW.State & Result<&2,&2,CW.Error,Unit>:
  CW.admit(~Fixture,~properties,~enabled,f,owner,C.Developer{},Q.Stamp{2n,0,sequence},mutation)
def unsupported_fuel(context:CW.Context) -> CW.Context:
  CW.Context{bindings,campfire,FF.Catalog{ints,floats,predicates,tags,items,defaults},depth} = context
  CW.Context{bindings,campfire,FF.Catalog{[FF.IntDefinition{"minecraft:cooking/time_coal",FF.OtherInt{J.JNull{}}}],floats,predicates,tags,items,defaults},depth}
def furnace_guard(view:Maybe<&2,Store.View>) -> Bool:
  match view:
    case Some{Store.View{p,b,Store.FurnaceView{F.Snapshot{F.Frame{kind,r,total,spent,cook,speed,cache,uses},K.FurnaceSlots{input,fuel,output}}},drops}}:
      U32.is_eq(r,1600) && U32.is_eq(total,1600) && U32.is_eq(spent,1) && U32.is_eq(cook,200) &&
      K.slot_equal(input,I.InvStack{I.ItemKey{"minecraft:oak_planks",""},2}) && K.slot_equal(fuel,I.InvStack{I.ItemKey{"minecraft:coal",""},1}) && K.slot_equal(output,I.InvEmpty{})
    case _: False{}
def drop_calls(values:List<&2,Store.Effect>,count:Nat) -> Nat:
  match values:
    case Nil{}: count
    case Store.Drop{position,index,item} <> rest: drop_calls(rest,1n+count)
    case head <> rest: drop_calls(rest,count)
def drop_items(values:List<&2,Store.Effect>,total:U32) -> U32:
  match values:
    case Nil{}: total
    case Store.Drop{position,index,item} <> rest: drop_items(rest,U32.add(total,I.slot_count(item)))
    case head <> rest: drop_items(rest,total)
def final(+effects:List<&2,Store.Effect>,owner:CW.State) -> IO(Unit):
  CW.State{world,entries,phase,keys} = owner
  do IO<Unit>:
    guard("removal_no_duplicate_items",U32.is_eq(drop_items(effects,0),3))
    guard("empty_drop_calls_retained",Nat.is_eq(drop_calls(effects,0n),20n))
    guard("all_removed",List.is_empty(&1,Store.Entry,entries))
def finish_remove(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{context,props,states} = f
  expect(~Unit,"remove_start",CW.start_tick(~Fixture,~properties,~enabled,f,context,owner),u => owner =>
    expect(~List<&2,Store.Effect>,"remove_finish",T.finish_tick(~Fixture,~properties,~enabled,f,context,owner),effects => owner => final(effects,owner)))
def first(values:List<&2,U32>) -> U32:
  match values:
    case Nil{}: 0
    case head <> rest: head
def remove_queue(left:Nat,+f:Fixture,owner:CW.State,+index:U32,+sequence:Nat) -> IO(Unit):
  match left:
    case 0n:
      Fixture{context,props,states} = f
      expect(~Unit,"recreate",CW.admit(~Fixture,~properties,~enabled,f,owner,C.Developer{},Q.Stamp{4n,0,10n},C.BlockSet{position(0),first(states)}),u => owner =>
        expect(~Unit,"remove_recreated",CW.admit(~Fixture,~properties,~enabled,f,owner,C.Developer{},Q.Stamp{4n,0,11n},C.BlockSet{position(0),0}),u => owner => finish_remove(f,owner)))
    case 1n+rest:
      expect(~Unit,"remove_admit",CW.admit(~Fixture,~properties,~enabled,f,owner,C.Developer{},Q.Stamp{4n,0,sequence},C.BlockSet{position(index),0}),u => owner => remove_queue(rest,f,owner,U32.add(index,1),1n+sequence))
def removed(f:Fixture,owner:CW.State) -> IO(Unit): remove_queue(5n,f,owner,0,1n)
def observed(f:Fixture,owner:CW.State,result:List<&1,Store.Entry> & Result<&2,&2,String,List<&2,Store.View>>) -> IO(Unit):
  CW.State{world,ignored,phase,keys} = owner
  (entries,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{views}:
      do IO<Unit>:
        guard("actual_java_ignite_frame",furnace_guard(Store.view_at(views,position(0))))
        removed(f,CW.State{world,entries,phase,keys})
def observe_context(+f:Fixture,owner:CW.State,campfire:A.Context) -> IO(Unit):
  CW.State{world,entries,phase,keys} = owner
  A.Context{recipes,defaults,features} = campfire
  observed(f,CW.State{world,[],phase,keys},Store.inspect(recipes,entries))
def observe(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{+context,props,states} = f
  observe_context(f,owner,CW.recipes(context))
def refused_edit(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{+context,props,states} = f
  refuse(~List<&2,Store.Effect>,"observer_edit_preserved",E.player_edit(~Fixture,~properties,~enabled,f,context,owner,C.Observer{},position(0),0,7n,1n,True{}),owner =>
    refuse(~S.Receipt,"output_slot_denied",S.dispatch(context,owner,position(0),S.FurnaceSet{2,A.Input{I.InvStack{I.ItemKey{"minecraft:stone",""},1},J.JObject{[]}}},C.Player{1},True{}),owner =>
      refuse(~S.Receipt,"unloaded_slot_denied",S.dispatch(context,owner,position(32),S.CampfirePlace{A.Input{I.InvStack{I.ItemKey{"minecraft:oak_planks",""},2},J.JObject{[]}},False{}},C.Player{1},True{}),owner => observe(f,owner))))
def cooked(+f:Fixture,effects:List<&2,Store.Effect>,owner:CW.State) -> IO(Unit):
  Fixture{context,props,states} = f
  do IO<Unit>:
    guard("two_actual_campfire_outputs",U32.is_eq(drop_items(effects,0),2))
    expect(~List<&2,Store.Effect>,"completed_finish",T.finish_tick(~Fixture,~properties,~enabled,f,context,owner),effects => owner =>
      do IO<Unit>:
        guard("completed_tick_does_not_replay",List.is_empty(&2,Store.Effect,effects))
        refused_edit(f,owner))
def pending(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{+context,props,states} = f
  refuse(~Unit,"pending_tick_cannot_advance",CW.start_tick(~Fixture,~properties,~enabled,f,context,owner),owner =>
    refuse(~List<&2,Store.Effect>,"unsupported_provider_retries_whole_pending_owner",T.finish_tick(~Fixture,~properties,~enabled,f,unsupported_fuel(context),owner),owner =>
      expect(~List<&2,Store.Effect>,"cook_retry",T.finish_tick(~Fixture,~properties,~enabled,f,context,owner),effects => owner => cooked(f,effects,owner))))
def tick(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{context,props,states} = f
  expect(~Unit,"start_cooking",CW.start_tick(~Fixture,~properties,~enabled,f,context,owner),u => owner => pending(f,owner))
def place_camps(left:Nat,+f:Fixture,owner:CW.State,+index:U32) -> IO(Unit):
  match left:
    case 0n: tick(f,owner)
    case 1n+rest:
      expect(~S.Receipt,"place_campfire",S.dispatch(game(f),owner,position(index),S.CampfirePlace{A.Input{I.InvStack{I.ItemKey{"minecraft:oak_planks",""},2},J.JObject{[]}},False{}},C.Player{1},True{}),receipt => owner => place_camps(rest,f,owner,U32.add(index,1)))
def fill_items(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{+context,props,states} = f
  expect(~S.Receipt,"put_furnace_input",S.dispatch(context,owner,position(0),S.FurnaceSet{0,A.Input{I.InvStack{I.ItemKey{"minecraft:oak_planks",""},2},J.JObject{[]}}},C.Player{1},True{}),r => owner =>
    expect(~S.Receipt,"put_furnace_fuel",S.dispatch(context,owner,position(0),S.FurnaceSet{1,A.Input{I.InvStack{I.ItemKey{"minecraft:coal",""},2},J.JObject{[]}}},C.Player{1},True{}),r => owner => place_camps(2n,f,owner,3)))
def body_limits() -> N.Limits: N.Limits{1048576,64,65536}
def body_roundtrip(left:Nat,+f:Fixture,owner:CW.State,+index:U32) -> IO(Unit):
  match left:
    case 0n:
      refuse(~CB.Details,"player_cannot_load_physical_body",P.load(game(f),owner,position(0),body_limits(),[],C.Player{1}),owner => fill_items(f,owner))
    case 1n+rest:
      expect(~List<&2,U32>,"body_save",P.save(game(f),owner,position(index),body_limits(),C.Developer{}),bytes => owner =>
        expect(~CB.Details,"body_load",P.load(game(f),owner,position(index),body_limits(),bytes,C.Developer{}),details => owner =>
          refuse(~CB.Details,"malformed_body_retains_owner_" ++ U32.show(index),P.load(game(f),owner,position(index),body_limits(),[],C.Developer{}),owner => body_roundtrip(rest,f,owner,U32.add(index,1)))))
def create_queue(values:List<&2,U32>,+f:Fixture,owner:CW.State,+index:U32,+sequence:Nat) -> IO(Unit):
  match values:
    case Nil{}:
      expect(~Unit,"creation_start",CW.start_tick(~Fixture,~properties,~enabled,f,game(f),owner),u => owner =>
        expect(~List<&2,Store.Effect>,"creation_finish",T.finish_tick(~Fixture,~properties,~enabled,f,game(f),owner),effects => owner => body_roundtrip(5n,f,owner,0)))
    case state <> rest:
      expect(~Unit,"create_admit",admit(f,owner,sequence,C.BlockSet{position(index),state}),u => owner => create_queue(rest,f,owner,U32.add(index,1),1n+sequence))
def section_ready(+f:Fixture,owner:CW.State) -> IO(Unit):
  Fixture{context,props,+states} = f
  create_queue(states,f,owner,0,1n)
def run(+f:Fixture) -> IO(Unit):
  Fixture{+context,props,states} = f
  expect(~Unit,"section_admit",CW.admit(~Fixture,~properties,~enabled,f,CW.begin(W.State{C.new(35723),L.new(),None{}}),C.Developer{},Q.Stamp{1n,0,1n},C.SectionCreate{position(0),0}),u => owner =>
    expect(~Unit,"section_start",CW.start_tick(~Fixture,~properties,~enabled,f,context,owner),u => owner =>
      expect(~List<&2,Store.Effect>,"section_finish",T.finish_tick(~Fixture,~properties,~enabled,f,context,owner),effects => owner => section_ready(f,owner))))
def loaded(value:Result<&2,&2,String,Fixture>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{f}: run(f)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{raw}: loaded(fixture(raw))
def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        read : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(read)
    case _: IO.die(Unit,2,"expected cooking-world input path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
