import Base
import ../src/entity_membership_codec.bend as C
import ../src/entity_section_membership_model.bend as M
import ../src/entity_section_membership.bend as P
import ../src/local_player_effect_entities_codec.bend as Raw
import ../src/cooking_effect_entities_model.bend as E
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/geometry.bend as A
import ../src/nbt.bend as N

# The Python oracle defines the physical wire independently. These constructors
# exercise the actual full manager owner, including opaque words and all orders.
def nat_max() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(65535),Nat.add(U32.to_nat(4294967295),1n)),U32.to_nat(4294967295))
def nat_large() -> Nat:
  Nat.add(Nat.mul(256n,Nat.add(U32.to_nat(4294967295),1n)),7n)
def opaque_dimension() -> String:
  "fixture:" ++ SCon{Chr{0},"§😀" ++ SCon{Chr{57343},SCon{Chr{4294967295},""}}}
def key0() -> M.SectionKey: M.SectionKey{4194303,1048575,0}
def key1() -> M.SectionKey: M.SectionKey{0,0,4194303}
def key2() -> M.SectionKey: M.SectionKey{2097152,524288,4194303}
def box(+index:U32) -> A.AABB:
  A.AABB{F.F64{2146964020,U32.add(1450744508,index)},F.F64{2147483648,index},
    F.F64{1072693248,U32.add(1,index)},F.F64{4294486989,U32.add(270544960,index)},
    F.F64{2146435072,index},F.F64{1048576,U32.add(8,index)}}
def uuid(+index:U32) -> E.Uuid:
  E.Uuid{R.Bits64{U32.add(19088743,index),U32.add(2309737967,index)},
    R.Bits64{U32.sub(4275878552,index),U32.add(1985229328,index)}}
def members() -> List<&2,M.Member>:
  [M.Member{opaque_dimension(),4294967295,key0(),nat_max(),box(0),uuid(0)},
    M.Member{"minecraft:overworld",4294967295,key1(),nat_large(),box(1),uuid(0)},
    M.Member{opaque_dimension(),2147483648,key2(),0n,box(2),uuid(1)},
    M.Member{opaque_dimension(),2147483647,key0(),7n,box(3),uuid(2)},
    M.Member{"minecraft:overworld",2147483648,key1(),nat_large(),box(4),uuid(3)}]
def sections() -> List<&2,M.Section>:
  [M.Section{"minecraft:overworld",key1(),M.Ticking{},[2147483648,4294967295]},
    M.Section{opaque_dimension(),key0(),M.Tracked{},[2147483647,4294967295]},
    M.Section{opaque_dimension(),key2(),M.Hidden{},[2147483648]}]
def chunks() -> List<&2,M.Chunk>:
  [M.Chunk{"",2147483648,2147483647,False{},M.Ticking{}},
    M.Chunk{opaque_dimension(),4292870144,4294967295,True{},M.Hidden{}},
    M.Chunk{opaque_dimension(),4294967295,0,False{},M.Tracked{}},
    M.Chunk{"minecraft:overworld",0,4294967295,True{},M.Ticking{}}]
def tracking() -> List<&2,M.Registration>:
  [M.Registration{opaque_dimension(),2147483647},M.Registration{"minecraft:overworld",4294967295},
    M.Registration{opaque_dimension(),4294967295},M.Registration{"minecraft:overworld",2147483648}]
def ticking() -> List<&2,M.Registration>:
  [M.Registration{"minecraft:overworld",2147483648},M.Registration{"minecraft:overworld",4294967295}]
def fixture() -> M.View: M.View{members(),sections(),chunks(),tracking(),ticking()}
def empty() -> M.View: M.View{[],[],[],[],[]}
def duplicate_registry_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  M.View{m,s,c,List.append(&2,M.Registration,t,[M.Registration{opaque_dimension(),4294967295}]),k}
def duplicate_registry() -> M.View: duplicate_registry_view(fixture())
def malformed_key_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  match m:
    case Nil{}: M.View{[],s,c,t,k}
    case M.Member{d,id,key,order,b,u} <> rest:
      M.View{M.Member{d,id,M.SectionKey{4194304,1048575,0},order,b,u} <> rest,s,c,t,k}
def malformed_key() -> M.View: malformed_key_view(fixture())
def duplicate_uuid_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  match m:
    case Nil{}: M.View{[],s,c,t,k}
    case M.Member{d,id,key,order,b,u} <> rest:
      M.View{M.Member{d,id,key,order,b,uuid(2)} <> rest,s,c,t,k}
def duplicate_uuid() -> M.View: duplicate_uuid_view(fixture())
def reversed_ids_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  match s:
    case Nil{}: M.View{m,[],c,t,k}
    case M.Section{d,key,v,ids} <> rest:
      M.View{m,M.Section{d,key,v,[4294967295,2147483648]} <> rest,c,t,k}
def reversed_ids() -> M.View: reversed_ids_view(fixture())
def empty_section_ids_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  match s:
    case Nil{}: M.View{m,[],c,t,k}
    case M.Section{d,key,v,ids} <> rest:
      M.View{m,M.Section{d,key,v,[]} <> rest,c,t,k}
def empty_section_ids() -> M.View: empty_section_ids_view(fixture())
def masked_duplicate_chunk_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  M.View{m,s,List.append(&2,M.Chunk,c,[M.Chunk{opaque_dimension(),4194303,0,False{},M.Tracked{}}]),t,k}
def masked_duplicate_chunk() -> M.View: masked_duplicate_chunk_view(fixture())
def missing_chunk_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  M.View{m,s,[M.Chunk{"",2147483648,2147483647,False{},M.Ticking{}},
    M.Chunk{opaque_dimension(),4292870144,4294967295,True{},M.Hidden{}},
    M.Chunk{"minecraft:overworld",0,4294967295,True{},M.Ticking{}}],t,k}
def missing_chunk() -> M.View: missing_chunk_view(fixture())
def mismatched_visibility_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  M.View{m,s,[M.Chunk{"",2147483648,2147483647,False{},M.Ticking{}},
    M.Chunk{opaque_dimension(),4292870144,4294967295,True{},M.Hidden{}},
    M.Chunk{opaque_dimension(),4294967295,0,False{},M.Hidden{}},
    M.Chunk{"minecraft:overworld",0,4294967295,True{},M.Ticking{}}],t,k}
def mismatched_visibility() -> M.View: mismatched_visibility_view(fixture())
def missing_tracking_view(view:M.View) -> M.View:
  M.View{m,s,c,t,k}=view
  match t:
    case Nil{}: M.View{m,s,c,[],k}
    case head <> rest: M.View{m,s,c,rest,k}
def missing_tracking() -> M.View: missing_tracking_view(fixture())
def same_string(a:String,b:String) -> Bool: Raw.equal_words(Raw.words(a),Raw.words(b))
def same_double(a:F.F64,b:F.F64) -> Bool:
  F.F64{ah,al}=a
  F.F64{bh,bl}=b
  U32.is_eq(ah,bh) && U32.is_eq(al,bl)
def same_box(a:A.AABB,b:A.AABB) -> Bool:
  A.AABB{ax,ay,az,aw,ah,ad}=a
  A.AABB{bx,by,bz,bw,bh,bd}=b
  same_double(ax,bx) && same_double(ay,by) && same_double(az,bz) &&
    same_double(aw,bw) && same_double(ah,bh) && same_double(ad,bd)
def same_member(a:M.Member,b:M.Member) -> Bool:
  M.Member{ad,ai,ak,ao,ab,au}=a
  M.Member{bd,bi,bk,bo,bb,bu}=b
  same_string(ad,bd) && U32.is_eq(ai,bi) && P.key_eq(ak,bk) && Nat.is_eq(ao,bo) && same_box(ab,bb) && P.uuid_eq(au,bu)
def same_members(a:List<&2,M.Member>,b:List<&2,M.Member>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: same_member(x,y) && same_members(xs,ys)
    case _ _: False{}
def same_section(a:M.Section,b:M.Section) -> Bool:
  M.Section{ad,ak,av,ai}=a
  M.Section{bd,bk,bv,bi}=b
  same_string(ad,bd) && P.key_eq(ak,bk) && P.visibility_eq(av,bv) && Raw.equal_words(ai,bi)
def same_sections(a:List<&2,M.Section>,b:List<&2,M.Section>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: same_section(x,y) && same_sections(xs,ys)
    case _ _: False{}
def same_chunk(a:M.Chunk,b:M.Chunk) -> Bool:
  M.Chunk{ad,ax,az,al,av}=a
  M.Chunk{bd,bx,bz,bl,bv}=b
  same_string(ad,bd) && U32.is_eq(ax,bx) && U32.is_eq(az,bz) && P.bool_eq(al,bl) && P.visibility_eq(av,bv)
def same_chunks(a:List<&2,M.Chunk>,b:List<&2,M.Chunk>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: same_chunk(x,y) && same_chunks(xs,ys)
    case _ _: False{}
def same_registration(a:M.Registration,b:M.Registration) -> Bool:
  M.Registration{ad,ai}=a
  M.Registration{bd,bi}=b
  same_string(ad,bd) && U32.is_eq(ai,bi)
def same_registrations(a:List<&2,M.Registration>,b:List<&2,M.Registration>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: same_registration(x,y) && same_registrations(xs,ys)
    case _ _: False{}
def same_view(a:M.View,b:M.View) -> Bool:
  M.View{am,asections,ac,at,ak}=a
  M.View{bm,bsections,bc,bt,bk}=b
  same_members(am,bm) && same_sections(asections,bsections) && same_chunks(ac,bc) &&
    same_registrations(at,bt) && same_registrations(ak,bk)
def encode_refused(value:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{bytes}: False{}
def decode_refused(value:Result<&2,&2,String,M.View>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{view}: False{}
def same_bytes(a:Result<&2,&2,String,List<&2,U32>>,b:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}: Raw.equal_words(x,y)
    case _ _: False{}
def roundtrip_bytes(value:Result<&2,&2,String,M.View>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{view}: C.encode(N.default_limits(),view)
def roundtrip_view(expected:M.View,value:Result<&2,&2,String,M.View>) -> Bool:
  match value:
    case Fail{message}: False{}
    case Done{actual}: same_view(expected,actual)
def inspected_success(+expected:M.View,status:Result<&2,&2,String,List<&2,U32>>,value:M.State & M.View) -> Bool:
  (M.State{retained},actual)=value
  same_view(expected,retained) && same_view(expected,actual) && same_bytes(status,C.encode(N.default_limits(),expected))
def owner_success(expected:M.View,value:M.State & Result<&2,&2,String,List<&2,U32>>) -> Bool:
  (owner,status)=value
  inspected_success(expected,status,P.inspect(owner))
def inspected_refusal(+expected:M.View,status:Result<&2,&2,String,List<&2,U32>>,value:M.State & M.View) -> Bool:
  (M.State{retained},actual)=value
  same_view(expected,retained) && same_view(expected,actual) && encode_refused(status)
def owner_refusal(expected:M.View,value:M.State & Result<&2,&2,String,List<&2,U32>>) -> Bool:
  (owner,status)=value
  inspected_refusal(expected,status,P.inspect(owner))
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("ok " ++ label)
    case False{}: IO.die(Unit,3,"entity membership codec guard failed: " ++ label)
def byte_text(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> Nil{}: U32.show(word)
    case word <> rest: U32.show(word) ++ "," ++ byte_text(rest)
def cases_encoded(value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,"entity membership fixture encode failed: " ++ message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("complete raw membership View roundtrip",roundtrip_view(fixture(),C.decode(N.default_limits(),bytes)))
        guard("all five independent list orders roundtrip",same_bytes(Done{bytes},roundtrip_bytes(C.decode(N.default_limits(),bytes))))
        guard("decode byte budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16,512,1048576},bytes)))
        guard("decode depth budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16777216,1,1048576},bytes)))
        guard("decode element budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16777216,512,1},bytes)))
        guard("truncated complete snapshot refuses",decode_refused(C.decode(N.default_limits(),List.take(&2,U32,bytes,10n))))
        guard("trailing complete snapshot refuses",decode_refused(C.decode(N.default_limits(),List.append(&2,U32,bytes,[0]))))
        IO.print("bytes " ++ byte_text(bytes))
def cases() -> IO(Unit):
  +view=fixture()
  +invalid=duplicate_registry()
  +bad_key=malformed_key()
  do IO<Unit>:
    guard("encode byte budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16,512,1048576},view)))
    guard("encode depth budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16777216,1,1048576},view)))
    guard("encode element budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16777216,512,1},view)))
    guard("empty five-list View roundtrip",roundtrip_view(empty(),Result.bind(&2,&2,String,List<&2,U32>,M.View,C.encode(N.default_limits(),empty()),bytes => C.decode(N.default_limits(),bytes))))
    guard("public inspect encode retains complete manager and actual snapshot",owner_success(view,C.inspect_encode(N.default_limits(),M.State{view})))
    guard("invalid registry encode retains complete manager",owner_refusal(invalid,C.inspect_encode(N.default_limits(),M.State{invalid})))
    guard("invalid packed-key encode retains complete manager",owner_refusal(bad_key,C.inspect_encode(N.default_limits(),M.State{bad_key})))
    guard("duplicate UUID encode retains complete manager",owner_refusal(duplicate_uuid(),C.inspect_encode(N.default_limits(),M.State{duplicate_uuid()})))
    guard("section ID order refusal retains complete manager",owner_refusal(reversed_ids(),C.inspect_encode(N.default_limits(),M.State{reversed_ids()})))
    guard("empty section refusal retains complete manager",owner_refusal(empty_section_ids(),C.inspect_encode(N.default_limits(),M.State{empty_section_ids()})))
    guard("masked chunk duplicate refusal retains complete manager",owner_refusal(masked_duplicate_chunk(),C.inspect_encode(N.default_limits(),M.State{masked_duplicate_chunk()})))
    guard("missing chunk refusal retains complete manager",owner_refusal(missing_chunk(),C.inspect_encode(N.default_limits(),M.State{missing_chunk()})))
    guard("visibility mismatch refusal retains complete manager",owner_refusal(mismatched_visibility(),C.inspect_encode(N.default_limits(),M.State{mismatched_visibility()})))
    guard("missing tracking refusal retains complete manager",owner_refusal(missing_tracking(),C.inspect_encode(N.default_limits(),M.State{missing_tracking()})))
    guard("byte-budget encode refusal retains complete manager",owner_refusal(view,C.inspect_encode(N.Limits{16,512,1048576},M.State{view})))
    guard("depth-budget encode refusal retains complete manager",owner_refusal(view,C.inspect_encode(N.Limits{16777216,1,1048576},M.State{view})))
    guard("element-budget encode refusal retains complete manager",owner_refusal(view,C.inspect_encode(N.Limits{16777216,512,1},M.State{view})))
    cases_encoded(C.encode(N.default_limits(),view))
def loaded(value:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status)=value
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)
def read_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16777217)
    loaded(result)
def printed(label:String,value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,"decoded membership cannot reencode: " ++ label ++ ": " ++ message)
    case Done{bytes}: IO.print("accepted " ++ label ++ " " ++ byte_text(bytes))
def decoded_file(label:String,value:Result<&2,&2,String,M.View>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{view}: printed(label,C.encode(N.default_limits(),view))
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- read_file(path)
        decoded_file(path,C.decode(N.default_limits(),bytes))
        batch(rest)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "cases" <> Nil{}: cases()
    case exe <> "decode" <> paths: batch(paths)
    case _: IO.die(Unit,2,"Expected cases or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
