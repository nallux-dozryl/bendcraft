import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/player_look.bend as PL
import ../src/vanilla_entity_fields.bend as V
import ../src/inventory.bend as I
import ../src/cooking_effect_entities_model.bend as E
import ../src/u32_decimal.bend as U

def num(value:U32) -> J.Value: J.JNumber{U.show(value)}
def bool(value:Bool) -> J.Value: J.JBool{value}
def txt(value:String) -> J.Value: J.JString{value}
def obj(value:List<&2,J.Member>) -> J.Value: J.JObject{value}
def bits(value:R.Bits64) -> J.Value:
  R.Bits64{hi,lo} = value
  J.JArray{[num(hi),num(lo)]}
def double(value:F.F64) -> J.Value:
  F.F64{hi,lo} = value
  J.JArray{[num(hi),num(lo)]}
def vector(value:V.Vec3) -> J.Value:
  V.Vec3{x,y,z} = value
  J.JArray{[double(x),double(y),double(z)]}
def source(value:R.Source) -> J.Value:
  match value:
    case R.Legacy{seed}: obj([J.JMember{"kind",txt("legacy")},J.JMember{"seed",bits(seed)}])
    case R.Xoroshiro{low,high}: obj([J.JMember{"kind",txt("xoroshiro")},J.JMember{"low",bits(low)},J.JMember{"high",bits(high)}])
def slot(value:I.Slot) -> J.Value:
  match value:
    case I.InvEmpty{}: J.JNull{}
    case I.InvStack{I.ItemKey{id,components},count}: obj([J.JMember{"id",txt(id)},J.JMember{"components",txt(components)},J.JMember{"count",num(count)}])
def common(value:E.Common) -> J.Value:
  E.Common{dimension,id,a,b,r,V.Fields{p,v,o,old,PL.State{yaw,pitch,yawo,pitcho},head,body,fall,ground,air,fire,portal,invulnerable,sync},ticks,first,removed,accessible,order} = value
  obj([J.JMember{"dimension",txt(dimension)},J.JMember{"id",num(id)},J.JMember{"uuid_most",bits(a)},J.JMember{"uuid_least",bits(b)},J.JMember{"random",source(r)},J.JMember{"position",vector(p)},J.JMember{"velocity",vector(v)},J.JMember{"position_o",vector(o)},J.JMember{"yaw",num(PL.raw(yaw))},J.JMember{"pitch",num(PL.raw(pitch))},J.JMember{"yaw_o",num(PL.raw(yawo))},J.JMember{"pitch_o",num(PL.raw(pitcho))},J.JMember{"tick_count",num(ticks)},J.JMember{"first_tick",bool(first)},J.JMember{"removed",bool(removed)},J.JMember{"accessible",bool(accessible)},J.JMember{"section_order",num(U32.from_nat(order))},J.JMember{"on_ground",bool(ground)},J.JMember{"air",num(air)},J.JMember{"fire",num(fire)},J.JMember{"portal_cooldown",num(portal)},J.JMember{"invulnerable",bool(invulnerable)},J.JMember{"needs_sync",bool(sync)}])
def record(value:E.Record) -> J.Value:
  match value:
    case E.Item{c,item,age,delay,health,thrower,target,bob}:
      obj([J.JMember{"kind",txt("item")},J.JMember{"common",common(c)},J.JMember{"item",slot(item)},J.JMember{"age",num(age)},J.JMember{"pickup_delay",num(delay)},J.JMember{"health",num(health)},J.JMember{"thrower",J.JNull{}},J.JMember{"target",J.JNull{}},J.JMember{"bob",num(PL.raw(bob))}])
    case E.Orb{c,value,age,health,count,following}:
      obj([J.JMember{"kind",txt("orb")},J.JMember{"common",common(c)},J.JMember{"value",num(value)},J.JMember{"age",num(age)},J.JMember{"health",num(health)},J.JMember{"count",num(count)},J.JMember{"following",J.JNull{}}])
def records(values:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: record(head) <> records(rest)
def view(value:E.View) -> J.Value:
  E.View{level,unique,cursor,order,values} = value
  obj([J.JMember{"level_after",source(level)},J.JMember{"unique_after",bits(unique)},J.JMember{"cursor_after",num(cursor)},J.JMember{"records",J.JArray{records(values)}}])
def array_field(value:J.Value,name:String) -> Result<&2,&2,String,List<&2,J.Value>>:
  do Result<&2,&2,String,List<&2,J.Value>>:
    raw : J.Value <- D.field(value,name)
    D.array(raw)
def boolean(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{value}: Done{value}
    case _: Fail{"expected boolean"}
def flag(value:J.Value,name:String) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    raw : J.Value <- D.field(value,name)
    boolean(raw)
def read_bits_array(values:List<&2,J.Value>) -> Result<&2,&2,String,R.Bits64>:
  match values:
    case hi <> lo <> Nil{}:
      do Result<&2,&2,String,R.Bits64>:
        hi : U32 <- D.number(hi)
        lo : U32 <- D.number(lo)
        return R.Bits64{hi,lo}
    case _: Fail{"expected two words"}
def read_bits(value:J.Value) -> Result<&2,&2,String,R.Bits64>:
  do Result<&2,&2,String,R.Bits64>:
    values : List<&2,J.Value> <- D.array(value)
    read_bits_array(values)
def bits_field(value:J.Value,name:String) -> Result<&2,&2,String,R.Bits64>:
  do Result<&2,&2,String,R.Bits64>:
    raw : J.Value <- D.field(value,name)
    read_bits(raw)
def read_double(value:R.Bits64) -> F.F64:
  R.Bits64{hi,lo} = value
  F.F64{hi,lo}
def read_vector_array(values:List<&2,J.Value>) -> Result<&2,&2,String,V.Vec3>:
  match values:
    case a <> b <> c <> Nil{}:
      do Result<&2,&2,String,V.Vec3>:
        a : R.Bits64 <- read_bits(a)
        b : R.Bits64 <- read_bits(b)
        c : R.Bits64 <- read_bits(c)
        return V.Vec3{read_double(a),read_double(b),read_double(c)}
    case _: Fail{"expected vector"}
def vector_field(value:J.Value,name:String) -> Result<&2,&2,String,V.Vec3>:
  do Result<&2,&2,String,V.Vec3>:
    values : List<&2,J.Value> <- array_field(value,name)
    read_vector_array(values)
def source_kind(legacy:Bool,+raw:J.Value) -> Result<&2,&2,String,R.Source>:
  match legacy:
    case True{}: Result.map(&2,&2,String,R.Bits64,R.Source,seed => R.Legacy{seed},bits_field(raw,"seed"))
    case False{}:
      do Result<&2,&2,String,R.Source>:
        low : R.Bits64 <- bits_field(raw,"low")
        high : R.Bits64 <- bits_field(raw,"high")
        return R.Xoroshiro{low,high}
def read_source(+raw:J.Value) -> Result<&2,&2,String,R.Source>:
  do Result<&2,&2,String,R.Source>:
    kind : String <- D.text_field(raw,"kind")
    source_kind(String.eq(kind,"legacy"),raw)
def read_common(+raw:J.Value) -> Result<&2,&2,String,E.Common>:
  do Result<&2,&2,String,E.Common>:
    dimension : String <- D.text_field(raw,"dimension")
    id : U32 <- D.number_field(raw,"id")
    a : R.Bits64 <- bits_field(raw,"uuid_most")
    b : R.Bits64 <- bits_field(raw,"uuid_least")
    random_raw : J.Value <- D.field(raw,"random")
    r : R.Source <- read_source(random_raw)
    p : V.Vec3 <- vector_field(raw,"position")
    v : V.Vec3 <- vector_field(raw,"velocity")
    o : V.Vec3 <- vector_field(raw,"position_o")
    yaw : U32 <- D.number_field(raw,"yaw")
    pitch : U32 <- D.number_field(raw,"pitch")
    yawo : U32 <- D.number_field(raw,"yaw_o")
    pitcho : U32 <- D.number_field(raw,"pitch_o")
    ticks : U32 <- D.number_field(raw,"tick_count")
    first : Bool <- flag(raw,"first_tick")
    removed : Bool <- flag(raw,"removed")
    accessible : Bool <- flag(raw,"accessible")
    order : U32 <- D.number_field(raw,"section_order")
    ground : Bool <- flag(raw,"on_ground")
    air : U32 <- D.number_field(raw,"air")
    fire : U32 <- D.number_field(raw,"fire")
    portal : U32 <- D.number_field(raw,"portal_cooldown")
    invulnerable : Bool <- flag(raw,"invulnerable")
    sync : Bool <- flag(raw,"needs_sync")
    return E.Common{dimension,id,a,b,r,V.Fields{p,v,o,V.zero_vector(),PL.State{PL.float_bits(yaw),PL.float_bits(pitch),PL.float_bits(yawo),PL.float_bits(pitcho)},PL.float_bits(0),PL.float_bits(0),F.F64{0,0},ground,air,fire,portal,invulnerable,sync},ticks,first,removed,accessible,U32.to_nat(order)}
# Only existing orbs are required by this focused receiver fixture.
def read_record(+raw:J.Value) -> Result<&2,&2,String,E.Record>:
  do Result<&2,&2,String,E.Record>:
    base : J.Value <- D.field(raw,"common")
    common : E.Common <- read_common(base)
    value : U32 <- D.number_field(raw,"value")
    age : U32 <- D.number_field(raw,"age")
    health : U32 <- D.number_field(raw,"health")
    count : U32 <- D.number_field(raw,"count")
    return E.Orb{common,value,age,health,count,None{}}
def read_records(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,E.Record>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,E.Record>>:
        head : E.Record <- read_record(head)
        tail : List<&2,E.Record> <- read_records(rest)
        return head <> tail
def read_times(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,R.Bits64>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,R.Bits64>>:
        head : R.Bits64 <- read_bits(head)
        tail : List<&2,R.Bits64> <- read_times(rest)
        return head <> tail
