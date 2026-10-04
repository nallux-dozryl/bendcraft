import Base
import ../src/worldgen_density_noise.bend as D
import ../src/worldgen_seed.bend as WS
import ../src/worldgen_perlin_noise.bend as P
import ../src/worldgen_blended_noise.bend as BL
import ../src/nbt.bend as N
import ../src/random.bend as R
import ../src/f64.bend as F

def number_result(value:Maybe<&2,U32>) -> U32:
  match value:
    case None{}: 0
    case Some{word}: word

def number(text:String) -> U32: number_result(U32.read(text))

def double_text(value:F.F64) -> String:
  match value:
    case F.F64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def source_text(source:R.Source) -> String:
  match source:
    case R.Legacy{R.Bits64{hi,lo}}: "legacy," ++ U32.show(hi) ++ "," ++ U32.show(lo)
    case R.Xoroshiro{R.Bits64{a,b},R.Bits64{c,d}}:
      "xoroshiro," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def normalization(value:String) -> D.Normalization:
  match value:
    case "disabled": D.Disabled{}
    case "legacy": D.Legacy{}
    case _: D.Enabled{}

def double_fields(fields:List<&2,String>) -> F.F64:
  match fields:
    case hi <> lo <> Nil{}: F.F64{number(hi),number(lo)}
    case _: P.zero()

def modifiers_fields(fields:List<&2,String>) -> List<&2,F.F64>:
  match fields:
    case Nil{}: []
    case head <> rest: double_fields(String.split(head,',')) <> modifiers_fields(rest)

def modifiers_case(text:String,empty:Bool) -> List<&2,F.F64>:
  match empty:
    case True{}: []
    case False{}: modifiers_fields(String.split(text,';'))

def modifiers(+text:String) -> List<&2,F.F64>:
  modifiers_case(text,String.eq(text,""))

def octaves_text(values:List<&2,D.Octave>) -> String:
  match values:
    case Nil{}: ""
    case D.Octave{index,frequency,amplitude} <> rest:
      U32.show(index) ++ "," ++ double_text(frequency) ++ "," ++ double_text(amplitude) ++ ";" ++ octaves_text(rest)

def parameters_text(parameters:D.Parameters) -> String:
  match parameters:
    case D.Parameters{octaves,normalization,max_value}:
      double_text(normalization) ++ "|" ++ U32.show(F32.bits(max_value)) ++ "|" ++ octaves_text(octaves)

def permutation_read(left:Nat,+index:U32,perms:Array<U32>) -> Array<U32> & String:
  match left:
    case 0n: (perms,"")
    case 1n+rest:
      P.paired(Array<U32>,U32,Array<U32> & String,Array.get(U32,perms,index),perms => value =>
        P.paired(Array<U32>,String,Array<U32> & String,permutation_read(rest,U32.inc(index),perms),perms => tail =>
          (perms,U32.show(value) ++ "," ++ tail)))

def layer_read(layer:BL.Layer) -> BL.Layer & String:
  match layer:
    case BL.Layer{P.Noise{perms,+x,+y,+z,mode},+frequency,+amplitude}:
      P.paired(Array<U32>,String,BL.Layer & String,permutation_read(256n,0,perms),perms => words =>
        (BL.Layer{P.Noise{perms,x,y,z,mode},frequency,amplitude},
          double_text(frequency) ++ "," ++ U32.show(F32.bits(amplitude)) ++ "," ++
          double_text(x) ++ "," ++ double_text(y) ++ "," ++ double_text(z) ++ "," ++ words))

def layers_read(layers:List<&1,BL.Layer>) -> List<&1,BL.Layer> & String:
  match layers:
    case Nil{}: ([],"")
    case layer <> rest:
      P.paired(BL.Layer,String,List<&1,BL.Layer> & String,layer_read(layer),layer => row =>
        P.paired(List<&1,BL.Layer>,String,List<&1,BL.Layer> & String,layers_read(rest),tail => rows =>
          (layer <> tail,row ++ ";" ++ rows)))

def stack_read(stack:BL.Stack) -> BL.Stack & String:
  match stack:
    case BL.Stack{layers}:
      P.paired(List<&1,BL.Layer>,String,BL.Stack & String,layers_read(layers),layers => text => (BL.Stack{layers},text))

def scalar_fields(noise:D.Noise,fields:List<&2,String>) -> D.Noise & String:
  match fields:
    case a <> b <> c <> d <> e <> f <> Nil{}:
      P.paired(D.Noise,F32,D.Noise & String,D.get(noise,F.F64{number(a),number(b)},F.F64{number(c),number(d)},F.F64{number(e),number(f)}),
        noise => value => (noise,U32.show(F32.bits(value))))
    case _: (noise,"invalid-coordinate")

def scalar_samples(coordinates:List<&2,String>,noise:D.Noise) -> D.Noise & String:
  match coordinates:
    case Nil{}: (noise,"")
    case head <> rest:
      P.paired(D.Noise,String,D.Noise & String,scalar_fields(noise,String.split(head,',')),noise => value =>
        P.paired(D.Noise,String,D.Noise & String,scalar_samples(rest,noise),noise => tail =>
          (noise,value ++ ";" ++ tail)))

def observed(root:WS.Root,name:String,config:D.Config,coordinates:String,
    result:R.Source & Result<&2,&1,String,D.Built>) -> String:
  match result:
    case Tuple{source,Fail{message}}: "fail|" ++ message ++ "|" ++ source_text(source)
    case Tuple{source,Done{D.Built{+parameters,stack}}}:
      P.paired(BL.Stack,String,String,stack_read(stack),stack => layers =>
        P.paired(D.Noise,String,String,scalar_samples(String.split(coordinates,';'),D.Noise{root,name,config,D.Built{parameters,stack}}),
          noise => values => "normal|" ++ source_text(source) ++ "|" ++ parameters_text(parameters) ++ "|" ++ layers ++ "|" ++ values))

def observed_named(+root:WS.Root,name:String,fuel:Nat,+config:D.Config,coordinates:String,
    result:Result<&2,&2,String,R.Source>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{source}: observed(root,name,config,coordinates,D.initialize(fuel,source,config))

def api_observed(coordinates:String,result:Result<&2,&1,String,D.Noise>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{noise}:
      P.paired(D.Noise,String,String,scalar_samples(String.split(coordinates,';'),noise),noise => values => "api|" ++ values)

def run(fields:List<&2,String>) -> String:
  match fields:
    case "normal" <> hi <> lo <> legacy <> +name <> fuel <> amp_hi <> amp_lo <> octave <> count <> mode <> mods <> coordinates <> Nil{}:
      +root = WS.new(N.Word64{number(hi),number(lo)},U32.is_ne(number(legacy),0))
      config = {D.Config{name,F.F64{number(amp_hi),number(amp_lo)},number(octave),number(count),normalization(mode),modifiers(mods)}:D.Config}
      observed_named(root,name,U32.to_nat(number(fuel)),config,coordinates,WS.named(D.root_factory(root),name))
    case "api" <> hi <> lo <> legacy <> +name <> fuel <> amp_hi <> amp_lo <> octave <> count <> mode <> mods <> coordinates <> Nil{}:
      api_observed(coordinates,D.create(WS.new(N.Word64{number(hi),number(lo)},U32.is_ne(number(legacy),0)),name,U32.to_nat(number(fuel)),
        D.Config{name,F.F64{number(amp_hi),number(amp_lo)},number(octave),number(count),normalization(mode),modifiers(mods)}))
    case "parameters" <> amp_hi <> amp_lo <> octave <> count <> mode <> mods <> Nil{}:
      parameters_text(D.parameters(D.Config{"fixture",F.F64{number(amp_hi),number(amp_lo)},number(octave),number(count),normalization(mode),modifiers(mods)}))
    case "octave" <> index <> Nil{}: D.octave_name(number(index))
    case _: "fail|invalid fixture arguments"

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fixture <> Nil{}: IO.print(run(String.split(fixture,'|')))
    case _: IO.print("fail|one fixture argument required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1,String> <- IO.args()
    arguments(args)
