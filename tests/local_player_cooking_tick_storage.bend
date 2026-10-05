import Base
import ../src/local_player_cooking_tick_storage.bend as S
import ../src/local_player_effect_tick_recovery.bend as Q
import ../src/local_player_effect_tick_recovery_codec.bend as C
import ../src/item_entity_tick_model.bend as T
import ../src/random.bend as R
import ../src/nbt.bend as N
import ../src/local_player_effect_entities_codec.bend as Raw
import ./local_player_effect_tick_recovery.bend as Fixture
import ./local_player_effect_entities_codec.bend as Entities
import ../src/entity_section_membership_model.bend as Manager

def clocks() -> List<&2,R.Bits64>:
  [R.Bits64{4294967295,0},R.Bits64{2147483648,4294967295},R.Bits64{0,0},R.Bits64{4294967295,0}]
def fixture() -> S.Stored: S.Stored{Fixture.fixture(),clocks(),None{}}
def empty_manager_fixture() -> S.Stored:
  S.Stored{Fixture.fixture(),clocks(),Some{Manager.View{[],[],[],[],[]}}}
def payload_encoded(limits:N.Limits,value:Result<&2,&2,String,S.Payload>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{payload}: N.encode_with(limits,N.Root{Raw.text("fixture:local-player-cooking-tick-storage"),S.payload_value(payload)})
def encode(+limits:N.Limits,value:S.Stored) -> Result<&2,&2,String,List<&2,U32>>:
  payload_encoded(limits,S.encode(limits,value))
def root_read(value:N.Root) -> Result<&2,&2,String,S.Stored>:
  match value:
    case N.Root{n,value}:
      do Result<&2,&2,String,S.Stored>:
        Raw.guard(Raw.name(n,"fixture:local-player-cooking-tick-storage"),"tick storage fixture root")
        S.payload_read(N.default_limits(),value)
def decode(bytes:List<&2,U32>) -> Result<&2,&2,String,S.Stored>:
  Result.bind(&2,&2,String,N.Root,S.Stored,N.decode_with(N.default_limits(),bytes),root_read)
def reencode(value:Result<&2,&2,String,S.Stored>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{stored}: encode(N.default_limits(),stored)
def inspected_value(result:T.State & S.Stored) -> S.Stored:
  (state,stored) = result
  stored
def inspect_again(result:T.State & S.Stored) -> S.Stored:
  (state,S.Stored{prior,+inputs,+membership}) = result
  inspected_value(S.inspect(state,inputs,membership))
def restored_encode(value:Result<&2,&1,String,S.Restored>) -> Result<&2,&2,String,List<&2,U32>>:
  match value:
    case Fail{message}: Fail{message}
    case Done{S.Restored{state,inputs,membership}}: encode(N.default_limits(),inspect_again(S.inspect(state,inputs,membership)))
def restore_refused(value:Result<&2,&1,String,S.Restored>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{owner}: False{}
def decode_refused(value:Result<&2,&2,String,S.Stored>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{stored}: False{}
def availability(value:S.Stored) -> Bool:
  S.Stored{Q.Recovery{+entities,+runtimes,+sound},inputs,membership} = value
  Fixture.runtime_refused(Q.require_runtimes(Q.Recovery{entities,runtimes,sound})) &&
    Fixture.sound_refused(Q.require_sound(Q.Recovery{entities,runtimes,sound}))
def legacy_decoded(value:Result<&2,&2,String,S.Stored>) -> Bool:
  match value:
    case Fail{message}: False{}
    case Done{stored}: availability(stored)
def legacy_read(value:Result<&2,&2,String,S.Payload>) -> Bool:
  match value:
    case Fail{message}: False{}
    case Done{S.Payload{bytes,inputs}}: legacy_decoded(S.decode(N.default_limits(),bytes,inputs))
def guard(label:String,valid:Bool) -> IO(Unit): Fixture.guard(label,valid)
def cases_encoded(value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("full recovery and remaining clock words roundtrip",Fixture.encoded_same(Done{bytes},reencode(decode(bytes))))
        guard("sole owner and clock inputs survive repeated inspect",Fixture.encoded_same(Done{bytes},restored_encode(S.restore(fixture()))))
        guard("physical component trailing bytes refuse",decode_refused(decode(List.append(&2,U32,bytes,[0]))))
        IO.print("bytes " ++ Entities.byte_text(bytes))
def clock_words(values:List<&2,R.Bits64>) -> List<&2,U32>:
  match values:
    case Nil{}: []
    case R.Bits64{hi,lo} <> rest: hi <> lo <> clock_words(rest)
def cases() -> IO(Unit):
  do IO<Unit>:
    guard("constructor clock duplicates and order retained",Raw.equal_words(
      [4294967295,0,2147483648,4294967295,0,0,4294967295,0],
      clock_words(S.clocks_read(S.clocks_value(clocks())))))
    guard("legacy projection retains unavailable runtime and sound",legacy_read(S.encode(N.default_limits(),S.legacy(Entities.fixture(2143293969),clocks()))))
    guard("legacy cannot restore guessed runtime",restore_refused(S.restore(S.legacy(Entities.fixture(2143293969),clocks()))))
    guard("clock field must be LongArray",decode_refused(S.decode_fields(N.default_limits(),[],N.IntArray{[]})))
    guard("known recovery cannot be replaced by empty entity bytes",decode_refused(S.decode(N.default_limits(),[],S.clocks_value(clocks()))))
    guard("noncanonical runtime tail refuses storage encode",Fixture.encode_refused(encode(N.default_limits(),S.Stored{Fixture.noncanonical(),clocks(),None{}})))
    guard("storage encode byte limit refuses",Fixture.encode_refused(encode(N.Limits{16,512,1048576},fixture())))
    guard("storage encode depth limit refuses",Fixture.encode_refused(encode(N.Limits{16777216,1,1048576},fixture())))
    guard("storage encode element limit refuses",Fixture.encode_refused(encode(N.Limits{16777216,512,1},fixture())))
    guard("known empty manager remains distinct from unavailable",Bool.not(Fixture.encoded_same(encode(N.default_limits(),fixture()),encode(N.default_limits(),empty_manager_fixture()))))
    guard("known empty manager survives full restoration as data",Fixture.encoded_same(encode(N.default_limits(),empty_manager_fixture()),restored_encode(S.restore(empty_manager_fixture()))))
    guard("aggregate envelope bound refuses individually fitting nested images",Fixture.encode_refused(encode(N.Limits{9700,512,1048576},empty_manager_fixture())))
    cases_encoded(encode(N.default_limits(),fixture()))
def printed(label:String,value:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,"storage reencode failed: " ++ message)
    case Done{bytes}: IO.print("accepted " ++ label ++ " " ++ Entities.byte_text(bytes))
def decoded(label:String,value:Result<&2,&2,String,S.Stored>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{stored}: printed(label,encode(N.default_limits(),stored))
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- Entities.read_file(path)
        decoded(path,decode(bytes))
        batch(rest)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "cases" <> Nil{}: cases()
    case exe <> "decode" <> paths: batch(paths)
    case _: IO.die(Unit,2,"Expected cases or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
