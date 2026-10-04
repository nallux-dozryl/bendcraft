import Base
import ../src/worldgen_density.bend as D
import ../src/worldgen_density_state.bend as S
import ../src/worldgen_density_ast.bend as A
import ../src/worldgen_density_compile.bend as C
import ../src/worldgen_density_loader.bend as L
import ../src/worldgen_density_number.bend as Number
import ../src/worldgen_overworld.bend as O
import ../src/worldgen_noise_settings.bend as NS
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/world_generation_settings.bend as WG
import ../src/worldgen_perlin_noise.bend as P
import ../src/json.bend as J
import ../src/nbt.bend as N
import ../src/f64.bend as F

def word(value:Maybe<&2,U32>) -> U32:
  match value:
    case Some{value}: value
    case None{}: 0

def number(value:String) -> U32: word(U32.read(value))

def double_result(result:Result<&2,&2,String,F.F64>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{F.F64{hi,lo}}: "double|" ++ U32.show(hi) ++ "," ++ U32.show(lo)

def root_index(program:A.Program) -> U32:
  match program:
    case A.Program{plan,registry,expression,nodes,root}: root

def sample_text(result:S.State & Result<&2,&2,String,F32>) -> S.State & String:
  match result:
    case Tuple{state,Fail{message}}: (state,"fail:" ++ message)
    case Tuple{state,Done{value}}: (state,U32.show(F32.bits(value)))

def sample(state:S.State,fields:List<&2,String>,+index:U32,depth:Nat) -> S.State & String:
  match fields:
    case x <> y <> z <> Nil{}:
      sample_text(D.evaluate(depth,state,index,S.Point{number(x),number(y),number(z)}))
    case _: (state,"fail:invalid point")

def samples(points:List<&2,String>,state:S.State,+index:U32,+depth:Nat) -> S.State & String:
  match points:
    case Nil{}: (state,"")
    case point <> rest:
      P.paired(S.State,String,S.State & String,sample(state,String.split(point,','),index,depth),
        state => value => P.paired(S.State,String,S.State & String,samples(rest,state,index,depth),
          state => tail => (state,value ++ ";" ++ tail)))

def sampled(state:S.State,points:String,depth:Nat) -> String:
  match state:
    case S.State{+program,pool,cache}:
      P.paired(S.State,String,String,samples(String.split(points,';'),S.State{program,pool,cache},root_index(program),depth),
        state => values => "density|" ++ values)

def initialized(points:String,depth:Nat,result:Result<&2,&1,String,S.State>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{state}: sampled(state,points,depth)

def expression(plan:O.Plan,registry:J.Value,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{value}: initialized(points,depth,L.initialize(plan,registry,value,limits,sampler_fuel))

def registry(plan:O.Plan,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{value}: expression(plan,value,limits,sampler_fuel,points,depth,J.parse(text))

def planned(loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,result:Result<&2,&2,String,O.Plan>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{plan}: registry(plan,text,limits,sampler_fuel,points,depth,J.parse_with(loaded,J.Limits{262144n,128}))

def settings(seed:N.Word64,loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,result:Result<&2,&2,String,NS.Settings>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{definition}: planned(loaded,text,limits,sampler_fuel,points,depth,O.prepare(WG.normal(seed),definition))

def metadata(seed:N.Word64,loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{value}: settings(seed,loaded,text,limits,sampler_fuel,points,depth,NC.read("minecraft:overworld",value))

def run(fields:List<&2,String>) -> String:
  match fields:
    case "number" <> token <> Nil{}: double_result(Number.read(token))
    case "density" <> hi <> lo <> metadata_text <> loaded <> expression <> points <> compile_depth <> nodes <> entries <> sampler_fuel <> depth <> Nil{}:
      metadata(N.Word64{number(hi),number(lo)},loaded,expression,C.Limits{U32.to_nat(number(compile_depth)),number(nodes),U32.to_nat(number(entries))},
        U32.to_nat(number(sampler_fuel)),points,U32.to_nat(number(depth)),J.parse(metadata_text))
    case _: "fail|invalid density fixture"

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fixture <> Nil{}: IO.print(run(String.split(fixture,'|')))
    case _: IO.print("fail|one fixture argument required")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<&1,String> <- IO.args()
    arguments(args)
