import Base
import ./furnace_authority_laws.bend as L
import ./furnace_authority.bend as A
import ./inventory.bend as Inv
import ./cooking_recipe.bend as K
import ./furnace_authority_fuel.bend as F
import ./crafting_recipe.bend as R

def L.failed_tick_preserves_affine_owner(state,message):
  A.State{inventory,frame} = state
  {==}
def L.invalid_backing_preserves_affine_owner(inventory,frame): {==}
def L.invalid_snapshot_cannot_publish_tick(catalog,fuel,context,profiles,snapshot,metadata):
  A.Snapshot{frame,slots} = snapshot
  K.FurnaceSlots{input,stack,output} = slots
  {==}
def L.invalid_slot_write_cannot_publish_mutation(catalog,snapshot,index,value,metadata):
  A.Snapshot{frame,slots} = snapshot
  {==}
def L.unlit_timer_is_not_decremented(frame):
  A.Frame{kind,r,t,s,c,speed,cached,uses} = frame
  {==}
def L.nonpositive_progress_is_not_cooled(frame):
  A.Frame{kind,r,t,s,c,speed,cached,uses} = frame
  {==}
def L.cache_miss_retains_previous_recipe(previous): {==}
def L.new_completion_creates_one_recipe_use(id): {==}
def L.empty_fuel_cannot_create_remainder(catalog):
  K.Catalog{recipes,tags,items} = catalog
  {==}
def L.last_fuel_routes_remainder_to_slot(remainder): {==}
def L.accepted_last_fuel_keeps_exact_item_remainder(recipes,tags,items,id,payload,limit,remainder,definition):
  %Equal.sym(Maybe<&2,R.ItemDefinition>,R.item_definition(items,id),Some{R.ItemDefinition{id,limit,remainder}},definition) :
    {A.spent_remainder(K.consume_input(Inv.InvStack{Inv.ItemKey{id,payload},1}),R.remainder_known(_)) == A.FuelSpent{remainder,[]} : A.FuelSpent}
  {==}
def L.remaining_fuel_routes_remainder_to_drop(key,count,remainder): {==}
def L.one_fuel_spends_one_unit_at_shared_count_boundary(remaining): {==}
def L.empty_fuel_uses_real_receiver_fallbacks(catalog,context): {==}
def L.absent_integer_provider_uses_zero_fallback(catalog,context):
  F.Context{block,depth} = context
  {==}
def L.absent_float_provider_uses_one_fallback(catalog,context):
  F.Context{block,depth} = context
  {==}
def L.divide_by_zero_is_arithmetic_failure(numerator): {==}
def L.restore_omits_ephemeral_cache(kind,slots,spent,total,remaining,lit_total,speed,uses): {==}
def L.save_preserves_timers_slots_and_use_counts(kind,remaining,lit_total,spent,total,speed,cached,uses,slots): {==}
def L.xp_pop_ignores_deleted_recipe(id,count): {==}
def L.empty_use_table_does_not_request_awards(recipes): {==}
def L.changed_current_subclass_refuses_xp_projection(id,name,wanted,count,hit):
  %Equal.sym(Bool,String.eq(id,wanted),True{},hit) :
    {R.choose(Result<&2,&2,String,Maybe<&2,A.XpRequest>>,Fail{"current recipesUsed key has a non-cooking subclass"},Done{None{}},_) == Fail{"current recipesUsed key has a non-cooking subclass"} : Result<&2,&2,String,Maybe<&2,A.XpRequest>>}
  {==}
def L.claimed_use_clear_preserves_all_other_fields(kind,remaining,lit_total,spent,total,speed,cached,uses): {==}
