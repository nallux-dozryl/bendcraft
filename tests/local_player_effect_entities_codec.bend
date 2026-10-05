import Base
import ../src/local_player_effect_entities_codec.bend as C
import ../src/cooking_effect_entities_model.bend as E
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ../src/player_look.bend as P
import ../src/inventory.bend as I
import ../src/nbt.bend as N

def nat_max() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(65535),Nat.add(U32.to_nat(4294967295),1n)),U32.to_nat(4294967295))
def nat_large() -> Nat:
  Nat.add(Nat.mul(256n,Nat.add(U32.to_nat(4294967295),1n)),7n)
def components() -> String:
  "BendCraftComponents1\t64\t{\"text\":\"§😀\"}" ++ SCon{Chr{0},SCon{Chr{55296},""}}
def fields(+index:U32,+nan:U32) -> V.Fields:
  V.Fields{
    V.Vec3{F.F64{2146964020,U32.add(1450744508,index)},F.F64{2147483648,index},F.F64{1072693248,U32.add(1,index)}},
    V.Vec3{F.F64{3220176896,U32.add(2,index)},F.F64{0,U32.add(3,index)},F.F64{2146435072,index}},
    V.Vec3{F.F64{1073741824,U32.add(4,index)},F.F64{4294486989,U32.add(270544960,index)},F.F64{1074266112,U32.add(5,index)}},
    V.Vec3{F.F64{1074790400,U32.add(6,index)},F.F64{3222536192,U32.add(7,index)},F.F64{1048576,U32.add(8,index)}},
    P.State{C.raw_float(nan),C.raw_float(2147483648),C.raw_float(U32.add(1058157654,index)),C.raw_float(U32.add(3211084577,index))},
    C.raw_float(2143363909),C.raw_float(2147483648),F.F64{2146981496,U32.add(2596069104,index)},
    U32.is_eq(index,1),U32.add(2147483649,index),U32.sub(4294967294,index),U32.sub(2147483647,index),True{},U32.is_eq(index,1)}
def common0(nan:U32) -> E.Common:
  E.Common{"minecraft:the_nether",4294967295,R.Bits64{19088743,2309737967},R.Bits64{4275878552,1985229328},
    R.Legacy{R.Bits64{2863311530,1431655765}},fields(0,nan),2147483653,True{},False{},True{},nat_max()}
def common1(nan:U32) -> E.Common:
  E.Common{"fixture:" ++ SCon{Chr{0},"§😀" ++ SCon{Chr{57343},""}},2147483648,
    R.Bits64{19088744,2309737968},R.Bits64{4275878551,1985229329},
    R.Xoroshiro{R.Bits64{286397204,353769240},R.Bits64{555885348,623257384}},
    fields(1,nan),2147483654,False{},False{},True{},nat_large()}
def common2(nan:U32) -> E.Common:
  E.Common{"minecraft:overworld",2147483647,R.Bits64{19088745,2309737969},R.Bits64{4275878550,1985229330},
    R.Legacy{R.Bits64{4294967295,2147483648}},fields(2,nan),2147483655,True{},True{},False{},0n}
def item(+nan:U32) -> E.Record:
  E.Item{common0(nan),I.InvStack{I.ItemKey{"minecraft:stone",components()},4294967295},2147483649,4294967293,2147483647,
    Some{E.Uuid{R.Bits64{2711790500,2779162536},R.Bits64{2981278644,3048650680}}},None{},C.raw_float(nan)}
def orb(nan:U32) -> E.Record:
  E.Orb{common1(nan),4294967295,2147483650,2147483646,0,
    Some{E.Uuid{R.Bits64{3250766788,3318138824},R.Bits64{3520254932,3587626968}}}}
def empty_item(nan:U32) -> E.Record:
  E.Item{common2(nan),I.InvEmpty{},0,2147483647,4294967295,None{},
    Some{E.Uuid{R.Bits64{3789743076,3857115112},R.Bits64{4059231220,4126603256}}},C.raw_float(2147483648)}
def untracked_orb(nan:U32) -> E.Record:
  E.Orb{common2(nan),0,4294967295,0,2147483648,None{}}
def records(+nan:U32) -> List<&2,E.Record>:
  +a = item(nan)
  +b = orb(nan)
  [a,b,a,empty_item(nan),untracked_orb(nan),b]
def with_records(values:List<&2,E.Record>) -> E.View:
  E.View{R.Xoroshiro{R.Bits64{16909060,84281096},R.Bits64{151653132,219025168}},
    R.Bits64{4275878552,1985229328},4294967295,nat_max(),values}
def fixture(nan:U32) -> E.View: with_records(records(nan))
def same(a:Result<&2,&2,String,List<&2,U32>>,b:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}: C.equal_words(x,y)
    case _ _: False{}
def encode_refused(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{bytes}: False{}
def decode_refused(result:Result<&2,&2,String,E.View>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}
def roundtrip_bytes(result:Result<&2,&2,String,E.View>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: C.encode(N.default_limits(),value)
def inspected(result:E.State & E.View) -> E.View:
  (owner,snapshot) = result
  snapshot
def installed(value:E.View) -> E.View: inspected(E.inspect(E.install(value)))
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("ok " ++ label)
    case False{}: IO.die(Unit,3,"effect entity codec guard failed: " ++ label)
def byte_text(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> Nil{}: U32.show(word)
    case word <> rest: U32.show(word) ++ "," ++ byte_text(rest)
def cases_encoded(result:Result<&2,&2,String,List<&2,U32>>,+nan:U32) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,3,"effect entity fixture encode failed: " ++ message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("complete raw state and duplicate ordered records roundtrip",same(Done{bytes},roundtrip_bytes(C.decode(N.default_limits(),bytes))))
        guard("one affine install and inspect retain complete snapshot",same(Done{bytes},C.encode(N.default_limits(),installed(fixture(nan)))))
        guard("decode byte budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16,512,1048576},bytes)))
        guard("decode depth budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16777216,1,1048576},bytes)))
        guard("decode element budget refuses complete snapshot",decode_refused(C.decode(N.Limits{16777216,512,1},bytes)))
        guard("truncated complete snapshot refuses",decode_refused(C.decode(N.default_limits(),List.take(&2,U32,bytes,10n))))
        guard("trailing complete snapshot refuses",decode_refused(C.decode(N.default_limits(),List.append(&2,U32,bytes,[0]))))
        IO.print("bytes " ++ byte_text(bytes))
def cases(+nan:U32) -> IO(Unit):
  +empty = C.encode(N.default_limits(),with_records([]))
  do IO<Unit>:
    guard("encode byte budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16,512,1048576},fixture(nan))))
    guard("encode depth budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16777216,1,1048576},fixture(nan))))
    guard("encode element budget refuses complete snapshot",encode_refused(C.encode(N.Limits{16777216,512,1},fixture(nan))))
    guard("empty records retain actual RNG and owner cursors",same(empty,roundtrip_bytes(Result.bind(&2,&2,String,List<&2,U32>,E.View,empty,bytes => C.decode(N.default_limits(),bytes)))))
    cases_encoded(C.encode(N.default_limits(),fixture(nan)),nan)
def loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)
def read_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16777217)
    loaded(result)
def printed(label:String,result:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,3,"decoded entity snapshot cannot reencode: " ++ label ++ ": " ++ message)
    case Done{bytes}: IO.print("accepted " ++ label ++ " " ++ byte_text(bytes))
def decoded_file(label:String,result:Result<&2,&2,String,E.View>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{value}: printed(label,C.encode(N.default_limits(),value))
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- read_file(path)
        decoded_file(path,C.decode(N.default_limits(),bytes))
        batch(rest)
def cases_word(value:Maybe<&2,U32>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit,2,"Expected raw F32 U32 word")
    case Some{word}: cases(word)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "cases" <> word <> Nil{}: cases_word(U32.read(word))
    case exe <> "decode" <> paths: batch(paths)
    case _: IO.die(Unit,2,"Expected cases NAN_WORD or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
