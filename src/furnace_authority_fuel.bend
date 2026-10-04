import Base
import ./inventory.bend as Inv
import ./json.bend as J
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./cooking_recipe_decoder.bend as KD

# Resource expressions, not a product fuel list. Unknown subclasses retain
# their complete input and refuse evaluation rather than becoming zero fuel.
type Predicate is Data:
  AnyBlock{}
  Blocks{ids:List<&2,String>}
  BlockTag{id:String}
  PredicateRef{id:String}
  OtherPredicate{source:J.Value}

type IntExpr is Data:
  IntConstant{bits:U32}
  IntRef{id:String}
  IntDiv{left:IntExpr,right:IntExpr}
  IntConditional{condition:Predicate,yes:IntExpr,no:IntExpr}
  OtherInt{source:J.Value}

type FloatExpr is Data:
  FloatConstant{value:F32}
  FloatRef{id:String}
  FloatConditional{condition:Predicate,yes:FloatExpr,no:FloatExpr}
  OtherFloat{source:J.Value}

type IntDefinition is Data:
  IntDefinition{id:String,value:IntExpr}
type FloatDefinition is Data:
  FloatDefinition{id:String,value:FloatExpr}
type PredicateDefinition is Data:
  PredicateDefinition{id:String,value:Predicate}
type BlockTagDefinition is Data:
  BlockTagDefinition{id:String,items:List<&2,String>}
type CookingFuel is Data:
  CookingFuel{time:IntExpr,speed:FloatExpr}
type FuelProfile is Data:
  FuelProfile{key:Inv.ItemKey,fuel:Maybe<&2,CookingFuel>,metadata:Inv.ItemMetadata}
type ItemFuel is Data:
  ItemFuel{id:String,fuel:Maybe<&2,CookingFuel>}
type Catalog is Data:
  Catalog{ints:List<&2,IntDefinition>,floats:List<&2,FloatDefinition>,predicates:List<&2,PredicateDefinition>,tags:List<&2,BlockTagDefinition>,items:List<&2,ItemFuel>,defaults:List<&2,C.Default>}
type Context is Data:
  Context{block:String,max_depth:Nat}
type Values is Data:
  Values{burn_time:U32,speed:F32}

def catalog_ints(+catalog:Catalog) -> List<&2,IntDefinition>:
  Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  ints
def catalog_floats(+catalog:Catalog) -> List<&2,FloatDefinition>:
  Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  floats
def catalog_predicates(+catalog:Catalog) -> List<&2,PredicateDefinition>:
  Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  predicates
def catalog_tags(+catalog:Catalog) -> List<&2,BlockTagDefinition>:
  Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  tags
def catalog_items(+catalog:Catalog) -> List<&2,ItemFuel>:
  Catalog{ints,floats,predicates,tags,items,defaults} = catalog
  items

def int_find(+values:List<&2,IntDefinition>,+wanted:String) -> Maybe<&2,IntExpr>:
  match values:
    case Nil{}: None{}
    case IntDefinition{id,value} <> rest: R.choose(Maybe<&2,IntExpr>,Some{value},int_find(rest,wanted),String.eq(id,wanted))
def float_find(+values:List<&2,FloatDefinition>,+wanted:String) -> Maybe<&2,FloatExpr>:
  match values:
    case Nil{}: None{}
    case FloatDefinition{id,value} <> rest: R.choose(Maybe<&2,FloatExpr>,Some{value},float_find(rest,wanted),String.eq(id,wanted))
def predicate_find(+values:List<&2,PredicateDefinition>,+wanted:String) -> Maybe<&2,Predicate>:
  match values:
    case Nil{}: None{}
    case PredicateDefinition{id,value} <> rest: R.choose(Maybe<&2,Predicate>,Some{value},predicate_find(rest,wanted),String.eq(id,wanted))
def contains(+values:List<&2,String>,+wanted:String) -> Bool:
  match values:
    case Nil{}: False{}
    case id <> rest: String.eq(id,wanted) || contains(rest,wanted)
def tag_contains(+values:List<&2,BlockTagDefinition>,+wanted:String,+block:String) -> Bool:
  match values:
    case Nil{}: False{}
    case BlockTagDefinition{id,members} <> rest: R.choose(Bool,contains(members,block),tag_contains(rest,wanted,block),String.eq(id,wanted))
def predicate_found(+value:Maybe<&2,Predicate>) -> Result<&2,&2,String,Predicate>:
  match value:
    case None{}: Fail{"unresolved nested fuel predicate"}
    case Some{expression}: Done{expression}
def predicate_eval(+depth:Nat,+catalog:Catalog,+block:String,+value:Predicate) -> Result<&2,&2,String,Bool>:
  match depth value:
    case 0n _: Fail{"fuel provider depth exhausted or cyclic"}
    case 1n+rest AnyBlock{}: Done{True{}}
    case 1n+rest Blocks{ids}: Done{contains(ids,block)}
    case 1n+rest BlockTag{id}:
      Done{tag_contains(catalog_tags(catalog),id,block)}
    case 1n+rest PredicateRef{id}:
      do Result<&2,&2,String,Bool>:
        expression : Predicate <- predicate_found(predicate_find(catalog_predicates(catalog),id))
        predicate_eval(rest,catalog,block,expression)
    case 1n+rest OtherPredicate{source}: Fail{"fuel predicate subclass or block-state profile unsupported"}

def negative(+bits:U32) -> Bool:
  U32.is_ge(bits,2147483648)
def magnitude(+bits:U32) -> U32:
  R.choose(U32,U32.sub(0,bits),bits,negative(bits))
def division_nonzero(+a:U32,+b:U32) -> U32:
  +quotient = U32.div(magnitude(a),magnitude(b))
  R.choose(U32,U32.sub(0,quotient),quotient,U32.is_ne(U32.and(a,2147483648),U32.and(b,2147483648)))
# Java idiv truncates toward zero; MIN_VALUE/-1 wraps to MIN_VALUE.
def division_checked(+a:U32,+b:U32,+zero:Bool) -> Maybe<&2,U32>:
  match zero:
    case True{}: None{}
    case False{}: Some{division_nonzero(a,b)}
def division(+a:U32,+b:U32) -> Maybe<&2,U32>:
  division_checked(a,b,U32.is_zero(b))
def divided(+a:Maybe<&2,U32>,+b:Maybe<&2,U32>) -> Maybe<&2,U32>:
  match a b:
    case Some{left} Some{right}: division(left,right)
    case _ _: None{}
def int_found(+value:Maybe<&2,IntExpr>) -> Result<&2,&2,String,IntExpr>:
  match value:
    case None{}: Fail{"unresolved nested integer fuel provider"}
    case Some{expression}: Done{expression}
def int_eval(+depth:Nat,+catalog:Catalog,+block:String,+value:IntExpr) -> Result<&2,&2,String,Maybe<&2,U32>>:
  match depth value:
    case 0n _: Fail{"fuel provider depth exhausted or cyclic"}
    case 1n+rest IntConstant{bits}: Done{Some{bits}}
    case 1n+ +rest IntRef{id}:
      do Result<&2,&2,String,Maybe<&2,U32>>:
        expression : IntExpr <- int_found(int_find(catalog_ints(catalog),id))
        int_eval(rest,catalog,block,expression)
    case 1n+ +rest IntDiv{left,right}:
      do Result<&2,&2,String,Maybe<&2,U32>>:
        a : Maybe<&2,U32> <- int_eval(rest,catalog,block,left)
        b : Maybe<&2,U32> <- int_eval(rest,catalog,block,right)
        return divided(a,b)
    case 1n+ +rest IntConditional{condition,yes,no}:
      do Result<&2,&2,String,Maybe<&2,U32>>:
        test : Bool <- predicate_eval(rest,catalog,block,condition)
        int_eval(rest,catalog,block,R.choose(IntExpr,yes,no,test))
    case 1n+rest OtherInt{source}: Fail{"integer fuel provider subclass unsupported"}
def float_found(+value:Maybe<&2,FloatExpr>) -> Result<&2,&2,String,FloatExpr>:
  match value:
    case None{}: Fail{"unresolved nested float fuel provider"}
    case Some{expression}: Done{expression}
def float_eval(+depth:Nat,+catalog:Catalog,+block:String,+value:FloatExpr) -> Result<&2,&2,String,F32>:
  match depth value:
    case 0n _: Fail{"fuel provider depth exhausted or cyclic"}
    case 1n+rest FloatConstant{value}: Done{value}
    case 1n+rest FloatRef{id}:
      do Result<&2,&2,String,F32>:
        expression : FloatExpr <- float_found(float_find(catalog_floats(catalog),id))
        float_eval(rest,catalog,block,expression)
    case 1n+ +rest FloatConditional{condition,yes,no}:
      do Result<&2,&2,String,F32>:
        test : Bool <- predicate_eval(rest,catalog,block,condition)
        float_eval(rest,catalog,block,R.choose(FloatExpr,yes,no,test))
    case 1n+rest OtherFloat{source}: Fail{"float fuel provider subclass unsupported"}
def int_safe(+value:Maybe<&2,U32>) -> U32:
  match value:
    case None{}: 0
    case Some{number}: number
def float_safe(+value:F32) -> F32:
  R.choose(F32,value,0.0,U32.is_ne(U32.and(F32.bits(value),2139095040),2139095040))
def root_int_found(+catalog:Catalog,+context:Context,+value:Maybe<&2,IntExpr>) -> Result<&2,&2,String,U32>:
  Context{block,depth} = context
  match value:
    case None{}: Done{0}
    case Some{expression}:
      do Result<&2,&2,String,U32>:
        result : Maybe<&2,U32> <- int_eval(depth,catalog,block,expression)
        return int_safe(result)
def root_int(+catalog:Catalog,+context:Context,+value:IntExpr) -> Result<&2,&2,String,U32>:
  match value:
    case IntRef{id}: root_int_found(catalog,context,int_find(catalog_ints(catalog),id))
    case IntConstant{bits}: Done{bits}
    case _: Fail{"cooking fuel requires resolvable integer constant or key"}
def root_float_found(+catalog:Catalog,+context:Context,+value:Maybe<&2,FloatExpr>) -> Result<&2,&2,String,F32>:
  Context{block,depth} = context
  match value:
    case None{}: Done{1.0}
    case Some{expression}:
      do Result<&2,&2,String,F32>:
        result : F32 <- float_eval(depth,catalog,block,expression)
        return float_safe(result)
def root_float(+catalog:Catalog,+context:Context,+value:FloatExpr) -> Result<&2,&2,String,F32>:
  match value:
    case FloatRef{id}: root_float_found(catalog,context,float_find(catalog_floats(catalog),id))
    case FloatConstant{value}: Done{value}
    case _: Fail{"cooking fuel requires resolvable float constant or key"}
def values(+catalog:Catalog,+context:Context,+fuel:Maybe<&2,CookingFuel>) -> Result<&2,&2,String,Values>:
  match fuel:
    case None{}: Done{Values{0,1.0}}
    case Some{CookingFuel{time,speed}}:
      do Result<&2,&2,String,Values>:
        ticks : U32 <- root_int(catalog,context,time)
        multiplier : F32 <- root_float(catalog,context,speed)
        return Values{ticks,multiplier}
def default_fuel(+items:List<&2,ItemFuel>,+wanted:String) -> Maybe<&2,CookingFuel>:
  match items:
    case Nil{}: None{}
    case ItemFuel{id,fuel} <> rest: R.choose(Maybe<&2,CookingFuel>,fuel,default_fuel(rest,wanted),String.eq(id,wanted))
def profile_fuel(+values:List<&2,FuelProfile>,+wanted:Inv.ItemKey) -> Result<&2,&2,String,Maybe<&2,CookingFuel>>:
  match values:
    case Nil{}: Fail{"modified fuel requires admitted exact component profile"}
    case FuelProfile{key,fuel,metadata} <> rest: R.choose(Result<&2,&2,String,Maybe<&2,CookingFuel>>,Done{fuel},profile_fuel(rest,wanted),Inv.key_equal(key,wanted))
def fuel_key(+catalog:Catalog,+profiles:List<&2,FuelProfile>,+key:Inv.ItemKey,+plain:Bool) -> Result<&2,&2,String,Maybe<&2,CookingFuel>>:
  Inv.ItemKey{id,components} = key
  match plain:
    case True{}: Done{default_fuel(catalog_items(catalog),id)}
    case False{}: profile_fuel(profiles,key)
def fuel_for(+catalog:Catalog,+profiles:List<&2,FuelProfile>,+slot:Inv.Slot) -> Result<&2,&2,String,Maybe<&2,CookingFuel>>:
  match slot:
    case Inv.InvEmpty{}: Done{None{}}
    case Inv.InvStack{Inv.ItemKey{+id,+components},count}: fuel_key(catalog,profiles,Inv.ItemKey{id,components},String.eq(components,""))
