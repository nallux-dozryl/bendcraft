import Base
import ../src/worldgen_md5.bend as M
import ../src/worldgen_seed.bend as WS
import ../src/random.bend as R
import ../src/nbt.bend as N

def number_result(value:Maybe<&2,U32>) -> U32:
  match value:
    case Some{word}: word
    case None{}: 0

def number(text:String) -> U32:
  number_result(U32.read(text))

def source_text(source:R.Source) -> String:
  match source:
    case R.Legacy{R.Bits64{hi,lo}}: "legacy," ++ U32.show(hi) ++ "," ++ U32.show(lo)
    case R.Xoroshiro{R.Bits64{a,b},R.Bits64{c,d}}:
      "xoroshiro," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def digest_text(result:Result<&2,&2,String,M.Digest>) -> String:
  match result:
    case Fail{message}: "fail," ++ message
    case Done{M.Digest{a,b,c,d}}:
      "digest," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def named_text(result:Result<&2,&2,String,R.Source>) -> String:
  match result:
    case Fail{message}: "fail," ++ message
    case Done{source}: source_text(source)

def named(factory:R.Positional,text:String) -> String:
  named_text(WS.named(factory,text))

def digest_bytes(text:String,limit:Nat,result:Result<&2,&2,String,List<&2,U32>>) -> String:
  match result:
    case Fail{message}: "fail," ++ message
    case Done{bytes}: digest_text(M.digest(limit,bytes))

def run(fields:List<&1,String>) -> String:
  match fields:
    case "md5" <> +text <> Nil{}:
      digest_bytes(text,16384n,WS.ascii_bytes_with(16384n,text))
    case "named" <> a <> b <> c <> d <> text <> Nil{}:
      named(R.XoroshiroPositional{R.Bits64{number(a),number(b)},R.Bits64{number(c),number(d)}},text)
    case "root" <> hi <> lo <> legacy <> text <> Nil{}:
      named_text(WS.compiled_random(WS.new(N.Word64{number(hi),number(lo)},U32.is_ne(number(legacy),0)),text))
    case "budget" <> limit <> a <> b <> c <> d <> text <> Nil{}:
      named_text(WS.named_with(U32.to_nat(number(limit)),R.XoroshiroPositional{R.Bits64{number(a),number(b)},R.Bits64{number(c),number(d)}},text))
    case "legacy-budget" <> limit <> hi <> lo <> text <> Nil{}:
      named_text(WS.named_with(U32.to_nat(number(limit)),R.LegacyPositional{R.Bits64{number(hi),number(lo)}},text))
    case _: "fail,invalid fixture arguments"

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fields: IO.print(run(fields))
    case _: IO.print("fail,no arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1,String> <- IO.args()
    arguments(args)
