import Base
import ./worldgen_overworld_laws.bend as Laws
import ./worldgen_overworld.bend as O
import ./worldgen_noise_settings.bend as NS
import ./worldgen_noise_settings_codec.bend as NC
import ./worldgen_seed.bend as WS
import ./worldgen_biome.bend as B
import ./world_generation_settings.bend as WG

def Laws.validated_definition_retains_complete_metadata(definition,valid):
  %Equal.sym(Bool,NS.valid(definition),True{},valid) :
    {NS.validated(definition,_) == Done{definition} : Result<&2,&2,String,NS.Settings>}
  {==}

def Laws.actual_legacy_terrain_uses_all_seed_bits(seed,factory): {==}

def Laws.empty_name_budget_refuses_nonempty_name(code,rest): {==}

def Laws.absent_aquifers_remain_absent(): {==}

def Laws.malformed_aquifers_are_refused(): {==}

def Laws.omitted_debug_functions_use_actual_empty_default(): {==}

def truth_type(value:Bool) -> Data:
  match value:
    case False{}: Empty
    case True{}: Unit

def false_is_not_true(contradiction:{False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool,False{},True{},contradiction) : truth_type(_)
  Unit{}

def admitted_metadata(generation:WG.Settings,definition:NS.Settings,
    specified:{WG.is_legacy(generation) == False{} : Bool}) ->
    {Laws.prepared_inputs(O.admitted(generation,definition,True{})) == Some{Laws.StoredInputs{generation,definition}} : Maybe<&2,Laws.StoredInputs>}:
  match generation definition:
    case WG.Unspecified{} _:
      Empty.absurd({Laws.prepared_inputs(O.admitted(WG.Unspecified{},definition,True{})) == Some{Laws.StoredInputs{WG.Unspecified{},definition}} : Maybe<&2,Laws.StoredInputs>},
        false_is_not_true(Equal.sym(Bool,True{},False{},specified)))
    case WG.Settings{dimension,min_y,height,seed,generator}
        NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs}: {==}

def Laws.admitted_plan_retains_saved_generation_and_loaded_definition(generation,definition,valid,specified):
  %Equal.sym(Bool,WG.valid(generation) && NS.valid(definition) && O.geometry_matches(generation,definition),True{},valid) :
    {Laws.prepared_inputs(O.admitted(generation,definition,_)) == Some{Laws.StoredInputs{generation,definition}} : Maybe<&2,Laws.StoredInputs>}
  admitted_metadata(generation,definition,specified)

def invalid_admission(generation:WG.Settings,definition:NS.Settings) ->
    {O.admitted(generation,definition,False{}) == Fail{"normal Overworld generation/noise-settings identity or geometry mismatch"} : Result<&2,&2,String,O.Plan>}:
  match generation definition:
    case WG.Unspecified{} _: {==}
    case WG.Settings{dimension,min_y,height,seed,generator}
        NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs}: {==}

def Laws.invalid_plan_is_refused_before_compilation(generation,definition,invalid):
  %Equal.sym(Bool,WG.valid(generation) && NS.valid(definition) && O.geometry_matches(generation,definition),False{},invalid) :
    {O.admitted(generation,definition,_) == Fail{"normal Overworld generation/noise-settings identity or geometry mismatch"} : Result<&2,&2,String,O.Plan>}
  invalid_admission(generation,definition)

def refused_sampler(sampler:O.Sampler,request:O.ColumnRequest) ->
    {O.column_admitted(sampler,request,False{}) == (sampler,Fail{"column density request exceeds signed-coordinate or sample budget"}) : O.Sampler & Result<&2,&2,String,O.Column>}:
  match sampler request:
    case O.Sampler{plan,base} O.ColumnRequest{x,z,bottom,step,count}: {==}

def Laws.refused_column_retains_complete_sampler(sampler,request,budget,invalid):
  %Equal.sym(Bool,O.request_valid(request,budget),False{},invalid) :
    {O.column_admitted(sampler,request,_) == (sampler,Fail{"column density request exceeds signed-coordinate or sample budget"}) : O.Sampler & Result<&2,&2,String,O.Column>}
  refused_sampler(sampler,request)

def Laws.climate_router_uses_the_actual_six_axes(surface,continents,depth,erosion,density,ridges,temperature,vegetation): {==}

def Laws.quart_to_block_preserves_java_word_arithmetic(x,y,z): {==}

def Laws.fixed_biome_request_does_not_need_climate(biome,quart): {==}

def Laws.multi_noise_request_cannot_silently_choose_a_biome(preset,definition,inputs,quart): {==}
