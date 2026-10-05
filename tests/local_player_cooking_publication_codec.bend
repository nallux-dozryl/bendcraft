import Base
import ../src/local_player_cooking_publication_codec.bend as P
import ../src/cooking_effect_publication_journal.bend as J
import ../src/cooking_world_bindings.bend as B
import ../src/cooking_recipe.bend as Recipe
import ../src/campfire_authority.bend as Camp
import ../src/core.bend as C
import ../src/nbt.bend as N

def large() -> Nat: Nat.add(Nat.mul(256n,Nat.add(4294967295n,1n)),7n)
def raw_block() -> String:
  "fixture:" ++ SCon{Chr{0},"§😀" ++ SCon{Chr{55296},SCon{Chr{57343},""}}}
def counters() -> Map<&2,Nat>:
  MNode{358n,
    MNode{823n,MNode{824n,MLeaf{"minecraft:overworld/0/0/0",0n},
      MLeaf{"minecraft:overworld/0/0/1",large()}},MLeaf{"minecraft:overworld/0/0/2",1n}},
    MLeaf{"minecraft:the_nether/4294967295/2147483648/2147483647",J.maximum_sequence()}}
def position() -> C.Position:
  C.Position{"minecraft:the_nether",4294967295,2147483648,2147483647}
def target() -> J.Chunk: J.Chunk{"minecraft:the_nether",4294967295,134217727}
def source() -> J.Source:
  J.Source{position(),B.Binding{4294967294,raw_block(),B.Campfire{Camp.Soul{}},True{},2147483648,4294967294},J.maximum_sequence()}
def recent() -> J.Receipt: J.Receipt{position(),source(),target(),J.maximum_sequence()}
def dirty() -> List<&2,J.DirtyChunk>:
  [J.DirtyChunk{target(),J.maximum_sequence()},J.DirtyChunk{J.Chunk{"minecraft:overworld",16,4294967295},large()}]
def fixture() -> P.Recovery: P.Recovery{counters(),J.View{J.maximum_sequence(),dirty(),Some{recent()}}}
def empty() -> P.Recovery: P.Recovery{MTip{},J.View{0n,[],None{}}}
def same(a:Result<&2,&2,String,List<&2,U32>>,b:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}: P.equal_words(x,y)
    case _ _: False{}
def encode_refused(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{bytes}: False{}
def decode_refused(result:Result<&2,&2,String,P.Recovery>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}
def roundtrip(result:Result<&2,&2,String,P.Recovery>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: P.encode(N.default_limits(),value)
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("ok " ++ label)
    case False{}: IO.die(Unit,3,"publication codec guard failed: " ++ label)
def byte_text(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> Nil{}: U32.show(word)
    case word <> rest: U32.show(word) ++ "," ++ byte_text(rest)
def encoded(result:Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,3,"publication fixture encode failed: " ++ message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("complete tree and raw source roundtrip",same(Done{bytes},roundtrip(P.decode(N.default_limits(),bytes))))
        guard("exact byte depth element bounds accept",same(Done{bytes},P.encode(N.Limits{2161,6,53},fixture())) && same(Done{bytes},roundtrip(P.decode(N.Limits{2161,6,53},bytes))))
        guard("one byte below encode bound refuses",encode_refused(P.encode(N.Limits{2160,512,1048576},fixture())))
        guard("one byte below decode bound refuses",decode_refused(P.decode(N.Limits{2160,512,1048576},bytes)))
        guard("one level below encode bound refuses",encode_refused(P.encode(N.Limits{16777216,5,1048576},fixture())))
        guard("one level below decode bound refuses",decode_refused(P.decode(N.Limits{16777216,5,1048576},bytes)))
        guard("one element below encode bound refuses",encode_refused(P.encode(N.Limits{16777216,512,52},fixture())))
        guard("one element below decode bound refuses",decode_refused(P.decode(N.Limits{16777216,512,52},bytes)))
        guard("decode byte budget refuses",decode_refused(P.decode(N.Limits{16,512,1048576},bytes)))
        guard("decode depth budget refuses",decode_refused(P.decode(N.Limits{16777216,1,1048576},bytes)))
        guard("decode element budget refuses",decode_refused(P.decode(N.Limits{16777216,512,1},bytes)))
        guard("truncated input refuses",decode_refused(P.decode(N.default_limits(),List.take(&2,U32,bytes,10n))))
        guard("trailing input refuses",decode_refused(P.decode(N.default_limits(),List.append(&2,U32,bytes,[0]))))
        IO.print("bytes " ++ byte_text(bytes))
def cases() -> IO(Unit):
  +blank = P.encode(N.default_limits(),empty())
  do IO<Unit>:
    guard("encode byte budget refuses",encode_refused(P.encode(N.Limits{16,512,1048576},fixture())))
    guard("encode depth budget refuses",encode_refused(P.encode(N.Limits{16777216,1,1048576},fixture())))
    guard("encode element budget refuses",encode_refused(P.encode(N.Limits{16777216,512,1},fixture())))
    guard("empty owner roundtrip",same(blank,roundtrip(Result.bind(&2,&2,String,List<&2,U32>,P.Recovery,blank,bytes => P.decode(N.default_limits(),bytes)))))
    guard("empty trie branch refuses",encode_refused(P.encode(N.default_limits(),P.Recovery{MNode{358n,MTip{},counters()},J.View{0n,[],None{}}})))
    guard("duplicate trie key refuses",encode_refused(P.encode(N.default_limits(),P.Recovery{MNode{824n,MLeaf{"minecraft:overworld/0/0/0",1n},MLeaf{"minecraft:overworld/0/0/0",2n}},J.View{0n,[],None{}}})))
    guard("noncanonical position key refuses",encode_refused(P.encode(N.default_limits(),P.Recovery{MLeaf{"minecraft:overworld/00/0/0",1n},J.View{0n,[],None{}}})))
    guard("missing latest receipt refuses",encode_refused(P.encode(N.default_limits(),P.Recovery{counters(),J.View{1n,[],None{}}})))
    guard("duplicate dirty chunk refuses",encode_refused(P.encode(N.default_limits(),P.Recovery{counters(),J.View{J.maximum_sequence(),[J.DirtyChunk{target(),1n},J.DirtyChunk{target(),2n}],Some{recent()}}})))
    encoded(P.encode(N.default_limits(),fixture()))
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
    case Fail{message}: IO.die(Unit,3,"publication snapshot cannot reencode: " ++ label ++ ": " ++ message)
    case Done{bytes}: IO.print("accepted " ++ label ++ " " ++ byte_text(bytes))
def decoded(label:String,result:Result<&2,&2,String,P.Recovery>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{value}: printed(label,P.encode(N.default_limits(),value))
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- read_file(path)
        decoded(path,P.decode(N.default_limits(),bytes))
        batch(rest)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "cases" <> Nil{}: cases()
    case exe <> "decode" <> paths: batch(paths)
    case _: IO.die(Unit,2,"Expected cases or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
