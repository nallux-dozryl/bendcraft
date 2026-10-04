import Base
import ./block_light_registry.bend as R
import ./block_light_registry_decoder.bend as D
import ./block_light_registry_laws.bend as L
import ./block_light.bend as B

def L.outside_registry_cannot_manufacture_a_dark_descriptor(identity,count,shapes,entries,rows,state,outside):
  %Equal.sym(Bool,U32.is_lt(state,count),False{},outside) :
    {R.properties_valid(R.Catalog{identity,count,shapes,entries,rows},state,_) == None{} : Maybe<&2,B.Descriptor>}
  {==}
def L.outside_registry_face_is_an_explicit_error(identity,count,shapes,entries,rows,state,direction,outside):
  %Equal.sym(Bool,U32.is_lt(state,count),False{},outside) :
    {R.state_face_valid(R.Catalog{identity,count,shapes,entries,rows},state,direction,_) ==
      Fail{R.UnknownState{state}} : Result<&2,&2,R.Error,U32>}
  {==}
def L.missing_registry_entry_is_unknown(state,entries): {==}
def L.source_failure_has_error_priority(catalog,error,target): {==}
def L.unavailable_occlusion_fails_closed(error): {==}
def L.unsigned_face_bit31_is_not_a_negative_word(): {==}
def L.face_bit32_uses_the_next_packed_word(rows): {==}
def L.truncated_packed_row_is_explicitly_unavailable(rows): {==}
def L.noncontiguous_or_overflowing_range_cannot_enter_catalog(line,states,next,entries,first,count,entry,invalid):
  %Equal.sym(Bool,(U32.is_eq(first,next) && U32.is_le(first,states) && U32.is_le(count,U32.sub(states,first))),False{},invalid) :
    {D.range_built(line,states,next,entries,D.Range{first,count,entry},_) ==
      Fail{D.Schema{line,"noncontiguous or overflowing state range"}} : Result<&2,&1,D.Error,U32 & Map<&2,Maybe<&2,R.Entry>>>}
  {==}
def L.noncanonical_decimal_state_fields_are_rejected(line): {==}
def L.untrusted_bytes_cannot_reach_the_decoder(identity,count,limit,bytes): {==}
