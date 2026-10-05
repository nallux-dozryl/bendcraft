import Base
import ./local_player_cooking_edit_laws.bend as Laws

def Laws.disabled_build_retains_complete_core_and_cooking_owner(world,sidecar,cap,position,state,expected,sequence):
  {==}

def Laws.observer_retains_complete_core_and_cooking_owner(world,sidecar,position,state,expected,sequence,maybuild):
  match maybuild:
    case False{}: {==}
    case True{}: {==}

def Laws.invalid_player_retains_complete_core_and_cooking_owner(world,sidecar,position,state,expected,sequence,maybuild):
  match maybuild:
    case False{}: {==}
    case True{}: {==}

def Laws.refused_prepared_edit_retains_core_light_and_entry_owners(operation,position,classification,light,loading,entries,views,world,error):
  {==}

def Laws.incarnation_exhaustion_retains_prepared_owners(world,entries,views,operation,classification,cap,position,state,expected,sequence,maybuild):
  {==}

def Laws.refused_capacity_result_retains_complete_owner(world,sidecar):
  {==}

def Laws.no_reset_has_capacity_at_every_counter(incarnations,headers):
  {==}
