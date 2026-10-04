import Base
import ../src/json.bend as J
import ../src/inventory.bend as I
import ../src/crafting_recipe_components.bend as C
import ../src/crafting_recipe.bend as R
import ../src/u32_decimal.bend as Decimal
import ../src/cooking_recipe.bend as K
import ../src/campfire_authority.bend as F
import ../src/campfire_authority_items.bend as A

def guard(name:String,ok:Bool) -> J.Value:
  J.JObject{[J.JMember{"id",J.JString{name}},J.JMember{"ok",J.JBool{ok}}]}
def slot_value(value:I.Slot) -> J.Value:
  match value:
    case I.InvEmpty{}: J.JNull{}
    case I.InvStack{I.ItemKey{id,components},count}: J.JArray{[J.JString{id},J.JString{components},J.JNumber{Decimal.show(count)}]}
def cell_value(cell:F.Cell) -> J.Value:
  F.Cell{A.Input{slot,patch},p,t} = cell
  J.JArray{[slot_value(slot),patch,J.JNumber{Decimal.show(p)},J.JNumber{Decimal.show(t)}]}
def four(value:F.Four) -> J.Value:
  F.Four{a,b,c,d} = value
  J.JArray{[cell_value(a),cell_value(b),cell_value(c),cell_value(d)]}
def cells_equal(expected:F.Four,actual:F.Four) -> Bool:
  String.eq(J.encode(four(expected)),J.encode(four(actual)))
def cached(value:Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{id}: "some:" ++ id
def refused(cells:F.Four,cache:Maybe<&2,String>,result:F.State & Result<&2,&2,String,F.Effects>) -> Bool:
  match result:
    case (F.State{F.Ordinary{},True{},actual,next},Fail{message}):
      cells_equal(cells,actual) && String.eq(cached(cache),cached(next))
    case _: False{}
def bad_slot(context:A.Context,name:String,slot:I.Slot,patch:J.Value) -> J.Value:
  +cells : F.Four = F.Four{F.Cell{A.Input{slot,patch},17,600},F.empty_cell(),F.empty_cell(),F.empty_cell()}
  guard(name,refused(cells,Some{"old-cache"},F.step(context,F.State{F.Ordinary{},True{},cells,Some{"old-cache"}})))
def missing_defaults(context:A.Context) -> A.Context:
  A.Context{recipes,defaults,features} = context
  A.Context{recipes,[],features}
def patch() -> J.Value: J.JObject{[J.JMember{"minecraft:enchantment_glint_override",J.JBool{True{}}}]}
def output_missing(context:A.Context) -> A.Context:
  A.Context{K.Catalog{recipes,tags,items},defaults,features} = context
  A.Context{K.Catalog{[
    K.Cooking{"bendcraft:guard_a",K.Campfire{},R.AnyOf{[R.Item{"minecraft:potato"}]},I.InvStack{I.ItemKey{"minecraft:stone",""},1},1,0.0},
    K.Cooking{"bendcraft:guard_b",K.Campfire{},R.AnyOf{[R.Item{"minecraft:diamond"}]},I.InvStack{I.ItemKey{"minecraft:gold_ingot",""},1},1,0.0}],tags,items},defaults,
    Map.set(&2,Maybe<&2,Bool>,MTip{},"minecraft:stone",Some{True{}})}
def late_slot(context:A.Context) -> J.Value:
  +cells : F.Four = F.Four{F.Cell{A.Input{I.InvStack{I.ItemKey{"minecraft:potato",""},1},J.JObject{[]}},0,1},F.Cell{A.Input{I.InvStack{I.ItemKey{"minecraft:diamond",""},1},J.JObject{[]}},0,1},F.empty_cell(),F.empty_cell()}
  guard("late_slot_missing_feature_rolls_back_prior_drop_and_cache",refused(cells,Some{"old-cache"},F.step(output_missing(context),F.State{F.Ordinary{},True{},cells,Some{"old-cache"}})))
def unsupported(context:A.Context) -> A.Context:
  A.Context{K.Catalog{recipes,tags,items},defaults,features} = context
  A.Context{K.Catalog{[K.Unsupported{"bendcraft:unsupported","minecraft:campfire_cooking/unsupported_codec_domain"}],tags,items},defaults,features}
def record_refused(cells:F.Four,result:F.State & Result<&2,&2,String,Unit>) -> Bool:
  match result:
    case (F.State{F.Ordinary{},True{},actual,Some{cache}},Fail{message}): cells_equal(cells,actual) && String.eq(cache,"old-cache")
    case _: False{}
def load_refusal(+context:A.Context) -> J.Value:
  +cells : F.Four = F.Four{F.Cell{A.plain(),11,600},F.empty_cell(),F.empty_cell(),F.empty_cell()}
  invalid : F.Four = F.Four{F.Cell{A.Input{I.InvStack{I.ItemKey{"minecraft:potato",""},0},J.JObject{[]}},0,1},F.empty_cell(),F.empty_cell(),F.empty_cell()}
  guard("invalid_record_retains_whole_owner",record_refused(cells,F.load_record(context,F.State{F.Ordinary{},True{},cells,Some{"old-cache"}},F.Record{invalid})))
def key_found(defaults:J.Value,result:Result<&2,&2,String,String>) -> String:
  match result:
    case Done{key}: key
    case _: "unexpected-resolution-failure"
def identity_found(found:Maybe<&2,J.Value>) -> String:
  match found:
    case Some{+map}: key_found(map,C.resolve(map,patch()))
    case None{}: "unexpected-missing-defaults"
def identity(context:A.Context) -> String:
  A.Context{recipes,defaults,features} = context
  identity_found(C.default_for(defaults,"minecraft:potato"))
def roundtrip_restored(expected:F.Four,result:F.State & Result<&2,&2,String,Unit>) -> Bool:
  match result:
    case (F.State{F.Ordinary{},False{},actual,None{}},Done{unit}): cells_equal(expected,actual)
    case _: False{}
def restore_snapshot(context:A.Context,expected:F.Four,result:F.State & F.Record) -> Bool:
  (owner,record) = result
  roundtrip_restored(expected,F.load_record(context,F.clear(owner),record))
def roundtrip(+context:A.Context) -> J.Value:
  +cells : F.Four = F.Four{F.Cell{A.Input{I.InvStack{I.ItemKey{"minecraft:potato",identity(context)},1},patch()},2147483647,2147483648},F.Cell{A.plain(),17,4294967295},F.empty_cell(),F.empty_cell()}
  guard("typed_snapshot_clear_restore_preserves_complete_cells_and_resets_cache",restore_snapshot(context,cells,F.snapshot(F.State{F.Ordinary{},False{},cells,Some{"old-cache"}})))
def run(+context:A.Context) -> List<&2,J.Value>:
  [bad_slot(context,"noncanonical_air_stack",I.InvStack{I.ItemKey{"minecraft:air",""},1},J.JObject{[]}),
   bad_slot(context,"zero_count",I.InvStack{I.ItemKey{"minecraft:potato",""},0},J.JObject{[]}),
   bad_slot(context,"count_over_initialized_limit",I.InvStack{I.ItemKey{"minecraft:potato",""},65},J.JObject{[]}),
   bad_slot(context,"forged_component_identity",I.InvStack{I.ItemKey{"minecraft:potato","BendCraftComponents1\t64\t{}"},1},patch()),
   bad_slot(context,"modified_identity_without_patch",I.InvStack{I.ItemKey{"minecraft:potato",identity(context)},1},J.JObject{[]}),
   bad_slot(missing_defaults(context),"patch_without_initialized_defaults",I.InvStack{I.ItemKey{"minecraft:potato",identity(context)},1},patch()),
   bad_slot(context,"unsupported_component_patch",I.InvStack{I.ItemKey{"minecraft:potato",""},1},J.JObject{[J.JMember{"minecraft:unknown",J.JBool{True{}}}]}),
   bad_slot(context,"unknown_item",I.InvStack{I.ItemKey{"bendcraft:unknown",""},1},J.JObject{[]}),
   bad_slot(unsupported(context),"unsupported_campfire_recipe",I.InvStack{I.ItemKey{"minecraft:potato",""},1},J.JObject{[]}),
   late_slot(context),load_refusal(context),roundtrip(context)]
