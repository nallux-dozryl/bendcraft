import Base
import ../src/json.bend as J
import ../src/inventory.bend as Inv
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/cooking_recipe.bend as K
import ../src/cooking_recipe_decoder.bend as KD
import ../src/furnace_authority.bend as A
import ../src/furnace_authority_fuel.bend as F
import ../src/furnace_authority_decoder.bend as FD
import ../src/furnace_authority_slots.bend as S
import ../src/furnace_authority_xp.bend as X
import ../src/u32_decimal.bend as Decimal

def num(+value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def txt(+value:String) -> J.Value: J.JString{value}
def obj(+values:List<&2,J.Member>) -> J.Value: J.JObject{values}
def float_bits(value:U32) -> F32:
  U32{word} = value
  F32{word}
def slot(+value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: obj([J.JMember{"id",txt(id)},J.JMember{"count",num(count)},J.JMember{"components",txt(components)}])
def slots(+value:K.FurnaceSlots) -> List<&2,J.Value>:
  K.FurnaceSlots{input,fuel,output} = value
  [slot(input),slot(fuel),slot(output)]
def uses(+values:List<&2,A.Use>) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case A.Use{id,count} <> rest: J.JMember{id,num(count)} <> uses(rest)
def optional_id(+value:Maybe<&2,String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{id}: txt(id)
def snapshot(+value:A.Snapshot) -> J.Value:
  A.Snapshot{A.Frame{kind,r,t,s,c,speed,cached,table},items} = value
  obj([J.JMember{"litTimeRemaining",num(r)},J.JMember{"litTotalTime",num(t)},J.JMember{"cookingTimer",num(s)},J.JMember{"cookingTotalTime",num(c)},J.JMember{"speed_bits",num(F32.bits(speed))},J.JMember{"cached",optional_id(cached)},J.JMember{"uses",obj(uses(table))},J.JMember{"slots",J.JArray{slots(items)}}])
def optional_bool(+value:Maybe<&2,Bool>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{value}: J.JBool{value}
def drops(+values:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: slot(value) <> drops(rest)
def raw(+value:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case _:
      do Result<&2,&2,String,Inv.Slot>:
        id : String <- D.text_field(value,"id")
        count : U32 <- D.number_field(value,"count")
        patch : String <- C.patch_text(J.member(value,"components"))
        D.resolve_output(Inv.InvStack{Inv.ItemKey{id,patch},count},defaults)
def raw_slots(+values:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,K.FurnaceSlots>:
  match values:
    case a <> b <> c <> Nil{}:
      do Result<&2,&2,String,K.FurnaceSlots>:
        input : Inv.Slot <- raw(a,defaults)
        fuel : Inv.Slot <- raw(b,defaults)
        output : Inv.Slot <- raw(c,defaults)
        return K.FurnaceSlots{input,fuel,output}
    case _: Fail{"fixture requires exactly three slots"}
def signed(+value:J.Value,+name:String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    actual : J.Value <- D.field(value,name)
    KD.cooking_time(actual)
def cached(+value:Maybe<&2,J.Value>) -> Maybe<&2,String>:
  match value:
    case Some{J.JString{id}}: Some{id}
    case _: None{}
def raw_uses(+values:List<&2,J.Member>) -> Result<&2,&2,String,List<&2,A.Use>>:
  match values:
    case Nil{}: Done{[]}
    case J.JMember{id,value} <> rest:
      do Result<&2,&2,String,List<&2,A.Use>>:
        count : U32 <- KD.cooking_time(value)
        tail : List<&2,A.Use> <- raw_uses(rest)
        return A.Use{id,count} <> tail
def raw_use_object(+value:J.Value) -> Result<&2,&2,String,List<&2,A.Use>>:
  match value:
    case J.JObject{members}: raw_uses(members)
    case _: Fail{"fixture uses must be object"}
def selected_kind(+value:Maybe<&2,K.CookingKind>) -> Result<&2,&2,String,K.CookingKind>:
  match value:
    case None{}: Fail{"unknown fixture kind"}
    case Some{kind}: Done{kind}
def raw_frame(+value:J.Value) -> Result<&2,&2,String,A.Frame>:
  do Result<&2,&2,String,A.Frame>:
    raw_kind : String <- D.text_field(value,"kind")
    kind : K.CookingKind <- selected_kind(KD.kind(raw_kind))
    r : U32 <- signed(value,"litTimeRemaining")
    t : U32 <- signed(value,"litTotalTime")
    s : U32 <- signed(value,"cookingTimer")
    c : U32 <- signed(value,"cookingTotalTime")
    speed : U32 <- D.number_field(value,"speed_bits")
    raw_table : J.Value <- D.field(value,"uses")
    table : List<&2,A.Use> <- raw_use_object(raw_table)
    return A.Frame{kind,r,t,s,c,float_bits(speed),cached(J.member(value,"cached")),table}
def admitted(+defaults:Maybe<&2,J.Value>,+key:Inv.ItemKey,+patch:J.Value) -> Result<&2,&2,String,F.FuelProfile>:
  match defaults:
    case None{}: Fail{"missing fixture initialized defaults"}
    case Some{map}: FD.admit(map,key,patch)
def profile_slot(+value:Inv.Slot,+defaults:List<&2,C.Default>,+id:String,+patch:Maybe<&2,J.Value>,+tail:List<&2,F.FuelProfile>) -> Result<&2,&2,String,List<&2,F.FuelProfile>>:
  match value patch:
    case Inv.InvStack{key,count} Some{source}:
      do Result<&2,&2,String,List<&2,F.FuelProfile>>:
        head : F.FuelProfile <- admitted(C.default_for(defaults,id),key,source)
        return head <> tail
    case _ _: Done{tail}
def profiles(+values:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,F.FuelProfile>>:
  match values:
    case Nil{}: Done{[]}
    case J.JNull{} <> rest: profiles(rest,defaults)
    case +value <> rest:
      do Result<&2,&2,String,List<&2,F.FuelProfile>>:
        +id : String <- D.text_field(value,"id")
        +key : Inv.Slot <- raw(value,defaults)
        tail : List<&2,F.FuelProfile> <- profiles(rest,defaults)
        profile_slot(key,defaults,id,J.member(value,"components"),tail)
def metadata(+values:List<&2,F.FuelProfile>) -> List<&2,Inv.ItemMetadata>:
  match values:
    case Nil{}: []
    case F.FuelProfile{key,fuel,head} <> rest: head <> metadata(rest)
def optional_slot(+value:Maybe<&2,J.Value>,+rest:List<&2,J.Value>) -> List<&2,J.Value>:
  match value:
    case None{}: rest
    case Some{head}: head <> rest
def op_slots(+values:List<&2,J.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case +value <> rest: optional_slot(J.member(value,"slot"),op_slots(rest))
def describe(result:A.State & Maybe<&2,A.Snapshot>,+effects:A.Effects) -> A.State & Result<&2,&2,String,J.Value>:
  match result effects:
    case (state,None{}) A.Effects{dirty,changed,dropped,completed}: (state,Fail{"invalid fixture owned array"})
    case (state,Some{after}) A.Effects{dirty,changed,dropped,completed}: (state,Done{obj([J.JMember{"after",snapshot(after)},J.JMember{"dirty",J.JBool{dirty}},J.JMember{"lit_change",optional_bool(changed)},J.JMember{"drops",J.JArray{drops(dropped)}}])})
def observed(result:A.State & Result<&2,&2,String,A.Effects>) -> A.State & Result<&2,&2,String,J.Value>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{effects}): describe(A.inspect(state),effects)
def put_slot(state:A.State,+catalog:K.Catalog,+index:U32,+value:Result<&2,&2,String,Inv.Slot>,+metadata:List<&2,Inv.ItemMetadata>) -> A.State & Result<&2,&2,String,A.Effects>:
  match value:
    case Fail{message}: (state,Fail{message})
    case Done{slot}: S.put(state,catalog,index,slot,metadata)
def put_parsed(state:A.State,+catalog:K.Catalog,+profiles:List<&2,F.FuelProfile>,+index:Result<&2,&2,String,U32>,+value:Result<&2,&2,String,J.Value>,+defaults:List<&2,C.Default>) -> A.State & Result<&2,&2,String,A.Effects>:
  match index value:
    case Fail{message} _: (state,Fail{message})
    case Done{index} Fail{message}: (state,Fail{message})
    case Done{index} Done{value}: put_slot(state,catalog,index,raw(value,defaults),metadata(profiles))
def action_kind(state:A.State,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+defaults:List<&2,C.Default>,+value:J.Value,+put:Bool) -> A.State & Result<&2,&2,String,A.Effects>:
  match put:
    case True{}: put_parsed(state,catalog,profiles,D.number_field(value,"index"),D.field(value,"slot"),defaults)
    case False{}: A.step(state,catalog,fuel_catalog,context,profiles,metadata(profiles))
def action_parsed(state:A.State,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+defaults:List<&2,C.Default>,+value:J.Value,+parsed_kind:Result<&2,&2,String,String>) -> A.State & Result<&2,&2,String,A.Effects>:
  match parsed_kind:
    case Fail{message}: (state,Fail{message})
    case Done{other}: action_kind(state,catalog,fuel_catalog,context,profiles,defaults,value,String.eq(other,"put"))
def action(state:A.State,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+defaults:List<&2,C.Default>,+value:J.Value) -> A.State & Result<&2,&2,String,A.Effects>:
  action_parsed(state,catalog,fuel_catalog,context,profiles,defaults,value,D.text_field(value,"type"))
def prepended(+head:J.Value,result:A.State & Result<&2,&2,String,List<&2,J.Value>>) -> A.State & Result<&2,&2,String,List<&2,J.Value>>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{tail}): (state,Done{head <> tail})
def step_observed(result:A.State & Result<&2,&2,String,J.Value>,next:A.State -> A.State & Result<&2,&2,String,List<&2,J.Value>>) -> A.State & Result<&2,&2,String,List<&2,J.Value>>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{head}): prepended(head,next(state))
def steps(+values:List<&2,J.Value>,state:A.State,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+defaults:List<&2,C.Default>) -> A.State & Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: (state,Done{[]})
    case value <> rest: step_observed(observed(action(state,catalog,fuel_catalog,context,profiles,defaults,value)),owner => steps(rest,owner,catalog,fuel_catalog,context,profiles,defaults))
def context(+kind:K.CookingKind) -> F.Context:
  match kind:
    case K.Smelting{}: F.Context{"minecraft:furnace",256n}
    case K.Blasting{}: F.Context{"minecraft:blast_furnace",256n}
    case _: F.Context{"minecraft:smoker",256n}
def finished(+id:String,result:A.State & Result<&2,&2,String,List<&2,J.Value>>) -> Result<&2,&2,String,J.Value>:
  match result:
    case (state,Fail{message}): Fail{message}
    case (state,Done{values}): Done{obj([J.JMember{"id",txt(id)},J.JMember{"steps",J.JArray{values}}])}
def fixture_run(+id:String,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+frame:A.Frame,+slots:K.FurnaceSlots,+profiles:List<&2,F.FuelProfile>,+defaults:List<&2,C.Default>,+ops:List<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  A.Frame{kind,r,t,s,c,speed,cached,uses} = frame
  finished(id,steps(ops,A.install(A.Snapshot{frame,slots}),catalog,fuel_catalog,context(kind),profiles,defaults))
def fixture(+row:J.Value,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(row,"id")
    raw_items : J.Value <- D.field(row,"slots")
    +items : List<&2,J.Value> <- D.array(raw_items)
    slots : K.FurnaceSlots <- raw_slots(items,defaults)
    frame : A.Frame <- raw_frame(row)
    raw_ops : J.Value <- D.field(row,"ops")
    +ops : List<&2,J.Value> <- D.array(raw_ops)
    admitted : List<&2,F.FuelProfile> <- profiles(List.append(&2,J.Value,items,op_slots(ops)),defaults)
    fixture_run(id,catalog,fuel_catalog,frame,slots,admitted,defaults,ops)
def fixtures(+values:List<&2,J.Value>,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(value,catalog,fuel_catalog,defaults)
        tail : List<&2,J.Value> <- fixtures(rest,catalog,fuel_catalog,defaults)
        return head <> tail
def fuel_described(+id:String,+block:String,+value:F.Values) -> J.Value:
  F.Values{time,speed} = value
  obj([J.JMember{"id",txt(id)},J.JMember{"block",txt(block)},J.JMember{"time",num(time)},J.JMember{"speed_bits",num(F32.bits(speed))}])
def fuel_value(+row:J.Value,+catalog:F.Catalog) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +id : String <- D.text_field(row,"id")
    +block : String <- D.text_field(row,"block")
    fuel : Maybe<&2,F.CookingFuel> <- F.fuel_for(catalog,[],Inv.InvStack{Inv.ItemKey{id,""},1})
    actual : F.Values <- F.values(catalog,F.Context{block,256n},fuel)
    return fuel_described(id,block,actual)
def fuel_values(+values:List<&2,J.Value>,+catalog:F.Catalog) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fuel_value(value,catalog)
        tail : List<&2,J.Value> <- fuel_values(rest,catalog)
        return head <> tail
def fuel_defaults(+catalog:F.Catalog) -> List<&2,C.Default>:
  F.Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  defaults
def xp_requests(values:List<&2,A.XpRequest>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case A.XpRequest{id,count,rate} <> rest: obj([J.JMember{"id",txt(id)},J.JMember{"uses",num(count)},J.JMember{"rate_bits",num(F32.bits(rate))}]) <> xp_requests(rest)
def xp_described(id:String,frame:A.Frame,value:Result<&2,&2,String,List<&2,A.XpRequest>>) -> J.Value:
  A.Frame{kind,r,t,s,c,speed,cached,table} = frame
  match value:
    case Fail{message}: obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("error")},J.JMember{"uses",obj(uses(table))}])
    case Done{requests}: obj([J.JMember{"id",txt(id)},J.JMember{"status",txt("accepted")},J.JMember{"requests",J.JArray{xp_requests(requests)}},J.JMember{"uses",obj(uses(table))}])
def xp_with(catalog:K.Catalog,id:String,table:List<&2,A.Use>,recipes:List<&2,K.Recipe>) -> J.Value:
  K.Catalog{previous,tags,items} = catalog
  +frame = {A.Frame{K.Smelting{},0,0,0,0,1.0,None{},table} : A.Frame}
  xp_described(id,frame,X.pop(K.Catalog{recipes,tags,items},frame))
def xp_fixture(+row:J.Value,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,J.Value>:
  K.Catalog{old,+tags,+items} = catalog
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(row,"id")
    raw_table : J.Value <- D.field(row,"uses")
    table : List<&2,A.Use> <- raw_use_object(raw_table)
    sources : List<&2,J.Value> <- FD.array_field(row,"recipes")
    recipes : List<&2,K.Recipe> <- KD.rows(sources,tags,items,defaults,[])
    return xp_with(catalog,id,table,recipes)
def xp_fixtures(values:List<&2,J.Value>,+catalog:K.Catalog,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- xp_fixture(value,catalog,defaults)
        tail : List<&2,J.Value> <- xp_fixtures(rest,catalog,defaults)
        return head <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_cooking : J.Value <- D.field(value,"catalog")
    +catalog : K.Catalog <- KD.catalog(raw_cooking)
    raw_fuel : J.Value <- D.field(value,"fuel_catalog")
    +fuel_catalog : F.Catalog <- FD.catalog(raw_fuel)
    +defaults : List<&2,C.Default> = fuel_defaults(fuel_catalog)
    raw_cases : List<&2,J.Value> <- FD.array_field(value,"cases")
    cases : List<&2,J.Value> <- fixtures(raw_cases,catalog,fuel_catalog,defaults)
    raw_values : List<&2,J.Value> <- FD.array_field(value,"values")
    values : List<&2,J.Value> <- fuel_values(raw_values,fuel_catalog)
    raw_xp : List<&2,J.Value> <- FD.array_field(value,"xp_cases")
    xp : List<&2,J.Value> <- xp_fixtures(raw_xp,catalog,defaults)
    return obj([J.JMember{"cases",J.JArray{cases}},J.JMember{"values",J.JArray{values}},J.JMember{"xp_cases",J.JArray{xp}}])
def respond(+value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{actual}: IO.print(J.encode(actual))
def parsed(+value:Result<&2,&2,String,J.Value>) -> IO(Unit):
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
    case _: IO.die(Unit,2,"expected furnace fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
