import Base
import ../src/worldgen_seed.bend as WS
import ../src/worldgen_perlin_noise.bend as P
import ../src/worldgen_blended_noise.bend as BL
import ../src/worldgen_overworld.bend as O
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/worldgen_noise_settings.bend as NS
import ../src/worldgen_biome.bend as B
import ../src/world_generation_settings.bend as WG
import ../src/f64.bend as F
import ../src/nbt.bend as N
import ../src/json.bend as J
import ../src/random.bend as R

def number_result(value:Maybe<&2,U32>) -> U32:
  match value:
    case Some{word}: word
    case None{}: 0

def number(text:String) -> U32: number_result(U32.read(text))

def word_text(word:F.Word64) -> String:
  match word:
    case F.Word64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def source_text(source:R.Source) -> String:
  match source:
    case R.Legacy{R.Bits64{hi,lo}}: "legacy," ++ U32.show(hi) ++ "," ++ U32.show(lo)
    case R.Xoroshiro{R.Bits64{a,b},R.Bits64{c,d}}:
      "xoroshiro," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def double_text(value:F.F64) -> String:
  match value:
    case F.F64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case head <> rest: U32.show(head) ++ "," ++ words(rest)

def permutation_read(left:Nat,+index:U32,perms:Array<U32>) -> Array<U32> & String:
  match left:
    case 0n: (perms,"")
    case 1n+rest:
      P.paired(Array<U32>,U32,Array<U32> & String,Array.get(U32,perms,index),
        perms => value => P.paired(Array<U32>,String,Array<U32> & String,permutation_read(rest,U32.inc(index),perms),
          perms => tail => (perms,U32.show(value) ++ "," ++ tail)))

def scalar_fields(noise:P.Noise,fields:List<&2,String>) -> P.Noise & String:
  match fields:
    case a <> b <> c <> d <> e <> f <> Nil{}:
      P.paired(P.Noise,F32,P.Noise & String,P.get(noise,False{},F.F64{number(a),number(b)},F.F64{number(c),number(d)},F.F64{number(e),number(f)}),
        noise => value => (noise,U32.show(F32.bits(value))))
    case _: (noise,"invalid-coordinate")

def scalar_samples(coordinates:List<&2,String>,noise:P.Noise) -> P.Noise & String:
  match coordinates:
    case Nil{}: (noise,"")
    case head <> rest:
      P.paired(P.Noise,String,P.Noise & String,scalar_fields(noise,String.split(head,',')),
        noise => value => P.paired(P.Noise,String,P.Noise & String,scalar_samples(rest,noise),
          noise => tail => (noise,value ++ ";" ++ tail)))

def created_perlin(coordinates:String,result:R.Source & Result<&2,&1,String,P.Noise>) -> String:
  match result:
    case Tuple{source,Fail{error}}: "fail|" ++ error ++ "|" ++ source_text(source)
    case Tuple{source,Done{P.Noise{perms,+x,+y,+z,mode}}}:
      P.paired(Array<U32>,String,String,permutation_read(256n,0,perms),
        perms => permutation => P.paired(P.Noise,String,String,scalar_samples(String.split(coordinates,';'),P.Noise{perms,x,y,z,mode}),
          noise => values => "perlin|" ++ source_text(source) ++ "|" ++ double_text(x) ++ "|" ++ double_text(y) ++ "|" ++ double_text(z) ++ "|" ++ permutation ++ "|" ++ values))

def perlin_named(mode:P.Mode,fuel:Nat,coordinates:String,result:Result<&2,&2,String,R.Source>) -> String:
  match result:
    case Fail{error}: "fail|" ++ error
    case Done{source}: created_perlin(coordinates,P.create(fuel,source,mode))

def density_words(values:List<&2,F32>) -> String:
  match values:
    case Nil{}: ""
    case head <> rest: U32.show(F32.bits(head)) ++ "," ++ density_words(rest)

def sampled_column(result:O.Sampler & Result<&2,&2,String,O.Column>) -> String:
  match result:
    case Tuple{sampler,Fail{error}}: "fail|" ++ error
    case Tuple{sampler,Done{O.Column{density,x,z,bottom,step,values}}}:
      "column|" ++ density ++ "|" ++ U32.show(x) ++ "|" ++ U32.show(z) ++ "|" ++ U32.show(bottom) ++ "|" ++ U32.show(step) ++ "|" ++ density_words(values)

def compiled_column(request:O.ColumnRequest,budget:U32,result:Result<&2,&1,String,O.Sampler>) -> String:
  match result:
    case Fail{error}: "fail|" ++ error
    case Done{sampler}: sampled_column(O.sample_column(sampler,request,budget))

def prepared_column(request:O.ColumnRequest,budget:U32,result:Result<&2,&2,String,O.Plan>) -> String:
  match result:
    case Fail{error}: "fail|" ++ error
    case Done{plan}: compiled_column(request,budget,O.compile_base(plan,64n,O.pinned_base_config()))

def column_settings(seed:N.Word64,request:O.ColumnRequest,budget:U32,result:Result<&2,&2,String,NS.Settings>) -> String:
  match result:
    case Fail{error}: "fail|" ++ error
    case Done{settings}: prepared_column(request,budget,O.prepare(WG.normal(seed),settings))

def column_json(seed:N.Word64,request:O.ColumnRequest,budget:U32,result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{error}: "fail|" ++ error
    case Done{settings}: column_settings(seed,request,budget,NC.read("minecraft:overworld",settings))

def target_text(value:B.Target) -> String:
  match value:
    case B.Target{a,b,c,d,e,f}: "climate|" ++ word_text(a) ++ "|" ++ word_text(b) ++ "|" ++ word_text(c) ++ "|" ++ word_text(d) ++ "|" ++ word_text(e) ++ "|" ++ word_text(f)

def float_word(word:U32) -> F32:
  match word:
    case U32{bits}: F32{bits}

def run(fields:List<&2,String>) -> String:
  match fields:
    case "perlin" <> hi <> lo <> legacy <> fudge_hi <> fudge_lo <> fuel <> coordinates <> Nil{}:
      perlin_named(P.Smeared{F.F64{number(fudge_hi),number(fudge_lo)}},U32.to_nat(number(fuel)),coordinates,
        WS.compiled_random(WS.new(N.Word64{number(hi),number(lo)},U32.is_ne(number(legacy),0)),"minecraft:terrain"))
    case "plain" <> hi <> lo <> legacy <> fuel <> coordinates <> Nil{}:
      perlin_named(P.Perlin{},U32.to_nat(number(fuel)),coordinates,
        WS.compiled_random(WS.new(N.Word64{number(hi),number(lo)},U32.is_ne(number(legacy),0)),"minecraft:terrain"))
    case "column" <> hi <> lo <> x <> z <> bottom <> step <> count <> budget <> metadata <> Nil{}:
      column_json(N.Word64{number(hi),number(lo)},O.ColumnRequest{number(x),number(z),number(bottom),number(step),number(count)},number(budget),J.parse(metadata))
    case "climate" <> a <> b <> c <> d <> e <> f <> Nil{}:
      target_text(B.target(B.Values{float_word(number(a)),float_word(number(b)),float_word(number(c)),float_word(number(d)),float_word(number(e)),float_word(number(f))}))
    case _: "fail|invalid fixture arguments"

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fixture <> Nil{}: IO.print(run(String.split(fixture,'|')))
    case _: IO.print("fail|one fixture argument required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1,String> <- IO.args()
    arguments(args)
