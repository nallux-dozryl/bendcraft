import Base
import ./sky_light_flat_authority.bend as A
import ./block_light.bend as B
import ./block_light_registry.bend as R
import ./world_generation_settings.bend as G
import ./sky_light.bend as S
import ./sky_light_world.bend as W
import ./core.bend as C
import ./sky_light_flat_authority_laws.bend as L

def and_false_right(value:Bool) -> {(value && False{}) == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def policy_false_prefix(+prefix:Bool,a:Bool,b:Bool,c:Bool,d:Bool) ->
    {A.policy_checked(prefix && False{} && a && b && c && d) == W.Unknown{} : W.SectionPolicy}:
  %Equal.sym(Bool,prefix && False{},False{},and_false_right(prefix)) :
    {A.policy_checked(_ && a && b && c && d) == W.Unknown{} : W.SectionPolicy}
  {==}

def policy_false_last(+prefix:Bool,suffix:Bool) ->
    {A.policy_checked(prefix && False{} && suffix) == W.Unknown{} : W.SectionPolicy}:
  %Equal.sym(Bool,prefix && False{},False{},and_false_right(prefix)) :
    {A.policy_checked(_ && suffix) == W.Unknown{} : W.SectionPolicy}
  {==}

def L.properties_delegate_to_complete_supplied_catalog(catalog,generation,air,sky,enabled,state): {==}
def L.occlusion_delegates_to_complete_supplied_catalog(catalog,generation,air,sky,enabled,source,target,direction): {==}
def L.unspecified_generation_cannot_supply_bounds(catalog,air,sky,enabled,dimension): {==}

def L.invalid_generation_cannot_supply_bounds(catalog,generation,air,sky,enabled,dimension,invalid):
  match generation:
    case G.Unspecified{}: {==}
    case G.Settings{key,minimum,height,seed,generator}:
      %Equal.sym(Bool,G.valid(G.Settings{key,minimum,height,seed,generator}),False{},invalid) :
        {A.bounds_checked(minimum,height,air,sky,_ && String.eq(key,dimension) && W.bounds_valid(W.Bounds{minimum,height,air,sky})) == None{} : Maybe<&2,W.Bounds>}
      {==}

def L.different_dimension_cannot_supply_bounds(catalog,key,minimum,height,seed,generator,air,sky,enabled,dimension,different):
  %Equal.sym(Bool,String.eq(key,dimension),False{},different) :
    {A.bounds_checked(minimum,height,air,sky,G.valid(G.Settings{key,minimum,height,seed,generator}) && _ && W.bounds_valid(W.Bounds{minimum,height,air,sky})) == None{} : Maybe<&2,W.Bounds>}
  %Equal.sym(Bool,G.valid(G.Settings{key,minimum,height,seed,generator}) && False{},False{},
      and_false_right(G.valid(G.Settings{key,minimum,height,seed,generator}))) :
    {A.bounds_checked(minimum,height,air,sky,_ && W.bounds_valid(W.Bounds{minimum,height,air,sky})) == None{} : Maybe<&2,W.Bounds>}
  {==}

def L.unspecified_generation_cannot_authorize_empty_sections(catalog,air,sky,enabled,position): {==}
def L.noise_generation_cannot_authorize_empty_sections(catalog,dimension,minimum,height,seed,settings,biome,air,sky,enabled,position): {==}

def L.nonbase_generation_cannot_authorize_empty_sections(catalog,generation,air,sky,enabled,position,nonbase):
  match generation position:
    case G.Unspecified{} _: {==}
    case G.Settings{key,minimum,height,seed,G.Noise{settings,biome}} _: {==}
    case G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}} C.Position{dimension,x,y,z}:
      %Equal.sym(Bool,G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}),False{},nonbase) :
        {A.policy_checked(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) && _ &&
          String.eq(key,dimension) && U32.is_eq(U32.and(y,15),0) &&
          S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))) && S.signed_lt(y,U32.add(minimum,height))) == W.Unknown{} : W.SectionPolicy}
      policy_false_prefix(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}),
        String.eq(key,dimension),U32.is_eq(U32.and(y,15),0),
        S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))),S.signed_lt(y,U32.add(minimum,height)))

def L.invalid_source_field_bounds_cannot_supply_bounds(catalog,key,minimum,height,seed,generator,air,sky,enabled,dimension,invalid):
  %Equal.sym(Bool,W.bounds_valid(W.Bounds{minimum,height,air,sky}),False{},invalid) :
    {A.bounds_checked(minimum,height,air,sky,G.valid(G.Settings{key,minimum,height,seed,generator}) && String.eq(key,dimension) && _) == None{} : Maybe<&2,W.Bounds>}
  %Equal.sym(Bool,(G.valid(G.Settings{key,minimum,height,seed,generator}) && String.eq(key,dimension)) && False{},False{},
      and_false_right(G.valid(G.Settings{key,minimum,height,seed,generator}) && String.eq(key,dimension))) :
    {A.bounds_checked(minimum,height,air,sky,_) == None{} : Maybe<&2,W.Bounds>}
  {==}

def L.below_actual_layer_ceiling_cannot_authorize_empty_sections(catalog,key,minimum,height,seed,profile,biome,layers,features,lakes,structures,air,sky,enabled,dimension,x,y,z,below):
  %Equal.sym(Bool,S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))),False{},below) :
    {A.policy_checked(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
      G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) && String.eq(key,dimension) &&
      U32.is_eq(U32.and(y,15),0) && _ && S.signed_lt(y,U32.add(minimum,height))) == W.Unknown{} : W.SectionPolicy}
  policy_false_last(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
    G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
    String.eq(key,dimension) && U32.is_eq(U32.and(y,15),0),S.signed_lt(y,U32.add(minimum,height)))

def L.disabled_authority_never_enables_a_chunk(catalog,generation,air,sky,position):
  match generation:
    case G.Unspecified{}: {==}
    case G.Settings{dimension,minimum,height,seed,generator}: {==}

def L.different_dimension_cannot_authorize_empty_sections(catalog,key,minimum,height,seed,profile,biome,layers,features,lakes,structures,air,sky,enabled,dimension,x,y,z,different):
  %Equal.sym(Bool,String.eq(key,dimension),False{},different) :
    {A.policy_checked(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
      G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) && _ &&
      U32.is_eq(U32.and(y,15),0) && S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))) &&
      S.signed_lt(y,U32.add(minimum,height))) == W.Unknown{} : W.SectionPolicy}
  %Equal.sym(Bool,(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
      G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}})) && False{},False{},
      and_false_right(G.valid(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}) &&
        G.base_only(G.Settings{key,minimum,height,seed,G.Flat{profile,biome,layers,features,lakes,structures}}))) :
    {A.policy_checked(_ && U32.is_eq(U32.and(y,15),0) &&
      S.signed_ge(y,U32.add(minimum,U32.from_nat(G.layer_height(layers)))) && S.signed_lt(y,U32.add(minimum,height))) == W.Unknown{} : W.SectionPolicy}
  {==}
