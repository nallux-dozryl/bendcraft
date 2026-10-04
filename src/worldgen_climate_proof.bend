import Base
import ./worldgen_climate_laws.bend as L
import ./worldgen_climate.bend as C
import ./worldgen_biome.bend as B

def L.admitted_tree_retains_complete_loaded_table_and_router(identity,inputs,entries,tree): {==}
def L.tree_failure_preserves_precise_diagnostic(identity,inputs,entries,message): {==}
def L.identity_refusal_precedes_tree_construction(identity,inputs,entries,budget): {==}
def L.fixed_lookup_retains_biome_without_climate_search(biome,target): {==}

def resolved_owner(identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,C.Entry>,tree:C.Tree,
    last:Maybe<&2,C.Entry>,target:B.Target,found:Maybe<&2,C.Entry>) ->
    {L.lookup_owner(C.resolved(identity,inputs,entries,tree,last,target,found)) ==
      L.MultiOwner{identity,inputs,entries,tree} : L.Owner}:
  match found:
    case None{}: {==}
    case Some{entry}: {==}

def L.every_lookup_retains_complete_loaded_owner(resolver,target):
  match resolver:
    case C.Fixed{biome}: {==}
    case C.MultiNoise{identity,inputs,entries,+tree,+last}:
      resolved_owner(identity,inputs,entries,tree,last,target,C.search(tree,target,last))

def L.failed_lookup_retains_complete_owner_and_previous_history(identity,inputs,entries,tree,last,target): {==}
def L.successful_lookup_records_actual_selected_leaf_and_fitness(identity,inputs,entries,tree,last,entry,target): {==}
def L.equal_signed_fitness_keeps_previous_leaf(candidate,previous,target,tied):
  %Equal.sym(Cmp,C.compare(C.fitness(C.entry_space(candidate),target),C.fitness(C.entry_space(previous),target)),EQ{},tied) : {C.gate(Maybe<&2,C.Entry>,Cmp.is_lt(_),u => Some{candidate},u => Some{previous}) ==
    Some{previous} : Maybe<&2,C.Entry>}
  {==}
def L.climate_values_compose_the_actual_quantized_target(resolver,values): {==}
def L.empty_loaded_parameter_list_is_refused(budget): {==}
def L.exhausted_entry_budget_refuses_unread_entries(ordinal,first,rest): {==}
def L.malformed_intervals_are_refused(space): {==}
