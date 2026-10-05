import Base
import ./entity_membership_codec.bend as C
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R
import ./geometry.bend as A
import ./nbt.bend as N

# Raw storage must not normalize exceptional coordinates, UUIDs or packed keys.
law box_words_preserve_every_endpoint:
  for box:A.AABB
  {C.box_read(C.box_value(box)) == Done{box} : Result<&2,&2,String,A.AABB>}

law uuid_words_preserve_complete_identity:
  for uuid:E.Uuid
  {C.uuid_read(C.uuid_value(uuid)) == Done{uuid} : Result<&2,&2,String,E.Uuid>}

law packed_key_words_are_lossless:
  for key:M.SectionKey
  {C.key_read(C.key_value(key)) == Done{key} : Result<&2,&2,String,M.SectionKey>}

law closed_visibility_projection_is_lossless:
  for visibility:M.Visibility
  {C.visibility_read(C.visibility_value(visibility)) == Done{visibility} : Result<&2,&2,String,M.Visibility>}

# Quantify all five lists, not a membership subset or flattened owner image.
# This includes invalid images and arbitrary limits: encode refusal cannot
# consume, rebuild, normalize or replace the actual sole manager owner.
law inspect_save_retains_complete_manager_and_actual_encoding:
  for +limits:N.Limits
  for +view:M.View
  {C.inspect_encode(limits,M.State{view}) == (M.State{view},C.encode(limits,view)) :
    M.State & Result<&2,&2,String,List<&2,U32>>}
