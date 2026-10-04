import Base
import ./campfire_authority.bend as F
import ./campfire_authority_items.bend as A
import ./inventory.bend as I
import ./cooking_recipe.bend as K
import ./json.bend as JSON

law refused_tick_preserves_whole_owner:
  for state:F.State
  for +message:String
  {F.committed(state,Fail{message}) == (state,Fail{message}) : F.State & Result<&2,&2,String,F.Effects>}

law refused_placement_preserves_owner_and_held_item:
  for state:F.State
  for +held:A.Input
  for infinite:Bool
  for index:U32
  for +message:String
  {F.place_selected(state,held,infinite,index,Fail{message}) ==
    (state,F.Placement{held,Fail{message}}) : F.State & F.Placement}

law absent_recipe_preserves_owner_and_held_item:
  for state:F.State
  for +held:A.Input
  for infinite:Bool
  for index:U32
  {F.place_selected(state,held,infinite,index,Done{None{}}) ==
    (state,F.Placement{held,Fail{"no campfire recipe"}}) : F.State & F.Placement}

law creative_placement_preserves_complete_held_input:
  for +held:A.Input
  {F.retained(held,True{}) == held : A.Input}

law placed_cell_contains_exactly_one_complete_key:
  for +key:I.ItemKey
  for count:U32
  for +patch:JSON.Value
  {F.one(A.Input{I.InvStack{key,count},patch}) == A.Input{I.InvStack{key,1},patch} : A.Input}

law disabled_result_preserves_slot_for_retry:
  for index:U32
  for +input:A.Input
  for +progress:U32
  for +total:U32
  for +cache:Maybe<&2,String>
  for output:I.Slot
  {F.cooked(index,F.Cell{input,progress,total},cache,output,Done{False{}}) ==
    Done{F.Advanced{F.Cell{input,progress,total},cache,F.Effects{[],True{},0n,0n}}} : Result<&2,&2,String,F.Advanced>}

law enabled_drop_clears_input_but_preserves_timer_words:
  for +index:U32
  for input:A.Input
  for +progress:U32
  for +total:U32
  for +cache:Maybe<&2,String>
  for +output:I.Slot
  {F.cooked(index,F.Cell{input,progress,total},cache,output,Done{True{}}) ==
    Done{F.Advanced{F.Cell{A.plain(),progress,total},cache,F.Effects{[F.Drop{index,output}],True{},1n,1n}}} : Result<&2,&2,String,F.Advanced>}

law missing_recipe_drops_complete_original_stack:
  for +original:I.Slot
  {F.result_item(None{},original) == original : I.Slot}

law nonpositive_cooldown_does_not_change_timer_word:
  for +input:A.Input
  for +progress:U32
  for +total:U32
  for nonpositive:{F.signed_lt(0,progress) == False{} : Bool}
  {F.cooldown(F.Cell{input,progress,total}) ==
    F.Advanced{F.Cell{input,progress,total},None{},F.Effects{[],False{},0n,0n}} : F.Advanced}

law lit_signed_overflow_does_not_use_unsigned_completion:
  for context:A.Context
  for +cache:Maybe<&2,String>
  for index:U32
  for +key:I.ItemKey
  for +count:U32
  for +patch:JSON.Value
  {F.cook_cell(context,cache,index,F.Cell{A.Input{I.InvStack{key,count},patch},2147483647,2147483647}) ==
    Done{F.Advanced{F.Cell{A.Input{I.InvStack{key,count},patch},2147483648,2147483647},cache,F.Effects{[],True{},0n,0n}}} : Result<&2,&2,String,F.Advanced>}

law snapshot_retains_complete_actual_owner:
  for +kind:F.CampfireKind
  for +lit:Bool
  for +cells:F.Four
  for +cache:Maybe<&2,String>
  {F.snapshot(F.State{kind,lit,cells,cache}) == (F.State{kind,lit,cells,cache},F.Record{cells}) : F.State & F.Record}

law refused_load_preserves_complete_actual_owner:
  for state:F.State
  for record:F.Record
  for +message:String
  {F.loaded(state,record,Fail{message}) == (state,Fail{message}) : F.State & Result<&2,&2,String,Unit>}

law removal_after_clear_cannot_emit_duplicate_items:
  for +kind:F.CampfireKind
  for +lit:Bool
  for +cells:F.Four
  for +cache:Maybe<&2,String>
  {F.remove(F.clear(F.State{kind,lit,cells,cache})) ==
    (F.clear(F.State{kind,lit,cells,cache}),F.Effects{[F.Drop{0,I.InvEmpty{}},F.Drop{1,I.InvEmpty{}},F.Drop{2,I.InvEmpty{}},F.Drop{3,I.InvEmpty{}}],False{},0n,0n}) : F.State & F.Effects}

law ticker_replacement_resets_ephemeral_recipe_cache:
  for +kind:F.CampfireKind
  for +cells:F.Four
  for cache:Maybe<&2,String>
  {F.set_lit(F.State{kind,True{},cells,cache},False{}) == F.State{kind,False{},cells,None{}} : F.State}

law first_empty_slot_has_lowest_placement_priority:
  for patch:JSON.Value
  for progress:U32
  for total:U32
  for second:F.Cell
  for third:F.Cell
  for fourth:F.Cell
  {F.first_empty(F.Four{F.Cell{A.Input{I.InvEmpty{},patch},progress,total},second,third,fourth}) == Some{0} : Maybe<&2,U32>}
