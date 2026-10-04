import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as A
import ./furnace_authority_fuel.bend as F
import ./furnace_authority_slots.bend as S
import ./furnace_authority_xp.bend as X

law failed_tick_preserves_affine_owner:
  for state:A.State
  for message:String
  {A.commit(state,Fail{message}) == (state,Fail{message}) : A.State & Result<&2,&2,String,A.Effects>}
law invalid_backing_preserves_affine_owner:
  for inventory:Inv.Inventory
  for frame:A.Frame
  {A.inspect_checked(inventory,frame,False{}) == (A.State{inventory,frame},None{}) : A.State & Maybe<&2,A.Snapshot>}
law invalid_snapshot_cannot_publish_tick:
  for catalog:K.Catalog
  for fuel:F.Catalog
  for context:F.Context
  for profiles:List<&2,F.FuelProfile>
  for snapshot:A.Snapshot
  for metadata:List<&2,Inv.ItemMetadata>
  {A.tick_checked(catalog,fuel,context,profiles,snapshot,metadata,False{}) == Fail{"furnace snapshot rejected: kind, slot/component/count authority or recipesUsed"} : Result<&2,&2,String,A.Transition>}
law invalid_slot_write_cannot_publish_mutation:
  for catalog:K.Catalog
  for snapshot:A.Snapshot
  for index:U32
  for value:Inv.Slot
  for metadata:List<&2,Inv.ItemMetadata>
  {S.put_checked(catalog,snapshot,index,value,metadata,False{}) == Fail{"furnace slot replacement refused: index, owner or exact item authority"} : Result<&2,&2,String,A.Transition>}
law unlit_timer_is_not_decremented:
  for frame:A.Frame
  {A.spend_lit_checked(frame,False{}) == frame : A.Frame}
law nonpositive_progress_is_not_cooled:
  for frame:A.Frame
  {A.cool_checked(frame,False{}) == frame : A.Frame}
law cache_miss_retains_previous_recipe:
  for previous:Maybe<&2,String>
  {A.select_found(previous,None{}) == A.Selection{None{},previous} : A.Selection}
law new_completion_creates_one_recipe_use:
  for id:String
  {A.add_use([],id) == [A.Use{id,1}] : List<&2,A.Use>}
law empty_fuel_cannot_create_remainder:
  for catalog:K.Catalog
  {A.consume_fuel(catalog,Inv.InvEmpty{}) == A.FuelSpent{Inv.InvEmpty{},[]} : A.FuelSpent}
law last_fuel_routes_remainder_to_slot:
  for remainder:Inv.Slot
  {A.spent_remainder(Inv.InvEmpty{},remainder) == A.FuelSpent{remainder,[]} : A.FuelSpent}
law accepted_last_fuel_keeps_exact_item_remainder:
  for recipes:List<&2,K.Recipe>
  for tags:List<&2,R.Tag>
  for +items:List<&2,R.ItemDefinition>
  for +id:String
  for payload:String
  for +limit:U32
  for +remainder:Inv.Slot
  for definition:{R.item_definition(items,id) == Some{R.ItemDefinition{id,limit,remainder}} : Maybe<&2,R.ItemDefinition>}
  {A.consume_fuel(K.Catalog{recipes,tags,items},Inv.InvStack{Inv.ItemKey{id,payload},1}) == A.FuelSpent{remainder,[]} : A.FuelSpent}
law remaining_fuel_routes_remainder_to_drop:
  for key:Inv.ItemKey
  for count:U32
  for remainder:Inv.Slot
  {A.spent_remainder(Inv.InvStack{key,count},remainder) == A.FuelSpent{Inv.InvStack{key,count},A.nonempty_drop(remainder)} : A.FuelSpent}
law one_fuel_spends_one_unit_at_shared_count_boundary:
  for +remaining:Nat
  {1n+K.decrement_count(1n+remaining) == 1n+remaining : Nat}
law empty_fuel_uses_real_receiver_fallbacks:
  for catalog:F.Catalog
  for context:F.Context
  {F.values(catalog,context,None{}) == Done{F.Values{0,1.0}} : Result<&2,&2,String,F.Values>}
law absent_integer_provider_uses_zero_fallback:
  for catalog:F.Catalog
  for context:F.Context
  {F.root_int_found(catalog,context,None{}) == Done{0} : Result<&2,&2,String,U32>}
law absent_float_provider_uses_one_fallback:
  for catalog:F.Catalog
  for context:F.Context
  {F.root_float_found(catalog,context,None{}) == Done{1.0} : Result<&2,&2,String,F32>}
law divide_by_zero_is_arithmetic_failure:
  for numerator:U32
  {F.division(numerator,0) == None{} : Maybe<&2,U32>}
law restore_omits_ephemeral_cache:
  for kind:K.CookingKind
  for slots:K.FurnaceSlots
  for spent:U32
  for total:U32
  for remaining:U32
  for lit_total:U32
  for speed:F32
  for uses:List<&2,A.Use>
  {A.load_snapshot(kind,A.Persisted{slots,spent,total,remaining,lit_total,speed,uses}) == A.Snapshot{A.Frame{kind,remaining,lit_total,spent,total,speed,None{},uses},slots} : A.Snapshot}
law save_preserves_timers_slots_and_use_counts:
  for kind:K.CookingKind
  for remaining:U32
  for lit_total:U32
  for spent:U32
  for total:U32
  for speed:F32
  for cached:Maybe<&2,String>
  for uses:List<&2,A.Use>
  for slots:K.FurnaceSlots
  {A.persisted(A.Snapshot{A.Frame{kind,remaining,lit_total,spent,total,speed,cached,uses},slots}) == A.Persisted{slots,spent,total,remaining,lit_total,speed,uses} : A.Persisted}
law xp_pop_ignores_deleted_recipe:
  for id:String
  for count:U32
  {X.request([],id,count) == Done{None{}} : Result<&2,&2,String,Maybe<&2,A.XpRequest>>}
law empty_use_table_does_not_request_awards:
  for recipes:List<&2,K.Recipe>
  {X.requests([],recipes) == Done{[]} : Result<&2,&2,String,List<&2,A.XpRequest>>}
law changed_current_subclass_refuses_xp_projection:
  for +id:String
  for name:String
  for +wanted:String
  for count:U32
  for hit:{String.eq(id,wanted) == True{} : Bool}
  {X.request([K.Unsupported{id,name}],wanted,count) == Fail{"current recipesUsed key has a non-cooking subclass"} : Result<&2,&2,String,Maybe<&2,A.XpRequest>>}
law claimed_use_clear_preserves_all_other_fields:
  for kind:K.CookingKind
  for remaining:U32
  for lit_total:U32
  for spent:U32
  for total:U32
  for speed:F32
  for cached:Maybe<&2,String>
  for uses:List<&2,A.Use>
  {X.clear(A.Frame{kind,remaining,lit_total,spent,total,speed,cached,uses}) == A.Frame{kind,remaining,lit_total,spent,total,speed,cached,[]} : A.Frame}
