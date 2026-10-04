import Base
import ./worldgen_climate.bend as C
import ./worldgen_climate_codec.bend as CC
import ./worldgen_biome.bend as B
import ./f64.bend as F
import ./json.bend as J

# The immutable table/tree owner is distinct from the intentionally changing
# Java last-result cache. These projections retain every prepared input.
type Owner is Data:
  FixedOwner{biome:String}
  MultiOwner{identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,C.Entry>,tree:C.Tree}

def owner(resolver:C.Resolver) -> Owner:
  match resolver:
    case C.Fixed{biome}: FixedOwner{biome}
    case C.MultiNoise{identity,inputs,entries,tree,last}: MultiOwner{identity,inputs,entries,tree}

def lookup_owner(result:C.Resolver & Result<&2,&2,String,C.Selection>) -> Owner:
  (resolver,result) = result
  owner(resolver)

law admitted_tree_retains_complete_loaded_table_and_router:
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for tree:C.Tree
  {C.prepared_tree(identity,inputs,entries,Done{tree}) ==
    Done{C.MultiNoise{identity,inputs,entries,tree,None{}}} : Result<&2,&1,String,C.Resolver>}

law tree_failure_preserves_precise_diagnostic:
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for message:String
  {C.prepared_tree(identity,inputs,entries,Fail{message}) ==
    Fail{message} : Result<&2,&1,String,C.Resolver>}

law identity_refusal_precedes_tree_construction:
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for budget:Nat
  {C.prepare_checked(identity,inputs,entries,budget,False{}) ==
    Fail{"climate preset identity or loaded definition mismatch"} : Result<&2,&1,String,C.Resolver>}

law fixed_lookup_retains_biome_without_climate_search:
  for +biome:String
  for target:B.Target
  {C.resolve_target(C.Fixed{biome},target) ==
    (C.Fixed{biome},Done{C.Selection{biome,0,C.zero()}}) : C.Resolver & Result<&2,&2,String,C.Selection>}

law every_lookup_retains_complete_loaded_owner:
  for resolver:C.Resolver
  for +target:B.Target
  {lookup_owner(C.resolve_target(resolver,target)) == owner(resolver) : Owner}

law failed_lookup_retains_complete_owner_and_previous_history:
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for tree:C.Tree
  for last:Maybe<&2,C.Entry>
  for target:B.Target
  {C.resolved(identity,inputs,entries,tree,last,target,None{}) ==
    (C.MultiNoise{identity,inputs,entries,tree,last},Fail{"climate tree search produced no leaf"}) :
    C.Resolver & Result<&2,&2,String,C.Selection>}

law successful_lookup_records_actual_selected_leaf_and_fitness:
  for identity:B.LoadedPreset
  for inputs:B.Inputs
  for entries:List<&2,C.Entry>
  for tree:C.Tree
  for last:Maybe<&2,C.Entry>
  for +entry:C.Entry
  for +target:B.Target
  {C.resolved(identity,inputs,entries,tree,last,target,Some{entry}) ==
    (C.MultiNoise{identity,inputs,entries,tree,Some{entry}},Done{C.selected(entry,target)}) :
    C.Resolver & Result<&2,&2,String,C.Selection>}

law equal_signed_fitness_keeps_previous_leaf:
  for +candidate:C.Entry
  for +previous:C.Entry
  for +target:B.Target
  for tied:{C.compare(C.fitness(C.entry_space(candidate),target),C.fitness(C.entry_space(previous),target)) == EQ{} : Cmp}
  {C.select_better(candidate,target,Some{previous}) == Some{previous} : Maybe<&2,C.Entry>}

law climate_values_compose_the_actual_quantized_target:
  for resolver:C.Resolver
  for values:B.Values
  {C.resolve_values(resolver,values) == C.resolve_target(resolver,B.target(values)) :
    C.Resolver & Result<&2,&2,String,C.Selection>}

law empty_loaded_parameter_list_is_refused:
  for budget:Nat
  {CC.entry_array(J.JArray{[]},budget) == Fail{"climate parameter list must be nonempty"} :
    Result<&2,&2,String,List<&2,C.Entry>>}

law exhausted_entry_budget_refuses_unread_entries:
  for ordinal:U32
  for first:J.Value
  for rest:List<&2,J.Value>
  {CC.entries(0n,ordinal,first <> rest) == Fail{"climate parameter list exceeds entry budget"} :
    Result<&2,&2,String,List<&2,C.Entry>>}

law malformed_intervals_are_refused:
  for space:C.Space
  {CC.space_checked(space,False{}) == Fail{"climate intervals or offset outside native codec range"} :
    Result<&2,&2,String,C.Space>}
