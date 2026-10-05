import Base
import ../src/local_player_effect_tick_recovery.bend as Q
import ../src/local_player_effect_tick_recovery_codec.bend as C
import ../src/local_player_effect_entities_codec.bend as EC
import ../src/item_entity_tick_model.bend as T
import ../src/cooking_effect_entities_model.bend as E
import ../src/random.bend as R
import ../src/vanilla_entity_fields.bend as V
import ../src/f64.bend as F
import ../src/support.bend as S
import ../src/travel.bend as Travel
import ../src/nbt.bend as N
import ./local_player_effect_entities_codec.bend as Fixtures

def vector(+index:U32) -> V.Vec3:
  V.Vec3{F.F64{2146964020,U32.add(1450744508,index)},F.F64{2147483648,index},F.F64{4294446029,U32.add(270544960,index)}}
def fluid(+index:U32) -> T.Fluid:
  T.Fluid{F.F64{2146435072,index},vector(U32.add(index,10)),U32.sub(4294967295,index),U32.is_eq(index,1)}
def last_position(index:U32) -> Maybe<&2,V.Vec3>:
  match index:
    case 0: None{}
    case _: Some{vector(index)}
def support(index:U32) -> S.State:
  match index:
    case 0: S.State{None{},True{}}
    case _: S.State{Some{Travel.BlockPos{4294967295,2147483648,2147483647}},False{}}
def movement(+index:U32) -> T.Movement:
  T.Movement{vector(index),vector(U32.add(index,1)),vector(U32.add(index,2))}
def runtime(+index:U32) -> T.Runtime:
  T.Runtime{T.Physical{True{},False{},True{},False{},True{},False{},True{},vector(U32.add(index,20))},
    T.BaseState{U32.sub(4294967295,index),U32.add(2147483648,index),True{},False{},True{},False{},True{},False{},True{},False{},
      last_position(index),vector(U32.add(index,30))},
    T.Fluids{fluid(0),fluid(1),False{},True{},False{}},
    [movement(index),movement(U32.add(index,3)),movement(index)],
    [movement(U32.add(index,6)),movement(U32.add(index,9))],support(index),[]}
def entries() -> List<&2,T.RuntimeEntry>:
  [T.RuntimeEntry{4294967295,runtime(0)},T.RuntimeEntry{2147483648,runtime(1)},T.RuntimeEntry{4294967295,runtime(0)}]
def fixture() -> Q.Recovery:
  Q.Recovery{Fixtures.fixture(2143293969),Some{entries()},Some{R.Legacy{R.Bits64{65535,4294967295}}}}
def empty() -> Q.Recovery:
  Q.Recovery{Fixtures.with_records([]),Some{[]},None{}}
def encoded_same(a:Result<&2,&2,String,List<&2,U32>>,b:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  Fixtures.same(a,b)
def encode_refused(value:Result<&2,&2,String,List<&2,U32>>) -> Bool: Fixtures.encode_refused(value)
def decode_refused(value:Result<&2,&2,String,Q.Recovery>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{snapshot}: False{}
def runtime_refused(value:Result<&2,&2,String,List<&2,T.RuntimeEntry>>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{entries}: False{}
def sound_refused(value:Result<&2,&2,String,R.Source>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{source}: False{}
def restore_refused(value:Result<&2,&1,String,T.State>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{state}: False{}
def reencode(value:Result<&2,&2,String,Q.Recovery>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{snapshot}: C.encode(N.default_limits(),snapshot)
def inspect_snapshot(result:T.State & Q.Recovery) -> Q.Recovery:
  (state,snapshot) = result
  snapshot
def inspect_again(result:T.State & Q.Recovery) -> Q.Recovery:
  (state,prior) = result
  inspect_snapshot(Q.inspect(state))
def restore_inspected(value:Result<&2,&1,String,T.State>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{state}: C.encode(N.default_limits(),inspect_again(Q.inspect(state)))
def noncanonical_runtime(value:T.Runtime) -> Q.Recovery:
  T.Runtime{p,b,f,q,m,s,tail} = value
  Q.Recovery{Fixtures.with_records([]),Some{[T.RuntimeEntry{7,T.Runtime{p,b,f,q,m,s,[runtime(1)]}}]},None{}}
def noncanonical() -> Q.Recovery: noncanonical_runtime(runtime(0))
def retained_noncanonical_again(result:T.State & Q.Recovery,encoded:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case (state,Q.Recovery{entities,Some{T.RuntimeEntry{id,T.Runtime{p,b,f,q,m,s,tail}} <> Nil{}},sound}):
      encode_refused(encoded) && Bool.not(List.is_empty(&2,T.Runtime,tail))
    case _: False{}
def retained_noncanonical(result:T.State & Q.Recovery) -> Bool:
  (state,snapshot) = result
  retained_noncanonical_again(Q.inspect(state),C.encode(N.default_limits(),snapshot))
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("ok " ++ label)
    case False{}: IO.die(Unit,3,"effect tick recovery guard failed: " ++ label)
def cases_encoded(value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("complete raw runtime and separate sound roundtrip",encoded_same(Done{bytes},reencode(C.decode(N.default_limits(),bytes))))
        guard("sole entity owner survives restore and repeated inspect",encoded_same(Done{bytes},restore_inspected(Q.restore(fixture()))))
        guard("decode byte limit refuses",decode_refused(C.decode(N.Limits{16,512,1048576},bytes)))
        guard("decode depth limit refuses",decode_refused(C.decode(N.Limits{16777216,1,1048576},bytes)))
        guard("decode element limit refuses",decode_refused(C.decode(N.Limits{16777216,512,1},bytes)))
        guard("truncated snapshot refuses",decode_refused(C.decode(N.default_limits(),List.take(&2,U32,bytes,10n))))
        guard("trailing snapshot refuses",decode_refused(C.decode(N.default_limits(),List.append(&2,U32,bytes,[0]))))
        IO.print("bytes " ++ Fixtures.byte_text(bytes))
def retained_noncanonical_restored(value:Result<&2,&1,String,T.State>) -> Bool:
  match value:
    case Fail{message}: False{}
    case Done{state}: retained_noncanonical(Q.inspect(state))
def cases() -> IO(Unit):
  +legacy = Q.legacy(Fixtures.fixture(2143293969))
  do IO<Unit>:
    guard("encode byte limit refuses",encode_refused(C.encode(N.Limits{16,512,1048576},fixture())))
    guard("encode depth limit refuses",encode_refused(C.encode(N.Limits{16777216,1,1048576},fixture())))
    guard("encode element limit refuses",encode_refused(C.encode(N.Limits{16777216,512,1},fixture())))
    guard("old snapshot has no runtime authority",runtime_refused(Q.require_runtimes(legacy)))
    guard("old snapshot has no sound authority",sound_refused(Q.require_sound(legacy)))
    guard("old snapshot cannot restore guessed runtimes",restore_refused(Q.restore(legacy)))
    guard("known empty runtime restores without invented sound",encoded_same(C.encode(N.default_limits(),empty()),restore_inspected(Q.restore(empty()))))
    guard("known empty runtime differs from unavailable",Bool.not(encoded_same(C.encode(N.default_limits(),empty()),C.encode(N.default_limits(),Q.legacy(Fixtures.with_records([]))))))
    guard("noncanonical tail refuses while original owner survives",retained_noncanonical_restored(Q.restore(noncanonical())))
    cases_encoded(C.encode(N.default_limits(),fixture()))
def printed(label:String,value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,"reencode failed: " ++ message)
    case Done{bytes}: IO.print("accepted " ++ label ++ " " ++ Fixtures.byte_text(bytes))
def decoded(label:String,value:Result<&2,&2,String,Q.Recovery>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{snapshot}: printed(label,C.encode(N.default_limits(),snapshot))
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- Fixtures.read_file(path)
        decoded(path,C.decode(N.default_limits(),bytes))
        batch(rest)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "cases" <> Nil{}: cases()
    case exe <> "decode" <> paths: batch(paths)
    case _: IO.die(Unit,2,"Expected cases or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
