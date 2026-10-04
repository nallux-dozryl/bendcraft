import Base
import ./worldgen_biome_resolver.bend as BR
import ./worldgen_density_router.bend as R
import ./worldgen_density_router_laws.bend as RL
import ./worldgen_density_ast.bend as A
import ./worldgen_density_state.bend as S
import ./worldgen_climate.bend as C
import ./worldgen_climate_laws.bend as CL
import ./worldgen_biome.bend as B
import ./worldgen_noise_settings.bend as NS
import ./worldgen_overworld.bend as O
import ./f64.bend as F

type Owner is Type:
  Owner{router:RL.Owner,resolver:CL.Owner}

def owner(state:BR.State) -> Owner:
  match state:
    case BR.State{router,resolver}: Owner{RL.owner(router),CL.owner(resolver)}

def returned_owner(result:BR.State & Result<&2,&2,String,C.Selection>) -> Owner:
  (state,status) = result
  owner(state)

law mismatched_loaded_router_refusal_retains_complete_density_owner:
  for router:R.State
  for generation:O.Plan
  for loaded:C.Loaded
  for budget:Nat
  {BR.admitted(router,generation,loaded,budget,False{}) ==
    (router,Fail{"compiled density router differs from retained generation settings"}) :
    R.State & Result<&2,&1,String,C.Resolver>}

law biome_plan_refusal_retains_complete_density_owner:
  for router:R.State
  for loaded:C.Loaded
  for budget:Nat
  for message:String
  {BR.prepared(router,loaded,budget,Fail{message}) == (router,Fail{message}) :
    R.State & Result<&2,&1,String,C.Resolver>}

law loaded_biome_plan_uses_the_actual_climate_tree_preparer:
  for router:R.State
  for loaded:C.Loaded
  for budget:Nat
  for plan:B.Plan
  {BR.prepared(router,loaded,budget,Done{plan}) == (router,C.prepare(plan,loaded,budget)) :
    R.State & Result<&2,&1,String,C.Resolver>}

law quart_sampling_uses_the_actual_wrapping_block_coordinate_conversion:
  for quart:B.Quart
  {BR.point(quart) == BR.block_point(B.to_block(quart)) : S.Point}

law fixed_biome_sampling_retains_every_density_field_without_evaluation:
  for router:R.State
  for +biome:String
  for depth:Nat
  for quart:B.Quart
  {BR.sample(BR.State{router,C.Fixed{biome}},depth,quart) ==
    (BR.State{router,C.Fixed{biome}},Done{C.Selection{biome,0,C.zero()}}) :
    BR.State & Result<&2,&2,String,C.Selection>}

law refused_climate_density_does_not_search_or_change_the_loaded_resolver:
  for router:R.State
  for resolver:C.Resolver
  for message:String
  {BR.climate_completed(resolver,(router,Fail{message})) ==
    (BR.State{router,resolver},Fail{message}) : BR.State & Result<&2,&2,String,C.Selection>}

law zero_depth_unblended_biome_sample_retains_the_complete_composed_owner:
  for definition:NS.Router
  for c:U32
  for d:U32
  for e:U32
  for r:U32
  for t:U32
  for v:U32
  for program:A.Program
  for pool:List<&1,S.Slot>
  for cache:S.Cache
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for tree:C.Tree
  for last:Maybe<&2,C.Entry>
  for quart:B.Quart
  {BR.sample(BR.State{R.State{definition,R.UnblendedRoots{R.ClimateRoots{c,d,e,r,t,v}},S.State{program,pool,cache}},
    C.MultiNoise{identity,inputs,entries,tree,last}},0n,quart) ==
    (BR.State{R.State{definition,R.UnblendedRoots{R.ClimateRoots{c,d,e,r,t,v}},S.State{program,pool,cache}},
      C.MultiNoise{identity,inputs,entries,tree,last}},Fail{"density evaluation exceeds caller depth budget"}) :
    BR.State & Result<&2,&2,String,C.Selection>}

law sampled_axes_join_the_actual_climate_quantizer_and_search:
  for router:R.State
  for resolver:C.Resolver
  for values:B.Values
  {BR.climate_completed(resolver,(router,Done{values})) ==
    BR.completed(router,C.resolve_values(resolver,values)) : BR.State & Result<&2,&2,String,C.Selection>}

law climate_lookup_retains_complete_router_and_loaded_preset_owner:
  for router:R.State
  for resolver:C.Resolver
  for values:B.Values
  {returned_owner(BR.climate_completed(resolver,(router,Done{values}))) ==
    Owner{RL.owner(router),CL.owner(resolver)} : Owner}

law density_cache_rollback_retains_router_program_and_ordered_noise_pool:
  for router:R.State
  for original:S.Cache
  {RL.owner(BR.restore_router(router,original)) == RL.owner(router) : RL.Owner}

law resolver_history_rollback_retains_complete_loaded_table_and_tree:
  for resolver:C.Resolver
  for original:Maybe<&2,C.Entry>
  {CL.owner(BR.restore_history(resolver,original)) == CL.owner(resolver) : CL.Owner}

law refused_join_restores_both_cache_and_previous_leaf_history:
  for router:R.State
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for tree:C.Tree
  for current:Maybe<&2,C.Entry>
  for original:Maybe<&2,C.Entry>
  for cache:S.Cache
  for message:String
  {BR.transaction(cache,original,(BR.State{router,C.MultiNoise{identity,inputs,entries,tree,current}},Fail{message})) ==
    (BR.State{BR.restore_router(router,cache),C.MultiNoise{identity,inputs,entries,tree,original}},Fail{message}) :
    BR.State & Result<&2,&2,String,C.Selection>}

law successful_join_retains_the_actual_returned_sampler_and_search_history:
  for cache:S.Cache
  for previous:Maybe<&2,C.Entry>
  for state:BR.State
  for selected:C.Selection
  {BR.transaction(cache,previous,(state,Done{selected})) == (state,Done{selected}) :
    BR.State & Result<&2,&2,String,C.Selection>}
