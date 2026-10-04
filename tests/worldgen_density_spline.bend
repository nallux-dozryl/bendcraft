import Base
import ./worldgen_density.bend as H
import ../src/worldgen_density_loader.bend as L
import ../src/worldgen_density_compile.bend as C
import ../src/worldgen_density_ast.bend as A
import ../src/worldgen_density_ranges.bend as R
import ../src/worldgen_density_interval.bend as I
import ../src/worldgen_overworld.bend as O
import ../src/worldgen_noise_settings.bend as NS
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/world_generation_settings.bend as WG
import ../src/json.bend as J
import ../src/nbt.bend as N

def range_text(result:Result<&2,&2,String,I.Interval>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{+range}: "range|" ++ Bool.show(I.is_nai(range)) ++ "|" ++ U32.show(F32.bits(I.low(range))) ++ "," ++ U32.show(F32.bits(I.high(range)))

def analyzed(+program:A.Program,result:Result<&2,&2,String,List<&2,R.Entry>>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{entries}: range_text(R.child(entries,H.root_index(program)))

def compiled_range(result:Result<&2,&2,String,A.Program>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{+program}: analyzed(program,R.program(program))

def expression(plan:O.Plan,registry:J.Value,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,range:Bool,
    result:Result<&2,&2,String,J.Value>) -> String:
  match range result:
    case _ Fail{message}: "fail|" ++ message
    case True{} Done{value}: compiled_range(L.compile_unblended(plan,registry,value,limits))
    case False{} Done{value}: H.initialized(points,depth,L.initialize_unblended(plan,registry,value,limits,sampler_fuel))

def registry(plan:O.Plan,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,range:Bool,
    result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{value}: expression(plan,value,limits,sampler_fuel,points,depth,range,J.parse_with(text,J.Limits{262144n,128}))

def planned(loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,range:Bool,
    result:Result<&2,&2,String,O.Plan>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{plan}: registry(plan,text,limits,sampler_fuel,points,depth,range,J.parse_with(loaded,J.Limits{262144n,128}))

def settings(seed:N.Word64,loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,range:Bool,
    result:Result<&2,&2,String,NS.Settings>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{definition}: planned(loaded,text,limits,sampler_fuel,points,depth,range,O.prepare(WG.normal(seed),definition))

def metadata(seed:N.Word64,loaded:String,text:String,limits:C.Limits,sampler_fuel:Nat,points:String,depth:Nat,range:Bool,
    result:Result<&2,&2,String,J.Value>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{value}: settings(seed,loaded,text,limits,sampler_fuel,points,depth,range,NC.read("minecraft:overworld",value))

def fixture(mode:String,hi:String,lo:String,metadata_text:String,loaded:String,expression:String,points:String,
    compile_depth:String,nodes:String,entries:String,sampler_fuel:String,depth:String) -> String:
  metadata(N.Word64{H.number(hi),H.number(lo)},loaded,expression,
    C.Limits{U32.to_nat(H.number(compile_depth)),H.number(nodes),U32.to_nat(H.number(entries))},
    U32.to_nat(H.number(sampler_fuel)),points,U32.to_nat(H.number(depth)),String.eq(mode,"spline-range"),J.parse(metadata_text))

def run(fields:List<&2,String>) -> String:
  match fields:
    case mode <> hi <> lo <> metadata_text <> loaded <> expression <> points <> compile_depth <> nodes <> entries <> sampler_fuel <> depth <> Nil{}:
      fixture(mode,hi,lo,metadata_text,loaded,expression,points,compile_depth,nodes,entries,sampler_fuel,depth)
    case _: "fail|invalid spline fixture"

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fixture <> Nil{}: IO.print(run(String.split(fixture,'|')))
    case _: IO.print("fail|one spline fixture argument required")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<&1,String> <- IO.args()
    arguments(args)
