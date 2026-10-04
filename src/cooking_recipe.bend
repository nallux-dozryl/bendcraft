import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R

type CookingKind is Data:
  Smelting{}
  Blasting{}
  Smoking{}
  Campfire{}

type Recipe is Data:
  Cooking{id:String,kind:CookingKind,ingredient:R.Ingredient,output:Inv.Slot,cooking_time:U32,experience:F32}
  Unsupported{id:String,kind:String}

type Catalog is Data:
  Catalog{recipes:List<&2,Recipe>,tags:List<&2,R.Tag>,items:List<&2,R.ItemDefinition>}

type Plan is Data:
  Plan{recipe_id:String,kind:CookingKind,output:Inv.Slot,before:Inv.Slot,cooking_time:U32,experience:F32}

type FurnaceSlots is Data:
  FurnaceSlots{input:Inv.Slot,fuel:Inv.Slot,output:Inv.Slot}

type Completion is Data:
  Completion{recipe_id:String,before:FurnaceSlots,after:FurnaceSlots,experience:F32}

def kind_name(kind:CookingKind) -> String:
  match kind:
    case Smelting{}: "minecraft:smelting"
    case Blasting{}: "minecraft:blasting"
    case Smoking{}: "minecraft:smoking"
    case Campfire{}: "minecraft:campfire_cooking"

def kind_equal(a:CookingKind,b:CookingKind) -> Bool:
  match a b:
    case Smelting{} Smelting{}: True{}
    case Blasting{} Blasting{}: True{}
    case Smoking{} Smoking{}: True{}
    case Campfire{} Campfire{}: True{}
    case _ _: False{}

def recipe_id(recipe:Recipe) -> String:
  match recipe:
    case Cooking{id,kind,ingredient,output,time,xp}: id
    case Unsupported{id,kind}: id

def slot_equal(a:Inv.Slot,b:Inv.Slot) -> Bool:
  R.snapshot_equal([a],[b])

def positive(slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: False{}
    case Inv.InvStack{key,count}: U32.is_gt(count,0)

def matches(recipe:Recipe,kind:CookingKind,tags:List<&2,R.Tag>,+input:Inv.Slot) -> Bool:
  match recipe:
    case Unsupported{id,other}: False{}
    case Cooking{id,other,ingredient,output,time,xp}:
      positive(input) && kind_equal(other,kind) && R.ingredient_matches(ingredient,tags,input)

def plan(recipe:Recipe,items:List<&2,R.ItemDefinition>,input:Inv.Slot) -> Maybe<&2,Plan>:
  match recipe:
    case Unsupported{id,kind}: None{}
    case Cooking{id,kind,ingredient,output,time,xp}: Some{Plan{id,kind,R.create_output(output,items),input,time,xp}}

def find_recipes(recipes:List<&2,Recipe>,+kind:CookingKind,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:Inv.Slot,found:Maybe<&2,Plan>) -> Maybe<&2,Plan>:
  match recipes found:
    case _ Some{value}: Some{value}
    case Nil{} None{}: None{}
    case +head <> rest None{}:
      selected = R.choose(Maybe<&2,Plan>,plan(head,items,input),None{},matches(head,kind,tags,input))
      find_recipes(rest,kind,tags,items,input,selected)

def find_checked(valid:Bool,catalog:Catalog,kind:CookingKind,input:Inv.Slot) -> Result<&2,&2,String,Maybe<&2,Plan>>:
  match valid:
    case False{}: Fail{"invalid cooking input: item definition, count or components"}
    case True{}:
      Catalog{recipes,tags,items} = catalog
      Done{find_recipes(recipes,kind,tags,items,input,None{})}

def find(+catalog:Catalog,kind:CookingKind,+input:Inv.Slot) -> Result<&2,&2,String,Maybe<&2,Plan>>:
  Catalog{recipes,tags,items} = catalog
  find_checked(R.slot_valid(items,input),catalog,kind,input)

def find_with_metadata(+catalog:Catalog,kind:CookingKind,+input:Inv.Slot,metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Maybe<&2,Plan>>:
  Catalog{recipes,tags,items} = catalog
  find_checked(R.slots_valid_with_metadata([input],items,metadata),catalog,kind,input)

def current(value:Plan,input:Inv.Slot) -> Bool:
  Plan{id,kind,output,before,time,xp} = value
  slot_equal(before,input)

def output_metadata(catalog:Catalog,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Catalog{recipes,tags,items} = catalog
  R.output_metadata(R.Catalog{[],tags,items},key)

# The empty destination branch intentionally ignores the container limit, as
# the actual canBurn receiver does. Template strict validation precedes it.
def capacity(existing:Inv.Slot,assembled:Inv.Slot,+container_limit:U32,result_limit:U32) -> Bool:
  match existing assembled:
    case Inv.InvEmpty{} _: True{}
    case Inv.InvStack{key,count} Inv.InvStack{other,amount}:
      Inv.key_equal(key,other) && U32.is_lt(container_limit,2147483648) && U32.is_le(U32.add(count,amount),U32.min(container_limit,result_limit))
    case _ _: False{}

def output_limit(value:Maybe<&2,Inv.ItemMetadata>) -> U32:
  match value:
    case None{}: 0
    case Some{Inv.ItemMetadata{key,limit}}: limit

def decrement_count(count:Nat) -> Nat:
  match count:
    case 0n: 0n
    case 1n+n: n

def remaining_input(key:Inv.ItemKey,count:Nat) -> Inv.Slot:
  match count:
    case 0n: Inv.InvEmpty{}
    case 1n+n: Inv.InvStack{key,U32.from_nat(1n+n)}

def consume_input(input:Inv.Slot) -> Inv.Slot:
  match input:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{key,count}: remaining_input(key,decrement_count(U32.to_nat(count)))

def merge_output(existing:Inv.Slot,assembled:Inv.Slot) -> Inv.Slot:
  match existing assembled:
    case Inv.InvEmpty{} _: assembled
    case Inv.InvStack{key,count} Inv.InvStack{other,amount}: Inv.InvStack{key,U32.add(count,amount)}
    case _ _: existing

def wet_sponge(input:Inv.Slot,fuel:Inv.Slot) -> Bool:
  match input fuel:
    case Inv.InvStack{Inv.ItemKey{id,components},count} Inv.InvStack{Inv.ItemKey{other,payload},amount}:
      U32.is_gt(count,0) && U32.is_gt(amount,0) && String.eq(id,"minecraft:wet_sponge") && String.eq(other,"minecraft:bucket")
    case _ _: False{}

def completed_fuel(input:Inv.Slot,+fuel:Inv.Slot) -> Inv.Slot:
  R.choose(Inv.Slot,Inv.InvStack{Inv.ItemKey{"minecraft:water_bucket",""},1},fuel,wet_sponge(input,fuel))

def burn(value:Plan,+slots:FurnaceSlots) -> Completion:
  Plan{id,kind,result,before,time,xp} = value
  FurnaceSlots{+input,+fuel,output} = slots
  Completion{id,slots,FurnaceSlots{consume_input(input),completed_fuel(input,fuel),merge_output(output,result)},xp}

def burn_snapshot(value:Completion) -> FurnaceSlots:
  Completion{id,before,after,xp} = value
  before

def completion_checked(valid:Bool,value:Plan,slots:FurnaceSlots) -> Result<&2,&2,String,Completion>:
  match valid:
    case False{}: Fail{"cooking completion refused: stale plan, invalid authority, kind or output capacity"}
    case True{}: Done{burn(value,slots)}

def plan_equal(a:Plan,b:Plan) -> Bool:
  Plan{id,kind,output,before,time,xp} = a
  Plan{other,other_kind,other_output,other_before,other_time,other_xp} = b
  String.eq(id,other) && kind_equal(kind,other_kind) && slot_equal(output,other_output) && slot_equal(before,other_before) &&
    U32.is_eq(time,other_time) && U32.is_eq(F32.bits(xp),F32.bits(other_xp))

def matching_selected(selected:Maybe<&2,Plan>,value:Plan,matched:Bool) -> Bool:
  match selected:
    case None{}: False{}
    case Some{expected}: matched && plan_equal(value,expected)

def matching_plan(+recipe:Recipe,+value:Plan,tags:List<&2,R.Tag>,items:List<&2,R.ItemDefinition>,+input:Inv.Slot) -> Bool:
  Plan{id,kind,output,before,time,xp} = value
  matching_selected(plan(recipe,items,input),value,matches(recipe,kind,tags,input))

def authentic(recipes:List<&2,Recipe>,+value:Plan,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:Inv.Slot) -> Bool:
  match recipes:
    case Nil{}: False{}
    case +recipe <> rest:
      Plan{+id,kind,output,before,time,xp} = value
      R.choose(Bool,matching_plan(recipe,value,tags,items,input),authentic(rest,value,tags,items,input),String.eq(recipe_id(recipe),id))

def slot_key(slot:Inv.Slot) -> Inv.ItemKey:
  match slot:
    case Inv.InvEmpty{}: Inv.ItemKey{"minecraft:air",""}
    case Inv.InvStack{key,count}: key

# Pure accepted-completion boundary only. The block owner must have already
# advanced its real timer/fuel state and must atomically apply this snapshot.
def complete(+catalog:Catalog,+value:Plan,+slots:FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,container_limit:U32) -> Result<&2,&2,String,Completion>:
  Catalog{recipes,tags,+items} = catalog
  Plan{id,kind,+result,before,time,xp} = value
  FurnaceSlots{+input,fuel,+output} = slots
  +valid_kind = Bool.not(kind_equal(kind,Campfire{}))
  valid = valid_kind && current(value,input) && authentic(recipes,value,tags,items,input) &&
    R.slots_valid_with_metadata([input,fuel,output],items,metadata) && R.slots_valid_with_metadata([completed_fuel(input,fuel)],items,metadata) && positive(result) &&
    capacity(output,result,container_limit,output_limit(output_metadata(catalog,slot_key(result))))
  completion_checked(valid,value,slots)

def furnace_equal(a:FurnaceSlots,b:FurnaceSlots) -> Bool:
  FurnaceSlots{input,fuel,output} = a
  FurnaceSlots{other_input,other_fuel,other_output} = b
  slot_equal(input,other_input) && slot_equal(fuel,other_fuel) && slot_equal(output,other_output)

def completion_current(value:Completion,slots:FurnaceSlots) -> Bool:
  Completion{id,before,after,xp} = value
  furnace_equal(before,slots)
