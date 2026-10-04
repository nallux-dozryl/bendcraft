import Base
import ./inventory.bend as Inv

# Ordinary crafting is pure. The menu owns stacks; this module returns a plan.
# Selectors retain tag identity and explicit alternatives rather than guessing
# ingredient membership from item names. Components are the inventory owner's
# default-only domain; patched result/input components are rejected by the codec.
type Selector is Data:
  Item{id:String}
  TagRef{id:String}

type Ingredient is Data:
  Empty{}
  AnyOf{selectors:List<&2,Selector>}

type Tag is Data:
  Tag{id:String,items:List<&2,String>}

type ItemDefinition is Data:
  ItemDefinition{id:String,limit:U32,remainder:Inv.Slot}

type Recipe is Data:
  Shaped{id:String,width:U32,height:U32,cells:List<&2,Ingredient>,output:Inv.Slot}
  Shapeless{id:String,ingredients:List<&2,Ingredient>,output:Inv.Slot}
  Unsupported{id:String,kind:String}

type Catalog is Data:
  Catalog{recipes:List<&2,Recipe>,tags:List<&2,Tag>,items:List<&2,ItemDefinition>}

type Grid is Data:
  Grid{width:U32,height:U32,slots:List<&2,Inv.Slot>}

type Consumption is Data:
  Consumption{slot:U32,count:U32,remainder:Inv.Slot}

type Plan is Data:
  Plan{recipe_id:String,output:Inv.Slot,before:Grid,consumption:List<&2,Consumption>}

def choose(-A:Data,yes:A,no:A,test:Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def contains(values:List<&2,String>,+id:String) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: String.eq(head,id) || contains(rest,id)

def item_definition(items:List<&2,ItemDefinition>,+wanted:String) -> Maybe<&2,ItemDefinition>:
  match items:
    case Nil{}: None{}
    case +head <> rest:
      ItemDefinition{id,limit,remainder} = head
      choose(Maybe<&2,ItemDefinition>,Some{head},item_definition(rest,wanted),String.eq(id,wanted))

def tag_members(tags:List<&2,Tag>,+wanted:String) -> Maybe<&2,List<&2,String>>:
  match tags:
    case Nil{}: None{}
    case Tag{id,items} <> rest:
      choose(Maybe<&2,List<&2,String>>,Some{items},tag_members(rest,wanted),String.eq(id,wanted))

def tag_contains(members:Maybe<&2,List<&2,String>>,id:String) -> Bool:
  match members:
    case None{}: False{}
    case Some{items}: contains(items,id)

def selector_matches(selector:Selector,tags:List<&2,Tag>,id:String) -> Bool:
  match selector:
    case Item{wanted}: String.eq(wanted,id)
    case TagRef{wanted}: tag_contains(tag_members(tags,wanted),id)

def alternatives_match(selectors:List<&2,Selector>,+tags:List<&2,Tag>,+id:String) -> Bool:
  match selectors:
    case Nil{}: False{}
    case selector <> rest: selector_matches(selector,tags,id) || alternatives_match(rest,tags,id)

def ingredient_matches(ingredient:Ingredient,tags:List<&2,Tag>,slot:Inv.Slot) -> Bool:
  match ingredient slot:
    case Empty{} Inv.InvEmpty{}: True{}
    case AnyOf{selectors} Inv.InvStack{Inv.ItemKey{id,components},count}:
      U32.is_gt(count,0) && alternatives_match(selectors,tags,id)
    case _ _: False{}

def definition_admits(definition:Maybe<&2,ItemDefinition>,+count:U32) -> Bool:
  match definition:
    case None{}: False{}
    case Some{ItemDefinition{id,limit,remainder}}: U32.is_gt(count,0) && U32.is_le(count,limit)

def slot_valid(items:List<&2,ItemDefinition>,slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{Inv.ItemKey{+id,components},count}:
      Bool.not(String.eq(id,"minecraft:air")) && String.is_empty(components) && definition_admits(item_definition(items,id),count)

def slots_valid(slots:List<&2,Inv.Slot>,+items:List<&2,ItemDefinition>) -> Bool:
  match slots:
    case Nil{}: True{}
    case head <> rest: slot_valid(items,head) && slots_valid(rest,items)

def dimensions(+width:U32,+height:U32) -> Bool:
  U32.is_ge(width,1) && U32.is_le(width,3) && U32.is_ge(height,1) && U32.is_le(height,3)

def grid_valid(items:List<&2,ItemDefinition>,grid:Grid) -> Bool:
  Grid{+width,+height,+slots} = grid
  dimensions(width,height) && Nat.is_eq(List.length(&2,Inv.Slot,slots),U32.to_nat(U32.mul(width,height))) && slots_valid(slots,items)

def cell_at(index:Nat,cells:List<&2,Ingredient>) -> Ingredient:
  match index cells:
    case 0n head <> rest: head
    case 1n+n head <> rest: cell_at(n,rest)
    case _ _: Empty{}

def expected_inside(inside:Bool,cells:List<&2,Ingredient>,+width:U32,+x:U32,y:U32,mirror:Bool) -> Ingredient:
  match inside:
    case False{}: Empty{}
    case True{}:
      column = choose(U32,U32.sub(U32.sub(width,1),x),x,mirror)
      cell_at(U32.to_nat(U32.add(U32.mul(y,width),column)),cells)

def expected(+cells:List<&2,Ingredient>,+width:U32,+height:U32,+x:U32,+y:U32,+offset_x:U32,+offset_y:U32,mirror:Bool) -> Ingredient:
  expected_inside(U32.is_ge(x,offset_x) && U32.is_ge(y,offset_y) && U32.is_lt(x,U32.add(offset_x,width)) && U32.is_lt(y,U32.add(offset_y,height)),
    cells,width,U32.sub(x,offset_x),U32.sub(y,offset_y),mirror)

def shaped_cells(slots:List<&2,Inv.Slot>,+tags:List<&2,Tag>,+cells:List<&2,Ingredient>,+width:U32,+height:U32,+grid_width:U32,+offset_x:U32,+offset_y:U32,+mirror:Bool,+index:U32) -> Bool:
  match slots:
    case Nil{}: True{}
    case slot <> rest:
      ingredient_matches(expected(cells,width,height,U32.mod(index,grid_width),U32.div(index,grid_width),offset_x,offset_y,mirror),tags,slot) &&
        shaped_cells(rest,tags,cells,width,height,grid_width,offset_x,offset_y,mirror,U32.add(index,1))

def shaped_position(+tags:List<&2,Tag>,+cells:List<&2,Ingredient>,+width:U32,+height:U32,+grid_width:U32,grid_height:U32,+slots:List<&2,Inv.Slot>,+x:U32,+y:U32) -> Bool:
  U32.is_le(U32.add(x,width),grid_width) && U32.is_le(U32.add(y,height),grid_height) &&
    (shaped_cells(slots,tags,cells,width,height,grid_width,x,y,False{},0) || shaped_cells(slots,tags,cells,width,height,grid_width,x,y,True{},0))

def shaped_offsets(xs:List<&2,U32>,+tags:List<&2,Tag>,+cells:List<&2,Ingredient>,+width:U32,+height:U32,+grid_width:U32,+grid_height:U32,+slots:List<&2,Inv.Slot>,+y:U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case x <> rest:
      shaped_position(tags,cells,width,height,grid_width,grid_height,slots,x,y) || shaped_offsets(rest,tags,cells,width,height,grid_width,grid_height,slots,y)

def shaped_rows(ys:List<&2,U32>,+tags:List<&2,Tag>,+cells:List<&2,Ingredient>,+width:U32,+height:U32,+grid_width:U32,+grid_height:U32,+slots:List<&2,Inv.Slot>) -> Bool:
  match ys:
    case Nil{}: False{}
    case y <> rest:
      shaped_offsets([0,1,2],tags,cells,width,height,grid_width,grid_height,slots,y) || shaped_rows(rest,tags,cells,width,height,grid_width,grid_height,slots)

def occupied_count(slots:List<&2,Inv.Slot>) -> Nat:
  match slots:
    case Nil{}: 0n
    case Inv.InvEmpty{} <> rest: occupied_count(rest)
    case Inv.InvStack{key,count} <> rest: 1n+occupied_count(rest)

def mask_contains(masks:List<&2,U32>,+wanted:U32) -> Bool:
  match masks:
    case Nil{}: False{}
    case mask <> rest: U32.is_eq(mask,wanted) || mask_contains(rest,wanted)

def add_mask(valid:Bool,+value:U32,+masks:List<&2,U32>) -> List<&2,U32>:
  match valid:
    case False{}: masks
    case True{}: choose(List<&2,U32>,masks,value <> masks,mask_contains(masks,value))

# All possible injective assignments survive until the next ingredient. A
# greedy first-match is incorrect when ingredient alternatives overlap.
def expand_slots(slots:List<&2,Inv.Slot>,+tags:List<&2,Tag>,+ingredient:Ingredient,+mask:U32,+bit:U32,masks:List<&2,U32>) -> List<&2,U32>:
  match slots:
    case Nil{}: masks
    case slot <> rest:
      expand_slots(rest,tags,ingredient,mask,U32.mul(bit,2),add_mask(U32.is_zero(U32.and(mask,bit)) && ingredient_matches(ingredient,tags,slot),U32.or(mask,bit),masks))

def expand_masks(states:List<&2,U32>,+slots:List<&2,Inv.Slot>,+tags:List<&2,Tag>,+ingredient:Ingredient,masks:List<&2,U32>) -> List<&2,U32>:
  match states:
    case Nil{}: masks
    case mask <> rest: expand_masks(rest,slots,tags,ingredient,expand_slots(slots,tags,ingredient,mask,1,masks))

def shapeless_assign(ingredients:List<&2,Ingredient>,+slots:List<&2,Inv.Slot>,+tags:List<&2,Tag>,states:List<&2,U32>) -> Bool:
  match ingredients states:
    case _ Nil{}: False{}
    case Nil{} head <> rest: True{}
    case ingredient <> remaining _: shapeless_assign(remaining,slots,tags,expand_masks(states,slots,tags,ingredient,[]))

def matches(recipe:Recipe,tags:List<&2,Tag>,grid:Grid) -> Bool:
  match recipe:
    case Shaped{id,+width,+height,+cells,output}:
      Grid{grid_width,grid_height,slots} = grid
      dimensions(width,height) && Nat.is_eq(List.length(&2,Ingredient,cells),U32.to_nat(U32.mul(width,height))) &&
        shaped_rows([0,1,2],tags,cells,width,height,grid_width,grid_height,slots)
    case Shapeless{id,+ingredients,output}:
      Grid{width,height,+slots} = grid
      Nat.is_gt(List.length(&2,Ingredient,ingredients),0n) && Nat.is_eq(List.length(&2,Ingredient,ingredients),occupied_count(slots)) &&
        shapeless_assign(ingredients,slots,tags,[0])
    case Unsupported{id,kind}: False{}

def remainder_known(item:Maybe<&2,ItemDefinition>) -> Inv.Slot:
  match item:
    case None{}: Inv.InvEmpty{}
    case Some{ItemDefinition{id,limit,remainder}}: remainder

def consumption(slots:List<&2,Inv.Slot>,+items:List<&2,ItemDefinition>,+index:U32) -> List<&2,Consumption>:
  match slots:
    case Nil{}: []
    case Inv.InvEmpty{} <> rest: consumption(rest,items,U32.add(index,1))
    case Inv.InvStack{Inv.ItemKey{id,components},count} <> rest:
      Consumption{index,1,remainder_known(item_definition(items,id))} <> consumption(rest,items,U32.add(index,1))

def create_output_checked(valid:Bool,output:Inv.Slot) -> Inv.Slot:
  match valid:
    case False{}: Inv.InvEmpty{}
    case True{}: output

# ItemStackTemplate.create validates its declared template before returning a
# stack. A codec-admitted1..99 count can still exceed the default item limit.
def create_output(+output:Inv.Slot,items:List<&2,ItemDefinition>) -> Inv.Slot:
  create_output_checked(slot_valid(items,output),output)

def plan(recipe:Recipe,+items:List<&2,ItemDefinition>,grid:Grid) -> Maybe<&2,Plan>:
  match recipe:
    case Shaped{id,width,height,cells,output}:
      Grid{grid_width,grid_height,+slots} = grid
      Some{Plan{id,create_output(output,items),Grid{grid_width,grid_height,slots},consumption(slots,items,0)}}
    case Shapeless{id,ingredients,output}:
      Grid{width,height,+slots} = grid
      Some{Plan{id,create_output(output,items),Grid{width,height,slots},consumption(slots,items,0)}}
    case Unsupported{id,kind}: None{}

def plan_matched(valid:Bool,recipe:Recipe,items:List<&2,ItemDefinition>,grid:Grid) -> Maybe<&2,Plan>:
  match valid:
    case False{}: None{}
    case True{}: plan(recipe,items,grid)

# Preserve supplied registry order. The catalog loader, rather than this
# matcher, decides resource-pack replacement/order and enabled recipe entries.
def find_recipes(recipes:List<&2,Recipe>,+tags:List<&2,Tag>,+items:List<&2,ItemDefinition>,+grid:Grid,selected:Maybe<&2,Plan>) -> Maybe<&2,Plan>:
  match recipes selected:
    case _ Some{value}: Some{value}
    case Nil{} None{}: None{}
    case +recipe <> rest None{}:
      find_recipes(rest,tags,items,grid,plan_matched(matches(recipe,tags,grid),recipe,items,grid))

def find_checked(valid:Bool,catalog:Catalog,grid:Grid) -> Result<&2,&2,String,Maybe<&2,Plan>>:
  match valid:
    case False{}: Fail{"invalid crafting grid: dimensions, slot count, item definition or components"}
    case True{}:
      Catalog{recipes,tags,items} = catalog
      Done{find_recipes(recipes,tags,items,grid,None{})}

def find(+catalog:Catalog,+grid:Grid) -> Result<&2,&2,String,Maybe<&2,Plan>>:
  Catalog{recipes,tags,items} = catalog
  find_checked(grid_valid(items,grid),catalog,grid)

def output(value:Plan) -> Inv.Slot:
  Plan{id,output,before,consumption} = value
  output

def snapshot_equal(a:List<&2,Inv.Slot>,b:List<&2,Inv.Slot>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Inv.InvEmpty{} <> rest Inv.InvEmpty{} <> tail: snapshot_equal(rest,tail)
    case Inv.InvStack{key,count} <> rest Inv.InvStack{other,amount} <> tail:
      Inv.key_equal(key,other) && U32.is_eq(count,amount) && snapshot_equal(rest,tail)
    case _ _: False{}

def current(value:Plan,grid:Grid) -> Bool:
  Plan{id,output,Grid{width,height,before},consumption} = value
  Grid{other_width,other_height,slots} = grid
  U32.is_eq(width,other_width) && U32.is_eq(height,other_height) && snapshot_equal(before,slots)

def unit_consumption(steps:List<&2,Consumption>) -> Bool:
  match steps:
    case Nil{}: True{}
    case Consumption{index,count,remainder} <> rest: U32.is_eq(count,1) && unit_consumption(rest)
