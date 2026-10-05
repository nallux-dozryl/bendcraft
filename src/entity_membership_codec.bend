import Base
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as Membership
import ./entity_membership_codec_validation.bend as Check
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R
import ./geometry.bend as A
import ./f64.bend as F
import ./nbt.bend as N

# Complete immutable manager image. Decoding is not an owner installation or a
# live visibility grant. The real loader/record join remains authoritative.
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
  N.Text{units}=value
  equal_words(units,words(expected))
def member(key:String,value:N.Value) -> N.Member: N.Member{text(key),value}
def visibility_value(value:M.Visibility) -> N.Value:
  match value:
    case M.Hidden{}: N.Int{0}
    case M.Tracked{}: N.Int{1}
    case M.Ticking{}: N.Int{2}
def visibility_read(value:N.Value) -> Result<&2,&2,String,M.Visibility>:
  match value:
    case N.Int{0}: Done{M.Hidden{}}
    case N.Int{1}: Done{M.Tracked{}}
    case N.Int{2}: Done{M.Ticking{}}
    case _: Fail{"entity-membership:visibility discriminant"}
def bool_read(value:U32) -> Result<&2,&2,String,Bool>:
  match value:
    case 0: Done{False{}}
    case 1: Done{True{}}
    case _: Fail{"entity-membership:noncanonical boolean"}
def key_value(value:M.SectionKey) -> N.Value:
  M.SectionKey{x,y,z}=value
  N.IntArray{[x,y,z]}
def key_read(value:N.Value) -> Result<&2,&2,String,M.SectionKey>:
  match value:
    case N.IntArray{x <> y <> z <> Nil{}}: Done{M.SectionKey{x,y,z}}
    case _: Fail{"entity-membership:key word cardinality"}
def nat_value(+value:Nat) -> N.Value:
  N.Long{N.Word64{U32.from_nat(Nat.div(value,Check.word_base())),U32.from_nat(value)}}
def nat_read(value:N.Value) -> Result<&2,&2,String,Nat>:
  match value:
    case N.Long{N.Word64{+hi,lo}}:
      do Result<&2,&2,String,Nat>:
        Check.guard(U32.is_le(hi,65535),"order exceeds native Nat48")
        return Nat.add(Nat.mul(U32.to_nat(hi),Check.word_base()),U32.to_nat(lo))
    case _: Fail{"entity-membership:order TAG_Long"}
def box_value(value:A.AABB) -> N.Value:
  A.AABB{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl},F.F64{dh,dl},F.F64{eh,el},F.F64{fh,fl}}=value
  N.IntArray{[ah,al,bh,bl,ch,cl,dh,dl,eh,el,fh,fl]}
def box_read(value:N.Value) -> Result<&2,&2,String,A.AABB>:
  match value:
    case N.IntArray{ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}}:
      Done{A.AABB{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl},F.F64{dh,dl},F.F64{eh,el},F.F64{fh,fl}}}
    case _: Fail{"entity-membership:box word cardinality"}
def uuid_value(value:E.Uuid) -> N.Value:
  E.Uuid{R.Bits64{a,b},R.Bits64{c,d}}=value
  N.IntArray{[a,b,c,d]}
def uuid_read(value:N.Value) -> Result<&2,&2,String,E.Uuid>:
  match value:
    case N.IntArray{a <> b <> c <> d <> Nil{}}: Done{E.Uuid{R.Bits64{a,b},R.Bits64{c,d}}}
    case _: Fail{"entity-membership:UUID word cardinality"}
def member_value(value:M.Member) -> N.Value:
  M.Member{dimension,id,key,order,box,uuid}=value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("id",N.Int{id}),member("key",key_value(key)),
    member("order",nat_value(order)),member("box",box_value(box)),member("uuid",uuid_value(uuid))]}
def member_read(value:N.Value) -> Result<&2,&2,String,M.Member>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{id}} <> N.Member{c,key} <>
      N.Member{d,order} <> N.Member{e,box} <> N.Member{f,uuid} <> Nil{}}:
      do Result<&2,&2,String,M.Member>:
        Check.guard(name(a,"dimension") && name(b,"id") && name(c,"key") && name(d,"order") && name(e,"box") && name(f,"uuid"),"member schema")
        k : M.SectionKey <- key_read(key)
        cursor : Nat <- nat_read(order)
        actual : A.AABB <- box_read(box)
        identity : E.Uuid <- uuid_read(uuid)
        return M.Member{string(dimension),id,k,cursor,actual,identity}
    case _: Fail{"entity-membership:member schema"}
def section_value(value:M.Section) -> N.Value:
  M.Section{dimension,key,visibility,ids}=value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("key",key_value(key)),
    member("visibility",visibility_value(visibility)),member("ids",N.IntArray{ids})]}
def section_read(value:N.Value) -> Result<&2,&2,String,M.Section>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,key} <> N.Member{c,visibility} <>
      N.Member{d,N.IntArray{ids}} <> Nil{}}:
      do Result<&2,&2,String,M.Section>:
        Check.guard(name(a,"dimension") && name(b,"key") && name(c,"visibility") && name(d,"ids"),"section schema")
        k : M.SectionKey <- key_read(key)
        status : M.Visibility <- visibility_read(visibility)
        return M.Section{string(dimension),k,status,ids}
    case _: Fail{"entity-membership:section schema"}
def chunk_value(value:M.Chunk) -> N.Value:
  M.Chunk{dimension,x,z,loaded,visibility}=value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("x",N.Int{x}),member("z",N.Int{z}),
    member("loaded",N.Int{Bool.to_u32(loaded)}),member("visibility",visibility_value(visibility))]}
def chunk_read(value:N.Value) -> Result<&2,&2,String,M.Chunk>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{x}} <> N.Member{c,N.Int{z}} <>
      N.Member{d,N.Int{loaded}} <> N.Member{e,visibility} <> Nil{}}:
      do Result<&2,&2,String,M.Chunk>:
        Check.guard(name(a,"dimension") && name(b,"x") && name(c,"z") && name(d,"loaded") && name(e,"visibility"),"chunk schema")
        observed : Bool <- bool_read(loaded)
        status : M.Visibility <- visibility_read(visibility)
        return M.Chunk{string(dimension),x,z,observed,status}
    case _: Fail{"entity-membership:chunk schema"}
def registration_value(value:M.Registration) -> N.Value:
  M.Registration{dimension,id}=value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("id",N.Int{id})]}
def registration_read(value:N.Value) -> Result<&2,&2,String,M.Registration>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{id}} <> Nil{}}:
      do Result<&2,&2,String,M.Registration>:
        Check.guard(name(a,"dimension") && name(b,"id"),"registration schema")
        return M.Registration{string(dimension),id}
    case _: Fail{"entity-membership:registration schema"}
def members_value(values:List<&2,M.Member>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: member_value(head) <> members_value(rest)
def sections_value(values:List<&2,M.Section>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: section_value(head) <> sections_value(rest)
def chunks_value(values:List<&2,M.Chunk>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: chunk_value(head) <> chunks_value(rest)
def registrations_value(values:List<&2,M.Registration>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: registration_value(head) <> registrations_value(rest)
def members_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,M.Member>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,M.Member>>:
        first : M.Member <- member_read(head)
        tail : List<&2,M.Member> <- members_read(rest)
        return first <> tail
def sections_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,M.Section>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,M.Section>>:
        first : M.Section <- section_read(head)
        tail : List<&2,M.Section> <- sections_read(rest)
        return first <> tail
def chunks_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,M.Chunk>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,M.Chunk>>:
        first : M.Chunk <- chunk_read(head)
        tail : List<&2,M.Chunk> <- chunks_read(rest)
        return first <> tail
def registrations_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,M.Registration>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,M.Registration>>:
        first : M.Registration <- registration_read(head)
        tail : List<&2,M.Registration> <- registrations_read(rest)
        return first <> tail
def root(value:M.View) -> N.Root:
  M.View{members,sections,chunks,tracked,ticked}=value
  N.Root{text("bendex:entity-membership"),N.Compound{[member("format",N.Int{1}),
    member("members",N.ListTag{10,members_value(members)}),member("sections",N.ListTag{10,sections_value(sections)}),
    member("chunks",N.ListTag{10,chunks_value(chunks)}),member("tracked",N.ListTag{10,registrations_value(tracked)}),
    member("ticked",N.ListTag{10,registrations_value(ticked)})]}}
def checked(+view:M.View) -> Result<&2,&2,String,M.View>:
  do Result<&2,&2,String,M.View>:
    Check.validate(view)
    return view
def root_read(value:N.Root) -> Result<&2,&2,String,M.View>:
  match value:
    case N.Root{label,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,N.ListTag{10,members}} <>
      N.Member{c,N.ListTag{10,sections}} <> N.Member{d,N.ListTag{10,chunks}} <>
      N.Member{e,N.ListTag{10,tracked}} <> N.Member{f,N.ListTag{10,ticked}} <> Nil{}}}:
      do Result<&2,&2,String,M.View>:
        Check.guard(name(label,"bendex:entity-membership") && name(a,"format") && name(b,"members") && name(c,"sections") &&
          name(d,"chunks") && name(e,"tracked") && name(f,"ticked"),"root schema")
        registered : List<&2,M.Member> <- members_read(members)
        entities : List<&2,M.Section> <- sections_read(sections)
        physical : List<&2,M.Chunk> <- chunks_read(chunks)
        observed : List<&2,M.Registration> <- registrations_read(tracked)
        scheduled : List<&2,M.Registration> <- registrations_read(ticked)
        checked(M.View{registered,entities,physical,observed,scheduled})
    case _: Fail{"entity-membership:root schema"}
def encoded(result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Done{bytes}: Done{bytes}
    case Fail{message}: Fail{"entity-membership:NBT:" ++ message}
def decoded(result:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,M.View>:
  match result:
    case Done{value}: root_read(value)
    case Fail{message}: Fail{"entity-membership:NBT:" ++ message}
def encode(limits:N.Limits,+view:M.View) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    Check.validate(view)
    encoded(N.encode_with(limits,root(view)))
def decode(limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,M.View>:
  decoded(N.decode_with(limits,bytes))
def encode_inspected(limits:N.Limits,result:M.State & M.View) -> M.State & Result<&2,&2,String,List<&2,U32>>:
  (state,view)=result
  (state,encode(limits,view))
def inspect_encode(limits:N.Limits,state:M.State) -> M.State & Result<&2,&2,String,List<&2,U32>>:
  encode_inspected(limits,Membership.inspect(state))
