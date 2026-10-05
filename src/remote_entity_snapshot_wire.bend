import Base
import ./json.bend as J
import ./u32_decimal.bend as Decimal
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./movement.bend as M
import ./client_render.bend as R
import ./generic_resource_world_sample.bend as GS
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./item_entity_render_model.bend as D
import ./remote_entity_frame.bend as EF

# A comparison stamp is extracted from the actual atomic publication. It is
# not a second mutable owner, simulation View, or a supplied entity identity.
type Stamp is Data:
  Stamp{registry:String,tick:Nat,revision:Nat,dimension:String,origin:M.Vec3,
    camera:R.Camera,partial:F32}

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}
def u(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def n(value:Nat) -> J.Value: J.JNumber{Nat.show(value)}
def s(value:String) -> J.Value: J.JString{value}
def b(value:Bool) -> J.Value: J.JBool{value}
def nat_max() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(65535),Nat.add(U32.to_nat(4294967295),1n)),U32.to_nat(4294967295))
def float_bits(value:U32) -> F32:
  U32{word} = value
  F32{word}
def finite32(value:F32) -> Bool:
  U32.is_ne(U32.and(F32.bits(value),2139095040),2139095040)
def partial_valid(+value:F32) -> Bool:
  finite32(value) && F32.is_ge(value,0.0) && F32.is_le(value,1.0)
def uint_read(+raw:String,value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Fail{"entity-wire:U32"}
    case Some{+word}:
      do Result<&2,&2,String,U32>:
        guard(String.eq(raw,Decimal.show(word)),"entity-wire:noncanonical-U32")
        Done{word}
def uint(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{+raw}: uint_read(raw,J.u32_lexeme(raw))
    case _: Fail{"entity-wire:expected-U32"}
def natural_read(+raw:String,value:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match value:
    case None{}: Fail{"entity-wire:Nat48"}
    case Some{+word}:
      do Result<&2,&2,String,Nat>:
        guard(String.eq(raw,Nat.show(word)) && Nat.is_le(word,nat_max()),"entity-wire:noncanonical-Nat48")
        Done{word}
def natural(value:J.Value) -> Result<&2,&2,String,Nat>:
  match value:
    case J.JNumber{+raw}: natural_read(raw,Nat.read(raw))
    case _: Fail{"entity-wire:expected-Nat48"}
def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{value}: Done{value}
    case _: Fail{"entity-wire:expected-String"}
def boolean(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{value}: Done{value}
    case _: Fail{"entity-wire:expected-Bool"}
def name_char(+c:U32) -> Bool:
  (U32.is_ge(c,97) && U32.is_le(c,122)) || (U32.is_ge(c,48) && U32.is_le(c,57)) ||
    U32.is_eq(c,95) || U32.is_eq(c,45) || U32.is_eq(c,46)
def path_chars(text:String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c},rest}:
      (name_char(c) || U32.is_eq(c,47)) && path_chars(rest)
def namespace_chars(text:String,nonempty:Bool) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{58},+rest}: nonempty && Bool.not(String.is_empty(rest)) && path_chars(rest)
    case SCon{Chr{c},rest}: name_char(c) && namespace_chars(rest,True{})
def dimension_valid(name:String) -> Bool: namespace_chars(name,False{})
def vector(value:J.Value) -> Result<&2,&2,String,V.Vec3>:
  match value:
    case J.JArray{[xh,xl,yh,yl,zh,zl]}:
      do Result<&2,&2,String,V.Vec3>:
        a:U32 <- uint(xh)
        b:U32 <- uint(xl)
        c:U32 <- uint(yh)
        d:U32 <- uint(yl)
        e:U32 <- uint(zh)
        f:U32 <- uint(zl)
        +answer:V.Vec3 = V.Vec3{F.F64{a,b},F.F64{c,d},F.F64{e,f}}
        guard(V.vector_finite(answer),"entity-wire:nonfinite-position")
        Done{answer}
    case _: Fail{"entity-wire:vector-cardinality"}
def vector_value(value:V.Vec3) -> J.Value:
  V.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  J.JArray{[u(xh),u(xl),u(yh),u(yl),u(zh),u(zl)]}
def common_valid(common:D.Common) -> Bool:
  D.Common{dimension,id,current,old,tick,removed,accessible,order} = common
  dimension_valid(dimension) && V.vector_finite(current) && V.vector_finite(old) && Nat.is_le(order,nat_max())
def common(value:J.Value) -> Result<&2,&2,String,D.Common>:
  match value:
    case J.JArray{[dimension,id,current,old,tick,removed,accessible,order]}:
      do Result<&2,&2,String,D.Common>:
        name:String <- text(dimension)
        identity:U32 <- uint(id)
        now:V.Vec3 <- vector(current)
        previous:V.Vec3 <- vector(old)
        count:U32 <- uint(tick)
        gone:Bool <- boolean(removed)
        live:Bool <- boolean(accessible)
        position:Nat <- natural(order)
        +answer:D.Common = D.Common{name,identity,now,previous,count,gone,live,position}
        guard(common_valid(answer),"entity-wire:invalid-common")
        Done{answer}
    case _: Fail{"entity-wire:common-cardinality"}
def common_value(value:D.Common) -> J.Value:
  D.Common{dimension,id,current,old,tick,removed,accessible,order} = value
  J.JArray{[s(dimension),u(id),vector_value(current),vector_value(old),u(tick),b(removed),b(accessible),n(order)]}
def slot(value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JArray{[J.JNumber{"0"}]}: Done{Inv.InvEmpty{}}
    case J.JArray{[J.JNumber{"1"},id,components,count]}:
      do Result<&2,&2,String,Inv.Slot>:
        name:String <- text(id)
        patch:String <- text(components)
        amount:U32 <- uint(count)
        +answer:Inv.Slot = Inv.InvStack{Inv.ItemKey{name,patch},amount}
        guard(I.structural_slot(answer),"entity-wire:invalid-item-stack")
        Done{answer}
    case _: Fail{"entity-wire:slot-tag-or-cardinality"}
def slot_value(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JArray{[u(0)]}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: J.JArray{[u(1),s(id),s(components),u(count)]}
def record_common(value:D.Record) -> D.Common:
  match value:
    case D.Item{common,item,bob}: common
    case D.Orb{common,value}: common
def common_id(value:D.Common) -> U32:
  D.Common{dimension,id,current,old,tick,removed,accessible,order} = value
  id
def record_id(value:D.Record) -> U32: common_id(record_common(value))
def record_valid(value:D.Record) -> Bool:
  match value:
    case D.Item{common,item,bob}: common_valid(common) && I.structural_slot(item) && finite32(bob)
    case D.Orb{common,value}: common_valid(common)
def record(value:J.Value) -> Result<&2,&2,String,D.Record>:
  match value:
    case J.JArray{[J.JNumber{"0"},base,item,bob]}:
      do Result<&2,&2,String,D.Record>:
        c:D.Common <- common(base)
        stack:Inv.Slot <- slot(item)
        bits:U32 <- uint(bob)
        +answer:D.Record = D.Item{c,stack,float_bits(bits)}
        guard(record_valid(answer),"entity-wire:invalid-item-record")
        Done{answer}
    case J.JArray{[J.JNumber{"1"},base,value]}:
      do Result<&2,&2,String,D.Record>:
        c:D.Common <- common(base)
        amount:U32 <- uint(value)
        Done{D.Orb{c,amount}}
    case _: Fail{"entity-wire:record-tag-or-cardinality"}
def record_value(value:D.Record) -> J.Value:
  match value:
    case D.Item{common,item,bob}: J.JArray{[u(0),common_value(common),slot_value(item),u(F32.bits(bob))]}
    case D.Orb{common,value}: J.JArray{[u(1),common_value(common),u(value)]}
def seen(result:Map<&2,Unit> & Bool) -> Bool:
  (map,found) = result
  found
def records_valid(values:List<&2,D.Record>,+ids:Map<&2,Unit>) -> Bool:
  match values:
    case Nil{}: True{}
    case +head <> rest:
      +key = Decimal.show(record_id(head))
      record_valid(head) && Bool.not(seen(Map.has(&2,Unit,ids,key))) &&
        records_valid(rest,Map.set(&2,Unit,ids,key,Unit{}))
def snapshot_valid(value:D.Snapshot) -> Bool:
  match value:
    case D.Unbound{}: True{}
    case D.Bound{values}: records_valid(values,MTip{})
def records(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,D.Record>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,D.Record>>:
        own:D.Record <- record(head)
        tail:List<&2,D.Record> <- records(rest)
        Done{own <> tail}
def records_value(values:List<&2,D.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: record_value(head) <> records_value(rest)
def snapshot(value:J.Value) -> Result<&2,&2,String,D.Snapshot>:
  match value:
    case J.JArray{[J.JNumber{"0"}]}: Done{D.Unbound{}}
    case J.JArray{[J.JNumber{"1"},J.JArray{values}]}:
      do Result<&2,&2,String,D.Snapshot>:
        rows:List<&2,D.Record> <- records(values)
        +answer:D.Snapshot = D.Bound{rows}
        guard(snapshot_valid(answer),"entity-wire:duplicate-or-invalid-records")
        Done{answer}
    case _: Fail{"entity-wire:snapshot-tag-or-cardinality"}
def snapshot_value(value:D.Snapshot) -> J.Value:
  match value:
    case D.Unbound{}: J.JArray{[u(0)]}
    case D.Bound{records}: J.JArray{[u(1),J.JArray{records_value(records)}]}
def word_equal(left:F.F64,right:F.F64) -> Bool:
  F.F64{a,b} = left
  F.F64{c,d} = right
  U32.is_eq(a,c) && U32.is_eq(b,d)
def origin_equal(left:M.Vec3,right:M.Vec3) -> Bool:
  M.Vec3{x,y,z} = left
  M.Vec3{a,b,c} = right
  word_equal(x,a) && word_equal(y,b) && word_equal(z,c)
def camera_equal(left:R.Camera,right:R.Camera) -> Bool:
  R.Camera{x,y,z,yaw,pitch} = left
  R.Camera{a,b,c,d,e} = right
  U32.is_eq(F32.bits(x),F32.bits(a)) && U32.is_eq(F32.bits(y),F32.bits(b)) &&
    U32.is_eq(F32.bits(z),F32.bits(c)) && U32.is_eq(F32.bits(yaw),F32.bits(d)) && U32.is_eq(F32.bits(pitch),F32.bits(e))
def stamp(frame:EF.Frame) -> Stamp:
  EF.Frame{GS.Sample{registry,tick,revision,origin,camera,cells},entities,dimension,partial} = frame
  Stamp{registry,tick,revision,dimension,origin,camera,partial}
def stamp_equal(left:Stamp,right:Stamp) -> Bool:
  Stamp{registry,tick,revision,dimension,origin,camera,partial} = left
  Stamp{a,b,c,d,e,f,g} = right
  String.eq(registry,a) && Nat.is_eq(tick,b) && Nat.is_eq(revision,c) && String.eq(dimension,d) &&
    origin_equal(origin,e) && camera_equal(camera,f) && U32.is_eq(F32.bits(partial),F32.bits(g))
def matches(expected:Stamp,frame:EF.Frame) -> Bool:
  stamp_equal(expected,stamp(frame))
def stamp_checked(valid:Bool,frame:EF.Frame) -> Result<&2,&2,String,EF.Frame>:
  match valid:
    case False{}: Fail{"entity-wire:capture-stamp-mismatch"}
    case True{}: Done{frame}
def checked_stamp(expected:Stamp,+frame:EF.Frame) -> Result<&2,&2,String,EF.Frame>:
  stamp_checked(matches(expected,frame),frame)
def frame_fields_valid(frame:EF.Frame) -> Bool:
  EF.Frame{sample,entities,dimension,partial} = frame
  dimension_valid(dimension) && partial_valid(partial) && snapshot_valid(entities)
