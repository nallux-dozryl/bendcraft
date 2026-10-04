import Base
import ../src/json.bend as J
import ../src/inventory.bend as Inv
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/cooking_recipe.bend as K
import ../src/cooking_recipe_decoder.bend as KD
import ../src/cooking_recipe_number.bend as N
import ../src/u32_decimal.bend as Decimal

type Observed is Data:
  Observed{id:String,decoded:Result<&2,&2,String,K.Recipe>}

def num(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def txt(value:String) -> J.Value: J.JString{value}
def obj(values:List<&2,J.Member>) -> J.Value: J.JObject{values}

def slot_value(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: obj([J.JMember{"id",txt(id)},J.JMember{"count",num(count)},J.JMember{"components",txt(components)}])

def raw_slot(+value:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case _:
      do Result<&2,&2,String,Inv.Slot>:
        id : String <- D.text_field(value,"id")
        count : U32 <- D.number_field(value,"count")
        patch : String <- C.patch_text(J.member(value,"components"))
        D.resolve_output(Inv.InvStack{Inv.ItemKey{id,patch},count},defaults)

def described(value:Result<&2,&2,String,K.Recipe>,items:List<&2,R.ItemDefinition>) -> List<&2,J.Member>:
  match value:
    case Fail{message}: [J.JMember{"status",txt("error")},J.JMember{"error",txt(message)}]
    case Done{K.Unsupported{id,kind}}: [J.JMember{"status",txt("unsupported")},J.JMember{"kind",txt(kind)}]
    case Done{K.Cooking{id,kind,ingredient,output,time,xp}}:
      [J.JMember{"status",txt("accepted")},J.JMember{"kind",txt(K.kind_name(kind))},J.JMember{"cooking_time",num(time)},J.JMember{"experience_bits",num(F32.bits(xp))},J.JMember{"output",slot_value(R.create_output(output,items))}]

def matched(value:Result<&2,&2,String,K.Recipe>,tags:List<&2,R.Tag>,input:Inv.Slot) -> Bool:
  match value:
    case Done{+recipe}:
      match recipe:
        case K.Cooking{id,kind,ingredient,output,time,xp}: K.matches(recipe,kind,tags,input)
        case K.Unsupported{id,kind}: False{}
    case Fail{message}: False{}

def match_queries(values:List<&2,J.Value>,+recipe:Result<&2,&2,String,K.Recipe>,+tags:List<&2,R.Tag>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        slot : Inv.Slot <- raw_slot(value,defaults)
        head : J.Value = J.JBool{matched(recipe,tags,slot)}
        tail : List<&2,J.Value> <- match_queries(rest,recipe,tags,defaults)
        return head <> tail

def observations(values:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,Observed>>:
  match values:
    case Nil{}: Done{[]}
    case +value <> rest:
      do Result<&2,&2,String,List<&2,Observed>>:
        +id : String <- D.text_field(value,"id")
        source : J.Value <- D.field(value,"source")
        head : Observed = Observed{id,KD.decode(id,source,defaults)}
        tail : List<&2,Observed> <- observations(rest,defaults)
        return head <> tail

def lookup(values:List<&2,Observed>,+id:String) -> Result<&2,&2,String,K.Recipe>:
  match values:
    case Nil{}: Fail{"missing cooking test recipe"}
    case Observed{other,decoded} <> rest: R.choose(Result<&2,&2,String,K.Recipe>,decoded,lookup(rest,id),String.eq(id,other))

def describe_queries(values:List<&2,J.Value>,+observed:List<&2,Observed>,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case +value <> rest:
      K.Catalog{recipes,+tags,items} = catalog
      do Result<&2,&2,String,List<&2,J.Value>>:
        +id : String <- D.text_field(value,"id")
        +decoded : Result<&2,&2,String,K.Recipe> = lookup(observed,id)
        raw_matches : J.Value <- D.field(value,"matches")
        matches : List<&2,J.Value> <- D.array(raw_matches)
        results : List<&2,J.Value> <- match_queries(matches,decoded,tags,defaults)
        head : J.Value = obj(List.append(&2,J.Member,[J.JMember{"id",txt(id)},J.JMember{"matches",J.JArray{results}}],described(decoded,items)))
        tail : List<&2,J.Value> <- describe_queries(rest,observed,catalog,defaults)
        return head <> tail

def append_authority(value:Maybe<&2,Inv.ItemMetadata>,rest:List<&2,Inv.ItemMetadata>) -> List<&2,Inv.ItemMetadata>:
  match value:
    case None{}: rest
    case Some{head}: head <> rest

def authority(slots:List<&2,Inv.Slot>,+catalog:K.Catalog) -> List<&2,Inv.ItemMetadata>:
  match slots:
    case Nil{}: []
    case Inv.InvEmpty{} <> rest: authority(rest,catalog)
    case Inv.InvStack{key,count} <> rest:
      selected : Maybe<&2,Inv.ItemMetadata> = K.output_metadata(catalog,key)
      append_authority(selected,authority(rest,catalog))

def boundary_text(value:Maybe<&2,J.Value>) -> String:
  match value:
    case Some{J.JString{actual}}: actual
    case _: ""

def mutate_plan(value:K.Plan,mode:String) -> K.Plan:
  match value mode:
    case K.Plan{id,kind,output,before,time,xp} "stale_plan":
      K.Plan{id,kind,output,K.consume_input(before),time,xp}
    case K.Plan{id,kind,output,before,time,xp} "forged_plan":
      K.Plan{id,kind,Inv.InvStack{Inv.ItemKey{"minecraft:diamond",""},1},before,time,xp}
    case _ _: value

def completed(value:Result<&2,&2,String,K.Completion>,before:K.FurnaceSlots) -> J.Value:
  match value:
    case Fail{message}: obj([J.JMember{"accepted",J.JBool{False{}}}])
    case Done{K.Completion{id,snapshot,K.FurnaceSlots{input,fuel,output},xp}}:
      obj([J.JMember{"accepted",J.JBool{True{}}},J.JMember{"after",J.JArray{[slot_value(input),slot_value(fuel),slot_value(output)]}},J.JMember{"snapshot_current",J.JBool{K.furnace_equal(snapshot,before)}}])

def completion_plan(+value:K.Plan,+catalog:K.Catalog,+slots:K.FurnaceSlots,metadata:List<&2,Inv.ItemMetadata>,+limit:U32,id:String) -> Result<&2,&2,String,J.Value>:
  K.Plan{name,kind,+result,input,time,xp} = value
  K.FurnaceSlots{source,fuel,output} = slots
  capacity = K.capacity(output,result,limit,K.output_limit(K.output_metadata(catalog,K.slot_key(result))))
  Done{obj([J.JMember{"id",txt(id)},J.JMember{"can_burn",J.JBool{capacity}},J.JMember{"completion",completed(K.complete(catalog,value,slots,metadata,limit),slots)}])}

def completion_selected(selected:Maybe<&2,K.Plan>,mode:String,catalog:K.Catalog,slots:K.FurnaceSlots,metadata:List<&2,Inv.ItemMetadata>,limit:U32,id:String) -> Result<&2,&2,String,J.Value>:
  match selected:
    case None{}: Fail{"unsupported cooking transition fixture"}
    case Some{plan}: completion_plan(mutate_plan(plan,mode),catalog,slots,metadata,limit,id)

def completion_query(+value:J.Value,observed:List<&2,Observed>,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,J.Value>:
  K.Catalog{recipes,tags,+items} = catalog
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    name : String <- D.text_field(value,"recipe")
    recipe : K.Recipe <- lookup(observed,name)
    raw_input : J.Value <- D.field(value,"input")
    +input : Inv.Slot <- raw_slot(raw_input,defaults)
    raw_fuel : J.Value <- D.field(value,"fuel")
    +fuel : Inv.Slot <- raw_slot(raw_fuel,defaults)
    raw_output : J.Value <- D.field(value,"output")
    +output : Inv.Slot <- raw_slot(raw_output,defaults)
    limit : U32 <- D.number_field(value,"limit")
    +mode : String = boundary_text(J.member(value,"boundary"))
    metadata : List<&2,Inv.ItemMetadata> = R.choose(List<&2,Inv.ItemMetadata>,[],authority([input,fuel,output],catalog),String.eq(mode,"missing_metadata"))
    +slots : K.FurnaceSlots = K.FurnaceSlots{input,fuel,output}
    completion_selected(K.plan(recipe,items,input),mode,catalog,slots,metadata,limit,id)

def completions(values:List<&2,J.Value>,+observed:List<&2,Observed>,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- completion_query(value,observed,catalog,defaults)
        tail : List<&2,J.Value> <- completions(rest,observed,catalog,defaults)
        return head <> tail

def selected_recipes(values:List<&2,J.Value>,+observed:List<&2,Observed>) -> Result<&2,&2,String,List<&2,K.Recipe>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,K.Recipe>>:
        id : String <- D.text(value)
        head : K.Recipe <- lookup(observed,id)
        tail : List<&2,K.Recipe> <- selected_recipes(rest,observed)
        return head <> tail

def recipe_subset(base:K.Catalog,recipes:List<&2,K.Recipe>) -> K.Catalog:
  K.Catalog{previous,tags,items} = base
  K.Catalog{recipes,tags,items}

def query_metadata(mode:String,+input:Inv.Slot,catalog:K.Catalog) -> List<&2,Inv.ItemMetadata>:
  match mode:
    case "none": []
    case "zero": [Inv.ItemMetadata{K.slot_key(input),0}]
    case "large": [Inv.ItemMetadata{K.slot_key(input),100}]
    case "wrong": [Inv.ItemMetadata{Inv.ItemKey{"minecraft:oak_planks",""},64}]
    case _: authority([input],catalog)

def report_plan(result:Result<&2,&2,String,Maybe<&2,K.Plan>>,id:String) -> J.Value:
  match result:
    case Fail{message}: obj([J.JMember{"id",txt(id)},J.JMember{"error",txt(message)}])
    case Done{None{}}: obj([J.JMember{"id",txt(id)},J.JMember{"recipe",J.JNull{}},J.JMember{"output",J.JNull{}}])
    case Done{Some{K.Plan{name,kind,output,before,time,xp}}}: obj([J.JMember{"id",txt(id)},J.JMember{"recipe",txt(name)},J.JMember{"output",slot_value(output)}])

def find_selected(kind:Maybe<&2,K.CookingKind>,+catalog:K.Catalog,+input:Inv.Slot,metadata:List<&2,Inv.ItemMetadata>,mode:String,id:String) -> Result<&2,&2,String,J.Value>:
  match kind:
    case None{}: Fail{"unknown cooking query type"}
    case Some{+actual}:
      selected = R.choose(Result<&2,&2,String,Maybe<&2,K.Plan>>,K.find(catalog,actual,input),K.find_with_metadata(catalog,actual,input,metadata),String.eq(mode,"default"))
      Done{report_plan(selected,id)}

def find_query(+value:J.Value,+observed:List<&2,Observed>,+catalog:K.Catalog,defaults:List<&2,C.Default>) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    kind : String <- D.text_field(value,"kind")
    raw_choices : J.Value <- D.field(value,"recipes")
    choices : List<&2,J.Value> <- D.array(raw_choices)
    recipes : List<&2,K.Recipe> <- selected_recipes(choices,observed)
    +subset : K.Catalog = recipe_subset(catalog,recipes)
    raw_input : J.Value <- D.field(value,"input")
    +input : Inv.Slot <- raw_slot(raw_input,defaults)
    +mode : String <- D.text_field(value,"metadata")
    metadata : List<&2,Inv.ItemMetadata> = query_metadata(mode,input,subset)
    find_selected(KD.kind(kind),subset,input,metadata,mode,id)

def find_queries(values:List<&2,J.Value>,+observed:List<&2,Observed>,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- find_query(value,observed,catalog,defaults)
        tail : List<&2,J.Value> <- find_queries(rest,observed,catalog,defaults)
        return head <> tail

def float_bits(value:U32) -> F32:
  U32{word} = value
  F32{word}

def time_selected(value:K.Recipe,speed:F32,id:String) -> Result<&2,&2,String,J.Value>:
  match value:
    case K.Unsupported{name,kind}: Fail{"unsupported cooking-time fixture"}
    case K.Cooking{name,kind,ingredient,output,base,xp}: Done{obj([J.JMember{"id",txt(id)},J.JMember{"time",num(N.total_time(base,speed))}])}

def time_query(+value:J.Value,observed:List<&2,Observed>) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    recipe : String <- D.text_field(value,"recipe")
    actual : K.Recipe <- lookup(observed,recipe)
    bits : U32 <- D.number_field(value,"speed_bits")
    time_selected(actual,float_bits(bits),id)

def time_queries(values:List<&2,J.Value>,+observed:List<&2,Observed>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- time_query(value,observed)
        tail : List<&2,J.Value> <- time_queries(rest,observed)
        return head <> tail

def xp_query(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    +uses : U32 <- D.number_field(value,"uses")
    rate_bits : U32 <- D.number_field(value,"rate_bits")
    ticket_bits : U32 <- D.number_field(value,"ticket_bits")
    +rate : F32 = float_bits(rate_bits)
    +fraction : F32 = N.fraction(uses,rate)
    return obj([J.JMember{"id",txt(id)},J.JMember{"award",num(N.experience(uses,rate,float_bits(ticket_bits)))},J.JMember{"fraction_bits",num(F32.bits(fraction))},J.JMember{"advances_rng",J.JBool{F32.is_ne(fraction,0.0)}}])

def xp_queries(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- xp_query(value)
        tail : List<&2,J.Value> <- xp_queries(rest)
        return head <> tail

def catalog_recipes(values:List<&2,Observed>) -> List<&2,K.Recipe>:
  match values:
    case Nil{}: []
    case Observed{id,Done{recipe}} <> rest: recipe <> catalog_recipes(rest)
    case Observed{id,Fail{message}} <> rest: catalog_recipes(rest)

def with_recipes(base:K.Catalog,observed:List<&2,Observed>) -> K.Catalog:
  K.Catalog{recipes,tags,items} = base
  K.Catalog{catalog_recipes(observed),tags,items}

def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +raw_catalog : J.Value <- D.field(value,"catalog")
    base : K.Catalog <- KD.catalog(raw_catalog)
    raw_items : J.Value <- D.field(raw_catalog,"items")
    item_values : List<&2,J.Value> <- D.array(raw_items)
    +defaults : List<&2,C.Default> <- D.defaults_rows(item_values,[])
    raw_recipes : J.Value <- D.field(value,"recipes")
    +recipe_values : List<&2,J.Value> <- D.array(raw_recipes)
    +observed : List<&2,Observed> <- observations(recipe_values,defaults)
    +catalog : K.Catalog = with_recipes(base,observed)
    results : List<&2,J.Value> <- describe_queries(recipe_values,observed,catalog,defaults)
    raw_queries : J.Value <- D.field(value,"queries")
    query_values : List<&2,J.Value> <- D.array(raw_queries)
    queries : List<&2,J.Value> <- find_queries(query_values,observed,catalog,defaults)
    raw_transitions : J.Value <- D.field(value,"transitions")
    transition_values : List<&2,J.Value> <- D.array(raw_transitions)
    transitions : List<&2,J.Value> <- completions(transition_values,observed,catalog,defaults)
    raw_times : J.Value <- D.field(value,"times")
    time_values : List<&2,J.Value> <- D.array(raw_times)
    times : List<&2,J.Value> <- time_queries(time_values,observed)
    raw_xp : J.Value <- D.field(value,"xp")
    xp_values : List<&2,J.Value> <- D.array(raw_xp)
    xp : List<&2,J.Value> <- xp_queries(xp_values)
    return obj([J.JMember{"recipes",J.JArray{results}},J.JMember{"queries",J.JArray{queries}},J.JMember{"transitions",J.JArray{transitions}},J.JMember{"times",J.JArray{times}},J.JMember{"xp",J.JArray{xp}}])

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
    parsed(J.parse_bounded(input,U32.to_nat(8388608),64))

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected cooking fixture path")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
