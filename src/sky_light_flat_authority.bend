import Base
import ./block_light.bend as B
import ./block_light_registry.bend as R
import ./core.bend as C
import ./world_generation_settings.bend as G
import ./sky_light.bend as S
import ./sky_light_world.bend as W

# All members are immutable authority, never a second Core/world owner. The
# caller binds the authenticated catalog, actual saved generation settings,
# registry-resolved air, dimension sky policy and initial chunk enablement.
type Context is Data:
  Context{catalog:R.Catalog,generation:G.Settings,air:U32,has_sky:Bool,enabled:Bool}
def properties(context:Context,state:U32) -> Maybe<&2,B.Descriptor>:
  Context{catalog,generation,air,sky,enabled} = context
  R.properties(catalog,state)
def occludes(context:Context,source:B.Descriptor,target:B.Descriptor,direction:B.Direction) -> Bool:
  Context{catalog,generation,air,sky,enabled} = context
  R.occludes(catalog,source,target,direction)
def bounds_checked(minimum:U32,height:U32,air:U32,sky:Bool,valid:Bool) -> Maybe<&2,W.Bounds>:
  match valid:
    case False{}: None{}
    case True{}: Some{W.Bounds{minimum,height,air,sky}}
def bounds(context:Context,dimension:String) -> Maybe<&2,W.Bounds>:
  Context{catalog,+generation,+air,+sky,enabled} = context
  match generation:
    case G.Unspecified{}: None{}
    case G.Settings{key,+minimum,+height,seed,generator}:
      bounds_checked(minimum,height,air,sky,G.valid(generation) && String.eq(key,dimension) &&
        W.bounds_valid(W.Bounds{minimum,height,air,sky}))
def policy_checked(valid:Bool) -> W.SectionPolicy:
  match valid:
    case False{}: W.Unknown{}
    case True{}: W.KnownEmpty{}
def policy_generation(+generation:G.Settings,position:C.Position) -> W.SectionPolicy:
  match generation:
    case G.Unspecified{}: W.Unknown{}
    case G.Settings{key,minimum,height,seed,G.Noise{settings,biome}}: W.Unknown{}
    case G.Settings{+key,+minimum,+height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}:
      C.Position{dimension,x,+y,z} = position
      policy_checked(G.valid(generation) && G.base_only(generation) && String.eq(key,dimension) &&
        U32.is_eq(U32.and(y,15),0) &&
        S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))) &&
        S.signed_lt(y,U32.add(minimum,height)))
def policy(context:Context,position:C.Position) -> W.SectionPolicy:
  Context{catalog,generation,air,sky,enabled} = context
  policy_generation(generation,position)
def enabled(context:Context,position:C.Position) -> Bool:
  Context{catalog,+generation,air,sky,admitted} = context
  match generation:
    case G.Unspecified{}: False{}
    case G.Settings{dimension,minimum,height,seed,generator}:
      admitted && G.valid(generation) && String.eq(dimension,C.dimension(position))
