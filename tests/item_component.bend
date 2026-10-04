import Base
import ../src/item_component.bend as C
import ../src/item_component_effects.bend as E
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ../src/nbt.bend as N

# CPU-only observer. The production adapter owns every component admission,
# codec and affine inventory transition. Host code supplies independent inputs.
def text(value:String) -> J.Value: J.JString{value}
def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}
def boolean(value:Bool) -> J.Value: J.JBool{value}
def object(values:List<&2,J.Member>) -> J.Value: J.JObject{values}

def error(message:String) -> J.Value:
  object([J.JMember{"accepted",boolean(False{})},J.JMember{"error",text(message)}])

def effects(values:List<&2,E.Effect>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case E.Effect{kind,ticks} <> rest:
      J.JArray{[text(E.kind_name(kind)),number(ticks)]} <> effects(rest)

def profile(value:C.Components) -> J.Value:
  C.SuspiciousStew{values} = value
  J.JArray{effects(values)}

def slot(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      object([J.JMember{"id",text(id)},J.JMember{"components",text(components)},J.JMember{"count",number(count)}])

def slots(values:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: slot(value) <> slots(rest)

def words(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: number(value) <> words(rest)

def encoded(value:Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{bytes}: object([J.JMember{"accepted",boolean(True{})},J.JMember{"bytes",J.JArray{words(bytes)}}])

def reconstructed(value:Result<&2,&2,String,Inv.ItemKey>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{Inv.ItemKey{id,components}}: object([J.JMember{"id",text(id)},J.JMember{"components",text(components)}])

def validated(+defaults:Maybe<&2,C.Defaults>,+count:U32,value:Result<&2,&2,String,C.Validated>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{C.Validated{+key,+components}}:
      Inv.ItemKey{+id,identity} = key
      object([J.JMember{"accepted",boolean(True{})},J.JMember{"components",text(identity)},J.JMember{"effects",profile(components)},
        J.JMember{"rebuilt",reconstructed(C.key(defaults,id,components))},J.JMember{"encoded",encoded(C.encode_bytes(defaults,key,count))}])

def decoded(+defaults:Maybe<&2,C.Defaults>,value:Result<&2,&2,String,Inv.Slot>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{+value}:
      match value:
        case Inv.InvEmpty{}: error("modified stack decoded empty")
        case Inv.InvStack{+key,count}:
          object([J.JMember{"accepted",boolean(True{})},J.JMember{"slot",slot(value)},
            J.JMember{"profile",validated(defaults,count,C.validate(defaults,key))}])

def initialized(value:Result<&2,&2,String,C.Defaults>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{token}: object([J.JMember{"accepted",boolean(True{})}])

def required(value:Maybe<&2,J.Value>,name:String) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"missing fixture " ++ name}
    case Some{value}: Done{value}

def text_value(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{raw}: Done{raw}
    case _: Fail{"fixture string required"}

def number_value(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Fail{"fixture unsigned word required"}
    case Some{value}: Done{value}

def numbers(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        head : U32 <- number_value(J.as_u32(value))
        tail : List<&2,U32> <- numbers(rest)
        return head <> tail

def bytes(value:J.Value) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case J.JArray{values}: numbers(values)
    case _: Fail{"fixture words require array"}

def defaults(value:Maybe<&2,J.Value>) -> Maybe<&2,C.Defaults>:
  match value:
    case Some{J.JBool{True{}}}: C.default_from_identity("minecraft:suspicious_stew",True{},C.default_digest())
    case _: None{}

def fixture_key(+value:J.Value) -> Result<&2,&2,String,Inv.ItemKey>:
  do Result<&2,&2,String,Inv.ItemKey>:
    raw_id : J.Value <- required(J.member(value,"id"),"id")
    id : String <- text_value(raw_id)
    raw_components : J.Value <- required(J.member(value,"components"),"components")
    components : String <- text_value(raw_components)
    return Inv.ItemKey{id,components}

def fixture_number(value:J.Value,+name:String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    raw : J.Value <- required(J.member(value,name),name)
    number_value(J.as_u32(raw))

def fixture_bytes(value:J.Value) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    raw : J.Value <- required(J.member(value,"bytes"),"bytes")
    bytes(raw)

# Includes raw invalid keys/counts and hidden backing slots beyond logical
# length. Refusal must retain all eight entries, not merely a public projection.
def owner() -> Inv.Inventory:
  slots = Array.new(Inv.Slot,3n,Inv.InvEmpty{})
  slots = Array.set(Inv.Slot,slots,0,Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},7})
  slots = Array.set(Inv.Slot,slots,1,Inv.InvStack{Inv.ItemKey{"fixture:raw","arbitrary opaque prior"},4294967295})
  slots = Array.set(Inv.Slot,slots,2,Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},0})
  slots = Array.set(Inv.Slot,slots,4,Inv.InvStack{Inv.ItemKey{"minecraft:suspicious_stew",""},1})
  slots = Array.set(Inv.Slot,slots,5,Inv.InvStack{Inv.ItemKey{"fixture:hidden","\nraw\tidentity"},2147483648})
  slots = Array.set(Inv.Slot,slots,7,Inv.InvStack{Inv.ItemKey{"fixture:last","{malformed}"},31})
  Inv.Inventory{slots,5}

def owner_read_next(result:Array<Inv.Slot> & Inv.Slot,continue:Array<Inv.Slot> -> Inv.Slot -> Inv.Inventory & List<&2,Inv.Slot>) -> Inv.Inventory & List<&2,Inv.Slot>:
  (next,value) = result
  continue(next,value)

def owner_read(left:Nat,+index:U32,length:U32,array:Array<Inv.Slot>,values:List<&2,Inv.Slot>) -> Inv.Inventory & List<&2,Inv.Slot>:
  match left:
    case 0n: (Inv.Inventory{array,length},List.reverse(&2,Inv.Slot,values))
    case 1n+rest:
      owner_read_next(Array.get(Inv.Slot,array,index),next => value => owner_read(rest,U32.add(index,1),length,next,value <> values))

def owner_snapshot_sized(length:U32,result:Array<Inv.Slot> & U32) -> Inv.Inventory & List<&2,Inv.Slot>:
  (array,size) = result
  owner_read(U32.to_nat(size),0,length,array,[])

def owner_snapshot(value:Inv.Inventory) -> Inv.Inventory & List<&2,Inv.Slot>:
  Inv.Inventory{array,length} = value
  owner_snapshot_sized(length,Array.size(Inv.Slot,array))

def status(value:Result<&2,&2,String,Unit>) -> J.Value:
  match value:
    case Fail{message}: error(message)
    case Done{unit}: object([J.JMember{"accepted",boolean(True{})}])

def owner_report_after(before:List<&2,Inv.Slot>,status_value:Result<&2,&2,String,Unit>,result:Inv.Inventory & List<&2,Inv.Slot>) -> J.Value:
  (Inv.Inventory{array,length},after) = result
  object([J.JMember{"status",status(status_value)},J.JMember{"before",J.JArray{slots(before)}},
    J.JMember{"after",J.JArray{slots(after)}},J.JMember{"logical_length",number(length)}])

def owner_report(before:List<&2,Inv.Slot>,result:Inv.Inventory & Result<&2,&2,String,Unit>) -> J.Value:
  (owned,status_value) = result
  owner_report_after(before,status_value,owner_snapshot(owned))

def run_owner_ready(defaults:Maybe<&2,C.Defaults>,key:Inv.ItemKey,count:U32,index:U32,result:Inv.Inventory & List<&2,Inv.Slot>) -> J.Value:
  (owned,before) = result
  owner_report(before,C.load(defaults,owned,index,Inv.InvStack{key,count}))

def run_owner(defaults:Maybe<&2,C.Defaults>,key:Inv.ItemKey,count:U32,index:U32) -> J.Value:
  run_owner_ready(defaults,key,count,index,owner_snapshot(owner()))

def run_owner_bytes_ready(defaults:Maybe<&2,C.Defaults>,bytes:List<&2,U32>,index:U32,result:Inv.Inventory & List<&2,Inv.Slot>) -> J.Value:
  (owned,before) = result
  owner_report(before,C.load_bytes(defaults,owned,index,bytes))

def run_owner_bytes(defaults:Maybe<&2,C.Defaults>,bytes:List<&2,U32>,index:U32) -> J.Value:
  run_owner_bytes_ready(defaults,bytes,index,owner_snapshot(owner()))

def run(+value:J.Value,mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "initialize":
      do Result<&2,&2,String,J.Value>:
        raw : J.Value <- required(J.member(value,"default_map"),"default_map")
        return initialized(C.initialize(raw))
    case "initialize_ast_injection":
      do Result<&2,&2,String,J.Value>:
        raw : J.Value <- required(J.member(value,"raw_number"),"raw_number")
        number : String <- text_value(raw)
        return initialized(C.initialize(J.JObject{[J.JMember{"minecraft:attack_animation",J.JNumber{number}}]}))
    case "validate":
      +known = defaults(J.member(value,"defaults"))
      do Result<&2,&2,String,J.Value>:
        key : Inv.ItemKey <- fixture_key(value)
        count : U32 <- fixture_number(value,"count")
        return validated(known,count,C.validate(known,key))
    case "nbt":
      +known = defaults(J.member(value,"defaults"))
      do Result<&2,&2,String,J.Value>:
        bytes : List<&2,U32> <- fixture_bytes(value)
        return decoded(known,C.decode_bytes(known,bytes))
    case "owner":
      do Result<&2,&2,String,J.Value>:
        key : Inv.ItemKey <- fixture_key(value)
        count : U32 <- fixture_number(value,"count")
        index : U32 <- fixture_number(value,"index")
        return run_owner(defaults(J.member(value,"defaults")),key,count,index)
    case "owner_nbt":
      do Result<&2,&2,String,J.Value>:
        bytes : List<&2,U32> <- fixture_bytes(value)
        index : U32 <- fixture_number(value,"index")
        return run_owner_bytes(defaults(J.member(value,"defaults")),bytes,index)
    case _: Fail{"unknown fixture mode"}

def fixture(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw : J.Value <- required(J.member(value,"mode"),"mode")
    mode : String <- text_value(raw)
    run(value,mode)

def print(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(J.encode(error(message)))
    case Done{value}: IO.print(J.encode(value))

def fixtures(values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        print(fixture(value))
        fixtures(rest)

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: print(Fail{message})
    case Done{J.JArray{values}}: fixtures(values)
    case Done{value}: print(fixture(value))

def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,U32.to_nat(8388608),32))

def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected item component fixture file")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
