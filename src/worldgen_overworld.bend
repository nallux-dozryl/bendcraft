import Base
import ./world_generation_settings.bend as WG
import ./worldgen_noise_settings.bend as NS
import ./worldgen_seed.bend as WS
import ./worldgen_blended_noise.bend as BL
import ./f64.bend as F
import ./random.bend as R
import ./json.bend as J
import ./worldgen_biome.bend as Biome
import ./worldgen_perlin_noise.bend as Perlin

# A prepared normal plan retains the durable seed/generator/biome identity and
# the actual loaded noise-settings definition. Base3D is a real dependency of
# that plan's sloped_cheese/final_density route, not a terrain substitute.
type Plan is Data:
  Plan{generation:WG.Settings,definition:NS.Settings,random:WS.Root}

type Sampler is Type:
  Sampler{plan:Plan,base_3d:BL.Blended}

type ColumnRequest is Data:
  ColumnRequest{x:U32,z:U32,min_y:U32,step:U32,count:U32}

type Column is Data:
  Column{density:String,x:U32,z:U32,min_y:U32,step:U32,values:List<&2,F32>}

def geometry_matches(generation:WG.Settings,definition:NS.Settings) -> Bool:
  match generation definition:
    case WG.Settings{dimension,min_y,height,seed,WG.Noise{+settings,biome}}
        NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs}:
      String.eq(dimension,"minecraft:overworld") && String.eq(settings,"minecraft:overworld") &&
        String.eq(settings,key) && U32.is_eq(min_y,bottom) && U32.is_eq(height,size)
    case _ _: False{}

def admitted(generation:WG.Settings,definition:NS.Settings,valid:Bool) -> Result<&2,&2,String,Plan>:
  match generation definition valid:
    case WG.Settings{dimension,min_y,height,+seed,generator}
        NS.Settings{key,bottom,size,sea,+legacy,block,fluid,material,router,aquifers,spawn,debug,mobs} True{}:
      Done{Plan{WG.Settings{dimension,min_y,height,seed,generator},
        NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs},WS.new(seed,legacy)}}
    case _ _ _: Fail{"normal Overworld generation/noise-settings identity or geometry mismatch"}

def prepare(+generation:WG.Settings,+definition:NS.Settings) -> Result<&2,&2,String,Plan>:
  admitted(generation,definition,WG.valid(generation) && NS.valid(definition) && geometry_matches(generation,definition))

def prepare_biomes(plan:Plan,preset_definition:Biome.LoadedPreset) -> Result<&2,&2,String,Biome.Plan>:
  match plan:
    case Plan{WG.Settings{dimension,min_y,height,seed,WG.Noise{settings,biome}},
        NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs},root}:
      Biome.prepare(biome,router,preset_definition)
    case _: Fail{"normal biome preparation requires retained noise-generation settings"}

def compile_created(plan:Plan,result:R.Source & Result<&2,&1,String,BL.Blended>) -> Result<&2,&1,String,Sampler>:
  (advanced,status) = result
  match status:
    case Fail{message}: Fail{message}
    case Done{blended}: Done{Sampler{plan,blended}}

def compile_named(plan:Plan,random_fuel:Nat,config:BL.Config,result:Result<&2,&2,String,R.Source>) -> Result<&2,&1,String,Sampler>:
  match result:
    case Fail{message}: Fail{message}
    case Done{source}: compile_created(plan,BL.create(random_fuel,source,config))

def compile_base(+plan:Plan,random_fuel:Nat,config:BL.Config) -> Result<&2,&1,String,Sampler>:
  Plan{generation,definition,root} = plan
  compile_named(plan,random_fuel,config,WS.compiled_random(root,"minecraft:terrain"))

def last_coordinate(bottom:U32,step:U32,count:U32) -> U32:
  U32.add(bottom,U32.mul(step,U32.sub(count,1)))

def request_valid(request:ColumnRequest,budget:U32) -> Bool:
  match request:
    case ColumnRequest{x,z,+bottom,+step,+count}:
      U32.is_lt(0,step) && U32.is_le(step,2147483647) && U32.is_lt(0,count) && U32.is_le(count,budget) &&
        U32.is_le(U32.sub(count,1),U32.div(2147483647,step)) &&
        WG.signed_le(bottom,last_coordinate(bottom,step,count))

def sample_loop(+plan:Plan,+x:U32,+z:U32,+bottom:U32,+step:U32,count:Nat,+y:U32,values:List<&2,F32>,blended:BL.Blended) -> Sampler & Column:
  match count:
    case 0n:
      (Sampler{plan,blended},Column{"minecraft:overworld/base_3d_noise",x,z,bottom,step,List.reverse(&2,F32,values)})
    case 1n+rest:
      Perlin.paired(BL.Blended,F32,Sampler & Column,BL.sample_block(blended,False{},x,y,z),
        next => value => sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next))

def sampled(result:Sampler & Column) -> Sampler & Result<&2,&2,String,Column>:
  (sampler,column) = result
  (sampler,Done{column})

def column_admitted(sampler:Sampler,request:ColumnRequest,valid:Bool) -> Sampler & Result<&2,&2,String,Column>:
  match sampler request valid:
    case _ _ False{}: (sampler,Fail{"column density request exceeds signed-coordinate or sample budget"})
    case Sampler{plan,blended} ColumnRequest{x,z,+bottom,step,count} True{}:
      sampled(sample_loop(plan,x,z,bottom,step,U32.to_nat(count),bottom,[],blended))

def sample_column(sampler:Sampler,+request:ColumnRequest,budget:U32) -> Sampler & Result<&2,&2,String,Column>:
  column_admitted(sampler,request,request_valid(request,budget))

# These defaults are the installed 26.3 base_3d_noise definition. Arbitrary
# definitions use compile_base's Config; loading their JSON doubles requires
# an exact binary64 resource decoder, not F32 widening.
def pinned_base_config() -> BL.Config:
  BL.Config{F.F64{1070596096,0},F.F64{1069547520,0},F.from_u32(80),F.from_u32(160),F.from_u32(8)}
