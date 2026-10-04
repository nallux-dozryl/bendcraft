import Base
import ./cooking_block_entity_codec.bend as B
import ./cooking_block_entity_codec_nbt.bend as N
import ./cooking_block_entity_codec_items.bend as I
import ./cooking_block_entity_codec_components.bend as C
import ./nbt.bend as P
import ./inventory.bend as Inv
import ./json.bend as J
import ./furnace_authority.bend as FA
import ./campfire_authority.bend as CA
import ./campfire_authority_items.bend as CI
import ./cooking_recipe.bend as K

law rejected_furnace_decode_preserves_complete_owner:
  for state:FA.State
  for context:I.Context
  for message:String
  {B.furnace_loaded(state,context,Fail{message}) == (state,Fail{message}) : FA.State & Result<&2,&2,String,B.Details>}
law rejected_campfire_decode_preserves_complete_owner:
  for state:CA.State
  for context:CI.Context
  for message:String
  {B.campfire_loaded(state,context,Fail{message}) == (state,Fail{message}) : CA.State & Result<&2,&2,String,B.Details>}
law invalid_furnace_backing_cannot_publish_load:
  for context:I.Context
  for document:B.FurnaceDocument
  for state:FA.State
  {B.furnace_inspected(context,document,(state,None{})) == (state,Fail{"physical furnace load requires valid three-slot backing owner"}) : FA.State & Result<&2,&2,String,B.Details>}
law refused_furnace_commit_preserves_owner:
  for details:B.Details
  for state:FA.State
  for message:String
  {B.furnace_committed(details,(state,Fail{message})) == (state,Fail{message}) : FA.State & Result<&2,&2,String,B.Details>}
law refused_campfire_commit_preserves_owner:
  for details:B.Details
  for state:CA.State
  for message:String
  {B.campfire_committed(details,(state,Fail{message})) == (state,Fail{message}) : CA.State & Result<&2,&2,String,B.Details>}
law refused_furnace_save_preserves_owner:
  for context:I.Context
  for limits:P.Limits
  for state:FA.State
  for message:String
  {B.furnace_saved(context,limits,(state,Fail{message})) == (state,Fail{message}) : FA.State & Result<&2,&2,String,List<&2,U32>>}
law campfire_save_preserves_owner_and_uses_actual_snapshot:
  for context:I.Context
  for limits:P.Limits
  for kind:CA.CampfireKind
  for lit:Bool
  for +cells:CA.Four
  for cache:Maybe<&2,String>
  {B.save_campfire(CA.State{kind,lit,cells,cache},context,limits) == (CA.State{kind,lit,cells,cache},B.encode_campfire(context,limits,CA.Record{cells})) : CA.State & Result<&2,&2,String,List<&2,U32>>}
law present_empty_timer_array_retains_prior_tail:
  for prior:List<&2,U32>
  {B.int_array(prior,Some{P.IntArray{[]}}) == prior : List<&2,U32>}
law missing_timer_array_resets_all_four_cells:
  for prior:List<&2,U32>
  {B.int_array(prior,None{}) == [0,0,0,0] : List<&2,U32>}
law wrong_timer_array_resets_all_four_cells:
  for prior:List<&2,U32>
  for bytes:List<&2,U32>
  {B.int_array(prior,Some{P.ByteArray{bytes}}) == [0,0,0,0] : List<&2,U32>}
law short_timer_array_retains_three_old_cells:
  for a:U32
  for b:U32
  for c:U32
  for d:U32
  for next:U32
  {B.int_array([a,b,c,d],Some{P.IntArray{[next]}}) == [next,b,c,d] : List<&2,U32>}
law full_timer_array_discards_source_tail:
  for a:U32
  for b:U32
  for c:U32
  for d:U32
  for w:U32
  for x:U32
  for y:U32
  for z:U32
  for tail:List<&2,U32>
  {B.int_array([a,b,c,d],Some{P.IntArray{w <> x <> y <> z <> tail}}) == [w,x,y,z] : List<&2,U32>}
law physical_int_timer_preserves_signed_bits:
  for bits:U32
  {N.int_tag(P.Int{bits},True{}) == Some{bits} : Maybe<&2,U32>}
law physical_long_timer_uses_low_signed_word:
  for high:U32
  for low:U32
  {N.int_tag(P.Long{P.Word64{high,low}},True{}) == Some{low} : Maybe<&2,U32>}
law malformed_recipe_count_preserves_valid_sibling:
  for name:P.Text
  for text:P.Text
  for siblings:List<&2,FA.Use>
  {B.use_entry(name,P.StringTag{text},siblings,False{}) == siblings : List<&2,FA.Use>}
law overwritten_physical_recipe_entry_is_not_reintroduced:
  for name:P.Text
  for value:P.Value
  for siblings:List<&2,FA.Use>
  {B.use_entry(name,value,siblings,True{}) == siblings : List<&2,FA.Use>}
law absent_items_clear_previous_furnace_inputs:
  for context:I.Context
  {I.decode(context,3n,None{}) == Done{I.Decoded{[CI.plain(),CI.plain(),CI.plain()],0}} : Result<&2,&2,String,I.Decoded>}
law absent_items_clear_previous_campfire_inputs:
  for context:I.Context
  {I.decode(context,4n,None{}) == Done{I.Decoded{[CI.plain(),CI.plain(),CI.plain(),CI.plain()],0}} : Result<&2,&2,String,I.Decoded>}
law output_slots_preserve_exact_keys_and_counts:
  for a:Inv.Slot
  for b:Inv.Slot
  for c:Inv.Slot
  for pa:J.Value
  for pb:J.Value
  for pc:J.Value
  {B.furnace_slots([CI.Input{a,pa},CI.Input{b,pb},CI.Input{c,pc}]) == Done{K.FurnaceSlots{a,b,c}} : Result<&2,&2,String,K.FurnaceSlots>}
law campfire_record_preserves_patch_and_timer_ownership:
  for a:CI.Input
  for b:CI.Input
  for c:CI.Input
  for d:CI.Input
  for p:U32
  for q:U32
  for r:U32
  for s:U32
  for t:U32
  for u:U32
  for v:U32
  for w:U32
  {B.campfire_cells([a,b,c,d],[p,q,r,s],[t,u,v,w]) == Done{CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}}} : Result<&2,&2,String,CA.Four>}
law empty_items_emit_java_end_list_header:
  {B.item_list([]) == P.ListTag{0,[]} : P.Value}
law invalid_physical_component_is_discarded_without_fabrication:
  for name:String
  {C.converted(name,None{}) == None{} : Maybe<&2,J.Member>}
law noncompound_registered_removal_is_discarded:
  for id:String
  for bits:U32
  {C.removed(id,True{},P.Byte{bits}) == Done{None{}} : Result<&2,&2,String,Maybe<&2,J.Member>>}
law invalid_stew_effect_preserves_valid_siblings:
  for message:String
  for siblings:List<&2,J.Value>
  {C.effect_more(Fail{message},siblings) == siblings : List<&2,J.Value>}
law campfire_timer_and_item_decomposition_roundtrips_record:
  for +cells:CA.Four
  {B.campfire_cells(B.cell_inputs(cells),B.cell_progress(cells),B.cell_total(cells)) == Done{cells} : Result<&2,&2,String,CA.Four>}
law physical_list_wrapper_returns_exact_wrapped_effect:
  for value:P.Value
  {C.effect_unwrap(P.Compound{[P.Member{P.Text{[]},value}]}) == value : P.Value}
law valid_recipe_key_does_not_require_a_nonair_item:
  {B.parsed_use_id(Done{"minecraft:air"}) == Some{"minecraft:air"} : Maybe<&2,String>}
