import Base
import ./item_component.bend as Fixture
import ../src/resource_client_wire.bend as W
import ../src/player_cooking_menu.bend as Menu
import ../src/cooking_recipe.bend as K
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/core.bend as Core
import ../src/json.bend as J

# Observe actual typed values independently of W's JSON encoder. Host literals
# supply the expected packet and all observed fields; no Backend fixture owner.
def strings(+value:J.Value,+name:String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    raw:J.Value <- Fixture.required(J.member(value,name),name)
    Fixture.text_value(raw)

def position(value:Core.Position) -> J.Value:
  Core.Position{dimension,x,y,z} = value
  J.JArray{[Fixture.text(dimension),Fixture.number(x),Fixture.number(y),Fixture.number(z)]}

def kind(value:K.CookingKind) -> J.Value:
  match value:
    case K.Smelting{}: Fixture.number(0)
    case K.Blasting{}: Fixture.number(1)
    case K.Smoking{}: Fixture.number(2)
    case K.Campfire{}: Fixture.number(3)

def handle(value:Menu.Handle) -> J.Value:
  match value:
    case Menu.Closed{}: J.JNull{}
    case Menu.Furnace{menu,peer,at,block,family,incarnation}:
      Fixture.object([J.JMember{"menu",Fixture.number(menu)},J.JMember{"peer",Fixture.number(peer)},
        J.JMember{"position",position(at)},J.JMember{"block",Fixture.text(block)},
        J.JMember{"kind",kind(family)},J.JMember{"incarnation",W.n(incarnation)}])

def furnace(value:Maybe<&2,Menu.FurnaceView>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{Menu.FurnaceView{family,K.FurnaceSlots{input,fuel,output},a,b,c,d}}:
      Fixture.object([J.JMember{"kind",kind(family)},
        J.JMember{"slots",J.JArray{[Fixture.slot(input),Fixture.slot(fuel),Fixture.slot(output)]}},
        J.JMember{"timers",J.JArray{[Fixture.number(a),Fixture.number(b),Fixture.number(c),Fixture.number(d)]}}])

def result_slot(value:Maybe<&2,Inv.Slot>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{slot}: Fixture.slot(slot)

def inventory(value:I.MenuSnapshot) -> J.Value:
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,I.Abilities{creative,build}},equipment,
    I.Status{invulnerable,mayfly,flying,walking_speed,flying_speed}},craft,carried,result,opened,revision} = value
  Fixture.object([J.JMember{"selected",Fixture.number(selected)},
    J.JMember{"abilities",J.JArray{[Fixture.boolean(creative),Fixture.boolean(build)]}},
    J.JMember{"main",J.JArray{Fixture.slots(main)}},J.JMember{"equipment",J.JArray{Fixture.slots(equipment)}},
    J.JMember{"status",J.JArray{[Fixture.boolean(invulnerable),Fixture.boolean(mayfly),Fixture.boolean(flying),Fixture.number(walking_speed),Fixture.number(flying_speed)]}},
    J.JMember{"craft",J.JArray{Fixture.slots(craft)}},J.JMember{"carried",Fixture.slot(carried)},
    J.JMember{"result",result_slot(result)},J.JMember{"opened",Fixture.boolean(opened)},J.JMember{"revision",W.n(revision)}])

def command(value:W.Command) -> J.Value:
  match value:
    case W.CookingOpen{at}: J.JArray{[Fixture.number(14),position(at)]}
    case W.CookingInspect{menu}: J.JArray{[Fixture.number(15),Fixture.number(menu)]}
    case W.CookingClick{menu,index,button}: J.JArray{[Fixture.number(16),Fixture.number(menu),Fixture.number(index),Fixture.number(button)]}
    case W.CookingQuickMove{menu,index}: J.JArray{[Fixture.number(17),Fixture.number(menu),Fixture.number(index)]}
    case W.CookingClose{menu}: J.JArray{[Fixture.number(18),Fixture.number(menu)]}
    case W.CookingUse{offhand}: J.JArray{[Fixture.number(19),Fixture.boolean(offhand)]}
    case other: W.command_value(other)

def request(value:W.Request) -> J.Value:
  match value:
    case W.Hello{capability}: Fixture.object([J.JMember{"capability",Fixture.text(capability)}])
    case W.Call{epoch,sequence,body}: Fixture.object([J.JMember{"epoch",Fixture.text(epoch)},
      J.JMember{"sequence",W.n(sequence)},J.JMember{"command",command(body)}])

def reply(value:W.Reply) -> J.Value:
  match value:
    case W.CookingReply{epoch,sequence,accepted,message,Menu.Snapshot{h,f,i}}:
      Fixture.object([J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)},
        J.JMember{"accepted",Fixture.boolean(accepted)},J.JMember{"message",Fixture.text(message)},
        J.JMember{"handle",handle(h)},J.JMember{"furnace",furnace(f)},J.JMember{"inventory",inventory(i)}])
    case W.HelloAck{epoch,sequence}: Fixture.object([J.JMember{"tag",Fixture.number(0)},
      J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)}])
    case W.Ack{epoch,sequence}: Fixture.object([J.JMember{"tag",Fixture.number(2)},
      J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)}])
    case W.Fault{epoch,sequence,message}: Fixture.object([J.JMember{"tag",Fixture.number(3)},
      J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)},J.JMember{"message",Fixture.text(message)}])
    case W.InventoryReply{epoch,sequence,I.Snapshot{selected,slots,I.Abilities{creative,build}}}:
      Fixture.object([J.JMember{"tag",Fixture.number(4)},J.JMember{"epoch",Fixture.text(epoch)},
        J.JMember{"sequence",W.n(sequence)},J.JMember{"snapshot",Fixture.object([
          J.JMember{"selected",Fixture.number(selected)},J.JMember{"abilities",J.JArray{[Fixture.boolean(creative),Fixture.boolean(build)]}},
          J.JMember{"slots",J.JArray{Fixture.slots(slots)}}])}])
    case W.ActionReply{epoch,sequence,changed,message}: Fixture.object([J.JMember{"tag",Fixture.number(5)},
      J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)},
      J.JMember{"changed",Fixture.boolean(changed)},J.JMember{"message",Fixture.text(message)}])
    case W.MenuReply{epoch,sequence,accepted,message,snapshot}: Fixture.object([J.JMember{"tag",Fixture.number(6)},
      J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",W.n(sequence)},
      J.JMember{"accepted",Fixture.boolean(accepted)},J.JMember{"message",Fixture.text(message)},J.JMember{"inventory",inventory(snapshot)}])
    case _: J.JNull{}

def encoded(value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{text}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"text",Fixture.text(text)}])

def decoded_request(value:Result<&2,&2,String,W.Request>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+value}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},
      J.JMember{"observed",request(value)},J.JMember{"encoded",encoded(W.encode_request(value))}])

def decoded_reply(value:Result<&2,&2,String,W.Reply>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+value}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},
      J.JMember{"observed",reply(value)},J.JMember{"encoded",encoded(W.encode_reply(value))}])

def encoded_request(+value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.object([J.JMember{"encoded",encoded(value)}])
    case Done{text}: Fixture.object([J.JMember{"encoded",encoded(value)},J.JMember{"decoded",decoded_request(W.decode_request(text))}])

def encoded_reply(+value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.object([J.JMember{"encoded",encoded(value)}])
    case Done{text}: Fixture.object([J.JMember{"encoded",encoded(value)},J.JMember{"decoded",decoded_reply(W.decode_reply(text))}])

def plain(id:String,count:U32) -> Inv.Slot: Inv.InvStack{Inv.ItemKey{id,""},count}
def stew(components:String) -> Inv.Slot: Inv.InvStack{Inv.ItemKey{"minecraft:suspicious_stew",components},1}

def main_slots(left:Nat,+index:U32,+components:String) -> List<&2,Inv.Slot>:
  match left:
    case 0n: []
    case 1n+rest:
      match index:
        case 7: stew(components) <> main_slots(rest,U32.add(index,1),components)
        case _: plain("minecraft:stone",U32.add(index,1)) <> main_slots(rest,U32.add(index,1),components)

def empty_slots(left:Nat) -> List<&2,Inv.Slot>:
  match left:
    case 0n: []
    case 1n+rest: Inv.InvEmpty{} <> empty_slots(rest)

def empty_inventory() -> I.MenuSnapshot:
  I.MenuSnapshot{I.Persisted{I.Snapshot{0,empty_slots(36n),I.Abilities{False{},True{}}},empty_slots(7n),
    I.Status{False{},False{},False{},1036831949,1028443341}},empty_slots(4n),Inv.InvEmpty{},None{},False{},0n}

def fixture_main_count(variant:String) -> Nat:
  match variant:
    case "short_main": 35n
    case "long_main": 37n
    case _: 36n

def equipment_slots() -> List<&2,Inv.Slot>:
  [plain("minecraft:diamond_boots",1),plain("minecraft:diamond_leggings",1),plain("minecraft:diamond_chestplate",1),
    plain("minecraft:diamond_helmet",1),plain("minecraft:shield",1),plain("minecraft:wolf_armor",1),plain("minecraft:saddle",1)]

def fixture_equipment(variant:String) -> List<&2,Inv.Slot>:
  match variant:
    case "short_equipment": List.take(&2,Inv.Slot,equipment_slots(),6n)
    case "long_equipment": plain("minecraft:dirt",8) <> equipment_slots()
    case _: equipment_slots()

def craft_slots(components:String) -> List<&2,Inv.Slot>:
  [plain("minecraft:diamond",1),plain("minecraft:stone",2),stew(components),plain("minecraft:oak_planks",4)]

def fixture_craft(variant:String,components:String) -> List<&2,Inv.Slot>:
  match variant:
    case "short_craft": List.take(&2,Inv.Slot,craft_slots(components),3n)
    case "long_craft": plain("minecraft:dirt",5) <> craft_slots(components)
    case _: craft_slots(components)

def full_inventory(+variant:String,+components:String) -> I.MenuSnapshot:
  I.MenuSnapshot{I.Persisted{I.Snapshot{8,main_slots(fixture_main_count(variant),0,components),I.Abilities{True{},False{}}},fixture_equipment(variant),
    I.Status{True{},False{},True{},2147483648,2143289345}},fixture_craft(variant,components),stew(components),Some{stew(components)},True{},W.nat_max()}

def fixture_kind(variant:String) -> K.CookingKind:
  match variant:
    case "blasting": K.Blasting{}
    case "smoking": K.Smoking{}
    case "campfire": K.Campfire{}
    case _: K.Smelting{}

def fixture_block(variant:String) -> String:
  match variant:
    case "blasting": "minecraft:blast_furnace"
    case "smoking": "minecraft:smoker"
    case "campfire": "minecraft:campfire"
    case "wrong_block": "minecraft:smoker"
    case _: "minecraft:furnace"

def fixture_position(variant:String) -> Core.Position:
  match variant:
    case "unknown_dimension": Core.Position{"fixture:unknown",4294967295,2147483648,4294967294}
    case _: Core.Position{"minecraft:the_end",4294967295,2147483648,4294967294}

def fixture_menu_id(variant:String) -> U32:
  match variant:
    case "menu_zero": 0
    case _: 23

def fixture_handle(+variant:String) -> Menu.Handle:
  match variant:
    case "closed": Menu.Closed{}
    case "closed_with_furnace": Menu.Closed{}
    case _: Menu.Furnace{fixture_menu_id(variant),7,fixture_position(variant),fixture_block(variant),fixture_kind(variant),W.nat_max()}

def fixture_view_kind(+variant:String) -> K.CookingKind:
  match variant:
    case "kind_mismatch": K.Smoking{}
    case _: fixture_kind(variant)

def fixture_furnace_slots(variant:String,components:String) -> K.FurnaceSlots:
  match variant:
    case "single_large": K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},stew(components)}
    case _: K.FurnaceSlots{plain("minecraft:iron_ore",64),plain("minecraft:coal",17),stew(components)}

def fixture_furnace(+variant:String,components:String) -> Maybe<&2,Menu.FurnaceView>:
  match variant:
    case "closed": None{}
    case "unavailable": None{}
    case _: Some{Menu.FurnaceView{fixture_view_kind(variant),fixture_furnace_slots(variant,components),
      4294967295,2147483648,4294967294,2147483647}}

def fixture_inventory(+variant:String,components:String) -> I.MenuSnapshot:
  match variant:
    case "single_large": empty_inventory()
    case _: full_inventory(variant,components)

def fixture_snapshot(+variant:String,+components:String) -> Menu.Snapshot:
  Menu.Snapshot{fixture_handle(variant),fixture_furnace(variant,components),fixture_inventory(variant,components)}

def fixture_command(+variant:String,menu:U32,index:U32,button:U32) -> Result<&2,&2,String,W.Command>:
  match variant:
    case "open": Done{W.CookingOpen{fixture_position(variant)}}
    case "unknown_dimension": Done{W.CookingOpen{fixture_position(variant)}}
    case "inspect": Done{W.CookingInspect{menu}}
    case "click": Done{W.CookingClick{menu,index,button}}
    case "quick_move": Done{W.CookingQuickMove{menu,index}}
    case "close": Done{W.CookingClose{menu}}
    case "use_main": Done{W.CookingUse{False{}}}
    case "use_offhand": Done{W.CookingUse{True{}}}
    case _: Fail{"unknown typed command fixture"}

def run(+value:J.Value,mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "decode_request":
      do Result<&2,&2,String,J.Value>:
        text:String <- strings(value,"text")
        return decoded_request(W.decode_request(text))
    case "decode_reply":
      do Result<&2,&2,String,J.Value>:
        text:String <- strings(value,"text")
        return decoded_reply(W.decode_reply(text))
    case "encode_request":
      do Result<&2,&2,String,J.Value>:
        variant:String <- strings(value,"variant")
        menu:U32 <- Fixture.fixture_number(value,"menu")
        index:U32 <- Fixture.fixture_number(value,"index")
        button:U32 <- Fixture.fixture_number(value,"button")
        body:W.Command <- fixture_command(variant,menu,index,button)
        return encoded_request(W.encode_request(W.Call{"cooking-wire",W.nat_max(),body}))
    case "encode_reply":
      do Result<&2,&2,String,J.Value>:
        variant:String <- strings(value,"variant")
        components:String <- strings(value,"components")
        return encoded_reply(W.encode_reply(W.CookingReply{"cooking-wire",W.nat_max(),False{},"refused \"quoted\" \\ path α",fixture_snapshot(variant,components)}))
    case _: Fail{"unknown cooking wire fixture mode"}

def fixture(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id:String <- strings(value,"id")
    mode:String <- strings(value,"mode")
    result:J.Value <- run(value,mode)
    return Fixture.object([J.JMember{"id",Fixture.text(id)},J.JMember{"result",result}])

def fixtures(values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Fixture.print(fixture(value))
        fixtures(rest)

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: Fixture.print(Fail{message})
    case Done{J.JArray{values}}: fixtures(values)
    case _: IO.die(Unit,2,"cooking wire fixture array required")

def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input:String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,8388608n,32))

def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file:File <- IO.try(File,File.open(path,"r"))
        result:File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected cooking wire fixture file")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
