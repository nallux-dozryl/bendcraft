import Base
import ./worldgen_density_noise_laws.bend as Laws
import ./worldgen_density_noise.bend as D
import ./worldgen_noise_laws.bend as NoiseLaws
import ./worldgen_noise_proof.bend as NoiseProof
import ./worldgen_blended_noise.bend as BL
import ./worldgen_seed.bend as WS
import ./random.bend as R
import ./f64.bend as F
import ./worldgen_perlin_noise.bend as P

def NoiseWitness(-original:D.Noise,-actual:D.Noise & F32) -> Type:
  Exists(D.Noise & F32,r =>
    {actual == r : D.Noise & F32} & {Laws.noise_owner(r) == original : D.Noise})

def noise_stack_pair(root:WS.Root,name:String,config:D.Config,parameters:D.Parameters,-stack:BL.Stack,
    -x:F.F64,-y:F.F64,-z:F.F64,actual:BL.Stack & F32,
    evidence:{BL.stack_get(stack,False{},x,y,z) == actual : BL.Stack & F32} &
      {NoiseLaws.state_owner(BL.Stack,F32,actual) == stack : BL.Stack}) ->
    NoiseWitness(D.Noise{root,name,config,D.Built{parameters,stack}},
      D.get(D.Noise{root,name,config,D.Built{parameters,stack}},x,y,z)):
  match actual evidence:
    case Tuple{next,value} Tuple{same,retained}:
      ((D.Noise{root,name,config,D.Built{parameters,next}},value),
        ((%Equal.sym(BL.Stack & F32,BL.stack_get(stack,False{},x,y,z),(next,value),same) :
          {P.paired(BL.Stack,F32,D.Noise & F32,_,
            stack => value => (D.Noise{root,name,config,D.Built{parameters,stack}},value)) ==
            (D.Noise{root,name,config,D.Built{parameters,next}},value) : D.Noise & F32}
        {==}),
        (%Equal.sym(BL.Stack,next,stack,retained) :
          {D.Noise{root,name,config,D.Built{parameters,_}} == D.Noise{root,name,config,D.Built{parameters,stack}} : D.Noise}
        {==})))

def noise_stack_result(root:WS.Root,name:String,config:D.Config,parameters:D.Parameters,-stack:BL.Stack,
    -x:F.F64,-y:F.F64,-z:F.F64,
    result:NoiseProof.StateWitness(BL.Stack,F32,stack,BL.stack_get(stack,False{},x,y,z))) ->
    NoiseWitness(D.Noise{root,name,config,D.Built{parameters,stack}},
      D.get(D.Noise{root,name,config,D.Built{parameters,stack}},x,y,z)):
  match result:
    case Tuple{actual,evidence}: noise_stack_pair(root,name,config,parameters,stack,x,y,z,actual,evidence)

def noise_owned(noise:D.Noise,+x:F.F64,+y:F.F64,+z:F.F64) -> NoiseWitness(noise,D.get(noise,x,y,z)):
  match noise:
    case D.Noise{root,name,config,D.Built{parameters,stack}}:
      noise_stack_result(root,name,config,parameters,stack,x,y,z,NoiseProof.stack_owned(stack,False{},x,y,z))

def noise_project_pair(-noise:D.Noise,-x:F.F64,-y:F.F64,-z:F.F64,-actual:D.Noise & F32,
    evidence:{D.get(noise,x,y,z) == actual : D.Noise & F32} & {Laws.noise_owner(actual) == noise : D.Noise}) ->
    {Laws.noise_owner(D.get(noise,x,y,z)) == noise : D.Noise}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(D.Noise & F32,D.get(noise,x,y,z),actual,same) : {Laws.noise_owner(_) == noise : D.Noise}
      retained

def noise_project(-noise:D.Noise,-x:F.F64,-y:F.F64,-z:F.F64,result:NoiseWitness(noise,D.get(noise,x,y,z))) ->
    {Laws.noise_owner(D.get(noise,x,y,z)) == noise : D.Noise}:
  match result:
    case Tuple{actual,evidence}: noise_project_pair(noise,x,y,z,actual,evidence)

def Laws.every_read_retains_complete_noise(noise,x,y,z):
  noise_project(noise,x,y,z,noise_owned(noise,x,y,z))

def Laws.invalid_config_preserves_constructor_source(fuel,source,config,invalid):
  %Equal.sym(Bool,D.config_valid(config),False{},invalid) :
    {D.initialize_gate(fuel,source,config,_) ==
      (source,Fail{"normal-noise configuration is outside the pinned finite codec ranges"}) :
      R.Source & Result<&2,&1,String,D.Built>}
  {==}

def failure_truth(value:Maybe<&2,String>) -> Data:
  match value:
    case None{}: Unit
    case Some{message}: Empty

def none_is_not_failure(-message:String,contradiction:{None{} == Some{message} : Maybe<&2,String>}) -> Empty:
  %contradiction : failure_truth(_)
  Unit{}

def ConstructorWitness(-original:R.Source,-actual:R.Source & Result<&2,&1,String,D.Built>) -> Type:
  Exists(R.Source & Result<&2,&1,String,D.Built>,r =>
    {actual == r : R.Source & Result<&2,&1,String,D.Built>} &
    (@message:String -> @failed:{Laws.initialization_failure(r) == Some{message} : Maybe<&2,String>} ->
      {Laws.initialization_source(r) == original : R.Source}))

def committed_owned(original:R.Source,result:R.Source & Result<&2,&1,String,D.Built>) ->
    ConstructorWitness(original,D.initialize_commit(original,result)):
  match result:
    case Tuple{advanced,Fail{message}}:
      ((original,Fail{message}),({==},other => failed => {==}))
    case Tuple{advanced,Done{built}}:
      ((advanced,Done{built}),({==},message => failed =>
        Empty.absurd({advanced == original : R.Source},none_is_not_failure(message,failed))))

def initialized_gate_owned(fuel:Nat,+source:R.Source,config:D.Config,valid:Bool) ->
    ConstructorWitness(source,D.initialize_gate(fuel,source,config,valid)):
  match valid:
    case False{}:
      ((source,Fail{"normal-noise configuration is outside the pinned finite codec ranges"}),
        ({==},message => failed => {==}))
    case True{}:
      committed_owned(source,D.forked_first(fuel,D.parameters(config),R.fork_positional(source)))

def initialization_owned(fuel:Nat,source:R.Source,+config:D.Config) ->
    ConstructorWitness(source,D.initialize(fuel,source,config)):
  initialized_gate_owned(fuel,source,config,D.config_valid(config))

def failure_transport(-source:R.Source,-before:R.Source & Result<&2,&1,String,D.Built>,
    -after:R.Source & Result<&2,&1,String,D.Built>,-message:String,
    same:{before == after : R.Source & Result<&2,&1,String,D.Built>},
    retained:(@failed:{Laws.initialization_failure(after) == Some{message} : Maybe<&2,String>} ->
      {Laws.initialization_source(after) == source : R.Source})) ->
    (@failed:{Laws.initialization_failure(before) == Some{message} : Maybe<&2,String>} ->
      {Laws.initialization_source(before) == source : R.Source}):
  %Equal.sym(R.Source & Result<&2,&1,String,D.Built>,before,after,same) :
    (@failed:{Laws.initialization_failure(_) == Some{message} : Maybe<&2,String>} ->
      {Laws.initialization_source(_) == source : R.Source})
  retained

def failed_pair(-fuel:Nat,-source:R.Source,-config:D.Config,message:String,
    -actual:R.Source & Result<&2,&1,String,D.Built>,
    evidence:{D.initialize(fuel,source,config) == actual : R.Source & Result<&2,&1,String,D.Built>} &
      (@other:String -> @failed:{Laws.initialization_failure(actual) == Some{other} : Maybe<&2,String>} ->
        {Laws.initialization_source(actual) == source : R.Source}),
    failed:{Laws.initialization_failure(D.initialize(fuel,source,config)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.initialization_source(D.initialize(fuel,source,config)) == source : R.Source}:
  match evidence:
    case Tuple{same,retained}:
      failure_transport(source,D.initialize(fuel,source,config),actual,message,same,retained(message))(failed)

def failed_result(-fuel:Nat,-source:R.Source,-config:D.Config,message:String,
    result:ConstructorWitness(source,D.initialize(fuel,source,config)),
    failed:{Laws.initialization_failure(D.initialize(fuel,source,config)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.initialization_source(D.initialize(fuel,source,config)) == source : R.Source}:
  match result:
    case Tuple{actual,evidence}: failed_pair(fuel,source,config,message,actual,evidence,failed)

def Laws.any_constructor_failure_rolls_back_complete_source(fuel,source,config,message,failed):
  failed_result(fuel,source,config,message,initialization_owned(fuel,source,config),failed)

def Laws.unsupported_biome_initializer_is_refused(root,name,fuel,config,unsupported):
  %Equal.sym(Bool,D.supported_name(name),False{},unsupported) :
    {D.create_supported(root,name,fuel,config,_) ==
      Fail{"normal-noise legacy Nether biome initializer is unavailable"} : Result<&2,&1,String,D.Noise>}
  {==}

def Laws.invalid_named_config_is_refused(root,name,fuel,config,supported,invalid):
  %Equal.sym(Bool,D.supported_name(name),True{},supported) :
    {D.create_supported(root,name,fuel,config,_) ==
      Fail{"normal-noise configuration or parameter identity is invalid"} : Result<&2,&1,String,D.Noise>}
  %Equal.sym(Bool,D.config_valid(config) && D.identity_matches(name,config),False{},invalid) :
    {D.create_validated(root,name,fuel,config,_) ==
      Fail{"normal-noise configuration or parameter identity is invalid"} : Result<&2,&1,String,D.Noise>}
  {==}

def Laws.negative_zero_modifier_is_refused(room,rest,count):
  match room:
    case 0n: {==}
    case 1n+left: {==}
