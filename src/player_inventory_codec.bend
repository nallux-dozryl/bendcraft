import Base
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./local_player_record.bend as R
import ./local_player_storage.bend as Legacy
import ./player_codec.bend as P
import ./nbt.bend as N
import ./extended_persistence.bend as E
import ./player_item_definitions.bend as D
import ./world_generation_settings.bend as WG
import ./world_generation_settings_codec.bend as WGC
import ./player_item_table.bend as Table
import ./item_component_inventory_codec.bend as Components

# The existing outer local-player-record schema remains 1. Its legacy payload
# stays byte-identical for a default empty inventory; nondefault state uses an
# explicitly versioned inner root. Legacy record constructors/codecs are intact.
type Saved is Type:
  Saved{record:R.Record,inventory:I.State,fresh:Bool,generation:WG.Settings}

def limits() -> E.Limits:
  E.Limits{E.core_limits(E.default_limits()),65536,E.file_limit(E.default_limits())}

def nbt_limits() -> N.Limits:
  N.Limits{65536,8,16384}

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
    case Done{inventory}: Done{Saved{record,inventory,False{},WG.legacy()}}

def projected(result:Result<&2,&2,String,Projection>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Projection{record,snapshot}}: restored(record,I.restore(snapshot))

def legacy_decoded(result:Result<&2,&2,R.Error,R.Record>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{record}: Done{Saved{record,I.new(),False{},WG.legacy()}}

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
    case Done{record}: Done{Saved{record,I.new(),True{},WG.legacy()}}

def initial(unit:Unit) -> Result<&2,&1,String,Saved>:
  initialized(Legacy.initial(unit))

def creative_initialized(result:Result<&2,&1,String,Saved>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Saved{record,inventory,fresh,generation}}:
      Done{Saved{record,I.set_abilities(inventory,I.Abilities{True{},True{}}),fresh,generation}}

# Only fresh missing-world initialization chooses this explicit profile. Decode
# always restores the saved abilities, including the legacy survival defaults.
def initial_creative(unit:Unit) -> Result<&2,&1,String,Saved>:
  creative_initialized(initial(unit))

def refuse_core_only(unit:Unit) -> Result<&2,&1,String,Saved>:
  Fail{"Core-only or plain-Player saves require explicit LocalPlayer migration"}

def status_members(status:I.Status) -> List<&2,N.Member>:
  I.Status{invulnerable,mayfly,flying,walking,flying_speed} = status
  [P.member("invulnerable",P.bool_tag(invulnerable)),P.member("mayfly",P.bool_tag(mayfly)),
    P.member("flying",P.bool_tag(flying)),P.member("walking_speed",N.Float{walking}),P.member("flying_speed",N.Float{flying_speed})]

def root_full_tags(saved:I.Persisted,record:List<&2,U32>,generation:List<&2,U32>,slots:List<&2,N.Value>,equipment:List<&2,N.Value>) -> N.Root:
  I.Persisted{I.Snapshot{selected,main,I.Abilities{instabuild,maybuild}},gear,status} = saved
  N.Root{P.text("bendex:local-player-inventory-record"),N.Compound{[
    P.member("format",N.Int{3}),P.member("record",N.ByteArray{record}),P.member("selected",N.Int{selected}),
    P.member("instabuild",P.bool_tag(instabuild)),P.member("maybuild",P.bool_tag(maybuild)),
    P.member("slots",N.ListTag{10,slots}),P.member("equipment",N.ListTag{10,equipment}),
    P.member("abilities",N.Compound{status_members(status)}),P.member("generation",N.ByteArray{generation})]}}

def root_full(+definitions:D.Catalog,+saved:I.Persisted,record:List<&2,U32>,generation:List<&2,U32>) -> Result<&2,&2,String,N.Root>:
  I.Persisted{I.Snapshot{selected,slots,abilities},equipment,status} = saved
  do Result<&2,&2,String,N.Root>:
    main : List<&2,N.Value> <- Components.slot_tags(definitions,slots)
    gear : List<&2,N.Value> <- Components.slot_tags(definitions,equipment)
    return root_full_tags(saved,record,generation,main,gear)

def legacy_status(status:I.Status) -> Bool:
  I.Status{invulnerable,mayfly,flying,walking,flying_speed} = status
  Bool.not(invulnerable) && Bool.not(mayfly) && Bool.not(flying) &&
    U32.is_eq(walking,1036831949) && U32.is_eq(flying_speed,1028443341)

def version_two_eligible(snapshot:I.Persisted,generation:WG.Settings) -> Bool:
  I.Persisted{main,equipment,status} = snapshot
  I.snapshot_valid(main) && I.empty_slots(equipment) && legacy_status(status) && WG.is_legacy(generation)

def payload_full(record:R.Record,+snapshot:I.Persisted,generation:WG.Settings,+definitions:D.Catalog) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    require(I.persisted_valid_with(definitions,snapshot),"invalid full inventory state")
    bytes : List<&2,U32> <- record_result(List<&2,U32>,R.encode(record))
    settings : List<&2,U32> <- WGC.encode(generation)
    root : N.Root <- root_full(definitions,snapshot,bytes,settings)
    N.encode_with(nbt_limits(),root)

def payload_selected(legacy:Bool,record:R.Record,snapshot:I.Persisted,generation:WG.Settings,definitions:D.Catalog) -> Result<&2,&2,String,List<&2,U32>>:
  match legacy:
    case False{}: payload_full(record,snapshot,generation,definitions)
    case True{}:
      I.Persisted{main,equipment,status} = snapshot
      payload(record,main)

def menu_payload(valid:Bool,record:R.Record,+snapshot:I.MenuSnapshot,+generation:WG.Settings,definitions:D.Catalog) -> Result<&2,&2,String,List<&2,U32>>:
  match valid:
    case False{}: Fail{"save refused: temporary crafting or carried items require return/drop authority"}
    case True{}:
      I.MenuSnapshot{+saved,craft,carried,result,opened,revision} = snapshot
      payload_selected(version_two_eligible(saved,generation),record,saved,generation,definitions)

def encoded_payload(record:R.Record,fresh:Bool,generation:WG.Settings,inventory:I.State,payload:Result<&2,&2,String,List<&2,U32>>) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  (Saved{record,inventory,fresh,generation},payload)

def encoded_menu(+record:R.Record,fresh:Bool,+generation:WG.Settings,+definitions:D.Catalog,result:I.State & I.MenuSnapshot) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  (inventory,+snapshot) = result
  encoded_payload(record,fresh,generation,inventory,menu_payload(I.temporary_empty(snapshot),record,snapshot,generation,definitions))

def encoding_definitions(record:R.Record,fresh:Bool,generation:WG.Settings,result:I.State & D.Catalog) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  (inventory,definitions) = result
  encoded_menu(record,fresh,generation,definitions,I.menu_inspect(inventory))

def encode(saved:Saved) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  Saved{record,inventory,fresh,generation} = saved
  encoding_definitions(record,fresh,generation,I.definitions(inventory))

def float_value(value:N.Value,field:String) -> Result<&2,&2,String,U32>:
  match value:
    case N.Float{bits}: Done{bits}
    case _: Fail{field ++ " requires Float tag"}

def status_value(value:N.Value) -> Result<&2,&2,String,I.Status>:
  do Result<&2,&2,String,I.Status>:
    +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(value,["invulnerable","mayfly","flying","walking_speed","flying_speed"]))
    invulnerable : Bool <- schema(Bool,P.bool_value(P.field(fields,"invulnerable"),"invulnerable"))
    mayfly : Bool <- schema(Bool,P.bool_value(P.field(fields,"mayfly"),"mayfly"))
    flying : Bool <- schema(Bool,P.bool_value(P.field(fields,"flying"),"flying"))
    walking : U32 <- float_value(P.field(fields,"walking_speed"),"walking_speed")
    speed : U32 <- float_value(P.field(fields,"flying_speed"),"flying_speed")
    return I.Status{invulnerable,mayfly,flying,walking,speed}

def sized_slots(left:Nat,values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match left values:
    case 0n Nil{}: Done{[]}
    case 1n+n value <> rest:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        slot : Inv.Slot <- slot_value(value)
        tail : List<&2,Inv.Slot> <- sized_slots(n,rest)
        return slot <> tail
    case _ _: Fail{"full inventory slot list has wrong length"}

def sized_value(value:N.Value,count:Nat) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match value:
    case N.ListTag{10,values}: sized_slots(count,values)
    case _: Fail{"full inventory requires Compound slot list"}

type FullProjection is Data:
  FullProjection{record:R.Record,snapshot:I.Persisted,generation:WG.Settings}

def full_projection(+definitions:D.Catalog,value:N.Value) -> Result<&2,&2,String,FullProjection>:
  do Result<&2,&2,String,FullProjection>:
    +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(value,["format","record","selected","instabuild","maybuild","slots","equipment","abilities","generation"]))
    version : U32 <- schema(U32,P.int_value(P.field(fields,"format"),"format"))
    require(U32.is_eq(version,3),"unsupported full inventory payload version")
    bytes : List<&2,U32> <- byte_array(P.field(fields,"record"))
    record : R.Record <- record_result(R.Record,R.decode(bytes))
    selected : U32 <- schema(U32,P.int_value(P.field(fields,"selected"),"selected"))
    instabuild : Bool <- schema(Bool,P.bool_value(P.field(fields,"instabuild"),"instabuild"))
    maybuild : Bool <- schema(Bool,P.bool_value(P.field(fields,"maybuild"),"maybuild"))
    slots : List<&2,Inv.Slot> <- Components.sized_value(definitions,P.field(fields,"slots"),36n)
    equipment : List<&2,Inv.Slot> <- Components.sized_value(definitions,P.field(fields,"equipment"),7n)
    status : I.Status <- status_value(P.field(fields,"abilities"))
    settings : List<&2,U32> <- byte_array(P.field(fields,"generation"))
    generation : WG.Settings <- WGC.decode(settings)
    return FullProjection{record,I.Persisted{I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}},equipment,status},generation}

def full_restored(record:R.Record,generation:WG.Settings,result:Result<&2,&1,String,I.State>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{inventory}: Done{Saved{record,inventory,False{},generation}}

def full_projected(definitions:D.Catalog,result:Result<&2,&2,String,FullProjection>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{FullProjection{record,snapshot,generation}}: full_restored(record,generation,I.restore_persisted(definitions,snapshot))

def empty_equipment() -> List<&2,Inv.Slot>:
  [Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}]

def old_projected(definitions:D.Catalog,result:Result<&2,&2,String,Projection>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Projection{record,snapshot}}:
      full_restored(record,WG.legacy(),I.restore_persisted(definitions,I.Persisted{snapshot,empty_equipment(),I.default_status()}))

def version_root(version:Maybe<&2,N.Value>,+definitions:D.Catalog,value:N.Value) -> Result<&2,&1,String,Saved>:
  match version:
    case Some{N.Int{2}}: old_projected(definitions,projection(value))
    case Some{N.Int{3}}: full_projected(definitions,full_projection(definitions,value))
    case _: Fail{"unsupported inventory format field"}

def is_format(result:Result<&2,&2,P.Error,String>) -> Bool:
  match result:
    case Fail{error}: False{}
    case Done{text}: String.eq(text,"format")

def find_format(members:List<&2,N.Member>) -> Maybe<&2,N.Value>:
  match members:
    case Nil{}: None{}
    case N.Member{name,+value} <> rest:
      N.choose(Maybe<&2,N.Value>,Some{value},find_format(rest),is_format(P.read_text(name)))

def full_root_value(definitions:D.Catalog,+value:N.Value) -> Result<&2,&1,String,Saved>:
  match value:
    case N.Compound{members}: version_root(find_format(members),definitions,value)
    case _: Fail{"inventory root requires Compound"}

def legacy_with(definitions:D.Catalog,result:Result<&2,&2,R.Error,R.Record>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{record}: Done{Saved{record,I.new_with(definitions),False{},WG.legacy()}}

def named_with(name:Result<&2,&2,String,String>,definitions:D.Catalog,+root:N.Root) -> Result<&2,&1,String,Saved>:
  match name:
    case Fail{message}: Fail{message}
    case Done{"bendex:local-player-record"}: legacy_with(definitions,R.decode_root(root))
    case Done{"bendex:local-player-inventory-record"}:
      N.Root{name,value} = root
      full_root_value(definitions,value)
    case _: Fail{"unexpected player inventory root"}

def decoded_with(definitions:D.Catalog,result:Result<&2,&2,String,N.Root>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{+root}:
      N.Root{name,value} = root
      named_with(schema(String,P.read_text(name)),definitions,root)

def decode_with(definitions:D.Catalog,schema:U32,bytes:List<&2,U32>) -> Result<&2,&1,String,Saved>:
  match schema:
    case 1: decoded_with(definitions,N.decode_with(nbt_limits(),bytes))
    case _: Fail{"unsupported local-player-record schema"}

def initial_with_record(definitions:D.Catalog,+creative:Bool,generation:WG.Settings,result:Result<&2,&1,String,R.Record>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{record}: Done{Saved{record,I.set_status(I.set_abilities(I.new_with(definitions),I.Abilities{creative,True{}}),
      I.Status{creative,creative,False{},1036831949,1028443341}),True{},generation}}

def initial_with(+definitions:D.Catalog,+creative:Bool,generation:WG.Settings,unit:Unit) -> Result<&2,&1,String,Saved>:
  initial_with_record(definitions,creative,generation,Legacy.initial(unit))

def codec_with(+definitions:D.Catalog,creative:Bool,generation:WG.Settings) -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,schema => bytes => decode_with(definitions,schema,bytes),
    unit => initial_with(definitions,creative,generation,unit),refuse_core_only}

def codec() -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,decode,initial,refuse_core_only}

def codec_creative() -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,decode,initial_creative,refuse_core_only}

def io_result(-A:Data,result:Result<&2,&2,String,A>) -> Result<&1,&1,U32 & String,A>:
  match result:
    case Fail{message}: Fail{(1,message)}
    case Done{value}: Done{value}

def definitions_text(+bytes:List<&2,U32>) -> Result<&2,&2,String,String>:
  Table.text(bytes)

def definitions_loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(D.Catalog):
  (file,status) = result
  do IO<D.Catalog>:
    File.close(file)
    bytes : List<&2,U32> <- IO.pass(List<&2,U32>,status)
    text : String <- IO.pass(String,io_result(String,definitions_text(bytes)))
    IO.pass(D.Catalog,io_result(D.Catalog,D.parse(text)))

def load_definitions(path:String) -> IO(D.Catalog):
  do IO<D.Catalog>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1048577)
    definitions_loaded(result)
