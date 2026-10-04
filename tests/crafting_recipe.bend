import Base
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/inventory.bend as Inv
import ../src/json.bend as J

def text(value:String) -> J.Value: J.JString{value}
def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}
def object(members:List<&2,J.Member>) -> J.Value: J.JObject{members}

def slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: object([J.JMember{"id",text(id)},J.JMember{"count",number(count)}])

def steps(values:List<&2,R.Consumption>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Consumption{index,count,remainder} <> rest:
      object([J.JMember{"slot",number(index)},J.JMember{"count",number(count)},J.JMember{"remainder",slot_value(remainder)}]) <> steps(rest)

def selected(value:Maybe<&2,R.Plan>) -> J.Value:
  match value:
    case None{}: object([J.JMember{"recipe",J.JNull{}},J.JMember{"output",J.JNull{}},J.JMember{"consumption",J.JArray{[]}}])
    case Some{R.Plan{id,output,before,consumption}}:
      object([J.JMember{"recipe",text(id)},J.JMember{"output",slot_value(output)},J.JMember{"consumption",J.JArray{steps(consumption)}}])

def reported(value:Result<&2,&2,String,Maybe<&2,R.Plan>>) -> J.Value:
  match value:
    case Fail{message}: object([J.JMember{"error",text(message)}])
    case Done{result}: selected(result)

def current_result(result:Result<&2,&2,String,Maybe<&2,R.Plan>>,after:R.Grid) -> J.Value:
  match result:
    case Done{Some{plan}}: object([J.JMember{"current",J.JBool{R.current(plan,after)}}])
    case _: object([J.JMember{"current",J.JBool{False{}}}])

def recipe_value(recipe:R.Recipe) -> J.Value:
  match recipe:
    case R.Shaped{id,width,height,cells,output}:
      object([J.JMember{"id",text(id)},J.JMember{"status",text("shaped")},J.JMember{"width",number(width)},J.JMember{"height",number(height)},J.JMember{"output",slot_value(output)}])
    case R.Shapeless{id,ingredients,output}:
      object([J.JMember{"id",text(id)},J.JMember{"status",text("shapeless")},J.JMember{"output",slot_value(output)}])
    case R.Unsupported{id,kind}:
      object([J.JMember{"id",text(id)},J.JMember{"status",text("unsupported")},J.JMember{"kind",text(kind)}])

def recipe_values(recipes:List<&2,R.Recipe>) -> List<&2,J.Value>:
  match recipes:
    case Nil{}: []
    case recipe <> rest: recipe_value(recipe) <> recipe_values(rest)

def lookup(recipes:List<&2,R.Recipe>,+id:String) -> Result<&2,&2,String,R.Recipe>:
  match recipes:
    case Nil{}: Fail{"test recipe not found"}
    case +recipe <> rest: R.choose(Result<&2,&2,String,R.Recipe>,Done{recipe},lookup(rest,id),String.eq(D.recipe_id(recipe),id))

def chosen(names:List<&2,J.Value>,+recipes:List<&2,R.Recipe>) -> Result<&2,&2,String,List<&2,R.Recipe>>:
  match names:
    case Nil{}: Done{[]}
    case name <> rest:
      do Result<&2,&2,String,List<&2,R.Recipe>>:
        id : String <- D.text(name)
        recipe : R.Recipe <- lookup(recipes,id)
        tail : List<&2,R.Recipe> <- chosen(rest,recipes)
        return recipe <> tail

def component_text(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,String>:
  match value:
    case None{}: Done{""}
    case Some{actual}: D.text(actual)

def grid_slot(+value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case _:
      do Result<&2,&2,String,Inv.Slot>:
        id : String <- D.text_field(value,"id")
        count : U32 <- D.number_field(value,"count")
        components : String <- component_text(J.member(value,"components"))
        return Inv.InvStack{Inv.ItemKey{id,components},count}

def grid_slots(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        head : Inv.Slot <- grid_slot(value)
        tail : List<&2,Inv.Slot> <- grid_slots(rest)
        return head <> tail

def grid(+value:J.Value) -> Result<&2,&2,String,R.Grid>:
  do Result<&2,&2,String,R.Grid>:
    width : U32 <- D.number_field(value,"width")
    height : U32 <- D.number_field(value,"height")
    raw_slots : J.Value <- D.field(value,"slots")
    values : List<&2,J.Value> <- D.array(raw_slots)
    slots : List<&2,Inv.Slot> <- grid_slots(values)
    return R.Grid{width,height,slots}

def query_result(after:Maybe<&2,J.Value>,catalog:R.Catalog,input:R.Grid) -> Result<&2,&2,String,J.Value>:
  match after:
    case None{}: Done{reported(R.find(catalog,input))}
    case Some{value}:
      do Result<&2,&2,String,J.Value>:
        later : R.Grid <- grid(value)
        return current_result(R.find(catalog,input),later)

def query(+value:J.Value,catalog:R.Catalog) -> Result<&2,&2,String,J.Value>:
  R.Catalog{recipes,tags,items} = catalog
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    raw_names : J.Value <- D.field(value,"recipes")
    names : List<&2,J.Value> <- D.array(raw_names)
    selected : List<&2,R.Recipe> <- chosen(names,recipes)
    raw_grid : J.Value <- D.field(value,"grid")
    input : R.Grid <- grid(raw_grid)
    result : J.Value <- query_result(J.member(value,"after"),R.Catalog{selected,tags,items},input)
    return object([J.JMember{"id",text(id)},J.JMember{"result",result}])

def queries(values:List<&2,J.Value>,+catalog:R.Catalog) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- query(value,catalog)
        tail : List<&2,J.Value> <- queries(rest,catalog)
        return head <> tail

def decode_accepted(value:Result<&2,&2,String,R.Recipe>) -> Bool:
  match value:
    case Fail{message}: False{}
    case Done{recipe}: True{}

def decoder_query(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +id : String <- D.text_field(value,"id")
    source : J.Value <- D.field(value,"source")
    return object([J.JMember{"id",text(id)},J.JMember{"accepted",J.JBool{decode_accepted(D.decode(id,source))}}])

def decoder_queries(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- decoder_query(value)
        tail : List<&2,J.Value> <- decoder_queries(rest)
        return head <> tail

def execution_result(catalog:R.Catalog,results:List<&2,J.Value>,decoder:List<&2,J.Value>) -> J.Value:
  R.Catalog{recipes,tags,items} = catalog
  object([J.JMember{"decoded",J.JArray{recipe_values(recipes)}},J.JMember{"queries",J.JArray{results}},J.JMember{"decoder_queries",J.JArray{decoder}}])

def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_catalog : J.Value <- D.field(value,"catalog")
    +catalog : R.Catalog <- D.catalog(raw_catalog)
    raw_queries : J.Value <- D.field(value,"queries")
    query_values : List<&2,J.Value> <- D.array(raw_queries)
    results : List<&2,J.Value> <- queries(query_values,catalog)
    raw_decoder : J.Value <- D.field(value,"decoder_queries")
    decoder_values : List<&2,J.Value> <- D.array(raw_decoder)
    decoder : List<&2,J.Value> <- decoder_queries(decoder_values)
    return execution_result(catalog,results,decoder)

def respond(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: respond(execute(value))

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
    case _: IO.die(Unit,2,"expected crafting recipe JSON fixture path")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
