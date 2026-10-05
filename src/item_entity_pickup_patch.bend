import Base
import ./json.bend as J
import ./inventory.bend as I
import ./cooking_block_entity_codec_components.bend as C

# The shared reconstruction selects between two recursive tails. Construct the
# one tail once here; all comparison, removal and exact admission semantics stay
# those of the existing component authority.
def addition(unchanged:Bool,head:J.Member,tail:List<&2,J.Member>) -> List<&2,J.Member>:
  match unchanged:
    case True{}: tail
    case False{}: head <> tail
def additions(values:List<&2,J.Member>,+defaults:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case +head <> rest:
      J.JMember{id,+value} = head
      addition(C.unchanged(value,J.member(defaults,id)),head,additions(rest,defaults))
def removal(present:Bool,id:String,tail:List<&2,J.Member>) -> List<&2,J.Member>:
  match present:
    case True{}: tail
    case False{}: J.JMember{"!" ++ id,J.JObject{[]}} <> tail
def removals(values:List<&2,J.Member>,+effective:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case J.JMember{+id,value} <> rest:
      removal(Maybe.is_some(&2,J.Value,J.member(effective,id)),id,removals(rest,effective))
def diff(+defaults:J.Value,+effective:J.Value) -> Result<&2,&2,String,J.Value>:
  match defaults effective:
    case J.JObject{original} J.JObject{actual}: Done{J.JObject{List.append(&2,J.Member,additions(actual,defaults),removals(original,effective))}}
    case _ _: Fail{"component patch reconstruction requires initialized and effective object maps"}
def kind(+defaults:J.Value,+key:I.ItemKey,plain:Bool) -> Result<&2,&2,String,J.Value>:
  I.ItemKey{id,identity} = key
  match plain:
    case True{}: C.authenticated(defaults,key,J.JObject{[]})
    case False{}:
      do Result<&2,&2,String,J.Value>:
        candidate : J.Value <- C.effective(String.split(identity,'\t'))
        delta : J.Value <- diff(defaults,candidate)
        C.authenticated(defaults,key,delta)
def patch(+defaults:J.Value,+key:I.ItemKey) -> Result<&2,&2,String,J.Value>:
  I.ItemKey{id,identity} = key
  kind(defaults,key,String.is_empty(identity))
