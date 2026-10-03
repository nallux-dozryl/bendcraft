import Base
import ../src/blockstate_model.bend as B
import ../src/random.bend as R
import ../src/model_choice.bend as C

def number_maybe(v:Maybe<&2,U32>) -> U32:
  match v:
    case Some{n}: n
    case None{}: 0
def number(s:String) -> U32:
  number_maybe(U32.read(s))
def flag(s:String) -> Bool:
  String.eq(s,"1")
def variant(fields:List<&2,String>) -> B.Variant:
  match fields:
    case model <> x <> y <> z <> uv <> Nil{}: B.Variant{model,number(x),number(y),number(z),flag(uv)}
    case _: B.Variant{"",0,0,0,False{}}
def entries(fields:List<&2,String>) -> List<&2,B.Weighted>:
  match fields:
    case weight <> model <> x <> y <> z <> uv <> rest:
      B.Weighted{B.Variant{model,number(x),number(y),number(z),flag(uv)},number(weight)} <> entries(rest)
    case _: Nil{}
def choice(fields:List<&2,String>) -> B.Choice:
  match fields:
    case "s" <> rest: B.Single{variant(rest)}
    case "w" <> total <> rest: B.WeightedChoice{entries(rest),number(total)}
    case _: B.WeightedChoice{Nil{},0}
def part(fields:List<&2,String>) -> B.SelectedPart:
  match fields:
    case index <> rest: B.SelectedPart{number(index),choice(rest)}
    case _: B.SelectedPart{0,B.WeightedChoice{Nil{},0}}
def parts(fields:List<&2,String>) -> List<&2,B.SelectedPart>:
  match fields:
    case Nil{}: Nil{}
    case "" <> Nil{}: Nil{}
    case head <> rest: part(String.split(head,',')) <> parts(rest)
def root(kind:String,encoded:String) -> B.Root:
  match kind:
    case "v": B.VariantRoot{choice(String.split(encoded,','))}
    case _: B.MultipartRoot{parts(String.split(encoded,';')),Nil{}}
def bits_show(value:R.Bits64) -> String:
  match value:
    case R.Bits64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)
def source_show(value:R.Source) -> String:
  match value:
    case R.Legacy{seed}: "l," ++ bits_show(seed) ++ ",0,0"
    case R.Xoroshiro{low,high}: "x," ++ bits_show(low) ++ "," ++ bits_show(high)
def variant_show(value:B.Variant) -> String:
  match value:
    case B.Variant{model,x,y,z,uv}: model ++ "," ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(Bool.to_u32(uv))
def index_show(value:Maybe<&2,U32>) -> String:
  match value:
    case None{}: "v"
    case Some{i}: U32.show(i)
def selected_show(value:C.Selected) -> String:
  match value:
    case C.Selected{index,v}: index_show(index) ++ "," ++ variant_show(v)
def selections_show(values:List<&2,C.Selected>) -> String:
  match values:
    case Nil{}: ""
    case head <> Nil{}: selected_show(head)
    case head <> rest: selected_show(head) ++ ";" ++ selections_show(rest)
def seed_show(value:Maybe<&2,R.Bits64>) -> String:
  match value:
    case None{}: "-"
    case Some{s}: bits_show(s)
def random_error(e:R.RandomError) -> String:
  match e:
    case R.InvalidBound{}: "InvalidBound"
    case R.RejectionFuelExhausted{}: "RejectionFuelExhausted"
    case R.UnsupportedHash{}: "UnsupportedHash"
def result_show(value:Result<&2,&2,C.Error,C.Selection>) -> String:
  match value:
    case Done{C.Selection{parts,seed}}: "ok|" ++ seed_show(seed) ++ "|" ++ selections_show(parts)
    case Fail{C.RandomFailure{error}}: "rng:" ++ random_error(error) ++ "|-|"
    case Fail{C.InvalidChoice{B.Error{code,path,detail}}}: "choice:" ++ code ++ "|-|"
def selected(+root:B.Root,source:R.Source,+fuel:Nat,+mode:String,+seed:R.Bits64)
  -> R.Source & Result<&2,&2,C.Error,C.Selection>:
  match mode:
    case "s": C.select_seeded(root,source,seed,fuel)
    case _: C.select(root,source,fuel)
def report(+label:String,index:U32,result:R.Source & Result<&2,&2,C.Error,C.Selection>) -> IO(R.Source):
  match result:
    case (+source,value):
      do IO<R.Source>:
        IO.print(label ++ "|" ++ U32.show(index) ++ "|" ++ source_show(source) ++ "|" ++ result_show(value))
        return source
def repeats(count:Nat,+label:String,+root:B.Root,source:R.Source,+fuel:Nat,+mode:String,+seed:R.Bits64,+index:U32) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        next:R.Source <- report(label,index,selected(root,source,fuel,mode,seed))
        repeats(p,label,root,next,fuel,mode,seed,U32.inc(index))
def start_source(kind:String,seed:R.Bits64,high:R.Bits64) -> R.Source:
  match kind:
    case "x": R.seeded_xoroshiro(seed)
    case "r": R.raw_xoroshiro(seed,high)
    case _: R.seeded_legacy(seed)
def source_only(pair:R.Source & U32) -> R.Source:
  match pair:
    case (source,value): source
def advance(fuel:Nat,source:R.Source) -> R.Source:
  match fuel:
    case 0n: source
    case 1n+p: advance(p,source_only(R.next_int(source)))
def dispatch(fields:List<&2,String>) -> IO(Unit):
  match fields:
    case label <> "position" <> x <> y <> z <> Nil{}:
      IO.print(label ++ "|" ++ bits_show(C.default_position_seed(number(x),number(y),number(z))))
    case label <> kind <> hi <> lo <> sh <> sl <> steps <> count <> fuel <> mode <> rh <> rl <> rkind <> encoded <> Nil{}:
      repeats(U32.to_nat(number(count)),label,root(rkind,encoded),advance(U32.to_nat(number(steps)),start_source(kind,R.Bits64{number(hi),number(lo)},R.Bits64{number(sh),number(sl)})),U32.to_nat(number(fuel)),mode,R.Bits64{number(rh),number(rl)},1)
    case _: IO.die(Unit,2,"Malformed fixture protocol")
def run_args(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        dispatch(String.split(head,'|'))
        run_args(rest)
def drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest: run_args(rest)
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),drop_program)
