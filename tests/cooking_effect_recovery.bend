import Base
import ../src/cooking_effect_delivery.bend as D
import ../src/cooking_effect_recovery.bend as R
import ../src/cooking_world_store.bend as S
import ../src/core.bend as C
import ../src/inventory.bend as I
import ../src/furnace_authority.bend as F
import ../src/nbt.bend as N

def point() -> C.Position: C.Position{"minecraft:the_nether",2147483648,4294967295,2147483647}
def components() -> String:
  "BendCraftComponents1\t64\t{\"text\":\"§😀\"}" ++ SCon{Chr{0},""}
def pending(+xp_bits:U32) -> List<&2,S.Effect>:
  [S.Drop{point(),0,I.InvEmpty{}},S.Drop{point(),2,I.InvStack{I.ItemKey{"minecraft:stone",components()},3}},
    S.Experience{point(),F.XpRequest{"minecraft:cooked_beef",3,0.5}},
    S.Experience{point(),F.XpRequest{"fixture:zero",2147483648,R.raw_float(2147483648)}},
    S.Experience{point(),F.XpRequest{"fixture:nan",4294967295,R.raw_float(xp_bits)}},
    S.Dirty{point()},S.BlockUpdate{point(),Nat.add(U32.to_nat(4294967295),1n)},S.BlockChange{point(),17n},
    S.OwnerReset{point()},S.Drop{point(),0,I.InvEmpty{}}]
def fixture(xp_bits:U32) -> List<&2,S.Effect>:
  S.OwnerReset{point()} <> S.BlockUpdate{point(),0n} <> S.BlockChange{point(),0n} <> pending(xp_bits)
def bytes_equal(a:List<&2,U32>,b:List<&2,U32>) -> Bool: R.equal_words(a,b)
def bytes_status_equal(a:Result<&2,&2,String,List<&2,U32>>,b:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}: bytes_equal(x,y)
    case _ _: False{}
def identical(a:List<&2,S.Effect>,b:List<&2,S.Effect>) -> Bool:
  bytes_status_equal(R.encode(N.default_limits(),a),R.encode(N.default_limits(),b))
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,3,"cooking effect guard failed: " ++ label)
    case True{}: IO.print("ok " ++ label)
def suffix(value:D.Outcome,xp_bits:U32) -> Bool:
  match value:
    case D.Outcome{effects,Fail{"cooking-effects:item-entity-and-level-rng-owner-required"}}: identical(effects,pending(xp_bits))
    case _: False{}
def refused(value:D.Outcome,+expected:String,+effect:S.Effect) -> Bool:
  match value:
    case D.Outcome{effects,Fail{message}}: String.eq(message,expected) && identical(effects,[effect])
    case _: False{}
def empty(value:D.Outcome) -> Bool:
  match value:
    case D.Outcome{Nil{},Done{Unit{}}}: True{}
    case _: False{}
def decoded(result:Result<&2,&2,String,List<&2,S.Effect>>,xp_bits:U32) -> Bool:
  match result:
    case Done{effects}: identical(effects,fixture(xp_bits))
    case Fail{message}: False{}
def encode_refused(value:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{bytes}: False{}
def decode_refused(value:Result<&2,&2,String,List<&2,S.Effect>>) -> Bool:
  match value:
    case Fail{message}: True{}
    case Done{effects}: False{}
def byte_text(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> Nil{}: U32.show(word)
    case word <> rest: U32.show(word) ++ "," ++ byte_text(rest)
def fixture_encoded(value:Result<&2,&2,String,List<&2,U32>>,xp_bits:U32) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,3,"cooking effect fixture encoding failed: " ++ message)
    case Done{+bytes}:
      do IO<Unit>:
        guard("ordered duplicate raw effect queue roundtrip",decoded(R.decode(N.default_limits(),bytes),xp_bits))
        guard("truncated recovery refuses",decode_refused(R.decode(N.default_limits(),List.take(&2,U32,bytes,10n))))
        IO.print("bytes " ++ byte_text(bytes))
def cases(+xp_bits:U32) -> IO(Unit):
  +xp : S.Effect = S.Experience{point(),F.XpRequest{"fixture:nan",4294967295,R.raw_float(xp_bits)}}
  +dirty : S.Effect = S.Dirty{point()}
  +update : S.Effect = S.BlockUpdate{point(),1n}
  +change : S.Effect = S.BlockChange{point(),1n}
  do IO<Unit>:
    guard("local marker and zero notifications acknowledge only safe prefix",suffix(D.deliver(fixture(xp_bits)),xp_bits))
    guard("empty item drop remains a real RNG-owner refusal",refused(D.deliver([S.Drop{point(),0,I.InvEmpty{}}]),"cooking-effects:item-entity-and-level-rng-owner-required",S.Drop{point(),0,I.InvEmpty{}}))
    guard("XP keeps raw uses rate and unavailable owner",refused(D.deliver([xp]),"cooking-effects:xp-orb-and-level-rng-owner-required",xp))
    guard("dirty keeps comparator publication intent",refused(D.deliver([dirty]),"cooking-effects:block-entity-and-comparator-publisher-owner-required",dirty))
    guard("nonzero block update keeps actual count",refused(D.deliver([update]),"cooking-effects:block-update-publisher-owner-required",update))
    guard("nonzero game event keeps actual count",refused(D.deliver([change]),"cooking-effects:game-event-publisher-owner-required",change))
    guard("all acknowledged local effects complete",empty(D.deliver([S.OwnerReset{point()},S.BlockChange{point(),0n},S.BlockUpdate{point(),0n}])))
    guard("empty effect delivery complete",empty(D.deliver([])))
    guard("byte budget refuses complete recovery encode",encode_refused(R.encode(N.Limits{16,32,10000},fixture(xp_bits))))
    guard("depth budget refuses complete recovery encode",encode_refused(R.encode(N.Limits{65536,1,10000},fixture(xp_bits))))
    guard("element budget refuses complete recovery encode",encode_refused(R.encode(N.Limits{65536,32,1},fixture(xp_bits))))
    fixture_encoded(R.encode(N.default_limits(),fixture(xp_bits)),xp_bits)
def loaded(value:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = value
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)
def read_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    bytes : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16777217)
    loaded(bytes)
def decoded_file(label:String,value:Result<&2,&2,String,List<&2,S.Effect>>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print("refused " ++ label)
    case Done{effects}: IO.print("accepted " ++ label)
def batch(paths:List<String>) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case +path <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- read_file(path)
        decoded_file(path,R.decode(N.default_limits(),bytes))
        batch(rest)
def cases_word(value:Maybe<&2,U32>) -> IO(Unit):
  match value:
    case Some{word}: cases(word)
    case None{}: IO.die(Unit,2,"Expected raw XP U32 word")
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "decode" <> paths: batch(paths)
    case exe <> "cases" <> word <> Nil{}: cases_word(U32.read(word))
    case _: IO.die(Unit,2,"Expected cases XP_WORD or decode FILE...")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
