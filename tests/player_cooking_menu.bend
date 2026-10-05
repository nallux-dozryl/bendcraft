import Base
import ../src/player_cooking_menu.bend as Menu
import ../src/player_cooking_menu_transfer.bend as Move
import ../src/player_cooking_menu_campfire.bend as Camp
import ../src/campfire_authority.bend as CA
import ../src/campfire_authority_items.bend as AI
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/cooking_world.bend as CW
import ../src/cooking_world_store.bend as Store
import ../src/cooking_world_bindings.bend as Binding
import ../src/cooking_effect_publication_journal.bend as Journal
import ../src/furnace_authority.bend as FA
import ../src/cooking_recipe.bend as K
import ../src/core.bend as C
import ../src/block_light.bend as L
import ../src/block_light_world.bend as W
import ../src/world_codec.bend as WC
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/nbt.bend as N
import ../src/json.bend as J
import ../src/live.bend as Live
import ./cooking_world.bend as Fixture
import ./player_inventory_close.bend as Slots
import ./furnace_authority.bend as Furnace
import ./player_cooking_menu_screen.bend as ScreenCases

# Initialize actual owners, call the production transaction once, and consume
# every backing cell. The fixture implements no pickup/quick-move algorithm.
def position() -> C.Position: C.Position{"minecraft:overworld",0,0,0}
def admit(value:Menu.Reply) -> Result<&2,&2,String,Unit>: Done{Unit{}}
def refuse(value:Menu.Reply) -> Result<&2,&2,String,Unit>: Fail{"fixture:complete-reply-budget"}
def byte_values(+values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: Live.uint(head) <> byte_values(rest)
def bytes(+values:List<&2,U32>) -> J.Value: J.JArray{byte_values(values)}
def first(+values:List<&2,U32>) -> U32:
  match values:
    case Nil{}: 0
    case head <> rest: head

def binding_classified(result:Result<&2,&2,String,Binding.Classification>) -> Result<&2,&2,String,Binding.Binding>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Binding.Cooking{binding}}: Done{binding}
    case Done{Binding.Other{}}: Fail{"fixture state lacks cooking binding"}
def actual_binding(+context:CW.Context,+id:U32) -> Result<&2,&2,String,Binding.Binding>:
  CW.Context{catalog,recipes,fuel,depth} = context
  binding_classified(Binding.classify(catalog,id))
def bound_handle() -> Menu.Handle: Menu.Furnace{5,7,position(),"minecraft:furnace",K.Smelting{},2n}
def frame() -> FA.Frame:
  FA.Frame{K.Smelting{},71,1600,83,200,1.0,Some{"minecraft:stone"},[FA.Use{"minecraft:stone",7}]}
def furnace(+slots:List<&2,Inv.Slot>) -> FA.State:
  FA.State{I.write_returned(List.append(&2,Inv.Slot,slots,[Inv.InvStack{Inv.ItemKey{"fixture:hidden-furnace",""},31}]),0,
    Inv.Inventory{Array.new(Inv.Slot,2n,Inv.InvEmpty{}),3}),frame()}
def inventory(+catalog:D.Catalog,+creative:Bool,+maybuild:Bool,+slots:List<&2,Inv.Slot>,+opened:Bool) -> I.State:
  I.State{I.write_returned(slots,0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),7,
    I.Abilities{creative,maybuild},I.Profile{catalog,I.Status{True{},True{},False{},2147483648,2143289345},I.Menu{opened,19n,None{}}}}
def access(+gate:String) -> Menu.Access:
  Menu.Access{N.choose(C.Capability,C.Observer{},N.choose(C.Capability,C.Player{0},N.choose(C.Capability,C.Player{8},C.Player{7},String.eq(gate,"peer")),String.eq(gate,"zero")),String.eq(gate,"observer")),
    Bool.not(String.eq(gate,"permission")),N.choose(String,"minecraft:the_nether","minecraft:overworld",String.eq(gate,"dimension")),
    M.Vec3{N.choose(F.F64,F.from_u32(19),F.from_u32(1),String.eq(gate,"range")),F.F64{1072693248,0},F.F64{1071644672,0}},
    F.F64{1074921472,0},N.choose(Nat,3n,2n,String.eq(gate,"incarnation"))}
def action(+name:String,+index:U32,+button:U32,+gate:String) -> Menu.Action:
  +menu = N.choose(U32,9,5,String.eq(gate,"menu"))
  N.choose(Menu.Action,Menu.MenuClose{menu},N.choose(Menu.Action,Menu.MenuInspect{menu},
    N.choose(Menu.Action,Menu.MenuQuickMove{menu,index},Menu.MenuPickup{menu,index,button},String.eq(name,"QUICK_MOVE")),String.eq(name,"INSPECT")),String.eq(name,"CLOSE"))

def used(+values:List<&2,Store.Effect>) -> U32:
  match values:
    case Nil{}: 0
    case Store.Dirty{position} <> rest: U32.add(1,used(rest))
    case Store.OwnedDirty{source} <> rest: U32.add(1,used(rest))
    case other <> rest: used(rest)
def legacy_used(values:List<&2,Store.Effect>) -> U32:
  match values:
    case Nil{}: 0
    case Store.Dirty{position} <> rest: U32.add(1,legacy_used(rest))
    case other <> rest: legacy_used(rest)
def source_furnace_kind(kind:K.CookingKind) -> String:
  match kind:
    case K.Smelting{}: "smelting"
    case K.Blasting{}: "blasting"
    case K.Smoking{}: "smoking"
    case K.Campfire{}: "campfire"
def source_family(family:Binding.Family) -> String:
  match family:
    case Binding.Furnace{kind}: source_furnace_kind(kind)
    case Binding.Campfire{CA.Ordinary{}}: "campfire"
    case Binding.Campfire{CA.Soul{}}: "soul_campfire"
def source_value(value:Journal.Source) -> J.Value:
  Journal.Source{C.Position{dimension,x,y,z},Binding.Binding{state,block,family,lit,dark,bright},incarnation} = value
  Live.obj([J.JMember{"dimension",Live.text(dimension)},J.JMember{"x",Live.uint(x)},J.JMember{"y",Live.uint(y)},J.JMember{"z",Live.uint(z)},
    J.JMember{"state",Live.uint(state)},J.JMember{"block",Live.text(block)},J.JMember{"family",Live.text(source_family(family))},J.JMember{"lit",Live.boolean(lit)},
    J.JMember{"dark_state",Live.uint(dark)},J.JMember{"lit_state",Live.uint(bright)},J.JMember{"incarnation",Live.natural(incarnation)}])
def source_values(values:List<&2,Store.Effect>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Store.OwnedDirty{source} <> rest: source_value(source) <> source_values(rest)
    case other <> rest: source_values(rest)
def player_value(state:I.State) -> J.Value:
  I.State{Inv.Inventory{slots,length},selected,abilities,I.Profile{catalog,status,I.Menu{opened,revision,result}}} = state
  Live.obj([J.JMember{"selected",Live.uint(selected)},J.JMember{"abilities",Slots.abilities_value(abilities,status)},
    J.JMember{"opened",Live.boolean(opened)},J.JMember{"revision",Live.uint(U32.from_nat(revision))},
    J.JMember{"result",Slots.output_value(result)},J.JMember{"logical_length",Live.uint(length)},
    J.JMember{"catalog_count",Live.uint(D.count(catalog))},J.JMember{"backing",J.JArray{Slots.slot_values(Array.to_list(~Inv.Slot,slots))}}])
def camp_cell(value:CA.Cell) -> J.Value:
  CA.Cell{AI.Input{slot,patch},progress,total} = value
  Live.obj([J.JMember{"slot",Slots.slot_value(slot)},J.JMember{"patch",patch},J.JMember{"progress",Live.uint(progress)},J.JMember{"total",Live.uint(total)}])
def cache_value(value:Maybe<&2,String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{recipe}: Live.text(recipe)
def entry_value(entry:Store.Entry) -> J.Value:
  match entry:
    case Store.Entry{position,Binding.Binding{state,block,family,lit,dark,bright},Store.Furnace{FA.State{Inv.Inventory{slots,length},frame}}}:
      Live.obj([J.JMember{"block",Live.text(block)},J.JMember{"state",Live.uint(state)},J.JMember{"logical_length",Live.uint(length)},
        J.JMember{"frame",Furnace.snapshot(FA.Snapshot{frame,K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}}})},
        J.JMember{"backing",J.JArray{Slots.slot_values(Array.to_list(~Inv.Slot,slots))}}])
    case Store.Entry{position,Binding.Binding{state,block,family,lit,dark,bright},Store.Campfire{CA.State{kind,enabled,CA.Four{a,b,c,d},cache}}}:
      Live.obj([J.JMember{"block",Live.text(block)},J.JMember{"state",Live.uint(state)},J.JMember{"lit",Live.boolean(enabled)},
        J.JMember{"cells",J.JArray{[camp_cell(a),camp_cell(b),camp_cell(c),camp_cell(d)]}},J.JMember{"cache",cache_value(cache)}])
def entry_values(entries:List<&1,Store.Entry>) -> List<&2,J.Value>:
  match entries:
    case Nil{}: []
    case head <> rest: entry_value(head) <> entry_values(rest)
def handle_value(value:Menu.Handle) -> J.Value:
  match value:
    case Menu.Closed{}: Live.uint(0)
    case Menu.Furnace{menu,peer,position,block,kind,token}: Live.uint(menu)
def reply_view(value:Menu.Snapshot) -> J.Value:
  Menu.Snapshot{handle,furnace,inventory} = value
  Live.obj([J.JMember{"id",handle_value(handle)},J.JMember{"furnace_available",Live.boolean(Maybe.is_some(&2,Menu.FurnaceView,furnace))}])
def output(+label:String,+before:List<&2,U32>,+accepted:Bool,+message:String,+dirty:U32,+legacy:U32,+sources:List<&2,J.Value>,+menu:J.Value,+player:J.Value,+entries:List<&2,J.Value>,result:C.World & Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{after}:
      IO.print(J.encode(Live.obj([J.JMember{"id",Live.text(label)},J.JMember{"accepted",Live.boolean(accepted)},J.JMember{"message",Live.text(message)},
        J.JMember{"dirty",Live.uint(dirty)},J.JMember{"legacy_dirty",Live.uint(legacy)},J.JMember{"owned_dirty",J.JArray{sources}},J.JMember{"menu",menu},J.JMember{"before_core",bytes(before)},J.JMember{"after_core",bytes(after)},
        J.JMember{"player",player},J.JMember{"entries",J.JArray{entries}}])))
def observed_status(+label:String,+before:List<&2,U32>,+identity:String,inventory:I.State,owner:CW.State,status:Result<&2,&2,String,Menu.Reply>) -> IO(Unit):
  CW.State{W.State{world,light,loading},entries,phase,keys} = owner
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{Menu.Reply{accepted,message,snapshot,+effects}}:
      output(label,before,accepted,message,used(effects),legacy_used(effects),source_values(effects),reply_view(snapshot),player_value(inventory),entry_values(entries),WC.encode(world,identity))
def observed(+label:String,+before:List<&2,U32>,+identity:String,result:CW.State & I.State & Result<&2,&2,String,Menu.Reply>) -> IO(Unit):
  (owner,inventory,status) = result
  observed_status(label,before,identity,inventory,owner,status)
def run_admission(+budget:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+handle:Menu.Handle,+access:Menu.Access,+action:Menu.Action) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match budget:
    case True{}: Menu.dispatch(refuse,context,owner,inventory,handle,access,action)
    case False{}: Menu.dispatch(admit,context,owner,inventory,handle,access,action)
def open_admission(budget:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+gate:String) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match budget:
    case True{}: Menu.open(refuse,context,owner,inventory,bound_handle(),access(gate),position(),6)
    case False{}: Menu.open(admit,context,owner,inventory,bound_handle(),access(gate),position(),6)
def furnace_mode(open:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+name:String,+index:U32,+button:U32,+gate:String) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match open:
    case True{}: open_admission(String.eq(gate,"budget"),context,owner,inventory,gate)
    case False{}: run_admission(String.eq(gate,"budget"),context,owner,inventory,bound_handle(),access(gate),action(name,index,button,gate))
def campfire_action(+name:String) -> Bool:
  String.eq(name,"USE_MAIN") || String.eq(name,"USE_OFFHAND") || String.eq(name,"USE_HANDS")
def campfire_fixture(full:Bool) -> CA.State:
  match full:
    case False{}: CA.new(CA.Ordinary{},True{})
    case True{}:
      +cell : CA.Cell = CA.Cell{AI.Input{Inv.InvStack{Inv.ItemKey{"minecraft:potato",""},1},J.JObject{[]}},19,600}
      CA.State{CA.Ordinary{},True{},CA.Four{cell,cell,cell,cell},Some{"minecraft:baked_potato_from_campfire_cooking"}}
def fixture_entity(camp:Bool,+slots:List<&2,Inv.Slot>,+gate:String) -> Store.Entity:
  match camp:
    case True{}: Store.Campfire{campfire_fixture(String.eq(gate,"full"))}
    case False{}: Store.Furnace{furnace(slots)}
def fixture_owner(+binding:Binding.Binding,+slots:List<&2,Inv.Slot>,+name:String,+gate:String,world:C.World) -> CW.State:
  CW.State{W.State{world,L.new(),None{}},[Store.Entry{position(),binding,fixture_entity(campfire_action(name),slots,gate)}],CW.Idle{},[]}
def use_admission(budget:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+gate:String,+offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match budget:
    case False{}: Camp.use(admit,context,owner,inventory,position(),access(gate),offhand)
    case True{}: Camp.use(refuse,context,owner,inventory,position(),access(gate),offhand)
def use_hands_admission(budget:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+gate:String) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match budget:
    case False{}: Camp.use_hands(admit,context,owner,inventory,position(),access(gate))
    case True{}: Camp.use_hands(refuse,context,owner,inventory,position(),access(gate))
def use_mode(hands:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+gate:String,offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match hands:
    case True{}: use_hands_admission(String.eq(gate,"budget"),context,owner,inventory,gate)
    case False{}: use_admission(String.eq(gate,"budget"),context,owner,inventory,gate,offhand)
def run_operation(camp:Bool,+context:CW.Context,owner:CW.State,inventory:I.State,+name:String,+index:U32,+button:U32,+gate:String) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match camp:
    case True{}: use_mode(String.eq(name,"USE_HANDS"),context,owner,inventory,gate,String.eq(name,"USE_OFFHAND"))
    case False{}: furnace_mode(String.eq(name,"OPEN"),context,owner,inventory,name,index,button,gate)
def before_encoded(+context:CW.Context,inventory:I.State,+binding:Binding.Binding,+slots:List<&2,Inv.Slot>,+label:String,+name:String,+index:U32,+button:U32,+gate:String,result:C.World & Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  CW.Context{Binding.Catalog{identity,count,bindings},recipes,fuel,depth} = context
  (world,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{before}:
      observed(label,before,identity,run_operation(campfire_action(name),context,fixture_owner(binding,slots,name,gate,world),inventory,name,index,button,gate))
def block_ready(+context:CW.Context,inventory:I.State,+binding:Binding.Binding,+slots:List<&2,Inv.Slot>,+label:String,+name:String,+index:U32,+button:U32,+gate:String,
    result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(Unit):
  CW.Context{Binding.Catalog{identity,count,bindings},recipes,fuel,depth} = context
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"fixture block setup failed")
    case Done{unit}: before_encoded(context,inventory,binding,slots,label,name,index,button,gate,WC.encode(world,identity))
def section_ready(+context:CW.Context,inventory:I.State,+binding:Binding.Binding,+slots:List<&2,Inv.Slot>,+label:String,+name:String,+index:U32,+button:U32,+gate:String,
    result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(Unit):
  Binding.Binding{+state,block,family,lit,dark,bright} = binding
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"fixture section setup failed")
    case Done{unit}: block_ready(context,inventory,binding,slots,label,name,index,button,gate,C.apply(world,C.BlockSet{position(),state}))
def setup_binding(+context:CW.Context,+catalog:D.Catalog,+slots:List<&2,Inv.Slot>,+player:List<&2,Inv.Slot>,+label:String,+name:String,+index:U32,+button:U32,+creative:Bool,+maybuild:Bool,+gate:String,
    result:Result<&2,&2,String,Binding.Binding>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{binding}:
      section_ready(context,inventory(catalog,creative,maybuild,player,Bool.not(campfire_action(name))),binding,slots,label,name,index,button,gate,C.apply(C.new(35723),C.SectionCreate{position(),0}))
def state_at(states:List<&2,U32>,index:Nat) -> U32:
  match states index:
    case Nil{} _: 0
    case value <> rest 0n: value
    case value <> rest 1n+n: state_at(rest,n)
def fixture_state(+name:String,+states:List<&2,U32>) -> U32:
  N.choose(U32,state_at(states,3n),first(states),campfire_action(name))
def setup(+context:CW.Context,+catalog:D.Catalog,+states:List<&2,U32>,+fields:List<&2,String>) -> IO(Unit):
  match fields:
    case label <> name <> index <> button <> creative <> maybuild <> gate <> a <> b <> c <> rest:
      setup_binding(context,catalog,Slots.fixture_slots([a,b,c]),Slots.fixture_slots(rest),label,name,Slots.number(index),Slots.number(button),Slots.flag(creative),Slots.flag(maybuild),gate,actual_binding(context,fixture_state(name,states)))
    case _: IO.die(Unit,2,"complete cooking menu fixture required")
def cases(+context:CW.Context,+catalog:D.Catalog,+states:List<&2,U32>,args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case input <> rest:
      do IO<Unit>:
        setup(context,catalog,states,String.split(input,'|'))
        cases(context,catalog,states,rest)
def loaded_catalog(+fixture:Fixture.Fixture,args:List<String>,result:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  Fixture.Fixture{context,properties,states} = fixture
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{catalog}: cases(context,catalog,states,args)
def fixture_loaded(+table:String,args:List<String>,result:Result<&2,&2,String,Fixture.Fixture>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{fixture}:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        loaded_catalog(fixture,args,catalog)
def parsed(+table:String,args:List<String>,result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{raw}: fixture_loaded(table,args,Fixture.fixture(raw))
def read_done(+table:String,args:List<String>,result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(table,args,J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "--screen" <> Nil{}: ScreenCases.run()
    case exe <> table <> path <> inputs:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        read : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(table,inputs,read)
    case _: IO.die(Unit,2,"expected table, cooking context and focused menu fixtures")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
