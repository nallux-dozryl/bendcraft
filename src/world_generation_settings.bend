import Base
import ./nbt.bend as N
import ./core.bend as C

# Durable identity of a generator. Unspecified is an honest legacy state; it
# never authorizes generating new terrain. Noise settings can be retained even
# while the density/biome/structure pipeline is unavailable to the client.
type Settings is Data:
  Unspecified{}
  Settings{dimension:String,min_y:U32,height:U32,seed:N.Word64,generator:Generator}

type Generator is Data:
  Flat{profile:String,biome:String,layers:List<&2,Layer>,features:Bool,lakes:Bool,structures:Maybe<&2,List<&2,String>>}
  Noise{settings:String,biome_source:BiomeSource}

type BiomeSource is Data:
  MultiNoisePreset{preset:String}
  EndBiomes{}
  FixedBiome{biome:String}

type Assignment is Data:
  Assignment{name:String,value:String}

type Layer is Data:
  Layer{height:U32,block:String,properties:List<&2,Assignment>}

def legacy() -> Settings:
  Unspecified{}

def is_legacy(settings:Settings) -> Bool:
  match settings:
    case Unspecified{}: True{}
    case _: False{}

def stone_dirt(seed:N.Word64) -> Settings:
  Settings{"minecraft:overworld",4294967232,384,seed,
    Flat{"bendex:stone-dirt-superflat","minecraft:plains",
      [Layer{1,"minecraft:stone",[]},Layer{2,"minecraft:dirt",[]},Layer{1,"minecraft:stone",[]}],
      False{},False{},Some{[]}}}

# These base layers and structure set IDs are taken from the pinned installed
# classic_flat preset. The settings retain the requests; base-layer population
# does not pretend to have executed the structure/feature pipeline.
def classic(seed:N.Word64) -> Settings:
  Settings{"minecraft:overworld",4294967232,384,seed,
    Flat{"minecraft:classic_flat","minecraft:plains",
      [Layer{1,"minecraft:bedrock",[]},Layer{2,"minecraft:dirt",[]},Layer{1,"minecraft:grass_block",[]}],
      False{},False{},Some{["minecraft:villages"]}}}

def normal(seed:N.Word64) -> Settings:
  Settings{"minecraft:overworld",4294967232,384,seed,
    Noise{"minecraft:overworld",MultiNoisePreset{"minecraft:overworld"}}}

def require(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}

def signed_le(a:U32,b:U32) -> Bool:
  U32.is_le(U32.xor(a,2147483648),U32.xor(b,2147483648))

def identifier_char(+code:U32) -> Bool:
  (U32.is_le(97,code) && U32.is_le(code,122)) ||
    (U32.is_le(48,code) && U32.is_le(code,57)) ||
    U32.is_eq(code,95) || U32.is_eq(code,45) || U32.is_eq(code,46)

def identifier_tail(text:String,+namespace:Bool,count:Nat,colon:Bool) -> Bool:
  match text:
    case SNil{}: colon && Bool.not(Nat.is_eq(count,0n))
    case SCon{Chr{58},rest}:
      namespace && Bool.not(Nat.is_eq(count,0n)) && identifier_tail(rest,False{},0n,True{})
    case SCon{Chr{+code},rest}:
      (identifier_char(code) || (Bool.not(namespace) && U32.is_eq(code,47))) &&
        identifier_tail(rest,namespace,1n+count,colon)

def identifier(name:String) -> Bool:
  identifier_tail(name,True{},0n,False{})

def property_tail(name:String) -> Bool:
  match name:
    case SNil{}: True{}
    case SCon{Chr{code},rest}: identifier_char(code) && property_tail(rest)

def property_name(name:String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{Chr{code},rest}: identifier_char(code) && property_tail(rest)

def properties_valid(properties:List<&2,Assignment>) -> Bool:
  match properties:
    case Nil{}: True{}
    case Assignment{name,value} <> rest:
      property_name(name) && property_name(value) && properties_valid(rest)

def layer_height(layers:List<&2,Layer>) -> Nat:
  match layers:
    case Nil{}: 0n
    case Layer{height,block,properties} <> rest: Nat.add(U32.to_nat(height),layer_height(rest))

def layers_valid(layers:List<&2,Layer>) -> Bool:
  match layers:
    case Nil{}: True{}
    case Layer{height,block,properties} <> rest:
      U32.is_le(height,2147483647) && identifier(block) && properties_valid(properties) && layers_valid(rest)

def names_valid(names:List<&2,String>) -> Bool:
  match names:
    case Nil{}: True{}
    case name <> rest: identifier(name) && names_valid(rest)

def structures_valid(structures:Maybe<&2,List<&2,String>>) -> Bool:
  match structures:
    case None{}: True{}
    case Some{names}: names_valid(names)

def biome_source_valid(source:BiomeSource) -> Bool:
  match source:
    case MultiNoisePreset{preset}: identifier(preset)
    case EndBiomes{}: True{}
    case FixedBiome{biome}: identifier(biome)

def generator_valid(generator:Generator,height:U32) -> Bool:
  match generator:
    case Flat{profile,biome,+layers,features,lakes,structures}:
      identifier(profile) && identifier(biome) && layers_valid(layers) &&
        Nat.is_le(layer_height(layers),U32.to_nat(height)) && structures_valid(structures)
    case Noise{settings,biome_source}: identifier(settings) && biome_source_valid(biome_source)

def valid(settings:Settings) -> Bool:
  match settings:
    case Unspecified{}: True{}
    case Settings{dimension,+min_y,+height,seed,generator}:
      C.dimension_known(dimension) && U32.is_eq(U32.and(min_y,15),0) &&
        U32.is_eq(U32.and(height,15),0) && U32.is_lt(0,height) && U32.is_le(height,2147483647) &&
        signed_le(min_y,U32.sub(U32.add(min_y,height),1)) && generator_valid(generator,height)

def validated(settings:Settings,valid:Bool) -> Result<&2,&2,String,Settings>:
  match valid:
    case True{}: Done{settings}
    case False{}: Fail{"invalid world generator settings"}

def validate(+settings:Settings) -> Result<&2,&2,String,Settings>:
  validated(settings,valid(settings))

def base_only_structures(structures:Maybe<&2,List<&2,String>>) -> Bool:
  match structures:
    case Some{Nil{}}: True{}
    case _: False{}

def base_only(settings:Settings) -> Bool:
  match settings:
    case Settings{dimension,min_y,height,seed,Flat{profile,biome,layers,features,lakes,structures}}:
      Bool.not(features) && Bool.not(lakes) && base_only_structures(structures)
    case _: False{}
