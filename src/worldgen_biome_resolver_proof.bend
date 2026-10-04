import Base
import ./worldgen_biome_resolver_laws.bend as L
import ./worldgen_biome_resolver.bend as BR
import ./worldgen_density_router.bend as R
import ./worldgen_density_router_laws.bend as RL
import ./worldgen_density_router_proof.bend as RP
import ./worldgen_density_state.bend as S
import ./worldgen_climate.bend as C
import ./worldgen_climate_laws.bend as CL
import ./worldgen_climate_proof.bend as CP
import ./worldgen_biome.bend as B

def L.mismatched_loaded_router_refusal_retains_complete_density_owner(router,generation,loaded,budget):
  match loaded:
    case C.Loaded{identity,entries}: {==}
def L.biome_plan_refusal_retains_complete_density_owner(router,loaded,budget,message): {==}
def L.loaded_biome_plan_uses_the_actual_climate_tree_preparer(router,loaded,budget,plan): {==}
def L.quart_sampling_uses_the_actual_wrapping_block_coordinate_conversion(quart): {==}
def L.fixed_biome_sampling_retains_every_density_field_without_evaluation(router,biome,depth,quart):
  match router:
    case R.State{definition,roots,S.State{program,pool,cache}}: {==}
def L.refused_climate_density_does_not_search_or_change_the_loaded_resolver(router,resolver,message): {==}
def L.zero_depth_unblended_biome_sample_retains_the_complete_composed_owner(definition,c,d,e,r,t,v,program,pool,cache,identity,inputs,entries,tree,last,quart): {==}
def L.sampled_axes_join_the_actual_climate_quantizer_and_search(router,resolver,values): {==}

def completed_lookup_owner(router:R.State,identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,C.Entry>,
    tree:C.Tree,last:Maybe<&2,C.Entry>,target:B.Target,found:Maybe<&2,C.Entry>) ->
    {L.returned_owner(BR.completed(router,C.resolved(identity,inputs,entries,tree,last,target,found))) ==
      L.Owner{RL.owner(router),CL.MultiOwner{identity,inputs,entries,tree}} : L.Owner}:
  match found:
    case None{}: {==}
    case Some{entry}: {==}

def L.climate_lookup_retains_complete_router_and_loaded_preset_owner(router,resolver,values):
  match resolver:
    case C.Fixed{biome}: {==}
    case C.MultiNoise{identity,inputs,entries,+tree,+last}:
      +target = B.target(values)
      completed_lookup_owner(router,identity,inputs,entries,tree,last,target,C.search(tree,target,last))

def L.density_cache_rollback_retains_router_program_and_ordered_noise_pool(router,original):
  match router:
    case R.State{definition,roots,S.State{program,pool,cache}}: {==}
def L.resolver_history_rollback_retains_complete_loaded_table_and_tree(resolver,original):
  match resolver:
    case C.Fixed{biome}: {==}
    case C.MultiNoise{identity,inputs,entries,tree,last}: {==}
def L.refused_join_restores_both_cache_and_previous_leaf_history(router,identity,inputs,entries,tree,current,original,cache,message): {==}
def L.successful_join_retains_the_actual_returned_sampler_and_search_history(cache,previous,state,selected):
  match state:
    case BR.State{router,resolver}: {==}
