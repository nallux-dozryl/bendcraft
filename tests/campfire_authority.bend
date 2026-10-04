import Base
import ../src/json.bend as J
import ../src/inventory.bend as I
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/cooking_recipe.bend as K
import ../src/campfire_authority.bend as F
import ../src/campfire_authority_items.bend as A
import ../src/campfire_authority_loader.bend as L
import ../src/u32_decimal.bend as Decimal
import ./campfire_authority_guards.bend as G

type Session is Type:
  Session{owner:F.State,context:A.Context}
type Report is Data:
  Report{effects:F.Effects,dirty:Nat,extra:List<&2,J.Member>}
def num(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def nat(value:Nat) -> J.Value: num(U32.from_nat(value))
def obj(values:List<&2,J.Member>) -> J.Value: J.JObject{values}
def txt(value:String) -> J.Value: J.JString{value}
def slot(value:I.Slot) -> J.Value:
  match value:
    case I.InvEmpty{}: J.JNull{}
    case I.InvStack{I.ItemKey{id,components},count}: obj([J.JMember{"id",txt(id)},J.JMember{"count",num(count)},J.JMember{"components",txt(components)}])
def item(value:A.Input) -> J.Value:
  A.Input{input,patch} = value
  slot(input)
def cache(value:Maybe<&2,String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{id}: txt(id)
def state(value:F.Four,recipe:Maybe<&2,String>) -> J.Value:
  F.Four{F.Cell{a,pa,ta},F.Cell{b,pb,tb},F.Cell{c,pc,tc},F.Cell{d,pd,td}} = value
  obj([J.JMember{"items",J.JArray{[item(a),item(b),item(c),item(d)]}},J.JMember{"progress",J.JArray{[num(pa),num(pb),num(pc),num(pd)]}},J.JMember{"total",J.JArray{[num(ta),num(tb),num(tc),num(td)]}},J.JMember{"cache",cache(recipe)}])
def drop_values(values:List<&2,F.Drop>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case F.Drop{index,I.InvEmpty{}} <> rest: drop_values(rest)
    case F.Drop{index,input} <> rest: slot(input) <> drop_values(rest)
def report(value:F.Effects,extra:List<&2,J.Member>) -> Report:
  F.Effects{drops,+dirty,updates,changes} = value
  Report{F.Effects{drops,dirty,updates,changes},R.choose(Nat,1n,0n,dirty),extra}
def observed(session:Session,op:String,result:Result<&2,&2,String,Report>) -> Session & Result<&2,&2,String,J.Value>:
  Session{F.State{kind,lit,+cells,+recipe},context} = session
  match result:
    case Fail{message}: (Session{F.State{kind,lit,cells,recipe},context},Fail{message})
    case Done{Report{F.Effects{drops,ignored,updates,changes},dirty,extra}}:
      (Session{F.State{kind,lit,cells,recipe},context},Done{obj(List.append(&2,J.Member,
        [J.JMember{"op",txt(op)},J.JMember{"state",state(cells,recipe)},J.JMember{"drops",J.JArray{drop_values(drops)}},J.JMember{"dirty",nat(dirty)},J.JMember{"updates",nat(updates)},J.JMember{"changes",nat(changes)}],extra))})
def raw_patch(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case None{}: J.JObject{[]}
    case Some{patch}: patch
def raw(+value:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,A.Input>:
  match value:
    case J.JNull{}: Done{A.plain()}
    case _:
      do Result<&2,&2,String,A.Input>:
        id : String <- D.text_field(value,"id")
        count : U32 <- D.number_field(value,"count")
        patch : String <- C.patch_text(J.member(value,"components"))
        input : I.Slot <- D.resolve_output(I.InvStack{I.ItemKey{id,patch},count},defaults)
        return A.Input{input,raw_patch(J.member(value,"components"))}
def array_field(value:J.Value,name:String) -> Result<&2,&2,String,List<&2,J.Value>>:
  do Result<&2,&2,String,List<&2,J.Value>>:
    found : J.Value <- D.field(value,name)
    D.array(found)
def bool(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{result}: Done{result}
    case _: Fail{"expected boolean"}
def bool_field(value:J.Value,name:String) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    found : J.Value <- D.field(value,name)
    bool(found)
def recipe(values:List<&2,K.Recipe>,+id:String) -> Result<&2,&2,String,K.Recipe>:
  match values:
    case Nil{}: Fail{"unknown test recipe"}
    case +head <> rest: R.choose(Result<&2,&2,String,K.Recipe>,Done{head},recipe(rest,id),String.eq(K.recipe_id(head),id))
def selected(values:List<&2,J.Value>,+recipes:List<&2,K.Recipe>) -> Result<&2,&2,String,List<&2,K.Recipe>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,K.Recipe>>:
        id : String <- D.text(value)
        head : K.Recipe <- recipe(recipes,id)
        tail : List<&2,K.Recipe> <- selected(rest,recipes)
        return head <> tail
def choose_recipes(+base:A.Context,current:A.Context,values:List<&2,J.Value>) -> Result<&2,&2,String,A.Context>:
  A.Context{K.Catalog{recipes,tags,items},defaults,original} = base
  A.Context{ignored,d,features} = current
  do Result<&2,&2,String,A.Context>:
    picked : List<&2,K.Recipe> <- selected(values,recipes)
    return A.Context{K.Catalog{picked,tags,items},defaults,features}
def features(values:List<&2,R.ItemDefinition>,+enabled:Bool) -> Map<&2,Maybe<&2,Bool>>:
  match values:
    case Nil{}: MTip{}
    case R.ItemDefinition{id,limit,remainder} <> rest: Map.set(&2,Maybe<&2,Bool>,features(rest,enabled),id,Some{enabled})
def feature_context(base:A.Context,current:A.Context,enabled:Bool) -> A.Context:
  A.Context{ignored,d,original} = base
  A.Context{+catalog,defaults,old} = current
  K.Catalog{recipes,tags,items} = catalog
  A.Context{catalog,defaults,R.choose(Map<&2,Maybe<&2,Bool>>,original,features(items,False{}),enabled)}
def place_done(context:A.Context,result:F.State & F.Placement) -> Session & Result<&2,&2,String,Report>:
  (owner,+placement) = result
  F.Placement{held,status} = placement
  (Session{owner,context},Done{report(F.placement_effects(placement),[J.JMember{"accepted",J.JBool{Result.is_done(&2,&2,String,U32,status)}},J.JMember{"held",item(held)}])})
def place_parsed(session:Session,result:Result<&2,&2,String,A.Input>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,+context} = session
  match result:
    case Fail{message}: (Session{owner,context},Fail{message})
    case Done{input}: place_done(context,F.place(context,owner,input,False{}))
def tick_more(next:F.State -> F.Effects -> Nat -> F.State & Result<&2,&2,String,Report>,acc:F.Effects,dirty:Nat,result:F.State & Result<&2,&2,String,F.Effects>) -> F.State & Result<&2,&2,String,Report>:
  match result:
    case (owner,Fail{message}): (owner,Fail{message})
    case (owner,Done{+effect}):
      F.Effects{drops,changed,u,c} = effect
      next(owner,F.join_effects(acc,effect),Nat.add(dirty,R.choose(Nat,1n,0n,changed)))
def tick_loop(count:Nat,+context:A.Context,owner:F.State,acc:F.Effects,dirty:Nat) -> F.State & Result<&2,&2,String,Report>:
  match count:
    case 0n: (owner,Done{Report{acc,dirty,[]}})
    case 1n+rest: tick_more(o => e => d => tick_loop(rest,context,o,e,d),acc,dirty,F.step(context,owner))
def tick_done(context:A.Context,result:F.State & Result<&2,&2,String,Report>) -> Session & Result<&2,&2,String,Report>:
  (owner,value) = result
  (Session{owner,context},value)
def ticks(session:Session,result:Result<&2,&2,String,U32>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,+context} = session
  match result:
    case Fail{message}: (Session{owner,context},Fail{message})
    case Done{count}: tick_done(context,tick_loop(U32.to_nat(count),context,owner,F.effects(),0n))
def lit(session:Session,result:Result<&2,&2,String,Bool>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,context} = session
  match result:
    case Fail{message}: (Session{owner,context},Fail{message})
    case Done{next}: (Session{F.set_lit(owner,next),context},Done{report(F.effects(),[])})
def changed_context(session:Session,result:Result<&2,&2,String,A.Context>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,old} = session
  match result:
    case Fail{message}: (Session{owner,old},Fail{message})
    case Done{next}: (Session{owner,next},Done{report(F.effects(),[])})
def catalog(session:Session,base:A.Context,result:Result<&2,&2,String,List<&2,J.Value>>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,+current} = session
  match result:
    case Fail{message}: (Session{owner,current},Fail{message})
    case Done{values}: changed_context(Session{owner,current},choose_recipes(base,current,values))
def feature(session:Session,base:A.Context,result:Result<&2,&2,String,Bool>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,current} = session
  match result:
    case Fail{message}: (Session{owner,current},Fail{message})
    case Done{enabled}: (Session{owner,feature_context(base,current,enabled)},Done{report(F.effects(),[])})
def cell(value:J.Value,progress:J.Value,total:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,F.Cell>:
  do Result<&2,&2,String,F.Cell>:
    input : A.Input <- raw(value,defaults)
    p : U32 <- D.number(progress)
    t : U32 <- D.number(total)
    return F.Cell{input,p,t}
def four(values:List<&2,J.Value>,progress:List<&2,J.Value>,total:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,F.Record>:
  match values progress total:
    case a <> b <> c <> d <> Nil{} pa <> pb <> pc <> pd <> Nil{} ta <> tb <> tc <> td <> Nil{}:
      do Result<&2,&2,String,F.Record>:
        first : F.Cell <- cell(a,pa,ta,defaults)
        second : F.Cell <- cell(b,pb,tb,defaults)
        third : F.Cell <- cell(c,pc,tc,defaults)
        fourth : F.Cell <- cell(d,pd,td,defaults)
        return F.Record{F.Four{first,second,third,fourth}}
    case _ _ _: Fail{"test record requires four cells and timer words"}
def record(+value:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,F.Record>:
  do Result<&2,&2,String,F.Record>:
    items : List<&2,J.Value> <- array_field(value,"items")
    p : List<&2,J.Value> <- array_field(value,"progress")
    t : List<&2,J.Value> <- array_field(value,"total")
    four(items,p,t,defaults)
def load_done(context:A.Context,result:F.State & Result<&2,&2,String,Unit>) -> Session & Result<&2,&2,String,Report>:
  match result:
    case (owner,Fail{message}): (Session{owner,context},Fail{message})
    case (owner,Done{unit}): (Session{owner,context},Done{report(F.effects(),[])})
def load(session:Session,result:Result<&2,&2,String,F.Record>) -> Session & Result<&2,&2,String,Report>:
  Session{owner,+context} = session
  match result:
    case Fail{message}: (Session{owner,context},Fail{message})
    case Done{value}: load_done(context,F.load_record(context,owner,value))
def removed(context:A.Context,result:F.State & F.Effects) -> Session & Result<&2,&2,String,Report>:
  (owner,effects) = result
  (Session{owner,context},Done{report(effects,[])})
def action(session:Session,+base:A.Context,+value:J.Value,op:String) -> Session & Result<&2,&2,String,Report>:
  Session{owner,+context} = session
  A.Context{recipes,defaults,flags} = context
  match op:
    case "place": place_parsed(Session{owner,context},Result.bind(&2,&2,String,J.Value,A.Input,D.field(value,"item"),v => raw(v,defaults)))
    case "ticks": ticks(Session{owner,context},D.number_field(value,"count"))
    case "lit": lit(Session{owner,context},bool_field(value,"value"))
    case "catalog": catalog(Session{owner,context},base,array_field(value,"recipes"))
    case "features": feature(Session{owner,context},base,bool_field(value,"enabled"))
    case "load": load(Session{owner,context},record(value,defaults))
    case "remove": removed(context,F.remove(owner))
    case "clear": (Session{F.clear(owner),context},Done{report(F.effects(),[])})
    case _: (Session{owner,context},Fail{"unknown campfire operation"})
def action_observed(op:String,result:Session & Result<&2,&2,String,Report>) -> Session & Result<&2,&2,String,J.Value>:
  (session,report) = result
  observed(session,op,report)
def action_parsed(session:Session,base:A.Context,value:J.Value,result:Result<&2,&2,String,String>) -> Session & Result<&2,&2,String,J.Value>:
  match result:
    case Fail{message}: (session,Fail{message})
    case Done{+op}: action_observed(op,action(session,base,value,op))
def prepended(head:J.Value,result:Session & Result<&2,&2,String,List<&2,J.Value>>) -> Session & Result<&2,&2,String,List<&2,J.Value>>:
  match result:
    case (session,Fail{message}): (session,Fail{message})
    case (session,Done{tail}): (session,Done{head <> tail})
def continue(result:Session & Result<&2,&2,String,J.Value>,next:Session -> Session & Result<&2,&2,String,List<&2,J.Value>>) -> Session & Result<&2,&2,String,List<&2,J.Value>>:
  match result:
    case (session,Fail{message}): (session,Fail{message})
    case (session,Done{head}): prepended(head,next(session))
def actions(values:List<&2,J.Value>,session:Session,+base:A.Context) -> Session & Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: (session,Done{[]})
    case +value <> rest: continue(action_parsed(session,base,value,D.text_field(value,"op")),s => actions(rest,s,base))
def finished(id:String,result:Session & Result<&2,&2,String,List<&2,J.Value>>) -> Result<&2,&2,String,J.Value>:
  match result:
    case (session,Fail{message}): Fail{message}
    case (session,Done{values}): Done{obj([J.JMember{"id",txt(id)},J.JMember{"observations",J.JArray{values}}])}
def fixture_run(id:String,base:A.Context,context:A.Context,soul:Bool,lit:Bool,values:List<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  finished(id,actions(values,Session{F.new(R.choose(F.CampfireKind,F.Soul{},F.Ordinary{},soul),lit),context},base))
def fixture(+value:J.Value,+base:A.Context) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(value,"id")
    soul : Bool <- bool_field(value,"soul")
    lit : Bool <- bool_field(value,"lit")
    recipes : List<&2,J.Value> <- array_field(value,"recipes")
    context : A.Context <- choose_recipes(base,base,recipes)
    values : List<&2,J.Value> <- array_field(value,"actions")
    fixture_run(id,base,context,soul,lit,values)
def fixtures(values:List<&2,J.Value>,+context:A.Context) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(value,context)
        tail : List<&2,J.Value> <- fixtures(rest,context)
        return head <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_catalog : J.Value <- D.field(value,"catalog")
    +context : A.Context <- L.catalog(raw_catalog)
    raw_cases : List<&2,J.Value> <- array_field(value,"cases")
    cases : List<&2,J.Value> <- fixtures(raw_cases,context)
    return obj([J.JMember{"cases",J.JArray{cases}},J.JMember{"guards",J.JArray{G.run(context)}}])
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
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected campfire fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
