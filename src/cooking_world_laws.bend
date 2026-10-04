import Base
import ./core.bend as C
import ./block_light_world.bend as W
import ./cooking_world.bend as B
import ./cooking_world_tick.bend as T
import ./cooking_world_slots.bend as S
import ./cooking_world_edit.bend as E
import ./cooking_world_bindings.bend as K
import ./cooking_world_store.bend as Store
import ./furnace_authority.bend as F
import ./campfire_authority.bend as A
import ./player_core_edit.bend as P

law refused_cooking_plan_retains_ready_owner:
  for world:W.State
  for entries:List<&1,Store.Entry>
  for loading:List<&2,String>
  for message:String
  {T.finish_planned(B.State{world,entries,B.Idle{},loading},Fail{message}) == (B.State{world,entries,B.Idle{},loading},Fail{B.Authority{message}}) : B.State & Result<&2,&2,B.Error,List<&2,Store.Effect>>}
def refused_cooking_plan_retains_ready_owner(world,entries,loading,message): {==}

law refused_cooking_plan_retains_pending_owner:
  for world:W.State
  for entries:List<&1,Store.Entry>
  for tick:Nat
  for effects:List<&2,Store.Effect>
  for loading:List<&2,String>
  for message:String
  {T.finish_planned(B.State{world,entries,B.Cooking{tick,effects},loading},Fail{message}) == (B.State{world,entries,B.Cooking{tick,effects},loading},Fail{B.Authority{message}}) : B.State & Result<&2,&2,B.Error,List<&2,Store.Effect>>}
def refused_cooking_plan_retains_pending_owner(world,entries,tick,effects,loading,message): {==}

law furnace_property_transition_retains_actual_array:
  for old_state:U32
  for new_state:U32
  for block:String
  for family:K.Family
  for before:Bool
  for after:Bool
  for dark:U32
  for bright:U32
  for owner:F.State
  {Store.updated_entity(K.Binding{old_state,block,family,before,dark,bright},K.Binding{new_state,block,family,after,dark,bright},Store.Furnace{owner}) == Store.Furnace{owner} : Store.Entity}
def furnace_property_transition_retains_actual_array(old_state,new_state,block,family,before,after,dark,bright,owner): {==}

law campfire_ticker_change_preserves_items_and_resets_cache:
  for kind:A.CampfireKind
  for lit:Bool
  for cells:A.Four
  for cache:Maybe<&2,String>
  for value:Bool
  {Store.updated_campfire(A.State{kind,lit,cells,cache},value,False{}) == A.State{kind,value,cells,None{}} : A.State}
def campfire_ticker_change_preserves_items_and_resets_cache(kind,lit,cells,cache,value): {==}

law unlit_partner_uses_exact_registry_state:
  for state:U32
  for block:String
  for family:K.Family
  for lit:Bool
  for dark:U32
  for bright:U32
  {K.lit_state(K.Binding{state,block,family,lit,dark,bright},False{}) == dark : U32}
def unlit_partner_uses_exact_registry_state(state,block,family,lit,dark,bright): {==}

law lit_partner_uses_exact_registry_state:
  for state:U32
  for block:String
  for family:K.Family
  for lit:Bool
  for dark:U32
  for bright:U32
  {K.lit_state(K.Binding{state,block,family,lit,dark,bright},True{}) == bright : U32}
def lit_partner_uses_exact_registry_state(state,block,family,lit,dark,bright): {==}
