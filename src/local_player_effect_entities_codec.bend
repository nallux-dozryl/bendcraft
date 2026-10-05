import Base
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./player_look.bend as P
import ./f64.bend as F
import ./inventory.bend as I
import ./nbt.bend as N

# Internal complete owner snapshot. This is deliberately independent of
# vanilla Entity load/save projection, which drops previous and transient fields.
# Every number is stored as raw U32 words; no numeric normalization is performed.
def words(value:String) -> List<&2,U32>:
  match value:
    case SNil{}: []
    case SCon{Chr{word},rest}: word <> words(rest)
def string(value:List<&2,U32>) -> String:
  match value:
    case Nil{}: ""
    case word <> rest: SCon{Chr{word},string(rest)}
def equal_words(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && equal_words(xs,ys)
    case _ _: False{}
def text(value:String) -> N.Text: N.Text{words(value)}
def name(value:N.Text,expected:String) -> Bool:
  N.Text{units} = value
  equal_words(units,words(expected))
def member(key:String,value:N.Value) -> N.Member: N.Member{text(key),value}
def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{"local-player-effect-entities:" ++ message}
def raw_float(bits:U32) -> F32:
  U32{word} = bits
  F32{word}
def bool_read(value:U32) -> Result<&2,&2,String,Bool>:
  match value:
    case 0: Done{False{}}
    case 1: Done{True{}}
    case _: Fail{"local-player-effect-entities:noncanonical boolean"}
def natural_read(+raw:String,result:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match result:
    case None{}: Fail{"local-player-effect-entities:natural number"}
    case Some{+value}:
      do Result<&2,&2,String,Nat>:
        guard(String.eq(raw,Nat.show(value)),"noncanonical natural number")
        return value
def nat_read(units:List<&2,U32>) -> Result<&2,&2,String,Nat>:
  +raw = string(units)
  natural_read(raw,Nat.read(raw))
def nat_value(value:Nat) -> N.Value: N.IntArray{words(Nat.show(value))}
def bits_value(value:R.Bits64) -> N.Value:
  R.Bits64{hi,lo} = value
  N.IntArray{[hi,lo]}
def bits_read(value:N.Value) -> Result<&2,&2,String,R.Bits64>:
  match value:
    case N.IntArray{hi <> lo <> Nil{}}: Done{R.Bits64{hi,lo}}
    case _: Fail{"local-player-effect-entities:64-bit words"}
def double_value(value:F.F64) -> N.Value:
  F.F64{hi,lo} = value
  N.IntArray{[hi,lo]}
def double_read(value:N.Value) -> Result<&2,&2,String,F.F64>:
  match value:
    case N.IntArray{hi <> lo <> Nil{}}: Done{F.F64{hi,lo}}
    case _: Fail{"local-player-effect-entities:double words"}
def random_value(value:R.Source) -> N.Value:
  match value:
    case R.Legacy{R.Bits64{hi,lo}}:
      N.Compound{[member("kind",N.Int{0}),member("words",N.IntArray{[hi,lo]})]}
    case R.Xoroshiro{R.Bits64{lh,ll},R.Bits64{hh,hl}}:
      N.Compound{[member("kind",N.Int{1}),member("words",N.IntArray{[lh,ll,hh,hl]})]}
def random_payload(kind:U32,units:List<&2,U32>) -> Result<&2,&2,String,R.Source>:
  match kind units:
    case 0 hi <> lo <> Nil{}: Done{R.Legacy{R.Bits64{hi,lo}}}
    case 1 lh <> ll <> hh <> hl <> Nil{}:
      Done{R.Xoroshiro{R.Bits64{lh,ll},R.Bits64{hh,hl}}}
    case _ _: Fail{"local-player-effect-entities:random kind or words"}
def random_read(value:N.Value) -> Result<&2,&2,String,R.Source>:
  match value:
    case N.Compound{N.Member{a,N.Int{kind}} <> N.Member{b,N.IntArray{units}} <> Nil{}}:
      do Result<&2,&2,String,R.Source>:
        guard(name(a,"kind") && name(b,"words"),"random schema")
        random_payload(kind,units)
    case _: Fail{"local-player-effect-entities:random schema"}
def vector_value(value:V.Vec3) -> N.Value:
  V.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  N.IntArray{[xh,xl,yh,yl,zh,zl]}
def vector_read(value:N.Value) -> Result<&2,&2,String,V.Vec3>:
  match value:
    case N.IntArray{xh <> xl <> yh <> yl <> zh <> zl <> Nil{}}:
      Done{V.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}}}
    case _: Fail{"local-player-effect-entities:vector words"}
def look_value(value:P.State) -> N.Value:
  P.State{yaw,pitch,old_yaw,old_pitch} = value
  N.IntArray{[P.raw(yaw),P.raw(pitch),P.raw(old_yaw),P.raw(old_pitch)]}
def look_read(value:N.Value) -> Result<&2,&2,String,P.State>:
  match value:
    case N.IntArray{yaw <> pitch <> old_yaw <> old_pitch <> Nil{}}:
      Done{P.State{raw_float(yaw),raw_float(pitch),raw_float(old_yaw),raw_float(old_pitch)}}
    case _: Fail{"local-player-effect-entities:look words"}
def fields_value(value:V.Fields) -> N.Value:
  V.Fields{position,velocity,previous,old,look,head,body,fall,ground,air,fire,portal,invulnerable,sync} = value
  N.Compound{[member("position",vector_value(position)),member("velocity",vector_value(velocity)),
    member("position_o",vector_value(previous)),member("position_old",vector_value(old)),
    member("look",look_value(look)),member("head_yaw",N.Int{P.raw(head)}),
    member("body_yaw",N.Int{P.raw(body)}),member("fall_distance",double_value(fall)),
    member("on_ground",N.Int{Bool.to_u32(ground)}),member("air",N.Int{air}),
    member("fire",N.Int{fire}),member("portal_cooldown",N.Int{portal}),
    member("invulnerable",N.Int{Bool.to_u32(invulnerable)}),member("needs_sync",N.Int{Bool.to_u32(sync)})]}
def fields_read(value:N.Value) -> Result<&2,&2,String,V.Fields>:
  match value:
    case N.Compound{N.Member{a,position} <> N.Member{b,velocity} <> N.Member{c,previous} <>
        N.Member{d,old} <> N.Member{e,look} <> N.Member{f,N.Int{head}} <> N.Member{g,N.Int{body}} <>
        N.Member{h,fall} <> N.Member{i,N.Int{ground}} <> N.Member{j,N.Int{air}} <>
        N.Member{k,N.Int{fire}} <> N.Member{l,N.Int{portal}} <> N.Member{m,N.Int{invulnerable}} <>
        N.Member{n,N.Int{sync}} <> Nil{}}:
      do Result<&2,&2,String,V.Fields>:
        guard(name(a,"position") && name(b,"velocity") && name(c,"position_o") && name(d,"position_old") &&
          name(e,"look") && name(f,"head_yaw") && name(g,"body_yaw") && name(h,"fall_distance") &&
          name(i,"on_ground") && name(j,"air") && name(k,"fire") && name(l,"portal_cooldown") &&
          name(m,"invulnerable") && name(n,"needs_sync"),"fields schema")
        pos : V.Vec3 <- vector_read(position)
        vel : V.Vec3 <- vector_read(velocity)
        prior : V.Vec3 <- vector_read(previous)
        older : V.Vec3 <- vector_read(old)
        angles : P.State <- look_read(look)
        distance : F.F64 <- double_read(fall)
        grounded : Bool <- bool_read(ground)
        invul : Bool <- bool_read(invulnerable)
        needs : Bool <- bool_read(sync)
        return V.Fields{pos,vel,prior,older,angles,raw_float(head),raw_float(body),distance,grounded,air,fire,portal,invul,needs}
    case _: Fail{"local-player-effect-entities:fields schema"}
def uuid_value(value:Maybe<&2,E.Uuid>) -> N.Value:
  match value:
    case None{}: N.IntArray{[]}
    case Some{E.Uuid{R.Bits64{mh,ml},R.Bits64{lh,ll}}}: N.IntArray{[mh,ml,lh,ll]}
def uuid_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,E.Uuid>>:
  match value:
    case N.IntArray{Nil{}}: Done{None{}}
    case N.IntArray{mh <> ml <> lh <> ll <> Nil{}}:
      Done{Some{E.Uuid{R.Bits64{mh,ml},R.Bits64{lh,ll}}}}
    case _: Fail{"local-player-effect-entities:optional UUID words"}
def common_value(value:E.Common) -> N.Value:
  E.Common{dimension,id,most,least,random,fields,tick,first,removed,accessible,order} = value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("id",N.Int{id}),
    member("uuid_most",bits_value(most)),member("uuid_least",bits_value(least)),
    member("random",random_value(random)),member("fields",fields_value(fields)),
    member("tick_count",N.Int{tick}),member("first_tick",N.Int{Bool.to_u32(first)}),
    member("removed",N.Int{Bool.to_u32(removed)}),member("accessible",N.Int{Bool.to_u32(accessible)}),
    member("section_order",nat_value(order))]}
def common_read(value:N.Value) -> Result<&2,&2,String,E.Common>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{id}} <> N.Member{c,most} <>
        N.Member{d,least} <> N.Member{e,random} <> N.Member{f,fields} <> N.Member{g,N.Int{tick}} <>
        N.Member{h,N.Int{first}} <> N.Member{i,N.Int{removed}} <> N.Member{j,N.Int{accessible}} <>
        N.Member{k,N.IntArray{order}} <> Nil{}}:
      do Result<&2,&2,String,E.Common>:
        guard(name(a,"dimension") && name(b,"id") && name(c,"uuid_most") && name(d,"uuid_least") &&
          name(e,"random") && name(f,"fields") && name(g,"tick_count") && name(h,"first_tick") &&
          name(i,"removed") && name(j,"accessible") && name(k,"section_order"),"common schema")
        uuid_most : R.Bits64 <- bits_read(most)
        uuid_least : R.Bits64 <- bits_read(least)
        source : R.Source <- random_read(random)
        values : V.Fields <- fields_read(fields)
        first_tick : Bool <- bool_read(first)
        is_removed : Bool <- bool_read(removed)
        is_accessible : Bool <- bool_read(accessible)
        section : Nat <- nat_read(order)
        return E.Common{string(dimension),id,uuid_most,uuid_least,source,values,tick,first_tick,is_removed,is_accessible,section}
    case _: Fail{"local-player-effect-entities:common schema"}
def slot_value(value:I.Slot) -> N.Value:
  match value:
    case I.InvEmpty{}: N.Compound{[]}
    case I.InvStack{I.ItemKey{id,components},count}:
      N.Compound{[member("id",N.IntArray{words(id)}),member("components",N.IntArray{words(components)}),member("count",N.Int{count})]}
def slot_read(value:N.Value) -> Result<&2,&2,String,I.Slot>:
  match value:
    case N.Compound{Nil{}}: Done{I.InvEmpty{}}
    case N.Compound{N.Member{a,N.IntArray{id}} <> N.Member{b,N.IntArray{components}} <> N.Member{c,N.Int{count}} <> Nil{}}:
      do Result<&2,&2,String,I.Slot>:
        guard(name(a,"id") && name(b,"components") && name(c,"count"),"item schema")
        return I.InvStack{I.ItemKey{string(id),string(components)},count}
    case _: Fail{"local-player-effect-entities:item schema"}
def record_value(value:E.Record) -> N.Value:
  match value:
    case E.Item{common,item,age,delay,health,thrower,target,bob}:
      N.Compound{[member("kind",N.Int{0}),member("common",common_value(common)),member("payload",N.Compound{
        [member("item",slot_value(item)),member("age",N.Int{age}),member("pickup_delay",N.Int{delay}),
          member("health",N.Int{health}),member("thrower",uuid_value(thrower)),member("target",uuid_value(target)),
          member("bob",N.Int{P.raw(bob)})]})]}
    case E.Orb{common,value,age,health,count,following}:
      N.Compound{[member("kind",N.Int{1}),member("common",common_value(common)),member("payload",N.Compound{
        [member("value",N.Int{value}),member("age",N.Int{age}),member("health",N.Int{health}),
          member("count",N.Int{count}),member("following",uuid_value(following))]})]}
def record_payload(kind:U32,common:E.Common,value:N.Value) -> Result<&2,&2,String,E.Record>:
  match kind value:
    case 0 N.Compound{N.Member{a,item} <> N.Member{b,N.Int{age}} <> N.Member{c,N.Int{delay}} <>
        N.Member{d,N.Int{health}} <> N.Member{e,thrower} <> N.Member{f,target} <> N.Member{g,N.Int{bob}} <> Nil{}}:
      do Result<&2,&2,String,E.Record>:
        guard(name(a,"item") && name(b,"age") && name(c,"pickup_delay") && name(d,"health") &&
          name(e,"thrower") && name(f,"target") && name(g,"bob"),"item payload schema")
        stack : I.Slot <- slot_read(item)
        owner : Maybe<&2,E.Uuid> <- uuid_read(thrower)
        destination : Maybe<&2,E.Uuid> <- uuid_read(target)
        return E.Item{common,stack,age,delay,health,owner,destination,raw_float(bob)}
    case 1 N.Compound{N.Member{a,N.Int{amount}} <> N.Member{b,N.Int{age}} <> N.Member{c,N.Int{health}} <>
        N.Member{d,N.Int{count}} <> N.Member{e,following} <> Nil{}}:
      do Result<&2,&2,String,E.Record>:
        guard(name(a,"value") && name(b,"age") && name(c,"health") && name(d,"count") && name(e,"following"),"orb payload schema")
        player : Maybe<&2,E.Uuid> <- uuid_read(following)
        return E.Orb{common,amount,age,health,count,player}
    case _ _: Fail{"local-player-effect-entities:entity kind or payload schema"}
def record_read(value:N.Value) -> Result<&2,&2,String,E.Record>:
  match value:
    case N.Compound{N.Member{a,N.Int{kind}} <> N.Member{b,common} <> N.Member{c,payload} <> Nil{}}:
      do Result<&2,&2,String,E.Record>:
        guard(name(a,"kind") && name(b,"common") && name(c,"payload"),"entity schema")
        fields : E.Common <- common_read(common)
        record_payload(kind,fields,payload)
    case _: Fail{"local-player-effect-entities:entity schema"}
def record_values(values:List<&2,E.Record>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: record_value(head) <> record_values(rest)
def records_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,E.Record>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,E.Record>>:
        first : E.Record <- record_read(head)
        tail : List<&2,E.Record> <- records_read(rest)
        return first <> tail
def root(value:E.View) -> N.Root:
  E.View{random,seed,id,order,records} = value
  N.Root{text("bendex:cooking-effect-entities"),N.Compound{[member("format",N.Int{1}),
    member("level_random",random_value(random)),member("seed_uniquifier",bits_value(seed)),
    member("last_id",N.Int{id}),member("next_section_order",nat_value(order)),
    member("records",N.ListTag{10,record_values(records)})]}}
def root_read(value:N.Root) -> Result<&2,&2,String,E.View>:
  match value:
    case N.Root{n,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,random} <> N.Member{c,seed} <>
        N.Member{d,N.Int{id}} <> N.Member{e,N.IntArray{order}} <> N.Member{f,N.ListTag{10,records}} <> Nil{}}}:
      do Result<&2,&2,String,E.View>:
        guard(name(n,"bendex:cooking-effect-entities") && name(a,"format") && name(b,"level_random") &&
          name(c,"seed_uniquifier") && name(d,"last_id") && name(e,"next_section_order") && name(f,"records"),"root schema")
        source : R.Source <- random_read(random)
        uniquifier : R.Bits64 <- bits_read(seed)
        cursor : Nat <- nat_read(order)
        values : List<&2,E.Record> <- records_read(records)
        return E.View{source,uniquifier,id,cursor,values}
    case _: Fail{"local-player-effect-entities:root schema"}
def encoded(result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Fail{message}: Fail{"local-player-effect-entities:NBT:" ++ message}
    case Done{bytes}: Done{bytes}
def decoded(result:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,E.View>:
  match result:
    case Fail{message}: Fail{"local-player-effect-entities:NBT:" ++ message}
    case Done{value}: root_read(value)
def native_nat(value:Nat) -> Result<&2,&2,String,Unit>:
  +raw = Nat.show(value)
  Result.map(&2,&2,String,Nat,Unit,count => Unit{},natural_read(raw,Nat.read(raw)))
def common_nat(value:E.Common) -> Result<&2,&2,String,Unit>:
  E.Common{dimension,id,most,least,random,fields,tick,first,removed,accessible,order} = value
  native_nat(order)
def records_nat(values:List<&2,E.Record>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case head <> rest:
      do Result<&2,&2,String,Unit>:
        common_nat(E.common(head))
        records_nat(rest)
def view_nat(value:E.View) -> Result<&2,&2,String,Unit>:
  E.View{random,seed,id,order,records} = value
  do Result<&2,&2,String,Unit>:
    native_nat(order)
    records_nat(records)
def encode(limits:N.Limits,+value:E.View) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    view_nat(value)
    encoded(N.encode_with(limits,root(value)))
def decode(limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,E.View>:
  decoded(N.decode_with(limits,bytes))

# These contracts concern the raw storage projection, including exceptional
# floating-point payloads and RNG words. They do not claim NBT limits or IO.
law vector_words_are_reversible:
  for value:V.Vec3
  {vector_read(vector_value(value)) == Done{value} : Result<&2,&2,String,V.Vec3>}
def vector_words_are_reversible(value):
  match value:
    case V.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}}: {==}
law random_words_are_reversible:
  for value:R.Source
  {random_read(random_value(value)) == Done{value} : Result<&2,&2,String,R.Source>}
def random_words_are_reversible(value):
  match value:
    case R.Legacy{R.Bits64{hi,lo}}: {==}
    case R.Xoroshiro{R.Bits64{lh,ll},R.Bits64{hh,hl}}: {==}
law optional_uuid_words_are_reversible:
  for value:Maybe<&2,E.Uuid>
  {uuid_read(uuid_value(value)) == Done{value} : Result<&2,&2,String,Maybe<&2,E.Uuid>>}
def optional_uuid_words_are_reversible(value):
  match value:
    case None{}: {==}
    case Some{E.Uuid{R.Bits64{mh,ml},R.Bits64{lh,ll}}}: {==}
law raw_float_words_are_reversible:
  for value:U32
  {P.raw(raw_float(value)) == value : U32}
def raw_float_words_are_reversible(value):
  match value:
    case U32{word}: {==}
