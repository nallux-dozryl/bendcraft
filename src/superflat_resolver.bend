import Base
import ./world_generation_settings.bend as WG
import ./superflat_population.bend as P
import ./registry.bend as B

# Registry resolution is an owner transfer before pure population begins.
def assignments(properties:List<&2,WG.Assignment>) -> List<&2,B.Assignment>:
  match properties:
    case Nil{}: []
    case WG.Assignment{name,value} <> rest: B.Assignment{name,value} <> assignments(rest)

def layer_resolved(height:U32,acc:List<&2,P.Layer>,result:B.Registry & Result<&2,&2,B.Error,U32>,
    next:B.Registry -> List<&2,P.Layer> -> B.Registry & Result<&2,&2,String,List<&2,P.Layer>>) -> B.Registry & Result<&2,&2,String,List<&2,P.Layer>>:
  (registry,status) = result
  match status:
    case Fail{error}: (registry,Fail{B.error_text(error)})
    case Done{state}: next(registry,P.Layer{height,state} <> acc)

def resolve_layers(layers:List<&2,WG.Layer>,registry:B.Registry,acc:List<&2,P.Layer>) -> B.Registry & Result<&2,&2,String,List<&2,P.Layer>>:
  match layers:
    case Nil{}: (registry,Done{List.reverse(&2,P.Layer,acc)})
    case WG.Layer{height,block,properties} <> rest:
      layer_resolved(height,acc,B.Registry.resolve(registry,block,assignments(properties),B.Defaults{}),r => xs => resolve_layers(rest,r,xs))

def resolved_layers(dimension:String,min_y:U32,height:U32,air:U32,result:B.Registry & Result<&2,&2,String,List<&2,P.Layer>>) -> B.Registry & Result<&2,&2,String,P.Flat>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{message})
    case Done{layers}: (registry,Done{P.Flat{dimension,min_y,height,air,layers}})

def resolved_air(dimension:String,min_y:U32,height:U32,layers:List<&2,WG.Layer>,result:B.Registry & Result<&2,&2,B.Error,U32>) -> B.Registry & Result<&2,&2,String,P.Flat>:
  (registry,status) = result
  match status:
    case Fail{error}: (registry,Fail{B.error_text(error)})
    case Done{air}: resolved_layers(dimension,min_y,height,air,resolve_layers(layers,registry,[]))

def resolve_generator(registry:B.Registry,dimension:String,min_y:U32,height:U32,generator:WG.Generator) -> B.Registry & Result<&2,&2,String,P.Flat>:
  match generator:
    case WG.Noise{settings,biome_source}: (registry,Fail{"noise generation unavailable: density, biome and structure pipeline required"})
    case WG.Flat{profile,biome,layers,features,lakes,structures}:
      resolved_air(dimension,min_y,height,layers,B.Registry.resolve(registry,"minecraft:air",[],B.Defaults{}))

def resolve_validated(registry:B.Registry,result:Result<&2,&2,String,WG.Settings>) -> B.Registry & Result<&2,&2,String,P.Flat>:
  match result:
    case Fail{message}: (registry,Fail{message})
    case Done{WG.Unspecified{}}: (registry,Fail{"generator settings unavailable for legacy save"})
    case Done{WG.Settings{dimension,min_y,height,seed,generator}}:
      resolve_generator(registry,dimension,min_y,height,generator)

def resolve(registry:B.Registry,settings:WG.Settings) -> B.Registry & Result<&2,&2,String,P.Flat>:
  resolve_validated(registry,WG.validate(settings))

