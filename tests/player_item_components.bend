import Base
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/player_item_table.bend as Table
import ../src/unicode.bend as Unicode
import ../src/player_item_components.bend as Components
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/item_component_inventory_codec.bend as Codec
import ../src/crafting_recipe_components.bend as C
import ../src/crafting_recipe_decoder.bend as Read
import ../src/json.bend as J
import ../src/nbt.bend as N
import ../src/u32_decimal.bend as Decimal

def boolean(value:Bool) -> J.Value: J.JBool{value}
def number(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def slot(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"components",J.JString{components}},J.JMember{"count",number(count)}]}
def optional_slot(value:Maybe<&2,Inv.Slot>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{value}: slot(value)
def slots(values:List<&1,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: slot(head) <> slots(rest)
def accepted(result:Result<&2,&2,String,Unit>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{unit}: True{}
def metadata(value:Maybe<&2,Inv.ItemMetadata>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{Inv.ItemMetadata{key,maximum}}: number(maximum)
def bytes(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: number(head) <> bytes(rest)
def decoded(value:Result<&2,&2,String,Inv.Slot>) -> J.Value:
  match value:
    case Fail{message}: J.JObject{[J.JMember{"error",J.JString{message}}]}
    case Done{value}: slot(value)
def physical_encoded(restored:Result<&2,&2,String,Inv.Slot>,value:Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  match value:
    case Fail{message}: J.JObject{[J.JMember{"error",J.JString{message}}]}
    case Done{data}: J.JObject{[J.JMember{"bytes",J.JArray{bytes(data)}},J.JMember{"decoded",decoded(restored)}]}
def physical(catalog:D.Catalog,value:Result<&2,&2,String,N.Value>) -> J.Value:
  match value:
    case Fail{message}: J.JObject{[J.JMember{"error",J.JString{message}}]}
    case Done{+value}: physical_encoded(Codec.slot_value(catalog,value),N.encode_with(N.Limits{65536,32,16384},N.Root{N.Text{[]},value}))
def observed(value:I.State & Result<&2,&2,String,Unit>) -> J.Value:
  match value:
    case (I.State{Inv.Inventory{array,length},selected,I.Abilities{creative,maybuild},I.Profile{catalog,I.Status{invulnerable,mayfly,flying,walking,speed},I.Menu{opened,revision,output}}},status):
      J.JObject{[J.JMember{"accepted",boolean(accepted(status))},J.JMember{"backing",J.JArray{slots(Array.to_list(~Inv.Slot,array))}},J.JMember{"length",number(length)},J.JMember{"selected",number(selected)},J.JMember{"abilities",J.JArray{[boolean(creative),boolean(maybuild)]}},J.JMember{"status",J.JArray{[boolean(invulnerable),boolean(mayfly),boolean(flying),number(walking),number(speed)]}},J.JMember{"opened",boolean(opened)},J.JMember{"revision",J.JString{Nat.show(revision)}},J.JMember{"result",optional_slot(output)},J.JMember{"catalog_count",number(D.count(catalog))}]}
def owner(catalog:D.Catalog) -> I.State:
  I.State{Inv.Inventory{Array.set(Inv.Slot,Array.set(Inv.Slot,Array.new(Inv.Slot,6n,Inv.InvEmpty{}),0,Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},7}),63,Inv.InvStack{Inv.ItemKey{"hidden:sentinel","opaque\tretained"},4294967295}),48},7,I.Abilities{True{},False{}},I.Profile{catalog,I.Status{True{},True{},True{},2143294004,2147483648},I.Menu{True{},23n,Some{Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},4}}}}}
def disabled(values:List<&2,D.Definition>) -> List<&2,D.Definition>:
  match values:
    case Nil{}: []
    case D.Definition{number,"minecraft:stone",description,limit,set,digest,enabled} <> rest:
      D.Definition{number,"minecraft:stone",description,limit,set,digest,False{}} <> disabled(rest)
    case head <> rest: head <> disabled(rest)
def selected(+catalog:D.Catalog,defaults:List<&2,C.Default>,mode:String) -> D.Catalog:
  match mode:
    case "uninitialized": catalog
    case "missing_defaults": D.with_initialized_defaults(catalog,[])
    case "disabled": D.with_initialized_defaults(D.Catalog{disabled(D.all(catalog)),D.count(catalog)},defaults)
    case _: D.with_initialized_defaults(catalog,defaults)
def row(+catalog:D.Catalog,+defaults:List<&2,C.Default>,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    label : String <- Read.text_field(value,"label")
    id : String <- Read.text_field(value,"id")
    identity : String <- Read.text_field(value,"components")
    +count : U32 <- Read.number_field(value,"count")
    mode : String <- Read.text_field(value,"mode")
    +current : D.Catalog = selected(catalog,defaults,mode)
    +key : Inv.ItemKey = Inv.ItemKey{id,identity}
    +value : Inv.Slot = Inv.InvStack{key,count}
    return J.JObject{[J.JMember{"label",J.JString{label}},J.JMember{"metadata",metadata(D.metadata(current,key))},J.JMember{"structural",boolean(I.structural_slot(value))},J.JMember{"valid",boolean(accepted(D.admitted_slot(current,value)))},J.JMember{"physical",physical(current,Codec.slot_tag(current,value))},J.JMember{"owner",observed(I.acquire(owner(current),2,key,count))}]}
def rows(values:List<&2,J.Value>,+catalog:D.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        actual : J.Value <- row(catalog,defaults,head)
        tail : List<&2,J.Value> <- rows(rest,catalog,defaults)
        return actual <> tail
def raw_bytes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        byte : U32 <- Read.number(head)
        tail : List<&2,U32> <- raw_bytes(rest)
        return byte <> tail
def raw_slot(catalog:D.Catalog,value:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case Fail{message}: Fail{message}
    case Done{N.Root{name,body}}: Codec.slot_value(catalog,body)
def raw_owner(catalog:D.Catalog,value:Result<&2,&2,String,Inv.Slot>) -> J.Value:
  match value:
    case Fail{message}: observed((owner(catalog),Fail{message}))
    case Done{Inv.InvEmpty{}}: observed((owner(catalog),Done{Unit{}}))
    case Done{Inv.InvStack{key,count}}: observed(I.acquire(owner(catalog),2,key,count))
def raw_row(+catalog:D.Catalog,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    label : String <- Read.text_field(value,"label")
    array : J.Value <- Read.field(value,"bytes")
    entries : List<&2,J.Value> <- Read.array(array)
    data : List<&2,U32> <- raw_bytes(entries)
    +result : Result<&2,&2,String,Inv.Slot> = raw_slot(catalog,N.decode_with(N.Limits{65536,32,16384},data))
    return J.JObject{[J.JMember{"label",J.JString{label}},J.JMember{"decoded",decoded(result)},J.JMember{"owner",raw_owner(catalog,result)}]}
def raw_rows(values:List<&2,J.Value>,+catalog:D.Catalog) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        actual : J.Value <- raw_row(catalog,head)
        tail : List<&2,J.Value> <- raw_rows(rest,catalog)
        return actual <> tail
def fixture(+catalog:D.Catalog,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw : J.Value <- Read.field(value,"defaults")
    entries : List<&2,J.Value> <- Read.array(raw)
    +defaults : List<&2,C.Default> <- Read.defaults_rows(entries,[])
    cases : J.Value <- Read.field(value,"cases")
    values : List<&2,J.Value> <- Read.array(cases)
    results : List<&2,J.Value> <- rows(values,catalog,defaults)
    raw : J.Value <- Read.field(value,"physical_cases")
    entries : List<&2,J.Value> <- Read.array(raw)
    decoded : List<&2,J.Value> <- raw_rows(entries,D.with_initialized_defaults(catalog,defaults))
    return J.JObject{[J.JMember{"admission",J.JArray{results}},J.JMember{"physical",J.JArray{decoded}}]}
def finished(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))
def parsed_json(catalog:D.Catalog,value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: finished(fixture(catalog,value))
def parsed_file(+catalog:D.Catalog,text:Result<&2,&2,String,String>) -> IO(Unit):
  match text:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: parsed_json(catalog,J.parse_bounded(value,65536n,32))
def decoded_file(catalog:D.Catalog,result:Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{bytes}: parsed_file(catalog,Unicode.decode(65536n,bytes))
def closed_file(catalog:D.Catalog,result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case (file,bytes):
      do IO<Unit>:
        File.close(file)
        decoded_file(catalog,bytes)
def opened_file(catalog:D.Catalog,result:Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match result:
    case Fail{Tuple{code,message}}: IO.die(Unit,2,message)
    case Done{file}:
      do IO<Unit>:
        read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,65537)
        closed_file(catalog,read)
def loaded_catalog(path:String,result:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{catalog}:
      do IO<Unit>:
        file : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        opened_file(catalog,file)
def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case exe <> table <> path <> Nil{}:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        loaded_catalog(path,catalog)
    case _: IO.die(Unit,2,"expected item table and fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1,String> <- IO.args()
    arguments(args)
