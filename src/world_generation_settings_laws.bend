# Contracts for durable generator requests. These certify identity/admission and
# exact scalar/tag decoding, not the complete NBT encode/decode roundtrip.
import Base
import ./world_generation_settings.bend as WG
import ./world_generation_settings_codec.bend as Codec
import ./nbt.bend as N

law validation_preserves_all_settings:
  for +settings:WG.Settings
  for accepted:{WG.valid(settings) == True{} : Bool}
  {WG.validate(settings) == Done{settings} : Result<&2,&2,String,WG.Settings>}

law validation_refuses_invalid_settings:
  for +settings:WG.Settings
  for rejected:{WG.valid(settings) == False{} : Bool}
  {WG.validate(settings) == Fail{"invalid world generator settings"} : Result<&2,&2,String,WG.Settings>}

law encode_refuses_invalid_settings:
  for +settings:WG.Settings
  for rejected:{WG.valid(settings) == False{} : Bool}
  {Codec.encode(settings) == Fail{"invalid world generator settings"} : Result<&2,&2,String,List<&2,U32>>}

law seed_tag_retains_all_64_bits:
  for bits:N.Word64
  {Codec.seed_value(N.Long{bits}) == Done{bits} : Result<&2,&2,String,N.Word64>}

law explicit_structure_request_retains_order:
  for names:List<&2,String>
  {Codec.structures_result(True{},names) == Done{Some{names}} : Result<&2,&2,String,Maybe<&2,List<&2,String>>>}

law unspecified_structures_remain_unspecified:
  {Codec.structures_result(False{},[]) == Done{None{}} : Result<&2,&2,String,Maybe<&2,List<&2,String>>>}

law contradictory_structure_metadata_is_refused:
  for name:String
  for rest:List<&2,String>
  {Codec.structures_result(False{},name <> rest) == Fail{"unspecified structures must have an empty entries list"} : Result<&2,&2,String,Maybe<&2,List<&2,String>>>}

law explicit_empty_structures_authorize_base_only:
  {WG.base_only_structures(Some{[]}) == True{} : Bool}

law unspecified_structures_do_not_authorize_base_only:
  {WG.base_only_structures(None{}) == False{} : Bool}

law requested_structures_do_not_authorize_base_only:
  for name:String
  for rest:List<&2,String>
  {WG.base_only_structures(Some{name <> rest}) == False{} : Bool}

law classic_preset_does_not_silently_skip_villages:
  for seed:N.Word64
  {WG.base_only(WG.classic(seed)) == False{} : Bool}

law normal_generator_is_retained_as_noise:
  for seed:N.Word64
  {WG.normal(seed) == WG.Settings{"minecraft:overworld",4294967232,384,seed,
    WG.Noise{"minecraft:overworld",WG.MultiNoisePreset{"minecraft:overworld"}}} : WG.Settings}
