import Base
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./local_player_record.bend as R
import ./local_player_storage.bend as Legacy
import ./player_codec.bend as P
import ./nbt.bend as N
import ./extended_persistence.bend as E

# The existing outer local-player-record schema remains 1. Its legacy payload
# stays byte-identical for a default empty inventory; nondefault state uses an
# explicitly versioned inner root. Legacy record constructors/codecs are intact.
type Saved is Type:
  Saved{record:R.Record,inventory:I.State,fresh:Bool}

def limits() -> E.Limits:
  E.Limits{E.core_limits(E.default_limits()),65536,E.file_limit(E.default_limits())}

def nbt_limits() -> N.Limits:
  N.Limits{65536,4,16384}

def require(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def schema(-A:Data,result:Result<&2,&2,P.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{P.SchemaError{field,message}}: Fail{field ++ ": " ++ message}
    case Fail{cause}: Fail{"invalid player inventory NBT schema"}
    case Done{value}: Done{value}

def record_result(-A:Data,result:Result<&2,&2,R.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{value}: Done{value}

def slot_tag(slot:Inv.Slot) -> N.Value:
  match slot:
    case Inv.InvEmpty{}: N.Compound{[]}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      N.Compound{[P.member("id",N.StringTag{P.text(id)}),P.member("count",N.Int{count})]}

def slot_tags(slots:List<&2,Inv.Slot>) -> List<&2,N.Value>:
  match slots:
    case Nil{}: []
    case slot <> rest: slot_tag(slot) <> slot_tags(rest)

def root(snapshot:I.Snapshot,record:List<&2,U32>) -> N.Root:
  I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}} = snapshot
  N.Root{P.text("bendex:local-player-inventory-record"),N.Compound{[
    P.member("format",N.Int{2}),P.member("record",N.ByteArray{record}),
    P.member("selected",N.Int{selected}),P.member("instabuild",P.bool_tag(instabuild)),
    P.member("maybuild",P.bool_tag(maybuild)),P.member("slots",N.ListTag{10,slot_tags(slots)})]}}

def encode_version(+snapshot:I.Snapshot,bytes:List<&2,U32>,legacy:Bool) -> Result<&2,&2,String,List<&2,U32>>:
  match legacy:
    case True{}: Done{bytes}
    case False{}: N.encode_with(nbt_limits(),root(snapshot,bytes))

def payload(record:R.Record,+snapshot:I.Snapshot) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    require(I.snapshot_valid(snapshot),"invalid inventory state")
    bytes : List<&2,U32> <- record_result(List<&2,U32>,R.encode(record))
    encode_version(snapshot,bytes,I.is_default(snapshot))

def encoded(+record:R.Record,fresh:Bool,result:I.State & I.Snapshot) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  (inventory,snapshot) = result
  (Saved{record,inventory,fresh},payload(record,snapshot))

def encode(saved:Saved) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  Saved{record,inventory,fresh} = saved
  encoded(record,fresh,I.inspect(inventory))

def byte_array(value:N.Value) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case N.ByteArray{bytes}: Done{bytes}
    case _: Fail{"record requires ByteArray"}

def string_value(value:N.Value) -> Result<&2,&2,String,String>:
  match value:
    case N.StringTag{text}: schema(String,P.read_text(text))
    case _: Fail{"id requires String tag"}

def slot_value(value:N.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case N.Compound{Nil{}}: Done{Inv.InvEmpty{}}
    case other:
      do Result<&2,&2,String,Inv.Slot>:
        +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(other,["id","count"]))
        id : String <- string_value(P.field(fields,"id"))
        count : U32 <- schema(U32,P.int_value(P.field(fields,"count"),"count"))
        return Inv.InvStack{Inv.ItemKey{id,""},count}

def slot_values(left:Nat,values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match left values:
    case 0n Nil{}: Done{[]}
    case 1n+n value <> rest:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        slot : Inv.Slot <- slot_value(value)
        tail : List<&2,Inv.Slot> <- slot_values(n,rest)
        return slot <> tail
    case _ _: Fail{"slots requires exactly 36 entries"}

def slots_value(value:N.Value) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match value:
    case N.ListTag{10,values}: slot_values(36n,values)
    case _: Fail{"slots requires Compound list"}

type Projection is Data:
  Projection{record:R.Record,snapshot:I.Snapshot}

def projection(value:N.Value) -> Result<&2,&2,String,Projection>:
  do Result<&2,&2,String,Projection>:
    +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(value,["format","record","selected","instabuild","maybuild","slots"]))
    version : U32 <- schema(U32,P.int_value(P.field(fields,"format"),"format"))
    require(U32.is_eq(version,2),"unsupported player inventory payload version")
    bytes : List<&2,U32> <- byte_array(P.field(fields,"record"))
    record : R.Record <- record_result(R.Record,R.decode(bytes))
    selected : U32 <- schema(U32,P.int_value(P.field(fields,"selected"),"selected"))
    instabuild : Bool <- schema(Bool,P.bool_value(P.field(fields,"instabuild"),"instabuild"))
    maybuild : Bool <- schema(Bool,P.bool_value(P.field(fields,"maybuild"),"maybuild"))
    slots : List<&2,Inv.Slot> <- slots_value(P.field(fields,"slots"))
    return Projection{record,I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}}}

def restored(record:R.Record,result:Result<&2,&1,String,I.State>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{inventory}: Done{Saved{record,inventory,False{}}}

def projected(result:Result<&2,&2,String,Projection>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Projection{record,snapshot}}: restored(record,I.restore(snapshot))

def legacy_decoded(result:Result<&2,&2,R.Error,R.Record>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{record}: Done{Saved{record,I.new(),False{}}}

def decode_named(result:Result<&2,&2,String,String>,+root:N.Root) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{"bendex:local-player-record"}: legacy_decoded(R.decode_root(root))
    case Done{"bendex:local-player-inventory-record"}:
      N.Root{name,value} = root
      projected(projection(value))
    case Done{other}: Fail{"unexpected player inventory record root"}

def decode_root(result:Result<&2,&2,String,N.Root>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{+root}:
      N.Root{name,value} = root
      decode_named(schema(String,P.read_text(name)),root)

def decode(schema:U32,bytes:List<&2,U32>) -> Result<&2,&1,String,Saved>:
  match schema:
    case 1: decode_root(N.decode_with(nbt_limits(),bytes))
    case _: Fail{"unsupported local-player-record schema"}

def initialized(result:Result<&2,&1,String,R.Record>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{record}: Done{Saved{record,I.new(),True{}}}

def initial(unit:Unit) -> Result<&2,&1,String,Saved>:
  initialized(Legacy.initial(unit))

def creative_initialized(result:Result<&2,&1,String,Saved>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Saved{record,inventory,fresh}}:
      Done{Saved{record,I.set_abilities(inventory,I.Abilities{True{},True{}}),fresh}}

# Only fresh missing-world initialization chooses this explicit profile. Decode
# always restores the saved abilities, including the legacy survival defaults.
def initial_creative(unit:Unit) -> Result<&2,&1,String,Saved>:
  creative_initialized(initial(unit))

def refuse_core_only(unit:Unit) -> Result<&2,&1,String,Saved>:
  Fail{"Core-only or plain-Player saves require explicit LocalPlayer migration"}

def codec() -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,decode,initial,refuse_core_only}

def codec_creative() -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,decode,initial_creative,refuse_core_only}
