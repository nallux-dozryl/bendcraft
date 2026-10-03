import Base
import ../src/json.bend as J
import ../src/resource_json.bend as R
import ../src/blockstate_model.bend as M

def bool_is(result:Result<&2,&2,M.Error,Bool>,expected:Bool) -> Bool:
  match result:
    case Done{value}: Bool.not(Bool.xor(value,expected))
    case _: False{}
def variant_is(result:Result<&2,&2,M.Error,M.Variant>,name:String) -> Bool:
  match result:
    case Done{M.Variant{model,x,y,z,lock}}: String.eq(model,name)
    case _: False{}
def choice_failed(result:Result<&2,&2,M.Error,M.Variant>) -> Bool:
  match result:
    case Fail{error}: True{}
    case _: False{}
def fixture_choice() -> M.Choice:
  M.WeightedChoice{[M.Weighted{M.Variant{"a",0,0,0,False{}},1},M.Weighted{M.Variant{"b",0,0,0,False{}},3}],4}
law empty_and:
  {bool_is(M.bound_matches(M.And{Nil{}},MTip{}),True{}) == True{} : Bool}
def empty_and():
  {==}
law empty_or:
  {bool_is(M.bound_matches(M.Or{Nil{}},MTip{}),False{}) == True{} : Bool}
def empty_or():
  {==}
law term_negation:
  {M.terms_match(M.Term{"true",True{}} <> Nil{},"false") == True{} : Bool}
def term_negation():
  {==}
law weighted_first:
  {variant_is(M.choose(fixture_choice(),0),"a") == True{} : Bool}
def weighted_first():
  {==}
law weighted_boundary:
  {variant_is(M.choose(fixture_choice(),1),"b") == True{} : Bool}
def weighted_boundary():
  {==}
law weighted_last:
  {variant_is(M.choose(fixture_choice(),3),"b") == True{} : Bool}
def weighted_last():
  {==}
law ticket_rejection:
  {choice_failed(M.choose(fixture_choice(),4)) == True{} : Bool}
def ticket_rejection():
  {==}
law single_ignores_ticket:
  {variant_is(M.choose(M.Single{M.Variant{"a",0,0,0,False{}}},4294967295),"a") == True{} : Bool}
def single_ignores_ticket():
  {==}

# Native harness.
def text(+s:String) -> J.Value:
  J.JString{s}
def number(+n:U32) -> J.Value:
  J.JNumber{U32.show(n)}
def string_values(+values:List<&2,String>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: text(head) <> string_values(rest)
def strings(+values:List<&2,String>) -> J.Value:
  J.JArray{string_values(values)}
def error_value(+value:M.Error) -> J.Value:
  match value:
    case M.Error{code,path,detail}: J.JObject{[J.JMember{"code",text(code)},J.JMember{"path",text(path)},J.JMember{"detail",text(detail)}]}
def error_values(+values:List<&2,M.Error>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: error_value(head) <> error_values(rest)
def errors(+values:List<&2,M.Error>) -> J.Value:
  J.JArray{error_values(values)}
def failed(+value:M.Error) -> J.Value:
  J.JObject{[J.JMember{"status",text("error")},J.JMember{"error",error_value(value)}]}
def variant(+value:M.Variant) -> J.Value:
  match value:
    case M.Variant{name,x,y,z,lock}: J.JObject{[J.JMember{"model",text(name)},J.JMember{"x",number(x)},
      J.JMember{"y",number(y)},J.JMember{"z",number(z)},J.JMember{"uvlock",J.JBool{lock}}]}
def entries(+values:List<&2,M.Weighted>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.Weighted{v,w} <> rest: J.JObject{[J.JMember{"variant",variant(v)},J.JMember{"weight",number(w)}]} <> entries(rest)
def choice(+value:M.Choice) -> J.Value:
  match value:
    case M.Single{v}: J.JObject{[J.JMember{"kind",text("single")},J.JMember{"variant",variant(v)}]}
    case M.WeightedChoice{values,total}: J.JObject{[J.JMember{"kind",text("weighted")},J.JMember{"total",number(total)},
      J.JMember{"entries",J.JArray{entries(values)}}]}
def terms(+values:List<&2,M.Term>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.Term{v,n} <> rest: J.JObject{[J.JMember{"value",text(v)},J.JMember{"negated",J.JBool{n}}]} <> terms(rest)
def tests(+values:List<&2,M.Test>) -> List<&2,J.Member>:
  match values:
    case Nil{}: Nil{}
    case M.Test{name,values} <> rest: J.JMember{name,J.JArray{terms(values)}} <> tests(rest)
def condition_tape(+fuel:Nat,+values:List<&2,M.Condition>) -> List<&2,J.Value>:
  match fuel values:
    case 1n+p M.KeyValues{tests0} <> rest:
      J.JObject{[J.JMember{"kind",text("keys")},J.JMember{"tests",J.JObject{tests(tests0)}}]} <> condition_tape(p,rest)
    case 1n+p M.And{+children} <> rest:
      J.JObject{[J.JMember{"kind",text("and")},J.JMember{"count",J.JNumber{Nat.show(List.length(&2,M.Condition,children))}}]} <>
        condition_tape(p,List.append(&2,M.Condition,children,rest))
    case 1n+p M.Or{+children} <> rest:
      J.JObject{[J.JMember{"kind",text("or")},J.JMember{"count",J.JNumber{Nat.show(List.length(&2,M.Condition,children))}}]} <>
        condition_tape(p,List.append(&2,M.Condition,children,rest))
    case _ _: Nil{}
def condition(+value:M.Condition) -> J.Value:
  J.JObject{[J.JMember{"tokens",J.JArray{condition_tape(262144n,value <> Nil{})}}]}
def maybe_condition(+value:Maybe<&2,M.Condition>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{v}: condition(v)
def selectors(+values:List<&2,M.Selector>) -> List<&2,J.Member>:
  match values:
    case Nil{}: Nil{}
    case M.Selector{name,c} <> rest: J.JMember{name,choice(c)} <> selectors(rest)
def definition_variants(+found:Maybe<&2,List<&2,M.Selector>>) -> J.Value:
  match found:
    case None{}: J.JNull{}
    case Some{values}: J.JObject{selectors(values)}
def selector_names(values:List<&2,M.Selector>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case M.Selector{key,choice} <> rest: key <> selector_names(rest)
def definition_order(found:Maybe<&2,List<&2,M.Selector>>) -> J.Value:
  match found:
    case None{}: J.JNull{}
    case Some{values}: strings(selector_names(values))
def parts(+values:List<&2,M.Part>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.Part{c,v} <> rest: J.JObject{[J.JMember{"condition",maybe_condition(c)},J.JMember{"choice",choice(v)}]} <> parts(rest)
def definition_parts(+found:Maybe<&2,List<&2,M.Part>>) -> J.Value:
  match found:
    case None{}: J.JNull{}
    case Some{values}: J.JArray{parts(values)}
def definition(+value:M.Definition) -> J.Value:
  match value:
    case M.Definition{+v,p}: J.JObject{[J.JMember{"variants",definition_variants(v)},J.JMember{"selector_order",definition_order(v)},J.JMember{"multipart",definition_parts(p)}]}
def selected_parts(+values:List<&2,M.SelectedPart>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.SelectedPart{index,c} <> rest: J.JObject{[J.JMember{"index",number(index)},J.JMember{"choice",choice(c)}]} <> selected_parts(rest)
def root(+value:M.Root) -> J.Value:
  match value:
    case M.VariantRoot{c}: J.JObject{[J.JMember{"kind",text("variant")},J.JMember{"choice",choice(c)}]}
    case M.MultipartRoot{values,names}: J.JObject{[J.JMember{"kind",text("multipart")},J.JMember{"parts",J.JArray{selected_parts(values)}}]}
def state_output(+id:U32,+found:Maybe<&2,M.Root>) -> J.Value:
  match found:
    case None{}: J.JObject{[J.JMember{"id",number(id)},J.JMember{"mapped",J.JBool{False{}}}]}
    case Some{+value}: J.JObject{[J.JMember{"id",number(id)},J.JMember{"mapped",J.JBool{True{}}},
      J.JMember{"root",root(value)},J.JMember{"dependencies",strings(M.dependencies(value))}]}
def state_outputs(+values:List<&2,M.State>,+prepared:M.Prepared) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.State{+id,properties} <> rest: state_output(id,M.lookup(prepared,id)) <> state_outputs(rest,prepared)
def prepare_report(+result:Result<&2,&2,M.Error,M.Prepared>,+d:M.Definition,+states:List<&2,M.State>) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{+prepared}:
      match prepared:
        case M.Prepared{models,diagnostics}: J.JObject{[J.JMember{"status",text("ok")},J.JMember{"definition",definition(d)},
          J.JMember{"states",J.JArray{state_outputs(states,prepared)}},J.JMember{"diagnostics",errors(diagnostics)}]}
def definition_report(+result:Result<&2,&2,M.Error,M.Definition>,+schema:M.Schema,+states:List<&2,M.State>) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{+d}: prepare_report(M.instantiate(d,schema,states),d,states)
def string_list_values(+values:List<&2,J.Value>) -> Result<&2,&2,M.Error,List<&2,String>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,M.Error,List<&2,String>>:
        value:String <- M.strict_string(head,"harness")
        tail:List<&2,String> <- string_list_values(rest)
        Done{value <> tail}
def string_list(+value:J.Value) -> Result<&2,&2,M.Error,List<&2,String>>:
  match value:
    case J.JArray{values}: string_list_values(values)
    case _: M.fail(List<&2,String>,"HarnessStringList","harness","Expected string array")
def property(+value:J.Value) -> Result<&2,&2,M.Error,M.Property>:
  do Result<&2,&2,M.Error,M.Property>:
    +obj:J.Value <- M.object(value,"harness")
    list:J.Value <- M.required(M.member(obj,"values"),"harness")
    values:List<&2,String> <- string_list(list)
    flag:J.Value <- M.required(M.member(obj,"integer"),"harness")
    integer:Bool <- M.strict_boolean(flag,"harness")
    Done{M.Property{values,integer}}
def property_members(+values:List<&2,J.Member>,+out:Map<&2,M.Property>) -> Result<&2,&2,M.Error,Map<&2,M.Property>>:
  match values:
    case Nil{}: Done{out}
    case J.JMember{name,value} <> rest:
      do Result<&2,&2,M.Error,Map<&2,M.Property>>:
        p:M.Property <- property(value)
        property_members(rest,Map.set(&2,M.Property,out,name,p))
def properties(+value:J.Value) -> Result<&2,&2,M.Error,Map<&2,M.Property>>:
  match value:
    case J.JObject{values}: property_members(values,MTip{})
    case _: M.fail(Map<&2,M.Property>,"HarnessProperties","harness","Expected property object")
def schema(+value:J.Value) -> Result<&2,&2,M.Error,M.Schema>:
  do Result<&2,&2,M.Error,M.Schema>:
    +obj:J.Value <- M.object(value,"harness")
    v:J.Value <- M.required(M.member(obj,"owner"),"harness")
    owner:String <- M.strict_string(v,"harness")
    v:J.Value <- M.required(M.member(obj,"properties"),"harness")
    p:Map<&2,M.Property> <- properties(v)
    Done{M.Schema{owner,p}}
def string_members(+values:List<&2,J.Member>,+out:Map<&2,String>) -> Result<&2,&2,M.Error,Map<&2,String>>:
  match values:
    case Nil{}: Done{out}
    case J.JMember{name,value} <> rest:
      do Result<&2,&2,M.Error,Map<&2,String>>:
        s:String <- M.strict_string(value,"harness")
        string_members(rest,Map.set(&2,String,out,name,s))
def property_values(+value:J.Value) -> Result<&2,&2,M.Error,Map<&2,String>>:
  match value:
    case J.JObject{values}: string_members(values,MTip{})
    case _: M.fail(Map<&2,String>,"HarnessValues","harness","Expected property values object")
def state(+value:J.Value) -> Result<&2,&2,M.Error,M.State>:
  do Result<&2,&2,M.Error,M.State>:
    +obj:J.Value <- M.object(value,"harness")
    v:J.Value <- M.required(M.member(obj,"id"),"harness")
    id:U32 <- M.integer(v,"harness")
    v:J.Value <- M.required(M.member(obj,"properties"),"harness")
    p:Map<&2,String> <- property_values(v)
    Done{M.State{id,p}}
def state_values(+values:List<&2,J.Value>) -> Result<&2,&2,M.Error,List<&2,M.State>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,M.Error,List<&2,M.State>>:
        s:M.State <- state(head)
        tail:List<&2,M.State> <- state_values(rest)
        Done{s <> tail}
def states(+value:J.Value) -> Result<&2,&2,M.Error,List<&2,M.State>>:
  match value:
    case J.JArray{values}: state_values(values)
    case _: M.fail(List<&2,M.State>,"HarnessStates","harness","Expected states array")
def match_append(+id:J.Value,+tail:List<&2,J.Value>,+matched:Bool) -> List<&2,J.Value>:
  match matched:
    case True{}: id <> tail
    case False{}: tail
def matched_states(+values:List<&2,M.State>,+tests:Map<&2,String>) -> List<&2,J.Value>:
  match values:
    case Nil{}: Nil{}
    case M.State{id,properties} <> rest:
      match_append(number(id),matched_states(rest,tests),M.selector_matches(tests,properties))
def selector_report(+result:Result<&2,&2,M.Error,Map<&2,String>>,+states:List<&2,M.State>) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{tests}: J.JObject{[J.JMember{"status",text("ok")},J.JMember{"matches",J.JArray{matched_states(states,tests)}}]}
def condition_states(+values:List<&2,M.State>,+condition:M.Condition) -> Result<&2,&2,M.Error,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{Nil{}}
    case M.State{id,properties} <> rest:
      do Result<&2,&2,M.Error,List<&2,J.Value>>:
        matched:Bool <- M.bound_matches(condition,properties)
        tail:List<&2,J.Value> <- condition_states(rest,condition)
        Done{match_append(number(id),tail,matched)}
def condition_matches_report(+result:Result<&2,&2,M.Error,List<&2,J.Value>>,+parsed:M.Condition) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{values}: J.JObject{[J.JMember{"status",text("ok")},J.JMember{"parsed",condition(parsed)},J.JMember{"matches",J.JArray{values}}]}
def bound_report(+result:Result<&2,&2,M.Error,M.Condition>,+parsed:M.Condition,+states:List<&2,M.State>) -> J.Value:
  match result:
    case Fail{error}: J.JObject{[J.JMember{"status",text("error")},J.JMember{"error",error_value(error)},J.JMember{"parsed",condition(parsed)}]}
    case Done{bound}: condition_matches_report(condition_states(states,bound),parsed)
def condition_report(+result:Result<&2,&2,M.Error,M.Condition>,+schema:M.Schema,+states:List<&2,M.State>) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{+parsed}: bound_report(M.bind_condition(parsed,schema),parsed,states)
def choose_result(+result:Result<&2,&2,M.Error,M.Variant>) -> J.Value:
  match result:
    case Fail{error}: failed(error)
    case Done{v}: J.JObject{[J.JMember{"status",text("ok")},J.JMember{"variant",variant(v)}]}
def ticket_values(+values:List<&2,J.Value>,+choice:M.Choice) -> Result<&2,&2,M.Error,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,M.Error,List<&2,J.Value>>:
        n:U32 <- M.integer(head,"ticket")
        tail:List<&2,J.Value> <- ticket_values(rest,choice)
        Done{choose_result(M.choose(choice,n)) <> tail}
def tickets(+value:J.Value,+choice:M.Choice) -> Result<&2,&2,M.Error,J.Value>:
  match value:
    case J.JArray{values}:
      do Result<&2,&2,M.Error,J.Value>:
        values:List<&2,J.Value> <- ticket_values(values,choice)
        Done{J.JArray{values}}
    case _: M.fail(J.Value,"HarnessTickets","harness","Expected ticket array")
def selector_input(result:Result<&2,&2,M.Error,String>,schema:M.Schema,states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{selector_report(M.compile_selector(schema,value),states)}
def dispatcher_input(result:Result<&2,&2,M.Error,String>,schema:M.Schema,states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{definition_report(M.parse(value),schema,states)}
def condition_input(found:Maybe<&2,J.Value>,schema:M.Schema,states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match found:
    case None{}: M.fail(J.Value,"MissingField","harness","Required field is absent")
    case Some{value}: Done{condition_report(M.decode_condition(value),schema,states)}
def field_string(found:Maybe<&2,J.Value>) -> Result<&2,&2,M.Error,String>:
  match found:
    case None{}: M.fail(String,"MissingField","harness","Required field is absent")
    case Some{value}: M.strict_string(value,"harness")
def operation_dispatch(matched:Bool,name:String,obj:J.Value,schema:M.Schema,states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match matched:
    case True{}: dispatcher_input(field_string(M.member(obj,"text")),schema,states)
    case False{}: M.fail(J.Value,"HarnessMode","harness",name)
def operation_condition(matched:Bool,+name:String,+obj:J.Value,+schema:M.Schema,+states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match matched:
    case True{}: condition_input(M.member(obj,"condition"),schema,states)
    case False{}: operation_dispatch(String.eq(name,"dispatcher"),name,obj,schema,states)
def operation(matched:Bool,+name:String,+obj:J.Value,+schema:M.Schema,+states:List<&2,M.State>) -> Result<&2,&2,M.Error,J.Value>:
  match matched:
    case True{}: selector_input(field_string(M.member(obj,"selector")),schema,states)
    case False{}: operation_condition(String.eq(name,"condition"),name,obj,schema,states)
def parsed_states(result:Result<&2,&2,M.Error,List<&2,M.State>>,+name:String,obj:J.Value,schema:M.Schema) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: operation(String.eq(name,"selector"),name,obj,schema,values)
def states_field(found:Maybe<&2,J.Value>) -> Result<&2,&2,M.Error,List<&2,M.State>>:
  match found:
    case None{}: M.fail(List<&2,M.State>,"MissingField","harness","Required field is absent")
    case Some{value}: states(value)
def parsed_schema(result:Result<&2,&2,M.Error,M.Schema>,name:String,+obj:J.Value) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: parsed_states(states_field(M.member(obj,"states")),name,obj,value)
def schema_field(found:Maybe<&2,J.Value>) -> Result<&2,&2,M.Error,M.Schema>:
  match found:
    case None{}: M.fail(M.Schema,"MissingField","harness","Required field is absent")
    case Some{value}: schema(value)
def choice_tickets(result:Result<&2,&2,M.Error,J.Value>,selected:M.Choice) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{J.JObject{[J.JMember{"status",text("ok")},J.JMember{"choice",choice(selected)},J.JMember{"tickets",values}]}}
def tickets_field(found:Maybe<&2,J.Value>,selected:M.Choice) -> Result<&2,&2,M.Error,J.Value>:
  match found:
    case None{}: M.fail(J.Value,"MissingField","harness","Required field is absent")
    case Some{value}: tickets(value,selected)
def parsed_choice(result:Result<&2,&2,M.Error,M.Choice>,obj:J.Value) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+selected}: choice_tickets(tickets_field(M.member(obj,"tickets"),selected),selected)
def choice_field(found:Maybe<&2,J.Value>) -> Result<&2,&2,M.Error,M.Choice>:
  match found:
    case None{}: M.fail(M.Choice,"MissingField","harness","Required field is absent")
    case Some{value}: M.choice(value,"choice")
def mode(matched:Bool,name:String,+obj:J.Value) -> Result<&2,&2,M.Error,J.Value>:
  match matched:
    case True{}: parsed_choice(choice_field(M.member(obj,"value")),obj)
    case False{}: parsed_schema(schema_field(M.member(obj,"schema")),name,obj)
def input_mode(result:Result<&2,&2,M.Error,String>,obj:J.Value) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+name}: mode(String.eq(name,"choice"),name,obj)
def input_object(result:Result<&2,&2,M.Error,J.Value>) -> Result<&2,&2,M.Error,J.Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+obj}: input_mode(field_string(M.member(obj,"mode")),obj)
def input(value:J.Value) -> Result<&2,&2,M.Error,J.Value>:
  input_object(M.object(value,"harness"))
def result_report(+result:Result<&2,&2,M.Error,J.Value>) -> String:
  match result:
    case Fail{error}: J.encode(failed(error))
    case Done{value}: J.encode(value)
def input_report(+result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{error}: J.encode(failed(M.Error{"HarnessJson","harness",error}))
    case Done{value}: result_report(input(value))
def batch(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(input_report(R.parse(head)))
        batch(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args:List<String> <- IO.args()
    batch(List.tail(&1,String,args))
