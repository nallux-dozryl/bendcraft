import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./cooking_recipe.bend as K
import ./cooking_recipe_number.bend as N
import ./furnace_authority.bend as A
import ./furnace_authority_fuel.bend as F

def request(+recipes:List<&2,K.Recipe>,+wanted:String,+uses:U32) -> Result<&2,&2,String,Maybe<&2,A.XpRequest>>:
  match recipes:
    case Nil{}: Done{None{}}
    case K.Cooking{+id,kind,ingredient,output,time,xp} <> rest:
      R.choose(Result<&2,&2,String,Maybe<&2,A.XpRequest>>,Done{Some{A.XpRequest{id,uses,xp}}},request(rest,wanted,uses),String.eq(id,wanted))
    case K.Unsupported{+id,kind} <> rest:
      R.choose(Result<&2,&2,String,Maybe<&2,A.XpRequest>>,Fail{"current recipesUsed key has a non-cooking subclass"},request(rest,wanted,uses),String.eq(id,wanted))
def append(+value:Maybe<&2,A.XpRequest>,+rest:List<&2,A.XpRequest>) -> List<&2,A.XpRequest>:
  match value:
    case None{}: rest
    case Some{head}: head <> rest
def requests(+values:List<&2,A.Use>,+recipes:List<&2,K.Recipe>) -> Result<&2,&2,String,List<&2,A.XpRequest>>:
  match values:
    case Nil{}: Done{[]}
    case A.Use{id,count} <> rest:
      do Result<&2,&2,String,List<&2,A.XpRequest>>:
        head : Maybe<&2,A.XpRequest> <- request(recipes,id,count)
        tail : List<&2,A.XpRequest> <- requests(rest,recipes)
        return append(head,tail)
# Keyed accounting projection: current registry rates, deleted-key skip, actual
# non-cooking cast failure. It never claims JVM identity-hash traversal order.
def pop(+catalog:K.Catalog,+frame:A.Frame) -> Result<&2,&2,String,List<&2,A.XpRequest>>:
  K.Catalog{recipes,tags,items} = catalog
  A.Frame{kind,r,t,s,c,speed,cached,uses} = frame
  requests(uses,recipes)
def found(+values:List<&2,A.XpRequest>,+wanted:String) -> Maybe<&2,A.XpRequest>:
  match values:
    case Nil{}: None{}
    case +head <> rest:
      A.XpRequest{id,count,xp} = head
      R.choose(Maybe<&2,A.XpRequest>,Some{head},found(rest,wanted),String.eq(id,wanted))
def require(+value:Maybe<&2,A.XpRequest>) -> Result<&2,&2,String,A.XpRequest>:
  match value:
    case None{}: Fail{"unknown XP traversal key"}
    case Some{request}: Done{request}
def ordered(+values:List<&2,A.XpRequest>,+names:List<&2,String>,+seen:List<&2,String>) -> Result<&2,&2,String,List<&2,A.XpRequest>>:
  match names:
    case Nil{}:
      do Result<&2,&2,String,List<&2,A.XpRequest>>:
        D.guard(Nat.is_eq(List.length(&2,String,seen),List.length(&2,A.XpRequest,values)),"XP traversal does not cover every current recipe")
        return []
    case +name <> rest:
      do Result<&2,&2,String,List<&2,A.XpRequest>>:
        D.guard(Bool.not(F.contains(seen,name)),"duplicate XP traversal key")
        value : A.XpRequest <- require(found(values,name))
        tail : List<&2,A.XpRequest> <- ordered(values,rest,name <> seen)
        return value <> tail
def clear(+frame:A.Frame) -> A.Frame:
  A.use_table(frame,[])
def clear_state(state:A.State) -> A.State:
  A.State{inventory,frame} = state
  A.State{inventory,clear(frame)}
def award(value:A.XpRequest,ticket:F32) -> U32:
  A.XpRequest{id,count,rate} = value
  N.experience(count,rate,ticket)
def advances_rng(value:A.XpRequest) -> Bool:
  A.XpRequest{id,count,rate} = value
  F32.is_ne(N.fraction(count,rate),0.0)
