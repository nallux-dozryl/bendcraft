import Base
import ./block_light_registry.bend as R
import ./block_light_registry_decoder.bend as D
import ./block_light_registry_loader.bend as L
import ./block_light.bend as B

law outside_registry_cannot_manufacture_a_dark_descriptor:
  for identity:String
  for +count:U32
  for shapes:U32
  for entries:Map<&2,Maybe<&2,R.Entry>>
  for rows:Map<&2,Maybe<&2,List<&2,U32>>>
  for +state:U32
  for outside:{U32.is_lt(state,count) == False{} : Bool}
  {R.properties(R.Catalog{identity,count,shapes,entries,rows},state) == None{} : Maybe<&2,B.Descriptor>}

law outside_registry_face_is_an_explicit_error:
  for identity:String
  for +count:U32
  for shapes:U32
  for entries:Map<&2,Maybe<&2,R.Entry>>
  for rows:Map<&2,Maybe<&2,List<&2,U32>>>
  for +state:U32
  for direction:B.Direction
  for outside:{U32.is_lt(state,count) == False{} : Bool}
  {R.state_face(R.Catalog{identity,count,shapes,entries,rows},state,direction) ==
    Fail{R.UnknownState{state}} : Result<&2,&2,R.Error,U32>}

law missing_registry_entry_is_unknown:
  for state:U32
  for entries:Map<&2,Maybe<&2,R.Entry>>
  {R.state_read(state,(entries,None{})) == None{} : Maybe<&2,B.Descriptor>}

law source_failure_has_error_priority:
  for catalog:R.Catalog
  for +error:R.Error
  for target:Result<&2,&2,R.Error,U32>
  {R.occlusion_faces(catalog,Fail{error},target) == Fail{error} : Result<&2,&2,R.Error,Bool>}

law unavailable_occlusion_fails_closed:
  for error:R.Error
  {R.conservative(Fail{error}) == True{} : Bool}

law unsigned_face_bit31_is_not_a_negative_word:
  {R.row_word(0,31,Some{2147483648}) == Done{True{}} : Result<&2,&2,R.Error,Bool>}

law face_bit32_uses_the_next_packed_word:
  for rows:Map<&2,Maybe<&2,List<&2,U32>>>
  {R.row_read(0,32,(rows,Some{[0,1]})) == Done{True{}} : Result<&2,&2,R.Error,Bool>}

law truncated_packed_row_is_explicitly_unavailable:
  for rows:Map<&2,Maybe<&2,List<&2,U32>>>
  {R.row_read(0,32,(rows,Some{[4294967295]})) == Fail{R.MissingWord{0,1}} : Result<&2,&2,R.Error,Bool>}

law noncontiguous_or_overflowing_range_cannot_enter_catalog:
  for +line:Nat
  for +states:U32
  for +next:U32
  for entries:Map<&2,Maybe<&2,R.Entry>>
  for +first:U32
  for +count:U32
  for +entry:R.Entry
  for invalid:{(U32.is_eq(first,next) && U32.is_le(first,states) && U32.is_le(count,U32.sub(states,first))) == False{} : Bool}
  {D.build_range(line,states,next,entries,Done{D.Range{first,count,entry}}) ==
    Fail{D.Schema{line,"noncontiguous or overflowing state range"}} :
    Result<&2,&1,D.Error,U32 & Map<&2,Maybe<&2,R.Entry>>>}

law noncanonical_decimal_state_fields_are_rejected:
  for line:Nat
  {D.number(line,"01") == Fail{D.Schema{line,"noncanonical U32"}} : Result<&2,&2,D.Error,U32>}

law untrusted_bytes_cannot_reach_the_decoder:
  for identity:String
  for count:U32
  for limit:Nat
  for bytes:List<&2,U32>
  {L.integrity(identity,count,limit,bytes,False{}) == Fail{L.IntegrityMismatch{}} : Result<&2,&2,L.Error,R.Catalog>}
