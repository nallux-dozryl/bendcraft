import Base
import ./world_generation_settings_laws.bend as Laws
import ./world_generation_settings.bend as WG
import ./world_generation_settings_codec.bend as Codec
import ./nbt.bend as N

def Laws.validation_preserves_all_settings(settings,accepted):
  %Equal.sym(Bool,WG.valid(settings),True{},accepted) :
    {WG.validated(settings,_) == Done{settings} : Result<&2,&2,String,WG.Settings>}
  {==}

def Laws.validation_refuses_invalid_settings(settings,rejected):
  %Equal.sym(Bool,WG.valid(settings),False{},rejected) :
    {WG.validated(settings,_) == Fail{"invalid world generator settings"} : Result<&2,&2,String,WG.Settings>}
  {==}

def Laws.encode_refuses_invalid_settings(settings,rejected):
  %Equal.sym(Result<&2,&2,String,WG.Settings>,WG.validate(settings),Fail{"invalid world generator settings"},
    Laws.validation_refuses_invalid_settings(settings,rejected)) :
    {Result.bind(&2,&2,String,WG.Settings,List<&2,U32>,_,s => N.encode_with(Codec.limits(),Codec.root(s))) ==
      Fail{"invalid world generator settings"} : Result<&2,&2,String,List<&2,U32>>}
  {==}

def Laws.seed_tag_retains_all_64_bits(bits):
  {==}

def Laws.explicit_structure_request_retains_order(names):
  match names:
    case Nil{}: {==}
    case head <> rest: {==}

def Laws.unspecified_structures_remain_unspecified():
  {==}

def Laws.contradictory_structure_metadata_is_refused(name,rest):
  {==}

def Laws.explicit_empty_structures_authorize_base_only():
  {==}

def Laws.unspecified_structures_do_not_authorize_base_only():
  {==}

def Laws.requested_structures_do_not_authorize_base_only(name,rest):
  {==}

def Laws.classic_preset_does_not_silently_skip_villages(seed):
  {==}

def Laws.normal_generator_is_retained_as_noise(seed):
  {==}
