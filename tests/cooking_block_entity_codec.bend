import Base
import ../src/json.bend as J
import ../src/nbt.bend as N
import ../src/inventory.bend as I
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/cooking_recipe.bend as K
import ../src/furnace_authority.bend as FA
import ../src/campfire_authority.bend as CA
import ../src/campfire_authority_items.bend as CI
import ../src/cooking_block_entity_codec.bend as B
import ../src/cooking_block_entity_codec_items.bend as Items
import ../src/cooking_block_entity_codec_nbt.bend as Bits
import ../src/u32_decimal.bend as Decimal

def num(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def txt(value:String) -> J.Value: J.JString{value}
def obj(values:List<&2,J.Member>) -> J.Value: J.JObject{values}
def nums(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: num(head) <> nums(rest)
def raw_bytes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        byte : U32 <- D.number(head)
        tail : List<&2,U32> <- raw_bytes(rest)
        return byte <> tail
def slot(value:I.Slot) -> J.Value:
  match value:
    case I.InvEmpty{}: J.JNull{}
    case I.InvStack{I.ItemKey{id,components},count}: obj([J.JMember{"id",txt(id)},J.JMember{"components",txt(components)},J.JMember{"count",num(count)}])
def slots(values:List<&2,I.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: slot(head) <> slots(rest)
def used(values:List<&2,FA.Use>) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case FA.Use{id,count} <> rest: J.JMember{id,num(count)} <> used(rest)
def furnace(value:FA.Persisted) -> J.Value:
  FA.Persisted{items,s,c,r,t,speed,table} = value
  obj([J.JMember{"slots",J.JArray{slots(B.slot_list(items))}},J.JMember{"cookingTimer",num(s)},J.JMember{"cookingTotalTime",num(c)},J.JMember{"litTimeRemaining",num(r)},J.JMember{"litTotalTime",num(t)},J.JMember{"speed_bits",num(F32.bits(speed))},J.JMember{"uses",obj(used(table))}])
def campfire(value:CA.Record) -> J.Value:
  CA.Record{+cells} = value
  obj([J.JMember{"slots",J.JArray{slots(B.input_slots(B.cell_inputs(cells)))}},J.JMember{"progress",J.JArray{nums(B.cell_progress(cells))}},J.JMember{"total",J.JArray{nums(B.cell_total(cells))}}])
def details(value:B.Details) -> J.Value:
  B.Details{name,extras,inputs,admission,discarded} = value
  obj([J.JMember{"extras",num(U32.from_nat(List.length(&2,N.Member,extras)))},J.JMember{"discarded",num(discarded)}])
def status(-A:Data,value:Result<&2,&2,String,A>) -> J.Value:
  match value:
    case Fail{message}: txt("refused")
    case Done{actual}: txt("accepted")
def baseline_frame() -> FA.Frame: FA.Frame{K.Smelting{},31,41,51,61,2.0,Some{"probe:previous"},[FA.Use{"probe:previous",7}]}
def furnace_sentinel(state:FA.State) -> FA.State:
  FA.State{I.Inventory{cells,length},frame} = state
  FA.State{I.Inventory{Array.set(I.Slot,cells,3,I.InvStack{I.ItemKey{"minecraft:stone",""},5}),length},frame}
def baseline_furnace() -> FA.State:
  furnace_sentinel(FA.install(FA.Snapshot{baseline_frame(),K.FurnaceSlots{I.InvStack{I.ItemKey{"minecraft:dirt",""},2},I.InvEmpty{},I.InvEmpty{}}}))
def prior() -> CA.Record:
  CA.Record{CA.Four{CA.Cell{CI.Input{I.InvStack{I.ItemKey{"minecraft:dirt",""},1},J.JObject{[]}},11,101},CA.Cell{CI.plain(),22,202},CA.Cell{CI.plain(),33,303},CA.Cell{CI.plain(),44,404}}}
def campfire_prior(record:CA.Record) -> CA.State:
  CA.Record{cells} = record
  CA.State{CA.Soul{},True{},cells,Some{"probe:previous"}}
def baseline_campfire() -> CA.State: campfire_prior(prior())
def cache(value:Maybe<&2,String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{id}: txt(id)
def furnace_owner_saved(hidden:I.Slot,frame:FA.Frame,result:FA.State & Result<&2,&2,String,FA.Persisted>) -> J.Value:
  FA.Frame{kind,r,t,s,c,speed,recipe,uses} = frame
  match result:
    case (state,Fail{message}): obj([J.JMember{"error",txt(message)}])
    case (state,Done{record}): obj([J.JMember{"state",furnace(record)},J.JMember{"hidden",slot(hidden)},J.JMember{"cache",cache(recipe)}])
def furnace_owner_hidden(+frame:FA.Frame,+length:U32,result:Array<I.Slot> & I.Slot) -> J.Value:
  (cells,+hidden) = result
  furnace_owner_saved(hidden,frame,FA.save(FA.State{I.Inventory{cells,length},frame}))
def furnace_owner(state:FA.State) -> J.Value:
  FA.State{I.Inventory{cells,length},+frame} = state
  furnace_owner_hidden(frame,length,Array.get(I.Slot,cells,3))
def furnace_load_observed(result:FA.State & Result<&2,&2,String,B.Details>) -> J.Value:
  (state,result) = result
  obj([J.JMember{"status",status(B.Details,result)},J.JMember{"owner",furnace_owner(state)}])
def soul(kind:CA.CampfireKind) -> Bool:
  match kind:
    case CA.Soul{}: True{}
    case CA.Ordinary{}: False{}
def campfire_load_observed(result:CA.State & Result<&2,&2,String,B.Details>) -> J.Value:
  (CA.State{kind,lit,+cells,recipe},result) = result
  obj([J.JMember{"status",status(B.Details,result)},J.JMember{"owner",campfire(CA.Record{cells})},J.JMember{"kind",txt(R.choose(String,"soul","ordinary",soul(kind)))},J.JMember{"lit",J.JBool{lit}},J.JMember{"cache",cache(recipe)}])
def furnace_roundtrip(value:Result<&2,&2,String,B.FurnaceDocument>) -> J.Value:
  match value:
    case Fail{message}: obj([J.JMember{"error",txt(message)}])
    case Done{B.FurnaceDocument{record,details}}: furnace(record)
def campfire_roundtrip(value:Result<&2,&2,String,B.CampfireDocument>) -> J.Value:
  match value:
    case Fail{message}: obj([J.JMember{"error",txt(message)}])
    case Done{B.CampfireDocument{record,details}}: campfire(record)
def furnace_case(+context:Items.Context,id:String,+bytes:List<&2,U32>,value:Result<&2,&2,String,B.FurnaceDocument>) -> Result<&2,&2,String,J.Value>:
  match value:
    case Fail{message}: Done{obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("refused")},J.JMember{"message",txt(message)},J.JMember{"load",furnace_load_observed(B.load_furnace(baseline_furnace(),context,N.default_limits(),bytes))}])}
    case Done{B.FurnaceDocument{+record,extra}}:
      do Result<&2,&2,String,J.Value>:
        +encoded : List<&2,U32> <- B.encode_furnace(context,N.default_limits(),record)
        return obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("accepted")},J.JMember{"state",furnace(record)},J.JMember{"details",details(extra)},J.JMember{"bytes",J.JArray{nums(encoded)}},J.JMember{"roundtrip",furnace_roundtrip(B.decode_furnace(context,N.default_limits(),encoded))},J.JMember{"load",furnace_load_observed(B.load_furnace(baseline_furnace(),context,N.default_limits(),bytes))}])
def campfire_case_with(+live:CI.Context,+context:Items.Context,id:String,+bytes:List<&2,U32>,value:Result<&2,&2,String,B.CampfireDocument>) -> Result<&2,&2,String,J.Value>:
  match value:
    case Fail{message}: Done{obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("refused")},J.JMember{"message",txt(message)},J.JMember{"load",campfire_load_observed(B.load_campfire(baseline_campfire(),live,N.default_limits(),bytes))}])}
    case Done{B.CampfireDocument{+record,extra}}:
      do Result<&2,&2,String,J.Value>:
        +encoded : List<&2,U32> <- B.encode_campfire(context,N.default_limits(),record)
        return obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("accepted")},J.JMember{"state",campfire(record)},J.JMember{"details",details(extra)},J.JMember{"bytes",J.JArray{nums(encoded)}},J.JMember{"roundtrip",campfire_roundtrip(B.decode_campfire(context,prior(),N.default_limits(),encoded))},J.JMember{"load",campfire_load_observed(B.load_campfire(baseline_campfire(),live,N.default_limits(),bytes))}])
def campfire_case(+context:Items.Context,id:String,bytes:List<&2,U32>,value:Result<&2,&2,String,B.CampfireDocument>) -> Result<&2,&2,String,J.Value>:
  Items.Context{recipes,defaults} = context
  campfire_case_with(CI.Context{recipes,defaults,MTip{}},context,id,bytes,value)
def case_kind(+context:Items.Context,id:String,+bytes:List<&2,U32>,is_campfire:Bool) -> Result<&2,&2,String,J.Value>:
  match is_campfire:
    case False{}: furnace_case(context,id,bytes,B.decode_furnace(context,N.default_limits(),bytes))
    case True{}: campfire_case(context,id,bytes,B.decode_campfire(context,prior(),N.default_limits(),bytes))
def fixture(+context:Items.Context,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    +kind : String <- D.text_field(value,"kind")
    raw : J.Value <- D.field(value,"bytes")
    values : List<&2,J.Value> <- D.array(raw)
    bytes : List<&2,U32> <- raw_bytes(values)
    case_kind(context,id,bytes,String.eq(kind,"campfire") || String.eq(kind,"soul_campfire"))
def fixtures(values:List<&2,J.Value>,+context:Items.Context) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        value : J.Value <- fixture(context,head)
        tail : List<&2,J.Value> <- fixtures(rest,context)
        return value <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_items : J.Value <- D.field(value,"items")
    +rows : List<&2,J.Value> <- D.array(raw_items)
    items : List<&2,R.ItemDefinition> <- D.item_rows(rows,[])
    defaults : List<&2,C.Default> <- D.defaults_rows(rows,[])
    raw_cases : J.Value <- D.field(value,"cases")
    cases : List<&2,J.Value> <- D.array(raw_cases)
    results : List<&2,J.Value> <- fixtures(cases,Items.Context{K.Catalog{[],[],items},defaults})
    return J.JArray{results}
def respond(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{actual}: IO.print(J.encode(actual))
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{actual}: respond(execute(actual))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,U32.to_nat(16777216),64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected physical cooking fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
