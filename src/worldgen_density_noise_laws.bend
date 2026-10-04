import Base
import ./worldgen_density_noise.bend as D
import ./worldgen_seed.bend as WS
import ./random.bend as R
import ./f64.bend as F

# These are actual complete-owner and constructor-admission contracts.
# Independent pinned-Java observations establish numeric operation parity.
def noise_owner(result:D.Noise & F32) -> D.Noise:
  (noise,value) = result
  noise

def initialization_source(result:R.Source & Result<&2,&1,String,D.Built>) -> R.Source:
  (source,status) = result
  source

def initialization_failure(result:R.Source & Result<&2,&1,String,D.Built>) -> Maybe<&2,String>:
  match result:
    case Tuple{source,Fail{message}}: Some{message}
    case Tuple{source,Done{built}}: None{}

law every_read_retains_complete_noise:
  for noise:D.Noise
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {noise_owner(D.get(noise,x,y,z)) == noise : D.Noise}

law invalid_config_preserves_constructor_source:
  for fuel:Nat
  for +source:R.Source
  for +config:D.Config
  for invalid:{D.config_valid(config) == False{} : Bool}
  {D.initialize(fuel,source,config) ==
    (source,Fail{"normal-noise configuration is outside the pinned finite codec ranges"}) :
    R.Source & Result<&2,&1,String,D.Built>}

law any_constructor_failure_rolls_back_complete_source:
  for fuel:Nat
  for +source:R.Source
  for +config:D.Config
  for message:String
  for failed:{initialization_failure(D.initialize(fuel,source,config)) == Some{message} : Maybe<&2,String>}
  {initialization_source(D.initialize(fuel,source,config)) == source : R.Source}

law unsupported_biome_initializer_is_refused:
  for root:WS.Root
  for +name:String
  for fuel:Nat
  for config:D.Config
  for unsupported:{D.supported_name(name) == False{} : Bool}
  {D.create(root,name,fuel,config) ==
    Fail{"normal-noise legacy Nether biome initializer is unavailable"} : Result<&2,&1,String,D.Noise>}

law invalid_named_config_is_refused:
  for root:WS.Root
  for +name:String
  for fuel:Nat
  for +config:D.Config
  for supported:{D.supported_name(name) == True{} : Bool}
  for invalid:{D.config_valid(config) && D.identity_matches(name,config) == False{} : Bool}
  {D.create(root,name,fuel,config) ==
    Fail{"normal-noise configuration or parameter identity is invalid"} : Result<&2,&1,String,D.Noise>}

# The official boxed-Double codec distinguishes -0.0 from its +0.0 lower bound.
# Refusal does not depend on the remaining modifiers or declared list count.
law negative_zero_modifier_is_refused:
  for room:Nat
  for rest:List<&2,F.F64>
  for count:U32
  {D.modifiers_valid(room,F.F64{2147483648,0} <> rest,count) == False{} : Bool}
