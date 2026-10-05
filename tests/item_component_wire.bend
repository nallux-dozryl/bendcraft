import Base
import ./item_component.bend as Fixture
import ./resource_client_interaction_wire.bend as Legacy
import ./resource_client_framing.bend as Framing
import ../src/item_component.bend as C
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/player_inventory.bend as I
import ../src/resource_client_wire.bend as Wire
import ../src/json.bend as J

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

def optional_result_ready(value:Result<&2,&2,String,Inv.Slot>) -> Result<&2,&1,String,Maybe<&2,Inv.Slot>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{slot}: Done{Some{slot}}

def optional_result(value:J.Value) -> Result<&2,&1,String,Maybe<&2,Inv.Slot>>:
  match value:
    case J.JNull{}: Done{None{}}
    case other: optional_result_ready(raw_slot(other))

def fixture_state(+definitions:D.Catalog,+value:J.Value) -> Result<&2,&1,String,I.State>:
  do Result<&2,&1,String,I.State>:
    array : Array<Inv.Slot> <- fixture_array(value)
    length : U32 <- affine_number(Fixture.fixture_number(value,"length"))
    selected : U32 <- affine_number(Fixture.fixture_number(value,"selected"))
    walking : U32 <- affine_number(Fixture.fixture_number(value,"walking"))
    flying_speed : U32 <- affine_number(Fixture.fixture_number(value,"flying_speed"))
    revision : U32 <- affine_number(Fixture.fixture_number(value,"revision"))
    derived : J.Value <- affine_json(Fixture.required(J.member(value,"result"),"result"))
    result : Maybe<&2,Inv.Slot> <- optional_result(derived)
    return I.State{Inv.Inventory{array,length},selected,I.Abilities{flag(J.member(value,"instabuild")),flag(J.member(value,"maybuild"))},
      I.Profile{definitions,I.Status{flag(J.member(value,"invulnerable")),flag(J.member(value,"mayfly")),flag(J.member(value,"flying")),walking,flying_speed},
        I.Menu{flag(J.member(value,"opened")),U32.to_nat(revision),result}}}

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

def result_slot(value:Maybe<&2,Inv.Slot>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{slot}: Fixture.slot(slot)

def state_value(length:U32,selected:U32,abilities:I.Abilities,profile:I.Profile,slots:List<&2,Inv.Slot>) -> J.Value:
  I.Abilities{instabuild,maybuild} = abilities
  I.Profile{definitions,I.Status{invulnerable,mayfly,flying,walk,fly},I.Menu{opened,revision,result}} = profile
  Fixture.object([J.JMember{"backing",J.JArray{Fixture.slots(slots)}},J.JMember{"length",Fixture.number(length)},
    J.JMember{"selected",Fixture.number(selected)},J.JMember{"instabuild",Fixture.boolean(instabuild)},J.JMember{"maybuild",Fixture.boolean(maybuild)},
    J.JMember{"status",J.JArray{[Fixture.boolean(invulnerable),Fixture.boolean(mayfly),Fixture.boolean(flying),Fixture.number(walk),Fixture.number(fly)]}},
    J.JMember{"opened",Fixture.boolean(opened)},J.JMember{"revision",Wire.n(revision)},
    J.JMember{"result",result_slot(result)},J.JMember{"catalog_count",Fixture.number(D.count(definitions))}])

def observed(+selected:U32,+abilities:I.Abilities,+profile:I.Profile,result:Inv.Inventory & List<&2,Inv.Slot>) -> I.State & J.Value:
  (Inv.Inventory{array,+length},slots) = result
  (I.State{Inv.Inventory{array,length},selected,abilities,profile},state_value(length,selected,abilities,profile,slots))

def observe(value:I.State) -> I.State & J.Value:
  I.State{inventory,selected,abilities,profile} = value
  observed(selected,abilities,profile,Fixture.owner_snapshot(inventory))

def action_report(before:J.Value,status:Result<&2,&2,String,Unit>,result:I.State & J.Value) -> J.Value:
  (owner,after) = result
  Fixture.object([J.JMember{"before",before},J.JMember{"after",after},J.JMember{"status",Fixture.status(status)}])

def action_after(before:J.Value,result:I.State & Result<&2,&2,String,Unit>) -> J.Value:
  (owner,status) = result
  action_report(before,status,observe(owner))

def action_ready(+value:J.Value,mode:String,result:I.State & J.Value) -> Result<&2,&2,String,J.Value>:
  match mode result:
    case "acquire" Tuple{owner,before}:
      do Result<&2,&2,String,J.Value>:
        key : Inv.ItemKey <- Fixture.fixture_key(value)
        count : U32 <- Fixture.fixture_number(value,"count")
        index : U32 <- Fixture.fixture_number(value,"index")
        return action_after(before,I.acquire(owner,index,key,count))
    case "pickup" Tuple{owner,before}:
      do Result<&2,&2,String,J.Value>:
        index : U32 <- Fixture.fixture_number(value,"index")
        button : U32 <- Fixture.fixture_number(value,"button")
        return action_after(before,I.menu_click(owner,index,I.Pickup{button}))
    case _ _: Fail{"unknown owner action"}

def action_state(value:J.Value,mode:String,result:Result<&2,&1,String,I.State>) -> Result<&2,&2,String,J.Value>:
  match result:
    case Fail{message}: Fail{message}
    case Done{owner}: action_ready(value,mode,observe(owner))

def encoded_string(value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{text}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"text",Fixture.text(text)}])

def json_result(value:Result<&2,&2,String,J.Value>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{json}: json

def decoded_reply(value:Result<&2,&2,String,Wire.Reply>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+reply}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"value",json_result(Wire.reply_json(reply))},
      J.JMember{"encoded",encoded_string(Wire.encode_reply(reply))}])

def decoded_request(value:Result<&2,&2,String,Wire.Request>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+request}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"value",Wire.request_json(request)},
      J.JMember{"encoded",encoded_string(Wire.encode_request(request))}])

def encoded_reply(+value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.object([J.JMember{"encoded",encoded_string(value)}])
    case Done{text}: Fixture.object([J.JMember{"encoded",encoded_string(value)},J.JMember{"decoded",decoded_reply(Wire.decode_reply(text))}])

def fixed_header(maximum:Bool,snapshot:I.MenuSnapshot) -> I.MenuSnapshot:
  match maximum snapshot:
    case False{} own: own
    case True{} I.MenuSnapshot{saved,craft,carried,result,opened,revision}: I.MenuSnapshot{saved,craft,carried,result,opened,Wire.nat_max()}

def snapshot_wire(mode:String,epoch:String,diagnostic:String,body:I.MenuSnapshot) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "wire_menu": Done{encoded_reply(Wire.encode_reply(Wire.MenuReply{epoch,Wire.nat_max(),False{},diagnostic,body}))}
    case "wire_main": Done{encoded_reply(Wire.encode_reply(Wire.InventoryReply{epoch,Wire.nat_max(),I.main_projection(body)}))}
    case _: Fail{"unknown snapshot wire mode"}

def snapshot_encoded(+value:J.Value,mode:String,result:I.State & I.MenuSnapshot) -> Result<&2,&2,String,J.Value>:
  (owner,+snapshot) = result
  do Result<&2,&2,String,J.Value>:
    epoch_json : J.Value <- Fixture.required(J.member(value,"epoch"),"epoch")
    epoch : String <- Fixture.text_value(epoch_json)
    diagnostic_json : J.Value <- Fixture.required(J.member(value,"diagnostic"),"diagnostic")
    diagnostic : String <- Fixture.text_value(diagnostic_json)
    body : I.MenuSnapshot = fixed_header(flag(J.member(value,"maximum_header")),snapshot)
    snapshot_wire(mode,epoch,diagnostic,body)

def snapshot_state(value:J.Value,mode:String,result:Result<&2,&1,String,I.State>) -> Result<&2,&2,String,J.Value>:
  match result:
    case Fail{message}: Fail{message}
    case Done{owner}: snapshot_encoded(value,mode,I.menu_inspect(owner))

def owner_kind(+value:J.Value,mode:String,chosen:D.Catalog) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "acquire": action_state(value,mode,fixture_state(chosen,value))
    case "pickup": action_state(value,mode,fixture_state(chosen,value))
    case _: snapshot_state(value,mode,fixture_state(chosen,value))

def fixture_with(+catalog:D.Catalog,+value:J.Value,mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "structural":
      do Result<&2,&2,String,J.Value>:
        key : Inv.ItemKey <- Fixture.fixture_key(value)
        count : U32 <- Fixture.fixture_number(value,"count")
        return Fixture.object([J.JMember{"accepted",Fixture.boolean(I.structural_slot(Inv.InvStack{key,count}))}])
    case "request":
      do Result<&2,&2,String,J.Value>:
        raw : J.Value <- Fixture.required(J.member(value,"wire"),"wire")
        text : String <- Fixture.text_value(raw)
        return decoded_request(Wire.decode_request(text))
    case "reply":
      do Result<&2,&2,String,J.Value>:
        raw : J.Value <- Fixture.required(J.member(value,"wire"),"wire")
        text : String <- Fixture.text_value(raw)
        return decoded_reply(Wire.decode_reply(text))
    case _:
      do Result<&2,&2,String,J.Value>:
        raw : J.Value <- Fixture.required(J.member(value,"catalog"),"catalog")
        name : String <- Fixture.text_value(raw)
        chosen : D.Catalog = selected_catalog(catalog,name)
        owner_kind(value,mode,chosen)

def fixture(catalog:D.Catalog,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw : J.Value <- Fixture.required(J.member(value,"mode"),"mode")
    mode : String <- Fixture.text_value(raw)
    fixture_with(catalog,value,mode)

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
    case program <> "legacy" <> Nil{}: Legacy.main()
    case program <> "framing" <> Nil{}: Framing.main()
    case program <> table <> path <> Nil{}:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        known(path,catalog)
    case _: IO.die(Unit,2,"expected item table and fixture file")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
