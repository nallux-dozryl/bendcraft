import Base
import ./cooking_block_entity_codec_laws.bend as L
import ./cooking_block_entity_codec.bend as B
import ./cooking_block_entity_codec_items.bend as I
import ./furnace_authority.bend as FA
import ./campfire_authority.bend as CA

def L.rejected_furnace_decode_preserves_complete_owner(state,context,message): {==}
def L.rejected_campfire_decode_preserves_complete_owner(state,context,message): {==}
def L.invalid_furnace_backing_cannot_publish_load(context,document,state):
  I.Context{recipes,defaults} = context
  B.FurnaceDocument{record,B.Details{name,extras,inputs,I.Admission{metadata,profiles},discarded}} = document
  {==}
def L.refused_furnace_commit_preserves_owner(details,state,message): {==}
def L.refused_campfire_commit_preserves_owner(details,state,message): {==}
def L.refused_furnace_save_preserves_owner(context,limits,state,message): {==}
def L.campfire_save_preserves_owner_and_uses_actual_snapshot(context,limits,kind,lit,cells,cache): {==}
def L.present_empty_timer_array_retains_prior_tail(prior):
  match prior:
    case Nil{}: {==}
    case value <> rest: {==}
def L.missing_timer_array_resets_all_four_cells(prior): {==}
def L.wrong_timer_array_resets_all_four_cells(prior,bytes): {==}
def L.short_timer_array_retains_three_old_cells(a,b,c,d,next): {==}
def L.full_timer_array_discards_source_tail(a,b,c,d,w,x,y,z,tail):
  match tail:
    case Nil{}: {==}
    case value <> rest: {==}
def L.physical_int_timer_preserves_signed_bits(bits): {==}
def L.physical_long_timer_uses_low_signed_word(high,low): {==}
def L.malformed_recipe_count_preserves_valid_sibling(name,text,siblings):
  match name:
    case n: {==}
def L.overwritten_physical_recipe_entry_is_not_reintroduced(name,value,siblings): {==}
def L.absent_items_clear_previous_furnace_inputs(context): {==}
def L.absent_items_clear_previous_campfire_inputs(context): {==}
def L.output_slots_preserve_exact_keys_and_counts(a,b,c,pa,pb,pc): {==}
def L.campfire_record_preserves_patch_and_timer_ownership(a,b,c,d,p,q,r,s,t,u,v,w): {==}
def L.empty_items_emit_java_end_list_header(): {==}
def L.invalid_physical_component_is_discarded_without_fabrication(name): {==}
def L.noncompound_registered_removal_is_discarded(id,bits): {==}
def L.invalid_stew_effect_preserves_valid_siblings(message,siblings): {==}
def L.campfire_timer_and_item_decomposition_roundtrips_record(cells):
  CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}} = cells
  {==}
def L.physical_list_wrapper_returns_exact_wrapped_effect(value): {==}
def L.valid_recipe_key_does_not_require_a_nonair_item(): {==}
