import Base
import ./campfire_authority.bend as F
import ./campfire_authority_items.bend as A
import ./campfire_authority_laws.bend as L

def L.refused_tick_preserves_whole_owner(state,message):
  match state:
    case F.State{kind,lit,cells,cache}: {==}
def L.refused_placement_preserves_owner_and_held_item(state,held,infinite,index,message):
  match state:
    case F.State{kind,lit,cells,cache}: {==}
def L.absent_recipe_preserves_owner_and_held_item(state,held,infinite,index):
  match state:
    case F.State{kind,lit,cells,cache}: {==}
def L.creative_placement_preserves_complete_held_input(held):
  match held:
    case A.Input{slot,patch}: {==}
def L.placed_cell_contains_exactly_one_complete_key(key,count,patch): {==}
def L.disabled_result_preserves_slot_for_retry(index,input,progress,total,cache,output): {==}
def L.enabled_drop_clears_input_but_preserves_timer_words(index,input,progress,total,cache,output): {==}
def L.missing_recipe_drops_complete_original_stack(original): {==}
def L.nonpositive_cooldown_does_not_change_timer_word(input,progress,total,nonpositive):
  %Equal.sym(Bool,F.signed_lt(0,progress),False{},nonpositive) :
    {F.Advanced{F.Cell{input,F.cool(progress,total,_),total},None{},F.Effects{[],_,0n,0n}} ==
      F.Advanced{F.Cell{input,progress,total},None{},F.Effects{[],False{},0n,0n}} : F.Advanced}
  {==}
def L.lit_signed_overflow_does_not_use_unsigned_completion(context,cache,index,key,count,patch): {==}
def L.snapshot_retains_complete_actual_owner(kind,lit,cells,cache): {==}
def L.refused_load_preserves_complete_actual_owner(state,record,message):
  match state record:
    case F.State{kind,lit,cells,cache} F.Record{next}: {==}
def L.removal_after_clear_cannot_emit_duplicate_items(kind,lit,cells,cache):
  match cells:
    case F.Four{F.Cell{a,pa,ta},F.Cell{b,pb,tb},F.Cell{c,pc,tc},F.Cell{d,pd,td}}: {==}
def L.ticker_replacement_resets_ephemeral_recipe_cache(kind,cells,cache): {==}
def L.first_empty_slot_has_lowest_placement_priority(patch,progress,total,second,third,fourth): {==}
