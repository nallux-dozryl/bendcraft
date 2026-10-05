import Base
import ./sky_light_flat_authority.bend as A
import ./block_light.bend as B
import ./block_light_registry.bend as R
import ./world_generation_settings.bend as G
import ./sky_light.bend as S
import ./sky_light_world.bend as W
import ./core.bend as C
import ./nbt.bend as N

# Contracts over the actual immutable authority adapter. Generation validity
# uses G.valid and source-field admission uses W.bounds_valid. These laws do
# not prove a universal population-to-air geometry invariant.
law properties_delegate_to_complete_supplied_catalog:
  for +catalog:R.Catalog
  for generation:G.Settings
  for air:U32
  for sky:Bool
  for enabled:Bool
  for +state:U32
  {A.properties(A.Context{catalog,generation,air,sky,enabled},state) ==
    R.properties(catalog,state) : Maybe<&2,B.Descriptor>}

law occlusion_delegates_to_complete_supplied_catalog:
  for +catalog:R.Catalog
  for generation:G.Settings
  for air:U32
  for sky:Bool
  for enabled:Bool
  for +source:B.Descriptor
  for +target:B.Descriptor
  for +direction:B.Direction
  {A.occludes(A.Context{catalog,generation,air,sky,enabled},source,target,direction) ==
    R.occludes(catalog,source,target,direction) : Bool}

law unspecified_generation_cannot_supply_bounds:
  for catalog:R.Catalog
  for air:U32
  for sky:Bool
  for enabled:Bool
  for dimension:String
  {A.bounds(A.Context{catalog,G.Unspecified{},air,sky,enabled},dimension) == None{} : Maybe<&2,W.Bounds>}

law invalid_generation_cannot_supply_bounds:
  for catalog:R.Catalog
  for +generation:G.Settings
  for +air:U32
  for +sky:Bool
  for enabled:Bool
  for +dimension:String
  for invalid:{G.valid(generation) == False{} : Bool}
  {A.bounds(A.Context{catalog,generation,air,sky,enabled},dimension) == None{} : Maybe<&2,W.Bounds>}

law different_dimension_cannot_supply_bounds:
  for catalog:R.Catalog
  for +key:String
  for +minimum:U32
  for +height:U32
  for +seed:N.Word64
  for +generator:G.Generator
  for +air:U32
  for +sky:Bool
  for enabled:Bool
  for +dimension:String
  for different:{String.eq(key,dimension) == False{} : Bool}
  {A.bounds(A.Context{catalog,G.Settings{key,minimum,height,seed,generator},air,sky,enabled},dimension) ==
    None{} : Maybe<&2,W.Bounds>}

law unspecified_generation_cannot_authorize_empty_sections:
  for catalog:R.Catalog
  for air:U32
  for sky:Bool
  for enabled:Bool
  for position:C.Position
  {A.policy(A.Context{catalog,G.Unspecified{},air,sky,enabled},position) == W.Unknown{} : W.SectionPolicy}

law noise_generation_cannot_authorize_empty_sections:
  for catalog:R.Catalog
  for dimension:String
  for minimum:U32
  for height:U32
  for seed:N.Word64
  for settings:String
  for biome:G.BiomeSource
  for air:U32
  for sky:Bool
  for enabled:Bool
  for position:C.Position
  {A.policy(A.Context{catalog,G.Settings{dimension,minimum,height,seed,G.Noise{settings,biome}},air,sky,enabled},position) ==
    W.Unknown{} : W.SectionPolicy}

law nonbase_generation_cannot_authorize_empty_sections:
  for catalog:R.Catalog
  for +generation:G.Settings
  for air:U32
  for sky:Bool
  for enabled:Bool
  for +position:C.Position
  for nonbase:{G.base_only(generation) == False{} : Bool}
  {A.policy(A.Context{catalog,generation,air,sky,enabled},position) == W.Unknown{} : W.SectionPolicy}

law invalid_source_field_bounds_cannot_supply_bounds:
  for catalog:R.Catalog
  for +key:String
  for +minimum:U32
  for +height:U32
  for +seed:N.Word64
  for +generator:G.Generator
  for +air:U32
  for +sky:Bool
  for enabled:Bool
  for +dimension:String
  for invalid:{W.bounds_valid(W.Bounds{minimum,height,air,sky}) == False{} : Bool}
  {A.bounds(A.Context{catalog,G.Settings{key,minimum,height,seed,generator},air,sky,enabled},dimension) ==
    None{} : Maybe<&2,W.Bounds>}

law below_actual_layer_ceiling_cannot_authorize_empty_sections:
  for catalog:R.Catalog
  for +key:String
  for +minimum:U32
  for +height:U32
  for +seed:N.Word64
  for +profile:String
  for +biome:String
  for +layers:List<&2,G.Layer>
  for +features:Bool
  for +lakes:Bool
  for +structures:Maybe<&2,List<&2,String>>
  for air:U32
  for sky:Bool
  for enabled:Bool
  for +dimension:String
  for x:U32
  for +y:U32
  for z:U32
  for below:{S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))) == False{} : Bool}
  {A.policy(A.Context{catalog,G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}},air,sky,enabled},
    C.Position{dimension,x,y,z}) == W.Unknown{} : W.SectionPolicy}

law disabled_authority_never_enables_a_chunk:
  for catalog:R.Catalog
  for generation:G.Settings
  for air:U32
  for sky:Bool
  for position:C.Position
  {A.enabled(A.Context{catalog,generation,air,sky,False{}},position) == False{} : Bool}

law different_dimension_cannot_authorize_empty_sections:
  for catalog:R.Catalog
  for +key:String
  for +minimum:U32
  for +height:U32
  for +seed:N.Word64
  for +profile:String
  for +biome:String
  for +layers:List<&2,G.Layer>
  for +features:Bool
  for +lakes:Bool
  for +structures:Maybe<&2,List<&2,String>>
  for air:U32
  for sky:Bool
  for enabled:Bool
  for +dimension:String
  for x:U32
  for +y:U32
  for z:U32
  for different:{String.eq(key,dimension) == False{} : Bool}
  {A.policy(A.Context{catalog,G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}},air,sky,enabled},
    C.Position{dimension,x,y,z}) == W.Unknown{} : W.SectionPolicy}
