import Base
import ./json.bend as J
import ./resource_json.bend as R

# Resource data and explicit state dispatch. No IO, baking, or RNG ownership.
type Error is Data:
  Error{code:String,path:String,detail:String}
type Variant is Data:
  Variant{model:String,x:U32,y:U32,z:U32,uvlock:Bool}
type Weighted is Data:
  Weighted{variant:Variant,weight:U32}
type Choice is Data:
  Single{variant:Variant}
  WeightedChoice{entries:List<&2,Weighted>,total:U32}
type Term is Data:
  Term{value:String,negated:Bool}
type Test is Data:
  Test{property:String,terms:List<&2,Term>}
type Condition is Data:
  KeyValues{tests:List<&2,Test>}
  And{conditions:List<&2,Condition>}
  Or{conditions:List<&2,Condition>}
type Selector is Data:
  Selector{key:String,choice:Choice}
type Part is Data:
  Part{condition:Maybe<&2,Condition>,choice:Choice}
type Definition is Data:
  Definition{variants:Maybe<&2,List<&2,Selector>>,multipart:Maybe<&2,List<&2,Part>>}

# Names are canonical property values; integer properties additionally admit
# supported Java integer text spellings when compiling selectors/conditions.
type Property is Data:
  Property{values:List<&2,String>,integer:Bool}
type Schema is Data:
  Schema{owner:String,properties:Map<&2,Property>}
type State is Data:
  State{id:U32,properties:Map<&2,String>}
type SelectedPart is Data:
  SelectedPart{index:U32,choice:Choice}
type Candidate is Data:
  Candidate{selector:String,choice:Choice}
type Candidates is Data:
  Candidates{variants:List<&2,Candidate>,parts:List<&2,SelectedPart>,diagnostics:List<&2,Error>}
type Root is Data:
  VariantRoot{choice:Choice}
  MultipartRoot{parts:List<&2,SelectedPart>,dependencies:List<&2,String>}
type Prepared is Data:
  Prepared{models:Map<&2,Root>,diagnostics:List<&2,Error>}

type NumberParts is Data:
  NumberParts{digits:List<&2,U32>,fraction:U32,exponent:U32,exponent_negative:Bool,negative:Bool}
type IdentifierParts is Data:
  IdentifierParts{namespace:String,path:String}
type Split is Data:
  Split{before:String,after:Maybe<&2,String>}
type ConditionTask is Data:
  DecodeNode{value:J.Value,path:String}
  BindNode{value:Condition,schema:Schema}
  FinishNode{count:Nat,all:Bool}
type ConditionWork is Data:
  ConditionWork{tasks:List<&2,ConditionTask>,stack:List<&2,Condition>}
type EvaluateTask is Data:
  Evaluate{value:Condition}
  Reduce{count:Nat,all:Bool}
type EvaluateWork is Data:
  EvaluateWork{tasks:List<&2,EvaluateTask>,stack:List<&2,Bool>}
type SelectorWalk is Data:
  SelectorWalk{states:List<&2,State>,models:Map<&2,Root>,errors:List<&2,Error>,stopped:Bool}
def choose_value(-A:Data,+yes:A,+no:A,+test:Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no
def fail(-A:Data,+code:String,+path:String,+detail:String) -> Result<&2,&2,Error,A>:
  Fail{Error{code,path,detail}}
def map_value(-A:Data,pair:Map<&2,A> & A) -> A:
  (map,value)=pair
  value
def map_present(-A:Data,pair:Map<&2,A> & Bool) -> Bool:
  (map,present)=pair
  present
def find_member(+values:List<&2,J.Member>,+key:String) -> Maybe<&2,J.Value>:
  match values:
    case Nil{}: None{}
    case J.JMember{+name,value} <> rest:
      choose_value(Maybe<&2,J.Value>,Some{value},find_member(rest,key),String.eq(name,key))
def member(+value:J.Value,+key:String) -> Maybe<&2,J.Value>:
  match value:
    case J.JObject{values}: find_member(values,key)
    case _: None{}
# JsonOps field lookup treats JsonNull as absent; map entries still retain it.
def non_null(+value:Maybe<&2,J.Value>) -> Maybe<&2,J.Value>:
  match value:
    case Some{J.JNull{}}: None{}
    case other: other
def field(+value:J.Value,+key:String) -> Maybe<&2,J.Value>:
  non_null(member(value,key))
def required(+value:Maybe<&2,J.Value>,+path:String) -> Result<&2,&2,Error,J.Value>:
  match value:
    case None{}: fail(J.Value,"MissingField",path,"Required field is absent")
    case Some{v}: Done{v}
def object(+value:J.Value,+path:String) -> Result<&2,&2,Error,J.Value>:
  match value:
    case J.JObject{members}: Done{J.JObject{members}}
    case _: fail(J.Value,"ExpectedObject",path,"Expected JSON object")
def strict_string(+value:J.Value,+path:String) -> Result<&2,&2,Error,String>:
  match value:
    case J.JString{s}: Done{s}
    case _: fail(String,"ExpectedString",path,"Expected JSON string")
def strict_boolean(+value:J.Value,+path:String) -> Result<&2,&2,Error,Bool>:
  match value:
    case J.JBool{b}: Done{b}
    case _: fail(Bool,"ExpectedBoolean",path,"Expected JSON boolean")
def signed_show(+word:U32) -> String:
  choose_value(String,"-" ++ U32.show(U32.sub(0,word)),U32.show(word),U32.is_ge(word,2147483648))

def scan_number(+text:String,+stage:U32,+digits:List<&2,U32>,+fraction:U32,+exponent:U32,+eneg:Bool,+negative:Bool,+path:String)
  -> Result<&2,&2,Error,NumberParts>:
  match text:
    case SNil{}: Done{NumberParts{List.reverse(&2,U32,digits),fraction,exponent,eneg,negative}}
    case SCon{Chr{+c},+rest}:
      match c:
        case 45: scan_number(rest,stage,digits,fraction,exponent,
          choose_value(Bool,True{},eneg,U32.is_ge(stage,2)),choose_value(Bool,negative,True{},U32.is_ge(stage,2)),path)
        case 43: scan_number(rest,stage,digits,fraction,exponent,eneg,negative,path)
        case 46: scan_number(rest,1,digits,fraction,exponent,eneg,negative,path)
        case 101: scan_number(rest,2,digits,fraction,exponent,eneg,negative,path)
        case 69: scan_number(rest,2,digits,fraction,exponent,eneg,negative,path)
        case _:
          match stage:
            case 0: scan_number(rest,stage,U32.sub(c,48) <> digits,fraction,exponent,eneg,negative,path)
            case 1: scan_number(rest,stage,U32.sub(c,48) <> digits,U32.add(fraction,1),exponent,eneg,negative,path)
            case _:
              do Result<&2,&2,Error,NumberParts>:
                next:U32 <- choose_value(Result<&2,&2,Error,U32>,Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
                  fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),
                  U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000))
                scan_number(rest,stage,digits,fraction,next,eneg,negative,path)
def digit_word(+fuel:Nat,+digits:List<&2,U32>,+acc:U32) -> U32:
  match fuel digits:
    case 1n+p h <> rest: digit_word(p,rest,U32.add(U32.mul(acc,10),h))
    case _ _: acc
def shift_decimal(+fuel:Nat,+word:U32) -> U32:
  match fuel:
    case 0n: word
    case 1n+p: shift_decimal(p,U32.mul(word,10))
def shifted(+digits:List<&2,U32>,+shift:U32,+small:Bool) -> U32:
  match small:
    case False{}: 0
    case True{}: shift_decimal(U32.to_nat(shift),digit_word(List.length(&2,U32,digits),digits,0))
def number_magnitude(+digits:List<&2,U32>,+fraction:U32,+exponent:U32,+eneg:Bool,+positive_shift:Bool) -> U32:
  match positive_shift:
    case True{}: shifted(digits,U32.sub(exponent,fraction),U32.is_lt(U32.sub(exponent,fraction),32))
    case False{}:
      drop=choose_value(U32,U32.add(exponent,fraction),U32.sub(fraction,exponent),eneg)
      digit_word(Nat.sub(List.length(&2,U32,digits),U32.to_nat(drop)),digits,0)
def number_word(+parts:NumberParts) -> U32:
  match parts:
    case NumberParts{digits,+fraction,+exponent,+eneg,negative}:
      +word=number_magnitude(digits,fraction,exponent,eneg,Bool.not(eneg) && U32.is_ge(exponent,fraction))
      choose_value(U32,U32.sub(0,word),word,negative)
def number_checked(+result:Result<&2,&2,String,J.Value>,+raw:String,+path:String) -> Result<&2,&2,Error,U32>:
  match result:
    case Done{J.JNumber{lexeme}}:
      do Result<&2,&2,Error,U32>:
        valid:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"InvalidNumber",path,"Invalid raw number lexeme"),String.eq(raw,lexeme))
        parts:NumberParts <- scan_number(raw,0,Nil{},0,0,False{},False{},path)
        Done{number_word(parts)}
    case _: fail(U32,"InvalidNumber",path,"Invalid raw number lexeme")
def integer(+value:J.Value,+path:String) -> Result<&2,&2,Error,U32>:
  match value:
    case J.JNumber{+raw}: number_checked(R.parse(raw),raw,path)
    case _: fail(U32,"ExpectedNumber",path,"Expected JSON number")
def optional_integer(+found:Maybe<&2,J.Value>,+fallback:U32,+path:String) -> Result<&2,&2,Error,U32>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: integer(v,path)
def optional_boolean(+found:Maybe<&2,J.Value>,+fallback:Bool,+path:String) -> Result<&2,&2,Error,Bool>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: strict_boolean(v,path)
def quarter(+word:U32,+path:String) -> Result<&2,&2,Error,U32>:
  +magnitude=choose_value(U32,U32.sub(0,word),word,U32.is_ge(word,2147483648))
  +rem=U32.mod(magnitude,360)
  +degrees=choose_value(U32,U32.mod(U32.sub(360,rem),360),rem,U32.is_ge(word,2147483648))
  choose_value(Result<&2,&2,Error,U32>,Done{degrees},fail(U32,"InvalidRotation",path,signed_show(word)),
    U32.is_eq(U32.mod(degrees,90),0))

def identifier_parts(+text:String,+reversed:String) -> IdentifierParts:
  match text:
    case SNil{}: IdentifierParts{"minecraft",String.reverse(reversed)}
    case SCon{Chr{58},rest}: IdentifierParts{String.reverse(reversed),rest}
    case SCon{head,rest}: identifier_parts(rest,SCon{head,reversed})
def identifier_characters(+text:String,+path:Bool) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c},rest}:
      ((U32.is_ge(c,97) && U32.is_le(c,122)) || (U32.is_ge(c,48) && U32.is_le(c,57)) ||
        U32.is_eq(c,95) || U32.is_eq(c,45) || U32.is_eq(c,46) || (path && U32.is_eq(c,47))) &&
        identifier_characters(rest,path)
def identifier_join(+parts:IdentifierParts,+path:String) -> Result<&2,&2,Error,String>:
  match parts:
    case IdentifierParts{+ns,+name}:
      +namespace=choose_value(String,"minecraft",ns,String.eq(ns,""))
      choose_value(Result<&2,&2,Error,String>,Done{namespace ++ ":" ++ name},fail(String,"InvalidIdentifier",path,namespace ++ ":" ++ name),
        identifier_characters(namespace,False{}) && identifier_characters(name,True{}))
def variant(+value:J.Value,+path:String) -> Result<&2,&2,Error,Variant>:
  do Result<&2,&2,Error,Variant>:
    +obj:J.Value <- object(value,path)
    input:J.Value <- required(field(obj,"model"),path ++ ".model")
    model_text:String <- strict_string(input,path ++ ".model")
    model:String <- identifier_join(identifier_parts(model_text,""),path ++ ".model")
    x:U32 <- optional_integer(field(obj,"x"),0,path ++ ".x")
    x:U32 <- quarter(x,path ++ ".x")
    y:U32 <- optional_integer(field(obj,"y"),0,path ++ ".y")
    y:U32 <- quarter(y,path ++ ".y")
    z:U32 <- optional_integer(field(obj,"z"),0,path ++ ".z")
    z:U32 <- quarter(z,path ++ ".z")
    lock:Bool <- optional_boolean(field(obj,"uvlock"),False{},path ++ ".uvlock")
    Done{Variant{model,x,y,z,lock}}
def weighted_entries(+values:List<&2,J.Value>,+index:U32,+path:String) -> Result<&2,&2,Error,List<&2,Weighted>>:
  match values:
    case Nil{}: Done{Nil{}}
    case +head <> rest:
      do Result<&2,&2,Error,List<&2,Weighted>>:
        v:Variant <- variant(head,path ++ "[" ++ U32.show(index) ++ "]")
        +weight:U32 <- optional_integer(field(head,"weight"),1,path ++ "[" ++ U32.show(index) ++ "].weight")
        positive:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"NonPositiveWeight",path,signed_show(weight)),U32.is_gt(weight,0) && U32.is_le(weight,2147483647))
        tail:List<&2,Weighted> <- weighted_entries(rest,U32.add(index,1),path)
        Done{Weighted{v,weight} <> tail}
def weight_total(+values:List<&2,Weighted>,+total:U32,+path:String) -> Result<&2,&2,Error,U32>:
  match values:
    case Nil{}: Done{total}
    case Weighted{variant,+weight} <> rest:
      do Result<&2,&2,Error,U32>:
        positive:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"NonPositiveWeight",path,signed_show(weight)),U32.is_gt(weight,0) && U32.is_le(weight,2147483647))
        next:U32 <- choose_value(Result<&2,&2,Error,U32>,Done{U32.add(total,weight)},
          fail(U32,"WeightSumOverflow",path,"Sum of weights exceeds 2147483647"),U32.is_le(weight,U32.sub(2147483647,total)))
        weight_total(rest,next,path)
def choice(+value:J.Value,+path:String) -> Result<&2,&2,Error,Choice>:
  match value:
    case J.JArray{Nil{}}: fail(Choice,"EmptyWeightedList",path,"Weighted list must have contents")
    case J.JArray{values}:
      do Result<&2,&2,Error,Choice>:
        +entries:List<&2,Weighted> <- weighted_entries(values,0,path)
        total:U32 <- weight_total(entries,0,path)
        Done{WeightedChoice{entries,total}}
    case other:
      do Result<&2,&2,Error,Choice>:
        v:Variant <- variant(other,path)
        Done{Single{v}}

def split_first(+text:String,+separator:U32,+reversed:String) -> Split:
  match text:
    case SNil{}: Split{String.reverse(reversed),None{}}
    case SCon{Chr{+c},+rest}:
      choose_value(Split,Split{String.reverse(reversed),Some{rest}},
        split_first(rest,separator,SCon{Chr{c},reversed}),U32.is_eq(c,separator))
def split_parts(+fuel:Nat,+value:Split,+separator:U32) -> List<&2,String>:
  match fuel value:
    case _ Split{head,None{}}: head <> Nil{}
    case 0n Split{head,Some{rest}}: head <> rest <> Nil{}
    case 1n+p Split{head,Some{rest}}: head <> split_parts(p,split_first(rest,separator,""),separator)
def split(+text:String,+separator:U32) -> List<&2,String>:
  split_parts(Nat.add(1n,String.length(text)),split_first(text,separator,""),separator)
def term_text(+text:String,+path:String) -> Result<&2,&2,Error,Term>:
  match text:
    case SCon{Chr{33},+rest}:
      choose_value(Result<&2,&2,Error,Term>,fail(Term,"EmptyTerm",path,"Empty term"),Done{Term{rest,True{}}},String.eq(rest,""))
    case +other:
      choose_value(Result<&2,&2,Error,Term>,fail(Term,"EmptyTerm",path,"Empty term"),Done{Term{other,False{}}},String.eq(other,""))
def term_list(+values:List<&2,String>,+path:String) -> Result<&2,&2,Error,List<&2,Term>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,Error,List<&2,Term>>:
        t:Term <- term_text(head,path)
        tail:List<&2,Term> <- term_list(rest,path)
        Done{t <> tail}
def condition_text(+value:J.Value,+path:String) -> Result<&2,&2,Error,String>:
  match value:
    case J.JString{text}: Done{text}
    case J.JBool{True{}}: Done{"true"}
    case J.JBool{False{}}: Done{"false"}
    case other:
      do Result<&2,&2,Error,String>:
        word:U32 <- integer(other,path)
        Done{signed_show(word)}
def condition_members(+values:List<&2,J.Member>,+path:String) -> Result<&2,&2,Error,List<&2,Test>>:
  match values:
    case Nil{}: Done{Nil{}}
    case J.JMember{+name,value} <> rest:
      do Result<&2,&2,Error,List<&2,Test>>:
        text:String <- condition_text(value,path ++ "." ++ name)
        terms:List<&2,Term> <- term_list(split(text,124),path ++ "." ++ name)
        tail:List<&2,Test> <- condition_members(rest,path)
        Done{Test{name,terms} <> tail}
def condition_fallback(+values:List<&2,J.Member>,+path:String) -> Result<&2,&2,Error,Condition>:
  do Result<&2,&2,Error,Condition>:
    tests:List<&2,Test> <- condition_members(values,path)
    Done{KeyValues{tests}}
def decode_tasks(+values:List<&2,J.Value>,+path:String,+tail:List<&2,ConditionTask>) -> List<&2,ConditionTask>:
  match values:
    case Nil{}: tail
    case head <> rest: DecodeNode{head,path} <> decode_tasks(rest,path,tail)
def bind_tasks(+values:List<&2,Condition>,+schema:Schema,+tail:List<&2,ConditionTask>) -> List<&2,ConditionTask>:
  match values:
    case Nil{}: tail
    case head <> rest: BindNode{head,schema} <> bind_tasks(rest,schema,tail)
def pop_conditions(+count:Nat,+stack:List<&2,Condition>,+out:List<&2,Condition>) -> List<&2,Condition> & List<&2,Condition>:
  match count stack:
    case 1n+p head <> rest: pop_conditions(p,rest,head <> out)
    case _ _: (out,stack)
def decoded_leaf(+result:Result<&2,&2,Error,Condition>,+tasks:List<&2,ConditionTask>,+stack:List<&2,Condition>)
  -> Result<&2,&2,Error,ConditionWork>:
  match result:
    case Fail{error}: Fail{error}
    case Done{condition}: Done{ConditionWork{tasks,condition <> stack}}
def decode_node(+value:J.Value,+path:String,+tasks:List<&2,ConditionTask>,+stack:List<&2,Condition>)
  -> Result<&2,&2,Error,ConditionWork>:
  match value:
    case J.JObject{Nil{}}: fail(ConditionWork,"EmptyCondition",path,"Condition map must have contents")
    case J.JObject{J.JMember{"AND",J.JArray{+values}} <> Nil{}}:
      Done{ConditionWork{decode_tasks(values,path ++ ".AND",FinishNode{List.length(&2,J.Value,values),True{}} <> tasks),stack}}
    case J.JObject{J.JMember{"OR",J.JArray{+values}} <> Nil{}}:
      Done{ConditionWork{decode_tasks(values,path ++ ".OR",FinishNode{List.length(&2,J.Value,values),False{}} <> tasks),stack}}
    case J.JObject{members}: decoded_leaf(condition_fallback(members,path),tasks,stack)
    case _: fail(ConditionWork,"ExpectedConditionObject",path,"Condition must be an object")
def contains(+values:List<&2,String>,+text:String) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: String.eq(head,text) || contains(rest,text)
def canonical_integer(+values:List<&2,String>,+found:Maybe<&2,U32>) -> Maybe<&2,String>:
  match found:
    case None{}: None{}
    case Some{word}:
      +text=signed_show(word)
      choose_value(Maybe<&2,String>,Some{text},None{},contains(values,text))
def digit_zeros() -> List<&2,U32>:
  48 <> 1632 <> 1776 <> 1984 <> 2406 <> 2534 <> 2662 <> 2790 <> 2918 <> 3046 <>
    3174 <> 3302 <> 3430 <> 3558 <> 3664 <> 3792 <> 3872 <> 4160 <> 4240 <> 6112 <>
    6160 <> 6470 <> 6608 <> 6784 <> 6800 <> 6992 <> 7088 <> 7232 <> 7248 <> 42528 <>
    43216 <> 43264 <> 43472 <> 43504 <> 43600 <> 44016 <> 65296 <> Nil{}
def property_digit(+word:U32,+negative:Bool,+found:Maybe<&2,U32>) -> Maybe<&2,U32>:
  match found:
    case None{}: None{}
    case Some{+digit}:
      choose_value(Maybe<&2,U32>,Some{U32.add(U32.mul(word,10),digit)},None{},U32.is_lt(word,214748364) ||
        (U32.is_eq(word,214748364) && U32.is_le(digit,choose_value(U32,8,7,negative))))
def unicode_digit(+zeros:List<&2,U32>,+c:U32) -> Maybe<&2,U32>:
  match zeros:
    case Nil{}: None{}
    case +zero <> rest:
      choose_value(Maybe<&2,U32>,Some{U32.sub(c,zero)},unicode_digit(rest,c),U32.is_ge(c,zero) && U32.is_lt(c,U32.add(zero,10)))
def property_scan(+text:String,+word:U32,+negative:Bool,+digits:Bool) -> Maybe<&2,U32>:
  match text:
    case SNil{}:
      choose_value(Maybe<&2,U32>,Some{choose_value(U32,U32.sub(0,word),word,negative)},None{},digits)
    case SCon{Chr{c},rest}:
      do Maybe<&2,U32>:
        next:U32 <- property_digit(word,negative,unicode_digit(digit_zeros(),c))
        property_scan(rest,next,negative,True{})
def property_integer(+text:String) -> Maybe<&2,U32>:
  match text:
    case SCon{Chr{45},rest}: property_scan(rest,0,True{},False{})
    case SCon{Chr{43},rest}: property_scan(rest,0,False{},False{})
    case other: property_scan(other,0,False{},False{})
def canonical(+property:Property,+text:String) -> Maybe<&2,String>:
  match property:
    case Property{values,True{}}: canonical_integer(values,property_integer(text))
    case Property{values,False{}}: choose_value(Maybe<&2,String>,Some{text},None{},contains(values,text))
def term_bound(+name:String,+text:String,+negated:Bool,+owner:String,+found:Maybe<&2,String>) -> Result<&2,&2,Error,Term>:
  match found:
    case Some{value}: Done{Term{value,negated}}
    case None{}: fail(Term,"ConditionUnknownValue",name,"Unknown value '" ++ text ++ "' for property '" ++ name ++ "' on '" ++ owner ++ "'")
def term_value(+property:Property,+name:String,+text:String,+negated:Bool,+owner:String) -> Result<&2,&2,Error,Term>:
  term_bound(name,text,negated,owner,canonical(property,text))
def bind_terms(+values:List<&2,Term>,+property:Property,+name:String,+owner:String) -> Result<&2,&2,Error,List<&2,Term>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Term{text,negated} <> rest:
      do Result<&2,&2,Error,List<&2,Term>>:
        value:Term <- term_value(property,name,text,negated,owner)
        tail:List<&2,Term> <- bind_terms(rest,property,name,owner)
        Done{value <> tail}
def bind_test_found(+name:String,+terms:List<&2,Term>,+owner:String,+found:Maybe<&2,Property>) -> Result<&2,&2,Error,Test>:
  match found:
    case None{}: fail(Test,"ConditionUnknownProperty",name,"Unknown property '" ++ name ++ "' on '" ++ owner ++ "'")
    case Some{property}:
      do Result<&2,&2,Error,Test>:
        terms:List<&2,Term> <- bind_terms(terms,property,name,owner)
        Done{Test{name,terms}}
def schema_property(+schema:Schema,+key:String) -> Maybe<&2,Property>:
  match schema:
    case Schema{owner,+properties}:
      choose_value(Maybe<&2,Property>,Some{map_value(Property,Map.get(Property,Property{Nil{},False{}},properties,key))},
        None{},map_present(Property,Map.has(&2,Property,properties,key)))
def bind_test(+value:Test,+schema:Schema) -> Result<&2,&2,Error,Test>:
  match value schema:
    case Test{+name,terms} Schema{+owner,+properties}:
      bind_test_found(name,terms,owner,schema_property(Schema{owner,properties},name))
def bind_tests(+values:List<&2,Test>,+schema:Schema) -> Result<&2,&2,Error,List<&2,Test>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,Error,List<&2,Test>>:
        value:Test <- bind_test(head,schema)
        tail:List<&2,Test> <- bind_tests(rest,schema)
        Done{value <> tail}
def bound_node(+value:Condition,+schema:Schema,+tasks:List<&2,ConditionTask>,+stack:List<&2,Condition>)
  -> Result<&2,&2,Error,ConditionWork>:
  match value:
    case KeyValues{tests}:
      do Result<&2,&2,Error,ConditionWork>:
        tests:List<&2,Test> <- bind_tests(tests,schema)
        Done{ConditionWork{tasks,KeyValues{tests} <> stack}}
    case And{+values}: Done{ConditionWork{bind_tasks(values,schema,FinishNode{List.length(&2,Condition,values),True{}} <> tasks),stack}}
    case Or{+values}: Done{ConditionWork{bind_tasks(values,schema,FinishNode{List.length(&2,Condition,values),False{}} <> tasks),stack}}
def condition_finished(pair:List<&2,Condition> & List<&2,Condition>,+tasks:List<&2,ConditionTask>,+all:Bool)
  -> Result<&2,&2,Error,ConditionWork>:
  (+children,rest)=pair
  Done{ConditionWork{tasks,choose_value(Condition,And{children},Or{children},all) <> rest}}
def condition_step(+task:ConditionTask,+tasks:List<&2,ConditionTask>,+stack:List<&2,Condition>)
  -> Result<&2,&2,Error,ConditionWork>:
  match task:
    case DecodeNode{value,path}: decode_node(value,path,tasks,stack)
    case BindNode{value,schema}: bound_node(value,schema,tasks,stack)
    case FinishNode{count,all}: condition_finished(pop_conditions(count,stack,Nil{}),tasks,all)
def condition_walk(+fuel:Nat,+work:ConditionWork) -> Result<&2,&2,Error,Condition>:
  match fuel work:
    case _ ConditionWork{Nil{},head <> Nil{}}: Done{head}
    case 0n _: fail(Condition,"ConditionWorkLimit","condition","At most 262144 work steps")
    case 1n+p ConditionWork{task <> tasks,stack}:
      do Result<&2,&2,Error,Condition>:
        next:ConditionWork <- condition_step(task,tasks,stack)
        condition_walk(p,next)
    case _ _: fail(Condition,"InvalidConditionWork","condition","Invalid condition stack")
def decode_condition_at(+value:J.Value,+path:String) -> Result<&2,&2,Error,Condition>:
  condition_walk(262144n,ConditionWork{DecodeNode{value,path} <> Nil{},Nil{}})
def decode_condition(+value:J.Value) -> Result<&2,&2,Error,Condition>:
  decode_condition_at(value,"condition")
def optional_condition(+found:Maybe<&2,J.Value>,+path:String) -> Result<&2,&2,Error,Maybe<&2,Condition>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2,&2,Error,Maybe<&2,Condition>>:
        c:Condition <- decode_condition_at(v,path)
        Done{Some{c}}
def part(+value:J.Value,+path:String) -> Result<&2,&2,Error,Part>:
  do Result<&2,&2,Error,Part>:
    +obj:J.Value <- object(value,path)
    c:Maybe<&2,Condition> <- optional_condition(field(obj,"when"),path ++ ".when")
    input:J.Value <- required(field(obj,"apply"),path ++ ".apply")
    model:Choice <- choice(input,path ++ ".apply")
    Done{Part{c,model}}
def parts(+values:List<&2,J.Value>,+index:U32,+path:String) -> Result<&2,&2,Error,List<&2,Part>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,Error,List<&2,Part>>:
        p:Part <- part(head,path ++ "[" ++ U32.show(index) ++ "]")
        tail:List<&2,Part> <- parts(rest,U32.add(index,1),path)
        Done{p <> tail}
def selectors(+values:List<&2,J.Member>) -> Result<&2,&2,Error,List<&2,Selector>>:
  match values:
    case Nil{}: Done{Nil{}}
    case J.JMember{+name,value} <> rest:
      do Result<&2,&2,Error,List<&2,Selector>>:
        model:Choice <- choice(value,"variants." ++ name)
        tail:List<&2,Selector> <- selectors(rest)
        Done{Selector{name,model} <> tail}
def optional_variants(+found:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Maybe<&2,List<&2,Selector>>>:
  match found:
    case None{}: Done{None{}}
    case Some{J.JObject{Nil{}}}: fail(Maybe<&2,List<&2,Selector>>,"EmptyVariants","variants","Variant map must have contents")
    case Some{J.JObject{members}}:
      do Result<&2,&2,Error,Maybe<&2,List<&2,Selector>>>:
        values:List<&2,Selector> <- selectors(members)
        Done{Some{values}}
    case _: fail(Maybe<&2,List<&2,Selector>>,"ExpectedVariantsObject","variants","Expected variant object")
def optional_parts(+found:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Maybe<&2,List<&2,Part>>>:
  match found:
    case None{}: Done{None{}}
    case Some{J.JArray{Nil{}}}: fail(Maybe<&2,List<&2,Part>>,"EmptyMultipart","multipart","Multipart list must have contents")
    case Some{J.JArray{values}}:
      do Result<&2,&2,Error,Maybe<&2,List<&2,Part>>>:
        result:List<&2,Part> <- parts(values,0,"multipart")
        Done{Some{result}}
    case _: fail(Maybe<&2,List<&2,Part>>,"ExpectedMultipartArray","multipart","Expected multipart array")
def decode(+value:J.Value) -> Result<&2,&2,Error,Definition>:
  do Result<&2,&2,Error,Definition>:
    +obj:J.Value <- object(value,"blockstate")
    +vs:Maybe<&2,List<&2,Selector>> <- optional_variants(field(obj,"variants"))
    +ps:Maybe<&2,List<&2,Part>> <- optional_parts(field(obj,"multipart"))
    present:Unit <- choose_value(Result<&2,&2,Error,Unit>,
      fail(Unit,"MissingDefinition","blockstate","Neither variants nor multipart found"),Done{Unit{}},
      Maybe.is_none(&2,List<&2,Selector>,vs) && Maybe.is_none(&2,List<&2,Part>,ps))
    Done{Definition{vs,ps}}
def decoded_text(+result:Result<&2,&2,String,J.Value>) -> Result<&2,&2,Error,Definition>:
  match result:
    case Fail{message}: fail(Definition,"ResourceJson","text",message)
    case Done{v}: decode(v)
def parse(+text:String) -> Result<&2,&2,Error,Definition>:
  decoded_text(R.parse(text))
def parse_with(+text:String,+limits:J.Limits) -> Result<&2,&2,Error,Definition>:
  decoded_text(R.parse_with(text,limits))

def comma_values(+values:List<&2,String>) -> String:
  match values:
    case Nil{}: ""
    case head <> Nil{}: head
    case head <> rest: head ++ ", " ++ comma_values(rest)
def selector_value(+property:Property,+name:String,+raw:String,+found:Maybe<&2,String>) -> Result<&2,&2,Error,String>:
  match property found:
    case _ Some{text}: Done{text}
    case Property{values,integer} None{}:
      fail(String,"SelectorUnknownValue",name,"Unknown value: '" ++ raw ++ "' for blockstate property: '" ++ name ++
        "' [" ++ comma_values(values) ++ "]")
def selector_property(+name:String,+raw:String,+out:Map<&2,String>,+found:Maybe<&2,Property>) -> Result<&2,&2,Error,Map<&2,String>>:
  match found:
    case None{}: fail(Map<&2,String>,"SelectorUnknownProperty",name,"Unknown blockstate property: '" ++ name ++ "'")
    case Some{+property}:
      do Result<&2,&2,Error,Map<&2,String>>:
        value:String <- selector_value(property,name,raw,canonical(property,raw))
        Done{Map.set(&2,String,out,name,value)}
def selector_pair(+pair:Split,+schema:Schema,+out:Map<&2,String>) -> Result<&2,&2,Error,Map<&2,String>>:
  match pair:
    case Split{"",after}: Done{out}
    case Split{+name,None{}}: fail(Map<&2,String>,"SelectorUnknownProperty",name,"Unknown blockstate property: '" ++ name ++ "'")
    case Split{+name,Some{+raw}}:
      selector_property(name,raw,out,schema_property(schema,name))
def selector_tests(+values:List<&2,String>,+schema:Schema,+out:Map<&2,String>) -> Result<&2,&2,Error,Map<&2,String>>:
  match values:
    case Nil{}: Done{out}
    case head <> rest:
      do Result<&2,&2,Error,Map<&2,String>>:
        next:Map<&2,String> <- selector_pair(split_first(head,61,""),schema,out)
        selector_tests(rest,schema,next)
def compile_selector(+schema:Schema,+text:String) -> Result<&2,&2,Error,Map<&2,String>>:
  selector_tests(split(text,44),schema,MTip{})
def test_keys(+keys:List<&2,String>,+tests:Map<&2,String>,+properties:Map<&2,String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case +name <> rest:
      map_present(String,Map.has(&2,String,properties,name)) &&
        String.eq(map_value(String,Map.get(String,"",tests,name)),map_value(String,Map.get(String,"",properties,name))) &&
        test_keys(rest,tests,properties)
def selector_matches(+tests:Map<&2,String>,+properties:Map<&2,String>) -> Bool:
  test_keys(Map.keys(&2,String,tests),tests,properties)
def match_selector(+schema:Schema,+text:String,+properties:Map<&2,String>) -> Result<&2,&2,Error,Bool>:
  do Result<&2,&2,Error,Bool>:
    tests:Map<&2,String> <- compile_selector(schema,text)
    Done{selector_matches(tests,properties)}

def bind_condition(+value:Condition,+schema:Schema) -> Result<&2,&2,Error,Condition>:
  condition_walk(262144n,ConditionWork{BindNode{value,schema} <> Nil{},Nil{}})
def terms_match(+values:List<&2,Term>,+text:String) -> Bool:
  match values:
    case Nil{}: False{}
    case Term{value,negated} <> rest:
      Bool.xor(String.eq(value,text),negated) || terms_match(rest,text)
def keyvalues_match(+values:List<&2,Test>,+properties:Map<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Test{+name,terms} <> rest:
      map_present(String,Map.has(&2,String,properties,name)) &&
        terms_match(terms,map_value(String,Map.get(String,"",properties,name))) && keyvalues_match(rest,properties)
def evaluate_tasks(+values:List<&2,Condition>,+tail:List<&2,EvaluateTask>) -> List<&2,EvaluateTask>:
  match values:
    case Nil{}: tail
    case head <> rest: Evaluate{head} <> evaluate_tasks(rest,tail)
def pop_bools(+count:Nat,+stack:List<&2,Bool>,+all:Bool,+acc:Bool) -> Bool & List<&2,Bool>:
  match count stack:
    case 1n+p +head <> rest: pop_bools(p,rest,all,choose_value(Bool,head && acc,head || acc,all))
    case _ _: (acc,stack)
def evaluate_finished(pair:Bool & List<&2,Bool>,+tasks:List<&2,EvaluateTask>) -> EvaluateWork:
  (value,rest)=pair
  EvaluateWork{tasks,value <> rest}
def evaluate_step(+task:EvaluateTask,+tasks:List<&2,EvaluateTask>,+stack:List<&2,Bool>,+properties:Map<&2,String>) -> EvaluateWork:
  match task:
    case Evaluate{KeyValues{tests}}: EvaluateWork{tasks,keyvalues_match(tests,properties) <> stack}
    case Evaluate{And{+values}}: EvaluateWork{evaluate_tasks(values,Reduce{List.length(&2,Condition,values),True{}} <> tasks),stack}
    case Evaluate{Or{+values}}: EvaluateWork{evaluate_tasks(values,Reduce{List.length(&2,Condition,values),False{}} <> tasks),stack}
    case Reduce{count,+all}: evaluate_finished(pop_bools(count,stack,all,all),tasks)
def evaluate_walk(+fuel:Nat,+work:EvaluateWork,+properties:Map<&2,String>) -> Result<&2,&2,Error,Bool>:
  match fuel work:
    case _ EvaluateWork{Nil{},head <> Nil{}}: Done{head}
    case 1n+p EvaluateWork{task <> tasks,stack}: evaluate_walk(p,evaluate_step(task,tasks,stack,properties),properties)
    case 0n _: fail(Bool,"ConditionWorkLimit","condition","At most 262144 work steps")
    case _ _: fail(Bool,"InvalidConditionWork","condition","Invalid evaluation stack")
def bound_matches(+value:Condition,+properties:Map<&2,String>) -> Result<&2,&2,Error,Bool>:
  evaluate_walk(262144n,EvaluateWork{Evaluate{value} <> Nil{},Nil{}},properties)
def matches(+value:Condition,+schema:Schema,+properties:Map<&2,String>) -> Result<&2,&2,Error,Bool>:
  do Result<&2,&2,Error,Bool>:
    bound:Condition <- bind_condition(value,schema)
    bound_matches(bound,properties)

def choose_entry(+values:List<&2,Weighted>,+ticket:U32) -> Result<&2,&2,Error,Variant>:
  match values:
    case Nil{}: fail(Variant,"InvalidWeightedChoice","choice","Weights do not cover ticket")
    case Weighted{variant,+weight} <> rest:
      choose_value(Result<&2,&2,Error,Variant>,Done{variant},choose_entry(rest,U32.sub(ticket,weight)),U32.is_lt(ticket,weight))
def choose(+choice:Choice,+ticket:U32) -> Result<&2,&2,Error,Variant>:
  match choice:
    case Single{variant}: Done{variant}
    case WeightedChoice{+entries,+total}:
      do Result<&2,&2,Error,Variant>:
        actual:U32 <- weight_total(entries,0,"choice")
        checked:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"InvalidWeightedChoice","choice","Invalid weights or total"),U32.is_eq(actual,total) && U32.is_gt(total,0))
        inside:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"TicketOutOfRange","ticket",U32.show(ticket)),U32.is_lt(ticket,total))
        choose_entry(entries,ticket)

def bind_part(+value:Part,+schema:Schema) -> Result<&2,&2,Error,Part>:
  match value:
    case Part{None{},choice}: Done{Part{None{},choice}}
    case Part{Some{condition},choice}:
      do Result<&2,&2,Error,Part>:
        c:Condition <- bind_condition(condition,schema)
        Done{Part{Some{c},choice}}
def bind_parts(+values:List<&2,Part>,+schema:Schema) -> Result<&2,&2,Error,List<&2,Part>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> rest:
      do Result<&2,&2,Error,List<&2,Part>>:
        p:Part <- bind_part(head,schema)
        tail:List<&2,Part> <- bind_parts(rest,schema)
        Done{p <> tail}
def bound_part_matches(+found:Maybe<&2,Condition>,+properties:Map<&2,String>) -> Result<&2,&2,Error,Bool>:
  match found:
    case None{}: Done{True{}}
    case Some{condition}: bound_matches(condition,properties)
def selected_part_tail(+choice:Choice,+index:U32,+tail:List<&2,SelectedPart>,+matched:Bool) -> List<&2,SelectedPart>:
  match matched:
    case False{}: tail
    case True{}: SelectedPart{index,choice} <> tail
def selected_parts(+values:List<&2,Part>,+index:U32,+properties:Map<&2,String>) -> Result<&2,&2,Error,List<&2,SelectedPart>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Part{condition,choice} <> rest:
      do Result<&2,&2,Error,List<&2,SelectedPart>>:
        matched:Bool <- bound_part_matches(condition,properties)
        tail:List<&2,SelectedPart> <- selected_parts(rest,U32.add(index,1),properties)
        Done{selected_part_tail(choice,index,tail,matched)}
def candidate_record(+result:Result<&2,&2,Error,Map<&2,String>>,+key:String,+choice:Choice,
  +properties:Map<&2,String>,+tail:Candidates) -> Candidates:
  match result tail:
    case Fail{error} Candidates{variants,parts,errors}: Candidates{variants,parts,error <> errors}
    case Done{tests} Candidates{+variants,parts,errors}:
      Candidates{choose_value(List<&2,Candidate>,Candidate{key,choice} <> variants,variants,selector_matches(tests,properties)),parts,errors}
def candidate_selectors(+values:List<&2,Selector>,+schema:Schema,+properties:Map<&2,String>,+parts:List<&2,SelectedPart>) -> Candidates:
  match values:
    case Nil{}: Candidates{Nil{},parts,Nil{}}
    case Selector{+key,choice} <> rest:
      candidate_record(compile_selector(schema,key),key,choice,properties,candidate_selectors(rest,schema,properties,parts))
def optional_selector_values(+found:Maybe<&2,List<&2,Selector>>) -> List<&2,Selector>:
  match found:
    case None{}: Nil{}
    case Some{values}: values
def optional_part_values(+found:Maybe<&2,List<&2,Part>>) -> List<&2,Part>:
  match found:
    case None{}: Nil{}
    case Some{values}: values
def candidates(+definition:Definition,+schema:Schema,+properties:Map<&2,String>) -> Result<&2,&2,Error,Candidates>:
  match definition:
    case Definition{vs,ps}:
      do Result<&2,&2,Error,Candidates>:
        parts:List<&2,Part> <- bind_parts(optional_part_values(ps),schema)
        selected:List<&2,SelectedPart> <- selected_parts(parts,0,properties)
        Done{candidate_selectors(optional_selector_values(vs),schema,properties,selected)}

def state_value(+found:Maybe<&2,Property>,+name:String,+text:String) -> Result<&2,&2,Error,Unit>:
  match found:
    case None{}: fail(Unit,"StateUnknownProperty",name,text)
    case Some{Property{values,integer}}:
      choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},fail(Unit,"StateNonCanonicalValue",name,text),contains(values,text))
def validate_state_keys(+keys:List<&2,String>,+schema:Schema,+properties:Map<&2,String>) -> Result<&2,&2,Error,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +name <> rest:
      do Result<&2,&2,Error,Unit>:
        valid:Unit <- state_value(schema_property(schema,name),name,map_value(String,Map.get(String,"",properties,name)))
        validate_state_keys(rest,schema,properties)
def validate_state(+value:State,+schema:Schema) -> Result<&2,&2,Error,Unit>:
  match value schema:
    case State{id,+values} Schema{+owner,+properties}:
      do Result<&2,&2,Error,Unit>:
        complete:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"IncompleteState",U32.show(id),owner),
          Nat.is_eq(List.length(&2,String,Map.keys(&2,String,values)),List.length(&2,String,Map.keys(&2,Property,properties))))
        validate_state_keys(Map.keys(&2,String,values),Schema{owner,properties},values)
def validate_states(+values:List<&2,State>,+schema:Schema,+seen:Map<&2,Unit>) -> Result<&2,&2,Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      match head:
        case State{+id,properties}:
          do Result<&2,&2,Error,Unit>:
            unique:Unit <- choose_value(Result<&2,&2,Error,Unit>,fail(Unit,"DuplicateStateId",U32.show(id),"Duplicate ordered state"),
              Done{Unit{}},map_present(Unit,Map.has(&2,Unit,seen,U32.show(id))))
            valid:Unit <- validate_state(head,schema)
            validate_states(rest,schema,Map.set(&2,Unit,seen,U32.show(id),Unit{}))
def validate_domain(+values:List<&2,String>,+integer:Bool,+seen:Map<&2,Unit>,+name:String) -> Result<&2,&2,Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +text <> rest:
      do Result<&2,&2,Error,Unit>:
        unique:Unit <- choose_value(Result<&2,&2,Error,Unit>,fail(Unit,"DuplicatePropertyValue",name,text),Done{Unit{}},
          map_present(Unit,Map.has(&2,Unit,seen,text)))
        canonical_value:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},fail(Unit,"NonCanonicalDomainValue",name,text),
          Bool.not(integer) || Bool.not(Maybe.is_none(&2,String,canonical(Property{text <> Nil{},True{}},text))))
        validate_domain(rest,integer,Map.set(&2,Unit,seen,text,Unit{}),name)
def validate_property(+value:Property,+name:String) -> Result<&2,&2,Error,Unit>:
  match value:
    case Property{+values,integer}:
      do Result<&2,&2,Error,Unit>:
        nonempty:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},fail(Unit,"EmptyPropertyDomain",name,"No values"),
          Nat.is_gt(List.length(&2,String,values),0n))
        validate_domain(values,integer,MTip{},name)
def validate_properties(+keys:List<&2,String>,+properties:Map<&2,Property>) -> Result<&2,&2,Error,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +name <> rest:
      do Result<&2,&2,Error,Unit>:
        valid:Unit <- validate_property(map_value(Property,Map.get(Property,Property{Nil{},False{}},properties,name)),name)
        validate_properties(rest,properties)
def validate_schema(+schema:Schema) -> Result<&2,&2,Error,Unit>:
  match schema:
    case Schema{owner,+properties}: validate_properties(Map.keys(&2,Property,properties),properties)

# Overlap changes the first conflicting state's root before aborting this
# selector's remaining ordered states, matching the measured Java insertion.
def insert_matched(+id:U32,+choice:Choice,+states:List<&2,State>,+models:Map<&2,Root>,
  +errors:List<&2,Error>,+key:String,+previous:Bool) -> SelectorWalk:
  match previous:
    case True{}: SelectorWalk{states,Map.set(&2,Root,models,U32.show(id),VariantRoot{choice}),Error{"OverlappingSelector",key,U32.show(id)} <> errors,True{}}
    case False{}: SelectorWalk{states,Map.set(&2,Root,models,U32.show(id),VariantRoot{choice}),errors,False{}}
def apply_state(+id:U32,+choice:Choice,+states:List<&2,State>,+models:Map<&2,Root>,
  +errors:List<&2,Error>,+key:String,+matched:Bool) -> SelectorWalk:
  match matched:
    case False{}: SelectorWalk{states,models,errors,False{}}
    case True{}: insert_matched(id,choice,states,models,errors,key,map_present(Root,Map.has(&2,Root,models,U32.show(id))))
def selector_walk(+fuel:Nat,+work:SelectorWalk,+tests:Map<&2,String>,+key:String,+choice:Choice) -> Prepared:
  match fuel work:
    case _ SelectorWalk{Nil{},models,errors,stopped}: Prepared{models,errors}
    case _ SelectorWalk{states,models,errors,True{}}: Prepared{models,errors}
    case 1n+p SelectorWalk{State{id,properties} <> rest,models,errors,False{}}:
      selector_walk(p,apply_state(id,choice,rest,models,errors,key,selector_matches(tests,properties)),tests,key,choice)
    case _ SelectorWalk{states,models,errors,stopped}: Prepared{models,Error{"StateWorkLimit","states","Invalid state work bound"} <> errors}
def apply_states(+values:List<&2,State>,+tests:Map<&2,String>,+models:Map<&2,Root>,+errors:List<&2,Error>,+key:String,+choice:Choice) -> Prepared:
  selector_walk(List.length(&2,State,values),SelectorWalk{values,models,errors,False{}},tests,key,choice)
def apply_compiled(+result:Result<&2,&2,Error,Map<&2,String>>,+choice:Choice,+key:String,+states:List<&2,State>,+prepared:Prepared) -> Prepared:
  match result prepared:
    case Fail{error} Prepared{models,errors}: Prepared{models,error <> errors}
    case Done{tests} Prepared{models,errors}: apply_states(states,tests,models,errors,key,choice)
def instantiate_selectors(+values:List<&2,Selector>,+schema:Schema,+states:List<&2,State>,+prepared:Prepared) -> Prepared:
  match values:
    case Nil{}: prepared
    case Selector{+key,choice} <> rest:
      instantiate_selectors(rest,schema,states,apply_compiled(compile_selector(schema,key),choice,key,states,prepared))
def weighted_dependencies(+values:List<&2,Weighted>,+out:Map<&2,Unit>) -> Map<&2,Unit>:
  match values:
    case Nil{}: out
    case Weighted{Variant{name,x,y,z,lock},weight} <> rest: weighted_dependencies(rest,Map.set(&2,Unit,out,name,Unit{}))
def choice_dependencies(+value:Choice,+out:Map<&2,Unit>) -> Map<&2,Unit>:
  match value:
    case Single{Variant{name,x,y,z,lock}}: Map.set(&2,Unit,out,name,Unit{})
    case WeightedChoice{entries,total}: weighted_dependencies(entries,out)
def part_dependencies(+values:List<&2,Part>,+out:Map<&2,Unit>) -> Map<&2,Unit>:
  match values:
    case Nil{}: out
    case Part{condition,choice} <> rest: part_dependencies(rest,choice_dependencies(choice,out))
def add_multipart_state(+id:U32,+properties:Map<&2,String>,+parts:List<&2,Part>,+dependencies:List<&2,String>,+models:Map<&2,Root>,+present:Bool)
  -> Result<&2,&2,Error,Map<&2,Root>>:
  match present:
    case True{}: Done{models}
    case False{}:
      do Result<&2,&2,Error,Map<&2,Root>>:
        selected:List<&2,SelectedPart> <- selected_parts(parts,0,properties)
        Done{Map.set(&2,Root,models,U32.show(id),MultipartRoot{selected,dependencies})}
def multipart_states(+values:List<&2,State>,+parts:List<&2,Part>,+dependencies:List<&2,String>,+models:Map<&2,Root>) -> Result<&2,&2,Error,Map<&2,Root>>:
  match values:
    case Nil{}: Done{models}
    case State{+id,properties} <> rest:
      do Result<&2,&2,Error,Map<&2,Root>>:
        next:Map<&2,Root> <- add_multipart_state(id,properties,parts,dependencies,models,map_present(Root,Map.has(&2,Root,models,U32.show(id))))
        multipart_states(rest,parts,dependencies,next)
def instantiate_parts(+found:Maybe<&2,List<&2,Part>>,+schema:Schema,+states:List<&2,State>,+prepared:Prepared) -> Result<&2,&2,Error,Prepared>:
  match found prepared:
    case None{} Prepared{models,errors}: Done{Prepared{models,List.reverse(&2,Error,errors)}}
    case Some{values} Prepared{models,errors}:
      do Result<&2,&2,Error,Prepared>:
        +parts:List<&2,Part> <- bind_parts(values,schema)
        models:Map<&2,Root> <- multipart_states(states,parts,Map.keys(&2,Unit,part_dependencies(parts,MTip{})),models)
        Done{Prepared{models,List.reverse(&2,Error,errors)}}
def instantiate(+definition:Definition,+schema:Schema,+states:List<&2,State>) -> Result<&2,&2,Error,Prepared>:
  match definition:
    case Definition{vs,ps}:
      do Result<&2,&2,Error,Prepared>:
        size:Unit <- choose_value(Result<&2,&2,Error,Unit>,Done{Unit{}},
          fail(Unit,"StateLimit","states","At most 65535 ordered states"),Nat.is_le(List.length(&2,State,states),65535n))
        valid_schema:Unit <- validate_schema(schema)
        valid_states:Unit <- validate_states(states,schema,MTip{})
        instantiate_parts(ps,schema,states,instantiate_selectors(optional_selector_values(vs),schema,states,Prepared{MTip{},Nil{}}))
def empty_root() -> Root:
  VariantRoot{Single{Variant{"",0,0,0,False{}}}}
def lookup(+prepared:Prepared,+id:U32) -> Maybe<&2,Root>:
  match prepared:
    case Prepared{+models,errors}:
      choose_value(Maybe<&2,Root>,Some{map_value(Root,Map.get(Root,empty_root(),models,U32.show(id)))},None{},
        map_present(Root,Map.has(&2,Root,models,U32.show(id))))
def dependencies(+root:Root) -> List<&2,String>:
  match root:
    case VariantRoot{choice}: Map.keys(&2,Unit,choice_dependencies(choice,MTip{}))
    case MultipartRoot{parts,names}: names
