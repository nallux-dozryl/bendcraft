import Base
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ./crafting_recipe.bend as T
import ../src/crafting_recipe_components.bend as C

type Observed is Data:
  Observed{id:String,output:Inv.Slot}

def slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      T.object([J.JMember{"id",T.text(id)},J.JMember{"count",T.number(count)},J.JMember{"components",T.text(components)}])

def metadata_value(value:Maybe<&2,Inv.ItemMetadata>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{Inv.ItemMetadata{key,limit}}: T.number(limit)

def limit(+catalog:R.Catalog,slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{key,count}: metadata_value(R.output_metadata(catalog,key))

def observed_output(value:Maybe<&2,R.Plan>) -> Inv.Slot:
  match value:
    case None{}: Inv.InvEmpty{}
    case Some{R.Plan{id,output,before,consumption}}: output

def query(+value:J.Value,+catalog:R.Catalog) -> Result<&2,&2,String,Observed>:
  R.Catalog{recipes,tags,items} = catalog
  do Result<&2,&2,String,Observed>:
    +id : String <- D.text_field(value,"id")
    recipe : R.Recipe <- T.lookup(recipes,id)
    raw_grid : J.Value <- D.field(value,"grid")
    input : R.Grid <- T.grid(raw_grid)
    plan : Maybe<&2,R.Plan> <- R.find(R.Catalog{[recipe],tags,items},input)
    return Observed{id,observed_output(plan)}

def queries(values:List<&2,J.Value>,+catalog:R.Catalog) -> Result<&2,&2,String,List<&2,Observed>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,Observed>>:
        head : Observed <- query(value,catalog)
        tail : List<&2,Observed> <- queries(rest,catalog)
        return head <> tail

def profile(defaults:J.Value,+slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{key,count}: metadata_value(C.stew_metadata(defaults,key))

def observation_values(values:List<&2,Observed>,+catalog:R.Catalog,+defaults:J.Value) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Observed{id,+output} <> rest:
      T.object([J.JMember{"id",T.text(id)},J.JMember{"output",slot_value(output)},J.JMember{"limit",limit(catalog,output)},J.JMember{"stew_profile_limit",profile(defaults,output)}]) <> observation_values(rest,catalog,defaults)

def profile_case(+value:J.Value,defaults:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    raw_key : J.Value <- D.field(value,"key")
    slot : Inv.Slot <- T.grid_slot(raw_key)
    return T.object([J.JMember{"id",T.text(id)},J.JMember{"limit",profile(defaults,slot)}])

def profile_cases(values:List<&2,J.Value>,+defaults:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- profile_case(value,defaults)
        tail : List<&2,J.Value> <- profile_cases(rest,defaults)
        return head <> tail

def find_output(values:List<&2,Observed>,+id:String) -> Inv.Slot:
  match values:
    case Nil{}: Inv.InvEmpty{}
    case Observed{name,+output} <> rest: R.choose(Inv.Slot,output,find_output(rest,id),String.eq(name,id))

def same_components(a:Inv.Slot,b:Inv.Slot) -> Bool:
  match a b:
    case Inv.InvEmpty{} Inv.InvEmpty{}: True{}
    case Inv.InvStack{key_a,count_a} Inv.InvStack{key_b,count_b}: Inv.key_equal(key_a,key_b)
    case _ _: False{}

def comparison(+value:J.Value,+outputs:List<&2,Observed>) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +a : String <- D.text_field(value,"a")
    +b : String <- D.text_field(value,"b")
    return T.object([J.JMember{"a",T.text(a)},J.JMember{"b",T.text(b)},J.JMember{"same",J.JBool{same_components(find_output(outputs,a),find_output(outputs,b))}}])

def comparisons(values:List<&2,J.Value>,+outputs:List<&2,Observed>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- comparison(value,outputs)
        tail : List<&2,J.Value> <- comparisons(rest,outputs)
        return head <> tail

def decoded(value:Result<&2,&2,String,R.Recipe>) -> J.Value:
  match value:
    case Fail{message}: T.object([J.JMember{"status",T.text("rejected")},J.JMember{"error",T.text(message)}])
    case Done{R.Unsupported{id,kind}}: T.object([J.JMember{"status",T.text("unsupported")},J.JMember{"kind",T.text(kind)}])
    case Done{recipe}: T.object([J.JMember{"status",T.text("supported")}])

def decode_case(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +id : String <- D.text_field(value,"id")
    source : J.Value <- D.field(value,"source")
    return T.object([J.JMember{"id",T.text(id)},J.JMember{"result",decoded(D.decode(id,source))}])

def decode_cases(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- decode_case(value)
        tail : List<&2,J.Value> <- decode_cases(rest)
        return head <> tail

def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_catalog : J.Value <- D.field(value,"catalog")
    +catalog : R.Catalog <- D.catalog(raw_catalog)
    +defaults : J.Value <- D.field(value,"stew_defaults")
    raw_cases : J.Value <- D.field(value,"cases")
    cases : List<&2,J.Value> <- D.array(raw_cases)
    +outputs : List<&2,Observed> <- queries(cases,catalog)
    raw_pairs : J.Value <- D.field(value,"comparisons")
    pairs : List<&2,J.Value> <- D.array(raw_pairs)
    same : List<&2,J.Value> <- comparisons(pairs,outputs)
    raw_decode : J.Value <- D.field(value,"decoder_cases")
    decoder_cases : List<&2,J.Value> <- D.array(raw_decode)
    decoder : List<&2,J.Value> <- decode_cases(decoder_cases)
    raw_profiles : J.Value <- D.field(value,"profile_cases")
    profiles : List<&2,J.Value> <- D.array(raw_profiles)
    admission : List<&2,J.Value> <- profile_cases(profiles,defaults)
    return T.object([J.JMember{"outputs",J.JArray{observation_values(outputs,catalog,defaults)}},J.JMember{"comparisons",J.JArray{same}},J.JMember{"decoder",J.JArray{decoder}},J.JMember{"profile_cases",J.JArray{admission}}])

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
    case _: IO.die(Unit,2,"expected crafting component fixture path")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
