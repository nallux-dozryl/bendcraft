import Base
import ./random.bend as R
import ./f64.bend as F
import ./worldgen_perlin_noise.bend as P
import ./worldgen_blended_noise.bend as B

# These contracts concern the actual affine sampler owners. Numeric parity
# requires independent pinned-Java observations and is not implied here.
def array_owner(-T:Data,result:Array<U32> & T) -> Array<U32>:
  (owner,value) = result
  owner

def state_owner(-O:Type,-V:Type,result:O & V) -> O:
  (owner,value) = result
  owner

def noise_owner(result:P.Noise & F32) -> P.Noise:
  state_owner(P.Noise,F32,result)

def layers_owner(result:List<&1,B.Layer> & F32) -> List<&1,B.Layer>:
  state_owner(List<&1,B.Layer>,F32,result)

def stack_owner(result:B.Stack & F32) -> B.Stack:
  state_owner(B.Stack,F32,result)

def blended_owner(result:B.Blended & F32) -> B.Blended:
  state_owner(B.Blended,F32,result)

law array_get_returns_exact_owner:
  for a:Array<U32>
  for +index:U32
  {array_owner(U32,Array.get(U32,a,index)) == a : Array<U32>}

law permute_returns_exact_owner:
  for a:Array<U32>
  for +index:U32
  {array_owner(U32,P.permute(a,index)) == a : Array<U32>}

law corner_hashes_returns_exact_owner:
  for a:Array<U32>
  for +x:U32
  for +y:U32
  for +z:U32
  {array_owner(P.Corners,P.corner_hashes(a,x,y,z)) == a : Array<U32>}

law perlin_get_returns_exact_owner:
  for noise:P.Noise
  for +farlands:Bool
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {noise_owner(P.get(noise,farlands,x,y,z)) == noise : P.Noise}

law stack_get_returns_exact_owner:
  for stack:B.Stack
  for +farlands:Bool
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {stack_owner(B.stack_get(stack,farlands,x,y,z)) == stack : B.Stack}

law blended_get_returns_exact_owner:
  for blended:B.Blended
  for +farlands:Bool
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {blended_owner(B.get(blended,farlands,x,y,z)) == blended : B.Blended}

law invalid_config_preserves_source:
  for fuel:Nat
  for +source:R.Source
  for +config:B.Config
  for invalid:{B.config_valid(config) == False{} : Bool}
  {B.create(fuel,source,config) ==
    (source,Fail{"blended-noise configuration is outside the pinned finite codec ranges"}) :
    R.Source & Result<&2,&1,String,B.Blended>}

law exhausted_perlin_constructor_preserves_source:
  for +source:R.Source
  for mode:P.Mode
  {P.create(0n,source,mode) ==
    (source,Fail{"noise permutation random rejection fuel exhausted"}) :
    R.Source & Result<&2,&1,String,P.Noise>}

law exhausted_blended_constructor_preserves_source:
  for +source:R.Source
  for config:B.Config
  {B.create_unchecked(0n,source,config) ==
    (source,Fail{"noise permutation random rejection fuel exhausted"}) :
    R.Source & Result<&2,&1,String,B.Blended>}
