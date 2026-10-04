import Base
import ../src/resource_client_wire.bend as Wire
import ../src/client_controls.bend as CC
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/world_visibility.bend as V
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv

# Finite executable probes of the renderer wire contract. Expected JSON is
# assembled independently of Wire's encoder; decoded fields are inspected.
# These fixtures establish the listed cases, not a general protocol law.
def require(valid:Bool,message:String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"resource-client-interaction-wire: " ++ message)

def encoded_is(result:Result<&2,&2,String,String>,expected:String) -> Bool:
  match result:
    case Done{actual}: String.eq(actual,expected)
    case Fail{message}: False{}

def encoded_rejected(result:Result<&2,&2,String,String>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def request_rejected(result:Result<&2,&2,String,Wire.Request>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def reply_rejected(result:Result<&2,&2,String,Wire.Reply>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def bool_same(expected:Bool,actual:Bool) -> Bool:
  match expected actual:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def event_same(expected:Event,actual:Event) -> Bool:
  match expected actual:
    case Key{code,down} Key{other,held}: U32.is_eq(code,other) && bool_same(down,held)
    case Mouse{x,y,button,down} Mouse{ox,oy,ob,held}:
      U32.is_eq(x,ox) && U32.is_eq(y,oy) && U32.is_eq(button,ob) && bool_same(down,held)
    case Move{x,y} Move{ox,oy}: U32.is_eq(x,ox) && U32.is_eq(y,oy)
    case Look{dx,dy} Look{ox,oy}: U32.is_eq(F32.bits(dx),F32.bits(ox)) && U32.is_eq(F32.bits(dy),F32.bits(oy))
    case Scroll{x,y,dx,dy} Scroll{ox,oy,odx,ody}:
      U32.is_eq(x,ox) && U32.is_eq(y,oy) && U32.is_eq(F32.bits(dx),F32.bits(odx)) && U32.is_eq(F32.bits(dy),F32.bits(ody))
    case Close{} Close{}: True{}
    case _ _: False{}

def action_same(expected:CC.Action,actual:CC.Action) -> Bool:
  match expected actual:
    case CC.Release{} CC.Release{}: True{}
    case CC.PlatformEvent{event,captured} CC.PlatformEvent{other,held}:
      event_same(event,other) && bool_same(captured,held)
    case _ _: False{}

def actions_same(expected:List<&2,CC.Action>,actual:List<&2,CC.Action>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> tail other <> rest: action_same(head,other) && actions_same(tail,rest)
    case _ _: False{}

def packet_same(expected:CC.Packet,actual:CC.Packet) -> Bool:
  CC.Packet{actions,focused,captured} = expected
  CC.Packet{other,ofocused,ocaptured} = actual
  actions_same(actions,other) && bool_same(focused,ofocused) && bool_same(captured,ocaptured)

def command_same(expected:Wire.Command,actual:Wire.Command) -> Bool:
  match expected actual:
    case Wire.Frame{width,height} Wire.Frame{ow,oh}: U32.is_eq(width,ow) && U32.is_eq(height,oh)
    case Wire.Input{packet} Wire.Input{other}: packet_same(packet,other)
    case Wire.Release{} Wire.Release{}: True{}
    case Wire.Action{button} Wire.Action{other}: U32.is_eq(button,other)
    case Wire.Hotbar{index} Wire.Hotbar{other}: U32.is_eq(index,other)
    case Wire.Inventory{} Wire.Inventory{}: True{}
    case _ _: False{}

def request_same(expected:Wire.Request,result:Result<&2,&2,String,Wire.Request>) -> Bool:
  match expected result:
    case Wire.Hello{capability} Done{Wire.Hello{other}}: String.eq(capability,other)
    case Wire.Call{epoch,sequence,command} Done{Wire.Call{other,number,body}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number) && command_same(command,body)
    case _ _: False{}

def slot_same(expected:Inv.Slot,actual:Inv.Slot) -> Bool:
  match expected actual:
    case Inv.InvEmpty{} Inv.InvEmpty{}: True{}
    case Inv.InvStack{Inv.ItemKey{id,components},count} Inv.InvStack{Inv.ItemKey{other,payload},amount}:
      String.eq(id,other) && String.eq(components,payload) && U32.is_eq(count,amount)
    case _ _: False{}

def slots_same(expected:List<&2,Inv.Slot>,actual:List<&2,Inv.Slot>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> tail other <> rest: slot_same(head,other) && slots_same(tail,rest)
    case _ _: False{}

def snapshot_same(expected:I.Snapshot,actual:I.Snapshot) -> Bool:
  I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}} = expected
  I.Snapshot{other,items,I.Abilities{creative,build}} = actual
  U32.is_eq(selected,other) && slots_same(slots,items) && bool_same(instabuild,creative) && bool_same(maybuild,build)

def frame_fixture() -> V.Sample:
  V.Sample{R.Snapshot{17n,19n,[],R.Camera{0.0,0.0,0.0,0.0,0.0}},[],[],
    M.Vec3{F.F64{0,0},F.F64{0,0},F.F64{0,0}},W.Palette{0,1,2,3},0}

def frame_fixture_matches(value:V.Sample) -> Bool:
  match value:
    case V.Sample{R.Snapshot{tick,revision,Nil{},R.Camera{x,y,z,yaw,pitch}},Nil{},Nil{},
        M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}},W.Palette{air,stone,dirt,planks},reads}:
      Nat.is_eq(tick,17n) && Nat.is_eq(revision,19n) &&
        U32.is_zero(F32.bits(x)) && U32.is_zero(F32.bits(y)) && U32.is_zero(F32.bits(z)) &&
        U32.is_zero(F32.bits(yaw)) && U32.is_zero(F32.bits(pitch)) &&
        U32.is_zero(xh) && U32.is_zero(xl) && U32.is_zero(yh) && U32.is_zero(yl) && U32.is_zero(zh) && U32.is_zero(zl) &&
        U32.is_zero(air) && U32.is_eq(stone,1) && U32.is_eq(dirt,2) && U32.is_eq(planks,3) && U32.is_zero(reads)
    case _: False{}

def reply_same(expected:Wire.Reply,result:Result<&2,&2,String,Wire.Reply>) -> Bool:
  match expected result:
    case Wire.HelloAck{epoch,sequence} Done{Wire.HelloAck{other,number}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case Wire.FrameReply{epoch,sequence,sample} Done{Wire.FrameReply{other,number,value}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number) && frame_fixture_matches(sample) && frame_fixture_matches(value)
    case Wire.Ack{epoch,sequence} Done{Wire.Ack{other,number}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case Wire.Fault{epoch,sequence,message} Done{Wire.Fault{other,number,diagnostic}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number) && String.eq(message,diagnostic)
    case Wire.InventoryReply{epoch,sequence,snapshot} Done{Wire.InventoryReply{other,number,value}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number) && snapshot_same(snapshot,value)
    case Wire.ActionReply{epoch,sequence,changed,message} Done{Wire.ActionReply{other,number,value,diagnostic}}:
      String.eq(epoch,other) && Nat.is_eq(sequence,number) && bool_same(changed,value) && String.eq(message,diagnostic)
    case _ _: False{}

def request_probe(+id:String,+expected:Wire.Request,+json:String) -> IO(Unit):
  do IO<Unit>:
    require(encoded_is(Wire.encode_request(expected),json),id ++ " exact encoding")
    require(request_same(expected,Wire.decode_request(json)),id ++ " decoding")

def reply_probe(+id:String,+expected:Wire.Reply,+json:String) -> IO(Unit):
  do IO<Unit>:
    require(encoded_is(Wire.encode_reply(expected),json),id ++ " exact encoding")
    require(reply_same(expected,Wire.decode_reply(json)),id ++ " decoding")

def request_refused(+id:String,json:String) -> IO(Unit):
  require(request_rejected(Wire.decode_request(json)),id ++ " admitted invalid request")

def reply_refused(+id:String,json:String) -> IO(Unit):
  require(reply_rejected(Wire.decode_reply(json)),id ++ " admitted invalid reply")

def old_packet() -> CC.Packet:
  CC.Packet{[CC.Release{},CC.PlatformEvent{Key{87,True{}},True{}},
    CC.PlatformEvent{Mouse{4294967295,2147483648,2,False{}},False{}},
    CC.PlatformEvent{Move{2147483648,4294967295},True{}},
    CC.PlatformEvent{Look{Wire.float_bits(2147483648),Wire.float_bits(2143289345)},False{}},
    CC.PlatformEvent{Scroll{9,11,Wire.float_bits(3212836864),Wire.float_bits(1065353216)},True{}},
    CC.PlatformEvent{Close{},False{}}],True{},False{}}

def old_requests() -> IO(Unit):
  do IO<Unit>:
    require(U32.is_eq(Wire.version(),1),"wire version changed")
    request_probe("hello",Wire.Hello{"token"},"[1,0,\"token\"]")
    request_probe("frame command 0",Wire.Call{"wire-epoch",7n,Wire.Frame{64,48}},"[1,1,\"wire-epoch\",7,[0,64,48]]")
    request_probe("input command 1",Wire.Call{"wire-epoch",7n,Wire.Input{old_packet()}},
      "[1,1,\"wire-epoch\",7,[1,[true,false,[[0],[1,true,[0,87,true]],[1,false,[1,4294967295,2147483648,2,false]],[1,true,[2,2147483648,4294967295]],[1,false,[3,2147483648,2143289345]],[1,true,[4,9,11,3212836864,1065353216]],[1,false,[5]]]]]]")
    request_probe("release command 2",Wire.Call{"wire-epoch",7n,Wire.Release{}},"[1,1,\"wire-epoch\",7,[2]]")
    request_refused("old release extra field","[1,1,\"wire-epoch\",7,[2,0]]")
    request_refused("old frame extra field","[1,1,\"wire-epoch\",7,[0,64,48,0]]")
    request_refused("old input extra field","[1,1,\"wire-epoch\",7,[1,[true,false,[]],0]]")
    request_refused("version 2 hello","[2,0,\"token\"]")
    request_refused("version 2 call","[2,1,\"wire-epoch\",7,[2]]")

def new_requests() -> IO(Unit):
  do IO<Unit>:
    request_probe("left action",Wire.Call{"wire-epoch",7n,Wire.Action{0}},"[1,1,\"wire-epoch\",7,[3,0]]")
    request_probe("right action",Wire.Call{"wire-epoch",7n,Wire.Action{1}},"[1,1,\"wire-epoch\",7,[3,1]]")
    request_probe("hotbar first",Wire.Call{"wire-epoch",7n,Wire.Hotbar{0}},"[1,1,\"wire-epoch\",7,[4,0]]")
    request_probe("hotbar 1",Wire.Call{"wire-epoch",7n,Wire.Hotbar{1}},"[1,1,\"wire-epoch\",7,[4,1]]")
    request_probe("hotbar 2",Wire.Call{"wire-epoch",7n,Wire.Hotbar{2}},"[1,1,\"wire-epoch\",7,[4,2]]")
    request_probe("hotbar 3",Wire.Call{"wire-epoch",7n,Wire.Hotbar{3}},"[1,1,\"wire-epoch\",7,[4,3]]")
    request_probe("hotbar 4",Wire.Call{"wire-epoch",7n,Wire.Hotbar{4}},"[1,1,\"wire-epoch\",7,[4,4]]")
    request_probe("hotbar 5",Wire.Call{"wire-epoch",7n,Wire.Hotbar{5}},"[1,1,\"wire-epoch\",7,[4,5]]")
    request_probe("hotbar 6",Wire.Call{"wire-epoch",7n,Wire.Hotbar{6}},"[1,1,\"wire-epoch\",7,[4,6]]")
    request_probe("hotbar 7",Wire.Call{"wire-epoch",7n,Wire.Hotbar{7}},"[1,1,\"wire-epoch\",7,[4,7]]")
    request_probe("hotbar last",Wire.Call{"wire-epoch",7n,Wire.Hotbar{8}},"[1,1,\"wire-epoch\",7,[4,8]]")
    request_probe("inventory command",Wire.Call{"wire-epoch",7n,Wire.Inventory{}},"[1,1,\"wire-epoch\",7,[5]]")
    require(encoded_rejected(Wire.encode_request(Wire.Call{"wire-epoch",7n,Wire.Action{2}})),"encode action button 2")
    require(encoded_rejected(Wire.encode_request(Wire.Call{"wire-epoch",7n,Wire.Action{4294967295}})),"encode action button U32 max")
    require(encoded_rejected(Wire.encode_request(Wire.Call{"wire-epoch",7n,Wire.Hotbar{9}})),"encode hotbar 9")
    require(encoded_rejected(Wire.encode_request(Wire.Call{"wire-epoch",7n,Wire.Hotbar{4294967295}})),"encode hotbar U32 max")
    request_refused("action button 2","[1,1,\"wire-epoch\",7,[3,2]]")
    request_refused("action button negative","[1,1,\"wire-epoch\",7,[3,-1]]")
    request_refused("action button fraction","[1,1,\"wire-epoch\",7,[3,0.5]]")
    request_refused("hotbar 9","[1,1,\"wire-epoch\",7,[4,9]]")
    request_refused("hotbar negative","[1,1,\"wire-epoch\",7,[4,-1]]")
    request_refused("hotbar nonnumber","[1,1,\"wire-epoch\",7,[4,true]]")
    request_refused("action extra field","[1,1,\"wire-epoch\",7,[3,0,1]]")
    request_refused("hotbar extra field","[1,1,\"wire-epoch\",7,[4,0,1]]")
    request_refused("inventory extra field","[1,1,\"wire-epoch\",7,[5,0]]")
    request_refused("action missing button","[1,1,\"wire-epoch\",7,[3]]")
    request_refused("hotbar missing index","[1,1,\"wire-epoch\",7,[4]]")
    request_refused("call extra field","[1,1,\"wire-epoch\",7,[5],0]")

def empty_slots(left:Nat) -> List<&2,Inv.Slot>:
  match left:
    case 0n: []
    case 1n+rest: Inv.InvEmpty{} <> empty_slots(rest)

# A list body's commas are generated separately from Wire's JSON projection.
def empty_slot_suffix(empty:Bool,body:String) -> String:
  match empty:
    case True{}: ""
    case False{}: "," ++ body

def empty_slot_body(left:Nat) -> String:
  match left:
    case 0n: ""
    case 1n+ +rest: "[0]" ++ empty_slot_suffix(Nat.is_eq(rest,0n),empty_slot_body(rest))

def inventory_fixture() -> I.Snapshot:
  I.Snapshot{8,Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},64} <> Inv.InvEmpty{} <>
    Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},1} <> Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},32} <> empty_slots(32n),
    I.Abilities{True{},False{}}}

def inventory_fixture_json() -> String:
  "[1,4,\"wire-epoch\",23,[8,true,false,[[1,\"minecraft:stone\",\"\",64],[0],[1,\"minecraft:dirt\",\"\",1],[1,\"minecraft:oak_planks\",\"\",32]," ++ empty_slot_body(32n) ++ "]]]"

def empty_inventory_json(selected:String,count:Nat) -> String:
  "[1,4,\"wire-epoch\",23,[" ++ selected ++ ",false,true,[" ++ empty_slot_body(count) ++ "]]]"

def stack_inventory_json(stack:String) -> String:
  "[1,4,\"wire-epoch\",23,[0,false,true,[" ++ stack ++ "," ++ empty_slot_body(35n) ++ "]]]"

def invalid_inventory_probe(+id:String,+snapshot:I.Snapshot,json:String) -> IO(Unit):
  do IO<Unit>:
    require(encoded_rejected(Wire.encode_reply(Wire.InventoryReply{"wire-epoch",23n,snapshot})),id ++ " encode admitted invalid inventory")
    reply_refused(id,json)

def old_replies() -> IO(Unit):
  do IO<Unit>:
    reply_probe("hello ack tag 0",Wire.HelloAck{"wire-epoch",0n},"[1,0,\"wire-epoch\",0]")
    reply_probe("frame reply tag 1",Wire.FrameReply{"wire-epoch",7n,frame_fixture()},
      "[1,1,\"wire-epoch\",7,[17,19,[0,0,0,0,0,0],[0,0,0,0,0],[0,1,2,3],0,[]]]")
    reply_probe("ack tag 2",Wire.Ack{"wire-epoch",7n},"[1,2,\"wire-epoch\",7]")
    reply_probe("fault tag 3",Wire.Fault{"wire-epoch",7n,"old failure"},"[1,3,\"wire-epoch\",7,\"old failure\"]")
    reply_probe("pre-hello fault",Wire.Fault{"",0n,"unleased"},"[1,3,\"\",0,\"unleased\"]")
    reply_refused("old ack extra field","[1,2,\"wire-epoch\",7,0]")
    reply_refused("reply version 2","[2,2,\"wire-epoch\",7]")

def inventory_replies() -> IO(Unit):
  do IO<Unit>:
    reply_probe("inventory tag 4",Wire.InventoryReply{"wire-epoch",23n,inventory_fixture()},inventory_fixture_json())
    reply_probe("empty survival inventory",Wire.InventoryReply{"wire-epoch",23n,I.Snapshot{0,empty_slots(36n),I.Abilities{False{},True{}}}},empty_inventory_json("0",36n))
    invalid_inventory_probe("inventory 35 slots",I.Snapshot{0,empty_slots(35n),I.Abilities{False{},True{}}},empty_inventory_json("0",35n))
    invalid_inventory_probe("inventory 37 slots",I.Snapshot{0,empty_slots(37n),I.Abilities{False{},True{}}},empty_inventory_json("0",37n))
    invalid_inventory_probe("inventory selected 9",I.Snapshot{9,empty_slots(36n),I.Abilities{False{},True{}}},empty_inventory_json("9",36n))
    invalid_inventory_probe("unsupported item",I.Snapshot{0,Inv.InvStack{Inv.ItemKey{"minecraft:bedrock",""},1} <> empty_slots(35n),I.Abilities{False{},True{}}},
      stack_inventory_json("[1,\"minecraft:bedrock\",\"\",1]"))
    invalid_inventory_probe("modified components",I.Snapshot{0,Inv.InvStack{Inv.ItemKey{"minecraft:stone","{}"},1} <> empty_slots(35n),I.Abilities{False{},True{}}},
      stack_inventory_json("[1,\"minecraft:stone\",\"{}\",1]"))
    invalid_inventory_probe("stack count 0",I.Snapshot{0,Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},0} <> empty_slots(35n),I.Abilities{False{},True{}}},
      stack_inventory_json("[1,\"minecraft:stone\",\"\",0]"))
    invalid_inventory_probe("stack count 65",I.Snapshot{0,Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},65} <> empty_slots(35n),I.Abilities{False{},True{}}},
      stack_inventory_json("[1,\"minecraft:stone\",\"\",65]"))
    reply_refused("empty slot extra field",stack_inventory_json("[0,0]"))
    reply_refused("stack slot extra field",stack_inventory_json("[1,\"minecraft:stone\",\"\",1,0]"))
    reply_refused("snapshot extra field","[1,4,\"wire-epoch\",23,[0,false,true,[" ++ empty_slot_body(36n) ++ "],0]]")
    reply_refused("inventory reply extra field","[1,4,\"wire-epoch\",23,[0,false,true,[" ++ empty_slot_body(36n) ++ "]],0]")

def unicode_message() -> String:
  "placed § 😀\n\"\\done"

def action_replies() -> IO(Unit):
  do IO<Unit>:
    reply_probe("changed action tag 5 Unicode",Wire.ActionReply{"wire-epoch",23n,True{},unicode_message()},
      "[1,5,\"wire-epoch\",23,true,\"placed \\u00a7 \\ud83d\\ude00\\n\\\"\\\\done\"]")
    reply_probe("unchanged action empty message",Wire.ActionReply{"wire-epoch",23n,False{},""},"[1,5,\"wire-epoch\",23,false,\"\"]")
    reply_refused("action reply extra field","[1,5,\"wire-epoch\",23,false,\"\",0]")
    reply_refused("action reply changed nonboolean","[1,5,\"wire-epoch\",23,0,\"\"]")
    reply_refused("action reply message nonstring","[1,5,\"wire-epoch\",23,false,0]")
    reply_refused("action message raw non-ASCII","[1,5,\"wire-epoch\",23,true,\"§\"]")
    reply_refused("action message lone surrogate","[1,5,\"wire-epoch\",23,true,\"\\ud83d\"]")
    require(encoded_rejected(Wire.encode_reply(Wire.ActionReply{"wire-epoch",0n,True{},""})),"encode action sequence 0")
    require(encoded_rejected(Wire.encode_reply(Wire.ActionReply{"",23n,True{},""})),"encode action empty epoch")
    reply_refused("action sequence 0","[1,5,\"wire-epoch\",0,true,\"\"]")
    reply_refused("action empty epoch","[1,5,\"\",23,true,\"\"]")

def correlation_cases() -> IO(Unit):
  +inventory = {Wire.InventoryReply{"wire-epoch",23n,inventory_fixture()} : Wire.Reply}
  +action = {Wire.ActionReply{"wire-epoch",23n,True{},unicode_message()} : Wire.Reply}
  do IO<Unit>:
    require(Wire.correlation("wire-epoch",23n,inventory),"inventory matching correlation")
    require(Bool.not(Wire.correlation("other-epoch",23n,inventory)),"inventory mismatched epoch")
    require(Bool.not(Wire.correlation("wire-epoch",24n,inventory)),"inventory mismatched sequence")
    require(Wire.correlation("wire-epoch",23n,action),"action matching correlation")
    require(Bool.not(Wire.correlation("other-epoch",23n,action)),"action mismatched epoch")
    require(Bool.not(Wire.correlation("wire-epoch",24n,action)),"action mismatched sequence")
    require(encoded_rejected(Wire.encode_reply(Wire.InventoryReply{"wire-epoch",0n,inventory_fixture()})),"encode inventory sequence 0")
    require(encoded_rejected(Wire.encode_reply(Wire.InventoryReply{"",23n,inventory_fixture()})),"encode inventory empty epoch")
    reply_refused("inventory sequence 0","[1,4,\"wire-epoch\",0,[0,false,true,[" ++ empty_slot_body(36n) ++ "]]]")
    reply_refused("inventory empty epoch","[1,4,\"\",23,[0,false,true,[" ++ empty_slot_body(36n) ++ "]]]")

def encoded_failure_is(result:Result<&2,&2,String,String>,expected:String) -> Bool:
  match result:
    case Fail{message}: String.eq(message,expected)
    case Done{value}: False{}

def request_failure_is(result:Result<&2,&2,String,Wire.Request>,expected:String) -> Bool:
  match result:
    case Fail{message}: String.eq(message,expected)
    case Done{value}: False{}

def reply_failure_is(result:Result<&2,&2,String,Wire.Reply>,expected:String) -> Bool:
  match result:
    case Fail{message}: String.eq(message,expected)
    case Done{value}: False{}

def repeated(left:Nat,+character:Char) -> String:
  match left:
    case 0n: ""
    case 1n+rest: SCon{character,repeated(rest,character)}

type BudgetRows is Data:
  BudgetRows{raw:List<&2,W.RawBlock>,blocks:List<&2,R.Block>,masks:List<&2,V.Visibility>}

def budget_prepend(+index:U32,remaining:BudgetRows) -> BudgetRows:
  BudgetRows{raw,blocks,masks} = remaining
  +cell = {W.Cell{U32.sub(0,index),4294967295,4294967295,0} : W.Cell}
  BudgetRows{W.RawBlock{cell,1,0} <> raw,
    R.Block{F32.neg(U32.to_f32(index)),Wire.float_bits(3212836864),Wire.float_bits(3212836864),1,0} <> blocks,
    V.Visibility{cell,1,63} <> masks}

def budget_rows(left:Nat,+index:U32) -> BudgetRows:
  match left:
    case 0n: BudgetRows{[],[],[]}
    case 1n+rest: budget_prepend(index,budget_rows(rest,U32.add(index,1)))

def budget_sample_from(count:U32,rows:BudgetRows) -> V.Sample:
  BudgetRows{raw,blocks,masks} = rows
  V.Sample{R.Snapshot{17n,19n,blocks,R.Camera{0.0,0.0,0.0,0.0,0.0}},raw,masks,
    M.Vec3{F.F64{0,0},F.F64{0,0},F.F64{0,0}},W.Palette{0,1,2,3},U32.mul(count,6)}

def budget_sample(+count:U32) -> V.Sample:
  budget_sample_from(count,budget_rows(U32.to_nat(count),1))

# Expected row text uses only integer/float primitives, never Wire's DTO
# projection. Coordinates -1 through -count are unique; all raw words survive.
def budget_row_json(+index:U32) -> String:
  "[" ++ U32.show(U32.sub(0,index)) ++ ",4294967295,4294967295,0,1,0,63," ++
    U32.show(F32.bits(F32.neg(U32.to_f32(index)))) ++ ",3212836864,3212836864]"

def budget_row_body(left:Nat,+index:U32) -> String:
  match left:
    case 0n: ""
    case 1n+ +rest: budget_row_json(index) ++
      empty_slot_suffix(Nat.is_eq(rest,0n),budget_row_body(rest,U32.add(index,1)))

def budget_frame_json(+count:U32) -> String:
  "[1,1,\"wire-epoch\",31,[17,19,[0,0,0,0,0,0],[0,0,0,0,0],[0,1,2,3]," ++
    U32.show(U32.mul(count,6)) ++ ",[" ++ budget_row_body(U32.to_nat(count),1) ++ "]]]"

def budget_rows_match(left:Nat,+index:U32,raw:List<&2,W.RawBlock>,blocks:List<&2,R.Block>,masks:List<&2,V.Visibility>) -> Bool:
  match left raw blocks masks:
    case 0n Nil{} Nil{} Nil{}: True{}
    case 1n+rest W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> tail
        R.Block{bx,by,bz,bs,bm} <> remaining
        V.Visibility{W.Cell{mx,my,mz,mb},ms,visible} <> other:
      +coordinate = U32.sub(0,index)
      U32.is_eq(x,coordinate) && U32.is_eq(y,4294967295) && U32.is_eq(z,4294967295) && U32.is_zero(boundary) &&
        U32.is_eq(state,1) && U32.is_zero(material) &&
        U32.is_eq(F32.bits(bx),F32.bits(F32.neg(U32.to_f32(index)))) &&
        U32.is_eq(F32.bits(by),3212836864) && U32.is_eq(F32.bits(bz),3212836864) && U32.is_eq(bs,1) && U32.is_zero(bm) &&
        U32.is_eq(mx,coordinate) && U32.is_eq(my,4294967295) && U32.is_eq(mz,4294967295) && U32.is_zero(mb) &&
        U32.is_eq(ms,1) && U32.is_eq(visible,63) && budget_rows_match(rest,U32.add(index,1),tail,remaining,other)
    case _ _ _ _: False{}

def budget_sample_matches(+count:U32,value:V.Sample) -> Bool:
  match value:
    case V.Sample{R.Snapshot{tick,revision,blocks,R.Camera{x,y,z,yaw,pitch}},raw,masks,
        M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}},W.Palette{air,stone,dirt,planks},reads}:
      Nat.is_eq(tick,17n) && Nat.is_eq(revision,19n) &&
        U32.is_zero(F32.bits(x)) && U32.is_zero(F32.bits(y)) && U32.is_zero(F32.bits(z)) &&
        U32.is_zero(F32.bits(yaw)) && U32.is_zero(F32.bits(pitch)) &&
        U32.is_zero(xh) && U32.is_zero(xl) && U32.is_zero(yh) && U32.is_zero(yl) && U32.is_zero(zh) && U32.is_zero(zl) &&
        U32.is_zero(air) && U32.is_eq(stone,1) && U32.is_eq(dirt,2) && U32.is_eq(planks,3) &&
        U32.is_eq(reads,U32.mul(count,6)) && budget_rows_match(U32.to_nat(count),1,raw,blocks,masks)

def budget_reply_matches(count:U32,value:Wire.Reply) -> Bool:
  match value:
    case Wire.FrameReply{epoch,sequence,sample}:
      String.eq(epoch,"wire-epoch") && Nat.is_eq(sequence,31n) && budget_sample_matches(count,sample)
    case _: False{}

def large_frame_decoded(result:Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,"large frame decoding: " ++ message)
    case Done{+reply}:
      do IO<Unit>:
        require(budget_reply_matches(256,reply),"large frame all 256 rows/fields retained")
        require(Wire.correlation("wire-epoch",31n,reply),"large frame correlation")
        require(Bool.not(Wire.correlation("other-epoch",31n,reply)),"large frame mismatched epoch")
        require(Bool.not(Wire.correlation("wire-epoch",32n,reply)),"large frame mismatched sequence")

def frame_budget_cases() -> IO(Unit):
  +json = budget_frame_json(256)
  do IO<Unit>:
    require(Nat.is_eq(String.length(json),19784n),"256-row frame exact 19784 ASCII characters")
    require(Nat.is_gt(String.length(json),16384n) && Nat.is_le(String.length(json),65536n),"large frame straddles old/new character bounds")
    require(encoded_is(Wire.encode_reply(Wire.FrameReply{"wire-epoch",31n,budget_sample(256)}),json),"large frame exact encoding")
    large_frame_decoded(Wire.decode_reply(json))
    # 1024 rows have 11292 AST values and 78920 ASCII characters: only the
    # transport gate refuses this otherwise valid sample and AST.
    require(encoded_failure_is(Wire.encode_reply(Wire.FrameReply{"wire-epoch",31n,budget_sample(1024)}),"wire:encoded-transport-parser-budget"),"1024-row frame exceeds transport, not AST")
    require(reply_failure_is(Wire.decode_reply(budget_frame_json(1024)),"wire:ASCII-or-transport-parser-budget"),"1024-row frame decode transport gate")
    # Full 4096-row samples remain in the domain. Their 45084 AST values are
    # refused before serialization; 4097 rows fail the sample domain guard.
    require(encoded_failure_is(Wire.encode_reply(Wire.FrameReply{"wire-epoch",31n,budget_sample(4096)}),"wire:encoded-value-budget"),"4096-row sample admitted, oversized AST refused")
    require(encoded_failure_is(Wire.encode_reply(Wire.FrameReply{"wire-epoch",31n,budget_sample(4097)}),"wire:invalid-reply"),"4097-row sample domain refused")
    require(U32.is_eq(Wire.sample_blocks(),4096) && U32.is_eq(Wire.parser_depth(),8),"sample/depth bounds retained")

def release_actions(left:Nat) -> List<&2,CC.Action>:
  match left:
    case 0n: []
    case 1n+rest: CC.Release{} <> release_actions(rest)

def release_packet_json(count:Nat) -> String:
  "[1,1,\"wire-epoch\",7,[1,[true,true,[" ++ empty_slot_body(count) ++ "]]]]"

def nonframe_budget_cases() -> IO(Unit):
  +capability = repeated(256n,Chr{120})
  +too_long_capability = repeated(257n,Chr{120})
  +diagnostic = repeated(2048n,Chr{120})
  +too_long_diagnostic = repeated(2049n,Chr{120})
  do IO<Unit>:
    request_probe("capability 256 boundary",Wire.Hello{capability},"[1,0,\"" ++ capability ++ "\"]")
    require(encoded_rejected(Wire.encode_request(Wire.Hello{too_long_capability})),"capability 257 encode refused")
    request_refused("capability 257 decode","[1,0,\"" ++ too_long_capability ++ "\"]")
    reply_probe("diagnostic 2048 boundary",Wire.ActionReply{"wire-epoch",23n,True{},diagnostic},"[1,5,\"wire-epoch\",23,true,\"" ++ diagnostic ++ "\"]")
    require(encoded_rejected(Wire.encode_reply(Wire.ActionReply{"wire-epoch",23n,True{},too_long_diagnostic})),"action diagnostic 2049 encode refused")
    reply_refused("action diagnostic 2049 decode","[1,5,\"wire-epoch\",23,true,\"" ++ too_long_diagnostic ++ "\"]")
    require(encoded_rejected(Wire.encode_reply(Wire.Fault{"wire-epoch",23n,too_long_diagnostic})),"fault diagnostic 2049 encode refused")
    reply_refused("fault diagnostic 2049 decode","[1,3,\"wire-epoch\",23,\"" ++ too_long_diagnostic ++ "\"]")
    request_probe("input 1024 actions boundary",Wire.Call{"wire-epoch",7n,Wire.Input{CC.Packet{release_actions(1024n),True{},True{}}}},release_packet_json(1024n))
    require(encoded_rejected(Wire.encode_request(Wire.Call{"wire-epoch",7n,Wire.Input{CC.Packet{release_actions(1025n),True{},True{}}}})),"input 1025 actions encode refused")
    request_refused("input 1025 actions decode",release_packet_json(1025n))

def zero_body(left:Nat) -> String:
  match left:
    case 0n: ""
    case 1n+ +rest: "0" ++ empty_slot_suffix(Nat.is_eq(rest,0n),zero_body(rest))

def independent_budget_cases() -> IO(Unit):
  +ack = {"[1,2,\"wire-epoch\",23]" : String}
  +at_limit = ack ++ repeated(65515n,Chr{32})
  +over_limit = ack ++ repeated(65516n,Chr{32})
  do IO<Unit>:
    require(Nat.is_eq(String.length(at_limit),65536n),"padded ack 65536 characters")
    require(reply_same(Wire.Ack{"wire-epoch",23n},Wire.decode_reply(at_limit)),"65536-character ASCII input admitted")
    require(Nat.is_eq(String.length(over_limit),65537n),"padded ack 65537 characters")
    require(reply_failure_is(Wire.decode_reply(over_limit),"wire:ASCII-or-transport-parser-budget"),"65537-character ASCII input refused")
    # One array container plus 16383 numeric scalars consumes exactly 16384
    # AST values. It reaches DTO validation; the next scalar fails AST admission.
    require(request_failure_is(Wire.decode_request("[" ++ zero_body(16383n) ++ "]"),"wire:request-version-tag-or-cardinality"),"16384 AST values reach DTO schema")
    require(request_failure_is(Wire.decode_request("[" ++ zero_body(16384n) ++ "]"),"wire:value-budget"),"16385 AST values refused independently of characters")

def run() -> IO(Unit):
  do IO<Unit>:
    old_requests()
    new_requests()
    old_replies()
    inventory_replies()
    action_replies()
    correlation_cases()
    frame_budget_cases()
    nonframe_budget_cases()
    independent_budget_cases()
    IO.print("PASS resource-client-interaction-wire: version 1, old/new commands and replies, exact JSON, inventory validation, correlation, Unicode, independent wire budgets")

def main() -> IO(Unit):
  run()
