import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as C
import ./worldgen_density_state.bend as S
import ./worldgen_overworld.bend as O
import ./worldgen_noise_settings_codec.bend as NC
import ./json.bend as J

# The resource layer supplies the actual selected density/noise definitions.
# This adapter retains every original definition; it does not manufacture
# missing resources or replace a refused graph with a constant.
def bindings(members:List<&2,J.Member>) -> List<&2,A.Binding>:
  match members:
    case Nil{}: []
    case J.JMember{key,value} <> rest: A.Binding{key,value} <> bindings(rest)

def table(value:J.Value) -> Result<&2,&2,String,List<&2,A.Binding>>:
  match value:
    case J.JObject{members}: Done{bindings(members)}
    case _: Fail{"loaded density/noise definitions must be resource-keyed objects"}

def registry(+value:J.Value) -> Result<&2,&2,String,A.Registry>:
  do Result<&2,&2,String,A.Registry>:
    density_value:J.Value <- NC.field(value,"densities")
    densities:List<&2,A.Binding> <- table(density_value)
    noise_value:J.Value <- NC.field(value,"noises")
    noises:List<&2,A.Binding> <- table(noise_value)
    return A.Registry{densities,noises}

def compile_registry(plan:O.Plan,expression:J.Value,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,A.Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{loaded}: C.compile(plan,loaded,expression,limits)

def compile(plan:O.Plan,loaded:J.Value,expression:J.Value,limits:C.Limits) -> Result<&2,&2,String,A.Program>:
  compile_registry(plan,expression,limits,registry(loaded))

def initialize_compiled(fuel:Nat,result:Result<&2,&2,String,A.Program>) -> Result<&2,&1,String,S.State>:
  match result:
    case Fail{message}: Fail{message}
    case Done{program}: S.initialize(program,fuel)

def initialize(plan:O.Plan,loaded:J.Value,expression:J.Value,limits:C.Limits,sampler_fuel:Nat) -> Result<&2,&1,String,S.State>:
  initialize_compiled(sampler_fuel,compile(plan,loaded,expression,limits))

def compile_registry_unblended(plan:O.Plan,expression:J.Value,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,A.Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{loaded}: C.compile_unblended(plan,loaded,expression,limits)

def compile_unblended(plan:O.Plan,loaded:J.Value,expression:J.Value,limits:C.Limits) -> Result<&2,&2,String,A.Program>:
  compile_registry_unblended(plan,expression,limits,registry(loaded))

def initialize_unblended(plan:O.Plan,loaded:J.Value,expression:J.Value,limits:C.Limits,sampler_fuel:Nat) -> Result<&2,&1,String,S.State>:
  initialize_compiled(sampler_fuel,compile_unblended(plan,loaded,expression,limits))
