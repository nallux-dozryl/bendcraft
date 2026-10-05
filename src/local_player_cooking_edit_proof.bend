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
