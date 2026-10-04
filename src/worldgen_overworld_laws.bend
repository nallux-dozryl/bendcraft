import Base
import ./worldgen_overworld.bend as O
import ./worldgen_noise_settings.bend as NS
import ./worldgen_noise_settings_codec.bend as NC
import ./worldgen_seed.bend as WS
import ./worldgen_biome.bend as B
import ./world_generation_settings.bend as WG
import ./nbt.bend as N
import ./json.bend as J
import ./random.bend as R

# Metadata/admission contracts concern the actual normal plan and consumer.
# Java observations, not these owner laws, establish the tested numerical bits.
type StoredInputs is Data:
  StoredInputs{generation:WG.Settings,definition:NS.Settings}

def prepared_inputs(result:Result<&2,&2,String,O.Plan>) -> Maybe<&2,StoredInputs>:
  match result:
    case Fail{message}: None{}
    case Done{O.Plan{generation,definition,root}}: Some{StoredInputs{generation,definition}}

def column_owner(result:O.Sampler & Result<&2,&2,String,O.Column>) -> O.Sampler:
  (owner,value) = result
  owner

law validated_definition_retains_complete_metadata:
  for +definition:NS.Settings
  for valid:{NS.valid(definition) == True{} : Bool}
  {NS.validate(definition) == Done{definition} : Result<&2,&2,String,NS.Settings>}

law actual_legacy_terrain_uses_all_seed_bits:
  for +seed:N.Word64
  for factory:R.Positional
  {WS.compiled_random(WS.Root{seed,True{},factory},"minecraft:terrain") ==
    Done{WS.source(seed,True{})} : Result<&2,&2,String,R.Source>}

law empty_name_budget_refuses_nonempty_name:
  for code:U32
  for rest:String
  {WS.ascii_bytes_with(0n,SCon{Chr{code},rest}) ==
    Fail{"worldgen seed name exceeds byte budget"} : Result<&2,&2,String,List<&2,U32>>}

law absent_aquifers_remain_absent:
  {NC.aquifers(None{}) == Done{None{}} : Result<&2,&2,String,Maybe<&2,J.Value>>}

law malformed_aquifers_are_refused:
  {NC.aquifers(Some{J.JNull{}}) == Fail{"noise-settings object required"} : Result<&2,&2,String,Maybe<&2,J.Value>>}

law omitted_debug_functions_use_actual_empty_default:
  {NC.debug_functions(None{}) == Done{J.JArray{[]}} : Result<&2,&2,String,J.Value>}

law admitted_plan_retains_saved_generation_and_loaded_definition:
  for +generation:WG.Settings
  for +definition:NS.Settings
  for valid:{WG.valid(generation) && NS.valid(definition) && O.geometry_matches(generation,definition) == True{} : Bool}
  for specified:{WG.is_legacy(generation) == False{} : Bool}
  {prepared_inputs(O.prepare(generation,definition)) == Some{StoredInputs{generation,definition}} : Maybe<&2,StoredInputs>}

law invalid_plan_is_refused_before_compilation:
  for +generation:WG.Settings
  for +definition:NS.Settings
  for invalid:{WG.valid(generation) && NS.valid(definition) && O.geometry_matches(generation,definition) == False{} : Bool}
  {O.prepare(generation,definition) == Fail{"normal Overworld generation/noise-settings identity or geometry mismatch"} : Result<&2,&2,String,O.Plan>}

law refused_column_retains_complete_sampler:
  for sampler:O.Sampler
  for +request:O.ColumnRequest
  for +budget:U32
  for invalid:{O.request_valid(request,budget) == False{} : Bool}
  {O.sample_column(sampler,request,budget) ==
    (sampler,Fail{"column density request exceeds signed-coordinate or sample budget"}) : O.Sampler & Result<&2,&2,String,O.Column>}

law climate_router_uses_the_actual_six_axes:
  for surface:J.Value
  for continents:J.Value
  for depth:J.Value
  for erosion:J.Value
  for density:J.Value
  for ridges:J.Value
  for temperature:J.Value
  for vegetation:J.Value
  {B.inputs(NS.Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}) ==
    B.Inputs{temperature,vegetation,continents,erosion,depth,ridges} : B.Inputs}

law quart_to_block_preserves_java_word_arithmetic:
  for x:U32
  for y:U32
  for z:U32
  {B.to_block(B.Quart{x,y,z}) == B.Block{U32.shln(x,2n),U32.shln(y,2n),U32.shln(z,2n)} : B.Block}

law fixed_biome_request_does_not_need_climate:
  for biome:String
  for quart:B.Quart
  {B.unavailable(B.Fixed{biome},quart) == Done{biome} : Result<&2,&2,String,String>}

law multi_noise_request_cannot_silently_choose_a_biome:
  for preset:String
  for definition:B.LoadedPreset
  for inputs:B.Inputs
  for quart:B.Quart
  {B.unavailable(B.MultiNoise{preset,definition,inputs},quart) ==
    Fail{"multi-noise biome sampling requires the compiled climate density graph and loaded preset parameter search"} : Result<&2,&2,String,String>}
