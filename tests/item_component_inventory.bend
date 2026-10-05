import Base
import ./item_component.bend as Fixture
import ../src/item_component.bend as C
import ../src/item_component_inventory_codec.bend as Slots
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/player_inventory.bend as I
import ../src/player_inventory_codec.bend as IC
import ../src/local_player_record.bend as R
import ../src/world_generation_settings.bend as WG
import ../src/json.bend as J

def raw_slots(values:List<Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: Fixture.slot(value) <> raw_slots(rest)

def state(value:I.State) -> J.Value:
  I.State{Inv.Inventory{array,length},selected,I.Abilities{instabuild,maybuild},I.Profile{definitions,
    I.Status{invulnerable,mayfly,flying,walking_speed,flying_speed},I.Menu{opened,revision,result}}} = value
  Fixture.object([J.JMember{"backing",J.JArray{raw_slots(Array.to_list(~Inv.Slot,array))}},J.JMember{"length",Fixture.number(length)},
    J.JMember{"selected",Fixture.number(selected)},J.JMember{"instabuild",Fixture.boolean(instabuild)},J.JMember{"maybuild",Fixture.boolean(maybuild)},
    J.JMember{"status",J.JArray{[Fixture.boolean(invulnerable),Fixture.boolean(mayfly),Fixture.boolean(flying),Fixture.number(walking_speed),Fixture.number(flying_speed)]}},
    J.JMember{"opened",Fixture.boolean(opened)},J.JMember{"revision",Fixture.number(U32.from_nat(revision))},J.JMember{"catalog_count",Fixture.number(D.count(definitions))}])

def byte_result(value:Result<&2,&2,R.Error,List<&2,U32>>) -> J.Value:
  match value:
    case Fail{cause}: Fixture.error("record encode failed")
    case Done{bytes}: Fixture.encoded(Done{bytes})

def saved(+before:R.Record,value:IC.Saved) -> J.Value:
  IC.Saved{record,inventory,fresh,generation} = value
  Fixture.object([J.JMember{"state",state(inventory)},J.JMember{"fresh",Fixture.boolean(fresh)},
    J.JMember{"record_before",byte_result(R.encode(before))},J.JMember{"record_after",byte_result(R.encode(record))}])

def restored(before:R.Record,value:Result<&2,&1,String,IC.Saved>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{result}: saved(before,result)

def reload(definitions:D.Catalog,before:R.Record,result:Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  match result:
    case Fail{message}: Fixture.error(message)
    case Done{bytes}: restored(before,IC.decode_with(definitions,1,bytes))

def encoded(+definitions:D.Catalog,+before:R.Record,result:IC.Saved & Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  (owner,+payload) = result
  Fixture.object([J.JMember{"owner",saved(before,owner)},J.JMember{"encoded",Fixture.encoded(payload)},
    J.JMember{"reload",reload(definitions,before,payload)}])

def raw_slot(value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case +other:
      do Result<&2,&2,String,Inv.Slot>:
        key : Inv.ItemKey <- Fixture.fixture_key(other)
        count : U32 <- Fixture.fixture_number(other,"count")
        return Inv.InvStack{key,count}

def load_raw_next(result:Result<&2,&2,String,Inv.Slot>,continue:Inv.Slot -> Result<&2,&1,String,Array<Inv.Slot>>) -> Result<&2,&1,String,Array<Inv.Slot>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{slot}: continue(slot)

def load_raw(values:List<&2,J.Value>,+index:U32,array:Array<Inv.Slot>) -> Result<&2,&1,String,Array<Inv.Slot>>:
  match values:
    case Nil{}: Done{array}
    case value <> rest:
      load_raw_next(raw_slot(value),slot => load_raw(rest,U32.add(index,1),Array.set(Inv.Slot,array,index,slot)))

def raw_array(value:J.Value) -> Result<&2,&1,String,Array<Inv.Slot>>:
  match value:
    case J.JArray{values}: load_raw(values,0,Array.new(Inv.Slot,6n,Inv.InvEmpty{}))
    case _: Fail{"fixture backing array required"}

def affine_json(value:Result<&2,&2,String,J.Value>) -> Result<&2,&1,String,J.Value>:
  match value:
    case Fail{message}: Fail{message}
    case Done{result}: Done{result}

def affine_number(value:Result<&2,&2,String,U32>) -> Result<&2,&1,String,U32>:
  match value:
    case Fail{message}: Fail{message}
    case Done{result}: Done{result}

def fixture_array(value:J.Value) -> Result<&2,&1,String,Array<Inv.Slot>>:
  do Result<&2,&1,String,Array<Inv.Slot>>:
    raw : J.Value <- affine_json(Fixture.required(J.member(value,"backing"),"backing"))
    raw_array(raw)

def flag(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JBool{True{}}}: True{}
    case _: False{}

def fixture_state(+definitions:D.Catalog,+value:J.Value) -> Result<&2,&1,String,I.State>:
  do Result<&2,&1,String,I.State>:
    array : Array<Inv.Slot> <- fixture_array(value)
    length : U32 <- affine_number(Fixture.fixture_number(value,"length"))
    selected : U32 <- affine_number(Fixture.fixture_number(value,"selected"))
    walking : U32 <- affine_number(Fixture.fixture_number(value,"walking"))
    flying_speed : U32 <- affine_number(Fixture.fixture_number(value,"flying_speed"))
    revision : U32 <- affine_number(Fixture.fixture_number(value,"revision"))
    return I.State{Inv.Inventory{array,length},selected,I.Abilities{flag(J.member(value,"instabuild")),flag(J.member(value,"maybuild"))},
      I.Profile{definitions,I.Status{flag(J.member(value,"invulnerable")),flag(J.member(value,"mayfly")),flag(J.member(value,"flying")),walking,flying_speed},
        I.Menu{flag(J.member(value,"opened")),U32.to_nat(revision),None{}}}}

def encode_state(definitions:D.Catalog,value:J.Value,+before:R.Record,result:Result<&2,&1,String,I.State>) -> J.Value:
  match result:
    case Fail{message}: Fixture.error(message)
    case Done{inventory}: encoded(definitions,before,IC.encode(IC.Saved{before,inventory,False{},WG.legacy()}))

def seeded(+definitions:D.Catalog,+value:J.Value,result:Result<&2,&1,String,IC.Saved>) -> J.Value:
  match result:
    case Fail{message}: Fixture.error(message)
    case Done{IC.Saved{record,old,fresh,generation}}: encode_state(definitions,value,record,fixture_state(definitions,value))

def metadata(value:Maybe<&2,Inv.ItemMetadata>) -> J.Value:
  match value:
    case None{}: Fixture.error("metadata refused")
    case Some{Inv.ItemMetadata{key,limit}}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"slot",Fixture.slot(Inv.InvStack{key,limit})}])

def modified_definition(mode:String,number:U32,description:String,limit:U32,set:U32,digest:String,enabled:Bool) -> D.Definition:
  match mode:
    case "disabled": D.Definition{number,"minecraft:suspicious_stew",description,limit,set,digest,False{}}
    case "wrong_digest": D.Definition{number,"minecraft:suspicious_stew",description,limit,set,"0000000000000000000000000000000000000000000000000000000000000000",enabled}
    case "wrong_limit": D.Definition{number,"minecraft:suspicious_stew",description,64,set,digest,enabled}
    case _: D.Definition{number,"minecraft:suspicious_stew",description,limit,set,digest,enabled}

def component_row(definitions:List<&2,D.Definition>,+mode:String) -> List<&2,D.Definition>:
  match definitions:
    case Nil{}: []
    case D.Definition{number,"minecraft:suspicious_stew",description,limit,set,digest,enabled} <> rest:
      modified_definition(mode,number,description,limit,set,digest,enabled) <> component_row(rest,mode)
    case head <> rest: head <> component_row(rest,mode)

def selected_catalog(+catalog:D.Catalog,mode:String) -> D.Catalog:
  match mode:
    case "missing": D.legacy()
    case _: D.Catalog{component_row(D.all(catalog),mode),D.count(catalog)}

def decoded(+catalog:D.Catalog,bytes:List<&2,U32>,seed:Result<&2,&1,String,IC.Saved>) -> J.Value:
  match seed:
    case Fail{message}: Fixture.error(message)
    case Done{IC.Saved{record,inventory,fresh,generation}}: restored(record,IC.decode_with(catalog,1,bytes))

def return_done(value:J.Value) -> Result<&2,&2,String,J.Value>: Done{value}

def run(+catalog:D.Catalog,+value:J.Value,mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "metadata":
      do Result<&2,&2,String,J.Value>:
        +key : Inv.ItemKey <- Fixture.fixture_key(value)
        kind : J.Value <- Fixture.required(J.member(value,"catalog"),"catalog")
        name : String <- Fixture.text_value(kind)
        return metadata(D.metadata(selected_catalog(catalog,name),key))
    case "encode":
      do Result<&2,&2,String,J.Value>:
        kind : J.Value <- Fixture.required(J.member(value,"catalog"),"catalog")
        name : String <- Fixture.text_value(kind)
        +chosen : D.Catalog = selected_catalog(catalog,name)
        return seeded(chosen,value,IC.initial_with(chosen,True{},WG.legacy(),Unit{}))
    case "decode":
      do Result<&2,&2,String,J.Value>:
        kind : J.Value <- Fixture.required(J.member(value,"catalog"),"catalog")
        name : String <- Fixture.text_value(kind)
        bytes : List<&2,U32> <- Fixture.fixture_bytes(value)
        +chosen : D.Catalog = selected_catalog(catalog,name)
        return decoded(chosen,bytes,IC.initial_with(chosen,True{},WG.legacy(),Unit{}))
    case _: Fail{"unknown inventory component fixture"}

def fixture(catalog:D.Catalog,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw : J.Value <- Fixture.required(J.member(value,"mode"),"mode")
    mode : String <- Fixture.text_value(raw)
    run(catalog,value,mode)

def fixtures(+catalog:D.Catalog,values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Fixture.print(fixture(catalog,value))
        fixtures(catalog,rest)

def parsed(catalog:D.Catalog,value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: Fixture.print(Fail{message})
    case Done{J.JArray{values}}: fixtures(catalog,values)
    case _: IO.die(Unit,2,"fixture array required")

def read_done(catalog:D.Catalog,result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(catalog,J.parse_bounded(input,U32.to_nat(8388608),32))

def known(path:String,value:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{catalog}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(catalog,result)

def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> table <> path <> Nil{}:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        known(path,catalog)
    case _: IO.die(Unit,2,"expected item table and fixture file")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
