import Base
import ./random.bend as R
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities_math.bend as M

type SectionKey is Data:
  SectionKey{x:U32,z:U32,y:U32,order:Nat}
type Hit is Data:
  Hit{id:U32,key:SectionKey}
def integer(result:Result<&2,&2,F.F64ConversionError,U32>) -> Result<&2,&2,E.Error,U32>:
  match result:
    case Fail{error}: Fail{E.Refused{"entity-section-position-outside-signed-range"}}
    case Done{value}: Done{value}
def section(point:F.F64) -> Result<&2,&2,E.Error,U32>:
  integer(F.floor_i32(F.div(point,F.F64{1076887552,0})))
def key(point:V.Vec3,order:Nat) -> Result<&2,&2,E.Error,SectionKey>:
  V.Vec3{x,y,z} = point
  do Result<&2,&2,E.Error,SectionKey>:
    x : U32 <- section(x)
    y : U32 <- section(y)
    z : U32 <- section(z)
    return SectionKey{x,U32.and(z,4194303),U32.and(y,1048575),order}
def less(a:SectionKey,b:SectionKey) -> Bool:
  SectionKey{+ax,+az,+ay,ao} = a
  SectionKey{+bx,+bz,+by,bo} = b
  U32.is_lt(U32.xor(ax,2147483648),U32.xor(bx,2147483648)) ||
    (U32.is_eq(ax,bx) && (U32.is_lt(az,bz) ||
      (U32.is_eq(az,bz) && (U32.is_lt(ay,by) ||
        (U32.is_eq(ay,by) && Nat.is_lt(ao,bo))))))
def first_choice(candidate:Hit,prior:Hit,earlier:Bool) -> Maybe<&2,Hit>:
  match earlier:
    case True{}: Some{candidate}
    case False{}: Some{prior}
def first(+candidate:Hit,prior:Maybe<&2,Hit>) -> Maybe<&2,Hit>:
  Hit{a,+key} = candidate
  match prior:
    case None{}: Some{candidate}
    case Some{+old}:
      Hit{b,other} = old
      first_choice(candidate,old,less(key,other))
def absolute(value:U32,negative:Bool) -> U32:
  match negative:
    case True{}: U32.sub(0,value)
    case False{}: value
def residue(+id:U32,ticket:U32) -> Bool:
  +difference = U32.sub(id,ticket)
  U32.is_zero(U32.mod(absolute(difference,U32.is_ge(difference,2147483648)),40))
def overlap(center:V.Vec3,position:V.Vec3) -> Bool:
  V.Vec3{+cx,+cy,+cz} = center
  V.Vec3{+x,+y,+z} = position
  F.is_lt(F.sub(x,F.F64{1070596096,0}),F.add(cx,M.half())) &&
  F.is_gt(F.add(x,F.F64{1070596096,0}),F.sub(cx,M.half())) &&
  F.is_lt(y,F.add(cy,M.half())) && F.is_gt(F.add(y,M.half()),F.sub(cy,M.half())) &&
  F.is_lt(F.sub(z,F.F64{1070596096,0}),F.add(cz,M.half())) &&
  F.is_gt(F.add(z,F.F64{1070596096,0}),F.sub(cz,M.half()))
def keyed(id:U32,prior:Maybe<&2,Hit>,result:Result<&2,&2,E.Error,SectionKey>) -> Result<&2,&2,E.Error,Maybe<&2,Hit>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{key}: Done{first(Hit{id,key},prior)}
def candidate(valid:Bool,id:U32,position:V.Vec3,order:Nat,prior:Maybe<&2,Hit>) -> Result<&2,&2,E.Error,Maybe<&2,Hit>>:
  match valid:
    case False{}: Done{prior}
    case True{}: keyed(id,prior,key(position,order))
def orb(dimension:String,center:V.Vec3,ticket:U32,value:U32,common:E.Common,other:U32,prior:Maybe<&2,Hit>) -> Result<&2,&2,E.Error,Maybe<&2,Hit>>:
  E.Common{d,+id,a,b,r,V.Fields{+position,velocity,o,old,look,head,body,fall,ground,air,fire,portal,invulnerable,sync},t,first,removed,accessible,order} = common
  candidate(String.eq(d,dimension) && Bool.not(removed) && accessible && U32.is_eq(value,other) && residue(id,ticket) && overlap(center,position),id,position,order,prior)
def find(values:List<&2,E.Record>,+dimension:String,+center:V.Vec3,+ticket:U32,+value:U32,prior:Maybe<&2,Hit>) -> Result<&2,&2,E.Error,Maybe<&2,Hit>>:
  match values:
    case Nil{}: Done{prior}
    case E.Item{common,item,age,delay,health,thrower,target,bob} <> rest: find(rest,dimension,center,ticket,value,prior)
    case E.Orb{common,other,age,health,count,following} <> rest:
      do Result<&2,&2,E.Error,Maybe<&2,Hit>>:
        next : Maybe<&2,Hit> <- orb(dimension,center,ticket,value,common,other,prior)
        find(rest,dimension,center,ticket,value,next)
def update_choice(value:E.Record,hit:Bool) -> E.Record:
  match value hit:
    case E.Orb{common,value,age,health,count,following} True{}: E.Orb{common,value,0,health,U32.inc(count),following}
    case value _: value
def update(values:List<&2,E.Record>,+id:U32) -> List<&2,E.Record>:
  match values:
    case Nil{}: []
    case +head <> rest: update_choice(head,U32.is_eq(E.record_id(head),id)) <> update(rest,id)
