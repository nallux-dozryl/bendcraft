import Base
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_components.bend as C
import ../src/crafting_recipe_decoder.bend as D
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ./crafting_recipe.bend as T
import ./crafting_recipe_components.bend as CT

def metadata(value:Maybe<&2,Inv.ItemMetadata>) -> List<&2,Inv.ItemMetadata>:
  match value:
    case None{}: []
    case Some{actual}: [actual]

def admitted(defaults:J.Value,slot:Inv.Slot) -> List<&2,Inv.ItemMetadata>:
  match slot:
    case Inv.InvEmpty{}: []
    case Inv.InvStack{key,count}: metadata(C.stew_metadata(defaults,key))

def relimit(values:List<&2,Inv.ItemMetadata>,limit:U32) -> List<&2,Inv.ItemMetadata>:
  match values:
    case Inv.ItemMetadata{key,old} <> rest: [Inv.ItemMetadata{key,limit}]
    case Nil{}: []

def authorities(mode:String,+defaults:J.Value,slot:Inv.Slot,other:Inv.Slot) -> List<&2,Inv.ItemMetadata>:
  match mode:
    case "none": []
    case "other": admitted(defaults,other)
    case "zero": relimit(admitted(defaults,slot),0)
    case "large": relimit(admitted(defaults,slot),100)
    case "validated": admitted(defaults,slot)
    case _: []

def with_count(slot:Inv.Slot,count:U32) -> Inv.Slot:
  match slot:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{key,old}: Inv.InvStack{key,count}

def other_output(value:Maybe<&2,J.Value>,templates:List<&2,CT.Observed>) -> Inv.Slot:
  match value:
    case Some{J.JString{id}}: CT.find_output(templates,id)
    case _: Inv.InvEmpty{}

def query(+value:J.Value,catalog:R.Catalog,+templates:List<&2,CT.Observed>,+defaults:J.Value) -> Result<&2,&2,String,J.Value>:
  R.Catalog{recipes,tags,items} = catalog
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    recipe_id : String <- D.text_field(value,"recipe_id")
    template_id : String <- D.text_field(value,"template_id")
    recipe : R.Recipe <- T.lookup(recipes,recipe_id)
    +slot : Inv.Slot = CT.find_output(templates,template_id)
    mode : String <- D.text_field(value,"metadata")
    count : U32 <- D.number_field(value,"count")
    authority : List<&2,Inv.ItemMetadata> = authorities(mode,defaults,slot,other_output(J.member(value,"other"),templates))
    grid : R.Grid = R.Grid{1,1,[with_count(slot,count)]}
    result : J.Value = T.reported(R.find_with_metadata(R.Catalog{[recipe],tags,items},grid,authority))
    return T.object([J.JMember{"id",T.text(id)},J.JMember{"result",result}])

def queries(values:List<&2,J.Value>,+catalog:R.Catalog,+templates:List<&2,CT.Observed>,+defaults:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- query(value,catalog,templates,defaults)
        tail : List<&2,J.Value> <- queries(rest,catalog,templates,defaults)
        return head <> tail

def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_catalog : J.Value <- D.field(value,"catalog")
    +catalog : R.Catalog <- D.catalog(raw_catalog)
    defaults : J.Value <- D.field(value,"stew_defaults")
    raw_templates : J.Value <- D.field(value,"templates")
    template_cases : List<&2,J.Value> <- D.array(raw_templates)
    templates : List<&2,CT.Observed> <- CT.queries(template_cases,catalog)
    raw_queries : J.Value <- D.field(value,"queries")
    query_values : List<&2,J.Value> <- D.array(raw_queries)
    results : List<&2,J.Value> <- queries(query_values,catalog,templates,defaults)
    return J.JArray{results}

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: T.respond(execute(value))

def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,U32.to_nat(8388608),64))

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected crafting component-input fixture path")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
